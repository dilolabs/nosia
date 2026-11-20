# RubyLLM 2.2.3 attaches the protocol code but not the originating method
# to its errors. Track the method without replacing the native stdio protocol.
class McpServer::Client::Stdio < RubyLLM::MCP::Stdio
  # @param command [Array<String>] Executable and arguments
  # @param env [Hash] Connector environment overrides
  # @param scope [McpServer::Client::RequestScope] Error provenance for this client
  def initialize(command, env:, scope:)
    super(command, env:)
    @scope = scope
  end

  # @param message [Hash] Native JSON-RPC request, before it is written to the pipe
  def request(message, ...)
    @scope.capture_stdio_request(message.fetch(:method))
    super
  end

  private
    def write(message)
      @scope.admit!(nil)
      super
    end
end
