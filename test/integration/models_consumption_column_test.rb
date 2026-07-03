require "test_helper"

class ModelsConsumptionColumnTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "mc@example.com", password: "testpassword123")
    @account = Account.create!(name: "MC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    Model.create!(model_id: "glm-5.2", name: "GLM 5.2", provider: "openai")
    Model.create!(model_id: "claude-4-6-sonnet", name: "Claude", provider: "anthropic")
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  test "index shows Comparia consumption for matched models and — for unmatched" do
    get models_path
    assert_response :success
    assert_select "th", text: /Conso\. moyenne/
    assert_select "td", text: "4,095"       # glm-5.2 mWh/1000tok
    assert_select "td", text: "—"
  end
end
