require "test_helper"
require "faraday/adapter/test"
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

  test "stale static test and disconnect cannot write to a connector already switched to OAuth" do
    stale = McpServer.find(@server.id)
    @server.update!(auth_mode: "oauth")
    attributes = @server.reload.attributes

    @wire.install(self) { refute stale.test_connection! }
    assert_empty @wire.requests
    assert_equal attributes, @server.reload.attributes
    refute stale.disconnect!
    assert_equal attributes, @server.reload.attributes
  end

  test "name and notes changes during a static test do not strand readiness in connecting" do
    @server.update_columns(status: "ready")
    original_reply = @wire.method(:reply)
    server_id = @server.id
    with_singleton_replacement(@wire, :reply, ->(env) {
      if JSON.parse(env.body)["method"] == "tools/list"
        McpServer.find(server_id).update!(name: "New label", notes: "Edited during test")
      end
      original_reply.call(env)
    }) do
      @wire.install(self) { assert @server.test_connection! }
    end

    assert @server.reload.status_ready?
    assert_equal "New label", @server.name
    assert_equal "Edited during test", @server.notes
    assert_equal "lookup", @server.tools_cache.sole.fetch("name")
  end

  test "editing the raw endpoint behind a static override does not supersede an in-flight test" do
    @server.update!(url: NativeMcpWire::URL)
    before = @server.connection_revision
    original_reply = @wire.method(:reply)
    server_id = @server.id
    with_singleton_replacement(@wire, :reply, ->(env) {
      if JSON.parse(env.body)["method"] == "tools/list"
        McpServer.find(server_id).save_workspace({ endpoint: "https://mcp.example.test/new-label" }, values: {})
      end
      original_reply.call(env)
    }) do
      @wire.install(self) { assert @server.test_connection! }
    end

    assert_equal "https://mcp.example.test/new-label", @server.reload.endpoint
    assert_equal NativeMcpWire::URL, @server.effective_endpoint
    assert_equal before, @server.connection_revision
    assert @server.status_ready?
    assert_equal "lookup", @server.tools_cache.sole.fetch("name")
  end

  test "a newer static test wins even if the clock is unchanged and the older result arrives last" do
    server_id = @server.id
    old_wire = @wire
    latest_wire = NativeMcpWire.new
    latest_wire.tools = [ NativeMcpWire::TOOL.merge("name" => "latest") ]
    original_reply = old_wire.method(:reply)
    install_for = self
    travel_to(Time.current) do
      @server.update_columns(metadata: { tools_cache: [ { name: "latest", description: NativeMcpWire::TOOL.fetch("description") } ],
        last_test_at: Time.current.iso8601 })
      with_singleton_replacement(old_wire, :reply, ->(env) {
        if JSON.parse(env.body)["method"] == "tools/list"
          latest_wire.install(install_for) do
            raise "Expected latest test to complete" unless McpServer.find(server_id).test_connection!
          end
        end
        original_reply.call(env)
      }) do
        old_wire.install(self) { refute @server.test_connection! }
      end
    end
    assert_equal "latest", @server.reload.tools_cache.sole.fetch("name")
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

  test "the Chat Completions payload fills empty properties on object schemas without imposing constraints" do
    input_schema = {
      "type" => "object",
      "additionalProperties" => {
        "type" => "array", "items" => { "anyOf" => [
          { "type" => "object", "description" => "Free-form object", "examples" => [ { "type" => "object" } ] },
          { "type" => "object", "properties" => { "value" => { "type" => "object" } }, "required" => [ "value" ] },
          { "type" => "string" }
        ] }
      },
      "$defs" => { "entry" => { "type" => [ "object", "null" ] } }
    }
    announced = input_schema.deep_dup
    @wire.tools = [ NativeMcpWire::TOOL.merge("inputSchema" => input_schema) ]

    @wire.install(self) do
      @server.with_client do |client|
        schema = rendered_tool_parameters(client.tools.fetch(0))
        assert_equal({}, schema["properties"])
        assert_not schema.key?("required"), "Normalizing the root must not require argument keys"
        variants = schema.dig("additionalProperties", "items", "anyOf")
        assert_equal({ "type" => "object", "description" => "Free-form object",
          "examples" => [ { "type" => "object" } ], "properties" => {} }, variants.fetch(0))
        assert_equal({ "type" => "object", "properties" => { "value" => { "type" => "object", "properties" => {} } },
          "required" => [ "value" ] }, variants.fetch(1))
        assert_equal({ "type" => "string" }, variants.fetch(2))
        assert_equal({ "type" => [ "object", "null" ], "properties" => {} }, schema.dig("$defs", "entry"))
      end
    end
    assert_equal announced, @wire.tools.first.fetch("inputSchema")
    assert_equal %w[server/discover tools/list], @wire.methods_requested
  end

  %i[workspace model].each do |boundary|
    test "#{boundary} rejects unsolicited tasks on native static Streamable HTTP" do
      token = "fixture-static-token"
      @server.update!(token:)
      @server.update_columns(status: "ready")
      @wire.legacy = @wire.stream = true
      @wire.tool_result = NativeMcpWire::UNSOLICITED_TASK.merge("statusMessage" => "#{token} #{NativeMcpWire::PRIVATE_MARKER}")

      @wire.install(self) { assert_unsolicited_task_rejected(boundary, secret: token) }
      assert_equal [ "server/discover", "initialize", "notifications/initialized", "tools/list", "tools/call", :delete ],
        @wire.methods_requested
    end

    test "#{boundary} rejects unsolicited tasks on enabled native stdio" do
      with_stdio_peer("unsolicited_task") do |trace|
        assert_unsolicited_task_rejected(boundary)
        assert_equal %w[server/discover tools/list tools/call], File.readlines(trace, chomp: true)
      end
    end

    test "#{boundary} rejects a string where the advertised output schema expects an integer" do
      @wire.tools = [ NativeMcpWire::TOOL.merge("outputSchema" => {
        "type" => "object", "properties" => { "count" => { "$ref" => "#/$defs/count" } }, "required" => [ "count" ],
        "$defs" => { "count" => { "type" => "integer" } }
      }) ]
      @wire.tool_result = { "structuredContent" => { "count" => NativeMcpWire::PRIVATE_MARKER }, "content" => [
        { "type" => "image", "mimeType" => "image/png", "data" => Base64.strict_encode64("fixture image") }
      ] }

      @wire.install(self) do
        error = { error: "Structured output is not valid" }
        assert_equal boundary_result(boundary, error), run_native_tool(boundary)

        @wire.tool_result.fetch("structuredContent")["count"] = 3
        result = run_native_tool(boundary)
        content = boundary == :workspace ? result.fetch(:result) : result
        text, attachments = RubyLLM::Tool.split_result(content)
        assert_equal({ "count" => 3 }, JSON.parse(text))
        assert_equal [ "fixture image" ], attachments.map(&:content)
      end
      assert_equal %w[server/discover tools/list tools/call] * 2, @wire.methods_requested
    end
  end

  test "advertised output schemas preserve valid primitive values and do not reject text-only or isError results" do
    @wire.tools = [ NativeMcpWire::TOOL.merge("outputSchema" => { "type" => [ "boolean", "null" ] }) ]
    @wire.install(self) do
      [ false, nil ].each do |value|
        @wire.tool_result = { "structuredContent" => value, "content" => [ { "type" => "text", "text" => "less authoritative" } ] }
        assert_equal({ success: true, result: JSON.generate(value) }, @server.execute_tool("lookup"))
      end
      @wire.tool_result = { "content" => [ { "type" => "text", "text" => "Legacy text-only response" } ] }
      assert_equal "Legacy text-only response", run_native_tool(:model)

      @wire.tool_result = { "isError" => true, "structuredContent" => 2 }
      assert_equal({ success: true, result: { error: "Tool execution error: 2" } }, @server.execute_tool("lookup"))
    end
  end

  test "output schemas stay with the tools that advertised them across catalog pages" do
    @wire.tools = [ NativeMcpWire::TOOL.merge("name" => "other", "outputSchema" => { "type" => "string" }) ]
    @wire.next_tools_page = [ NativeMcpWire::TOOL.merge("outputSchema" => { "type" => "integer" }) ]
    @wire.tool_result = { "structuredContent" => "fixture text" }
    @wire.install(self) do
      @server.with_client do |client|
        tools = client.tools.index_by(&:server_name)
        assert_equal '"fixture text"', tools.fetch("other").call
        assert_equal({ error: "Structured output is not valid" }, tools.fetch("lookup").call)
      end
    end
    assert_equal %w[server/discover tools/list tools/list tools/call tools/call], @wire.methods_requested
  end

  test "unavailable external output schema references fail closed without fetching or disclosing them" do
    @wire.tools = [ NativeMcpWire::TOOL.merge("outputSchema" => { "$ref" => "https://not-the-mcp-host.test/fixture-schema" }) ]
    @wire.tool_result = { "structuredContent" => { "count" => 3 } }
    @wire.install(self) do
      with_singleton_replacement(Net::HTTP, :new, ->(*) { raise Minitest::Assertion, "Output schema opened an HTTP connection" }) do
        assert_equal({ success: true, result: { error: "Structured output is not valid" } }, @server.execute_tool("lookup"))
      end
    end
    assert_equal %w[server/discover tools/list tools/call], @wire.methods_requested
  end

  %w[image audio resource].each do |type|
    test "native #{type} tool attachments reject malformed base64 on both boundaries" do
      malformed = "YWJj #{NativeMcpWire::PRIVATE_MARKER}!"
      block = case type
      when "image" then { "type" => type, "data" => malformed, "mimeType" => "image/png" }
      when "audio" then { "type" => type, "data" => malformed, "mimeType" => "audio/wav" }
      else { "type" => type, "resource" => { "uri" => "file:///fixture/report.pdf", "blob" => malformed, "mimeType" => "application/pdf" } }
      end
      @wire.tool_result = { "structuredContent" => { "count" => 3 }, "content" => [ block ] }

      @wire.install(self) do
        error = { error: "Tool execution error: Invalid attachment data" }
        assert_equal error, run_native_tool(:model)
        assert_equal({ success: true, result: error }, run_native_tool(:workspace))
      end
    end
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

  test "chat uses safe provider names for dotted and long MCP names without changing the wire names" do
    long_stem = "a" * 72
    names = [ "search.issues", "search-issues", "search_issues", "#{long_stem}-first", "#{long_stem}-second" ]
    @wire.tools = names.map { |name| NativeMcpWire::TOOL.merge("name" => name) }
    peer = @server.dup
    peer.name = "Second connector at the same endpoint"
    peer.save!
    chat = chats(:picker_second_chat)
    chat.add_mcp_server(@server)
    chat.add_mcp_server(peer)
    chat.with_model(chat.model_id, provider: :openai, assume_model_exists: true)

    @wire.install(self) do
      chat.with_mcp_tools do
        registrations = chat.to_llm.tools
        assert_equal names.size * 2, registrations.size
        registrations.each do |key, tool|
          assert_match(/\A[A-Za-z0-9_-]{1,64}\z/, key.to_s)
          assert_includes names, tool.server_name
        end
        [ @server, peer ].each do |server|
          prefix = "mcp_#{server.id}_"
          assert_equal names.size, registrations.keys.count { |key| key.to_s.start_with?(prefix) }
          assert_equal "search_issues", registrations.fetch(:"#{prefix}search_issues").server_name
          tool = registrations.values.find { |entry| entry.name.start_with?(prefix) && entry.server_name == "search.issues" }
          assert_equal "found", tool.call(query: "opaque")
          assert_equal "search.issues", @wire.last_tool_call.fetch("name")
        end
      end

      assert_equal({ success: true, result: "found" }, @server.execute_tool("#{long_stem}-first"))
      assert_equal "#{long_stem}-first", @wire.last_tool_call.fetch("name")
    end
  end

  test "a safe raw name matching a synthesized name keeps its spelling regardless of catalog order" do
    raw_name = "search.issues"
    definition = NativeMcpWire::TOOL.merge("name" => raw_name)
    @wire.tools = [ definition ]
    prefix = "mcp_#{@server.id}_"
    @wire.install(self) do
      original = provider_tool_names(@server).fetch(raw_name)
      assert_match(/\A[A-Za-z0-9_-]{1,64}\z/, original)
      raw_safe_name = original.delete_prefix(prefix)
      @wire.tools << NativeMcpWire::TOOL.merge("name" => raw_safe_name)

      colliding = provider_tool_names(@server)
      assert_equal original, colliding.fetch(raw_safe_name)
      refute_equal original, colliding.fetch(raw_name)
      assert_match(/\A[A-Za-z0-9_-]{1,64}\z/, colliding.fetch(raw_name))

      @wire.tools.reverse!
      assert_equal colliding, provider_tool_names(@server)
    end
  end

  test "static HTTPS uses its explicit URL override and custom headers without global config changes" do
    adapter = RubyLLM.config.faraday_adapter
    @server.update!(url: "https://#{NativeMcpWire::HOST}/override", headers: { "X-Custom" => "kept" })
    @wire.install(self) { assert @server.test_connection! }
    assert_equal %w[https], @wire.requests.pluck(:scheme).uniq
    assert_equal [ "/override" ], @wire.requests.pluck(:path).uniq
    assert_equal "kept", @wire.requests.last.fetch(:headers)["X-Custom"]
    assert_nil @wire.requests.last.fetch(:headers)["Authorization"]
    assert_same adapter, RubyLLM.config.faraday_adapter
  end

  test "a stale static server and its retained client cannot send headers after OAuth mode is saved" do
    @server.update!(token: "fixture-static-token")
    stale = McpServer.find(@server.id)
    retained = stale.client
    @server.update!(auth_mode: "oauth")

    @wire.install(self) do
      [ retained, stale.client ].compact.each do |client|
        assert_raises(McpServer::Client::Error) { client.tools }
      ensure
        client.close
      end
    end
    assert_empty @wire.requests
    refute McpOutbound.active?
  end

  test "the real guarded adapter denies stale static requests before constructing a socket" do
    @server.update!(token: "fixture-static-token")
    retained = @server.client
    attempts = []
    constructor = ->(*args) do
      attempts << args
      raise Errno::ECONNREFUSED
    end

    with_singleton_replacement(UrlGuard, :resolve, ->(_) { [ IPAddr.new("93.184.216.34") ] }) do
      with_singleton_replacement(Net::HTTP, :new, constructor) do
        assert_raises(McpServer::Client::Error) { retained.tools }
        assert_equal [ [ NativeMcpWire::HOST, 443, nil ] ], attempts
        @server.update!(auth_mode: "oauth")

        error = assert_raises(McpServer::Client::Error) { retained.tools }
        assert_instance_of McpServer::Client::Error, error
        assert_equal "Could not connect to the MCP server", error.message
        assert_nil error.cause
        assert_equal [ [ NativeMcpWire::HOST, 443, nil ] ], attempts
      end
    end
  ensure
    retained&.close
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
    @server.update!(transport_type: "stdio", command: "exit", args: [], env: { "PATH" => "/nonexistent" })
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
        @server.update_columns(status: "ready")
        assert_equal({ success: true, result: "one argument ; unchanged / from encrypted env" }, @server.reload.execute_tool("lookup"))
        assert_equal "closed", closed.read
      end
    end
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous
  end

  test "a transport error is sanitized and closes an established session" do
    @wire.legacy = true
    @wire.unavailable_method = "tools/call"
    @wire.install(self) do
      assert_equal({ error: "Could not connect to the MCP server" }, @server.execute_tool("lookup"))
    end
    assert_equal [ "tools/call", :delete ], @wire.methods_requested.last(2)
  end

  test "a native stdio JSON-RPC tool error keeps the sanitized nested envelope" do
    previous_logger = RubyLLM.config.logger
    output = StringIO.new
    RubyLLM.config.logger = Logger.new(output, level: Logger::DEBUG)
    with_stdio_peer("tool_error") do |trace|
      assert_equal({ success: true, result: { error: "Tool execution error: The MCP server rejected the tool call" } },
        @server.execute_tool("lookup"))
      assert_equal %w[server/discover tools/list tools/call], File.readlines(trace, chomp: true)
      refute_includes output.string, NativeMcpWire::PRIVATE_MARKER
    end
  ensure
    RubyLLM.config.logger = previous_logger
  end

  %w[disconnect timeout discovery_error].each do |mode|
    test "native stdio #{mode} is a connection failure, not a tool rejection" do
      previous_timeout = RubyLLM.config.request_timeout
      RubyLLM.config.request_timeout = 0.5
      with_stdio_peer(mode) do |trace|
        assert_equal({ error: "Could not connect to the MCP server" }, @server.execute_tool("lookup"))
        expected = mode == "discovery_error" ? %w[server/discover] : %w[server/discover tools/list tools/call]
        assert_equal expected, File.readlines(trace, chomp: true)
      end
    ensure
      RubyLLM.config.request_timeout = previous_timeout
    end
  end

  test "native stdio JSON-RPC reinitialization errors after a peer exits remain connection failures" do
    with_stdio_peer("reinitialize_error") do |trace|
      popen = Open3.method(:popen2)
      children = []
      with_singleton_replacement(Open3, :popen2, ->(*args, **options) {
        popen.call(*args, **options).tap { |_, _, child| children << child }
      }) do
        @server.with_client do |client|
          assert_equal [ "lookup" ], client.tools.map(&:server_name)
          assert children.fetch(0).join(5), "The legacy peer must exit before its next tool call"
          error = assert_raises(McpServer::Client::Error) { client.call("lookup", {}) }
          assert_equal "Could not connect to the MCP server", error.message
        end
      end
      assert_equal %w[server/discover initialize notifications/initialized tools/list initialize], File.readlines(trace, chomp: true)
    end
  end

  test "a timed out tool request reports a connection failure" do
    @wire.timeout_method = "tools/call"
    @wire.install(self) do
      assert_equal({ error: "Could not connect to the MCP server" }, @server.execute_tool("lookup"))
    end
    assert_equal "tools/call", @wire.methods_requested.last
  end

  test "a JSON-RPC listing error is not reported as a tool rejection" do
    @wire.fail_method = "tools/list"
    @wire.install(self) do
      assert_equal({ error: "Could not connect to the MCP server" }, @server.execute_tool("lookup"))
    end
    assert_equal %w[server/discover tools/list], @wire.methods_requested
  end

  test "a JSON-RPC reinitialization error after a session expires is not itself a tool rejection" do
    @wire.legacy = @wire.fail_reinitialize = true
    @wire.install(self) do
      assert_equal({ error: "Could not connect to the MCP server" }, @server.execute_tool("lookup"))
    end
    assert_equal [ "tools/call", "initialize", :delete ], @wire.methods_requested.last(3)
  end

  test "a JSON-RPC tool rejection on a resumed legacy stream keeps the nested error" do
    @wire.legacy = @wire.resume_tool_error = true
    @wire.install(self) do
      assert_equal({ success: true, result: { error: "Tool execution error: The MCP server rejected the tool call" } },
        @server.execute_tool("lookup"))
    end
    assert_equal [ "tools/call", :get, :delete ], @wire.methods_requested.last(3)
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

  private
    def assert_unsolicited_task_rejected(boundary, secret: nil)
      NativeMcpWire.assert_task_boundary(self, secret:) do
        if boundary == :workspace
          error = { error: "Tool execution error: The MCP server rejected the tool call" }
          assert_equal({ success: true, result: error }, @server.execute_tool("lookup"))
        else
          chat = chats(:picker_second_chat)
          chat.user.update!(admin: true) if @server.stdio?
          chat.add_mcp_server(@server)
          chat.with_model(chat.model_id, provider: :openai, assume_model_exists: true)
          turn = chat.with_mcp_tools do
            assert_equal({ error: "Could not connect to the MCP server" }, chat.to_llm.tools.values.sole.call)
            :completed
          end
          assert_equal :completed, turn
        end
      end
    end

    def rendered_tool_parameters(tool)
      request = nil
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/v1/chat/completions") do |env|
          request = JSON.parse(env.body)
          body = { model: "fixture-model", choices: [ { message: { role: "assistant", content: "Ready" }, finish_reason: "stop" } ] }
          [ 200, { "Content-Type" => "application/json" }, JSON.generate(body) ]
        end
      end
      adapter = Class.new(Faraday::Adapter::Test) do
        define_method(:initialize) { |app, **| super(app, stubs, &nil) }
      end
      context = RubyLLM.context do |config|
        config.faraday_adapter = adapter
        config.openai_api_base = "http://127.0.0.1:9/v1"
      end
      chat = context.chat(model: "fixture-model", provider: :openai, assume_model_exists: true).with_tools(tool)
      assert_equal "Ready", chat.ask("Which tool can you call?").content
      stubs.verify_stubbed_calls
      request.fetch("tools").fetch(0).fetch("function").fetch("parameters")
    end

    def run_native_tool(boundary)
      if boundary == :workspace
        @server.execute_tool("lookup")
      else
        @server.with_client { |client| client.tools.fetch(0).call }
      end
    end

    def boundary_result(boundary, result)
      boundary == :workspace ? { success: true, result: result } : result
    end

    def with_stdio_peer(mode)
      previous = ENV["MCP_STDIO_ENABLED"]
      ENV["MCP_STDIO_ENABLED"] = "true"
      Tempfile.create("mcp-stdio-requests") do |trace|
        @server.update!(transport_type: "stdio", connection_config: { command: RbConfig.ruby,
          args: [ Rails.root.join("test/support/native_mcp_stdio_peer.rb").to_s, mode, trace.path ] })
        @server.update_columns(status: "ready")
        yield trace.path
      end
    ensure
      ENV["MCP_STDIO_ENABLED"] = previous
    end

    def provider_tool_names(server)
      server.with_client { |client| client.tools.to_h { |tool| [ tool.server_name, tool.name ] } }
    end
end
