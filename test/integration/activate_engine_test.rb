require "test_helper"

# Verifies the admin journey of activating the OpenAlex engine from the MCP
# catalog end-to-end through the real controller. This is an
# ActionDispatch::IntegrationTest rather than the originally planned Capybara
# system test: this environment has no Chrome/chromedriver, and activation
# does not call test_connection! (the server stays "disconnected"), so a
# system test asserting "ready" could not run or pass here.
class ActivateEngineTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "ae-openalex@example.com", password: "testpassword123")
    @account = Account.create!(name: "AE OpenAlex Account", owner: @user)
    @account.account_users.grant_to(@user)
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  test "admin activates the OpenAlex engine from the catalog" do
    get mcp_catalog_index_url
    assert_response :success
    assert_select "h4.n-card-title", text: /OpenAlex/

    get mcp_catalog_path("open_alex")
    assert_response :success
    assert_select "input[type='submit'][value='Activate OpenAlex']"
    assert_select "label", text: /OpenAlex API key/

    assert_difference -> { @account.mcp_servers.where(transport_type: "local").count }, 1 do
      post mcp_catalog_index_url, params: { id: "open_alex", config: { api_key: "" } }
    end

    assert_response :redirect
    assert_equal "OpenAlex activated successfully.", flash[:notice]

    follow_redirect!
    assert_response :success

    server = @account.mcp_servers.where(transport_type: "local")
                      .find_by("metadata->>'engine' = 'open_alex'")
    assert server
    assert_equal "local", server.transport_type
    assert_equal "open_alex", server.metadata["engine"]
    assert_equal "open_alex", server.metadata["catalog_id"]
    assert_equal "disconnected", server.status
  end
end
