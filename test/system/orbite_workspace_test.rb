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
    orbite_assert_downward_focus("saved-chat-downward")
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

    def orbite_assert_downward_focus(label)
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
      assert_selector "#orbite-shell[tabindex='-1'][role=region][aria-label]:focus"
      assert_equal page.title, find("#orbite-shell")["aria-label"]
      reachable = orbite_assert_reachable("#orbite-shell")
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
