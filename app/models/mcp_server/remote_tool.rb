# A native tool registered by value, retaining its client until the turn ends.
class McpServer::RemoteTool < RubyLLM::Tool
  delegate :server_name, :description, :parameters_schema, to: :@tool
  attr_reader :name

  # @param tool [RubyLLM::MCP::Tool] The advertised native tool
  # @param client [McpServer::Client] The connection that advertised it
  # @param name [String] The sanitized provider-facing name
  def initialize(tool, client, name:)
    super()
    @tool = tool
    @client = client
    @name = name
  end

  # @param arguments [Hash] Parameters passed by the model
  # @return [String, Array, Hash] Model content with native attachments, or a safe error
  def call(**arguments)
    @client.within do
      result = @tool.call(**arguments)
      case result
      when RubyLLM::MCP::Result then @client.output(result)
      when RubyLLM::MCP::Outages::Failure then unavailable
      when Hash then @client.tool_error(result[:error])
      else unavailable
      end
    end
  rescue McpServer::Client::Error
    unavailable
  end

  private
    def unavailable
      { error: I18n.t("nosia.mcp_workspace.remote_failure") }
    end
end
