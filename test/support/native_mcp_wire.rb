# A controlled peer at the Faraday adapter boundary. It never opens a socket.
class NativeMcpWire
  HOST = "mcp.example.test"
  URL = "https://#{HOST}/mcp"
  LEGACY_SESSION = "fixture-session"
  PRIVATE_MARKER = "fixture-private-error"
  TOOL = {
    "name" => "lookup",
    "description" => "Look up a fixture",
    "inputSchema" => { "type" => "object", "properties" => {
      "query" => { "type" => "string" }, "options" => { "type" => "object", "properties" => {
        "page" => { "type" => "integer" }
      } }
    }, "required" => [ "query" ] }
  }.freeze
  RESOURCE = { "name" => "Report", "uri" => "https://not-the-mcp-host.test/report.txt", "mimeType" => "text/plain" }.freeze

  attr_reader :requests
  attr_accessor :tool_result, :legacy, :stream, :fail_method, :tools, :prompts, :resources, :ping
  attr_accessor :unavailable_method, :timeout_method, :fail_reinitialize, :failure_status
  attr_accessor :resume_tool_error

  def initialize
    @requests = []
    @tools = [ TOOL ]
    @prompts = [ { "name" => "summary", "arguments" => [ { "name" => "topic", "required" => true } ] } ]
    @resources = [ RESOURCE ]
    @tool_result = { "content" => [ { "type" => "text", "text" => "found" } ] }
  end

  def install(test, &block)
    wire = self
    test.with_singleton_replacement(McpOutbound::Adapter, :new, ->(app, *) { Adapter.new(app, wire) }, &block)
  end

  def methods_requested
    requests.map { |request| request[:rpc]["method"] || request[:verb] }
  end

  def last_tool_call
    requests.reverse.find { |request| request[:rpc]["method"] == "tools/call" }.fetch(:rpc).fetch("params")
  end

  def reply(env)
    raise Minitest::Assertion, "Unexpected MCP host #{env.url.host}" unless env.url.host == HOST

    rpc = env.body ? JSON.parse(env.body) : {}
    requests << { verb: env.method, scheme: env.url.scheme, path: env.url.path, headers: env.request_headers.dup, rpc:, scope: McpOutbound.current! }
    return [ 204, {}, "" ] if legacy && env.method == :delete && env.request_headers["Mcp-Session-Id"] == LEGACY_SESSION
    return resumed_tool_error if resume_tool_error && env.method == :get && env.request_headers["Last-Event-ID"] == "fixture-event"

    raise Minitest::Assertion, "Unexpected MCP HTTP method #{env.method}" unless env.method == :post

    if rpc["id"] == "fixture-peer-ping" && !rpc.key?("method")
      body = JSON.generate({ "jsonrpc" => "2.0", "id" => rpc["id"] }.merge(rpc_error(-32_603, PRIVATE_MARKER)))
      return [ 500, { "Content-Type" => "application/json" }, body ]
    end

    method = rpc.fetch("method")
    raise Faraday::TimeoutError, PRIVATE_MARKER if method == timeout_method
    return [ 503, { "Content-Type" => "text/plain" }, PRIVATE_MARKER ] if method == unavailable_method

    if method == "tools/call" && fail_reinitialize
      @session_expired = true
      return [ 404, {}, "" ]
    end

    if method == "tools/call" && resume_tool_error
      @resumed_id = rpc.fetch("id")
      return [ 200, { "Content-Type" => "text/event-stream" }, "id: fixture-event\r\nretry: 0\r\n\r\n" ]
    end

    if method == fail_method || (method == "initialize" && @session_expired)
      outcome = rpc_error(-32_603, PRIVATE_MARKER)
    else
      outcome = rpc_outcome(method)
    end
    return [ 202, {}, "" ] unless rpc.key?("id")

    body = JSON.generate({ "jsonrpc" => "2.0", "id" => rpc["id"] }.merge(outcome))
    headers = { "Content-Type" => stream ? "text/event-stream" : "application/json" }
    headers["Mcp-Session-Id"] = LEGACY_SESSION if legacy && method == "initialize"
    if stream
      body = event_frame(body)
      if method == "tools/list" && ping
        body = event_frame(JSON.generate(jsonrpc: "2.0", method: "ping", id: "fixture-peer-ping")) + body
      end
    end
    [ method == fail_method && failure_status ? failure_status : 200, headers, body ]
  end

  private
    def resumed_tool_error
      outcome = { "jsonrpc" => "2.0", "id" => @resumed_id }.merge(rpc_error(-32_603, PRIVATE_MARKER))
      [ 200, { "Content-Type" => "text/event-stream" }, event_frame(JSON.generate(outcome)) ]
    end

    def event_frame(body)
      "event: message\r\ndata: #{body}\r\n\r\n"
    end

    def rpc_outcome(method)
      case method
      when "server/discover"
        return rpc_error(-32_601, "Method not found") if legacy

        { "result" => { "supportedVersions" => [ "2026-07-28" ], "capabilities" => { "tools" => {}, "resources" => {}, "prompts" => {} } } }
      when "initialize" then { "result" => { "protocolVersion" => "2025-11-25", "capabilities" => { "tools" => {}, "resources" => {}, "prompts" => {} } } }
      when "notifications/initialized" then {}
      when "tools/list" then { "result" => { "tools" => tools } }
      when "prompts/list" then { "result" => { "prompts" => prompts } }
      when "resources/list" then { "result" => { "resources" => resources } }
      when "resources/read" then { "result" => { "contents" => [ RESOURCE.merge("text" => "MCP resource body") ] } }
      when "tools/call" then { "result" => tool_result }
      else raise Minitest::Assertion, "Unexpected MCP request #{method}"
      end
    end

    def rpc_error(code, message)
      { "error" => { "code" => code, "message" => message } }
    end

    class Adapter < Faraday::Adapter
      def initialize(app, wire)
        super(app)
        @wire = wire
      end

      def call(env)
        super
        scope = McpOutbound.current!
        attempt = scope.capture(env)
        status, headers, body = @wire.reply(env)
        if env.stream_response?
          save_response(env, status, nil, headers, nil, finished: false)
          env.stream_response do |&on_data|
            body.bytes.each_slice(11) { |bytes| on_data.call(bytes.pack("C*")) }
          end
          body = ""
        end
        save_response(env, status, body, headers)
        scope.observe(attempt, env.response)
        @app.call(env)
      end
    end
end
