class DashboardsController < ApplicationController
  def show
    @chat = Current.user.chats.new(account: Current.account)
  end
end
