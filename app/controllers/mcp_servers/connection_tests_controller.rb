# Tests authorized MCP connections while preserving HTML and JSON compatibility.
class McpServers::ConnectionTestsController < ApplicationController
  include McpScoped

  before_action :set_mcp_server

  # @return [void] Redirects HTML clients or renders the existing JSON result
  def create
    success = @mcp_server.test_connection!
    respond_to do |format|
      format.html { redirect_to mcp_record_path(@mcp_server), status: :see_other, flash: { connection_test: success ? "success" : "error" } }
      format.json do
        if success
          render json: { success: true, status: @mcp_server.status, latency: @mcp_server.latency_ms, message: t("nosia.mcp.connection_established") }
        else
          render json: { success: false, status: @mcp_server.status, error: @mcp_server.last_error, message: t("nosia.mcp.connection_failed") }, status: :unprocessable_entity
        end
      end
    end
  end
end
