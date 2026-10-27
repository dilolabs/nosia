require "test_helper"
require_relative "../support/chat_account_fixtures"

class McpConnectionTestsTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup do
    @engines = Engines::Registry.all
    Engines::Registry.register(Engines::Registration.new(
      id: "connection-test", name: "Connection test", icon: "test", description: "Connection test",
      required_config: [], tool_classes: [], health_check: ->(auth) {
        raise "Invalid credentials <script>alert('unsafe')</script>" if auth[:api_key] == "invalid"
      }
    ))
    @server = mcp_servers(:picker_first_tool)
    ActsAsTenant.with_tenant(@first) do
      @server.update!(status: "disconnected", metadata: { engine: "connection-test" })
    end
    sign_in_picker_user
  end

  teardown do
    Engines::Registry.clear
    @engines.each { |registration| Engines::Registry.register(registration) }
  end

  test "HTML connection test returns to the server with a success result and latency" do
    freeze_time do
      post test_connection_mcp_server_url(@server)

      assert_response :see_other
      assert_redirected_to mcp_server_url(@server)
      follow_redirect!
      assert_equal "text/html", response.media_type
      assert_select "#connection-test-result[role=status]" do
        assert_select "h2", text: "Connection established"
        assert_select "p", text: /0ms/
      end
      assert_select "[data-state=ready]", text: /Ready/
      assert @server.reload.status_ready?
    end
  end

  test "HTML connection failure omits diagnostic details and shows recovery guidance" do
    ActsAsTenant.with_tenant(@first) { @server.update!(api_key: "invalid") }

    post test_connection_mcp_server_url(@server)

    assert_response :see_other
    assert_redirected_to mcp_server_url(@server)
    follow_redirect!
    assert_select "#connection-test-result[role=alert]" do
      assert_select "h2", text: "Connection failed"
      assert_select "p", text: /configuration and credentials/
      assert_select "script", count: 0
    end
    refute_includes response.body, "Invalid credentials <script>"
    assert_select "a[href=?]", edit_mcp_server_path(@server), text: "Edit"
    assert @server.reload.status_error?
  end

  test "Turbo form submissions receive an HTML redirect instead of JSON" do
    post test_connection_mcp_server_url(@server), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :see_other
    assert_redirected_to mcp_server_url(@server)
  end

  test "JSON connection tests retain their success response" do
    freeze_time do
      post test_connection_mcp_server_url(@server), as: :json

      assert_response :success
      assert_equal({ "success" => true, "status" => "ready", "latency" => 0, "message" => "Connection established" }, response.parsed_body)
    end
  end

  test "JSON connection tests retain their failure response" do
    ActsAsTenant.with_tenant(@first) { @server.update!(api_key: "invalid") }

    post test_connection_mcp_server_url(@server), as: :json

    assert_response :unprocessable_entity
    assert_equal({ "success" => false, "status" => "error", "error" => "Invalid credentials <script>alert('unsafe')</script>", "message" => "Connection failed" }, response.parsed_body)
  end

  test "connection tests cannot access another account's server" do
    server = mcp_servers(:picker_foreign_tool)
    original_attributes = server.attributes

    post test_connection_mcp_server_url(server)

    assert_response :not_found
    assert_equal original_attributes, server.reload.attributes
  end

  test "server page connection test supports Turbo loading feedback" do
    get mcp_server_url(@server)

    assert_response :success
    assert_select "form[action=?]", test_connection_mcp_server_path(@server) do |forms|
      assert_select "button[data-turbo-submits-with=?]", "Testing connection…"
      assert_select "[data-turbo=false]", count: 0
      refute_equal "false", forms.first["data-turbo"]
    end
  end

  test "edit page connection test is separate from the configuration form" do
    get edit_mcp_server_url(@server)

    assert_response :success
    assert_select "form[action=?]", test_connection_mcp_server_path(@server) do |forms|
      assert_select "button[data-turbo-submits-with=?]", "Testing connection…"
      assert_empty forms.first.ancestors("form")
    end
    assert_select "form[action=?]", mcp_server_path(@server) do
      assert_select "input[name='mcp_server[name]']"
      assert_select "input[type=submit][value=Save]"
      assert_select "button[data-turbo-submits-with]", count: 0
    end
  end

  test "connection test feedback follows the selected language" do
    patch language_preference_url, params: { locale: "fr" }
    assert_response :see_other
    post test_connection_mcp_server_url(@server)

    assert_redirected_to mcp_server_url(@server)
    follow_redirect!
    assert_select "#connection-test-result h2", text: "Connexion établie"
    assert_select "button[data-turbo-submits-with=?]", "Test de la connexion…"
  end
end
