UsersController.class_eval do
  HONEYPOT_KEY ||= 'HONEYPOT_KEY'
  CHALLENGE_KEY ||= 'CHALLENGE_KEY'

  def create
    params.require(:email)
    params.require(:username)
    params.permit(:user_fields)

    unless SiteSetting.allow_new_registrations
      return fail_with("login.new_registrations_disabled")
    end

    if params[:password] && params[:password].length > User.max_password_length
      return fail_with("login.password_too_long")
    end

    if params[:email].length > 254 + 1 + 253
      return fail_with("login.email_too_long")
    end

    if clashing_with_existing_route?(params[:username]) || User.reserved_username?(params[:username])
      return fail_with("login.reserved_username")
    end

    params[:locale] ||= I18n.locale unless current_user

    new_user_params = user_params.except(:timezone)
    user = User.unstage(new_user_params)
    # unknown attribute timezone causing problem here
    user = User.new(new_user_params) if user.nil?

    # Handle API approval
    ReviewableUser.set_approved_fields!(user, current_user) if user.approved?

    # Handle custom fields
    user_fields = UserField.all
    if user_fields.present?
      field_params = params[:user_fields] || {}
      fields = user.custom_fields

      user_fields.each do |f|
        field_val = field_params[f.id.to_s]
        if field_val.blank?
          return fail_with("login.missing_user_field") if f.required?
        else
          fields["#{User::USER_FIELD_PREFIX}#{f.id}"] = field_val[0...UserField.max_length]
        end
      end

      user.custom_fields = fields
    end

    authentication = UserAuthenticator.new(user, session)

    if !authentication.has_authenticator? && !SiteSetting.enable_local_logins
      return render body: nil, status: :forbidden
    end

    authentication.start

    if authentication.email_valid? && !authentication.authenticated?
      # posted email is different that the already validated one?
      return fail_with('login.incorrect_username_email_or_password')
    end

    activation = UserActivator.new(user, request, session, cookies)
    activation.start

    # just assign a password if we have an authenticator and no password
    # this is the case for Twitter
    user.password = SecureRandom.hex if user.password.blank? && authentication.has_authenticator?
    if !session[:authentication][:country].nil?
      user.country = session[:authentication][:country]
    end

    if !session[:authentication][:organization].present?
      user.custom_fields["organization"] = session[:authentication][:organization]
    end

    if user.save

      authentication.finish
      activation.finish
      user.update_timezone_if_missing(params[:timezone])

      secure_session[HONEYPOT_KEY] = nil
      secure_session[CHALLENGE_KEY] = nil

      render json: {
        success: true,
        active: true,
        message: activation.message,
        user_id: user.id
      }
    elsif SiteSetting.hide_email_address_taken && user.errors[:primary_email]&.include?(I18n.t('errors.messages.taken'))
      session["user_created_message"] = activation.success_message

      if existing_user = User.find_by_email(user.primary_email&.email)
        Jobs.enqueue(:critical_user_email, type: :account_exists, user_id: existing_user.id)
      end

      render json: {
        success: true,
        active: true,
        message: activation.success_message,
        user_id: user.id
      }
    else
      errors = user.errors.to_hash
      errors[:email] = errors.delete(:primary_email) if errors[:primary_email]

      render json: {
        success: false,
        message: I18n.t(
          'login.errors',
          errors: user.errors.full_messages.join("\n")
        ),
        errors: errors,
        values: {
          name: user.name,
          username: user.username,
          email: user.primary_email&.email
        },
        is_developer: UsernameCheckerService.is_developer?(user.email)
      }
    end
  rescue ActiveRecord::StatementInvalid
    render json: {
      success: false,
      message: I18n.t("login.something_already_taken")
    }
  end

  private

  def user_params
    permitted = [
      :name,
      :email,
      :password,
      :country,
      :username,
      :title,
      :date_of_birth,
      :muted_usernames,
      :ignored_usernames,
      :theme_ids,
      :locale,
      :bio_raw,
      :location,
      :website,
      :dismissed_banner_key,
      :profile_background_upload_url,
      :card_background_upload_url,
      :primary_group_id,
      :featured_topic_id
    ]

    editable_custom_fields = User.editable_user_custom_fields(by_staff: current_user.try(:staff?))
    permitted << { custom_fields: editable_custom_fields } unless editable_custom_fields.blank?
    permitted.concat UserUpdater::OPTION_ATTR
    permitted.concat UserUpdater::CATEGORY_IDS.keys.map { |k| { k => [] } }
    permitted.concat UserUpdater::TAG_NAMES.keys

    result = params
      .permit(permitted, theme_ids: [])
      .reverse_merge(
        ip_address: request.remote_ip,
        registration_ip_address: request.remote_ip
      )

    if !UsernameCheckerService.is_developer?(result['email']) &&
        is_api? &&
        current_user.present? &&
        current_user.admin?

      result.merge!(params.permit(:active, :staged, :approved))
    end

    modify_user_params(result)
  end
end
