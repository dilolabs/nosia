require "test_helper"
require_relative "../support/account_experience_fixtures"

class SettingsWorkspaceTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "hub has one localized breadcrumb heading and four descriptive links" do
    destinations = [ agent_skills_path, api_tokens_path, mcp_servers_path, system_prompts_path ]
    titles = %w[skills tokens mcp prompts]
    descriptions = %w[skills_description tokens_description mcp_description prompts_description]

    %i[en fr].each do |locale|
      get settings_path, headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "title", text: I18n.t("nosia.nav.settings", locale: locale)
      assert_select "main h1", text: I18n.t("nosia.nav.settings", locale: locale), count: 1
      assert_select "main nav", count: 1
      assert_select "main nav a[href='#{user_root_path}']"
      assert_select "main nav [aria-current='page']", text: I18n.t("nosia.nav.settings", locale: locale), count: 1
      assert_equal destinations, css_select("[data-settings-card]").map { |link| link["href"] }

      destinations.each_with_index do |path, index|
        assert_select "a[data-settings-card][href='#{path}']" do
          assert_select "h2", text: I18n.t("nosia.#{titles[index]}.title", locale: locale)
          assert_select "p", text: I18n.t("nosia.settings.#{descriptions[index]}", locale: locale)
          assert_select "svg[aria-hidden='true']", count: 2
          assert_select "[data-settings-card] a, [data-settings-card] button, [data-settings-card] input, [data-settings-card] select", count: 0
        end
      end

      assert_select "[data-settings-workspace] form, [data-settings-workspace] input", count: 0
      assert_select "main svg:not([aria-hidden='true'])", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "Settings and MCP omit unrelated drawers while other pages retain them and New chat stays accessible" do
    get settings_path
    assert_select "#accordion-right-actions, #drawer-right, [data-drawer-target]", count: 0
    assert_select "[data-settings-workspace] .hidden.lg\\:block a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
    assert_select ".lg\\:hidden a[href='#{new_chat_path}']", minimum: 1

    [ new_chat_path ].each do |path|
      get path
      assert_response :success
      assert_select "#accordion-right-actions, #drawer-right", count: 2
    end

    get system_prompts_path
    assert_response :success
    assert_select "#accordion-right-actions, #drawer-right", count: 0
    assert_select "[data-settings-tool] .n-workspace-header a[href=?]", new_chat_path
    assert_select ".lg\\:hidden a[href=?]", new_chat_path

    get mcp_servers_path
    assert_response :success
    assert_select "#accordion-right-actions, #drawer-right, [data-drawer-target]", count: 0
    assert_select ".n-workspace-header .hidden.lg\\:block a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
    assert_select ".lg\\:hidden a[href='#{new_chat_path}']", minimum: 1

    get account_settings_path(@second)
    assert_redirected_to account_path(@second)

    get api_tokens_path
    assert_response :success
    assert_select "#accordion-right-actions, #drawer-right", count: 0
    assert_select "[data-settings-tool] .n-workspace-header a[href=?]", new_chat_path
    assert_select ".lg\\:hidden a[href=?]", new_chat_path
  end

  test "hub remains static and read only for members and users without accounts" do
    [ @user, @member, experience(:users, :overview_no_account) ].each do |user|
      sign_in_overview(user)
      before = [ Account.count, Chat.count, Prompt.count, Document.count, Text.count, Qna.count, Website.count, ApiToken.count ]

      assert_no_enqueued_jobs { get settings_path, params: { account_id: @foreign.id } }
      assert_response :success
      assert_select "[data-settings-card]", count: 4
      assert_select "[data-workspace-scope]", count: 0
      assert_equal before, [ Account.count, Chat.count, Prompt.count, Document.count, Text.count, Qna.count, Website.count, ApiToken.count ]
    end
  end
end
