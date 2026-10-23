class Profiles::EmailsController < Profiles::BaseController
  def update
    attributes = params.expect(email_change: [ :email, :current_password ])

    if @user.change_email(email: attributes[:email], current_password: attributes[:current_password])
      redirect_to profile_path(anchor: "email"), status: :see_other, notice: t("nosia.profile.email_success")
    else
      @failed_section = :email
      render "profiles/show", status: :unprocessable_entity
    end
  end
end
