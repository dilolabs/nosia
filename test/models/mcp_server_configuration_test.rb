require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpServerConfigurationTest < ActiveSupport::TestCase
  include McpWorkspaceFixtures

  test "blank keeps saved secrets and replacement preserves other configuration" do
    @second_server.update!(connection_config: { env: { "UNEDITED" => "keep" } })
    assert @second_server.save_workspace({ notes: "Updated" }, values: { "api_key" => "", "team" => "New team" })
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
    assert_equal "New team", @second_server.auth_config.fetch("team")
    assert @second_server.save_workspace({}, values: { "api_key" => "replacement" })
    assert_equal "replacement", @second_server.reload.auth_config.fetch("api_key")
    assert_equal({ "UNEDITED" => "keep" }, @second_server.connection_config.fetch("env"))
  end

  test "required removal and contradictory instructions fail without database writes" do
    before = @second_server.attributes
    refute @second_server.save_workspace({}, values: {}, removals: [ "api_key" ])
    assert @second_server.errors.include?(:"configuration.api_key")
    assert_equal before, @second_server.reload.attributes
    refute @second_server.save_workspace({}, values: { "api_key" => "new" }, removals: [ "api_key" ])
    assert @second_server.errors.include?(:"configuration.api_key")
    assert_equal before, @second_server.reload.attributes
  end

  test "optional removal is explicit and a failed edit retains only public values" do
    @second_server.update!(metadata: { engine: "open_alex" }, auth_config: { api_key: "optional-secret" })
    assert @second_server.save_workspace({}, values: {}, removals: [ "api_key" ])
    refute @second_server.reload.auth_config.key?("api_key")
    @second_server.update!(metadata: { engine: "workspace-demo" }, auth_config: { api_key: "saved-secret", team: "Research" })
    refute @second_server.save_workspace({ name: "" }, values: { "api_key" => "not-for-html", "team" => "Retained" })
    assert_equal({ "team" => "Retained" }, @second_server.workspace_public_values)
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
  end

  test "local transport cannot be coerced and unknown registrations preserve data" do
    refute @second_server.save_workspace({ transport_type: "streamable" }, values: {})
    assert_equal "local", @second_server.reload.transport_type
    @second_server.update!(metadata: { engine: "missing" })
    assert @second_server.save_workspace({ notes: "Safe edit" }, values: { api_key: "ignored" })
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
    assert_equal [], @second_server.workspace_configuration_fields
  end

  test "unchanged argument arrays round trip instead of becoming strings" do
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
      connection_config: { args: [ "one value", "", "last" ], headers: { "X-Custom" => "keep" } })
    assert @second_server.save_workspace({ args: "one value\n\nlast" }, values: {})
    assert_equal [ "one value", "", "last" ], @second_server.reload.args
    assert_equal({ "X-Custom" => "keep" }, @second_server.headers)
  end

  test "disabled stdio cannot construct a client or test a persisted command" do
    previous = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    @second_server.update!(transport_type: "stdio", endpoint: nil, command: "must-not-run", args: [])
    ENV["MCP_STDIO_ENABLED"] = "false"
    before = @second_server.attributes
    with_singleton_replacement(RubyLLM::MCP, :client, ->(**_) { flunk "stdio process construction attempted" }) do
      assert_nil @second_server.client
      refute @second_server.test_connection!
    end
    assert_equal before, @second_server.reload.attributes
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous
  end
end
