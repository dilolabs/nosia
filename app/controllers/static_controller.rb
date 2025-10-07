# frozen_string_literal: true

class StaticController < ApplicationController
  allow_unauthenticated_access only: [ :index ]
  before_action :ensure_user_exists

  def index
  end

  private

  def ensure_user_exists
    redirect_to first_run_path if User.none?
  end
end
