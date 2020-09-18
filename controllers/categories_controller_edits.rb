module ExtendCategoriesController
  def create
    guardian.ensure_can_create!(Category)
    position = category_params.delete(:position)

    @category =
      begin
        Category.new(category_params.merge(user: current_user))
      rescue ArgumentError => e
        return render json: { errors: [e.message] }, status: 422
      end

    if params[:permissions].nil?
      @category.errors[:base] << "Please assign a project to this group."
      return render_json_error(@category)
    end

    icij_groups = Group.visible_icij_groups(current_user).pluck(:name)
    has_permission = icij_groups.any? { |group| (params[:permissions].keys).include? group }

    unless has_permission
      @category.errors[:base] << "You are not a member of this project."
      return render_json_error(@category)
    end

    if @category.save
      @category.move_to(position.to_i) if position

      Scheduler::Defer.later "Log staff action create category" do
        @staff_action_logger.log_category_creation(@category)
      end

      render_serialized(@category, CategorySerializer)
    else
      return render_json_error(@category) unless @category.save
    end
  end
end

class ::CategoriesController
  prepend ExtendCategoriesController
end
