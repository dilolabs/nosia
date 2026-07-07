require "test_helper"

class McpServersControllerTest < ActionDispatch::IntegrationTest
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
end
