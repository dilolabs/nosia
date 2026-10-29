require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class CompactHeadersTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "application pages share one scrolling surface around branding and main" do
    [ user_root_path, accounts_path, account_path(@second), sources_path, token_usage_path,
      settings_path, profile_path, account_agent_skills_path(@second), account_mcp_servers_path(@second),
      new_chat_path, chat_path(@chat) ].each do |path|
      get path

      assert_response :success
      assert_select "[data-application-scroll]", count: 1
      assert_select "[data-application-scroll] > nav[data-application-header]", count: 1
      assert_select "[data-application-scroll] main", count: 1
      assert_select "main", count: 1
      assert_select "#theme-toggle", count: 1
      assert_select "#language_preference_locale", count: 1
      assert_select "#dropdownUser", count: 1
    end
  end

  test "signed out login keeps the same scrolling shell without a user menu" do
    delete logout_path
    get root_path

    assert_response :success
    assert_select "[data-application-scroll]", count: 1
    assert_select "[data-application-scroll] > nav[data-application-header]", count: 1
    assert_select "[data-application-scroll] main", count: 1
    assert_select "form[action='#{login_path}']", count: 1
    assert_select "#theme-toggle", count: 1
    assert_select "#language_preference_locale", count: 1
    assert_select "#dropdownUser", count: 0
  end
end
