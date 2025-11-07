class ChatMcpSessionsController < ApplicationController
  before_action :set_chat

  def create
    @mcp_server = Current.account.mcp_servers.find(params[:mcp_server_id])
    @session = @chat.add_mcp_server(@mcp_server)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat, notice: "MCP server added to the chat." }
    end
  end

  def destroy
    @session = @chat.chat_mcp_sessions.find(params[:id])
    @mcp_server = @session.mcp_server
    @session.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat, notice: "MCP server removed from the chat." }
    end
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:chat_id])
  end
end
