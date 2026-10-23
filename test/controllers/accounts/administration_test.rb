require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::AdministrationTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup do
    sign_in_overview(@member)
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
