# frozen_string_literal: true

class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  before_action :check_allowed_registrations

  def new
    @user = User.new
  end

  def create
    @user = User.create_with_account!(user_params)
    start_new_session_for @user

    redirect_to root_path
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_session_path(email_address: user_params[:email_address])
  end

  private

  def check_allowed_registrations
    redirect_to root_path, alert: "Registrations are closed." unless ActiveModel::Type::Boolean.new.cast(ENV["REGISTRATIONS_ALLOWED"])
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end
end
