class ChatMcpSessionsController < ApplicationController
  include ChatAccountScoped

  before_action :set_chat

  def create
    raise ActiveRecord::RecordNotFound if params[:mcp_server_id].blank?

    server = @chat.selected_mcp_servers([ params[:mcp_server_id] ]).fetch(0)
    @chat.add_mcp_server(server)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat, notice: I18n.t("nosia.chat.server_added") }
    end
  end

  def destroy
    ActsAsTenant.with_tenant(@chat.account) do
      session = @chat.chat_mcp_sessions.joins(:mcp_server).where(mcp_servers: { account_id: @chat.account_id }).find(params[:id])
      session.destroy
    end

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
