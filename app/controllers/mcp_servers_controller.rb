# Manages MCP servers in the authorized URL account or the legacy default account.
class McpServersController < ApplicationController
  include McpScoped

  before_action :set_mcp_server, only: [ :show, :edit, :update, :destroy ]
  before_action :protect_oauth_response, only: [ :show, :edit, :update, :destroy ]
  before_action :validate_configuration_values, only: [ :create, :update ]

  # @return [void] Renders the account's servers with allowlisted filters
  def index
    @mcp_servers = @account.mcp_servers.order(created_at: :desc)
    filters = { "transport_type" => %w[stdio streamable sse local], "enabled" => %w[true false 1 0] }
    filters.each do |key, allowed|
      @mcp_servers = @mcp_servers.where(key => params[key]) if allowed.include?(params[key])
    end
    no_store
    if McpServer.statuses.key?(params[:status])
      @mcp_servers = @mcp_servers.where(auth_mode: "static", status: params[:status])
    elsif McpWorkspaceHelper::OAUTH_STATES.include?(params[:status])
      @mcp_servers = @mcp_servers.where(auth_mode: "oauth").select { |server| mcp_oauth_state(server) == params[:status] }
    end
  end

  # @return [void] Renders the authorized server and its capabilities
  def show
    discover = flash[:mcp_configuration_saved] != @mcp_server.id
    @capabilities = @mcp_server.capability_snapshot(discover: discover, user: Current.user)
    @oauth_test_reason = oauth_test_reason if @mcp_server.oauth?
    @tools = @capabilities.fetch(:tools).items
    @prompts = @capabilities.fetch(:prompts).items
    @resources = @capabilities.fetch(:resources).items
  end

  # @return [void] Renders a new server form in the current MCP context
  def new
    @mcp_server = @account.mcp_servers.build(transport_type: "streamable")
  end

  # @return [void] Creates an account server or returns input/validation errors
  def create
    @mcp_server = @account.mcp_servers.build(transport_type: mcp_server_params[:transport_type])

    if @mcp_server.save_workspace(mcp_server_params, values: configuration_values, removals: configuration_removals)
      redirect_to mcp_record_path(@mcp_server), status: configuration_redirect_status, notice: t("nosia.mcp.created"), flash: { mcp_configuration_saved: @mcp_server.id }
    else
      render :new, status: :unprocessable_entity
    end
  end

  # @return [void] Renders the authorized server's configuration form
  def edit
  end

  # @return [void] Updates an account server or returns input/validation errors
  def update
    if @mcp_server.save_workspace(mcp_server_params, values: configuration_values, removals: configuration_removals)
      redirect_to mcp_record_path(@mcp_server), status: configuration_redirect_status, notice: t("nosia.mcp.updated"), flash: { mcp_configuration_saved: @mcp_server.id }
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # @return [void] Deletes the authorized server and preserves the list context
  def destroy
    @mcp_server.destroy
    redirect_to mcp_index_path, status: configuration_redirect_status, notice: t("nosia.mcp.deleted")
  end

  private
    def oauth_test_reason
      result = flash[:mcp_oauth_test]
      if result.is_a?(Hash) && result["server_id"] == @mcp_server.id && result["session_id"] == Current.session.id
        result["reason"]
      end
    end

    def validate_configuration_values
      root = params.require(:mcp_server)
      if root.key?(:configuration_values) && !root[:configuration_values].is_a?(ActionController::Parameters)
        head :bad_request
      end
    end

    def mcp_server_params
      params.require(:mcp_server).permit(:name, :transport_type, :endpoint, :enabled, :notes, :tags, :command, :args, :auth_mode)
    end

    def configuration_redirect_status
      protect_oauth_response
      @mcp_server.oauth? || @mcp_server.auth_mode_before_last_save == "oauth" ? :see_other : :found
    end

    def configuration_values
      root = params.require(:mcp_server)
      allowed = @mcp_server.workspace_configuration_fields.map { |field| field[:name].to_s }
      legacy = root.permit(:token, :api_key).to_h.slice(*allowed)
      legacy.merge(root.fetch(:configuration_values, ActionController::Parameters.new).permit(*allowed).to_h)
    end

    def configuration_removals
      params.require(:mcp_server).permit(remove_credentials: []).fetch(:remove_credentials, [])
    end
end
