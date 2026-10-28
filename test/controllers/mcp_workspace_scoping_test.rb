require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceScopingTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures

  setup { sign_in_picker_user }

  test "scoped reads use the path account and never change the default" do
    get account_mcp_servers_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_includes response.body, @second_server.name
    refute_includes response.body, @first_server.name
    get account_mcp_server_path(@second, @first_server)
    assert_response :not_found
    get account_mcp_servers_path(@foreign)
    assert_response :not_found
    get "/accounts/#{@second.id}junk/mcp_servers"
    assert_response :not_found
    assert_equal @first, @user.reload.first_account
  end

  test "scoped creation update and deletion retain context" do
    assert_difference -> { @second.mcp_servers.count }, 1 do
      post account_mcp_servers_path(@second), params: { mcp_server: {
        name: "Scoped HTTP", transport_type: "streamable", endpoint: "https://mcp.example.org/mcp" }, account_id: @foreign.id }
    end
    server = @second.mcp_servers.find_by!(name: "Scoped HTTP")
    assert_redirected_to account_mcp_server_path(@second, server)
    patch account_mcp_server_path(@second, server), params: { mcp_server: { name: "Renamed" } }
    assert_redirected_to account_mcp_server_path(@second, server)
    assert_equal "Renamed", server.reload.name
    assert_difference -> { @second.mcp_servers.count }, -1 do
      delete account_mcp_server_path(@second, server)
    end
    assert_redirected_to account_mcp_servers_path(@second)
  end

  test "catalog activation and connection operations preserve URL context" do
    get account_mcp_catalog_index_path(@second)
    assert_response :success
    post account_mcp_catalog_index_path(@second), params: { id: "open_alex", config: {}, account_id: @foreign.id }
    assert_redirected_to account_mcp_server_path(@second, @second.mcp_servers.find_by!(name: "OpenAlex"))
    post account_mcp_server_connection_path(@second, @second_server)
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    assert @second_server.reload.status_ready?
    delete account_mcp_server_connection_path(@second, @second_server)
    assert @second_server.reload.status_disconnected?
    post account_mcp_server_connection_test_path(@second, @second_server), as: :json
    assert_response :success
    assert_equal true, response.parsed_body.fetch("success")
    post account_mcp_server_tool_execution_path(@second, @second_server), as: :json,
      params: { tool_name: "workspace_echo", arguments: { query: "fixture" } }
    assert_equal({ "success" => true, "result" => "fixture" }, response.parsed_body)
  end

  test "foreign and revoked mutations fail without writes" do
    before = @second_server.attributes
    account_users(:picker_second_membership).destroy!
    [ [ :post, account_mcp_server_connection_test_path(@second, @second_server) ],
      [ :post, account_mcp_server_connection_path(@second, @second_server) ],
      [ :delete, account_mcp_server_connection_path(@second, @second_server) ],
      [ :post, account_mcp_server_tool_execution_path(@second, @second_server) ],
      [ :patch, account_mcp_server_path(@second, @second_server) ],
      [ :delete, account_mcp_server_path(@second, @second_server) ],
      [ :post, account_mcp_catalog_index_path(@second) ] ].each do |verb, path|
      public_send(verb, path, params: { id: "open_alex", account_id: @first.id, mcp_server: { name: "Forged" } })
      assert_response :not_found
    end
    assert_equal before, @second_server.reload.attributes
  end

  test "legacy routes and ordinary member permissions remain" do
    post test_connection_mcp_server_path(@first_server), as: :json
    assert_response :success
    assert_equal %w[latency message status success], response.parsed_body.keys.sort
    post disconnect_mcp_server_path(@first_server)
    assert_redirected_to mcp_server_path(@first_server)
    @second.account_users.grant_to(users(:picker_outsider))
    sign_in_picker_user(users(:picker_outsider))
    patch account_mcp_server_path(@second, @second_server), params: { mcp_server: { notes: "Member edit" } }
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    assert_equal "Member edit", @second_server.reload.notes
  end
end
