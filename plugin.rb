# name: icij-projects
# about: A plugin for using groups to separate and organize categories and topics.
# version: 0.0.1
# authors: Madeline O'Leary

register_asset 'stylesheets/common/select-kit/category-chooser.scss'
PLUGIN_NAME = 'icij_discourse_projects'.freeze

after_initialize do

  User.register_custom_field_type("organization", :string)

  module ::IcijDiscourseProjects
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace IcijDiscourseProjects
    end
  end

  add_to_class(:Guardian, :can_send_private_message?) do |target, notify_moderators: false|
    is_user = target.is_a?(User)
    is_group = target.is_a?(Group)

    target_is_project_member = false
    if is_user && !@user.nil?
      project_members = User.members_visible_icij_groups(@user)

      target_is_project_member = project_members.include? target
    end

    target_is_project = false
    if is_group && !@user.nil?
      if is_staff?
        target_is_project = @user.groups.include? target
      else
        target_is_project = @user.groups.where(icij_group: true).include? target
      end
    end

    (is_group || is_user) &&
    # User is authenticated
    authenticated? &&
    # Have to be a basic level at least
    @user.has_trust_level?(SiteSetting.min_trust_to_send_messages) &&
    # The target must be either a fellow project member, or the target must be a project that the user is a member of
    (target.staff? || is_system? || target_is_project_member || target_is_project) &&
    # User disabled private message
    (is_staff? || is_group || target.user_option.allow_private_messages) &&
    # PMs are enabled
    (is_staff? || SiteSetting.enable_personal_messages || notify_moderators) &&
    # Can't send PMs to suspended users
    (is_staff? || is_group || !target.suspended?) &&
    # Check group messageable level
    (is_staff? || is_user || Group.messageable(@user).where(id: target.id).exists?) &&
    # Silenced users can only send PM to staff
    (!is_silenced? || target.staff?)
  end

  ::UserGuardian.module_eval do
    def can_see_profile?(user)
      return false if user.blank?
      return true if is_me?(user)

      group_users = User.members_visible_icij_groups(@user).pluck(:id)

      both_empty = @user.groups.empty? && user.groups.empty?

      if !is_me?(user) && !@user.admin? && both_empty
        return false
      end

      if !@user.admin? && !group_users.include?(user.id)
        return false
      end

      # If a user has hidden their profile, restrict it to them and staff
      if user.user_option.try(:hide_profile_and_presence?)
        return is_me?(user) || is_staff?
      end

      true
    end
  end

  ::CategoryGuardian.module_eval do
    # Creating Method
    def can_create_category?(parent = nil)
      true
    end

    # Editing Method
    def can_edit_category?(category)
      is_admin? || is_moderator? || (category.user_id == @user.id)
    end

    def can_delete_category?(category)
      can_edit_category?(category) &&
      category.topic_count <= 0 &&
      !category.uncategorized? &&
      !category.has_children?
    end
  end

  ::TopicGuardian.module_eval do
    # Editing Method
    def can_edit_topic?(topic)
      return false if Discourse.static_doc_topic_ids.include?(topic.id) && !is_admin?
      return false unless can_see?(topic)

      return true if is_admin?
      return true if is_moderator? && can_create_post?(topic)

      # can't edit topics in secured categories where you don't have permission to create topics
      # except for a tiny edge case where the topic is uncategorized and you are trying
      # to fix it but uncategorized is disabled
      if (
        SiteSetting.allow_uncategorized_topics ||
        topic.category_id != SiteSetting.uncategorized_category_id
      )
        return false if !can_create_topic_on_category?(topic.category)
      end

      # TL4 users can edit archived topics, but can not edit private messages
      return true if (
        SiteSetting.trusted_users_can_edit_others? &&
        topic.archived &&
        !topic.private_message? &&
        user.has_trust_level?(TrustLevel[4]) &&
        can_create_post?(topic)
      )

      # TL3 users can not edit archived topics and private messages
      return true if (
        SiteSetting.trusted_users_can_edit_others? &&
        !topic.archived &&
        !topic.private_message? &&
        user.has_trust_level?(TrustLevel[3]) &&
        can_create_post?(topic)
      )

      return false if topic.archived
      is_my_own?(topic)
    end

    def can_delete_topic?(topic)
      !topic.trashed? &&
      (is_staff? || is_my_own?(topic)) &&
      !(topic.is_category_topic?) &&
      !Discourse.static_doc_topic_ids.include?(topic.id)
    end
  end

  add_to_class(:User, :organization_name) do
    self.custom_fields["organization"]
  end

  add_to_class(:User, :added_at) do
    ""
  end

  add_class_method(:User, :members_visible_icij_groups) do |user|
    if user.nil?
      []
    else
      users = self.human_users

      sql = <<~SQL
        users.id IN (
          SELECT gu.user_id
          FROM group_users gu
          WHERE gu.group_id in (
            SELECT g.id
            FROM groups g
            JOIN group_users gu ON gu.group_id = g.id AND gu.user_id = :user_id
            WHERE gu.user_id = :user_id
            AND  g.icij_group = true
           )
        )
        SQL

      params = { user_id: user&.id }

      users = self.where(sql, params)
      users
    end
  end

  module UserExtension
    class ::User
      scope :filter_by_username_or_email_or_country, ->(filter, current_user) do
        if filter =~ /.+@.+/
          # probably an email so try the bypass
          if user_id = UserEmail.where("lower(email) = ?", filter.downcase).pluck(:user_id).first
            return where('users.id = ?', user_id)
          end
        end

        user_ids = User.members_visible_icij_groups(current_user).pluck(:id)

        users = joins(:primary_email)

        if filter.is_a?(Array)
          users.where(
            'username_lower ~* :filter OR lower(user_emails.email) SIMILAR TO :filter',
            filter: "(#{filter.join('|')})"
          ).where(id: user_ids)
        else
          users.where(
            'username_lower ILIKE :filter OR lower(user_emails.email) ILIKE :filter OR lower(country) ILIKE :filter',
            filter: "%#{filter}%"
          ).where(id: user_ids)
        end
      end
    end
  end

  class ::User
    prepend UserExtension
  end

  add_to_serializer(:current_user, :current_user_icij_projects) { Group.visible_icij_groups(object).pluck(:id, :name).map { |id, name| { id: id, name: name } } }
  add_to_serializer(:current_user, :fellow_icij_project_members) { User.members_visible_icij_groups(object).pluck(:id) }
  add_to_serializer(:current_user, :icij_project_categories) { Category.visible_icij_groups_categories(object).pluck(:id) }

  add_to_class(:UserSearch, :initialize) do |term, opts = {}|
    @term = term
    @term_like = "#{term.downcase.gsub("_", "\\_")}%"
    @topic_id = opts[:topic_id]
    @topic_allowed_users = opts[:topic_allowed_users]
    @searching_user = opts[:searching_user]
    @include_staged_users = opts[:include_staged_users] || false
    @limit = opts[:limit] || 20
    @group = opts[:group]
    @guardian = Guardian.new(@searching_user)
    @guardian.ensure_can_see_group!(@group) if @group
  end

  add_to_class(:UserSearch, :scoped_users) do
    users = User.where(active: true)
    users = users.where(staged: false) unless @include_staged_users

    if @group
      users = users.where('users.id IN (
        SELECT user_id FROM group_users WHERE group_id = ?
      )', @group.id)
    end

    unless @searching_user && @searching_user.staff?
      users = users.not_suspended
    end

    # Only show users who have access to private topic
    if @topic_id && @topic_allowed_users == "true"
      topic = Topic.find_by(id: @topic_id)

      if topic.category && topic.category.read_restricted
        users = users.includes(:secure_categories)
          .where("users.admin = TRUE OR categories.id = ?", topic.category.id)
          .references(:categories)
      end
    end

    users.limit(@limit)
  end

  add_to_class(:UserSearch, :filtered_by_term_users) do
    users = scoped_users

    if @term.present?
      if SiteSetting.enable_names? && @term !~ /[_\.-]/
        # query = Search.ts_query(term: @term, ts_config: "simple")

        # why are they using this? the vector seems to take more time (did very rudimentary benchmark test)...maybe with thousands of users to search it starts to be faster? really not sure
        # users = users.includes(:user_search_data)
          # .references(:user_search_data)
          # .where("user_search_data.search_data @@ #{query}")
          # .order(DB.sql_fragment("CASE WHEN country LIKE ? THEN 0 ELSE 1 END ASC", @term_like, @term_like))

          users = users.includes(:_custom_fields).references(:_custom_fields).where("users.username_lower ILIKE :term_like OR users.country ILIKE :term_like OR user_custom_fields.value ILIKE :term_like OR LOWER(users.name) ILIKE :term_like", term_like: @term_like)
      else
        users = users.where("username_lower LIKE :term_like OR country LIKE :term_like", term_like: @term_like)
      end
    end
    users
  end

  add_to_class(:UserSearch, :search_ids) do
    users = Set.new

    # 1. exact username matches
    if @term.present?
      scoped_users.where(username_lower: @term.downcase)
        .limit(@limit)
        .pluck(:id)
        .each { |id| users << id }

    end

    return users.to_a if users.length >= @limit

    # 2. in topic
    if @topic_id
      filtered_by_term_users.where('users.id IN (SELECT p.user_id FROM posts p WHERE topic_id = ?)', @topic_id)
        .order('last_seen_at DESC')
        .limit(@limit - users.length)
        .pluck(:id)
        .each { |id| users << id }
    end

    return users.to_a if users.length >= @limit

    # 3. global matches
    filtered_by_term_users.order('last_seen_at DESC')
      .limit(@limit - users.length)
      .pluck(:id)
      .each { |id| users << id }

    users.to_a
  end

  add_to_class(:UserSearch, :search) do
    ids = search_ids
    return User.where("0=1") if ids.empty?

    User.joins("JOIN (SELECT unnest uid, row_number() OVER () AS rn
      FROM unnest('{#{ids.join(",")}}'::int[])
    ) x on uid = users.id")
      .order("rn")
  end

  add_to_class(:Search, :find_grouped_results) do
    if @results.type_filter.present?
      raise Discourse::InvalidAccess.new("invalid type filter") unless Search.facets.include?(@results.type_filter)
      send("#{@results.type_filter}_search")
    else
      unless @search_context
        user_search if @term.present?
        user_country_search if @term.present?
        category_search if @term.present?
        tags_search if @term.present?
      end
      topic_search
    end

    add_more_topics_if_expected
    @results
  rescue ActiveRecord::StatementInvalid
      # In the event of a PG:Error return nothing, it is likely they used a foreign language whose
      # locale is not supported by postgres
  end

  class ::Search
    private

    def user_country_search
      return if SiteSetting.hide_user_profiles_from_public && !@guardian.user

      users = User.includes(:user_search_data)
        .references(:user_search_data)
        .where(active: true)
        .where(staged: false)
        .where("country ILIKE ?", "%#{@original_term}%")

      users.each do |user|
        @results.add(user)
      end
    end
  end

  add_to_serializer(:basic_user, :country) do
    user.country
  rescue
    user.try(:country)
  end

  add_to_serializer(:admin_user_list, :country) do
    user.country
  rescue
    user.try(:country)
  end

  add_to_serializer(:search_result_user, :country) do
    user.country
  rescue
    user.try(:country)
  end

  add_to_serializer(:user, :country) { object.country }
  add_to_serializer(:user, :organization_name) { object.organization_name }

  add_to_serializer(:directory_item, :country) { object.user.country }
  add_to_serializer(:directory_item, :organization_name) { object.user.organization_name }

  add_to_serializer(:directory_item, :user_created_at_age) do
    Time.now - object.user.created_at
  rescue
    nil
  end

  add_to_serializer(:directory_item, :user_last_seen_age) do
    return nil if object.user.last_seen_at.blank?
    Time.now - object.user.last_seen_at
  rescue
    nil
  end

  add_to_class(:CategoryList, :find_group) do |group_name, ensure_can_see: true|
    group = Group
    group = group.find_by("lower(name) = ?", group_name.downcase)
    @guardian.ensure_can_see!(group) if ensure_can_see
    group
  end

  add_to_class(:CategoryList, :find_categories) do
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
      @categories = @categories.order('name ASC')
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

  module ExtendGroupInstance
    def posts_for(guardian, opts = nil)
      category_ids = categories.pluck(:id)
      topic_ids = Topic.where(category_id: category_ids).pluck(:id)

      result = super(guardian, opts = nil)
      result.where(topic_id: topic_ids)
    end
  end

  class ::Group
    prepend ExtendGroupInstance
  end

  add_class_method(:Group, :icij_projects) do
    self.where(icij_group: true)
  end

  add_class_method(:Group, :visible_icij_groups) do |user|
    groups = self.order("name ASC")


    groups = groups.where("groups.id > 0")

    sql = <<~SQL
      groups.id IN (

        SELECT g.id
          FROM groups g
          JOIN group_users gu ON gu.group_id = g.id AND gu.user_id = :user_id
         WHERE gu.user_id = :user_id
          AND  g.icij_group = true

      )
    SQL

    params = { user_id: user&.id }
    groups = groups.where(sql, params)

    groups
  end

  add_to_class(:Search, :user_country_search) do
    return if SiteSetting.hide_user_profiles_from_public && !@guardian.user

    users = User.includes(:user_search_data)
      .references(:user_search_data)
      .where(active: true)
      .where(staged: false)

    if @guardian.current_user
      if !@guardian.is_admin?
        user_ids = User.members_visible_icij_groups(@guardian.current_user).pluck(:id)
        user_ids

        if !user_ids.empty?
          users = users
            .where(id: user_ids)
            .where("country ILIKE ?", "%#{@original_term}%")
            .order("CASE WHEN country = '#{@original_term}' THEN 0 ELSE 1 END")
            .order("last_posted_at DESC")
            .limit(limit)
        else
          users = []
        end
      else
        users = users
          .where("country ILIKE ?", "%#{@original_term}%")
          .order("CASE WHEN country = '#{@original_term}' THEN 0 ELSE 1 END")
          .order("last_posted_at DESC")
          .limit(limit)
      end
      users.each do |user|
        @results.add(user)
      end
    end
  end

  module ExtendSearch
    def execute
      super

      unless !@results.search_context.nil?
        user_country_search if @results.term.present?
      end

      if !@results.users.empty?
        ids = User.members_visible_icij_groups(@guardian.user).pluck(:id)
        @results.users.reject! { |user| !ids.include?(user.id) }
        @results
      else
        @results
      end
    end
  end

  class ::Search
    prepend ExtendSearch

    # an ICIJ customization
    advanced_filter(/^group:(.+)$/) do |posts, match|
      group_id = Group.where('name ilike ? OR (id = ? AND id > 0)', match, match.to_i).pluck_first(:id)
      if group_id
        posts.joins(:topic).where("topics.category_id IN (select cg.category_id from category_groups cg where cg.group_id = ?)", group_id)
      else
        posts.where("1 = 0")
      end
    end
  end

  add_to_class(:Site, :determine_user) do
    if @guardian.nil?
      user = current_user
    elsif @guardian.current_user.nil?
      user = nil
    else
      user = @guardian.current_user
    end
  end

  add_to_class(:Site, :available_icij_projects) do
    user = self.determine_user
    Group.visible_icij_groups(user).pluck(:id, :name).map { |id, name| { id: id, name: name } }.as_json
  end

  add_to_serializer(:site, :available_icij_projects) { object.available_icij_projects }

  add_class_method(:Category, :visible_icij_groups_categories) do |user|
    if user.nil?
      []
    else
      categories = self.all

      sql = <<~SQL
        categories.id IN (
          SELECT cg.category_id
          FROM category_groups cg
          WHERE cg.group_id in (
            SELECT g.id
            FROM groups g
            JOIN group_users gu ON gu.group_id = g.id AND gu.user_id = :user_id
            WHERE gu.user_id = :user_id
            AND  g.icij_group = true
          )
        )
      SQL

      params = { user_id: user&.id }

      categories = self.where(sql, params)
      categories
    end
  end

  add_to_class(:Category, :icij_projects_for_category) do
    if self.category_groups.nil?
      []
    else
      Group.where(id: self.category_groups.pluck(:group_id)).pluck(:name)
    end
  end

  add_to_class(:Category, :icij_project_subcategories_for_category) do
    if self.parent_category_id
      Group.where(id: self.parent_category.category_groups.pluck(:group_id)).pluck(:name)
    else
      []
    end
  end

  add_to_class(:Category, :icij_project_permissions_for_category) do
    perms = self.category_groups.joins(:group).includes(:group).order("groups.name").map do |cg|
        {
          permission_type: cg.permission_type,
          group_name: cg.group.name
        }
    end
    if perms.length == 0 && !self.read_restricted
      perms << { permission_type: CategoryGroup.permission_types[:full], group_name: Group[:everyone]&.name.presence || :everyone }
    end
    perms
  end

  add_to_serializer(:category, :available_groups) do
    user = scope && scope.user
    groups = Group.visible_icij_groups(user).order(:name)
    groups.pluck(:name) - group_permissions.map { |g| g[:group_name] }
  end

  add_to_serializer(:basic_category, :icij_projects_for_category) { object.icij_projects_for_category }
  add_to_serializer(:basic_category, :icij_project_subcategories_for_category) { object.icij_project_subcategories_for_category }
  add_to_serializer(:basic_category, :icij_project_permissions_for_category) { object.icij_project_permissions_for_category }

  add_class_method(:TopicQuery, :public_valid_options) do
    @public_valid_options ||=
      %i(page
         before
         bumped_before
         exclude_category_ids
         topic_ids
         category
         order
         ascending
         min_posts
         max_posts
         status
         filter
         state
         search
         q
         group_name
         tags
         match_all_tags
         no_subcategories
         no_tags)
  end

  module TopicQueryExtension
    def create_list(filter, options = {}, topics = nil)
      list = super
      if !@options[:exclude_category_ids].nil?
        ids = @options[:exclude_category_ids]
        topics = list.topics.select { |topic| !ids.include?(topic.category_id) }
        list = TopicList.new(filter, @user, topics, options.merge(@options))
        list.per_page = options[:per_page] || per_page_setting
        list
      else
        list
      end
    end
  end

  class ::TopicQuery
    prepend TopicQueryExtension
  end

  ListController.class_eval do
    private

    def generate_list_for(action, target_user, opts)
      action == "group_topics" ? IcijTopicQuery.new(current_user, opts).send("list_icij_group_topics", target_user) : TopicQuery.new(current_user, opts).send("list_#{action}", target_user)
    end
  end

  Discourse::Application.routes.append do
    %w{groups g}.each do |root_path|
      get "g/:group_id/categories" => 'groups#categories', constraints: { group_id: RouteFormat.username }
    end
  end

  [
    "../controllers/categories_controller_edits.rb",
    "../controllers/groups_controller_edits.rb",
    "../controllers/directory_items_controller_edits.rb",
    "../controllers/search_controller_edits.rb",
    "../controllers/users_controller_edits.rb"
  ].each do |path|
    load File.expand_path(path, __FILE__)
  end
end
