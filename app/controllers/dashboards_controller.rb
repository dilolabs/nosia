class DashboardsController < ApplicationController
  def show
    @chat = Current.user.chats.new
  end
end
