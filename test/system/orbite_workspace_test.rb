require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class OrbiteWorkspaceSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include OrbiteBrowserChecks

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(*@original_size) if @original_size
  end

  test "context scrolls away while the real composer remains visible in every viewport" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      find("lexxy-editor .lexxy-editor__content").send_keys("Draft must stay in this editor")
      page.execute_script("window.orbiteDockEditor = document.querySelector('lexxy-editor')")
      page.execute_script(<<~JS)
        const surface = document.querySelector('[data-application-scroll]')
        surface.scrollTop = 0; surface.dispatchEvent(new Event('scroll'))
      JS
      orbite_settle
      before = page.evaluate_script("document.querySelector('.n-chat-dock').getBoundingClientRect().toJSON()")
      page.execute_script(<<~JS)
        const surface = document.querySelector('[data-application-scroll]')
        surface.scrollTop = 700; surface.dispatchEvent(new Event('scroll'))
      JS
      orbite_settle
      sample = page.evaluate_script(<<~JS)
        (() => { const rect = s => document.querySelector(s).getBoundingClientRect().toJSON(); return {
          surface: rect('[data-application-scroll]'), header: rect('.n-chat-header'), dock: rect('.n-chat-dock'),
          top: document.querySelector('[data-application-scroll]').scrollTop,
          nested: [document.querySelector('main').scrollTop, document.querySelector('.n-chat-transcript').scrollTop],
          sameEditor: window.orbiteDockEditor === document.querySelector('lexxy-editor'), viewport: [innerWidth, innerHeight] }; })()
      JS
      orbite_record("dock-#{width}x#{height}", sample, screenshot: true)
      assert_operator sample.fetch("top"), :>=, 699, sample.to_json
      assert_operator sample.fetch("header").fetch("bottom"), :<=, sample.fetch("surface").fetch("top"), sample.to_json
      assert_in_delta before.fetch("top"), sample.fetch("dock").fetch("top"), 1, sample.to_json
      assert_operator sample.fetch("surface").fetch("bottom"), :<=, sample.fetch("dock").fetch("top") + 1, sample.to_json
      assert_operator sample.fetch("dock").fetch("bottom"), :<=, height, sample.to_json
      assert_equal [ 0, 0 ], sample.fetch("nested"), sample.to_json
      assert sample.fetch("sameEditor"), sample.to_json
      assert_selector "lexxy-editor .lexxy-editor__content", text: "Draft must stay in this editor"
      orbite_assert_reachable(".n-composer-send")
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "mobile navigation remains usable after the context has scrolled away and during generation" do
    orbite_viewport(375, 812)
    @chat.start_generation!
    visit chat_path(@chat)
    assert_button "Stop generating", enable_aria_label: true
    assert_selector "[data-orbite-composer-navigation]:not([disabled])"
    orbite_assert_reachable("[data-orbite-composer-navigation]")
    find("[data-orbite-composer-navigation]").click
    assert_selector "#chat-history:modal"
    orbite_tab_to("#chat-history [data-action='workspace-navigation#close']")
    page.driver.browser.action.send_keys(:escape).perform
    assert_selector "[data-orbite-composer-navigation]:focus"
    orbite_assert_reachable(".n-composer-stop")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "reserved new and saved composers keep native formatting and labels reachable" do
    [ [ 375, 812 ], [ 812, 375 ] ].each do |width, height|
      orbite_viewport(width, height)
      { new: new_chat_path(account_id: @second.id), saved: chat_path(@chat) }.each do |entry, path|
        [ false, true ].each do |dark|
          visit path
          assert_selector "lexxy-editor[connected]"
          orbite_theme(dark)
          editor = find("lexxy-editor")
          assert_selector "label[for='#{editor[:id]}']", text: "Message", visible: :all
          find("lexxy-editor .lexxy-editor__content").send_keys("Native formatting stays in this editor")
          find("summary[aria-label=Formatting]").click
          assert_selector ".n-chat-composer[data-formatting-open] lexxy-toolbar"
          orbite_assert_reachable("lexxy-toolbar button[name=bold]")
          orbite_assert_reachable(".n-composer-send")
          orbite_assert_reachable(".n-composer-notice")
          orbite_record("formatting-#{entry}-#{dark ? 'dark' : 'light'}-#{width}x#{height}", { editorId: editor[:id], formattingOpen: true }, screenshot: true)
        end
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "new chat without an account has one guidance surface and no fake composer" do
    orbite_open_utilities
    find("#dropdownUser").click
    find("#dropdown a[href='#{logout_path}']").click
    assert_selector "form[action='#{login_path}']"
    fill_in "email", with: users(:picker_no_account).email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"

    [ [ 375, 812 ], [ 812, 375 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit new_chat_path
      [ false, true ].each do |dark|
        orbite_theme(dark)
        assert_selector ".n-orbite-reading [data-chat-no-account]", count: 1
        assert_no_selector ".n-chat-dock, lexxy-editor, [data-orbite-composer-navigation]", visible: :all
        orbite_assert_reachable("[data-chat-no-account]")
        orbite_assert_reachable(".n-chat-start a[href='#{accounts_path}']")
        orbite_record("no-account-#{dark ? 'dark' : 'light'}-#{width}x#{height}", { guidance: true, composer: false }, screenshot: true)
        find("#workspace-history-trigger").click
        assert_selector "#chat-history:modal"
        page.driver.browser.action.send_keys(:escape).perform
        assert_selector "#workspace-history-trigger:focus"
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "downward navigation reflow keeps a paused saved paragraph and visible focus" do
    orbite_viewport(812, 375)
    visit chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep this editor through downward navigation reflow")
    page.execute_script("window.orbiteDownwardEditor = document.querySelector('lexxy-editor')")
    orbite_tab_to("#workspace-history-rail-trigger", reverse: true)
    page.execute_script(<<~JS)
      const surface = document.querySelector('[data-application-scroll]')
      const paragraph = document.querySelectorAll('.ai-response-content p')[19]
      surface.scrollTop += paragraph.getBoundingClientRect().top - surface.getBoundingClientRect().top - 24
      surface.dispatchEvent(new Event('scroll'))
    JS
    orbite_settle_reader
    assert_selector ".n-chat-workspace[data-reader-following=false]"
    before = orbite_paragraph_anchor
    assert_operator page.evaluate_script("document.querySelector('#workspace-history-trigger').getBoundingClientRect().bottom"), :<, 0
    assert_selector "#workspace-history-rail-trigger:focus"
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#chat-history:modal"
    assert page.evaluate_script("document.querySelector('#chat-history').contains(document.activeElement)")

    orbite_viewport(375, 812)
    orbite_settle_reader
    orbite_assert_downward_focus("saved-chat-downward", destination: "[data-orbite-composer-navigation]")
    after = orbite_paragraph_anchor
    orbite_record("saved-chat-downward-anchor", { before: before, after: after })
    assert_equal before.fetch("text"), after.fetch("text"), after.to_json
    assert_in_delta before.fetch("offset"), after.fetch("offset"), 1, after.to_json
    assert_selector ".n-chat-workspace[data-reader-following=false]"
    assert_operator page.evaluate_script("(() => { const surface = document.querySelector('[data-application-scroll]'); return surface.scrollHeight - surface.clientHeight - surface.scrollTop })()"), :>, 80
    assert_equal [ 0, 0 ], page.evaluate_script("[document.querySelector('main').scrollTop, document.querySelector('.n-chat-transcript').scrollTop]")
    assert page.evaluate_script("window.orbiteDownwardEditor === document.querySelector('lexxy-editor')")
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this editor through downward navigation reflow"
    orbite_assert_next_tab_usable
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "downward navigation reflow gives a long non chat page a visible focus handoff" do
    orbite_viewport(812, 375)
    visit accounts_path
    orbite_tab_to("#workspace-history-rail-trigger", reverse: true)
    # Explicit geometry-only fixture, not a claim of a long account workflow.
    page.execute_script(<<~JS)
      const surface = document.querySelector('[data-application-scroll]'), fixture = document.createElement('div')
      fixture.dataset.orbiteDownwardOverflowFixture = ''
      fixture.inert = true
      fixture.style.cssText = 'height:2200px;flex:none'
      surface.append(fixture)
      surface.scrollTop = 700
      surface.dispatchEvent(new Event('scroll'))
    JS
    orbite_settle
    assert_selector "main[data-application-scroll] > [data-orbite-downward-overflow-fixture][inert]", count: 1, visible: :all
    assert_operator page.evaluate_script("document.querySelector('main h1').getBoundingClientRect().bottom"), :<, 0
    refute page.evaluate_script("document.querySelector('#workspace-mobile-trigger').checkVisibility()")
    assert_selector "#workspace-history-rail-trigger:focus"
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#chat-history:modal"

    orbite_viewport(375, 812)
    assert_operator page.evaluate_script("document.querySelector('#workspace-mobile-trigger').getBoundingClientRect().bottom"), :<, 0
    orbite_assert_downward_focus("non-chat-downward-geometry")
    assert_in_delta 700, page.evaluate_script("document.querySelector('[data-application-scroll]').scrollTop"), 1
    assert_no_selector "[data-history-chat]", visible: :all
    orbite_assert_next_tab_usable
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "inline History panel Close resumes after a real refresh" do
    orbite_viewport(1400, 1000)
    visit chat_path(@chat)
    assert_selector "#chat-history[data-inline=true][open]"
    orbite_refresh
    assert_selector "#chat-history[data-inline=true][open]"
    assert_no_selector "#chat-history:modal"
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep this editor while closing refreshed History")
    page.execute_script("window.orbiteRefreshedEditor = document.querySelector('lexxy-editor')")
    orbite_tab_to("#workspace-navigation-close", reverse: true)
    page.driver.browser.action.send_keys(:enter).perform

    assert_no_selector "#chat-history[open]", visible: :all
    orbite_record("refreshed-inline-panel-close", orbite_close_state)
    orbite_assert_history_closed("#workspace-history-rail-trigger")
    assert page.evaluate_script("window.orbiteRefreshedEditor === document.querySelector('lexxy-editor')")
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this editor while closing refreshed History"
    assert_equal [ 0, 0 ], page.evaluate_script("[document.querySelector('main').scrollTop, document.querySelector('.n-chat-transcript').scrollTop]")

    orbite_refresh
    assert_no_selector "#chat-history[open]", visible: :all
    assert_no_selector "#chat-history:modal"
    assert_selector "#workspace-history-rail-trigger[aria-expanded=false]"
    assert_selector "#workspace-history-trigger[aria-expanded=false]", visible: :all
    ids = page.evaluate_script("[...document.querySelectorAll('[id]')].map(node => node.id)")
    assert_equal ids.uniq, ids
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  [ [ 1024, 1000 ], [ 375, 812 ] ].product(%w[close escape]).each do |(width, height), action|
    test "recovered History #{action} resumes closed state at #{width}px" do
      orbite_viewport(width, height)
      visit chat_path(@chat)
      opener = width >= 768 ? "#workspace-history-rail-trigger" : "#workspace-history-trigger"
      find(opener).click
      assert_selector "#chat-history:modal"
      orbite_refresh
      assert_selector "#chat-history:modal"
      assert page.evaluate_script("document.querySelector('#chat-history').contains(document.activeElement)")

      if action == "close"
        find("#workspace-navigation-close").click
      else
        page.driver.browser.action.send_keys(:escape).perform
      end
      assert_no_selector "#chat-history[open]", visible: :all
      orbite_record("recovered-#{width}-#{action}", orbite_close_state)
      orbite_assert_history_closed(opener)
      orbite_refresh
      assert_no_selector "#chat-history[open]", visible: :all
      assert_no_selector "dialog:modal"
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "shared History modal alone selects Close without consuming editor autofocus" do
    orbite_viewport(1024, 1000)
    visit chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    assert_selector "#message_content-content:focus"
    assert_no_selector "#chat-history [autofocus]", visible: :all
    find("#workspace-history-trigger").click
    assert_selector "#chat-history:modal"
    assert_selector "#chat-history [data-action='workspace-navigation#close']:focus"
    page.driver.browser.action.send_keys(:escape).perform
    assert_selector "#workspace-history-trigger:focus"
    assert_no_selector "#chat-history [autofocus]", visible: :all
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "shared History refresh restores its current focus and replaced opener but caches closed" do
    orbite_viewport(1024, 1000)
    visit chat_path(@chat)
    find("#workspace-history-trigger").click
    orbite_tab_to("#language_preference_locale")
    page.execute_script(<<~JS)
      window.orbiteOriginalOpener = document.querySelector('#workspace-history-trigger')
      document.addEventListener('turbo:before-cache', () => {
        window.orbiteCachedModalIds = [...document.querySelectorAll('dialog[open]')].map(node => node.id)
      }, { once: true })
      document.addEventListener('turbo:before-render', () => {
        const trigger = document.querySelector('#workspace-history-trigger')
        trigger.replaceWith(trigger.cloneNode(true))
      }, { once: true })
    JS
    orbite_refresh
    assert_equal [], page.evaluate_script("window.orbiteCachedModalIds")
    refute page.evaluate_script("window.orbiteOriginalOpener.isConnected")
    assert_selector "#chat-history:modal"
    assert_selector "#language_preference_locale:focus"
    assert_selector "#workspace-history-trigger[aria-expanded=true]", visible: :all
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#chat-history:modal"
    assert_selector "#workspace-history-trigger:focus"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "shared History refresh does not steal deliberate outside focus or replace newer Tools" do
    orbite_viewport(1024, 1000)
    %w[outside tools].each do |destination|
      visit chat_path(@chat)
      find("#workspace-history-trigger").click
      assert_selector "#chat-history:modal"
      # Deliberate focus/modal intent at the real lifecycle boundary, not native
      # Tab evidence or a replacement rendering/delivery gate.
      page.execute_script(<<~JS, destination)
        const destination = arguments[0]
        document.addEventListener('turbo:before-render', () => {
          if (destination === 'outside') document.querySelector('#workspace-utilities-trigger').focus({ preventScroll: true })
          else document.querySelector('.n-composer-tools-trigger').click()
        }, { once: true })
      JS
      orbite_refresh
      assert_no_selector "#chat-history:modal"
      if destination == "outside"
        assert_no_selector "dialog:modal"
        assert_selector "#workspace-utilities-trigger:focus"
      else
        assert_selector "#mcp-selector-modal:modal"
        assert_selector "dialog:modal", count: 1
        assert page.evaluate_script("document.querySelector('#mcp-selector-modal').contains(document.activeElement)")
        find("#mcp-selector-modal button[aria-label=Close]").click
        assert_selector ".n-composer-tools-trigger:focus"
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "shared History recovery is consumed before standalone cache cleanup" do
    orbite_viewport(1024, 1000)
    visit chat_path(@chat)
    find("#workspace-history-trigger").click
    orbite_refresh
    assert_selector "#chat-history:modal"
    page.execute_script(<<~JS)
      document.dispatchEvent(new Event('turbo:before-cache'))
      document.dispatchEvent(new Event('turbo:render'))
    JS
    assert_no_selector "#chat-history[open]", visible: :all
    assert_no_selector "dialog:modal"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "explicitly closed shared History stays closed on refresh and another conversation" do
    orbite_viewport(1024, 1000)
    visit chat_path(@chat)
    find("#workspace-history-trigger").click
    assert_selector "#chat-history:modal"
    find("#chat-history [data-action='workspace-navigation#close']").click
    assert_no_selector "#chat-history:modal"
    orbite_refresh
    assert_no_selector "#chat-history[open]", visible: :all
    find("#workspace-history-trigger").click
    first_chat = workspace(:chats, :workspace_first_chat)
    within("[data-history-chat='#{first_chat.id}']") { click_link "First account question" }
    assert_current_path chat_path(first_chat)
    assert_no_selector "#chat-history[open]", visible: :all
    page.go_back
    assert_current_path chat_path(@chat)
    assert_no_selector "#chat-history[open]", visible: :all
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "distinct chat surface scrolls without nested scrolling" do
    orbite_viewport(1400, 1000)
    visit chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    orbite_settle
    refute page.evaluate_script("document.querySelector('main') === document.querySelector('[data-application-scroll]')")
    assert page.evaluate_script("document.querySelector('main').contains(document.querySelector('[data-application-scroll]'))")
    assert_selector "main#application-page .n-chat-workspace > .n-orbite-reading#application-scroll[data-application-scroll]", count: 1
    assert_selector "[data-application-scroll]", count: 1
    [ 0, 700 ].each do |top|
      page.execute_script(<<~JS, top)
        const surface = document.querySelector('[data-application-scroll]')
        surface.scrollTop = arguments[0]
        surface.dispatchEvent(new Event('scroll'))
      JS
      orbite_settle
    end
    sample = page.evaluate_script(<<~JS)
      (() => {
        const sample = selector => { const node = document.querySelector(selector); return { top: node.scrollTop, bounds: node.getBoundingClientRect().toJSON() } }
        return { surface: sample('[data-application-scroll]'), main: sample('main'), transcript: sample('.n-chat-transcript') }
      })()
    JS
    orbite_record("distinct-chat-surface", sample, screenshot: true)
    assert_operator sample.fetch("surface").fetch("top"), :>=, 699, sample.to_json
    assert_equal 0, sample.fetch("main").fetch("top"), sample.to_json
    assert_equal 0, sample.fetch("transcript").fetch("top"), sample.to_json
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "wide history collapses inline without replacing the editor or draft" do
    orbite_viewport(1400, 1000)
    visit chat_path(@chat)
    assert_selector "#chat-history[data-inline=true][open]"
    assert_no_selector "#chat-history:modal"
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep the actual editor")
    page.execute_script("window.orbiteEditor = document.querySelector('lexxy-editor')")

    find("#workspace-history-rail-trigger").click
    assert_no_selector "#chat-history[open]", visible: :all
    assert_selector "#workspace-history-rail-trigger[aria-expanded=false]"
    find("#workspace-history-rail-trigger").click
    assert_selector "#chat-history[data-inline=true][open]"
    assert_selector "#workspace-history-rail-trigger[aria-expanded=true]"
    assert page.evaluate_script("window.orbiteEditor === document.querySelector('lexxy-editor')")
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep the actual editor"
    orbite_record("wide-inline-light", { editorPreserved: true }, screenshot: true)
    orbite_theme(true)
    orbite_record("wide-inline-dark", { editorPreserved: true }, screenshot: true)
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  %w[en fr].product(%w[new saved], [ false, true ]).each do |locale, entry, dark|
    test "inline history keeps readable rows and native controls in #{locale} on #{entry} in #{dark ? 'dark' : 'light'}" do
      @second.update_columns(name: "CompteDeRecherche" * 12)
      orbite_viewport(1400, 1000)
      orbite_select_language(locale.upcase)
      visit(entry == "new" ? new_chat_path(account_id: @second.id) : chat_path(@chat))
      assert_selector "html[lang=#{locale}]"
      assert_selector "lexxy-editor[connected]"
      assert_selector "#chat-history[data-inline=true][open]"
      orbite_theme(dark)
      conversations = { workspace(:chats, :workspace_first_chat) => "First account question",
        @chat => "What are the key findings in this report?" }
      sample = orbite_history_rows
      orbite_record("inline-history-#{entry}-#{locale}-#{dark ? 'dark' : 'light'}", sample, screenshot: true)
      assert_in_delta 240, sample.fetch("panel").fetch("width"), 1
      assert_operator sample.fetch("scrollWidth"), :<=, sample.fetch("clientWidth"), sample.to_json
      conversations.each do |conversation, title|
        row = "#chat-history [data-history-chat='#{conversation.id}']"
        geometry = sample.fetch("rows").find { |item| item.fetch("id") == conversation.id.to_s }
        refute_nil geometry, sample.to_json
        # Eight actual font ems allow several normal words, not merely a positive
        # hitbox or a one-character column. The panel itself is not widened.
        minimum = [ geometry.fetch("row").fetch("width"), geometry.fetch("fontSize") * 8 ].min
        assert_operator geometry.fetch("body").fetch("width"), :>=, minimum, geometry.to_json
        assert_operator geometry.fetch("link").fetch("width"), :>=, minimum, geometry.to_json
        assert geometry.fetch("textFits"), geometry.to_json
        assert geometry.fetch("separateAction"), geometry.to_json
        %w[link form button].each do |part|
          bounds = geometry.fetch(part)
          assert_operator bounds.fetch("left"), :>=, geometry.fetch("row").fetch("left"), geometry.to_json
          assert_operator bounds.fetch("right"), :<=, geometry.fetch("row").fetch("right"), geometry.to_json
        end
        assert_operator geometry.fetch("button").fetch("height"), :>=, 44, geometry.to_json
        assert_selector "#{row} > div > a", text: title, exact_text: true
        assert_selector "#{row} > div > p", text: conversation.account.name, exact_text: true
        assert_selector "#{row} time[datetime='#{conversation.updated_at.iso8601}']",
          text: I18n.l(conversation.updated_at, format: :short, locale: locale), exact_text: true
        assert_selector "#{row} > div > a[aria-current=page]", count: entry == "saved" && conversation == @chat ? 1 : 0
        assert_selector "#{row} > div > p > span", text: I18n.t("nosia.chat_workspace.current", locale: locale),
          count: entry == "saved" && conversation == @chat ? 1 : 0
        assert_selector "#{row} form[action='#{chat_path(conversation)}'][method=post] input[name=_method][value=delete]", visible: :all
        button = find("#{row} button")
        assert_equal I18n.t("nosia.nav.delete_chat", locale: locale), button.text
        assert_equal I18n.t("nosia.actions.confirm_delete", locale: locale), button["data-turbo-confirm"]
      end
      controls = conversations.keys.flat_map do |conversation|
        row = "#chat-history [data-history-chat='#{conversation.id}']"
        [ "#{row} > div > a", "#{row} button" ]
      end
      controls.each { |selector| orbite_history_tab_to(selector) }
      controls.reverse_each { |selector| orbite_history_tab_to(selector, reverse: true) }
      assert_equal 0, page.evaluate_script("document.scrollingElement.scrollTop")
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "one native history panel reflows across mobile tablet and inline modes" do
    orbite_viewport(375, 812)
    visit new_chat_path(account_id: @second.id)
    assert_selector "#chat-history:not([open])", visible: :all
    find("#workspace-history-trigger").click
    assert_selector "#chat-history:modal"
    page.execute_script("window.orbitePanel = document.querySelector('#chat-history')")
    orbite_tab_to("#language_preference_locale")
    orbite_tab_to("#chat-history [data-action='workspace-navigation#close']", reverse: true)
    orbite_record("mobile-modal-light", { modal: true }, screenshot: true)

    orbite_viewport(768, 1024)
    assert_no_selector "#chat-history:modal"
    assert page.evaluate_script("window.orbitePanel === document.querySelector('#chat-history')")
    find("#workspace-history-rail-trigger").click
    assert_selector "#chat-history:modal"
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#chat-history:modal"
    assert_selector "#workspace-history-rail-trigger:focus"

    orbite_viewport(1400, 1000)
    assert_selector "#chat-history[data-inline=true][open]"
    assert_no_selector "#chat-history:modal"
    assert page.evaluate_script("window.orbitePanel === document.querySelector('#chat-history')")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "bottom utility menu is reachable in both themes on mobile and desktop" do
    [ [ 375, 812 ], [ 1400, 1000 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit chat_path(@chat)
      [ false, true ].each do |dark|
        orbite_theme(dark)
        orbite_open_utilities
        find("#dropdownUser").click
        assert_selector "#dropdown"
        [ profile_path, settings_path, logout_path ].each do |path|
          orbite_assert_reachable("#dropdown a[href='#{path}']")
        end
        orbite_record("bottom-utilities-#{width}-#{dark ? 'dark' : 'light'}", { dropdown: true }, screenshot: true)
        find("#dropdownUser").click
        assert_no_selector "#dropdown"
        orbite_close_navigation
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "mobile utilities retain French dark mode and native profile navigation" do
    orbite_viewport(375, 812)
    visit accounts_path
    orbite_select_language("FR")
    assert_selector "html[lang=fr]"
    orbite_theme(true)
    orbite_open_utilities
    assert_selector "#chat-history:modal"
    assert_no_selector "[data-history-chat]", visible: :all
    orbite_tab_to("#dropdownUser")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#dropdown"
    orbite_assert_reachable("#dropdown a[href='#{profile_path}']")
    orbite_record("mobile-utilities-profile-dark-fr", { modal: true, dropdown: true }, screenshot: true)
    orbite_tab_to("#dropdown a[href='#{profile_path}']")
    page.driver.browser.action.send_keys(:enter).perform
    assert_current_path profile_path
    assert_selector "h1", text: I18n.t("nosia.profile.title", locale: :fr)
    assert_selector "html[lang=fr].dark"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  private
    def orbite_history_rows
      page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector('#chat-history'), content = panel.querySelector('.n-orbite-panel-content')
          const rect = node => node.getBoundingClientRect().toJSON()
          return { panel: rect(panel), clientWidth: content.clientWidth, scrollWidth: content.scrollWidth,
            rows: [...panel.querySelectorAll('[data-history-chat]')].map(row => {
              const body = row.querySelector(':scope > div'), link = body.querySelector('a')
              const form = row.querySelector('form'), button = form.querySelector('button'), b = rect(body), f = rect(form)
              const textFits = [...body.querySelectorAll('a, p')].every(node => {
                const range = document.createRange(); range.selectNodeContents(node)
                return [...range.getClientRects()].every(line => line.left >= b.left - 1 && line.right <= b.right + 1)
              })
              return { id: row.dataset.historyChat, row: rect(row), body: b, link: rect(link), form: f, button: rect(button),
                fontSize: parseFloat(getComputedStyle(link).fontSize), textFits,
                separateAction: f.top >= b.bottom || b.top >= f.bottom || f.left >= b.right || b.left >= f.right }
            }) }
        })()
      JS
    end

    def orbite_history_tab_to(selector, reverse: false)
      # Only trusted Tab/Shift+Tab brings vertically offscreen rows into the
      # panel's own scrollport. Never focus(), scrollIntoView(), or click Delete.
      sample = orbite_tab_to(selector, reverse: reverse)
      content = page.evaluate_script("document.querySelector('#chat-history .n-orbite-panel-content').getBoundingClientRect().toJSON()")
      assert_operator sample.fetch("top"), :>=, content.fetch("top"), sample.to_json
      assert_operator sample.fetch("bottom"), :<=, content.fetch("bottom"), sample.to_json
      assert_operator sample.fetch("left"), :>=, content.fetch("left"), sample.to_json
      assert_operator sample.fetch("right"), :<=, content.fetch("right"), sample.to_json
    end

    def orbite_settle_reader
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        Promise.all(document.querySelector('.n-chat-transcript').getAnimations({ subtree: true })
          .filter(animation => Number.isFinite(animation.effect.getComputedTiming().endTime))
          .map(animation => animation.finished.catch(() => {})))
          .then(() => requestAnimationFrame(() => requestAnimationFrame(done)))
      JS
    end

    def orbite_paragraph_anchor
      page.evaluate_script(<<~JS)
        (() => {
          const top = document.querySelector('[data-application-scroll]').getBoundingClientRect().top
          const paragraph = [...document.querySelectorAll('.ai-response-content p')].find(node => node.getBoundingClientRect().bottom > top)
          return { text: paragraph.textContent, offset: paragraph.getBoundingClientRect().top - top }
        })()
      JS
    end

    def orbite_assert_downward_focus(label, destination: "#orbite-shell")
      assert_no_selector "dialog:modal"
      assert_no_selector "#chat-history[open]", visible: :all
      sample = page.evaluate_script(<<~JS)
        (() => {
          const active = document.activeElement
          return { tag: active.tagName, id: active.id, visible: active.checkVisibility(),
            bounds: active.getBoundingClientRect().toJSON(), inert: !!active.closest('[inert]'),
            focusVisible: active.matches(':focus-visible'), outlineWidth: parseFloat(getComputedStyle(active).outlineWidth) }
        })()
      JS
      orbite_record(label, sample, screenshot: true)
      refute_includes %w[BODY HTML], sample.fetch("tag"), sample.to_json
      assert sample.fetch("visible"), sample.to_json
      refute sample.fetch("inert"), sample.to_json
      assert_selector "#orbite-shell[tabindex='-1'][role=region][aria-label]"
      assert_equal page.title, find("#orbite-shell")["aria-label"]
      assert_selector "#{destination}:focus"
      reachable = orbite_assert_reachable(destination)
      assert reachable.fetch("focusVisible"), reachable.to_json
      assert_operator reachable.fetch("outlineWidth"), :>=, 2, reachable.to_json
    end

    def orbite_assert_next_tab_usable
      # Native input after the handoff may intentionally scroll to its next
      # control; paragraph preservation is measured before that new user intent.
      page.driver.browser.action.send_keys(:tab).perform
      orbite_settle
      assert page.evaluate_script("document.activeElement.matches('a[href], button, select, input, summary, [contenteditable=true]')")
      refute page.evaluate_script("!!document.activeElement.closest('#chat-history, [inert]')")
      sample = orbite_assert_reachable(":focus")
      assert sample.fetch("focusVisible"), sample.to_json
      assert_operator sample.fetch("outlineWidth"), :>=, 2, sample.to_json
    end

    def orbite_close_state
      page.evaluate_script(<<~JS)
        ({ open: document.querySelector('#chat-history').open,
          expanded: document.querySelector('#orbite-shell').dataset.orbiteHistoryExpanded,
          active: document.activeElement.id || document.activeElement.tagName,
          triggers: [...document.querySelectorAll('[data-workspace-navigation-target~=trigger]')].map(node => ({ id: node.id, expanded: node.getAttribute('aria-expanded') })) })
      JS
    end

    def orbite_assert_history_closed(opener)
      assert_no_selector "[data-workspace-navigation-target~=trigger][aria-expanded=true]", visible: :all
      all("[data-workspace-navigation-target~=trigger]", visible: true).each do |trigger|
        assert_equal "false", trigger["aria-expanded"], trigger[:id]
      end
      assert_selector "#{opener}:focus"
      orbite_assert_reachable(opener)
    end

    def orbite_refresh
      page.execute_script(<<~JS)
        document.documentElement.removeAttribute('data-orbite-refreshed')
        document.addEventListener('turbo:render', () => document.documentElement.dataset.orbiteRefreshed = 'true', { once: true })
        Turbo.visit(location.href, { action: 'replace' })
      JS
      assert_selector "html[data-orbite-refreshed=true]"
      orbite_settle
    end
end
