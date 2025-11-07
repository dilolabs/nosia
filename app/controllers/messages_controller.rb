class MessagesController < ApplicationController
  before_action :set_chat

  def create
    return unless content.present?

    # Create the user message immediately for instant display
    @user_message = @chat.messages.create!(role: "user", content: content)

    # Queue the job in the background with the ID of the created message
    ChatResponseJob.perform_later(@chat.id, content, @user_message.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat }
    end
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:chat_id])
  end

  def content
    params[:message][:content]
  end
end
