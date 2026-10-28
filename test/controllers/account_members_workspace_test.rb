require "test_helper"
require_relative "../support/settings_tool_fixtures"

class AccountMembersWorkspaceTest < ActionDispatch::IntegrationTest
  include SettingsToolFixtures

  setup { sign_in_overview }

  test "dedicated bilingual page identifies owner and keeps other resources out" do
    %i[en fr].each do |locale|
      get account_account_users_path(@second), headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select "main h1", text: I18n.t("nosia.settings_tools.members_title", locale: locale), count: 1
      assert_equal css_select("main h1").first.text, css_select("head title").first.text
      assert_select "main .n-workspace-header nav", count: 1
      assert_select "[data-workspace-scope]", text: /#{Regexp.escape(@second.name)}/
      assert_select "[data-member-row]", count: 2
      assert_select "[data-member-owner=true] form", count: 0
      assert_select "[data-member-owner=true]", text: /#{Regexp.escape(I18n.t('nosia.settings_tools.owner_protected', locale: locale))}/
      assert_select "[data-settings-tool] input[name^='api_token'], [data-settings-tool] textarea[name='prompt[content]']", count: 0
      assert_select "#drawer-right, #accordion-right-actions", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "unknown and duplicate users retain email with linked 422 recovery and no side effects" do
    %i[en fr].each do |locale|
      { "not-registered@example.invalid" => :member_unknown, @member.email => :member_duplicate }.each do |email, key|
        assert_no_enqueued_jobs do
          assert_no_difference [ "User.count", "AccountUser.count", "Prompt.count", "ApiToken.count", "Chat.count" ] do
            post account_account_users_path(@second), params: { account_user: { email: email } }, headers: { "Accept-Language" => locale.to_s }
          end
        end
        assert_response :unprocessable_entity
        assert_select "#account_user_email[value=?][aria-invalid=true]", email
        assert_select "[data-form-errors-target=summary][role=alert][tabindex='-1'] a[href='#account_user_email']", text: I18n.t("nosia.settings_tools.#{key}", locale: locale)
        assert_select "#account_user_email_error", text: I18n.t("nosia.settings_tools.#{key}", locale: locale)
        assert_select "form[action=?]", account_account_users_path(@second)
      end
    end
  end

  test "owner adds existing user and removes only that membership with contextual confirmation" do
    assert_no_enqueued_jobs do
      assert_no_difference [ "User.count", "ApiToken.count", "Chat.count", "Prompt.count" ] do
        assert_difference("AccountUser.count", 1) do
          post account_account_users_path(@second), params: { account_user: { email: @outsider.email, account_id: @foreign.id } }
        end
      end
    end
    assert_redirected_to account_account_users_path(@second)
    follow_redirect!
    membership = @second.account_users.find_by!(user: @outsider)
    assert_select "form[action=?] button[data-turbo-confirm=?]", account_account_user_path(@second, membership), I18n.t("nosia.settings_tools.member_confirm", email: @outsider.email, account: @second.name)

    assert_no_difference [ "User.count", "ApiToken.count", "Chat.count" ] do
      assert_difference("AccountUser.count", -1) { delete account_account_user_path(@second, membership) }
    end
    assert_redirected_to account_account_users_path(@second)
    assert User.exists?(@outsider.id)
    assert @foreign.account_users.exists?(user: @outsider)
    assert_equal @first, @user.reload.first_account
  end

  test "owner protection and existing owner member foreign revoked context rules stay authoritative" do
    owner_membership = @second.account_users.find_by!(user: @user)
    assert_no_difference("AccountUser.count") { delete account_account_user_path(@second, owner_membership) }
    assert_redirected_to account_account_users_path(@second)
    assert_equal I18n.t("nosia.accounts.owner_cannot_remove"), flash[:alert]

    foreign_membership = @foreign.account_users.first
    assert_no_difference("AccountUser.count") { delete account_account_user_path(@second, foreign_membership) }
    assert_response :not_found

    sign_in_overview(@member)
    get account_account_users_path(@second)
    assert_response :forbidden
    assert_no_difference("AccountUser.count") do
      post account_account_users_path(@second), params: { account_user: { email: @outsider.email } }
    end
    assert_response :forbidden
    get account_account_users_path(@foreign), params: { account_id: @second.id }
    assert_response :not_found

    sign_in_overview
    owner_membership.destroy!
    get account_account_users_path(@second)
    assert_response :not_found
  end

  test "owner-only list is not mislabeled empty and malformed form containers fail closed" do
    get account_account_users_path(@empty)
    assert_select "[data-member-row]", count: 1
    assert_select "[data-members-only-owner]", text: I18n.t("nosia.settings_tools.no_additional_members")

    [ nil, "bad", [], { email: [] } ].each do |payload|
      assert_no_difference [ "User.count", "AccountUser.count" ] do
        post account_account_users_path(@second), params: { account_user: payload }, as: :json
      end
      assert_response :bad_request
    end
  end
end
