require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class CompactHeadersTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "application pages share one primary surface beside the navigation rail" do
    [ user_root_path, accounts_path, account_path(@second), sources_path, token_usage_path,
      settings_path, profile_path, account_agent_skills_path(@second), account_mcp_servers_path(@second),
      new_chat_path, chat_path(@chat) ].each do |path|
      get path

      assert_response :success
      assert_select "[data-application-scroll]", count: 1
      assert_select "#orbite-shell", count: 1
      assert_select ".n-orbite-rail", count: 1
      assert_select "[data-application-header]", count: 0
      assert_select ".n-orbite-rail > a.n-orbite-logo[href='#{root_path}'][aria-label]", count: 1 do
        assert_select "img[src*='nosia-logo'][alt=''][aria-hidden='true']", count: 1
      end
      if [ new_chat_path, chat_path(@chat) ].include?(path)
        assert_select "main#application-page.n-chat-main .n-orbite-reading#application-scroll[data-application-scroll]", count: 1
        assert_select "main[data-application-scroll], .n-orbite-chat-frame", count: 0
      else
        assert_select "main#application-scroll[data-application-scroll]", count: 1
        assert_select ".n-orbite-chat-frame", count: 0
      end
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

  %i[en fr].each do |locale|
    test "#{locale} page heading exposes useful trail without a redundant profile description" do
      get profile_path, headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select ".n-workspace-header h1", text: I18n.t("nosia.profile.title", locale: locale), count: 1
      assert_select ".n-workspace-header details, .n-header-details, [data-header-details]", count: 0
      assert_select ".n-workspace-header .n-workspace-context nav[aria-label='#{I18n.t('nosia.workspace.breadcrumb', locale: locale)}'] .n-workspace-trail", count: 1
      assert_select ".n-workspace-header p", text: I18n.t("nosia.profile.introduction", locale: locale), count: 0
      assert_select ".n-workspace-actions .n-workspace-trail", count: 0
      assert_select ".n-profile form", count: 2
    end

    test "#{locale} saved Usage is a labelled visible section with the exact live accounting subtree" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select "#application-scroll > .n-chat-header", count: 1
      assert_select ".n-chat-header > section#chat-usage-details[aria-labelledby=chat-usage-summary]", count: 1 do
        assert_select "h2#chat-usage-summary:not([tabindex])", text: I18n.t("nosia.chat_workspace.usage_details", locale: locale), count: 1
        assert_select "summary, details, [data-chat-detail], [open], [hidden]", count: 0
        assert_select "##{dom_id(@chat, :token_totals)}", count: 1
        assert_select "[data-chat-total-input]", text: "125"
        assert_select "[data-chat-total-output]", text: "24"
        assert_select ".n-chat-token-kind-heading", text: I18n.t("nosia.usage.per_kind", locale: locale)
        assert_select "ul.n-chat-token-kinds > li[data-usage-kind]", minimum: 1
        assert_select "table, caption, thead, tbody", count: 0
        assert_select "[data-estimate-note]", count: 1
      end
      assert_select ".n-chat-toolbar #chat-usage-details, .n-chat-dock #chat-usage-details", count: 0
    end
  end

  test "saved chat toolbar keeps its heading account and existing usage target" do
    get chat_path(@chat)

    assert_response :success
    assert_select ".n-chat-toolbar h1.n-chat-title", count: 1
    assert_select ".n-chat-toolbar [data-chat-account-label]", count: 0
    assert_select ".n-chat-header [data-chat-account-label]", text: @second.name, count: 1
    assert_select ".n-chat-header #workspace-history-trigger, .n-chat-header [aria-controls=chat-history], .n-chat-header a[href='#{user_root_path}']", count: 0
    assert_select "#workspace-history-rail-trigger, [data-orbite-composer-navigation]", count: 2
    assert_select ".n-chat-header a[href='#{new_chat_path}'], .n-chat-header .n-workspace-actions", count: 0
    assert_select "#chat-history > .n-orbite-navigation-actions > a[href='#{new_chat_path}']", text: I18n.t("nosia.chat_workspace.new_chat"), count: 1
    assert_select ".n-chat-header > section#chat-usage-details", count: 1 do
      assert_select "##{dom_id(@chat, :token_totals)}", count: 1
    end
  end
end
