require "test_helper"

class TokenUsagesTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "tu2@example.com", password: "testpassword123")
    @account = Account.create!(name: "TU2 Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    TokenUsage.create!(account: @account, kind: :completion, model_id: "glm-5.2",
                       input_tokens: 500, output_tokens: 100)
    TokenUsage.create!(account: @account, kind: :embedding, input_tokens: 20, output_tokens: 0)
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  test "token usage dashboard shows headline totals and per-kind breakdown" do
    get token_usage_path
    assert_response :success
    assert_select "h2", text: /Token usage & environmental impact/
    assert_select "li", text: /glm-5\.2/
    assert_select "li span.capitalize", text: /embedding/
  end

  test "main dashboard no longer shows the token usage section" do
    get user_root_path
    assert_response :success
    assert_select "h2", text: /Token usage & environmental impact/, count: 0
    assert_select "li", text: /glm-5\.2/, count: 0
  end

  test "application menu links to the token usage dashboard" do
    get user_root_path
    assert_response :success
    assert_select "a[href=?]", token_usage_path, text: /Token usage/
  end

  test "settings page no longer shows a token usage card" do
    get settings_path
    assert_response :success
    assert_select "p.n-card-title", text: "Token usage", count: 0
  end

  test "transparency methodology section is present and cites the data source" do
    get token_usage_path
    assert_response :success
    assert_select "details summary", text: /How is the energy impact/
    assert_select "details", text: /Ecologits/
    assert_select "details", text: /ISO 14044/
    assert_select "details", text: /Etalab 2.0/
    assert_select "details", text: /2 July 2026/
  end
end
