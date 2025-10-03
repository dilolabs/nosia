class ProfilesController < ApplicationController
  def show
    @user = Current.user
  end
end
