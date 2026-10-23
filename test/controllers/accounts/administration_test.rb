require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::AdministrationTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup do
    sign_in_overview(@member)
  end

  test "member prompt read page has neither membership navigation nor edit controls" do
    get account_system_prompt_path(@second)
    assert_response :success
    assert_select "a[href='#{edit_account_system_prompt_path(@second)}']", count: 0
    assert_select "a[href='#{account_account_users_path(@second)}']", count: 0
    assert_includes response.body, "Shared research instructions"
    assert_select "p", text: "Account default · Personal overrides may apply"
    assert_select "nav[aria-label='Breadcrumb'] a[href='#{account_path(@second)}']"
    shared = experience(:prompts, :overview_second_shared)
    get system_prompt_path(shared)
    assert_response :success
    assert_select "a[href='#{edit_system_prompt_path(shared)}']", count: 0
  end

  test "missing shared prompt edit submits PATCH and failed saving creates no default" do
    sign_in_overview
    get edit_account_system_prompt_path(@empty)
    assert_response :success
    assert_select "form[action='#{account_system_prompt_path(@empty)}'] input[name='_method'][value='patch']"
    assert_no_difference "Prompt.count" do
      patch account_system_prompt_path(@empty), params: { prompt: { content: "" } }
      assert_response :unprocessable_entity
    end
    assert_select "form [role='alert'] li", text: /Content/
    assert_select "form a[href='#{account_system_prompt_path(@empty)}']", text: "Cancel"
  end

  test "legacy shared prompt read controls are hidden from members but personal controls remain" do
    shared = experience(:prompts, :overview_second_shared)
    get system_prompt_path(shared)
    assert_response :success
    assert_select "a[href='#{edit_system_prompt_path(shared)}']", count: 0
    assert_includes response.body, shared.content

    personal = experience(:prompts, :overview_second_personal)
    get system_prompt_path(personal)
    assert_response :success
    assert_select "a[href='#{edit_system_prompt_path(personal)}']", count: 2

    sign_in_overview
    get system_prompt_path(shared)
    assert_response :success
    assert_select "a[href='#{edit_system_prompt_path(shared)}']", count: 2
  end

  test "owner prompt page retains membership and both edit controls" do
    sign_in_overview
    get account_system_prompt_path(@second)
    assert_response :success
    assert_select "a[href='#{edit_account_system_prompt_path(@second)}']", count: 2
    assert_select "a[href='#{account_account_users_path(@second)}']", count: 1

    get edit_account_system_prompt_path(@second)
    assert_response :success
    assert_select "nav[aria-label='Breadcrumb'] [aria-current='page']", text: "System prompt"
    assert_select "form[action='#{account_system_prompt_path(@second)}'] input[name='_method'][value='patch']"
  end

  test "member cannot edit account details or manage membership" do
    get edit_account_path(@second)
    assert_response :forbidden

    assert_no_changes -> { @second.reload.name } do
      patch account_path(@second), params: { account: { name: "Changed" } }
    end
    assert_response :forbidden

    get account_account_users_path(@second)
    assert_response :forbidden

    assert_no_difference "AccountUser.count" do
      post account_account_users_path(@second), params: { account_user: { email: @user.email } }
      assert_response :forbidden
      delete account_account_user_path(@second, experience(:account_users, :overview_owner_second))
      assert_response :forbidden
    end
  end

  test "shared prompt is readable but only the owner may mutate it, including legacy routes" do
    prompt = experience(:prompts, :overview_second_shared)
    get account_system_prompt_path(@second)
    assert_response :success

    get edit_account_system_prompt_path(@second)
    assert_response :forbidden

    assert_no_changes -> { prompt.reload.content } do
      patch account_system_prompt_path(@second), params: { prompt: { content: "Hijack" } }
      assert_response :forbidden
      patch system_prompt_path(prompt), params: { prompt: { content: "Legacy hijack" } }
      assert_response :forbidden
    end

    get edit_system_prompt_path(prompt)
    assert_response :forbidden

    assert_no_difference "Prompt.count" do
      delete system_prompt_path(prompt)
      assert_response :forbidden
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "personal override editing remains unchanged" do
    prompt = experience(:prompts, :overview_second_personal)

    patch system_prompt_path(prompt), params: { prompt: { content: "My replacement override" } }

    assert_response :redirect
    assert_equal "My replacement override", prompt.reload.content
  end

  test "owner can save a shared prompt and invalid input stays editable with 422" do
    sign_in_overview

    patch account_system_prompt_path(@second), params: { prompt: { content: "Owner replacement" } }
    assert_redirected_to account_system_prompt_path(@second)

    patch account_system_prompt_path(@second), params: { prompt: { content: "" } }
    assert_response :unprocessable_entity
    assert_select "textarea[name='prompt[content]']"
  end

  test "outsider cannot reach account administration" do
    get edit_account_path(@foreign)
    assert_response :not_found

    get account_account_users_path(@foreign)
    assert_response :not_found
  end

  test "member cannot update account details directly" do
    assert_no_changes -> { @second.reload.name } do
      patch account_path(@second), params: { account: { name: "Changed" } }
      assert_response :forbidden
    end
  end

  test "membership denial happens before looking up users" do
    assert_no_difference "AccountUser.count" do
      post account_account_users_path(@second), params: { account_user: { email: "missing@example.invalid" } }
      assert_response :forbidden
    end
  end

  test "member cannot update a shared prompt through the account route directly" do
    prompt = experience(:prompts, :overview_second_shared)

    assert_no_changes -> { prompt.reload.content } do
      patch account_system_prompt_path(@second), params: { prompt: { content: "Hijack" } }
      assert_response :forbidden
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "member cannot edit a shared prompt through the legacy route directly" do
    prompt = experience(:prompts, :overview_second_shared)

    get edit_system_prompt_path(prompt)
    assert_response :forbidden
  end

  test "member cannot update a shared prompt through the legacy route directly" do
    prompt = experience(:prompts, :overview_second_shared)

    assert_no_changes -> { prompt.reload.content } do
      patch system_prompt_path(prompt), params: { prompt: { content: "Legacy hijack" } }
      assert_response :forbidden
    end
  end

  test "member cannot delete a shared prompt through the legacy route directly" do
    prompt = experience(:prompts, :overview_second_shared)

    assert_no_difference "Prompt.count" do
      delete system_prompt_path(prompt)
      assert_response :forbidden
    end
  end

  test "membership denial happens before looking up a foreign membership" do
    assert_no_difference "AccountUser.count" do
      delete account_account_user_path(@second, experience(:account_users, :overview_outsider_foreign))
      assert_response :forbidden
    end
  end

  test "invalid input does not materialize a missing shared prompt" do
    sign_in_overview

    assert_no_difference "Prompt.count" do
      patch account_system_prompt_path(@empty), params: { prompt: { content: "" } }
      assert_response :unprocessable_entity
    end
    assert_select "textarea[name='prompt[content]']"
    assert_empty @empty.prompts.reload
  end

  test "owner without current membership cannot administer the account" do
    sign_in_overview
    experience(:account_users, :overview_owner_second).destroy!
    prompt = experience(:prompts, :overview_second_shared)

    [ edit_account_path(@second), account_account_users_path(@second),
      account_system_prompt_path(@second), edit_account_system_prompt_path(@second),
      system_prompt_path(prompt), edit_system_prompt_path(prompt) ].each do |path|
      get path
      assert_response :not_found
    end

    assert_no_changes -> { prompt.reload.content } do
      patch account_system_prompt_path(@second), params: { prompt: { content: "Revoked hijack" } }
      assert_response :not_found
      patch system_prompt_path(prompt), params: { prompt: { content: "Legacy revoked hijack" } }
      assert_response :not_found
    end
  end

  test "request parameters cannot replace route account IDs" do
    sign_in_overview

    assert_no_changes -> { @foreign.reload.name } do
      patch account_path(@foreign), params: { id: @second.id, account: { name: "Hijack" } }
      assert_response :not_found
    end

    assert_no_difference "AccountUser.count" do
      post account_account_users_path(@foreign), params: { account_id: @second.id, account_user: { email: @member.email } }
      assert_response :not_found
    end

    assert_no_difference "Prompt.count" do
      patch account_system_prompt_path(@foreign), params: { account_id: @second.id, prompt: { content: "Hijack" } }
      assert_response :not_found
    end
  end
end
