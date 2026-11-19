# Executes authorized MCP tools with the existing JSON boundary contract.
class McpServers::ToolExecutionsController < ApplicationController
  include McpScoped

  before_action :set_mcp_server
  before_action :protect_oauth_response

  # @return [void] Renders the tool result or rejects non-object arguments
  # @raise [TypeError] If the result contains an unsupported JSON value
  def create
    if !params[:arguments].nil? && !params[:arguments].is_a?(ActionController::Parameters)
      render json: { error: t("nosia.mcp.arguments_invalid") }, status: :bad_request
    else
      arguments = params.permit(arguments: {}).to_h.fetch("arguments", {})
      result = if @mcp_server.oauth?
        @mcp_server.execute_tool(params[:tool_name], arguments, user: Current.user)
      else
        @mcp_server.execute_tool(params[:tool_name], arguments)
      end
      render json: tool_result_for_json(result)
    end
  rescue McpAuthorization::Unavailable, McpAuthorization::InsufficientScope => error
    render json: { error: mcp_oauth_text(McpAuthorization.failure_reason(error)) }
  end

  private
    def tool_result_for_json(value)
      case value
      when RubyLLM::Attachment
        { type: value.type.to_s, data: value.encoded, mimeType: value.mime_type, filename: value.filename.presence || "mcp-attachment" }
      when Array
        value.map { |item| tool_result_for_json(item) }
      when Hash
        value.to_h do |key, item|
          raise TypeError, "Unsupported tool result JSON key" unless key.is_a?(String) || key.is_a?(Symbol)

          [ key, tool_result_for_json(item) ]
        end
      when String, Integer, Float, BigDecimal, TrueClass, FalseClass, NilClass
        value
      else
        raise TypeError, "Unsupported tool result JSON value"
      end
    end
end
