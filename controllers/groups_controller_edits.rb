module ExtendGroupsController
  def search
    groups = Group.visible_icij_groups(current_user)
      .order(:name)

    if (term = params[:term]).present?
      groups = groups.where("name ILIKE :term OR full_name ILIKE :term", term: "%#{term}%")
    end

    if params[:ignore_automatic].to_s == "true"
      groups = groups.where(automatic: false)
    end

    if Group.preloaded_custom_field_names.present?
      Group.preload_custom_fields(groups, Group.preloaded_custom_field_names)
    end

    render_serialized(groups, BasicGroupSerializer)
  end

  def index
    type_filters_icij = {
      my: Proc.new { |groups, user|
        raise Discourse::NotFound unless user
        Group.member_of(groups, user)
      },
      owner: Proc.new { |groups, user|
        raise Discourse::NotFound unless user
        Group.owner_of(groups, user)
      },
      public: Proc.new { |groups|
        groups.where(public_admission: true, automatic: false)
      },
      close: Proc.new {
        current_user.groups.where(
          public_admission: false,
          automatic: false
        )
      },
      automatic: Proc.new { |groups|
        groups.where(automatic: true)
      }
    }

    unless SiteSetting.enable_group_directory? || current_user&.staff?
      raise Discourse::InvalidAccess.new(:enable_group_directory)
    end

    page_size = 30
    page = params[:page]&.to_i || 0
    order = %w{name user_count}.delete(params[:order])
    dir = params[:asc] ? 'ASC' : 'DESC'
    groups = Group.visible_groups(current_user, order ? "#{order} #{dir}" : nil).visible_icij_groups(current_user)

    if (filter = params[:filter]).present?
      groups = Group.search_groups(filter, groups: groups)
    end

    type_filters = type_filters_icij.keys

    if username = params[:username]
      groups = type_filters_icij[:my].call(groups, User.find_by_username(username))
      type_filters = type_filters - [:my, :owner]
    end

    unless guardian.is_staff?
      # hide automatic groups from all non stuff to de-clutter page
      groups = groups.where("automatic IS FALSE OR groups.id = #{Group::AUTO_GROUPS[:moderators]}")
      type_filters.delete(:automatic)
    end

    if Group.preloaded_custom_field_names.present?
      Group.preload_custom_fields(groups, Group.preloaded_custom_field_names)
    end

    if type = params[:type]&.to_sym
      callback = type_filters_icij[type]
      if !callback
        raise Discourse::InvalidParameters.new(:type)
      end
      groups = callback.call(groups, current_user)
    end

    if current_user
      group_users = GroupUser.where(group: groups, user: current_user)
      user_group_ids = group_users.pluck(:group_id)
      owner_group_ids = group_users.where(owner: true).pluck(:group_id)
    else
      type_filters = type_filters - [:my, :owner]
    end

    count = groups.count
    groups = groups.offset(page * page_size).limit(page_size)

    render_json_dump(
      groups: serialize_data(groups,
        BasicGroupSerializer,
        user_group_ids: user_group_ids || [],
        owner_group_ids: owner_group_ids || []
      ),
      extras: {
        type_filters: type_filters
      },
      total_rows_groups: count,
      load_more_groups: groups_path(
        page: page + 1,
        type: type,
        order: order,
        asc: params[:asc],
        filter: filter
      ),
    )
  end

  def show
    respond_to do |format|
      group = find_group(:id)

      format.html do
        @title = group.full_name.present? ? group.full_name.capitalize : group.name
        @description_meta = group.bio_cooked.present? ? PrettyText.excerpt(group.bio_cooked, 300) : @title
        render :show
      end

      draft_key = Draft::NEW_TOPIC
      draft_sequence = DraftSequence.current(current_user, draft_key)
      draft = Draft.get(current_user, draft_key, draft_sequence) if current_user

      format.json do
        groups = Group.visible_groups(current_user)
        icij_groups = Group.visible_icij_groups(current_user)

        if !guardian.is_staff?
          groups = groups.where(automatic: false)
        end

        render_json_dump(
          group: serialize_data(group, GroupShowSerializer, root: nil),
          draft_key: draft_key,
          draft_sequence: draft_sequence,
          draft: draft,
          extras: {
            visible_group_names: groups.pluck(:name),
            icij_group_names: icij_groups.pluck(:name)
          }
        )
      end
    end
  end

  def members
    group = find_group(:group_id)

    guardian.ensure_can_see_group_members!(group)

    limit = (params[:limit] || 50).to_i
    offset = params[:offset].to_i

    raise Discourse::InvalidParameters.new(:limit) if limit < 0 || limit > 1000
    raise Discourse::InvalidParameters.new(:offset) if offset < 0

    dir = (params[:desc] && params[:desc].present?) ? 'DESC' : 'ASC'
    order = ""

    if params[:requesters]
      guardian.ensure_can_edit!(group)

      users = group.requesters
      total = users.count

      if (filter = params[:filter]).present?
        filter = filter.split(',') if filter.include?(',')

        if current_user&.admin
          users = users.filter_by_username_or_email(filter)
        else
          users = users.filter_by_username(filter)
        end
      end

      users = users
        .select("users.*, group_requests.reason, group_requests.created_at requested_at")
        .order(params[:order] == 'requested_at' ? "group_requests.created_at #{dir}" : "")
        .order(username_lower: dir)
        .limit(limit)
        .offset(offset)

      return render json: {
        members: serialize_data(users, GroupRequesterSerializer),
        meta: {
          total: total,
          limit: limit,
          offset: offset
        }
      }
    end

    if params[:order] && %w{last_posted_at last_seen_at}.include?(params[:order])
      order = "#{params[:order]} #{dir} NULLS LAST"
    elsif params[:order] == 'added_at'
      order = "group_users.created_at #{dir}"
    elsif params[:order] == 'country'
      order = "country #{dir}"
    end

    users = group.users.human_users
    total = users.count

    if (filter = params[:filter]).present?
      filter = filter.split(',') if filter.include?(',')

      users = users.filter_by_username_or_email_or_country(filter, current_user)
    end

    users = users.joins(:user_option).select('users.*, user_options.timezone, group_users.created_at as added_at')

    members = users
      .order('NOT group_users.owner')
      .order(order)
      .order(username_lower: dir)
      .limit(limit)
      .offset(offset)
      .includes(:primary_group)

    owners = users
      .order(order)
      .order(username_lower: dir)
      .where('group_users.owner')
      .includes(:primary_group)

    render json: {
      members: serialize_data(members, GroupUserSerializer),
      owners: serialize_data(owners, GroupUserSerializer),
      meta: {
        total: total,
        limit: limit,
        offset: offset
      }
    }
  end
end

class ::GroupsController
  def categories
    group = find_group(:group_id)

    category_options = {
      group_name: group.name,
      include_topics: false
    }

    ids_to_exclude = Category.where.not(id: group.categories.pluck(:id)).pluck(:id)

    topic_options = {
      per_page: SiteSetting.categories_topics,
      no_definitions: true,
      exclude_category_ids: ids_to_exclude
    }

    result = CategoryAndTopicLists.new
    result.category_list = CategoryList.new(guardian, category_options)
    result.topic_list = TopicQuery.new(current_user, topic_options).list_latest

    draft_key = Draft::NEW_TOPIC
    draft_sequence = DraftSequence.current(current_user, draft_key)
    draft = Draft.get(current_user, draft_key, draft_sequence) if current_user

    %w{category topic}.each do |type|
      result.send(:"#{type}_list").draft = draft
      result.send(:"#{type}_list").draft_key = draft_key
      result.send(:"#{type}_list").draft_sequence = draft_sequence
    end

    render_json_dump(
      lists: serialize_data(result, CategoryAndTopicListsSerializer, root: false)
    )
  end

  def watching
    group = find_group(:group_id)

    ids_to_exclude = Category.where.not(id: group.categories.pluck(:id)).pluck(:id)

    topic_options = {
      per_page: SiteSetting.categories_topics,
      no_definitions: true,
      exclude_category_ids: ids_to_exclude,
      watching: true
    }

    result = TopicQuery.new(current_user, topic_options).list_latest

    draft_key = Draft::NEW_TOPIC
    draft_sequence = DraftSequence.current(current_user, draft_key)
    draft = Draft.get(current_user, draft_key, draft_sequence) if current_user

    result.draft = draft
    result.draft_key = draft_key
    result.draft_sequence = draft_sequence

    render_json_dump(
      lists: serialize_data(result, TopicListSerializer, root: false)
    )
  end

  prepend ExtendGroupsController
end
