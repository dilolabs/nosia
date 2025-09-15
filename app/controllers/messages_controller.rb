# frozen_string_literal: true

class MessagesController < ApplicationController
  include ActionView::RecordIdentifier

  def create
    @chat = Current.user.chats.find(params[:chat_id])
    @message = @chat.messages.create(
      message_params.merge(
        response_number: @chat.messages.count
      ),
    )
    GetAiResponseJob.perform_later(@message.chat_id)

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
