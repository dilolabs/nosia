require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceConfigurationTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures

  setup { sign_in_picker_user }

  test "scoped edits use whitelisted credential values and preserve blank secrets" do
    patch account_mcp_server_path(@second, @second_server), params: { mcp_server: {
      name: "Changed", configuration_values: { api_key: "", team: "Public team", ignored: "no" } } }
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
    assert_equal "Public team", @second_server.auth_config.fetch("team")
    refute @second_server.auth_config.key?("ignored")
  end

  test "activation failure remains on setup without writing or echoing secret values" do
    before = @second.mcp_servers.count
    post account_mcp_catalog_index_path(@second), params: { id: "workspace-demo", config: { api_key: "never-echo-this", team: "" } }
    assert_response :unprocessable_entity
    assert_equal before, @second.mcp_servers.count
    refute_includes response.body, "never-echo-this"
    refute flash.to_hash.values.join.include?("never-echo-this")
  end

  test "missing YAML requirements are validated without enabling blocked stdio" do
    assert_no_difference -> { @first.mcp_servers.count } do
      post mcp_catalog_index_path, params: { id: "kchat", config: {} }
    end
    assert_response :unprocessable_entity
    refute @first.mcp_servers.exists?(name: "Infomaniak kChat")
    assert_equal @first, @user.reload.first_account
  end
end
