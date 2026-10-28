require "test_helper"

class SystemPromptsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "sp@example.com", password: "testpassword123")
    @account = Account.create!(name: "SP Account", owner: @user)
    @account.account_users.grant_to(@user)
    post login_url, params: { email: @user.email, password: "testpassword123" }

    @stranger = User.create!(email: "sp-stranger@example.com", password: "testpassword123")
    @foreign_account = Account.create!(name: "Foreign Account", owner: @stranger)
  end

  test "index lists account-level system prompts for the user's accounts" do
    @account.create_default_system_prompt!(user: nil)
    get system_prompts_url
    assert_response :success
    assert_select "[data-prompt-row] a[href=?]", system_prompt_path(@account.prompts.find_by!(name: "system_prompt", user: nil)), text: @account.name
  end

  # Read actions no longer write: Account#system_prompt falls back to the
  # shipped default when no row exists, so index just lists what's there.
  test "index lists existing prompts without creating missing ones" do
    assert_no_difference -> { Prompt.count } do
      get system_prompts_url
    end
    assert_response :success

    prompt = @account.create_default_system_prompt!(user: nil)
    get system_prompts_url
    assert_response :success
    assert_select "[data-prompt-row] a[href=?]", system_prompt_path(prompt), text: @account.name
  end

  test "show is scoped to the user's accounts" do
    prompt = @account.create_default_system_prompt!(user: nil)
    get system_prompt_url(prompt)
    assert_response :success
  end

  test "update cannot move a system prompt to another user's account" do
    prompt = @account.create_default_system_prompt!(user: nil)

    patch system_prompt_url(prompt), params: {
      prompt: { content: "hijacked", account_id: @foreign_account.id }
    }

    assert_equal @account.id, prompt.reload.account_id
    assert_empty Prompt.where(account: @foreign_account)
  end
end
