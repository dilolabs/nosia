require "test_helper"
require_relative "../support/chat_account_fixtures"

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

  test "a new server cannot select legacy SSE even with a public endpoint" do
    server = @account.mcp_servers.new(
      name: "public", transport_type: "sse", endpoint: "https://mcp.example.com/sse"
    )

    refute server.valid?
    assert_not_empty server.errors[:transport_type]
  end

  test "scheme-less endpoints are rejected before constructing a client" do
    stub_url_resolver([ "10.1.2.3" ])

    server = @account.mcp_servers.new(
      name: "bare", transport_type: "streamable", endpoint: "10.1.2.3:9222/mcp"
    )

    assert_not server.valid?
    assert_not_empty server.errors[:endpoint]
  end

  test "local execution keeps hash arguments and recoverable error contracts" do
    server = @account.mcp_servers.new(name: "local", transport_type: "local", status: "ready")
    server.define_singleton_method(:local_tools) { [ KeywordTool.new ] }
    assert_equal({ success: true, result: { query: "file:///not-a-source", options: { "limit" => 2 } } },
      server.execute_tool("keyword", { "query" => "file:///not-a-source", "options" => { "limit" => 2 } }))
    assert_equal({ success: true, result: { error: "Invalid tool arguments: missing keyword: query" } }, server.execute_tool("keyword"))
    assert_equal({ error: "Tool not found: missing" }, server.execute_tool("missing"))
  end
end

class LocalizedMcpServerValidationTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  teardown { unstub_url_resolver }

  test "French public host validation retains the SSRF rule" do
    server = mcp_servers(:picker_second_tool)
    server.assign_attributes(transport_type: "streamable", endpoint: "http://127.0.0.1/mcp")

    I18n.with_locale(:fr) do
      refute server.valid?
      assert_includes server.errors[:endpoint], "doit désigner un hôte accessible publiquement"
      assert_includes server.errors.full_messages, "Adresse du serveur doit désigner un hôte accessible publiquement"
    end
  end

  test "French stdio validation retains the deployment restriction" do
    previous_stdio_env = ENV.delete("MCP_STDIO_ENABLED")
    server = mcp_servers(:picker_second_tool)
    server.transport_type = "stdio"

    I18n.with_locale(:fr) do
      refute server.valid?
      assert_includes server.errors[:transport_type], "stdio nécessite MCP_STDIO_ENABLED sur ce déploiement"
    end
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous_stdio_env
  end
end
