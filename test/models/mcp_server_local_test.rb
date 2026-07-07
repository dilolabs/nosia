require "test_helper"

class McpServerLocalTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "eng@example.com", password: "testpassword123")
    @account = Account.create!(name: "Eng Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    # Preserve boot-time registrations; restore in teardown so later tests
    # (e.g. EnginesBootTest) still see the engines registered at boot.
    @engines = Engines::Registry.all
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    Engines::Registry.clear
    @engines.each { |registration| Engines::Registry.register(registration) }
  end

  def stub_registration(health_check: ->(auth) { }, tool_classes: [])
    reg = Engines::Registration.new(
      id: "demo", name: "Demo", icon: "🧪", description: "demo",
      required_config: [], tool_classes: tool_classes, health_check: health_check
    )
    Engines::Registry.register(reg)
    reg
  end

  test "#client returns nil for local transport" do
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", metadata: { engine: "demo" }
    )
    assert_nil server.client
  end

  test "#tools returns adapted RubyLLM tools for a ready local server" do
    stub_registration(tool_classes: [ FlatToolForServer ])
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", status: "ready",
      metadata: { engine: "demo" }, auth_config: { api_key: "sekret" }
    )
    tools = server.tools
    assert_equal 1, tools.size
    assert_kind_of RubyLLM::Tool, tools.first
    assert_equal "flat_for_server", tools.first.name
  end

  test "#tools returns [] when the engine is unknown" do
    server = @account.mcp_servers.create!(
      name: "ghost", transport_type: "local", status: "ready",
      metadata: { engine: "nope" }
    )
    assert_equal [], server.tools
  end

  test "#tools returns [] when the server is not ready" do
    stub_registration(tool_classes: [ FlatToolForServer ])
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", status: "disconnected",
      metadata: { engine: "demo" }
    )
    assert_equal [], server.tools
  end

  test "#test_connection! flips status to ready when health_check passes" do
    stub_registration(health_check: ->(auth) { raise "bad" if auth[:api_key] == "BAD" })
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", metadata: { engine: "demo" },
      auth_config: { api_key: "GOOD" }
    )
    assert server.test_connection!
    assert_equal "ready", server.reload.status
  end

  test "#test_connection! flips status to error when health_check raises" do
    stub_registration(health_check: ->(auth) { raise "Invalid credentials" })
    server = @account.mcp_servers.create!(
      name: "demo", transport_type: "local", metadata: { engine: "demo" },
      auth_config: { api_key: "BAD" }
    )
    assert_not server.test_connection!
    assert_equal "error", server.reload.status
    assert_match(/Invalid credentials/, server.reload.last_error)
  end
end

class FlatToolForServer < MCP::Tool
  tool_name "flat_for_server"
  description "flat"
  input_schema(properties: { query: { type: "string" } }, required: [ "query" ])
  def self.call(query:, server_context:)
    MCP::Tool::Response.new([ { type: "text", text: "ok" } ])
  end
end
