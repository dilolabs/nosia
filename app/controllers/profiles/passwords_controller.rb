class Profiles::PasswordsController < Profiles::BaseController
  def update
    attributes = params.expect(password_change: [ :password, :password_confirmation, :current_password ])

    if @user.change_password(password: attributes[:password], password_confirmation: attributes[:password_confirmation],
      current_password: attributes[:current_password], session: Current.session)
      redirect_to profile_path(anchor: "password"), status: :see_other, notice: t("nosia.profile.password_success")
    else
      @failed_section = :password
      render "profiles/show", status: :unprocessable_entity
    end
  end
end
