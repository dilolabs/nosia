require "test_helper"
require "tempfile"
require_relative "../support/chat_account_fixtures"
require_relative "../support/native_mcp_wire"

class McpServerNativeTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  setup do
    @server = mcp_servers(:picker_second_tool)
    @wire = NativeMcpWire.new
    # Reuse a persisted fixture; exercise save/configuration separately.
    @server.update_columns(transport_type: "streamable", endpoint: NativeMcpWire::URL)
  end

  test "native discovery uses the guarded scope and does not execute discovered capabilities" do
    @wire.fail_method = "prompts/list"

    @wire.install(self) do
      snapshot = @server.capability_snapshot
      assert_equal({ tools: :loaded, prompts: :unavailable, resources: :loaded }, snapshot.transform_values(&:state))
      tool = snapshot.fetch(:tools).items.first
      assert_equal "lookup", tool.server_name
      assert_equal "integer", tool.parameters_schema.dig("properties", "options", "properties", "page", "type")
      assert_equal [ NativeMcpWire::RESOURCE.fetch("uri") ], snapshot.fetch(:resources).items.map(&:uri)
      assert_equal %w[server/discover tools/list prompts/list resources/list], @wire.methods_requested
      assert_equal 1, @wire.requests.pluck(:scope).uniq.size
      assert_equal({ error: "Could not connect to the MCP server" }, tool.call(query: "closed"))
      assert_equal %w[server/discover tools/list prompts/list resources/list], @wire.methods_requested
    end
  end

  test "keeps the configured endpoint on the Chat Completions protocol" do
    config = RubyLLM.config
    assert_respond_to config, :openai_protocol
    assert_equal :chat_completions, config.openai_protocol
    assert_equal ENV.fetch("LLM_MODEL"), config.default_model
    assert_equal ENV.fetch("EMBEDDING_MODEL"), config.default_embedding_model
    assert_equal ENV.fetch("AI_BASE_URL"), config.openai_api_base
    assert_equal ENV.fetch("AI_API_KEY"), config.openai_api_key
    assert_equal true, config.openai_use_system_role
  end

  test "a stateless construction and blank edit preserve static credentials without network" do
    @server.update_columns(auth_config: { "token" => "fixture-token", "api_key" => "fixture-api-key" },
      connection_config: { "headers" => { "authorization" => "saved-header", "X-Example" => "local-header" } })
    lookups = []
    with_singleton_replacement(UrlGuard, :resolve, ->(host) { lookups << host; [ IPAddr.new("93.184.216.34") ] }) do
      @wire.install(self) do
        assert @server.save_workspace({ notes: "edited" }, values: { token: "", api_key: "" })
        assert_empty lookups
        @server.with_client { |client| assert_kind_of McpServer::Client, client }
        assert_empty @wire.requests
      end
    end

    @wire.install(self) { assert @server.test_connection! }
    headers = @wire.requests.last.fetch(:headers)
    assert_equal "Bearer fixture-token", headers["Authorization"]
    assert_equal "local-header", headers["X-Example"]
    assert_nil headers["X-API-Key"]
    assert_equal({ "authorization" => "saved-header", "X-Example" => "local-header" }, @server.reload.headers)
    assert_equal "fixture-api-key", @server.api_key
  end

  test "legacy initialize can stream over Streamable HTTP and closes its session after tool execution" do
    @wire.legacy = @wire.stream = true
    @wire.install(self) do
      assert_equal({ success: true, result: "found" }, @server.execute_tool("lookup", {
        "query" => "opaque", "options" => { "page" => 2 }
      }))
    end

    assert_equal [ "server/discover", "initialize", "notifications/initialized", "tools/list", "tools/call", :delete ], @wire.methods_requested
    assert_equal "lookup", @wire.last_tool_call.fetch("name")
    assert_equal({ "query" => "opaque", "options" => { "page" => 2 } }, @wire.last_tool_call.fetch("arguments"))
    @wire.requests.drop(2).each do |request|
      assert_equal NativeMcpWire::LEGACY_SESSION, request.fetch(:headers)["Mcp-Session-Id"]
    end
    assert_equal 1, @wire.requests.pluck(:scope).uniq.size
  end

  test "chat receives structured output and native binary content without fetching resource links" do
    bytes = "\x00\xffpdf".b
    @wire.tool_result = { "structuredContent" => { "count" => 3 }, "content" => [
      { "type" => "text", "text" => "less authoritative" },
      { "type" => "resource_link", "name" => "link", "uri" => NativeMcpWire::RESOURCE.fetch("uri") },
      { "type" => "resource", "resource" => {
        "uri" => "file:///server/report", "mimeType" => "application/pdf", "blob" => Base64.strict_encode64(bytes)
      } }
    ] }
    @wire.install(self) do
      @server.with_client do |client|
        result = client.tools.first.call(query: "fixture")
        text, files = RubyLLM::Tool.split_result(result)
        assert_equal '{"count":3}', text
        assert_equal [ bytes ], files.map(&:content)
        assert_equal [ "application/pdf" ], files.map(&:mime_type)
        encoded = Base64.strict_encode64(bytes)
        parts = RubyLLM::Protocols::ChatCompletions::Media.render_content(text, files)
        assert_equal "data:application/pdf;base64,#{encoded}", parts[1].dig(:file, :file_data)
      end
    end
    assert_equal %w[server/discover tools/list tools/call], @wire.methods_requested
  end

  test "direct tool calls require a wire name and an advertised tool on every call" do
    @wire.install(self) do
      assert_equal({ error: "Tool not found: mcp_#{@server.id}_lookup" }, @server.execute_tool("mcp_#{@server.id}_lookup"))
      assert_equal({ success: true, result: "found" }, @server.execute_tool("lookup"))
      @wire.tools = []
      assert_equal({ error: "Tool not found: lookup" }, @server.execute_tool("lookup"))
    end
    assert_equal %w[server/discover tools/list server/discover tools/list tools/call server/discover tools/list], @wire.methods_requested
  end

  test "static public HTTP uses its explicit URL override and custom headers without global config changes" do
    adapter = RubyLLM.config.faraday_adapter
    @server.update!(url: "http://#{NativeMcpWire::HOST}/override", headers: { "X-Custom" => "kept" })
    @wire.install(self) { assert @server.test_connection! }
    assert_equal %w[http], @wire.requests.pluck(:scheme).uniq
    assert_equal [ "/override" ], @wire.requests.pluck(:path).uniq
    assert_equal "kept", @wire.requests.last.fetch(:headers)["X-Custom"]
    assert_nil @wire.requests.last.fetch(:headers)["Authorization"]
    assert_same adapter, RubyLLM.config.faraday_adapter
  end

  test "a legacy SSE record stays editable but cannot connect, execute, or be selected" do
    @server.update_columns(transport_type: "sse", endpoint: "https://mcp.example.test/sse",
      connection_config: { "url" => "https://mcp.example.test/old" })
    chat = chats(:picker_second_chat)
    chat.add_mcp_server(@server)
    stub_url_resolver([ "93.184.216.34" ])
    @wire.install(self) do
      assert_nil @server.client
      refute @server.test_connection!
      assert_equal({ error: "Server not ready" }, @server.execute_tool("lookup"))
      assert_equal [ :not_loaded ], @server.capability_snapshot.values.map(&:state).uniq
      assert_not_includes @second.mcp_servers.enabled.ready, @server
      assert_empty @wire.requests
    end
    assert_equal "ready", @server.reload.status
    assert chat.mcp_servers.exists?(@server.id)
    assert_raises(ActiveRecord::RecordNotFound) { chat.selected_mcp_servers([ @server.id ]) }
    assert @server.save_workspace({ notes: "still here", transport_type: "sse" }, values: {})
    assert @server.save_workspace({ transport_type: "streamable", endpoint: NativeMcpWire::URL }, values: {})
    assert_nil @server.url
    assert_equal NativeMcpWire::URL, @server.endpoint
    assert @server.status_disconnected?
    @wire.install(self) { assert @server.test_connection! }
    assert_equal [ "/mcp" ], @wire.requests.pluck(:path).uniq
    assert chat.mcp_servers.exists?(@server.id)
  ensure
    unstub_url_resolver
  end

  test "a malicious override is rejected before a transport is constructed" do
    @server.update_columns(connection_config: { "url" => "https://@mcp.example.test/mcp" })
    @wire.install(self) do
      assert_equal({ error: "Could not connect to the MCP server" }, @server.execute_tool("lookup"))
      assert_empty @wire.requests
    end
  end

  test "the native client reaches the real outbound guard before opening a private socket" do
    @server.update_columns(endpoint: "https://127.0.0.1/mcp")
    stub_url_resolver([ "127.0.0.1" ])
    with_singleton_replacement(Net::HTTP, :new, ->(*) { raise Minitest::Assertion, "private socket attempted" }) do
      assert_equal({ error: "Could not connect to the MCP server" }, @server.execute_tool("lookup"))
    end
    refute McpOutbound.active?
  ensure
    unstub_url_resolver
  end

  test "explicit resource reads send the URI only to the MCP server" do
    @wire.install(self) do
      assert_respond_to @server, :with_client
      @server.with_client do |client|
        uri = NativeMcpWire::RESOURCE.fetch("uri")
        assert_equal "MCP resource body", client.resource(uri).content
        assert_equal uri, @wire.requests.last.fetch(:rpc).dig("params", "uri")
      end
    end
    assert_equal %w[server/discover resources/read], @wire.methods_requested
  end

  test "an inline stdio command is never accepted, even with no arguments" do
    previous = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    @server.assign_attributes(transport_type: "stdio", command: "echo not-a-single-executable", args: [])
    refute @server.valid?
    assert_not_empty @server.errors[:command]
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous
  end

  test "stdio does not use shell builtins in place of a missing executable" do
    previous = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    @server.assign_attributes(transport_type: "stdio", command: "exit", args: [], env: { "PATH" => "/nonexistent" })
    assert_not @server.test_connection!
    assert_equal "Could not connect to the MCP server", @server.last_error
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous
  end

  test "native stdio passes argv and encrypted env intact and closes the peer" do
    previous = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    Tempfile.create([ "mcp-stdio-peer", ".rb" ]) do |peer|
      peer.write <<~'RUBY'
        require "json"
        STDOUT.sync = true
        STDIN.each_line do |line|
          request = JSON.parse(line)
          result = case request.fetch("method")
          when "server/discover"
            { supportedVersions: ["2026-07-28"], capabilities: { tools: {} } }
          when "tools/list"
            { tools: [{ name: "lookup", inputSchema: { type: "object" } }] }
          when "tools/call"
            { content: [{ type: "text", text: [ARGV.fetch(0), ENV.fetch("FIXTURE_SETTING")].join(" / ") }] }
          else abort "unexpected request"
          end
          puts JSON.generate(jsonrpc: "2.0", id: request.fetch("id"), result:)
        end
        File.write(ENV.fetch("CLOSED_PATH"), "closed")
      RUBY
      peer.flush
      Tempfile.create("mcp-stdio-closed") do |closed|
        @server.update!(transport_type: "stdio", connection_config: { command: RbConfig.ruby,
          args: [ peer.path, "one argument ; unchanged" ], env: { "FIXTURE_SETTING" => "from encrypted env", "CLOSED_PATH" => closed.path } })
        assert_equal({ success: true, result: "one argument ; unchanged / from encrypted env" }, @server.reload.execute_tool("lookup"))
        assert_equal "closed", closed.read
      end
    end
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous
  end

  test "a transport error is sanitized and closes an established session" do
    @wire.legacy = true
    @wire.fail_method = "tools/call"
    @wire.install(self) do
      assert_equal({ error: "Could not connect to the MCP server" }, @server.execute_tool("lookup"))
    end
    assert_equal [ "tools/call", :delete ], @wire.methods_requested.last(2)
  end

  test "a new turn binds prefixed tools in its account and closes after the last use even on failure" do
    @wire.legacy = true
    chat = chats(:picker_second_chat)
    chat.add_mcp_server(@server)
    bound = []
    chat.define_singleton_method(:with_tools) { |*tools| bound.replace(tools.compact) }

    @wire.install(self) do
      assert_respond_to chat, :with_mcp_tools
      assert_raises(RuntimeError, "a failure in the turn must still close the client") do
        chat.with_mcp_tools do
          assert_equal [ "mcp_#{@server.id}_lookup" ], bound.map(&:name)
          refute_includes @wire.methods_requested, :delete
          # RubyLLM may call a model tool in a different fiber.
          assert_equal "found", Fiber.new { bound.first.call(query: "opaque") }.resume
          raise "turn failed"
        end
      end
    end

    assert_empty bound
    assert_equal [ "tools/call", :delete ], @wire.methods_requested.last(2)
  end

  test "the API streaming callback runs before the native session closes" do
    @wire.legacy = true
    chat = chats(:picker_second_chat)
    chat.add_mcp_server(@server)
    bound = []
    chat.define_singleton_method(:with_tools) { |*tools| bound.replace(tools.compact) }
    chat.messages.create!(role: "assistant", content: "done")
    stub_chat_for_streaming(chat, chunks: [ ActiveSupport::TestCase::StreamChunk.new("done") ], stub_mcp: false)

    @wire.install(self) do
      message = chat.complete_with_nosia("question") do |chunk|
        assert_equal "done", chunk.content
        assert_equal "found", bound.fetch(0).call
        refute_includes @wire.methods_requested, :delete
      end
      assert_equal "done", message.content
    end
    assert_empty bound
    assert_equal [ "tools/call", :delete ], @wire.methods_requested.last(2)
  end

  test "stopping the UI stream closes the native session and clears the binding" do
    @wire.legacy = true
    chat = chats(:picker_second_chat)
    chat.add_mcp_server(@server)
    bound = []
    chat.define_singleton_method(:with_tools) { |*tools| bound.replace(tools.compact) }
    chat.define_singleton_method(:generation_stopped?) { true }
    stub_chat_for_streaming(chat, chunks: [ ActiveSupport::TestCase::StreamChunk.new("stopped") ], stub_mcp: false)

    @wire.install(self) { assert_nil chat.complete_with_nosia("question") }
    assert_empty bound
    assert_equal [ "tools/list", :delete ], @wire.methods_requested.last(2)
    refute_includes @wire.methods_requested, "tools/call"
  end
end
