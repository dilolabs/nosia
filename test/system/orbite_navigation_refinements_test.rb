require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class OrbiteNavigationRefinementsSystemTest < ApplicationSystemTestCase
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

  %w[en fr].product([ false, true ], [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ]).each do |locale, dark, (width, height)|
    test "direct user menu in #{locale} #{dark ? 'dark' : 'light'} at #{width}x#{height}" do
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      { accounts: accounts_path, new: new_chat_path(account_id: @second.id), saved: chat_path(@chat) }.each do |route_key, path|
        visit path
        orbite_theme(dark)
        assert_selector "html[lang=#{locale}]"
        assert_selector "lexxy-editor[connected]" unless route_key == :accounts
        states = width >= 1280 && route_key != :accounts ? [ true, false ] : [ false ]
        states.each do |expanded|
          if width >= 1280 && route_key != :accounts && page.evaluate_script("document.querySelector('#chat-history').open") != expanded
            find("#workspace-history-rail-trigger").click
          end
          opener = refinement_trigger(width)
          before = refinement_history
          orbite_tab_to(opener)
          page.driver.browser.action.send_keys(:enter).perform
          assert_selector "#dropdown:popover-open"
          assert_selector "#{opener}[aria-expanded=true]"
          assert_selector "#dropdown a[href='#{profile_path}']:focus"
          assert_selector "#dropdown", count: 1, visible: :all
          assert_selector "#dropdownUser", count: 1, visible: :all
          sample = refinement_menu_geometry(opener)
          label = "direct-user-menu-#{locale}-#{dark ? 'dark' : 'light'}-#{width}x#{height}-#{route_key}-#{expanded}"
          orbite_record(label, sample.merge(historyBefore: before), screenshot: true)
          assert_equal 1, sample.fetch("menuCount")
          assert sample.fetch("modalContainsMenu"), sample.to_json
          menu, button = sample.values_at("menu", "opener")
          assert_operator menu.fetch("bottom"), :<=, button.fetch("top") - 7, sample.to_json
          assert_operator menu.fetch("left"), :>=, 8, sample.to_json
          assert_operator menu.fetch("right"), :<=, width - 8, sample.to_json
          assert_operator menu.fetch("top"), :>=, 8, sample.to_json
          assert_operator menu.fetch("bottom"), :<=, height - 8, sample.to_json
          # Opening already focused Profile. Traverse forward then back rather
          # than cycling through the background page to reach it again.
          orbite_tab_to("#dropdown a[href='#{settings_path}']")
          [ profile_path, settings_path, logout_path ].each_with_index do |destination, index|
            hit = orbite_tab_to("#dropdown a[href='#{destination}']", reverse: index.zero?)
            assert_operator hit.fetch("height"), :>=, 44
            assert_operator hit.fetch("width"), :>=, 44
          end
          orbite_tab_to("#dropdown a[href='#{settings_path}']", reverse: true)
          page.driver.browser.action.send_keys(:escape).perform
          assert_no_selector "#dropdown:popover-open"
          assert_selector "#{opener}[aria-expanded=false]:focus"
          orbite_assert_reachable(opener)
          assert_equal before, refinement_history
          if width < 768
            assert_selector "#chat-history:modal", count: 1
            assert_selector "dialog:modal", count: 1
            page.driver.browser.action.send_keys(:escape).perform
            assert_no_selector "#chat-history:modal"
          else
            assert_no_selector "dialog:modal"
          end
          orbite_record("#{label}-dismissed", refinement_menu_geometry(opener).merge(historyAfter: refinement_history))
        end
      end
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "rail pointer opens directly outside dismisses and real profile settings links navigate" do
    orbite_viewport(768, 1024)
    visit accounts_path
    find("#workspace-utilities-trigger").click
    assert_selector "#dropdown:popover-open"
    assert_no_selector "#chat-history[open]", visible: :all
    find("main h1").click
    assert_no_selector "#dropdown:popover-open"
    assert_selector "#workspace-utilities-trigger[aria-expanded=false]"
    { profile_path => ".n-profile", settings_path => "[data-settings-workspace]" }.each do |path, marker|
      find("#workspace-utilities-trigger").click
      assert_selector "#dropdown:popover-open"
      find("#dropdown a[href='#{path}']").click
      assert_current_path path
      assert_selector marker
      assert_no_selector ":popover-open, dialog:modal"
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "current trigger pointer closes the native user menu" do
    [ [ 375, 812 ], [ 768, 1024 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit accounts_path
      opener = refinement_trigger(width)
      # Passive native-event receipt; never intercepts delivery or writes state.
      page.execute_script(<<~JS)
        window.refinementPointerTrace = []
        if (!window.refinementPointerObserver) {
          window.refinementPointerObserver = true
          for (const type of ['pointerdown', 'pointerup', 'click', 'beforetoggle', 'toggle']) {
            document.addEventListener(type, event => {
              window.refinementPointerTrace.push({type, trusted: event.isTrusted, target: event.target.id,
                newState: event.newState || null, open: !!document.querySelector('#dropdown:popover-open'),
                expanded: [...document.querySelectorAll('[data-user-menu-target~=trigger]')].map(button => ({id: button.id, expanded: button.getAttribute('aria-expanded'), nativeTarget: button.popoverTargetElement?.id || null}))})
            }, {capture: true, passive: true})
          }
        }
      JS
      begin
        find(opener).click
        assert_selector "#dropdown:popover-open"
        find(opener).click
        assert_no_selector "#dropdown:popover-open"
        assert_selector "#{opener}[aria-expanded=false]:focus"
      ensure
        orbite_record("user-menu-current-pointer-#{width}x#{height}", page.evaluate_script("window.refinementPointerTrace"), screenshot: true)
      end
      orbite_close_navigation
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "popover closes on breakpoint changes modal closure and Turbo caching without hidden focus" do
    orbite_viewport(375, 812)
    visit chat_path(@chat)
    opener = refinement_trigger(375)
    orbite_tab_to(opener)
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#chat-history:modal #dropdown:popover-open"
    find("#workspace-navigation-close").click
    assert_no_selector ":popover-open, dialog:modal"
    refinement_assert_visible_focus

    orbite_viewport(768, 1024)
    orbite_tab_to("#workspace-utilities-trigger")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#dropdown:popover-open"
    orbite_viewport(375, 812)
    assert_no_selector ":popover-open"
    refinement_assert_visible_focus

    orbite_viewport(768, 1024)
    orbite_tab_to("#workspace-utilities-trigger")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#dropdown:popover-open"
    leaving_url = page.current_url
    # Test-only receipt from the actual cache event, not a supplied zero.
    page.execute_script(<<~JS)
      document.addEventListener('turbo:before-cache', () => {
        sessionStorage.setItem('refinement-user-menu-cache', JSON.stringify({url: location.href, count: document.querySelectorAll(':popover-open').length}))
      }, {once: true})
    JS
    find("#dropdown a[href='#{settings_path}']").click
    assert_current_path settings_path
    page.go_back
    assert_current_path chat_path(@chat)
    receipt = JSON.parse(page.evaluate_script("sessionStorage.getItem('refinement-user-menu-cache')"))
    assert_equal leaving_url, receipt.fetch("url")
    assert_equal 0, receipt.fetch("count")
    assert_no_selector ":popover-open, dialog:modal"
    assert_selector "[data-user-menu-target~=trigger][aria-expanded=false]", count: 2, visible: :all
    assert_selector "#workspace-user-menu-home > #dropdown", count: 1, visible: :all
    refinement_assert_visible_focus
    orbite_record("user-menu-cache-modal-breakpoint-receipt", receipt.merge(focusVisible: true), screenshot: true)
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "actual background scroll closes the anchored menu without interfering with its own scrollport" do
    orbite_viewport(812, 375)
    visit accounts_path
    # Geometry-only inert tail on the actual root; no reader/controller ledger writes.
    page.execute_script(<<~JS)
      const tail = document.createElement('div')
      tail.dataset.refinementGeometryOnlyTail = ''
      tail.inert = true
      tail.style.cssText = 'height:2200px;flex:none'
      document.querySelector('[data-application-scroll]').append(tail)
    JS
    orbite_tab_to("#workspace-utilities-trigger")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#dropdown:popover-open"
    page.execute_script("document.querySelector('[data-application-scroll]').scrollTop = 100")
    assert_no_selector "#dropdown:popover-open"
    assert_operator page.evaluate_script("document.querySelector('[data-application-scroll]').scrollTop"), :>, 0
    assert_selector "#workspace-utilities-trigger[aria-expanded=false]:focus"
    assert_no_selector "dialog:modal"
    orbite_record("user-menu-actual-background-scroll", { scrollTop: page.evaluate_script("document.querySelector('[data-application-scroll]').scrollTop"), focused: page.evaluate_script("document.activeElement.id") }, screenshot: true)
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "open popover returns to the current streamed rail opener not its detached predecessor" do
    orbite_viewport(768, 1024)
    visit accounts_path
    orbite_tab_to("#workspace-utilities-trigger")
    page.driver.browser.action.send_keys(:space).perform
    assert_selector "#dropdown:popover-open"
    # Genuine local Turbo DOM-lifecycle fixture, not a private controller state write.
    page.execute_script(<<~JS)
      window.oldRefinementOpener = document.querySelector('#workspace-utilities-trigger')
      Turbo.renderStreamMessage(`<turbo-stream action="replace" target="workspace-utilities-trigger"><template>${window.oldRefinementOpener.outerHTML}</template></turbo-stream>`)
    JS
    assert_selector "#workspace-utilities-trigger[aria-expanded=true]"
    refute page.evaluate_script("window.oldRefinementOpener.isConnected")
    assert_selector "#dropdown:popover-open"
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#dropdown:popover-open"
    assert_selector "#workspace-utilities-trigger[aria-expanded=false]:focus"
    hit = orbite_assert_reachable("#workspace-utilities-trigger")
    orbite_record("user-menu-streamed-current-opener", hit.merge(oldConnected: page.evaluate_script("window.oldRefinementOpener.isConnected")), screenshot: true)
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  private
    def refinement_trigger(width)
      if width < 768
        orbite_open_utilities
        "#dropdownUser"
      else
        "#workspace-utilities-trigger"
      end
    end

    def refinement_history
      page.evaluate_script("({open: document.querySelector('#chat-history').open, expanded: document.querySelector('#orbite-shell').dataset.orbiteHistoryExpanded})")
    end

    def refinement_menu_geometry(opener)
      page.evaluate_script(<<~JS, opener)
        (() => {
          const menu = document.querySelector('#dropdown'), modal = document.querySelector('dialog:modal')
          return {menu: menu.getBoundingClientRect().toJSON(), opener: document.querySelector(arguments[0]).getBoundingClientRect().toJSON(),
            menuCount: document.querySelectorAll('#dropdown').length, modal: modal?.id || null,
            modalContainsMenu: !modal || modal.contains(menu), active: document.activeElement.id || document.activeElement.tagName}
        })()
      JS
    end

    def refinement_assert_visible_focus
      assert page.evaluate_script("document.activeElement.checkVisibility() && !document.activeElement.closest('[inert]')")
    end
end
