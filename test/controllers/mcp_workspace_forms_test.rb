require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceFormsTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures

  setup { sign_in_picker_user }

  test "new and edit have one title heading trail and contextual cancellation" do
    %i[en fr].each do |locale|
      [ [ new_account_mcp_server_path(@second), account_mcp_servers_path(@second) ],
        [ edit_account_mcp_server_path(@second, @second_server), account_mcp_server_path(@second, @second_server) ] ].each do |path, cancel|
        get path, headers: { "Accept-Language" => locale.to_s }
        assert_response :success
        assert_select "head title", count: 1
        assert_select "main h1", count: 1
        assert_equal css_select("main h1").first.text, css_select("head title").first.text
        assert_select "main .n-workspace-header nav", count: 1
        assert_select "[data-mcp-form] a[href=?]", cancel, text: I18n.t("nosia.actions.cancel", locale: locale)
        assert_select "meta[name=turbo-cache-control][content=no-cache]"
        assert_select "#drawer-right, #accordion-right-actions", count: 0
        refute_match(/translation missing|missing translation/i, response.body)
      end
    end
  end

  test "built-in fields retain their transport and never contain saved secret values" do
    get edit_account_mcp_server_path(@second, @second_server)
    assert_select "input[name='mcp_server[transport_type]'][value=local]"
    assert_select "select[name='mcp_server[transport_type]']", count: 0
    assert_select "input[name='mcp_server[configuration_values][api_key]'][value='']"
    assert_select "input[name='mcp_server[configuration_values][team]'][value=Research]"
    refute_includes response.body, "saved-secret"
  end

  test "422 keeps non-secret values and connects errors without echoing replacement" do
    %i[en fr].each do |locale|
      original = @second_server.reload.attributes.deep_dup
      patch account_mcp_server_path(@second, @second_server), params: { mcp_server: { name: "", notes: "Retained note", configuration_values: { api_key: "never-render", team: "" } } }, headers: { "Accept-Language" => locale.to_s }

      assert_response :unprocessable_entity
      assert_select "textarea#mcp_server_notes", text: "Retained note"
      assert_select "a[data-error-field=mcp_server_name]"
      assert_select "input#mcp_server_name[aria-invalid=true]"
      message = "Team #{I18n.t('errors.messages.blank', locale: locale)}"
      assert_select "a[data-error-field=mcp_server_configuration_values_team]", text: message
      assert_select "p#mcp_server_configuration_values_team_error", text: message
      assert_select "input#mcp_server_configuration_values_team[aria-invalid=true][aria-describedby='mcp_server_configuration_values_team_help mcp_server_configuration_values_team_error'][value='']"
      assert_select "input#mcp_server_configuration_values_api_key[value='']"
      refute_includes response.body, "never-render"
      assert_equal original, @second_server.reload.attributes
    end
  end

  test "secret removal and replacement conflict uses the declared label without echo or writes" do
    %i[en fr].each do |locale|
      original = @second_server.reload.attributes.deep_dup
      patch account_mcp_server_path(@second, @second_server), params: { mcp_server: {
        notes: "Retained conflict note", configuration_values: { api_key: "never-render-conflict", team: "Retained team" }, remove_credentials: [ "api_key" ] } }, headers: { "Accept-Language" => locale.to_s }

      assert_response :unprocessable_entity
      message = "Demo key #{I18n.t('nosia.mcp_workspace.credential_conflict', locale: locale)}"
      assert_select "a[data-error-field=mcp_server_configuration_values_api_key]", text: message
      assert_select "p#mcp_server_configuration_values_api_key_error", text: message
      assert_select "input#mcp_server_configuration_values_api_key[aria-invalid=true][aria-describedby='mcp_server_configuration_values_api_key_help mcp_server_configuration_values_api_key_error'][value='']"
      assert_select "input#mcp_server_configuration_values_team[value='Retained team']"
      assert_select "textarea#mcp_server_notes", text: "Retained conflict note"
      refute_includes response.body, "never-render-conflict"
      refute_includes response.body, "saved-secret"
      assert_equal original, @second_server.reload.attributes
    end
  end

  test "test saved configuration is a separate scoped form" do
    get edit_account_mcp_server_path(@second, @second_server)
    assert_select "form[action=?]", account_mcp_server_connection_test_path(@second, @second_server) do |forms|
      assert_empty forms.first.ancestors("form")
      assert_select "input[name^='mcp_server']", count: 0
    end
    assert_select "[data-mcp-form] button[data-turbo-submits-with]", count: 0
    assert_select "[data-mcp-form] input[type=submit][data-turbo-submits-with]"
  end

  test "failed HTTP edits do not expose testing for saved deployment-disabled stdio" do
    previous_stdio = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    server = ActsAsTenant.with_tenant(@second) do
      @second.mcp_servers.create!(name: "Saved stdio", transport_type: "stdio", command: "never-execute", args: [ "--fixture-only" ])
    end
    original = server.attributes.deep_dup
    ENV["MCP_STDIO_ENABLED"] = "false"

    with_singleton_replacement(RubyLLM::MCP, :client, ->(**) { flunk "Form requests must not initialize an MCP client" }) do
      %i[en fr].each do |locale|
        get edit_account_mcp_server_path(@second, server), headers: { "Accept-Language" => locale.to_s }
        assert_response :success
        assert_select "aside form[action=?]", account_mcp_server_connection_test_path(@second, server), count: 0
        assert_select "aside p", text: I18n.t("nosia.mcp_workspace.stdio_unavailable", locale: locale)

        assert_no_difference -> { @second.mcp_servers.count } do
          patch account_mcp_server_path(@second, server), params: { mcp_server: {
            name: "", transport_type: "streamable", endpoint: "https://mcp.example.org/mcp", notes: "Attempted HTTP notes" } }, headers: { "Accept-Language" => locale.to_s }
        end

        assert_response :unprocessable_entity
        assert_select "select#mcp_server_transport_type option[value=streamable][selected]"
        assert_select "input#mcp_server_endpoint[value='https://mcp.example.org/mcp']"
        assert_select "input#mcp_server_name[aria-invalid=true]"
        assert_select "textarea#mcp_server_notes", text: "Attempted HTTP notes"
        assert_select "aside p", text: I18n.t("nosia.mcp_workspace.saved_test_help", locale: locale)
        assert_equal original, server.reload.attributes
        assert_select "aside form[action=?]", account_mcp_server_connection_test_path(@second, server), count: 0
        assert_select "aside p", text: I18n.t("nosia.mcp_workspace.stdio_unavailable", locale: locale)
      end
    end
  ensure
    previous_stdio.nil? ? ENV.delete("MCP_STDIO_ENABLED") : ENV["MCP_STDIO_ENABLED"] = previous_stdio
  end

  test "failed stdio edits do not hide testing for saved HTTP configuration" do
    previous_stdio = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "false"
    server = ActsAsTenant.with_tenant(@second) do
      @second.mcp_servers.create!(name: "Saved HTTP", transport_type: "streamable", endpoint: "https://mcp.example.org/mcp")
    end
    original = server.attributes.deep_dup

    with_singleton_replacement(RubyLLM::MCP, :client, ->(**) { flunk "Form requests must not initialize an MCP client" }) do
      %i[en fr].each do |locale|
        get edit_account_mcp_server_path(@second, server), headers: { "Accept-Language" => locale.to_s }
        assert_response :success
        assert_select "aside form[action=?]", account_mcp_server_connection_test_path(@second, server), count: 1

        assert_no_difference -> { @second.mcp_servers.count } do
          patch account_mcp_server_path(@second, server), params: { mcp_server: {
            name: "", transport_type: "stdio", command: "never-execute", notes: "Attempted stdio notes" } }, headers: { "Accept-Language" => locale.to_s }
        end

        assert_response :unprocessable_entity
        assert_select "select#mcp_server_transport_type[aria-invalid=true] option[value=stdio][selected]"
        assert_select "a[data-error-field=mcp_server_transport_type]"
        assert_select "input#mcp_server_command[value=never-execute]"
        assert_select "input#mcp_server_name[aria-invalid=true]"
        assert_select "textarea#mcp_server_notes", text: "Attempted stdio notes"
        assert_select "aside p", text: I18n.t("nosia.mcp_workspace.saved_test_help", locale: locale)
        assert_equal original, server.reload.attributes
        assert_select "aside form[action=?]", account_mcp_server_connection_test_path(@second, server), count: 1
        assert_select "aside button", text: I18n.t("nosia.mcp_workspace.saved_test", locale: locale)
      end
    end
  ensure
    previous_stdio.nil? ? ENV.delete("MCP_STDIO_ENABLED") : ENV["MCP_STDIO_ENABLED"] = previous_stdio
  end

  test "nullable local metadata permits safe basic editing without rewriting configuration" do
    @second_server.update!(metadata: nil, env: { "UNDECLARED" => "preserved-env" })
    original_auth = @second_server.auth_config.deep_dup
    original_env = @second_server.env.deep_dup

    patch account_mcp_server_path(@second, @second_server), params: { mcp_server: { notes: "Basic edit remains available" } }
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    assert_equal "Basic edit remains available", @second_server.reload.notes
    assert_equal original_auth, @second_server.auth_config
    assert_equal original_env, @second_server.env
    assert_nil @second_server.metadata

    get edit_account_mcp_server_path(@second, @second_server)
    assert_response :success
    assert_select "p", text: I18n.t("nosia.mcp_workspace.missing_registration")
    assert_select "textarea#mcp_server_notes"
  end
end
