require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class OrbiteShellTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  %i[en fr].each do |locale|
    test "lean History retains localized names and native delete in #{locale}" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "dialog#chat-history[aria-labelledby=chat-history-title]", count: 1 do
        assert_select "h2#chat-history-title.sr-only", text: I18n.t("nosia.orbite.navigation", locale: locale), count: 1
        assert_select ".n-orbite-panel-heading, .n-orbite-logo, img", count: 0
        close = I18n.t("nosia.chat_workspace.close", locale: locale)
        assert_select "button#workspace-navigation-close[type=button][data-chat-dialog-initial-focus][data-action='workspace-navigation#close']", count: 1 do |buttons|
          assert_equal close, buttons.first["aria-label"]
          assert_equal close, buttons.first["title"]
          assert_empty buttons.first.text.strip
          assert_select "svg[aria-hidden=true]", count: 1
        end
        assert_select "[data-history-chat='#{@chat.id}']", count: 1 do
          assert_select "a[href='#{chat_path(@chat)}'][aria-current=page]", count: 1
          assert_select "p > span", count: 0
          assert_select "p", text: @chat.account.name, count: 1
          assert_select "time[datetime='#{@chat.updated_at.iso8601}']", text: I18n.l(@chat.updated_at, format: :short, locale: locale), count: 1
          assert_select "form[action='#{chat_path(@chat)}'][method=post]", count: 1 do
            assert_select "input[name=_method][value=delete]", count: 1
            assert_select "button.n-workspace-danger.n-chat-history-delete", count: 1 do |buttons|
              assert_equal I18n.t("nosia.nav.delete_chat", locale: locale), buttons.first["aria-label"]
              assert_equal I18n.t("nosia.nav.delete_chat", locale: locale), buttons.first["title"]
              assert_equal I18n.t("nosia.actions.confirm_delete", locale: locale), buttons.first["data-turbo-confirm"]
              assert_empty buttons.first.text.strip
              assert_select "svg[aria-hidden=true]", count: 1
            end
          end
        end
      end
    end

    test "rail navigation label describes chat and non chat content in #{locale}" do
      get accounts_path, headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "#chat-history [data-history-chat]", count: 0
      assert_select "#workspace-history-rail-trigger", text: I18n.t("nosia.orbite.navigation", locale: locale), count: 1

      [ new_chat_path, chat_path(@chat) ].each do |path|
        get path, headers: { "Accept-Language" => locale.to_s }
        assert_response :success
        assert_select "#workspace-history-rail-trigger", text: I18n.t("nosia.orbite.expand_history", locale: locale), count: 1
      end
    end
  end

  test "chat reading surface is the final primary child inside main" do
    [ new_chat_path, chat_path(@chat) ].each do |path|
      get path
      assert_response :success
      assert_select "[data-application-scroll]", count: 1
      assert_select "main#application-page.n-chat-main .n-orbite-reading#application-scroll[data-application-scroll]", count: 1
      assert_select "main[data-application-scroll], .n-chat-transcript[data-application-scroll]", count: 0
    end

    get accounts_path
    assert_response :success
    assert_select "main#application-scroll[data-application-scroll]", count: 1
    assert_select ".n-orbite-chat-frame, .n-orbite-reading", count: 0
  end

  test "signed in routes share one navigation shell without private history outside chat" do
    scoped_routes = [ account_agent_skills_path(@second), account_mcp_servers_path(@second) ]
    routes = [ user_root_path, accounts_path, account_path(@second), sources_path,
      token_usage_path, settings_path, profile_path, *scoped_routes, api_tokens_path,
      system_prompts_path, new_chat_path, chat_path(@chat) ]

    routes.each do |path|
      get path
      assert_response :success
      assert_select "#orbite-shell[data-controller~=workspace-navigation][data-controller~=chat-dialog]", count: 1
      assert_select ".n-orbite-rail", count: 1
      assert_select "dialog#chat-history:not([open])", count: 1
      assert_select "main", count: 1
      assert_select "#theme-toggle, #language_preference_locale, #dropdownUser", count: 3
      assert_select "[data-application-header], .n-nav-bottom, #accordion-right-actions, #drawer-right", count: 0
      shortcut = scoped_routes.include?(path) ? new_chat_path(account_id: @second.id) : new_chat_path
      assert_select "#chat-history .n-orbite-panel-links a[href='#{shortcut}']", count: 1
      assert_select "[data-history-chat]", count: 0 unless [ new_chat_path, chat_path(@chat) ].include?(path)
    end
  end

  test "public root keeps its accessible header without private navigation" do
    delete logout_path
    get root_path

    assert_response :success
    assert_select "[data-application-header]", count: 1
    assert_select "#theme-toggle, #language_preference_locale", count: 2
    assert_select "#orbite-shell, #chat-history, [data-history-chat], #dropdownUser", count: 0
    assert_select "form[action='#{login_path}']", count: 1
  end

  test "history keeps personal roots current item and existing delete confirmation" do
    get chat_path(@chat)
    assert_response :success
    assert_select "[data-history-chat='#{@chat.id}']", count: 1 do
      assert_select "a[href='#{chat_path(@chat)}'][aria-current=page]", count: 1
      assert_select "form[action='#{chat_path(@chat)}'] [name=_method][value=delete]", count: 1
      assert_select "[data-turbo-confirm]", count: 1 do |controls|
        assert_equal I18n.t("nosia.actions.confirm_delete"), controls.first["data-turbo-confirm"]
      end
    end
    [ workspace(:chats, :workspace_peer_chat), workspace(:chats, :workspace_child_chat), chats(:picker_foreign_chat) ].each do |excluded|
      assert_select "[data-history-chat='#{excluded.id}']", count: 0
    end
    assert_select "##{dom_id(@chat, :token_totals)}", count: 1
  end

  test "native utility identities and logout method remain unique" do
    get chat_path(@chat)
    %w[theme-toggle theme-toggle-dark-icon theme-toggle-light-icon language_preference_locale dropdownUser dropdown].each do |id|
      assert_select "[id='#{id}']", count: 1
    end
    assert_select "form[action='#{language_preference_path}'] [name=_method][value=patch]", count: 1
    assert_select "a[href='#{logout_path}'][data-turbo-method=delete]", count: 1
    assert_select "a[href='#{profile_path}']", minimum: 1
  end
end
