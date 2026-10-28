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

  { null: nil, scalar: "never-echo-malformed-secret", array: [ "never-echo-malformed-secret" ] }.each do |shape, configuration|
    test "server creation rejects a #{shape} credential container without writes or secret reflection" do
      assert_no_difference -> { @second.mcp_servers.count } do
        post account_mcp_servers_path(@second), as: :json, params: { mcp_server: {
          name: "Rejected HTTP", transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
          token: "never-echo-malformed-secret", configuration_values: configuration } }
      end

      assert_response :bad_request
      refute_includes response.body, "never-echo-malformed-secret"
      refute_includes flash.to_hash.values.join, "never-echo-malformed-secret"
    end

    test "server update rejects a #{shape} credential container without writes or secret reflection" do
      before = @second_server.attributes.deep_dup
      patch account_mcp_server_path(@second, @second_server), as: :json, params: { mcp_server: {
        name: "Rejected edit", api_key: "never-echo-malformed-secret", configuration_values: configuration } }

      assert_response :bad_request
      assert_equal before, @second_server.reload.attributes
      refute_includes response.body, "never-echo-malformed-secret"
      refute_includes flash.to_hash.values.join, "never-echo-malformed-secret"
    end

    test "catalog activation rejects a #{shape} config container without writes or secret reflection" do
      assert_no_difference -> { @second.mcp_servers.count } do
        post account_mcp_catalog_index_path(@second), as: :json, params: {
          id: "workspace-demo", config: configuration, api_key: "never-echo-malformed-secret" }
      end

      assert_response :bad_request
      refute_includes response.body, "never-echo-malformed-secret"
      refute_includes flash.to_hash.values.join, "never-echo-malformed-secret"
    end
  end

  test "catalog activation allows an omitted config container" do
    assert_difference -> { @second.mcp_servers.count }, 1 do
      post account_mcp_catalog_index_path(@second), as: :json, params: { id: "open_alex" }
    end
    assert_redirected_to account_mcp_server_path(@second, @second.mcp_servers.find_by!(name: "OpenAlex"))
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
