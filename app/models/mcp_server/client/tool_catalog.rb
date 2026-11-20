# Guards native tool replies and retains output schemas the SDK's public
# Tool wrapper drops.
module McpServer::Client::ToolCatalog
  class UnsolicitedTask < StandardError; end

  # @return [Hash] The original SDK reply, with no changes to wire data
  # @raise [UnsolicitedTask] The peer returned a task the client did not negotiate
  def request(method, params = {}, **options, &block)
    super.tap do |result|
      case method
      when "tools/call"
        # Reject before RubyLLM can turn the reply into a task and wait on it.
        raise UnsolicitedTask, cause: nil if result.is_a?(Hash) && result["resultType"] == "task"
      when "tools/list"
        @nosia_output_schemas = {} unless params[:cursor]
        Array(result["tools"]).each do |definition|
          @nosia_output_schemas[definition["name"]] = definition["outputSchema"]
        end
      end
    end
  end

  # @param name [String] The name on the MCP wire
  # @return [Hash, Boolean, nil] The peer's advertised output schema
  def output_schema_for(name) = @nosia_output_schemas&.[](name)
end
