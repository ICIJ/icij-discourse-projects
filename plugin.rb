# name: icij-projects
# about: A plugin for using groups to separate and organize categories and topics.
# version: 0.0.1
# authors: Madeline O'Leary

after_initialize do

  require_dependency "app/models/topic_list"
  class ::TopicList
    attr_accessor :icij_group_names

    def icij_group_names
      if @current_user.nil?
        icij_group_names = []
        icij_group_names
      else
        guardian = Guardian.new(@current_user)
        group_users = GroupUser.where(user_id: guardian.user.id)
        group_ids = group_users.pluck(:group_id).uniq

        icij_group_names = Group.icij_groups.where(id: group_ids).pluck(:name)

        icij_group_names
      end
    end
  end

  require_dependency "app/models/category_list"
  class ::CategoryList
    attr_accessor :icij_group_names

    def icij_group_names
      if @guardian.current_user.nil?
        icij_group_names = []
        icij_group_names
      else
        group_users = GroupUser.where(user_id: @guardian.current_user.id)
        group_ids = group_users.pluck(:group_id).uniq

        icij_group_names = Group.icij_groups.where(id: group_ids).pluck(:name)

        icij_group_names
      end
    end

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

  require_dependency "category_list_serializer"
  class ::CategoryListSerializer
    attributes :icij_group_names
  end

  require_dependency "topic_list_serializer"
  class ::TopicListSerializer
    attributes :icij_group_names
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

  require_dependency "app/controllers/application_controller"
    GroupsController.class_eval do
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
