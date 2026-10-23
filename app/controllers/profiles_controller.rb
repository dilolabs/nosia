class ProfilesController < ApplicationController
  before_action -> { response.headers["Cache-Control"] = "no-store" }

  def show
    @user = Current.user
  end
end
