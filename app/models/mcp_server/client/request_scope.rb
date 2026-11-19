# Tracks the provenance of native errors during a direct tool call without
# keeping request arguments, credentials, or response bodies.
class McpServer::Client::RequestScope < McpOutbound::Scope
  # @return [Object] The result of the native operation
  def while_calling_tool
    @calling_tool = true
    yield
  ensure
    @calling_tool = false
    @tool_request = false
    @stdio_tool_request = false
    @tool_http_status = nil
  end

  # @param env [Faraday::Env] The outgoing request before Faraday reads the response
  def capture(env)
    return unless @calling_tool

    if env.method == :post
      method = JSON.parse(env.body)["method"]
      return unless method # Answers to server pings do not replace the active request.

      @tool_request = method == "tools/call"
    elsif env.method != :get
      @tool_request = false
    end

    # A legacy GET can resume the active tool request. Its status, not any
    # earlier response's status, determines whether the resumed answer qualifies.
    @tool_http_status = nil
    return unless @tool_request && (on_data = env.request.on_data)

    # RubyLLM may end an SSE stream as soon as it has the answer, so observe
    # the status before its callback can interrupt the adapter.
    env.request.on_data = ->(chunk, size, response) do
      @tool_http_status = response.status
      on_data.call(chunk, size, response)
    end
    nil
  end

  # @param method [String] The method about to be sent by the native stdio transport
  def capture_stdio_request(method)
    @stdio_tool_request = method == "tools/call" if @calling_tool
  end

  # @param error [RubyLLM::MCP::Error] The error raised by the native call
  # @return [Boolean] Whether the peer sent a JSON-RPC error for tools/call
  def tool_protocol_error?(error)
    (@stdio_tool_request || (200..299).cover?(@tool_http_status)) &&
      error.instance_of?(RubyLLM::MCP::Error) && error.response.nil? && error.code.is_a?(Integer)
  end
end
