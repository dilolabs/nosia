require "test_helper"

class McpServersControllerTest < ActionDispatch::IntegrationTest
  class EndpointTool < MCP::Tool
    tool_name "endpoint_demo"
    description "keyword endpoint regression"
    input_schema(properties: { query: { type: "string" }, options: { type: "object", properties: { page: { type: "integer" } } } }, required: [ "query" ])

    def self.call(query:, options: {}, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: "#{query} page=#{options['page']} authorized=#{server_context[:api_key] == 'fake-key'}" } ])
    end
  end

  def setup
    @user = User.create!(email: "mcp@example.com", password: "testpassword123")
    @account = Account.create!(name: "MCP Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  def make_server(account: @account, name: "Demo")
    ActsAsTenant.current_tenant = account
    server = account.mcp_servers.create!(name: name, transport_type: "local")
    ActsAsTenant.current_tenant = @account
    server
  end

  test "index renders a delete button for each server" do
    make_server
    get mcp_servers_url
    assert_response :success
    assert_select "span.sr-only", text: "Delete server"
  end

  test "show renders a Delete button" do
    server = make_server
    get mcp_server_url(server)
    assert_response :success
    assert_select "a[data-turbo-method=delete]", text: /Delete/
  end

  test "destroy deletes the server and redirects to the index" do
    server = make_server
    assert_difference -> { @account.mcp_servers.count }, -1 do
      delete mcp_server_url(server)
    end
    assert_redirected_to mcp_servers_url
    follow_redirect!
    assert_match(/deleted/i, response.body)
  end

  test "destroy is scoped to the current account" do
    other_user = User.create!(email: "other@example.com", password: "testpassword123")
    other_account = Account.create!(name: "Other Account", owner: other_user)
    other_server = make_server(account: other_account, name: "Other")

    assert_no_difference -> { McpServer.unscoped.count } do
      delete mcp_server_url(other_server)
    end
    assert_response :not_found
    assert McpServer.unscoped.exists?(other_server.id)
  end

  test "execute_tool normalizes JSON object arguments at the boundary without permitting record attributes" do
    registrations = Engines::Registry.all
    Engines::Registry.register(Engines::Registration.new(id: "endpoint-test", name: "Endpoint", icon: "test", description: "test",
      required_config: [], tool_classes: [ EndpointTool ], health_check: ->(_) { }))
    server = @account.mcp_servers.create!(name: "Endpoint", transport_type: "local", status: "ready",
      metadata: { engine: "endpoint-test" }, auth_config: { api_key: "fake-key" })

    post execute_tool_mcp_server_url(server), as: :json, params: {
      tool_name: "endpoint_demo", arguments: { query: "https://not-a-source.example", options: { page: 2 } },
      mcp_server: { name: "changed", auth_config: { api_key: "attacker" } }
    }
    assert_response :success
    assert_equal({ "success" => true, "result" => "https://not-a-source.example page=2 authorized=true" }, response.parsed_body)
    assert_equal "Endpoint", server.reload.name
    assert_equal "fake-key", server.api_key
  ensure
    Engines::Registry.clear
    registrations&.each { |registration| Engines::Registry.register(registration) }
  end

  test "execute_tool rejects non-object JSON arguments" do
    server = make_server
    [ [ "not", "keywords" ], "not an object", false, 5 ].each do |arguments|
      post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "unused", arguments: arguments }
      assert_response :bad_request
      assert_equal "Tool arguments must be a JSON object", response.parsed_body.fetch("error")
    end
  end

  test "execute_tool is scoped to the current account" do
    other_user = User.create!(email: "tool-other@example.com", password: "testpassword123")
    other_account = Account.create!(name: "Other tools", owner: other_user)
    server = make_server(account: other_account)
    post execute_tool_mcp_server_url(server), as: :json, params: { tool_name: "unused", arguments: {} }
    assert_response :not_found
  end
end
