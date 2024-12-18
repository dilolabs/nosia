class ChatsController < ApplicationController
  before_action :set_chat, only: %i[show destroy]

  def show
  end

  def create
    @chat = Current.user.chats.create(account: Current.account)
    redirect_to @chat
  end

  def destroy
    @chat.destroy
    redirect_to root_path
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:id])
  end
end
