class ChatMcpSessionsController < ApplicationController
  include ChatAccountScoped

  before_action :set_chat

  def create
    raise ActiveRecord::RecordNotFound if params[:mcp_server_id].blank?

    @mcp_server = @chat.selected_mcp_servers([ params[:mcp_server_id] ]).fetch(0)
    @session = @chat.add_mcp_server(@mcp_server)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat, notice: I18n.t("nosia.chat.server_added") }
    end
  end

  def destroy
    @session = @chat.chat_mcp_sessions.find(params[:id])
    @mcp_server = ActsAsTenant.with_tenant(@chat.account) { @session.mcp_server }
    raise ActiveRecord::RecordNotFound unless @mcp_server

    @session.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat, notice: I18n.t("nosia.chat.server_removed") }
    end
  end

  private
    def set_chat
      @chat = authorized_chat(params[:chat_id])
    end
end
