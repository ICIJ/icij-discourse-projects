DirectoryItemsController.class_eval do
  PAGE_SIZE = 50

  def index
    raise Discourse::InvalidAccess.new(:enable_user_directory) unless SiteSetting.enable_user_directory?

    period_type = 5
    raise Discourse::InvalidAccess.new(:period_type) unless period_type

    if current_user
      groups = current_user.groups.where(icij_group: true).pluck(:group_id)
      users = GroupUser.where(group_id: groups).pluck(:user_id).uniq
      result = DirectoryItem.where(period_type: period_type).includes(:user).where(user_id: users)
    else
      result = DirectoryItem.where(period_type: period_type).includes(:user)
    end

    if params[:group]
      result = result.includes(user: :groups).where(users: { groups: { name: params[:group] } })
    end

    if params[:exclude_usernames]
      result = result.references(:user).where.not(users: { username: params[:exclude_usernames].split(",") })
    end

    order = params[:order] || DirectoryItem.headings.first
    if DirectoryItem.headings.include?(order.to_sym)
      dir = params[:asc] ? 'ASC' : 'DESC'
      result = result.order("directory_items.#{order} #{dir}")
    end

    if period_type == DirectoryItem.period_types[:all]
      result = result.includes(:user_stat)
    end
    page = params[:page].to_i

    user_ids = nil
    if params[:name].present?
      user_ids = UserSearch.new(params[:name], include_staged_users: true).search.pluck(:id)
      if user_ids.present?
        # Add the current user if we have at least one other match
        # if current_user && result.dup.where(user_id: user_ids).exists?
        #   user_ids << current_user.id
        # end
        result = result.where(user_id: user_ids)
      else
        result = result.where('false')
      end
    end

    if params[:username]
      user_id = User.where(username_lower: params[:username].to_s.downcase).pluck(:id).first
      if user_id
        result = result.where(user_id: user_id)
      else
        result = result.where('false')
      end
    end

    result_count = result.count
    result = result.limit(PAGE_SIZE).offset(PAGE_SIZE * page).to_a

    more_params = params.slice(:period, :order, :asc).permit!
    more_params[:page] = page + 1

    # Put yourself at the top of the first page
    if result.present? && current_user.present? && page == 0

      position = result.index { |r| r.user_id == current_user.id }

      # Don't show the record unless you're not in the top positions already
      if (position || 10) >= 10
        your_item = DirectoryItem.where(period_type: period_type, user_id: current_user.id).first
        result.insert(0, your_item) if your_item
      end

    end

    render_json_dump(directory_items: serialize_data(result, DirectoryItemSerializer),
                     total_rows_directory_items: result_count,
                     load_more_directory_items: directory_items_path(more_params))
  end
end
