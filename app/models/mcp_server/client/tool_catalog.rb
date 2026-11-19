# Retains output schemas from completed native tools/list pages. The SDK's
# public Tool wrapper exposes input parameters, but drops outputSchema.
module McpServer::Client::ToolCatalog
  # @return [Hash] The original SDK catalog page, with no changes to wire data
  def request(method, params = {}, **options, &block)
    super.tap do |page|
      if method == "tools/list"
        @nosia_output_schemas = {} unless params[:cursor]
        Array(page["tools"]).each do |definition|
          @nosia_output_schemas[definition["name"]] = definition["outputSchema"]
        end
      end
    end
  end

  # @param name [String] The name on the MCP wire
  # @return [Hash, Boolean, nil] The peer's advertised output schema
  def output_schema_for(name) = @nosia_output_schemas&.[](name)
end
