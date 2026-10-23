class McpServersController < ApplicationController
  before_action :set_mcp_server, only: [ :show, :edit, :update, :destroy, :test_connection, :connect, :disconnect ]

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
      redirect_to @mcp_server, notice: t("nosia.mcp.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @mcp_server.update(mcp_server_params)
      redirect_to @mcp_server, notice: t("nosia.mcp.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mcp_server.destroy
    redirect_to mcp_servers_path, notice: t("nosia.mcp.deleted")
  end

  # Test connection
  def test_connection
    if @mcp_server.test_connection!
      respond_to do |format|
        format.html { redirect_to @mcp_server, status: :see_other, flash: { connection_test: "success" } }
        format.json do
          render json: {
            success: true,
            status: @mcp_server.status,
            latency: @mcp_server.latency_ms,
            message: t("nosia.mcp.connection_established")
          }
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to @mcp_server, status: :see_other, flash: { connection_test: "error" } }
        format.json do
          render json: {
            success: false,
            status: @mcp_server.status,
            error: @mcp_server.last_error,
            message: t("nosia.mcp.connection_failed")
          }, status: :unprocessable_entity
        end
      end
    end
  end

  # Connect to server
  def connect
    if @mcp_server.test_connection!
      redirect_to @mcp_server, notice: t("nosia.mcp.connected")
    else
      redirect_to @mcp_server, alert: t("nosia.mcp.connection_error", error: @mcp_server.last_error)
    end
  end

  # Disconnect from server
  def disconnect
    @mcp_server.disconnect!
    redirect_to @mcp_server, notice: t("nosia.mcp.disconnected")
  end

  # Execute a tool (AJAX)
  def execute_tool
    @mcp_server = Current.account.mcp_servers.find(params[:id])
    tool_name = params[:tool_name]
    if !params[:arguments].nil? && !params[:arguments].is_a?(ActionController::Parameters)
      render json: { error: t("nosia.mcp.arguments_invalid") }, status: :bad_request
      return
    end
    # Tool inputs are an arbitrary JSON object, not McpServer attributes.
    arguments = params.permit(arguments: {}).fetch(:arguments, {}).to_h

    result = @mcp_server.execute_tool(tool_name, arguments)

    render json: tool_result_for_json(result)
  end

  private

  def tool_result_for_json(value)
    case value
    when RubyLLM::Attachment
      { type: value.type.to_s, data: value.encoded, mimeType: value.mime_type, filename: value.filename }
    when Array
      value.map { |item| tool_result_for_json(item) }
    when Hash
      value.transform_values { |item| tool_result_for_json(item) }
    when String, Numeric, TrueClass, FalseClass, NilClass
      value
    else
      raise TypeError, "Unsupported tool result JSON value"
    end
  end

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
