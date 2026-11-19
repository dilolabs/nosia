require "test_helper"
require_relative "../support/chat_account_fixtures"
require_relative "../support/native_mcp_wire"

class McpServersControllerTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  class EndpointTool < MCP::Tool
    tool_name "endpoint_demo"
    description "keyword endpoint regression"
    input_schema(properties: { query: { type: "string" }, options: { type: "object", properties: { page: { type: "integer" } } } }, required: [ "query" ])

    def self.call(query:, options: {}, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: "#{query} page=#{options['page']} authorized=#{server_context[:api_key] == 'fake-key'}" } ])
    end
  end

  def setup
    @user = User.create!(email: "mcp@example.com", password: "testpassword123")
    @account = Account.create!(name: "MCP Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    unstub_url_resolver
  end

  def make_server(account: @account, name: "Demo")
    ActsAsTenant.current_tenant = account
    server = account.mcp_servers.create!(name: name, transport_type: "local")
    ActsAsTenant.current_tenant = @account
    server
  end

  test "index exposes details instead of a competing destructive row action" do
    server = make_server
    get mcp_servers_url
    assert_response :success
    assert_select "[data-mcp-row] a[href=?]", mcp_server_path(server)
    assert_select "[data-mcp-row] form input[name=_method][value=delete]", count: 0
  end

  test "show renders a Delete button" do
    server = make_server
    get mcp_server_url(server)
    assert_response :success
    assert_select "[data-mcp-danger] form[action=?]", mcp_server_path(server) do
      assert_select "input[name=_method][value=delete]"
      assert_select "button", text: /Delete/
    end
  end

  test "destroy deletes the server and redirects to the index" do
    server = make_server
    assert_difference -> { @account.mcp_servers.count }, -1 do
      delete mcp_server_url(server)
    end
    assert_redirected_to mcp_servers_url
    follow_redirect!
    assert_match(/deleted/i, response.body)
  end

  test "destroy is scoped to the current account" do
    other_user = User.create!(email: "other@example.com", password: "testpassword123")
    other_account = Account.create!(name: "Other Account", owner: other_user)
    other_server = make_server(account: other_account, name: "Other")

    assert_no_difference -> { McpServer.unscoped.count } do
      delete mcp_server_url(other_server)
    end
    assert_response :not_found
    assert McpServer.unscoped.exists?(other_server.id)
  end

  test "execute_tool normalizes JSON object arguments at the boundary without permitting record attributes" do
    registrations = Engines::Registry.all
    Engines::Registry.register(Engines::Registration.new(id: "endpoint-test", name: "Endpoint", icon: "test", description: "test",
      required_config: [], tool_classes: [ EndpointTool ], health_check: ->(_) { }))
    server = @account.mcp_servers.create!(name: "Endpoint", transport_type: "local", status: "ready",
      metadata: { engine: "endpoint-test" }, auth_config: { api_key: "fake-key" })

    post execute_tool_mcp_server_url(server), as: :json, params: {
      tool_name: "endpoint_demo", arguments: { query: "https://not-a-source.example", options: { page: 2 } },
      mcp_server: { name: "changed", auth_config: { api_key: "attacker" } }
    }
    assert_response :success
    assert_equal({ "success" => true, "result" => "https://not-a-source.example page=2 authorized=true" }, response.parsed_body)
    assert_equal "Endpoint", server.reload.name
    assert_equal "fake-key", server.api_key
  ensure
    Engines::Registry.clear
    registrations&.each { |registration| Engines::Registry.register(registration) }
  end

  test "execute_tool rejects non-object JSON arguments" do
    server = make_server
    [ [ "not", "keywords" ], "not an object", false, 5 ].each do |arguments|
      post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "unused", arguments: arguments }
      assert_response :bad_request
      assert_equal "Tool arguments must be a JSON object", response.parsed_body.fetch("error")
    end
  end

  test "execute_tool is scoped to the current account" do
    other_user = User.create!(email: "tool-other@example.com", password: "testpassword123")
    other_account = Account.create!(name: "Other tools", owner: other_user)
    server = make_server(account: other_account)
    post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "unused", arguments: {} }
    assert_response :not_found
  end

  %w[text structured].each do |mode|
    test "execute_tool serializes remote binary PNG and audio safely with #{mode}" do
      png = "\x89PNG\r\n\x1a\n\x00\xff".b
      audio = "RIFF\x00\xff\x80WAVE".b
      result = { "content" => [
        { "type" => "text", "text" => "before" },
        { "type" => "image", "mimeType" => "image/png", "data" => Base64.strict_encode64(png) },
        { "type" => "audio", "mimeType" => "audio/wav", "data" => Base64.strict_encode64(audio) },
        { "type" => "text", "text" => "after" }
      ] }
      if mode == "structured"
        result["structuredContent"] = { "count" => 3 }
      end
      with_remote_tool_server(result) do |server, wire|
        # The model/LLM boundary must keep real attachments, not JSON hashes.
        model_result = server.execute_tool("lookup", { "query" => "opaque query" })
        assert_equal true, model_result.fetch(:success)
        attachments = model_result.fetch(:result).grep(RubyLLM::Attachment)
        assert_equal [ png, audio ], attachments.map(&:content)

        post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "lookup", arguments: { query: "opaque query" } }
        assert_response :success
        body = response.parsed_body
        assert_equal true, body.fetch("success")
        content = body.fetch("result")
        if mode == "structured"
          assert_equal({ "count" => 3 }, JSON.parse(content.first))
        else
          assert_equal "before\nafter", content.first
        end
        assert_equal [ "image", "audio" ], content.drop(1).map { |file| file.fetch("type") }
        assert_equal [ "image/png", "audio/wav" ], content.drop(1).map { |file| file.fetch("mimeType") }
        assert_equal [ png, audio ], content.drop(1).map { |file| Base64.strict_decode64(file.fetch("data")) }
        assert_equal %w[image.png audio], content.drop(1).pluck("filename")
        content.drop(1).each do |file|
          assert_equal %w[data filename mimeType type], file.keys.sort
        end
        assert_not_includes response.body, "StringIO"
        assert_equal %w[server/discover tools/list tools/call] * 2, wire.methods_requested
        assert_equal "lookup", wire.last_tool_call.fetch("name")
        assert_equal({ "query" => "opaque query" }, wire.last_tool_call.fetch("arguments"))
      end
    end
  end

  test "execute_tool keeps remote error hash semantics in JSON" do
    with_remote_tool_server({ "content" => [ { "type" => "text", "text" => "failed" } ], "isError" => true }) do |server, _wire|
      post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "lookup", arguments: { query: "opaque" } }
      assert_response :success
      assert_equal({ "success" => true, "result" => { "error" => "Tool execution error: failed" } }, response.parsed_body)
    end
  end

  [ false, true ].each do |stream|
    test "execute_tool keeps a sanitized nested error for HTTP 200 JSON-RPC errors#{' in SSE' if stream}" do
      with_remote_tool_server({}) do |server, wire|
        wire.fail_method = "tools/call"
        wire.stream = stream
        post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "lookup" }

        assert_response :success
        assert_equal({ "success" => true, "result" => { "error" => "Tool execution error: The MCP server rejected the tool call" } }, response.parsed_body)
        refute_includes response.body, NativeMcpWire::PRIVATE_MARKER
        assert_equal %w[server/discover tools/list tools/call], wire.methods_requested
      end
    end
  end

  test "execute_tool redacts configured secrets from native isError tool results" do
    result = { "isError" => true, "content" => [ { "type" => "text", "text" => "Rejected #{NativeMcpWire::PRIVATE_MARKER}" } ] }
    with_remote_tool_server(result) do |server, _wire|
      server.update!(token: NativeMcpWire::PRIVATE_MARKER)
      post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "lookup" }

      assert_response :success
      assert_equal({ "success" => true, "result" => { "error" => "Tool execution error: Rejected [FILTERED]" } }, response.parsed_body)
      refute_includes response.body, NativeMcpWire::PRIVATE_MARKER
    end
  end

  test "execute_tool uses structured JSON when no attachments accompany it" do
    with_remote_tool_server({ "content" => [ { "type" => "text", "text" => "less authoritative" } ], "structuredContent" => { "count" => 3 } }) do |server, _wire|
      post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "lookup" }
      assert_response :success
      assert_equal({ "success" => true, "result" => '{"count":3}' }, response.parsed_body)
    end
  end

  test "execute_tool falls back to a neutral filename for a binary attachment without one" do
    with_remote_tool_server({ "content" => [] }) do |server, _wire|
      client = Object.new
      client.define_singleton_method(:call) do |*|
        RubyLLM::Attachment.new(StringIO.new("fixture bytes"), filename: "", mime_type: "application/pdf")
      end
      client.define_singleton_method(:close) { }
      with_singleton_replacement(McpServer::Client, :new, ->(*) { client }) do
        post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "lookup" }
      end
      assert_response :success
      assert_equal({ "type" => "pdf", "data" => Base64.strict_encode64("fixture bytes"),
        "mimeType" => "application/pdf", "filename" => "mcp-attachment" }, response.parsed_body.fetch("result"))
    end
  end

  test "execute_tool never introspects unsupported IO values for JSON" do
    with_remote_tool_server({ "content" => [] }) do |server, _wire|
      io = StringIO.new("not JSON content")
      serialized = false
      io.define_singleton_method(:as_json) { |*| serialized = true; { internals: "must not be serialized" } }
      client = Object.new
      client.define_singleton_method(:call) { |*| { nested: [ io ] } }
      client.define_singleton_method(:close) { }
      with_singleton_replacement(McpServer::Client, :new, ->(*) { client }) do
        assert_raises(TypeError) do
          post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "unsupported_io", arguments: {} }
        end
      end
      assert_not serialized
    end
  end

  test "execute_tool rejects unsupported object keys without converting them to strings" do
    with_remote_tool_server({ "content" => [] }) do |server, _wire|
      key = Object.new
      key.define_singleton_method(:to_s) { raise Minitest::Assertion, "JSON inspected an unsupported key" }
      client = Object.new
      client.define_singleton_method(:call) { |*| { key => true } }
      client.define_singleton_method(:close) { }
      with_singleton_replacement(McpServer::Client, :new, ->(*) { client }) do
        assert_raises(TypeError) do
          post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "unsupported_key" }
        end
      end
    end
  end

  private
    def with_remote_tool_server(result)
      server = @account.mcp_servers.create!(name: "Remote binary", transport_type: "streamable", status: "ready", endpoint: NativeMcpWire::URL)
      wire = NativeMcpWire.new
      wire.tool_result = result
      wire.install(self) { yield server, wire }
    end
end
