require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "accounts@example.com", password: "testpassword123")
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  test "create grants owner membership and seeds both system prompts" do
    assert_difference -> { Account.count }, 1 do
      post accounts_path, params: { account: { name: "New Account" } }
    end

    assert_redirected_to accounts_path

    account = @user.accounts.find_by!(name: "New Account")
    assert_equal @user, account.owner
    assert_equal 1, account.account_users.where(user: @user).count
    assert_equal 2, account.prompts.count
    assert_equal Prompts.system_prompt, account.prompts.find_by!(name: "system_prompt", user: nil).content
    assert_equal Prompts.system_prompt, account.prompts.find_by!(name: "system_prompt", user: @user).content
  end
end
