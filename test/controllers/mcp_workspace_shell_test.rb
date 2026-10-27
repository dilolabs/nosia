require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceShellTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures

  setup { sign_in_picker_user }

  test "list owns its bilingual shell and catalog-first scoped actions" do
    %i[en fr].each do |locale|
      get account_mcp_servers_path(@second), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "head title", text: I18n.t("nosia.mcp.title", locale: locale), count: 1
      assert_select "main h1", text: I18n.t("nosia.mcp.title", locale: locale), count: 1
      assert_select "main .n-workspace-header nav", count: 1
      assert_select "main nav [aria-current=page]", count: 1
      assert_select "[data-workspace-scope]", text: /#{Regexp.escape(@second.name)}/
      assert_select ".n-workspace-primary[href=?]", account_mcp_catalog_index_path(@second)
      assert_select "a[href=?]", new_account_mcp_server_path(@second)
      assert_select ".n-workspace-header a[href=?]", new_chat_path(account_id: @second.id)
      assert_select "[data-mcp-row]", count: 1
      assert_select "[data-mcp-row] a[href=?]", account_mcp_server_path(@second, @second_server)
      assert_select "#drawer-right, #accordion-right-actions", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "account overview exposes the explicit MCP route without changing its default" do
    get account_path(@second)
    assert_response :success
    assert_select "a[href=?]", account_mcp_servers_path(@second), text: I18n.t("nosia.mcp_workspace.manage_many")
    assert_equal @first, @user.reload.first_account
  end

  test "filters distinguish empty results and preserve disabled values" do
    @second_server.update!(enabled: false)
    get account_mcp_servers_path(@second), params: { enabled: "false" }
    assert_select "[data-mcp-row]", count: 1
    get account_mcp_servers_path(@second), params: { status: "ready" }
    assert_select "[data-mcp-filtered-empty]"
    assert_select "a[href=?]", account_mcp_servers_path(@second), text: I18n.t("nosia.mcp_workspace.reset")
    get account_mcp_servers_path(@second), params: { status: "unsupported" }
    assert_select "[data-mcp-row]", count: 1
  end

  test "no-account entry points offer setup and mutations fail closed" do
    sign_in_picker_user(users(:picker_no_account))
    [ mcp_servers_path, new_mcp_server_path, mcp_catalog_index_path, mcp_catalog_path("kchat") ].each do |path|
      get path
      assert_response :success
      assert_select "a[href=?]", new_account_path
      assert_select "[data-mcp-workspace] form", count: 0
    end
    post mcp_servers_path, params: { mcp_server: { name: "Not created" } }
    assert_response :not_found
    get mcp_server_path(@first_server)
    assert_response :not_found
  end

  test "non-MCP drawers remain while secrets and long identifiers are escaped" do
    get api_tokens_path
    assert_select "#drawer-right, #accordion-right-actions", count: 2
    @first_server.update!(name: "<script>#{'LongName' * 30}</script>", notes: "saved-secret")
    get mcp_servers_path
    assert_select "main script", count: 0
    refute_includes response.body, "saved-secret"
    assert_select "[data-mcp-row]", text: /LongName/
  end

  test "legacy credential-bearing endpoints are redacted in list summaries" do
    @first_server.update_columns(transport_type: "streamable", status: "disconnected",
      endpoint: "https://user:embedded-fixture@mcp.example.org/mcp?token=query-fixture")
    get mcp_servers_path
    assert_response :success
    refute_includes response.body, "embedded-fixture"
    refute_includes response.body, "query-fixture"
    assert_includes response.body, "mcp.example.org/mcp"
  end

  test "active account membership cannot mutate a different account server" do
    before = @first_server.attributes
    count = McpServer.count

    [ [ :patch, account_mcp_server_path(@second, @first_server) ],
      [ :delete, account_mcp_server_path(@second, @first_server) ],
      [ :post, account_mcp_server_connection_path(@second, @first_server) ],
      [ :delete, account_mcp_server_connection_path(@second, @first_server) ],
      [ :post, account_mcp_server_connection_test_path(@second, @first_server) ],
      [ :post, account_mcp_server_tool_execution_path(@second, @first_server) ] ].each do |verb, path|
      public_send(verb, path, params: { mcp_server: { name: "Forged" }, tool_name: "workspace_echo", arguments: { query: "fixture" } })
      assert_response :not_found
      assert_equal before, @first_server.reload.attributes
      assert_equal count, McpServer.count
    end
  end
end
