class DashboardsController < ApplicationController
  include ChatAccountScoped

  def show
    @chat = Current.user.chats.new(account: selected_chat_account(params[:account_id]))
    @selected_model = params[:model]
    @default_account = Current.user.first_account
    @report = TokenUsage::Report.new(accounts: Current.user.accounts)
    @conversations = Current.user.recent_conversations.limit(5).to_a
    @titles = Chat.first_questions_for(@conversations)
  end
end
