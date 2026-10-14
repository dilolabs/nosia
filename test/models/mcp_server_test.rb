require "test_helper"

class McpServerTest < ActiveSupport::TestCase
  class KeywordTool < RubyLLM::Tool
    def name
      "keyword"
    end

    def execute(query:, options: {})
      { query: query, options: options }
    end
  end

  def setup
    @user = User.create!(email: "ms@example.com", password: "testpassword123")
    @account = Account.create!(name: "MS Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    unstub_url_resolver
    ENV["MCP_STDIO_ENABLED"] = @previous_stdio_env
  end

  test "stdio transport is rejected unless enabled for the deployment" do
    ENV.delete("MCP_STDIO_ENABLED")

    server = @account.mcp_servers.new(
      name: "shell", transport_type: "stdio", command: "curl", args: [ "https://evil.example" ]
    )

    assert_not server.valid?
    assert_not_empty server.errors[:transport_type]
  end

  test "stdio transport is allowed when MCP_STDIO_ENABLED is set" do
    @previous_stdio_env = nil
    ENV["MCP_STDIO_ENABLED"] = "true"

    server = @account.mcp_servers.new(name: "local-tool", transport_type: "stdio", command: "npx")

    assert server.valid?
  end

  test "streamable endpoints on private hosts are rejected" do
    stub_url_resolver([ "127.0.0.1" ])

    server = @account.mcp_servers.new(
      name: "internal", transport_type: "streamable", endpoint: "http://127.0.0.1:9222/mcp"
    )

    assert_not server.valid?
    assert_not_empty server.errors[:endpoint]
  end

  test "sse endpoints on public hosts are accepted" do
    stub_url_resolver([ "93.184.216.34" ])

    server = @account.mcp_servers.new(
      name: "public", transport_type: "sse", endpoint: "https://mcp.example.com/sse"
    )

    assert server.valid?
  end

  test "scheme-less endpoints are validated as https" do
    stub_url_resolver([ "10.1.2.3" ])

    server = @account.mcp_servers.new(
      name: "bare", transport_type: "streamable", endpoint: "10.1.2.3:9222/mcp"
    )

    assert_not server.valid?
    assert_not_empty server.errors[:endpoint]
  end

  test "remote execution keeps hash arguments and recoverable error contracts" do
    server = @account.mcp_servers.new(name: "remote", transport_type: "sse", status: "ready")
    server.define_singleton_method(:tools) { [ KeywordTool.new ] }
    assert_equal({ success: true, result: { query: "file:///not-a-source", options: { "limit" => 2 } } },
      server.execute_tool("keyword", { "query" => "file:///not-a-source", "options" => { "limit" => 2 } }))
    assert_equal({ success: true, result: { error: "Invalid tool arguments: missing keyword: query" } }, server.execute_tool("keyword"))
    assert_equal({ error: "Tool not found: missing" }, server.execute_tool("missing"))
  end

  test "client config preserves stdio command args env and HTTP URL headers and auth" do
    original_client = RubyLLM::MCP.method(:client)
    calls = []
    RubyLLM::MCP.define_singleton_method(:client) { |**options| calls << options; Object.new }
    begin
      server = @account.mcp_servers.new(name: "stdio", transport_type: "stdio", connection_config: {
        command: "ruby", args: [ "server.rb" ], env: { "TOOL_MODE" => "test" }
      })
      assert server.client
      assert_equal({ command: "ruby", args: [ "server.rb" ], env: { "TOOL_MODE" => "test" } }, calls.last.fetch(:config))
      %w[sse streamable].each do |type|
        server = @account.mcp_servers.new(name: type, transport_type: type, endpoint: "https://mcp.example.com/mcp",
          connection_config: { headers: { "X-Custom" => "kept" } }, auth_config: { token: "fake-token" })
        assert server.client
        assert_equal type.to_sym, calls.last.fetch(:transport_type)
        assert_equal({ url: "https://mcp.example.com/mcp", headers: { "X-Custom" => "kept", "Authorization" => "Bearer fake-token" } }, calls.last.fetch(:config))
      end
      server = @account.mcp_servers.new(name: "key", transport_type: "streamable", endpoint: "https://mcp.example.com/mcp", auth_config: { api_key: "fake-key" })
      assert server.client
      assert_equal "fake-key", calls.last.dig(:config, :headers, "X-API-Key")
    ensure
      RubyLLM::MCP.define_singleton_method(:client, original_client)
    end
  end
end
