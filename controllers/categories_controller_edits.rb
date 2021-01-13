module CategoriesControllerExtension
  private

  def verify_permissions
    if params[:permissions].nil?
      return render json: { errors: ['Please assign a project to this group.'] }, status: 400
    end

    icij_groups = Group.visible_icij_groups(current_user).pluck(:name)
    has_permission = icij_groups.any? { |group| (params[:permissions].keys).include? group.downcase }

    unless has_permission
      return render json: { errors: ['You are not a member of this project.'] }, status: 403
    end
  end
end

class ::CategoriesController
  before_action :verify_permissions, only: [:create, :update]

  prepend CategoriesControllerExtension
end
