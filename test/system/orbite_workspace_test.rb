require "application_system_test_case"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class OrbiteWorkspaceSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper
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

  test "Orbite prose and controls retain measured typography and native editing" do
    %w[EN FR].each do |language|
      orbite_select_language(language)
      [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
        [ false, true ].each do |dark|
          orbite_viewport(width, height)
          visit chat_path(@chat)
          assert_selector "lexxy-editor[connected]"
          orbite_theme(dark)
          lines = (1..35).flat_map { |index| [ "Native draft line #{index}", [ :shift, :enter ] ] }
          find("lexxy-editor .lexxy-editor__content").send_keys(*lines[0...-1])
          assert_selector ".lexxy-editor__content", text: "Native draft line 35"
          assert_no_enqueued_jobs only: ChatResponseJob
          find("[data-composer-chrome-target=formatting] > summary").click
          assert_selector "[data-formatting-open] lexxy-toolbar", visible: true
          sample = page.evaluate_script(<<~JS)
            (() => {
              const box = selector => document.querySelector(selector).getBoundingClientRect().toJSON()
              const body = document.querySelector('.n-chat-assistant-body:not([data-chat-error=true])'), style = getComputedStyle(body)
              const text = getComputedStyle(body.querySelector('.ai-response-content'))
              const editor = document.querySelector('.lexxy-editor__content')
              const measure = document.createElement('canvas').getContext('2d'); measure.font = text.fontSize + ' ' + text.fontFamily
              const controls = [...document.querySelectorAll('.n-composer-send, .n-composer-control')].filter(element => element.checkVisibility())
              return { assistant: { border: style.borderTopWidth, background: style.backgroundColor, padding: style.paddingLeft },
                typography: { size: parseFloat(text.fontSize), line: parseFloat(text.lineHeight), font: text.fontFamily, zero: measure.measureText('0').width },
                prose: box('.n-chat-transcript .n-chat-reading-column'), editor: { client: editor.clientHeight, height: editor.scrollHeight },
                reading: box('[data-application-scroll]'), dock: box('.n-chat-dock'),
                overflow: { document: document.documentElement.scrollWidth - innerWidth, main: document.querySelector('main').scrollWidth - document.querySelector('main').clientWidth },
                uniqueControlCount: new Set(controls).size,
                controls: controls.map(element => ({ name: element.getAttribute('aria-label') || element.textContent.trim(),
                  text: element.textContent.trim(), ariaLabel: element.getAttribute('aria-label'), className: element.className,
                  box: element.getBoundingClientRect().toJSON() })) }
            })()
          JS
          orbite_record("visual-materials-#{language}-#{width}-#{dark}", sample, screenshot: true)
          assert_equal "0px", sample.fetch("assistant").fetch("border"), sample.to_json
          assert_equal "rgba(0, 0, 0, 0)", sample.fetch("assistant").fetch("background"), sample.to_json
          assert_in_delta 16, sample.fetch("typography").fetch("size"), 0.1
          assert_operator sample.fetch("typography").fetch("line"), :>=, 25.6
          assert_operator sample.fetch("typography").fetch("line"), :<=, 28
          if width >= 1280
            characters = sample.fetch("prose").fetch("width") / sample.fetch("typography").fetch("zero")
            assert_operator characters, :>=, 65
            assert_operator characters, :<=, 75
          end
          assert_operator sample.fetch("editor").fetch("height"), :>, sample.fetch("editor").fetch("client")
          assert_equal({ "document" => 0, "main" => 0 }, sample.fetch("overflow"))
          assert_operator sample.fetch("reading").fetch("bottom"), :<=, sample.fetch("dock").fetch("top") + 1
          assert_operator sample.fetch("reading").fetch("height"), :>, 0
          assert_equal sample.fetch("controls").size, sample.fetch("uniqueControlCount"), sample.to_json
          tools = sample.fetch("controls").select { |control| control.fetch("className").split.include?("n-composer-tools-trigger") }
          assert_equal 1, tools.size, sample.to_json
          assert_nil tools.first.fetch("ariaLabel"), tools.to_json
          assert_equal tools.first.fetch("text"), tools.first.fetch("name")
          refute_empty tools.first.fetch("name")
          sample.fetch("controls").each do |control|
            assert_operator control.fetch("box").fetch("width"), :>=, 44, control.to_json
            assert_operator control.fetch("box").fetch("height"), :>=, 44, control.to_json
          end
          orbite_assert_reachable(".n-composer-send")
          page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
          assert page.evaluate_script("[...document.querySelectorAll('#orbite-shell button')].every(element => getComputedStyle(element).transitionDuration.split(',').every(value => parseFloat(value) === 0))")
          page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
        end
      end
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

  test "mobile navigation returns focus to its current streamed composer opener" do
    orbite_viewport(375, 812)
    @chat.start_generation!
    visit chat_path(@chat)
    assert_button "Stop generating", enable_aria_label: true
    trigger = "[data-orbite-composer-navigation]"
    page.execute_script("window.oldOrbiteTrigger = document.querySelector(arguments[0]); window.streamedOrbitePanel = document.querySelector('#chat-history')", trigger)
    find(trigger).click
    assert_selector "#chat-history:modal"
    @chat.stop_generation!
    Current.reset
    replacement = ApplicationController.render(
      inline: '<%= turbo_stream.replace target, partial: "messages/form", locals: { chat: chat } %>',
      locals: { target: "#{dom_id(@chat)}_message_form", chat: @chat })
    page.execute_script("Turbo.renderStreamMessage(arguments[0])", replacement)
    assert_selector "button[aria-label=Send]:not([disabled])", visible: :all
    assert_no_selector ".n-composer-stop", visible: :all
    refute page.evaluate_script("window.oldOrbiteTrigger.isConnected")
    assert_selector "#chat-history:modal"
    assert page.evaluate_script("window.streamedOrbitePanel === document.querySelector('#chat-history')")
    orbite_record("streamed-opener-modal", { oldConnected: false, samePanel: true, modal: true }, screenshot: true)
    page.driver.browser.action.send_keys(:escape).perform
    assert_selector "#{trigger}:focus"
    assert_no_selector "#chat-history:modal"
    refute page.evaluate_script("!!document.activeElement.closest('[inert]')")
    sample = orbite_assert_reachable(trigger)
    orbite_record("streamed-current-opener-focus", sample.merge(oldConnected: page.evaluate_script("window.oldOrbiteTrigger.isConnected"), currentFocused: page.evaluate_script("document.activeElement === document.querySelector(arguments[0])", trigger)), screenshot: true)
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "same page refresh retains collapsed wide history without duplicate interactive ids" do
    orbite_viewport(1400, 1000)
    visit chat_path(@chat)
    find("#workspace-history-rail-trigger").click
    assert_no_selector "#chat-history[open]", visible: :all
    find("lexxy-editor .lexxy-editor__content").send_keys("Refresh draft")
    orbite_refresh
    assert_selector "lexxy-editor[connected]"
    orbite_settle
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Refresh draft", exact_text: true
    assert_selector "#workspace-history-rail-trigger[aria-expanded=false]"
    assert_no_selector "#chat-history[open]", visible: :all
    ids = page.evaluate_script("[...document.querySelectorAll('[id]')].map(element => element.id)")
    assert_equal ids.uniq, ids
    orbite_record("same-page-collapsed-refresh", { rendered: page.evaluate_script("document.documentElement.dataset.orbiteRefreshed"), draft: find("lexxy-editor .lexxy-editor__content").text, ids: ids, collapsed: true }, screenshot: true)
    find("#workspace-history-rail-trigger").click
    assert_selector "#chat-history[data-inline=true][open]"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "new chat without an account has one guidance surface and no fake composer" do
    orbite_open_user_menu
    find("#dropdown a[href='#{logout_path}']").click
    assert_selector "form[action='#{login_path}']"
    fill_in "email", with: users(:picker_no_account).email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"

    %w[en fr].product([ [ 375, 812 ], [ 812, 375 ] ]).each do |locale, (width, height)|
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      visit new_chat_path
      [ false, true ].each do |dark|
        orbite_theme(dark)
        assert_selector ".n-orbite-reading [data-chat-no-account]", count: 1
        assert_no_selector ".n-chat-dock, lexxy-editor, [data-orbite-composer-navigation]", visible: :all
        assert_no_selector ".n-chat-header a, .n-chat-header button, .n-chat-header .n-chat-toolbar", visible: :all
        assert_selector "#workspace-mobile-trigger", count: 1, visible: :all
        orbite_assert_reachable("[data-chat-no-account]")
        orbite_assert_reachable(".n-chat-start a[href='#{accounts_path}']")
        orbite_record("no-account-#{locale}-#{dark ? 'dark' : 'light'}-#{width}x#{height}", { guidance: true, composer: false }, screenshot: true)
        opener = orbite_navigation_trigger
        target = orbite_tab_to(opener)
        %w[width height].each { |dimension| assert_operator target.fetch(dimension), :>=, 44 }
        page.driver.browser.action.send_keys(:enter).perform
        assert_selector "#chat-history:modal"
        orbite_tab_to("#workspace-navigation-close")
        page.driver.browser.action.send_keys(:enter).perform
        assert_no_selector "#chat-history:modal"
        assert_selector "#{opener}:focus"
        page.driver.browser.action.send_keys(:enter).perform
        assert_selector "#chat-history:modal"
        page.driver.browser.action.send_keys(:escape).perform
        assert_selector "#{opener}:focus"
        orbite_assert_reachable(opener)
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "mobile accounted chat headers omit navigation while the real composer opener retains draft and focus" do
    %w[en fr].product(%w[new saved], [ false, true ]).each do |locale, entry, dark|
      orbite_viewport(375, 812)
      orbite_select_language(locale.upcase)
      visit(entry == "new" ? new_chat_path(account_id: @second.id) : chat_path(@chat))
      assert_selector "lexxy-editor[connected]"
      orbite_theme(dark)
      assert_no_selector ".n-chat-header a[href='#{user_root_path}'], .n-chat-header [aria-controls=chat-history], #workspace-mobile-trigger", visible: :all
      assert_selector "main h1", count: 1
      assert_no_selector ".n-chat-header a, .n-chat-header button, .n-chat-header .n-workspace-actions", visible: :all
      assert_selector "#chat-history > .n-orbite-navigation-actions > a[href='#{new_chat_path}']", count: entry == "saved" ? 1 : 0, visible: :all
      find("lexxy-editor .lexxy-editor__content").send_keys("Keep this header navigation draft")
      page.execute_script("window.headerNavigationEditor = document.querySelector('lexxy-editor')")
      page.execute_script("document.querySelector('[data-application-scroll]').scrollTop = 0")
      orbite_settle
      orbite_record("header-controls-#{entry}-#{locale}-#{dark ? 'dark' : 'light'}", page.evaluate_script(<<~JS), screenshot: true)
        ({header: document.querySelector('.n-chat-header').getBoundingClientRect().toJSON(),
          heading: document.querySelector('main h1').textContent.trim(),
          actions: [...document.querySelectorAll('.n-chat-header a, .n-chat-header button')].map(node => node.textContent.trim()),
          usage: !!document.querySelector('#chat-usage-details'), rootTop: document.scrollingElement.scrollTop})
      JS
      opener = orbite_navigation_trigger
      assert_equal "[data-orbite-composer-navigation]", opener
      target = orbite_tab_to(opener, reverse: true)
      %w[width height].each { |dimension| assert_operator target.fetch(dimension), :>=, 44 }
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-history:modal"
      orbite_tab_to("#workspace-navigation-close")
      page.driver.browser.action.send_keys(:enter).perform
      assert_no_selector "#chat-history:modal"
      assert_selector "#{opener}:focus"
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-history:modal"
      page.driver.browser.action.send_keys(:escape).perform
      assert_selector "#{opener}:focus"
      orbite_assert_reachable(opener)
      assert page.evaluate_script("window.headerNavigationEditor === document.querySelector('lexxy-editor')")
      assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this header navigation draft", exact_text: true
      assert_no_enqueued_jobs only: ChatResponseJob
    end
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
    assert_operator page.evaluate_script("document.querySelector('.n-chat-header h1').getBoundingClientRect().bottom"), :<, 0
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
    assert_selector "[data-orbite-composer-navigation][aria-expanded=false]", visible: :all
    ids = page.evaluate_script("[...document.querySelectorAll('[id]')].map(node => node.id)")
    assert_equal ids.uniq, ids
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  [ [ 1024, 1000 ], [ 375, 812 ] ].product(%w[close escape]).each do |(width, height), action|
    test "recovered History #{action} resumes closed state at #{width}px" do
      orbite_viewport(width, height)
      visit chat_path(@chat)
      opener = orbite_navigation_trigger
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
    find(orbite_navigation_trigger).click
    assert_selector "#chat-history:modal"
    assert_selector "#chat-history [data-action='workspace-navigation#close']:focus"
    page.driver.browser.action.send_keys(:escape).perform
    assert_selector "#{orbite_navigation_trigger}:focus"
    assert_no_selector "#chat-history [autofocus]", visible: :all
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "shared History refresh restores its current focus and replaced opener but caches closed" do
    orbite_viewport(1024, 1000)
    visit chat_path(@chat)
    find(orbite_navigation_trigger).click
    orbite_tab_to("#language_preference_locale")
    page.execute_script(<<~JS, orbite_navigation_trigger)
      const openerSelector = arguments[0]
      window.orbiteOriginalOpener = document.querySelector(openerSelector)
      document.addEventListener('turbo:before-cache', () => {
        window.orbiteCachedModalIds = [...document.querySelectorAll('dialog[open]')].map(node => node.id)
      }, { once: true })
      document.addEventListener('turbo:before-render', () => {
        const trigger = document.querySelector(openerSelector)
        trigger.replaceWith(trigger.cloneNode(true))
      }, { once: true })
    JS
    orbite_refresh
    assert_equal [], page.evaluate_script("window.orbiteCachedModalIds")
    refute page.evaluate_script("window.orbiteOriginalOpener.isConnected")
    assert_selector "#chat-history:modal"
    assert_selector "#language_preference_locale:focus"
    assert_selector "#{orbite_navigation_trigger}[aria-expanded=true]", visible: :all
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#chat-history:modal"
    assert_selector "#{orbite_navigation_trigger}:focus"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "shared History refresh does not steal deliberate outside or Tools focus" do
    orbite_viewport(1024, 1000)
    %w[outside tools].each do |destination|
      visit chat_path(@chat)
      find(orbite_navigation_trigger).click
      assert_selector "#chat-history:modal"
      # Deliberate focus intent at the real lifecycle boundary, not native
      # Tab evidence or a replacement rendering/delivery gate.
      page.execute_script(<<~JS, destination)
        const destination = arguments[0]
        document.addEventListener('turbo:before-render', () => {
          if (destination === 'outside') document.querySelector('#workspace-utilities-trigger').focus({ preventScroll: true })
          else document.querySelector('.n-composer-tools-trigger').focus({ preventScroll: true })
        }, { once: true })
      JS
      orbite_refresh
      assert_no_selector "#chat-history:modal"
      if destination == "outside"
        assert_no_selector "dialog:modal"
        assert_selector "#workspace-utilities-trigger:focus"
      else
        assert_no_selector "dialog:modal"
        assert_selector ".n-composer-tools-trigger:focus"
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "shared History recovery is consumed before standalone cache cleanup" do
    orbite_viewport(1024, 1000)
    visit chat_path(@chat)
    find(orbite_navigation_trigger).click
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
    find(orbite_navigation_trigger).click
    assert_selector "#chat-history:modal"
    find("#chat-history [data-action='workspace-navigation#close']").click
    assert_no_selector "#chat-history:modal"
    orbite_refresh
    assert_no_selector "#chat-history[open]", visible: :all
    find(orbite_navigation_trigger).click
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
        assert geometry.fetch("labelsFit"), geometry.to_json
        assert geometry.fetch("dateFits"), geometry.to_json
        assert_in_delta geometry.fetch("row").fetch("width"), geometry.fetch("link").fetch("width"), 1, geometry.to_json
        assert_operator geometry.fetch("link").fetch("left"), :>=, geometry.fetch("row").fetch("left"), geometry.to_json
        assert_operator geometry.fetch("link").fetch("right"), :<=, geometry.fetch("row").fetch("right"), geometry.to_json
        assert_operator geometry.fetch("link").fetch("width"), :>=, 44, geometry.to_json
        assert_operator geometry.fetch("link").fetch("height"), :>=, 44, geometry.to_json
        assert_selector "#{row} > div > a > .n-chat-history-title", text: title, exact_text: true
        assert_selector "#{row} > div > a .n-chat-history-account", text: conversation.account.name, exact_text: true
        assert_equal title, geometry.fetch("titleText")
        assert_equal conversation.account.name, geometry.fetch("accountText")
        assert_equal title, geometry.fetch("nativeTitle")
        assert_equal conversation.account.name, geometry.fetch("nativeAccount")
        assert_selector "#{row} time[datetime='#{conversation.updated_at.iso8601}']",
          text: I18n.l(conversation.updated_at, format: :short, locale: locale), exact_text: true
        assert_selector "#{row} > div > a[aria-current=page]", count: entry == "saved" && conversation == @chat ? 1 : 0
        assert_no_selector "#{row} > div > p", visible: :all
        if entry == "saved" && conversation == @chat
          %w[paddingInlineStart paddingInlineEnd textInset].each do |inset|
            assert_operator geometry.fetch(inset), :>=, 8, geometry.to_json
          end
          %w[paddingBlockStart paddingBlockEnd].each do |inset|
            assert_operator geometry.fetch(inset), :>, 0, geometry.to_json
          end
        end
        assert_no_selector "#{row} form, #{row} button, #{row} [data-turbo-method=delete], #{row} [data-method=delete], #{row} [data-turbo-confirm]", visible: :all
      end
      controls = conversations.keys.map do |conversation|
        row = "#chat-history [data-history-chat='#{conversation.id}']"
        "#{row} > div > a"
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
    find(orbite_navigation_trigger).click
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
        opener = orbite_open_user_menu
        assert_selector "#dropdown:popover-open"
        [ profile_path, settings_path, logout_path ].each do |path|
          orbite_assert_reachable("#dropdown a[href='#{path}']")
        end
        orbite_record("bottom-utilities-#{width}-#{dark ? 'dark' : 'light'}", { dropdown: true }, screenshot: true)
        find(opener).click
        assert_no_selector "#dropdown:popover-open"
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
    assert_selector "#dropdown:popover-open"
    assert_selector "dialog:modal", count: 1
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
              const b = rect(body)
              const title = link.querySelector('.n-chat-history-title'), account = link.querySelector('.n-chat-history-account'), time = link.querySelector('time')
              const l = rect(link), t = rect(time), style = getComputedStyle(link)
              const inside = (a, box) => a.left >= box.left - 1 && a.right <= box.right + 1 && a.top >= box.top - 1 && a.bottom <= box.bottom + 1
              const labelsFit = [title, account].every(node => {
                const box = rect(node), css = getComputedStyle(node)
                return box.width > 0 && box.height > 0 && inside(box, l) && css.whiteSpace === 'nowrap' &&
                  css.overflowX === 'hidden' && css.textOverflow === 'ellipsis' && box.height <= parseFloat(css.lineHeight) + 1
              })
              const range = document.createRange(); range.selectNodeContents(time)
              const dateFits = t.width > 0 && t.height > 0 && inside(t, l) && getComputedStyle(time).textOverflow !== 'ellipsis' &&
                range.getClientRects().length > 0 && [...range.getClientRects()].every(glyph => inside(glyph, t) && inside(glyph, l))
              return { id: row.dataset.historyChat, row: rect(row), body: b, link: rect(link),
                paddingInlineStart: parseFloat(style.paddingInlineStart), paddingInlineEnd: parseFloat(style.paddingInlineEnd),
                paddingBlockStart: parseFloat(style.paddingBlockStart), paddingBlockEnd: parseFloat(style.paddingBlockEnd),
                textInset: rect(title).left - l.left,
                fontSize: parseFloat(style.fontSize), labelsFit, dateFits,
                titleText: title.textContent, accountText: account.textContent,
                nativeTitle: link.getAttribute('title'), nativeAccount: account.getAttribute('title') }
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
