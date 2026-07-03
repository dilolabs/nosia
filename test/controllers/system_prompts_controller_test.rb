require "test_helper"

class SystemPromptsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "sp@example.com", password: "testpassword123")
    @account = Account.create!(name: "SP Account", owner: @user)
    @account.account_users.grant_to(@user)
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  test "index lists account-level system prompts for the user's accounts" do
    @account.create_default_system_prompt!(user: nil)
    get system_prompts_url
    assert_response :success
    assert_select "p.n-card-title", text: /System Prompt for #{@account.name} Account/
  end

  test "index auto-creates a default system prompt for accounts missing one" do
    assert_empty Prompt.where(account: @account, name: "system_prompt")
    assert_difference -> { Prompt.where(account: @account, name: "system_prompt").count }, 1 do
      get system_prompts_url
    end
    assert_response :success
  end

  test "show is scoped to the user's accounts" do
    prompt = @account.create_default_system_prompt!(user: nil)
    get system_prompt_url(prompt)
    assert_response :success
  end
end
