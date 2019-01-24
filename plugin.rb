# name: icij-projects
# about: A plugin for using groups to separate and organize categories and topics.
# version: 0.0.1
# authors: Madeline O'Leary

register_asset 'stylesheets/common/select-kit/category-chooser'

after_initialize do

  require_dependency "category_list"
  class ::CategoryList
    def find_group(group_name, ensure_can_see: true)
      group = Group
      group = group.find_by("lower(name) = ?", group_name.downcase)
      @guardian.ensure_can_see!(group) if ensure_can_see
      group
    end

    def find_categories
      @categories = Category.includes(
        :uploaded_background,
        :uploaded_logo,
        :topic_only_relative_url,
        subcategories: [:topic_only_relative_url]
      ).secured(@guardian)

      @categories = @categories.where("categories.parent_category_id = ?", @options[:parent_category_id].to_i) if @options[:parent_category_id].present?

      if @options[:group_name].present?
        group = find_group(@options[:group_name])
        @categories = group.categories.all
      end

      if SiteSetting.fixed_category_positions
        @categories = @categories.order(:position, :id)
      else
        @categories = @categories.order('COALESCE(categories.posts_week, 0) DESC')
          .order('COALESCE(categories.posts_month, 0) DESC')
          .order('COALESCE(categories.posts_year, 0) DESC')
          .order('id ASC')
      end

      @categories = @categories.to_a

      category_user = {}
      default_notification_level = nil
      unless @guardian.anonymous?
        category_user = Hash[*CategoryUser.where(user: @guardian.user).pluck(:category_id, :notification_level).flatten]
        default_notification_level = CategoryUser.notification_levels[:regular]
      end

      allowed_topic_create = Set.new(Category.topic_create_allowed(@guardian).pluck(:id))
      @categories.each do |category|
        category.notification_level = category_user[category.id] || default_notification_level
        category.permission = CategoryGroup.permission_types[:full] if allowed_topic_create.include?(category.id)
        category.has_children = category.subcategories.present?
      end

      if @options[:parent_category_id].blank?
        subcategories = {}
        to_delete = Set.new
        @categories.each do |c|
          if c.parent_category_id.present?
            subcategories[c.parent_category_id] ||= []
            subcategories[c.parent_category_id] << c.id
            to_delete << c
          end
        end
        @categories.each { |c| c.subcategory_ids = subcategories[c.id] }
        @categories.delete_if { |c| to_delete.include?(c) }
      end

      if @topics_by_category_id
        @categories.each do |c|
          topics_in_cat = @topics_by_category_id[c.id]
          if topics_in_cat.present?
            c.displayable_topics = []
            topics_in_cat.each do |topic_id|
              topic = @topics_by_id[topic_id]
              if topic.present? && @guardian.can_see?(topic)
                # topic.category is very slow under rails 4.2
                topic.association(:category).target = c
                c.displayable_topics << topic
              end
            end
          end
        end
      end
    end
  end

  require_dependency "app/models/concerns/has_custom_fields"
  require_dependency "app/models/concerns/anon_cache_invalidator"
  require_dependency "lib/validators/url_validator"
  require_dependency "app/models/group"
  class ::Group < ::ActiveRecord::Base
    scope :icij_groups_get, Proc.new { |user|
      group_users = GroupUser.where(user_id: user.id)
      group_ids = group_users.pluck(:group_id).uniq
      icij_groups = Group.icij_groups.where(id: group_ids)
      icij_groups
    }

    scope :icij_groups, -> { where(icij_group: true) }
  end

  require_dependency "lib/search"
  class ::Search
    def icij_group_members(user)
      if user.admin?
        user_ids = User.all.pluck(:id)
        user_ids
      else
        group_ids = user.groups.where(icij_group: true).pluck(:id) + [0]
        user_ids = GroupUser.where(group_id: group_ids).pluck(:user_id).uniq
        user_ids
      end
    end

    def posts_query(limit, opts = nil)
      user_ids = icij_group_members(@guardian.current_user)
      opts ||= {}
      posts = Post.where(user_id: user_ids)
        .where(post_type: Topic.visible_post_types(@guardian.user))
        .joins(:post_search_data, :topic)
        .joins("LEFT JOIN categories ON categories.id = topics.category_id")
        .where("topics.deleted_at" => nil)

      is_topic_search = @search_context.present? && @search_context.is_a?(Topic)

      posts = posts.where("topics.visible") unless is_topic_search

      if opts[:private_messages] || (is_topic_search && @search_context.private_message?)
        posts = posts.where("topics.archetype =  ?", Archetype.private_message)

         unless @guardian.is_admin?
           posts = posts.private_posts_for_user(@guardian.user)
         end
      else
        posts = posts.where("topics.archetype <> ?", Archetype.private_message)
      end

      if @term.present?
        if is_topic_search

          term_without_quote = @term
          if @term =~ /"(.+)"/
            term_without_quote = $1
          end

          if @term =~ /'(.+)'/
            term_without_quote = $1
          end

          posts = posts.joins('JOIN users u ON u.id = posts.user_id')
          posts = posts.where("posts.raw  || ' ' || u.username || ' ' || COALESCE(u.name, '') ilike ?", "%#{term_without_quote}%")
        else
          # A is for title
          # B is for category
          # C is for tags
          # D is for cooked
          weights = @in_title ? 'A' : (SiteSetting.tagging_enabled ? 'ABCD' : 'ABD')
          posts = posts.where("post_search_data.search_data @@ #{ts_query(weight_filter: weights)}")
          exact_terms = @term.scan(/"([^"]+)"/).flatten
          exact_terms.each do |exact|
            posts = posts.where("posts.raw ilike :exact OR topics.title ilike :exact", exact: "%#{exact}%")
          end
        end
      end

      @filters.each do |block, match|
        if block.arity == 1
          posts = instance_exec(posts, &block) || posts
        else
          posts = instance_exec(posts, match, &block) || posts
        end
      end if @filters

      # If we have a search context, prioritize those posts first
      if @search_context.present?

        if @search_context.is_a?(User)

          if opts[:private_messages]
            posts = posts.private_posts_for_user(@search_context)
          else
            posts = posts.where("posts.user_id = #{@search_context.id}")
          end

        elsif @search_context.is_a?(Category)
          category_ids = [@search_context.id] + Category.where(parent_category_id: @search_context.id).pluck(:id)
          posts = posts.where("topics.category_id in (?)", category_ids)
        elsif @search_context.is_a?(Topic)
          posts = posts.where("topics.id = #{@search_context.id}")
            .order("posts.post_number #{@order == :latest ? "DESC" : ""}")
        end

      end

      if @order == :latest || (@term.blank? && !@order)
        if opts[:aggregate_search]
          posts = posts.order("MAX(posts.created_at) DESC")
        else
          posts = posts.reorder("posts.created_at DESC")
        end
      elsif @order == :latest_topic
        if opts[:aggregate_search]
          posts = posts.order("MAX(topics.created_at) DESC")
        else
          posts = posts.order("topics.created_at DESC")
        end
      elsif @order == :views
        if opts[:aggregate_search]
          posts = posts.order("MAX(topics.views) DESC")
        else
          posts = posts.order("topics.views DESC")
        end
      elsif @order == :likes
        if opts[:aggregate_search]
          posts = posts.order("MAX(posts.like_count) DESC")
        else
          posts = posts.order("posts.like_count DESC")
        end
      else
        data_ranking = "TS_RANK_CD(post_search_data.search_data, #{ts_query})"
        if opts[:aggregate_search]
          posts = posts.order("MAX(#{data_ranking}) DESC")
        else
          posts = posts.order("#{data_ranking} DESC")
        end
        posts = posts.order("topics.bumped_at DESC")
      end

      if secure_category_ids.present?
        posts = posts.where("(categories.id IS NULL) OR (NOT categories.read_restricted) OR (categories.id IN (?))", secure_category_ids).references(:categories)
      else
        posts = posts.where("(categories.id IS NULL) OR (NOT categories.read_restricted)").references(:categories)
      end

      posts = posts.offset(offset)
      posts.limit(limit)
    end
  end

  require_dependency "site"
  class ::Site
    def icij_group_names
      if @guardian.current_user.nil?
        icij_group_names = []
        icij_group_names
      else
        group_users = GroupUser.where(user_id: @guardian.current_user.id)
        group_ids = group_users.pluck(:group_id).uniq

        icij_group_names = Group.where(icij_group: true).where(id: group_ids).pluck(:name)

        icij_group_names
      end
    end

    def icij_projects
      if @guardian.current_user.nil?
        icij_projects = []
        icij_projects
      else
        group_users = GroupUser.where(user_id: @guardian.current_user.id)
        group_ids = group_users.pluck(:group_id).uniq

        icij_projects = Group.where(icij_group: true).where(id: group_ids)

        icij_projects
      end
    end

    def available_icij_groups
      if @guardian.current_user.nil?
        icij_group_objects = []
        icij_group_objects
      else
        group_users = GroupUser.where(user_id: @guardian.current_user.id)
        group_ids = group_users.pluck(:group_id).uniq

        icij_group_objects = (Group.where(icij_group: true).where(id: group_ids))

        icij_group_objects.pluck(:id, :name).map { |id, name| { id: id, name: name } }.as_json
      end
    end

    def icij_groups_and_everyone
      if @guardian.current_user.nil?
        icij_group_objects = []
        icij_group_objects
      else
        group_users = GroupUser.where(user_id: @guardian.current_user.id)
        group_ids = group_users.pluck(:group_id).uniq

        icij_group_objects = (Group.where(icij_group: true).where(id: group_ids)) + Group.where(id: 0)

        icij_group_objects.pluck(:id, :name).map { |id, name| { id: id, name: name } }.as_json
      end
    end
  end

  require_dependency "site_serializer"
  class ::SiteSerializer
    attributes :icij_group_names,
               :available_icij_groups,
               :icij_groups_and_everyone
  end

  require_dependency "basic_category_serializer"
  class ::BasicCategorySerializer
    attributes :group_names,
               :subcategory_group_names

   def group_names
     if object.category_groups.nil?
       []
     else
       groups = object.category_groups.pluck(:group_id)
       Group.where(id: groups).pluck(:name)
     end
   end

   def subcategory_group_names
     if object.parent_category_id
       parent_category = Category.find(object.parent_category_id)
       groups = parent_category.category_groups.pluck(:group_id)
       Group.where(id: groups).pluck(:name)
     else
       []
     end
   end
  end

  require_dependency "application_controller"
    GroupsController.class_eval do
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
        groups = Group.visible_groups(current_user, order ? "#{order} #{dir}" : nil).icij_groups_get(current_user)
        # groups = groups.icij_groups_get

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

          format.json do
            groups = Group.visible_groups(current_user)
            icij_groups = Group.icij_groups_get(current_user)

            if !guardian.is_staff?
              groups = groups.where(automatic: false)
            end

            render_json_dump(
              group: serialize_data(group, GroupShowSerializer, root: nil),
              extras: {
                visible_group_names: groups.pluck(:name),
                icij_group_names: icij_groups.pluck(:name)
              }
            )
          end
        end
      end

      def categories
        group = find_group(:group_id)
        name = group.name

        category_options = {
          group_name: name,
          include_topics: false
        }

        categories = group.categories.all
        category_ids = categories.pluck(:id)
        ids_to_exclude = Category.where.not(id: category_ids).pluck(:id)

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
          group: serialize_data(group, GroupShowSerializer, root: nil),
          extras: serialize_data(result, CategoryAndTopicListsSerializer, root: false)
        )
      end
    end

    require_dependency 'application_controller'
    Discourse::Application.routes.append do
      resources :groups, id: RouteFormat.username do
        get 'categories'
      end
    end
end
