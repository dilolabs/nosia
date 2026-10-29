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
      assert_select "nav.n-application-header a.n-application-home[href='#{root_path}'][aria-label]", count: 1 do
        assert_select "img.h-6[src*='nosia-logo'][alt=''][aria-hidden='true']", count: 1
      end
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

  test "page heading discloses secondary description and breadcrumb" do
    get profile_path

    assert_response :success
    assert_select ".n-workspace-header h1", count: 1
    assert_select ".n-workspace-header details[data-header-details]:not([open])", count: 1 do
      assert_select "summary", text: I18n.t("nosia.layout.details"), count: 1
      assert_select ".n-workspace-help", text: I18n.t("nosia.profile.introduction"), count: 1
      assert_select "nav[aria-label='#{I18n.t('nosia.workspace.breadcrumb')}'] .n-workspace-trail", count: 1
    end
  end

  test "saved chat toolbar keeps its heading account actions and existing usage target" do
    get chat_path(@chat)

    assert_response :success
    assert_select ".n-chat-toolbar h1.n-chat-title", count: 1
    assert_select ".n-chat-toolbar [data-chat-account-label]", text: @second.name, count: 1
    assert_select ".n-chat-toolbar button[aria-controls='chat-history']", text: I18n.t("nosia.chat_workspace.history"), count: 1
    assert_select ".n-chat-toolbar a[href='#{new_chat_path}']", text: I18n.t("nosia.chat_workspace.new_chat"), count: 1
    assert_select ".n-chat-toolbar #chat-usage-details:not([open])", count: 1 do
      assert_select "##{dom_id(@chat, :token_totals)}", count: 1
    end
  end
end
