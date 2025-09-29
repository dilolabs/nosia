# frozen_string_literal: true

class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Try again later." }

  before_action :ensure_user_exists, only: :new

  def new
  end

  def create
    if user = User.authenticate_by(email: params[:email], password: params[:password])
      start_new_session_for user
      redirect_to after_authentication_url
    else
      render_rejection :unauthorized
    end
  end

  def destroy
    terminate_session
    redirect_to root_path
  end

  private

  def ensure_user_exists
    redirect_to first_run_path if User.none?
  end

  def render_rejection(status)
    flash.now[:alert] = "Too many requests or unauthorized."
    render :new, status: status
  end
end
