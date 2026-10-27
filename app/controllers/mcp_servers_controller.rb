# Manages MCP servers in the authorized URL account or the legacy default account.
class McpServersController < ApplicationController
  include McpScoped

  before_action :set_mcp_server, only: [ :show, :edit, :update, :destroy ]
  before_action :validate_configuration_values, only: [ :create, :update ]

  # @return [void] Renders the account's servers with allowlisted filters
  def index
    @mcp_servers = @account.mcp_servers.order(created_at: :desc)
    filters = { "status" => McpServer.statuses.keys, "transport_type" => %w[stdio streamable sse local], "enabled" => %w[true false 1 0] }
    filters.each do |key, allowed|
      @mcp_servers = @mcp_servers.where(key => params[key]) if allowed.include?(params[key])
    end
  end

  # @return [void] Renders the authorized server and its capabilities
  def show
    @capabilities = @mcp_server.capability_snapshot
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
      redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.created")
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
      redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # @return [void] Deletes the authorized server and preserves the list context
  def destroy
    @mcp_server.destroy
    redirect_to mcp_index_path, notice: t("nosia.mcp.deleted")
  end

  private
    def validate_configuration_values
      root = params.require(:mcp_server)
      if root.key?(:configuration_values) && !root[:configuration_values].is_a?(ActionController::Parameters)
        head :bad_request
      end
    end

    def mcp_server_params
      params.require(:mcp_server).permit(:name, :transport_type, :endpoint, :enabled, :notes, :tags, :command, :args)
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
