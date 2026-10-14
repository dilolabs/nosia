require "test_helper"

class RubyLlmMcpTransportTest < ActiveSupport::TestCase
  TRANSPORTS = {
    stdio: RubyLLM::MCP::Native::Transports::Stdio,
    sse: RubyLLM::MCP::Native::Transports::SSE,
    streamable: RubyLLM::MCP::Native::Transports::StreamableHTTP,
    streamable_http: RubyLLM::MCP::Native::Transports::StreamableHTTP
  }.freeze

  # Only the physical transport is fake. Client, adapter, protocol messages,
  # capabilities, remote-tool wrapping, and result conversion are real.
  class CannedTransport
    attr_reader :config, :events

    def initialize(**config)
      @config = config
      @events = []
      @alive = false
    end

    def start
      @events << :start
      @alive = true
    end

    def alive?
      @alive
    end

    def close
      @events << :close
      @alive = false
    end

    def set_protocol_version(version)
      @events << [ :version, version ]
    end

    def request(body, wait_for_response: true)
      @events << body
      return unless wait_for_response

      value = case body.fetch(:method)
      when "initialize"
        { "protocolVersion" => @config.fetch(:coordinator).protocol_version, "capabilities" => { "tools" => {} } }
      when "tools/list"
        { "tools" => [ { "name" => "echo", "inputSchema" => { "type" => "object", "properties" => { "query" => { "type" => "string" } }, "required" => [ "query" ] } } ] }
      when "tools/call"
        { "content" => [ { "type" => "text", "text" => body.dig(:params, :arguments, :query) } ] }
      else
        raise "Unexpected canned MCP request: #{body.inspect}"
      end
      RubyLLM::MCP::Result.new({ "id" => body[:id], "result" => value })
    end
  end

  test "every existing transport still selects its original implementation without connecting" do
    TRANSPORTS.each do |type, klass|
      client = RubyLLM::MCP.client(name: "selection", transport_type: type, start: false, config: transport_config(type))
      begin
        native = client.adapter.native_client
        assert_instance_of RubyLLM::MCP::Adapters::RubyLLMAdapter, client.adapter
        assert_instance_of klass, native.transport.transport_protocol
        if type == :stdio
          assert_equal "ruby", native.config.fetch(:command)
          assert_equal [ "fixture.rb" ], native.config.dig(:options, :args)
          assert_equal({ "TOOL_MODE" => "test" }, native.config.dig(:options, :env))
        else
          assert_equal "https://mcp.example.com/mcp", native.config.fetch(:url)
          assert_equal "Bearer fake-token", native.config.dig(:options, :headers, "Authorization")
          assert_equal "preserved", native.config.dig(:options, :headers, "X-Custom")
        end
      ensure
        # No remote close request: this client was never started.
        native.instance_variable_set(:@transport, nil)
        client.stop
      end
    end
  end

  test "stdio sse and streamable clients retain default start list call and stop lifecycle" do
    TRANSPORTS.each do |type, klass|
      original_new = klass.method(:new)
      transport = nil
      klass.define_singleton_method(:new) { |**options| transport = CannedTransport.new(**options) }
      client = nil
      begin
        client = RubyLLM::MCP.client(name: "canned", transport_type: type, config: transport_config(type))
        assert client.alive?
        assert_equal :start, transport.events.first
        assert client.capabilities.tools_list?
        tool = client.tools.first
        assert_equal "echo", tool.name
        assert_equal [ "query" ], tool.parameters_schema.fetch("required")
        assert_equal "file:///opaque-argument", tool.call(**{ "query" => "file:///opaque-argument" })
        assert_equal [ "initialize", "notifications/initialized", "tools/list", "tools/call" ], transport.events.grep(Hash).map { |event| event[:method] }
        if type == :stdio
          assert_equal "ruby", transport.config.fetch(:command)
          assert_equal [ "fixture.rb" ], transport.config.fetch(:args)
          assert_equal({ "TOOL_MODE" => "test" }, transport.config.fetch(:env))
        else
          config = type == :sse ? transport.config.fetch(:options) : transport.config
          assert_equal "https://mcp.example.com/mcp", transport.config.fetch(:url)
          assert_equal "Bearer fake-token", config.dig(:headers, "Authorization")
          assert_equal "preserved", config.dig(:headers, "X-Custom")
        end
        client.stop
        assert_not client.alive?
        assert_equal :close, transport.events.last
      ensure
        client&.stop
        klass.define_singleton_method(:new, original_new)
      end
    end
  end

  test "capability errors remain explicit when the server does not offer completions" do
    adapter = Struct.new(:capabilities).new(RubyLLM::MCP::ServerCapabilities.new({}))
    prompt = RubyLLM::MCP::Prompt.new(adapter, "name" => "demo")
    assert_raises(RubyLLM::MCP::Errors::Capabilities::CompletionNotAvailable) { prompt.complete("query", "test") }
    resource = RubyLLM::MCP::Resource.new(adapter, "uri" => "file:///demo")
    assert_raises(RubyLLM::MCP::Errors::Capabilities::ResourceSubscribeNotAvailable) { resource.subscribe! }
  end

  test "sampling response respects the client's negotiated legacy protocol" do
    klass = TRANSPORTS.fetch(:streamable)
    original_new = klass.method(:new)
    klass.define_singleton_method(:new) { |**options| CannedTransport.new(**options) }
    client = RubyLLM::MCP.client(name: "legacy", transport_type: :streamable,
      config: transport_config(:streamable).merge(protocol_version: "2025-06-18"))
    attachment = RubyLLM::MCP::Attachment.new(Base64.strict_encode64("image"), "image/png")
    mixed = RubyLLM::Message.new(role: :assistant, content: "caption", attachments: [ attachment ])
    assert_equal "2025-06-18", client.adapter.native_client.protocol_version
    assert_raises(RubyLLM::MCP::Errors::InvalidFormatError) do
      client.adapter.native_client.sampling_create_message_response(id: "legacy", model: "test-model", message: mixed)
    end
  ensure
    client&.stop
    klass.define_singleton_method(:new, original_new)
  end

  private
    def transport_config(type)
      if type == :stdio
        { command: "ruby", args: [ "fixture.rb" ], env: { "TOOL_MODE" => "test" } }
      else
        { url: "https://mcp.example.com/mcp", headers: { "Authorization" => "Bearer fake-token", "X-Custom" => "preserved" } }
      end
    end
end
