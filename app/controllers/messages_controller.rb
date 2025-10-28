class MessagesController < ApplicationController
  before_action :set_chat

  def create
    return unless content.present?

    # Créer le message utilisateur immédiatement pour qu'il soit visible tout de suite
    @chat.messages.create!(role: :user, content: content)

    ChatResponseJob.perform_later(@chat.id, content)

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
