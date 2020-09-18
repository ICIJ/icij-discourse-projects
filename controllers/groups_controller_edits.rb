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
  
  prepend ExtendGroupsController
end
