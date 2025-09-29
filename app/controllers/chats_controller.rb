class ChatsController < ApplicationController
  before_action :set_chat, only: [:show, :destroy]

  def show
    @message = @chat.messages.build
  end

  def new
    @chat = Current.user.chats.new
    @selected_model = params[:model]
  end

  def create
    return unless prompt.present?

    @chat = Current.user.chats.create!(account: Current.account, model: model)
    ChatResponseJob.perform_later(@chat.id, prompt)

    redirect_to @chat, notice: 'Chat was successfully created.'
  end

  def destroy
    @chat.destroy
    redirect_to root_path
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:id])
  end

  def model
    params[:chat][:model].presence || ENV['LLM_MODEL']
  end

  def prompt
    params[:chat][:prompt]
  end
end
