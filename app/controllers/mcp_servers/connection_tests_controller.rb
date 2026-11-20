# Tests authorized MCP connections while preserving HTML and JSON compatibility.
class McpServers::ConnectionTestsController < ApplicationController
  include McpScoped

  before_action :set_mcp_server
  before_action :protect_oauth_response

  # @return [void] Redirects HTML clients or renders the existing JSON result
  def create
    return render_oauth_test if @mcp_server.oauth?

    success = @mcp_server.test_connection!
    respond_to do |format|
      format.html { redirect_to mcp_record_path(@mcp_server), status: :see_other, flash: { connection_test: success ? "success" : "error" } }
      format.json do
        if success
          render json: { success: true, status: @mcp_server.status, latency: @mcp_server.latency_ms, message: t("nosia.mcp.connection_established") }
        else
          error = @mcp_server.legacy_sse? ? t("nosia.mcp_workspace.legacy_sse_migration") : @mcp_server.last_error
          render json: { success: false, status: @mcp_server.status, error:, message: t("nosia.mcp.connection_failed") }, status: :unprocessable_entity
        end
      end
    end
  end

  private
    def render_oauth_test
      grant = @mcp_server.oauth_grant_for(Current.user)
      reason = oauth_test_failure(grant)
      respond_to do |format|
        format.html do
          redirect_within_oauth_workspace(account_mcp_server_path(@account, @mcp_server),
            mcp_oauth_test: { "server_id" => @mcp_server.id, "session_id" => Current.session.id,
              "connection_revision" => @mcp_server.connection_revision, "grant_id" => grant&.id, "reason" => (reason || :success).to_s })
        end
        format.json do
          state = mcp_oauth_state(@mcp_server)
          if reason
            render json: { success: false, status: state, error: mcp_oauth_text(reason), message: t("nosia.mcp.connection_failed") }, status: :unprocessable_entity
          else
            render json: { success: true, status: state, latency: nil, message: t("nosia.mcp.connection_established") }
          end
        end
      end
    end

    def oauth_test_failure(grant)
      return :authorization_needed unless grant

      grant.with_authorized_client(&:tools)
      nil
    rescue McpAuthorization::Unavailable, McpAuthorization::InsufficientScope => error
      McpAuthorization.failure_reason(error)
    end
end
