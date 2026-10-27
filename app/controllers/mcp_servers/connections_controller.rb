# Connects and disconnects authorized MCP servers through scoped or legacy URLs.
class McpServers::ConnectionsController < ApplicationController
  include McpScoped

  before_action :set_mcp_server

  # @return [void] Tests the connection and redirects with its outcome
  def create
    if @mcp_server.test_connection!
      redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.connected")
    else
      redirect_to mcp_record_path(@mcp_server), alert: t("nosia.mcp.connection_failed")
    end
  end

  # @return [void] Disconnects the server and preserves the detail context
  def destroy
    @mcp_server.disconnect!
    redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.disconnected")
  end
end
