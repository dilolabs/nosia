class DashboardsController < ApplicationController
  include ChatAccountScoped

  def show
    @chat = Current.user.chats.new(account: selected_chat_account(params[:account_id]))
    @selected_model = params[:model]
  end
end
