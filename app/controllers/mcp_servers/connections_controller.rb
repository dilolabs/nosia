# Connects and disconnects authorized MCP servers through scoped or legacy URLs.
class McpServers::ConnectionsController < ApplicationController
  include McpScoped

  before_action :set_mcp_server
  before_action :protect_oauth_response

  # @return [void] Tests the connection and redirects with its outcome
  def create
    if @mcp_server.oauth?
      redirect_oauth(:use_authorize, notice: true)
    elsif @mcp_server.legacy_sse?
      redirect_to mcp_record_path(@mcp_server), alert: t("nosia.mcp_workspace.legacy_sse_migration")
    elsif @mcp_server.test_connection!
      redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.connected")
    else
      redirect_to mcp_record_path(@mcp_server), alert: t("nosia.mcp.connection_failed")
    end
  end

  # @return [void] Disconnects the server and preserves the detail context
  def destroy
    if @mcp_server.oauth?
      @mcp_server.disconnect!(user: Current.user)
      redirect_oauth(:disconnected, notice: true)
    elsif @mcp_server.legacy_sse?
      redirect_to mcp_record_path(@mcp_server), alert: t("nosia.mcp_workspace.legacy_sse_migration")
    elsif @mcp_server.disconnect!
      redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.disconnected")
    else
      redirect_to mcp_record_path(@mcp_server), alert: t("nosia.mcp.connection_failed")
    end
  rescue McpAuthorization::Unavailable => error
    redirect_oauth(McpAuthorization.failure_reason(error))
  end
end
