# Manages MCP servers in the authorized URL account or the legacy default account.
class McpServersController < ApplicationController
  include McpScoped

  before_action :set_mcp_server, only: [ :show, :edit, :update, :destroy ]

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
    @tools, @prompts, @resources = @mcp_server.tools, @mcp_server.prompts, @mcp_server.resources
  end

  # @return [void] Renders a new server form in the current MCP context
  def new
    @mcp_server = @account.mcp_servers.build
  end

  # @return [void] Creates an account server or renders validation errors
  def create
    @mcp_server = @account.mcp_servers.build(mcp_server_params)

    if @mcp_server.save
      redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # @return [void] Renders the authorized server's configuration form
  def edit
  end

  # @return [void] Updates an account server or renders validation errors
  def update
    if @mcp_server.update(mcp_server_params)
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
    def mcp_server_params
      params.require(:mcp_server).permit(
        :name,
        :transport_type,
        :endpoint,
        :enabled,
        :notes,
        :tags,
        :command,
        :args,
        :env,
        :url,
        :token,
        :api_key,
        connection_config: {},
        auth_config: {}
      )
    end
end
