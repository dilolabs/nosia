require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class OrbiteShellTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "one user popover has distinct breakpoint triggers and no Flowbite owner" do
    [ accounts_path, new_chat_path(account_id: @second.id), chat_path(@chat) ].each do |path|
      get path
      assert_response :success
      assert_select "#orbite-shell[data-controller~=user-menu]", count: 1
      assert_select "#workspace-utilities-trigger[aria-controls=dropdown][aria-expanded=false][data-action='user-menu#toggle']", count: 1
      assert_select "#workspace-utilities-trigger[aria-controls=chat-history]", count: 0
      assert_select "#dropdownUser[aria-controls=dropdown][aria-expanded=false]", count: 1
      assert_select "#dropdown[popover=auto][data-user-menu-target=menu]", count: 1
      assert_select "#workspace-user-menu-home > #dropdown", count: 1
      assert_select "[data-dropdown-toggle=dropdown], #dropdown[role=menu], #dropdown[role=menuitem]", count: 0
      [ profile_path, settings_path ].each { |destination| assert_select "#dropdown a[href='#{destination}']", count: 1 }
      assert_select "#dropdown a[href='#{logout_path}'][data-turbo-method=delete]", count: 1
      assert_select "#language_preference_locale, #theme-toggle", count: 2
    end

    delete logout_path
    get root_path
    assert_response :success
    assert_select "#dropdown, #dropdownUser, #workspace-utilities-trigger, [data-controller~=user-menu]", count: 0
    assert_select "#language_preference_locale, #theme-toggle", count: 2
  end

  %i[en fr].each do |locale|
    test "chat headers omit Home and History controls in #{locale}" do
      [ new_chat_path(account_id: @second.id), chat_path(@chat) ].each do |path|
        get path, headers: { "Accept-Language" => locale.to_s }
        assert_response :success
        assert_select ".n-chat-header #workspace-history-trigger, .n-chat-header [aria-controls=chat-history]", count: 0
        assert_select ".n-chat-header a[href='#{user_root_path}']", count: 0
        assert_select "#workspace-history-rail-trigger", count: 1
        assert_select "[data-orbite-composer-navigation]", count: 1
        assert_select "#workspace-mobile-trigger", count: 0
      end
    end

    test "new chat without an account retains global mobile navigation in #{locale}" do
      @user.account_users.destroy_all
      get new_chat_path, headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select "#chat-history > .n-orbite-navigation-actions > a", count: 0
      assert_select "#chat-history > .n-orbite-navigation-actions > #workspace-navigation-close[data-chat-dialog-initial-focus]", count: 1
      assert_select ".n-chat-header", count: 1
      assert_select ".n-chat-header a, .n-chat-header button, .n-chat-toolbar, .n-chat-header .n-workspace-actions", count: 0
      assert_select "[data-orbite-composer-navigation], .n-chat-composer", count: 0
      assert_select "#workspace-mobile-trigger[aria-controls=chat-history]", count: 1
      assert_select "#workspace-history-rail-trigger", count: 1
      assert_select "[data-chat-no-account][role=status]", count: 1
      assert_select ".n-chat-start a[href='#{accounts_path}']", count: 1
      assert_select "#chat-history [data-history-empty]", text: I18n.t("nosia.chat_workspace.no_history", locale: locale), count: 1
      assert_select ".n-chat-start h1", text: I18n.t("nosia.chat_workspace.new_title", locale: locale), count: 1
    end

    test "history rows omit delete controls in #{locale}" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "#chat-history [data-history-chat]", minimum: 1 do |rows|
        rows.each do |row|
          assert_select row, "form, button, [data-turbo-method=delete], [data-method=delete], [data-turbo-confirm]", count: 0
          assert_select row, "div > a[href]", count: 1
        end
      end
    end

    test "lean History retains localized names without delete controls in #{locale}" do
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
          assert_select "a > .n-chat-history-title", text: "What are the key findings in this report?", count: 1
          assert_select "a > .n-chat-history-meta.n-workspace-help > .n-chat-history-account", text: @chat.account.name, count: 1
          assert_select "div > p", count: 0
          assert_select "time[datetime='#{@chat.updated_at.iso8601}']", text: I18n.l(@chat.updated_at, format: :short, locale: locale), count: 1
          assert_select "form, button, [data-turbo-method=delete], [data-method=delete], [data-turbo-confirm]", count: 0
        end
      end
    end

    test "density chrome preserves independent localized navigation and empty guidance in #{locale}" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "dialog#chat-history[aria-labelledby=chat-history-title]", count: 1 do
        assert_select "h2#chat-history-title.sr-only", text: I18n.t("nosia.orbite.navigation", locale: locale), count: 1
        assert_select "section[data-orbite-history]", count: 1 do |sections|
          assert_equal I18n.t("nosia.chat_workspace.history_title", locale: locale), sections.first["aria-label"]
          assert_select "h3, .n-orbite-history-heading, p.n-workspace-help:not([data-history-empty])", count: 0
        end
        assert_select "button#workspace-navigation-close[data-action='workspace-navigation#close']", count: 1
        assert_select ".n-orbite-panel-links a", minimum: 1
      end

      @user.account_users.destroy_all
      get new_chat_path, headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "#chat-history [data-history-empty]", text: I18n.t("nosia.chat_workspace.no_history", locale: locale), count: 1
      assert_select "#chat-history [data-history-chat]", count: 0
    end

    test "density labels retain escaped complete previews and accounts in #{locale}" do
      question = workspace(:messages, :workspace_question)
      question.update_columns(content: "A" * 240)
      account = %q{Research "quoted" & <img src=x onerror="alert(1)"> <script>bad()</script>}
      @second.update_columns(name: account)
      preview = "A" * 119 + "…"

      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "[data-history-chat='#{@chat.id}']", count: 1 do
        assert_select "a > .n-chat-history-title, a > .n-chat-history-meta > .n-chat-history-account", count: 2
        assert_select "a > .n-chat-history-title", text: preview, count: 1 do |titles|
          assert_equal 120, titles.first.text.length
          assert_equal preview, titles.first.parent["title"]
          assert_includes titles.first.parent.text, account
        end
        assert_select "a > .n-chat-history-meta > .n-chat-history-account", text: account, count: 1 do |accounts|
          assert_equal account, accounts.first["title"]
          assert_includes accounts.first.parent.parent.text, preview
        end
        assert_select "img, script, [onerror]", count: 0
        assert_select "time[datetime='#{@chat.updated_at.iso8601}']", text: I18n.l(@chat.updated_at, format: :short, locale: locale), count: 1
        assert_select "form, button, [data-turbo-method=delete], [data-method=delete], [data-turbo-confirm]", count: 0
      end
      assert_select ".n-chat-header h1", text: preview, count: 1
      assert_equal "A" * 240, question.reload.content
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

  test "history keeps personal roots and current item without delete controls" do
    get chat_path(@chat)
    assert_response :success
    assert_select "[data-history-chat='#{@chat.id}']", count: 1 do
      assert_select "a[href='#{chat_path(@chat)}'][aria-current=page]", count: 1
      assert_select "form, button, [data-turbo-method=delete], [data-method=delete], [data-turbo-confirm]", count: 0
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
