require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceCatalogTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures

  setup { sign_in_picker_user }

  test "catalog uses scoped cards and added means manage not connected" do
    %i[en fr].each do |locale|
      get account_mcp_catalog_index_path(@second), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "[data-mcp-screen=catalog] h1", count: 1
      assert_select "[data-mcp-entry='workspace-demo']" do
        assert_select "a[href=?]", account_mcp_server_path(@second, @second_server)
        assert_select "button[disabled]", count: 0
        assert_select "svg[aria-hidden=true]", minimum: 1
      end
      assert_select "#drawer-right, #accordion-right-actions", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "failed setup retains public fields with linked errors and empty secrets" do
    @second_server.update!(metadata: { engine: "workspace-demo" })
    post account_mcp_catalog_index_path(@second), params: { id: "workspace-demo", config: { api_key: "", team: "Retained public value" } }
    assert_response :unprocessable_entity
    assert_select "[data-form-errors-target=summary][tabindex='-1'][role=alert]"
    assert_select "a[data-error-field=config_api_key][href='#config_api_key']"
    assert_select "input#config_team[value='Retained public value']"
    assert_select "input#config_api_key[type=password][value='']"
    assert_select "input#config_api_key[aria-invalid=true]"
    assert_select "form[action=?]", account_mcp_catalog_index_path(@second)
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    refute_includes response.body, "saved-secret"
  end

  test "added setup offers management but failed direct posts still expose recovery" do
    get account_mcp_catalog_path(@second, "workspace-demo")
    assert_response :success
    assert_select "[data-mcp-screen=catalog-setup] a[href=?]", account_mcp_server_path(@second, @second_server)
    assert_select "form[action=?]", account_mcp_catalog_index_path(@second), count: 0

    post account_mcp_catalog_index_path(@second), params: { id: "workspace-demo", config: { api_key: "", team: "Retained public value" } }
    assert_response :unprocessable_entity
    assert_select "form[action=?]", account_mcp_catalog_index_path(@second)
    assert_select "input#config_api_key[aria-describedby='config_api_key_help config_api_key_error']"
    assert_select "p#config_api_key_error", text: /Demo key/
    assert_select "input#config_team[value='Retained public value']"
  end

  test "blocked stdio failure explains the problem without links to absent fields" do
    unless McpServer.stdio_enabled?
      assert_no_difference -> { @second.mcp_servers.count } do
        post account_mcp_catalog_index_path(@second), params: { id: "kchat", config: {} }
      end
      assert_response :unprocessable_entity
      assert_select "[data-mcp-transport-unavailable] [data-form-errors-target=summary][role=alert][tabindex='-1']"
      assert_select "a[data-error-field]", count: 0
      assert_select "form[action=?]", account_mcp_catalog_index_path(@second), count: 0
    end
  end

  test "nullable legacy metadata does not break catalog reads or setup recovery" do
    @second_server.update!(metadata: nil)

    get account_mcp_catalog_index_path(@second)
    assert_response :success
    get account_mcp_catalog_path(@second, "workspace-demo")
    assert_response :success
    post account_mcp_catalog_index_path(@second), params: { id: "workspace-demo", config: { api_key: "", team: "Public team" } }
    assert_response :unprocessable_entity
  end

  test "public metadata stays public and declared secrets stay secret" do
    assert_equal [ "drive_id" ], McpCatalog.public_configuration_values(McpCatalog.find("kdrive"), { token: "hide", drive_id: "123" }).keys
    assert_empty McpCatalog.public_configuration_values(McpCatalog.find("kchat"), { kchat_token: "hide", kchat_team_name: "hide-team" })
    get mcp_catalog_path("kchat")
    if McpServer.stdio_enabled?
      assert_select "input#config_kchat_team_name[type=password]"
    else
      assert_select "[data-mcp-transport-unavailable]"
      assert_select "form[action=?]", mcp_catalog_index_path, count: 0
    end
  end
end
