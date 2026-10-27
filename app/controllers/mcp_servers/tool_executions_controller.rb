# Executes authorized MCP tools with the existing JSON boundary contract.
class McpServers::ToolExecutionsController < ApplicationController
  include McpScoped

  before_action :set_mcp_server

  # @return [void] Renders the tool result or rejects non-object arguments
  # @raise [TypeError] If the result contains an unsupported JSON value
  def create
    if !params[:arguments].nil? && !params[:arguments].is_a?(ActionController::Parameters)
      render json: { error: t("nosia.mcp.arguments_invalid") }, status: :bad_request
    else
      arguments = params.permit(arguments: {}).fetch(:arguments, {}).to_h
      render json: tool_result_for_json(@mcp_server.execute_tool(params[:tool_name], arguments))
    end
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
end
