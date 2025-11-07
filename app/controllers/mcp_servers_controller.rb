class McpServersController < ApplicationController
  before_action :set_mcp_server, only: [:show, :edit, :update, :destroy, :test_connection, :connect, :disconnect]

  def index
    @mcp_servers = Current.account.mcp_servers.order(created_at: :desc)

    # Filters
    @mcp_servers = @mcp_servers.where(status: params[:status]) if params[:status].present?
    @mcp_servers = @mcp_servers.where(enabled: params[:enabled]) if params[:enabled].present?
    @mcp_servers = @mcp_servers.where(transport_type: params[:transport_type]) if params[:transport_type].present?
  end

  def show
    @tools = @mcp_server.tools
    @prompts = @mcp_server.prompts
    @resources = @mcp_server.resources
  end

  def new
    @mcp_server = Current.account.mcp_servers.build
  end

  def create
    @mcp_server = Current.account.mcp_servers.build(mcp_server_params)

    if @mcp_server.save
      redirect_to @mcp_server, notice: "MCP server created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @mcp_server.update(mcp_server_params)
      redirect_to @mcp_server, notice: "MCP server updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mcp_server.destroy
    redirect_to mcp_servers_path, notice: "MCP server deleted."
  end

  # Test connection
  def test_connection
    if @mcp_server.test_connection!
      render json: {
        success: true,
        status: @mcp_server.status,
        latency: @mcp_server.latency_ms,
        message: "Connection established"
      }
    else
      render json: {
        success: false,
        status: @mcp_server.status,
        error: @mcp_server.last_error,
        message: "Connection failed"
      }, status: :unprocessable_entity
    end
  end

  # Connect to server
  def connect
    if @mcp_server.test_connection!
      redirect_to @mcp_server, notice: "Connected to MCP server."
    else
      redirect_to @mcp_server, alert: "Connection failed: #{@mcp_server.last_error}."
    end
  end

  # Disconnect from server
  def disconnect
    @mcp_server.disconnect!
    redirect_to @mcp_server, notice: "Disconnected from MCP server."
  end

  # Execute a tool (AJAX)
  def execute_tool
    @mcp_server = Current.account.mcp_servers.find(params[:id])
    tool_name = params[:tool_name]
    arguments = params[:arguments] || {}

    result = @mcp_server.execute_tool(tool_name, arguments)

    render json: result
  end

  private

  def set_mcp_server
    @mcp_server = Current.account.mcp_servers.find(params[:id])
  end

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
