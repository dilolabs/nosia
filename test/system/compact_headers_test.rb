require "application_system_test_case"
require "json"
require "tmpdir"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/chat_workspace_browser_checks"
require_relative "../support/account_experience_fixtures"

class CompactHeadersSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include ChatWorkspaceBrowserChecks

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

  %w[dashboard account sources saved_chat].each do |route|
    test "page header scrolls away beside persistent navigation on #{route} with labelled overflow" do
      visit({ "dashboard" => user_root_path, "account" => account_path(@second),
        "sources" => sources_path, "saved_chat" => chat_path(@chat) }.fetch(route))
      assert_selector "main h1"
      assert_selector "lexxy-editor[connected]" if route == "saved_chat"
      settle_workspace_layout
      page.execute_script("document.querySelector('[data-application-scroll]').scrollTo({top:0,behavior:'instant'})")
      settle_workspace_layout
      header_record("#{route}-before", header_geometry, screenshot: true)

      header_overflow_fixture(route)
      page.execute_script(<<~JS)
        const surface = document.querySelector('[data-application-scroll]')
        surface.scrollTop = 700
        surface.dispatchEvent(new Event('scroll'))
      JS
      settle_workspace_layout
      geometry = header_geometry
      header_record("#{route}-overflow-scrolled", geometry, screenshot: true)

      assert_selector "[data-application-scroll]", count: 1
      assert_operator geometry.fetch("surface").fetch("scrollTop"), :>=, 699, geometry.to_json
      assert_no_selector "[data-application-header]", visible: :all
      if page.evaluate_script("innerWidth >= 768")
        assert_operator geometry.fetch("navigation").fetch("top"), :>=, 0, geometry.to_json
      end
      assert_operator geometry.fetch("heading").fetch("bottom"), :<=, geometry.fetch("surface").fetch("top"), geometry.to_json
      if page.has_selector?(".n-chat-workspace", wait: 0)
        assert_equal 0, geometry.fetch("main").fetch("scrollTop"), geometry.to_json
      else
        assert_equal geometry.fetch("surface").fetch("scrollTop"), geometry.fetch("main").fetch("scrollTop"), geometry.to_json
      end
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "rail and native utilities retain full target sizes without an old global bar" do
    [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
      header_viewport(width, height)
      visit accounts_path
      assert_no_selector "[data-application-header], .n-nav-bottom", visible: :all
      orbite_open_utilities
      header_settle
      sample = page.evaluate_script(<<~JS)
        ({ controls: ['#language_preference_locale', '#theme-toggle', '#dropdownUser'].map(selector =>
          ({ selector, geometry: document.querySelector(selector).getBoundingClientRect().toJSON() })) })
      JS
      header_record("orbite-targets-#{width}x#{height}", sample, screenshot: true)
      sample.fetch("controls").each do |control|
        assert_operator control.fetch("geometry").fetch("height"), :>=, 44, control.to_json
        assert_operator control.fetch("geometry").fetch("width"), :>=, 44, control.to_json
        orbite_assert_reachable(control.fetch("selector"))
      end
      orbite_close_navigation
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "History cross and trash retain native targets focus and measured strokes" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    %w[en fr].product([ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ], [ false, true ]).each do |locale, (width, height), dark|
      header_viewport(width, height)
      orbite_select_language(locale.upcase)
      visit chat_path(@chat)
      assert_selector "html[lang='#{locale}']"
      assert_selector "lexxy-editor[connected]"
      header_theme(dark)
      orbite_open_utilities
      assert_selector "#chat-history h2#chat-history-title.sr-only", text: I18n.t("nosia.orbite.navigation", locale: locale), visible: :all
      assert_no_selector "#chat-history .n-orbite-panel-heading, #chat-history .n-orbite-logo, #chat-history img", visible: :all
      [ [ "#workspace-navigation-close", "nosia.chat_workspace.close" ],
        [ "#chat-history [data-history-chat='#{@chat.id}'] button", "nosia.nav.delete_chat" ] ].each do |selector, key|
        header_tab_to(selector)
        button = find(selector)
        assert_empty button.text
        assert_equal I18n.t(key, locale: locale), button["aria-label"]
        assert_equal I18n.t(key, locale: locale), button["title"]
        assert_selector "#{selector} svg[aria-hidden=true]", count: 1
        sample = header_hit(selector)
        assert_operator sample.fetch("geometry").fetch("width"), :>=, 44, sample.to_json
        assert_operator sample.fetch("geometry").fetch("height"), :>=, 44, sample.to_json
        header_icon_stroke("#{selector} svg")
        header_contrast("#{selector} svg", minimum: 3, property: "color")
        header_contrast(selector, minimum: 3, property: "outlineColor")
        header_record("history-icon-#{key.split('.').last}-#{locale}-#{width}x#{height}-#{dark ? 'dark' : 'light'}", sample, screenshot: true)
      end
      orbite_close_navigation
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "panel controls retain native language theme and profile navigation" do
    [ [ 375, 812 ], [ 812, 375 ], [ 1400, 375 ], [ 768, 1024 ], [ 1400, 1000 ] ].each do |width, height|
      header_viewport(width, height)
      %w[en fr].each do |locale|
        visit accounts_path
        orbite_select_language(locale.upcase)
        assert_selector "html[lang='#{locale}']"

        [ false, true ].each do |dark|
          visit accounts_path
          assert_selector "html[lang='#{locale}']"
          header_theme(dark)
          orbite_open_utilities
          [ "#chat-history .n-orbite-panel-links a[href='#{root_path}']", "#language_preference_locale", "#theme-toggle", "#dropdownUser" ].each do |selector|
            header_tab_to(selector)
          end
          page.driver.browser.action.send_keys(:enter).perform
          assert_selector "#dropdown:not(.hidden)"
          header_tab_to("#dropdown a[href='#{profile_path}']")
          header_record("native-dropdown", {
            menu: find("#dropdown").text,
            controls: page.evaluate_script(<<~JS)
              [...document.querySelectorAll('#chat-history a, #chat-history button, #chat-history select')].map(element =>
                ({ id: element.id, name: element.getAttribute('aria-label') || element.textContent.trim(), value: element.value }))
            JS
          }, screenshot: true)
          page.driver.browser.action.send_keys(:enter).perform
          assert_current_path profile_path
          assert_selector ".n-profile"
          assert_selector "html[lang='#{locale}']"
          assert_equal dark, page.evaluate_script("document.documentElement.classList.contains('dark')")
          assert_selector "main h1", text: I18n.t("nosia.profile.title", locale: locale)
          header_record("native-profile", { heading: find("main h1").text }, screenshot: true)
        end
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "saved header is compact and preserves the draft while disclosing usage" do
    header_viewport(1400, 1000)
    visit chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep this draft while reading usage")
    page.execute_script("window.headerDraftEditor = document.querySelector('lexxy-editor')")
    header_top

    find("#chat-usage-summary").click
    assert_selector "#chat-usage-details[open]"
    within "#chat-usage-details" do
      assert_selector "dt", text: I18n.t("nosia.usage.input"), exact_text: true
      assert_selector "[data-chat-total-input]", text: "125", exact_text: true
      assert_selector "dt", text: I18n.t("nosia.usage.output"), exact_text: true
      assert_selector "[data-chat-total-output]", text: "24", exact_text: true
    end
    header_settle
    header_record("saved-heading-usage-open", header_geometry.merge(
      "headerHeight" => page.evaluate_script("document.querySelector('.n-chat-header').getBoundingClientRect().height")
    ), screenshot: true)
    find("#chat-usage-summary").click
    assert_selector "#chat-usage-details:not([open])"
    header_settle
    geometry = page.evaluate_script(<<~JS, dom_id(@chat, :token_totals))
      (() => ({
        headerHeight: document.querySelector('.n-chat-header').getBoundingClientRect().height,
        titleTop: document.querySelector('.n-chat-title').getBoundingClientRect().top,
        historyTop: document.querySelector('#workspace-history-trigger').getBoundingClientRect().top,
        sameEditor: window.headerDraftEditor === document.querySelector('lexxy-editor'),
        draft: document.querySelector('lexxy-editor .lexxy-editor__content').textContent,
        totalsTargets: document.querySelectorAll(`[id="${arguments[0]}"]`).length
      }))()
    JS
    header_record("saved-heading", geometry, screenshot: true)

    assert_operator geometry.fetch("headerHeight"), :<=, 92, geometry.to_json
    assert_operator (geometry.fetch("titleTop") - geometry.fetch("historyTop")).abs, :<=, 20, geometry.to_json
    assert_selector ".n-chat-toolbar h1.n-chat-title", count: 1
    assert geometry.fetch("sameEditor"), geometry.to_json
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this draft while reading usage"
    assert_equal 1, geometry.fetch("totalsTargets"), geometry.to_json
    assert_selector "#chat-usage-details ##{dom_id(@chat, :token_totals)}", count: 1, visible: :all
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "page heading descriptions and trails remain operable through native details" do
    header_viewport(1400, 1000)
    %w[en fr].each do |locale|
      visit profile_path
      orbite_select_language(locale.upcase)
      assert_selector "html[lang='#{locale}']"
      header_theme(locale == "fr")
      assert_selector "details[data-header-details]:not([open])"
      summary = "details[data-header-details] > summary"
      assert_selector summary, text: I18n.t("nosia.layout.details", locale: locale), exact_text: true
      assert_no_selector ".n-workspace-header .n-workspace-trail"
      header_tab_to(summary)
      header_record("page-heading-closed", header_geometry.merge(
        "headerHeight" => page.evaluate_script("document.querySelector('.n-workspace-header').getBoundingClientRect().height")
      ), screenshot: true)

      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "details[data-header-details][open]"
      assert_selector ".n-workspace-header .n-workspace-help", text: I18n.t("nosia.profile.introduction", locale: locale), exact_text: true
      assert_selector ".n-workspace-header nav[aria-label='#{I18n.t('nosia.workspace.breadcrumb', locale: locale)}'] .n-workspace-trail"
      header_hit(summary)
      header_record("page-heading-open", header_geometry.merge(
        "headerHeight" => page.evaluate_script("document.querySelector('.n-workspace-header').getBoundingClientRect().height")
      ), screenshot: true)

      page.driver.browser.action.send_keys(:space).perform
      assert_selector "details[data-header-details]:not([open])"
      assert_no_selector ".n-workspace-header .n-workspace-trail"
      header_hit(summary)
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  %w[forward backward].each do |direction|
    test "native header #{direction} navigation survives a pending resize acknowledgment" do
      header_prepare_paused_chat(direction)
      header_defer_resize_acknowledgment
      header_viewport(812, 375)
      if direction == "backward"
        page.driver.browser.action.key_down(:shift).send_keys(:tab).key_up(:shift).perform
      else
        page.driver.browser.action.send_keys(:tab).perform
      end
      header_settle
      sample = header_resize_sample
      header_record("native-header-#{direction}", sample, screenshot: true)

      key = sample.fetch("trace").find { |entry| entry["event"] == "keydown" && entry["key"] == "Tab" }
      assert key.fetch("trusted"), sample.to_json
      assert_equal direction == "backward", key.fetch("shift"), sample.to_json
      refute_equal key.fetch("ledger").fetch("clientWidth"), key.fetch("clientWidth"), sample.to_json
      assert_operator sample.fetch("deferred"), :>, 0, sample.to_json
      target = direction == "backward" ? ".n-chat-toolbar a[href='#{new_chat_path}']" : "#workspace-history-trigger"
      assert_selector "#{target}:focus"
      header_hit(target)
      assert_selector ".n-chat-workspace[data-reader-following='false']"
      assert_equal [ 0, 0 ], page.evaluate_script("[document.querySelector('main').scrollTop, document.querySelector('.n-chat-transcript').scrollTop]")
      assert_no_enqueued_jobs only: ChatResponseJob
    ensure
      page.execute_script("window.headerResizeBoundary?.restore()")
    end
  end

  test "resize alone preserves the paused paragraph without pinning an already focused header" do
    header_prepare_paused_chat("backward")
    before = header_reader_anchor
    header_viewport(812, 375)
    header_settle
    after = header_reader_anchor(before.fetch("index"))
    header_record("resize-alone", { before: before, after: after }, screenshot: true)

    assert_equal before.fetch("text"), after.fetch("text"), after.to_json
    assert_in_delta before.fetch("offset"), after.fetch("offset"), 1, after.to_json
    assert_selector ".n-chat-workspace[data-reader-following='false']"
    assert_selector "#chat-usage-summary:focus", visible: :all
    assert_operator page.evaluate_script("document.querySelector('#chat-usage-summary').getBoundingClientRect().bottom"), :<, 0
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  %w[en fr].product([ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ], [ false, true ]).each do |locale, (width, height), dark|
    test "compact headers across eleven routes in #{locale} at #{width}x#{height} in #{dark ? 'dark' : 'light'}" do
      @second.update_columns(name: "CompteDeRecherche" * 12)
      header_viewport(width, height)
      orbite_select_language(locale.upcase)
      assert_selector "html[lang='#{locale}']"

      header_pages.each_with_index do |path, index|
        visit path
        assert_current_path path
        assert_selector "html[lang='#{locale}']"
        assert_selector "main", count: 1
        assert_selector "main h1", count: 1
        assert_selector "#orbite-shell", count: 1
        assert_no_selector "[data-application-header]", visible: :all
        assert_selector "[data-application-scroll]", count: 1
        assert_selector "lexxy-editor[connected]" if [ user_root_path, new_chat_path(account_id: @second.id), chat_path(@chat) ].include?(path)
        header_theme(dark)
        header_top
        assert_header_widths
        assert_no_text(/translation missing|missing translation/i)
        if page.has_selector?("[data-workspace-scope]", visible: :all, wait: 0)
          assert_selector "[data-workspace-scope]", visible: true
          assert_no_selector "details [data-workspace-scope]", visible: :all
        end
        header_contrast("main h1")
        orbite_with_utilities do
          header_contrast("#language_preference_locale")
          header_contrast("#theme-toggle svg:not(.hidden)", minimum: 3, property: "fill")
          header_tab_to("#language_preference_locale")
          header_tab_to("#theme-toggle")
        end
        if width >= 768
          home = ".n-orbite-rail .n-orbite-link[href='#{root_path}']"
          orbite_tab_to(home, reverse: true)
          header_hit(home)
          icon = ".n-orbite-rail .n-orbite-link[href='#{root_path}'] svg"
          assert page.evaluate_script(<<~JS, find(icon))
            (() => { const svg = arguments[0], path = svg.querySelector('path'), paint = getComputedStyle(path)
              return paint.stroke === getComputedStyle(svg).color && Number(paint.strokeOpacity) === 1 && paint.fill === 'none' })()
          JS
          header_contrast(icon, minimum: 3, property: "color")
        end
        header_top
        header_record("matrix-top-#{index}", header_matrix_geometry, screenshot: true)
        header_disclosures(index)

        # Only insufficient real overflow receives a labelled geometry fixture.
        # The saved chat already contains the real eighty-paragraph answer.
        header_overflow_fixture("matrix-#{index}")
        before_scroll = header_geometry.merge(header_scroll_context)
        header_record("matrix-before-scroll-#{index}", before_scroll)
        assert_operator before_scroll.fetch("surface").fetch("scrollHeight") - before_scroll.fetch("surface").fetch("clientHeight") - before_scroll.fetch("surface").fetch("scrollTop"), :>=, 700, before_scroll.to_json
        page.execute_script(<<~JS, before_scroll.fetch("surface").fetch("scrollTop") + 700)
          const surface = document.querySelector('[data-application-scroll]')
          surface.scrollTop = arguments[0]
          surface.dispatchEvent(new Event('scroll'))
        JS
        header_settle
        sample = header_matrix_geometry.merge(header_scroll_context)
        header_record("matrix-scrolled-#{index}", sample, screenshot: true)
        assert_operator sample.fetch("surface").fetch("scrollTop"), :>=, 699, sample.to_json
        assert_no_selector "[data-application-header]", visible: :all
        assert_operator sample.fetch("navigation").fetch("top"), :>=, 0, sample.to_json if width >= 768
        assert_operator sample.fetch("heading").fetch("bottom"), :<=, sample.fetch("surface").fetch("top"), sample.to_json
        assert_header_scroll_movement(before_scroll, sample)
        if page.has_selector?(".n-chat-workspace", wait: 0)
          assert_equal 0, sample.fetch("main").fetch("scrollTop"), sample.to_json
        else
          assert_equal sample.fetch("surface").fetch("scrollTop"), sample.fetch("main").fetch("scrollTop"), sample.to_json
        end
        refute sample.fetch("syntheticOverflow"), sample.to_json if path == chat_path(@chat)
      end
      assert_equal 11, header_pages.size
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "labelled geometry probe measures real heading movement from a nonzero primary baseline" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    header_viewport(812, 375)
    orbite_select_language("FR")
    visit chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    header_theme(false)
    header_disclosures(10)

    # Adversarial geometry only, not native user input or a reader-state write.
    page.execute_script(<<~JS)
      const surface = document.querySelector('[data-application-scroll]')
      surface.scrollTop = 3
      surface.dispatchEvent(new Event('scroll'))
    JS
    header_settle
    before_scroll = header_geometry.merge(header_scroll_context)
    header_record("adversarial-nonzero-before", before_scroll.merge("geometryOnly" => true, "nativeUserInput" => false), screenshot: true)
    assert_equal 3, before_scroll.fetch("surface").fetch("scrollTop"), before_scroll.to_json
    assert_operator before_scroll.fetch("surface").fetch("scrollHeight") - before_scroll.fetch("surface").fetch("clientHeight") - before_scroll.fetch("surface").fetch("scrollTop"), :>=, 700
    page.execute_script(<<~JS, before_scroll.fetch("surface").fetch("scrollTop") + 700)
      const surface = document.querySelector('[data-application-scroll]')
      surface.scrollTop = arguments[0]
      surface.dispatchEvent(new Event('scroll'))
    JS
    header_settle
    sample = header_matrix_geometry.merge(header_scroll_context)
    header_record("adversarial-nonzero-after", sample.merge("geometryOnly" => true, "nativeUserInput" => false), screenshot: true)
    assert_equal 700, sample.fetch("surface").fetch("scrollTop") - before_scroll.fetch("surface").fetch("scrollTop"), sample.to_json
    assert_equal 0, sample.fetch("main").fetch("scrollTop"), sample.to_json
    refute sample.fetch("syntheticOverflow"), sample.to_json
    assert_header_scroll_movement(before_scroll, sample)
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "headers allow enlarged text to grow without clipping controls" do
    header_viewport(375, 812)
    visit profile_path
    original = page.evaluate_script("document.documentElement.style.getPropertyValue('font-size')")
    page.execute_script("document.documentElement.style.fontSize = '200%'")
    header_top
    assert_header_widths
    orbite_with_utilities do
      header_record("enlarged-css-text-before-tab", header_matrix_geometry.merge(
        "nativeZoomVerified" => false, "textSizeMethod" => "CSS root font-size: 200%"
      ), screenshot: true)
      header_tab_to("#language_preference_locale", enlarged: true)
      header_tab_to("#theme-toggle", enlarged: true)
      header_top
      sample = header_matrix_geometry.merge("nativeZoomVerified" => false, "textSizeMethod" => "CSS root font-size: 200%")
      header_record("enlarged-css-text", sample, screenshot: true)
      assert_operator find("#language_preference_locale").native.rect.height, :>=, 44
      assert page.evaluate_script("document.querySelector('#chat-history').scrollWidth <= document.querySelector('#chat-history').clientWidth")
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  ensure
    page.execute_script("document.documentElement.style.setProperty('font-size', arguments[0])", original) if original
  end

  [ [ 375, 812 ], [ 812, 375 ] ].product(%w[keyboard pointer]).each do |(width, height), input|
    test "native Usage #{input} keeps its summary operable at #{width}x#{height}" do
      @second.update_columns(name: "CompteDeRecherche" * 12)
      header_viewport(width, height)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      header_top
      header_tab_to("#chat-usage-summary")
      before = page.evaluate_script("document.querySelector('#chat-usage-summary').getBoundingClientRect().top")

      [ true, false ].each do |open|
        header_record("usage-#{input}-before-#{open}", header_geometry, screenshot: true)
        if input == "keyboard"
          page.driver.browser.action.send_keys(open ? :enter : :space).perform
        else
          find("#chat-usage-summary").click
        end
        assert_selector "#chat-usage-details#{open ? '[open]' : ':not([open])'}"
        header_settle
        header_record("usage-#{input}-after-#{open}", header_geometry, screenshot: true)
        assert_selector "#chat-usage-summary:focus"
        assert_in_delta before, page.evaluate_script("document.querySelector('#chat-usage-summary').getBoundingClientRect().top"), 1
        if input == "keyboard"
          header_hit("#chat-usage-summary")
        else
          chat_reachable "#chat-usage-summary", scroll: false
        end
        assert_selector ".n-chat-workspace[data-reader-following='false']"
        assert_no_button "Latest message"
        assert_equal [ 0, 0 ], page.evaluate_script("[document.querySelector('main').scrollTop, document.querySelector('.n-chat-transcript').scrollTop]")
      end
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  [ [ 375, 812 ], [ 812, 375 ] ].each do |width, height|
    test "native Usage stream overlap keeps the summary through HUD reflow at #{width}x#{height}" do
      @second.update_columns(name: "CompteDeRecherche" * 12)
      header_viewport(width, height)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      header_top
      header_tab_to("#chat-usage-summary")
      assert_no_button "Latest message"
      before = page.evaluate_script("document.querySelector('#chat-usage-summary').getBoundingClientRect().top")
      header_hold_reader_frame

      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-usage-details[open]"
      message = workspace(:messages, :workspace_answer)
      text = message.content + "\n\nOrdering overlap: genuinely new content below the viewport."
      html = ApplicationController.render(partial: "messages/streaming_content",
        locals: { message: message, content_html: Message.render_markdown_content(text) })
      stream = %(<turbo-stream action="replace" target="#{dom_id(message, :content)}"><template>#{html}</template></turbo-stream>)
      page.execute_script("Turbo.renderStreamMessage(arguments[0])", stream)
      assert_selector ".ai-response-content p:last-child", text: "Ordering overlap:", visible: :all
      page.execute_script("window.headerOrderingBoundary.mark('before-release'); window.headerOrderingBoundary.release()")
      3.times { header_settle }
      sample = page.evaluate_script("window.headerOrderingBoundary.sample()")
      header_record("ordering-stream-hud", sample, screenshot: true)

      assert sample.fetch("trace").any? { |entry| entry["event"] == "restoreDisclosure:after" && entry["restored"] }, sample.to_json
      assert sample.fetch("trace").any? { |entry| entry["event"] == "restoreAnchor:after" && entry["latestVisible"] }, sample.to_json
      assert sample.fetch("trace").any? { |entry| entry["event"] == "schedule" && entry["latestVisible"] && entry["stack"].include?("ResizeObserver") }, sample.to_json
      assert_button "Latest message"
      assert_in_delta before, page.evaluate_script("document.querySelector('#chat-usage-summary').getBoundingClientRect().top"), 1, sample.to_json
      header_hit("#chat-usage-summary")
      assert_no_enqueued_jobs only: ChatResponseJob
    ensure
      page.execute_script("window.headerOrderingBoundary?.restore()")
    end

    test "native Tab supersedes a pending Usage activation at #{width}x#{height}" do
      @second.update_columns(name: "CompteDeRecherche" * 12)
      header_viewport(width, height)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      target = "##{dom_id(workspace(:messages, :workspace_answer), :reasoning_summary)}"
      # Adversarial geometry only: the reserved composer is no longer below this
      # target inside the reader. Supply real inert overflow, not a paused-state
      # write, so trusted native Tab can still exercise the >80px paused case.
      geometry = page.evaluate_script(<<~JS, target)
        (() => {
          const surface = document.querySelector('[data-application-scroll]')
          const target = document.querySelector(arguments[0]), tail = document.createElement('div')
          tail.dataset.headerPausedTabTail = ''
          tail.inert = true
          tail.style.cssText = `height:${Math.ceil(surface.clientHeight + target.getBoundingClientRect().height + 81)}px;flex:none;overflow-anchor:none`
          document.querySelector('.n-chat-transcript').append(tail)
          return { geometryOnly: true, inert: tail.inert, height: tail.getBoundingClientRect().height,
            clientHeight: surface.clientHeight, targetHeight: target.getBoundingClientRect().height,
            parentClass: tail.parentElement.className }
        })()
      JS
      header_record("paused-tab-adversarial-tail", geometry)
      assert geometry.fetch("inert")
      assert_equal "n-chat-transcript", geometry.fetch("parentClass")
      assert_operator geometry.fetch("height"), :>, geometry.fetch("clientHeight") + 80
      header_settle
      header_top
      header_tab_to("#chat-usage-summary")
      header_hold_reader_frame

      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-usage-details[open]"
      header_tab_to(target)
      page.execute_script("window.headerOrderingBoundary.mark('native-tab-accepted')")
      accepted = page.evaluate_script("window.headerOrderingBoundary.sample().trace.find(entry => entry.event === 'native-tab-accepted')")
      page.execute_script("window.headerOrderingBoundary.release()")
      3.times { header_settle }
      sample = page.evaluate_script("window.headerOrderingBoundary.sample()")
      header_record("ordering-native-tab", sample, screenshot: true)

      key = sample.fetch("trace").find { |entry| entry["event"] == "keydown" && entry["key"] == "Tab" }
      assert key.fetch("trusted"), sample.to_json
      refute_nil key.fetch("activation"), sample.to_json
      assert_operator accepted.fetch("top"), :>, key.fetch("top"), sample.to_json
      assert sample.fetch("trace").any? { |entry| entry["event"] == "recordInput:before" && entry["activation"] && entry["active"] != "chat-usage-summary" }, sample.to_json
      assert accepted.fetch("paused"), sample.to_json
      assert_operator accepted.fetch("gap"), :>, 80, sample.to_json
      assert_in_delta accepted.fetch("top"), page.evaluate_script("document.querySelector('[data-application-scroll]').scrollTop"), 1, sample.to_json
      assert_selector "#{target}:focus"
      assert_in_delta accepted.fetch("activeTop"), page.evaluate_script("document.activeElement.getBoundingClientRect().top"), 1
      header_hit(target)
      assert_no_button "Latest message"
      assert_no_enqueued_jobs only: ChatResponseJob
    ensure
      page.execute_script("window.headerOrderingBoundary?.restore()")
    end
  end

  private
    def header_icon_stroke(selector)
      sample = page.evaluate_script(<<~JS, find(selector))
        (() => {
          const svg = arguments[0], color = getComputedStyle(svg).color
          return { color, paths: [...svg.querySelectorAll('path')].map(path => {
            const style = getComputedStyle(path)
            return { stroke: style.stroke, strokeOpacity: style.strokeOpacity, fill: style.fill }
          }) }
        })()
      JS
      header_record("history-icon-stroke", { selector: selector, measurement: sample })
      refute_empty sample.fetch("paths"), sample.to_json
      sample.fetch("paths").each do |path|
        assert_equal sample.fetch("color"), path.fetch("stroke"), sample.to_json
        assert_equal 1, path.fetch("strokeOpacity").to_f, sample.to_json
        assert_equal "none", path.fetch("fill"), sample.to_json
      end
    end

    def header_hold_reader_frame
      page.execute_script(<<~JS)
        (() => {
          const root = document.querySelector('.n-chat-workspace--saved'), surface = root.querySelector('[data-scroll-target~="surface"]')
          const reader = window.Stimulus.getControllerForElementAndIdentifier(root, 'scroll')
          const summary = root.querySelector('#chat-usage-summary')
          const raf = window.requestAnimationFrame, caf = window.cancelAnimationFrame, schedule = reader.schedule
          const callbacks = new Map(), originals = new Map()
          let scheduling = false, holding = true, serial = 0
          const boundary = window.headerOrderingBoundary = { trace: [] }
          const mark = (event, extra = {}) => {
            const anchor = reader.state.anchor, message = anchor && document.getElementById(anchor.id)
            const block = message && (reader.blocksFor(message)[anchor.block] || message)
            const active = document.activeElement
            boundary.trace.push({ event, ...extra, top: surface.scrollTop, height: surface.scrollHeight,
              clientHeight: surface.clientHeight, gap: surface.scrollHeight - surface.clientHeight - surface.scrollTop,
              summaryTop: summary.getBoundingClientRect().top, summaryBottom: summary.getBoundingClientRect().bottom,
              active: active.id || active.tagName, activeTop: active.getBoundingClientRect().top,
              activation: reader.disclosureActivation ? { offset: reader.disclosureActivation.offset, open: reader.disclosureActivation.open } : null,
              anchor: anchor && { ...anchor }, blockTop: block?.getBoundingClientRect().top,
              latestVisible: !reader.latestTarget.hidden, paused: reader.state.paused, pending: reader.state.pending })
          }
          // Hold only the existing reader's actual queued RAF callbacks. All other
          // native frame work (including Turbo rendering) runs normally. No input,
          // focus, scroll, geometry, reader state or observer acknowledgment is forged.
          window.requestAnimationFrame = callback => {
            if (!holding || !scheduling) return raf.call(window, callback)
            const id = --serial
            callbacks.set(id, { callback, delivered: null })
            return id
          }
          window.cancelAnimationFrame = id => {
            const entry = callbacks.get(id)
            if (entry) { caf.call(window, entry.delivered); callbacks.delete(id) }
            else caf.call(window, id)
          }
          reader.schedule = function(...args) {
            mark('schedule', { stack: new Error().stack })
            scheduling = true
            try { return schedule.apply(this, args) } finally { scheduling = false }
          }
          for (const name of ['restoreDisclosure', 'recordInput', 'capture', 'reflect', 'restoreAnchor', 'reconcile']) {
            const original = reader[name]
            originals.set(name, original)
            reader[name] = function(...args) {
              mark(`${name}:before`)
              const result = original.apply(this, args)
              mark(`${name}:after`, name === 'restoreDisclosure' ? { restored: !!result } : {})
              return result
            }
          }
          const keydown = event => mark('keydown', { key: event.key, trusted: event.isTrusted })
          const focusin = () => mark('focusin-after-reader')
          surface.addEventListener('keydown', keydown, true)
          surface.addEventListener('focusin', focusin)
          boundary.mark = mark
          boundary.release = () => {
            holding = false
            for (const [id, entry] of callbacks) entry.delivered = raf.call(window, time => { callbacks.delete(id); entry.callback(time) })
          }
          boundary.sample = () => { mark('settled'); return { trace: boundary.trace, heldCallbacks: callbacks.size } }
          boundary.restore = () => {
            for (const entry of callbacks.values()) caf.call(window, entry.delivered)
            window.requestAnimationFrame = raf; window.cancelAnimationFrame = caf; reader.schedule = schedule
            for (const [name, original] of originals) reader[name] = original
            surface.removeEventListener('keydown', keydown, true)
            surface.removeEventListener('focusin', focusin)
          }
          mark('installed')
        })()
      JS
    end

    def header_overflow_fixture(label)
      if page.evaluate_script("document.querySelector('[data-application-scroll]').scrollHeight - document.querySelector('[data-application-scroll]').clientHeight < 900")
        before = header_geometry
        # Geometry only: a nonshrinking child of the actual primary surface.
        page.execute_script(<<~JS)
          const fixture = document.createElement('div')
          fixture.dataset.headerOverflowFixture = ''
          fixture.inert = true
          fixture.style.cssText = 'height:2200px;flex:none'
          document.querySelector('[data-application-scroll]').append(fixture)
        JS
        header_settle
        assert_selector "[data-application-scroll] > [data-header-overflow-fixture][inert]", count: 1, visible: :all
        fixture = page.evaluate_script(<<~JS)
          (() => {
            const fixture = document.querySelector('[data-header-overflow-fixture]'), style = getComputedStyle(fixture)
            return { geometry: fixture.getBoundingClientRect().toJSON(), flexShrink: style.flexShrink, inert: fixture.inert,
              parentId: fixture.parentElement.id, insideMain: !!fixture.closest('main') }
          })()
        JS
        header_record("#{label}-fixture-layout", { before: before, after: header_geometry,
          fixture: fixture, placement: "inert nonshrinking child of the actual primary surface", actualWorkflow: false })
        assert_equal "0", fixture.fetch("flexShrink")
        assert_equal "application-scroll", fixture.fetch("parentId")
        assert fixture.fetch("insideMain"), fixture.to_json
      end
    end

    def header_pages
      [ user_root_path, accounts_path, account_path(@second), sources_path, token_usage_path,
        settings_path, profile_path, account_agent_skills_path(@second), account_mcp_servers_path(@second),
        new_chat_path(account_id: @second.id), chat_path(@chat) ]
    end

    def assert_header_widths
      sample = page.evaluate_script(<<~JS)
        ({ viewport: innerWidth, document: document.documentElement.scrollWidth,
          application: document.querySelector('[data-application-scroll]').scrollWidth })
      JS
      %w[document application].each { |key| assert_operator sample.fetch(key), :<=, sample.fetch("viewport"), sample.to_json }
    end

    def header_matrix_geometry
      header_geometry.merge(page.evaluate_script(<<~JS))
        (() => {
          const header = document.querySelector('main header, .n-dashboard-heading')
          const controls = [...document.querySelectorAll('.n-orbite-rail a, .n-orbite-rail button, #chat-history a, #chat-history button, #chat-history select, main header a, main header button, main header summary')]
            .filter(element => element.checkVisibility() && getComputedStyle(element).visibility === 'visible')
          return { pageHeader: header.getBoundingClientRect().toJSON(),
            controls: controls.map(element => ({ id: element.id, text: element.textContent.trim(), geometry: element.getBoundingClientRect().toJSON() })) }
        })()
      JS
    end

    def header_disclosures(index)
      if page.has_selector?("details[data-header-details]", wait: 0)
        summary = "details[data-header-details] > summary"
        assert_selector "details[data-header-details]:not([open])"
        header_tab_to(summary)
        page.driver.browser.action.send_keys(:enter).perform
        assert_selector "details[data-header-details][open]"
        assert_header_widths
        header_hit(summary)
        header_record("matrix-details-open-#{index}", header_matrix_geometry, screenshot: true)
        page.driver.browser.action.send_keys(:space).perform
        assert_selector "details[data-header-details]:not([open])"
      elsif page.has_selector?("#chat-usage-summary", wait: 0)
        header_tab_to("#chat-usage-summary")
        page.driver.browser.action.send_keys(:enter).perform
        assert_selector "#chat-usage-details[open]"
        assert_selector "#chat-usage-details > .n-workspace-help", text: @second.name, exact_text: true
        assert_header_widths
        header_hit("#chat-usage-summary")
        sample = page.evaluate_script(<<~JS)
          (() => {
            const preview = document.querySelector('[data-chat-account-label]'), full = document.querySelector('#chat-usage-details > p')
            const usage = document.querySelector('#chat-usage-details'), actions = document.querySelector('.n-chat-toolbar > .n-workspace-actions')
            const range = document.createRange(); range.selectNodeContents(full)
            const rect = full.getBoundingClientRect()
            return { preview: { geometry: preview.getBoundingClientRect().toJSON(), clientWidth: preview.clientWidth, scrollWidth: preview.scrollWidth,
                textOverflow: getComputedStyle(preview).textOverflow, whiteSpace: getComputedStyle(preview).whiteSpace },
              fullAccount: { text: full.textContent, geometry: rect.toJSON(), fits: full.scrollWidth <= full.clientWidth && [...range.getClientRects()].every(line => line.left >= rect.left - 1 && line.right <= rect.right + 1) },
              ownRow: !actions.contains(usage) && usage.getBoundingClientRect().top >= actions.getBoundingClientRect().bottom }
          })()
        JS
        header_record("matrix-saved-account-usage-#{index}", header_matrix_geometry.merge(sample), screenshot: true)
        assert_operator sample.fetch("preview").fetch("scrollWidth"), :>, sample.fetch("preview").fetch("clientWidth"), sample.to_json
        assert_operator sample.fetch("preview").fetch("geometry").fetch("left"), :>=, 0, sample.to_json
        assert_operator sample.fetch("preview").fetch("geometry").fetch("right"), :<=, page.evaluate_script("innerWidth"), sample.to_json
        assert_equal "ellipsis", sample.fetch("preview").fetch("textOverflow"), sample.to_json
        assert_equal "nowrap", sample.fetch("preview").fetch("whiteSpace"), sample.to_json
        assert sample.fetch("fullAccount").fetch("fits"), sample.to_json
        assert sample.fetch("ownRow"), sample.to_json
        page.driver.browser.action.send_keys(:space).perform
        assert_selector "#chat-usage-details:not([open])"
      end
      header_top
    end

    # Opaque canvas or modal interiors only, never backdrop composition or glyph
    # contrast inferred from a focus outline/border.
    def header_contrast(selector, minimum: 4.5, property: "color")
      element = find(selector)
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        Promise.all(document.getAnimations().filter(animation => Number.isFinite(animation.effect.getComputedTiming().endTime))
          .map(animation => animation.finished.catch(() => {}))).then(done)
      JS
      sample = page.evaluate_script(<<~JS, element, property)
        (() => {
          const element = arguments[0], property = arguments[1]
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
          const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
          const rgba = color => {
            if (!CSS.supports('color', color)) throw new Error(`Unparsed header color: ${color}`)
            context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data].map(channel => channel / 255)
          }
          const over = (fg, bg) => [...fg.slice(0, 3).map((channel, i) => channel * fg[3] + bg[i] * (1 - fg[3])), 1]
          const modal = element.closest('dialog:modal'), chain = []
          for (let node = element; node; node = node.parentElement) { chain.unshift(node); if (node === modal) break }
          if (modal && rgba(getComputedStyle(modal).backgroundColor)[3] !== 1) throw new Error('Modal interior must have an opaque backing surface')
          const backgrounds = chain.map(node => {
            const style = getComputedStyle(node)
            if (style.backgroundImage !== 'none' || Number(style.opacity) !== 1 || style.filter !== 'none' || style.backdropFilter !== 'none' || style.mixBlendMode !== 'normal')
              throw new Error(`Unmeasured header paint effect on ${node.tagName}`)
            return style.backgroundColor
          })
          if (!backgrounds.some(color => rgba(color)[3] === 1)) throw new Error('No measured opaque backing surface')
          const background = backgrounds.reduce((bg, color) => over(rgba(color), bg), [1, 1, 1, 1])
          const style = getComputedStyle(element)
          if (property === 'fill' && Number(style.fillOpacity) !== 1) throw new Error('Unmeasured SVG fill opacity')
          const color = style[property], foreground = over(rgba(color), background)
          const luminance = color => color.slice(0, 3).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4)
            .reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0)
          const a = luminance(foreground), b = luminance(background), rect = element.getBoundingClientRect()
          const hit = document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2)
          return { property, color, foreground, background, backgrounds, geometry: rect.toJSON(),
            hit: !!hit && (hit === element || element.contains(hit)), ratio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05) }
        })()
      JS
      header_record("header-contrast", { selector: selector, minimum: minimum, measurement: sample })
      assert sample.fetch("hit"), sample.to_json
      assert_operator sample.fetch("ratio"), :>=, minimum, sample.to_json
    end

    def header_prepare_paused_chat(direction)
      @second.update_columns(name: "CompteDeRecherche" * 12)
      header_viewport(375, 812)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      find("#chat-usage-summary").click
      assert_selector "#chat-usage-details[open]"
      header_tab_to(direction == "backward" ? "#chat-usage-summary" : ".n-chat-toolbar a[href='#{user_root_path}']")
      page.execute_script(<<~JS)
        const surface = document.querySelector('[data-application-scroll]')
        const paragraph = document.querySelectorAll('.n-chat-transcript .ai-response-content p')[19]
        surface.scrollTop += paragraph.getBoundingClientRect().top - surface.getBoundingClientRect().top - 24
        surface.dispatchEvent(new Event('scroll'))
      JS
      header_settle
      assert_selector ".n-chat-workspace[data-reader-following='false']"
    end

    def header_reader_anchor(index = nil)
      page.evaluate_script(<<~JS, index)
        (() => {
          const top = document.querySelector('[data-application-scroll]').getBoundingClientRect().top
          const paragraphs = [...document.querySelectorAll('.n-chat-transcript .ai-response-content p')]
          const paragraph = Number.isInteger(arguments[0]) ? paragraphs[arguments[0]] : paragraphs.find(element => element.getBoundingClientRect().bottom > top)
          return { index: paragraphs.indexOf(paragraph), text: paragraph.textContent, offset: paragraph.getBoundingClientRect().top - top }
        })()
      JS
    end

    def header_defer_resize_acknowledgment
      page.execute_script(<<~JS)
        (() => {
          const root = document.querySelector('.n-chat-workspace--saved'), surface = root.querySelector('[data-scroll-target~="surface"]')
          const reader = window.Stimulus.getControllerForElementAndIdentifier(root, 'scroll')
          const remember = reader.rememberPosition
          const boundary = window.headerResizeBoundary = { pending: true, deferred: 0, trace: [] }
          const sample = (event, extra = {}) => {
            const active = document.activeElement
            boundary.trace.push({ event, ...extra, top: surface.scrollTop, clientWidth: surface.clientWidth,
              clientHeight: surface.clientHeight, active: active.id || active.textContent.trim().slice(0, 80),
              activeRect: active.getBoundingClientRect().toJSON(),
              ledger: { top: reader.position.top, clientWidth: reader.position.clientWidth, clientHeight: reader.position.clientHeight },
              state: JSON.parse(JSON.stringify(root.chatReaderState)) })
          }
          // Test-only pending-dimensions boundary: let real resize/RAF work run,
          // but defer its ledger acknowledgment until the actual native Tab.
          // No focus/scroll writes, synthetic key events, or post-key delay gates.
          reader.rememberPosition = function(...args) {
            if (boundary.pending && (this.position.clientWidth !== surface.clientWidth || this.position.clientHeight !== surface.clientHeight)) {
              boundary.deferred++
            } else {
              return remember.apply(this, args)
            }
          }
          const keydown = event => {
            sample('keydown', { key: event.key, shift: event.shiftKey, trusted: event.isTrusted })
            if (event.key === 'Tab') boundary.pending = false
          }
          const focused = () => sample('focusin')
          const scrolled = () => sample('scroll-after-reader')
          surface.addEventListener('keydown', keydown, true)
          surface.addEventListener('focusin', focused, true)
          surface.addEventListener('scroll', scrolled)
          boundary.restore = () => {
            reader.rememberPosition = remember
            surface.removeEventListener('keydown', keydown, true)
            surface.removeEventListener('focusin', focused, true)
            surface.removeEventListener('scroll', scrolled)
          }
          boundary.sample = () => { sample('settled'); return { deferred: boundary.deferred, trace: boundary.trace } }
          sample('before-resize')
        })()
      JS
    end

    def header_resize_sample
      page.evaluate_script("window.headerResizeBoundary.sample()")
    end

    def header_viewport(width, height)
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      page.current_window.resize_to(width, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
    end

    def header_settle
      page.evaluate_async_script("const done = arguments[arguments.length - 1]; requestAnimationFrame(() => requestAnimationFrame(done))")
    end

    def header_top
      page.execute_script(<<~JS)
        const surface = document.querySelector('[data-application-scroll]')
        surface.scrollTop = 0
        surface.dispatchEvent(new Event('scroll'))
      JS
      header_settle
    end

    def header_theme(dark)
      header_top
      orbite_theme(dark)
      header_settle
    end

    def header_tab_to(selector, enlarged: false)
      160.times do
        page.driver.browser.action.send_keys(:tab).perform
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          assert_selector "#{selector}:focus"
          header_settle
          enlarged ? header_enlarged_hit(selector) : header_hit(selector)
          return
        end
      end
      flunk "Keyboard traversal did not reach #{selector}"
    end

    def header_enlarged_hit(selector)
      header_contrast(selector, minimum: 3, property: "outlineColor")
      sample = page.evaluate_script(<<~JS, find(selector))
        (() => {
          const element = arguments[0], rect = element.getBoundingClientRect(), style = getComputedStyle(element)
          const corners = [['borderTopLeftRadius', rect.left, rect.top, 1, 1], ['borderTopRightRadius', rect.right, rect.top, -1, 1],
            ['borderBottomLeftRadius', rect.left, rect.bottom, 1, -1], ['borderBottomRightRadius', rect.right, rect.bottom, -1, -1]]
          const radii = corners.map(([property, x, y, dx, dy]) => {
            const parts = style[property].split(' ')
            if (parts.some(value => !/^\\d+(?:\\.\\d+)?px$/.test(value))) throw new Error('Unmeasured rounded radius')
            const rx = Math.min(parseFloat(parts[0]), rect.width / 2), ry = Math.min(parseFloat(parts[1] || parts[0]), rect.height / 2)
            return { property, computed: style[property], rx, ry, point: [x + dx * (rx * (1 - Math.SQRT1_2) + 1), y + dy * (ry * (1 - Math.SQRT1_2) + 1)] }
          })
          const points = [[rect.x + rect.width / 2, rect.y + rect.height / 2], [rect.x + rect.width / 2, rect.top + 2],
            [rect.x + rect.width / 2, rect.bottom - 2], [rect.left + 2, rect.y + rect.height / 2], [rect.right - 2, rect.y + rect.height / 2], ...radii.map(radius => radius.point)]
          const outset = Math.max(0, parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset))
          return { geometry: rect.toJSON(), viewport: [innerWidth, innerHeight], radii, points,
            formula: 'corner inset = computed radius * (1 - sqrt(1/2)) + 1 CSS px inside the painted arc',
            hits: points.map(([x, y]) => { const hit = document.elementFromPoint(x, y); return !!hit && (hit === element || element.contains(hit)) }),
            focusVisible: element.matches(':focus-visible'), outlineWidth: parseFloat(style.outlineWidth), outlineStyle: style.outlineStyle,
            indicatorFits: rect.left - outset >= 0 && rect.right + outset <= innerWidth && rect.top - outset >= 0 && rect.bottom + outset <= innerHeight }
        })()
      JS
      header_record("enlarged-keyboard-control", { selector: selector, measurement: sample })
      geometry = sample.fetch("geometry")
      assert_operator geometry.fetch("left"), :>=, 0, sample.to_json
      assert_operator geometry.fetch("right"), :<=, sample.fetch("viewport").first + 1, sample.to_json
      assert_operator geometry.fetch("top"), :>=, 0, sample.to_json
      assert_operator geometry.fetch("bottom"), :<=, sample.fetch("viewport").last + 1, sample.to_json
      assert sample.fetch("hits").all?, sample.to_json
      assert sample.fetch("focusVisible"), sample.to_json
      assert_operator sample.fetch("outlineWidth"), :>=, 2, sample.to_json
      refute_equal "none", sample.fetch("outlineStyle"), sample.to_json
      assert sample.fetch("indicatorFits"), sample.to_json
    end

    def header_hit(selector)
      element = find(selector)
      # Measure settled native focus paint, not a transient transition color.
      page.evaluate_async_script(<<~JS, element)
        const element = arguments[0], done = arguments[arguments.length - 1]
        Promise.all(element.getAnimations().map(animation => animation.finished.catch(() => {}))).then(done)
      JS
      sample = page.evaluate_script(<<~JS, element)
        (() => {
          const element = arguments[0], rect = element.getBoundingClientRect(), style = getComputedStyle(element)
          const points = [[rect.x + rect.width / 2, rect.y + rect.height / 2], [rect.x + rect.width / 2, rect.top + 2],
            [rect.x + rect.width / 2, rect.bottom - 2], [rect.left + 2, rect.y + rect.height / 2], [rect.right - 2, rect.y + rect.height / 2]]
          const hits = points.map(([x, y]) => { const hit = document.elementFromPoint(x, y); return !!hit && (hit === element || element.contains(hit)) })
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
          const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
          const rgba = color => {
            context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data].map(channel => channel / 255)
          }
          const over = (fg, bg) => [...fg.slice(0, 3).map((channel, i) => channel * fg[3] + bg[i] * (1 - fg[3])), 1]
          const modal = element.closest('dialog:modal'), chain = []
          for (let node = element; node; node = node.parentElement) { chain.unshift(node); if (node === modal) break }
          if (modal && rgba(getComputedStyle(modal).backgroundColor)[3] !== 1) throw new Error('Modal interior must have an opaque backing surface')
          for (const node of chain) {
            const paint = getComputedStyle(node)
            if (paint.backgroundImage !== 'none' || Number(paint.opacity) !== 1 || paint.filter !== 'none' || paint.backdropFilter !== 'none' || paint.mixBlendMode !== 'normal')
              throw new Error('Unmeasured header paint effect')
          }
          const background = chain.map(node => getComputedStyle(node).backgroundColor).reduce((bg, color) => over(rgba(color), bg), [1, 1, 1, 1])
          const foreground = over(rgba(style.outlineColor), background)
          const luminance = color => color.slice(0, 3).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4)
            .reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0)
          const a = luminance(foreground), b = luminance(background)
          const outset = Math.max(0, parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset))
          return { geometry: rect.toJSON(), hits, viewport: [innerWidth, innerHeight],
            focusVisible: element.matches(':focus-visible'), outlineWidth: parseFloat(style.outlineWidth), outlineOffset: parseFloat(style.outlineOffset),
            outlineStyle: style.outlineStyle, borderRadius: style.borderRadius,
            outlineColor: style.outlineColor, background, outlineRatio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05),
            indicatorFits: rect.left - outset >= 0 && rect.right + outset <= innerWidth && rect.top - outset >= 0 && rect.bottom + outset <= innerHeight }
        })()
      JS
      header_record("keyboard-control", { selector: selector, measurement: sample })
      geometry = sample.fetch("geometry")
      assert_operator geometry.fetch("left"), :>=, 0, sample.to_json
      assert_operator geometry.fetch("right"), :<=, sample.fetch("viewport").first + 1, sample.to_json
      assert_operator geometry.fetch("top"), :>=, 0, sample.to_json
      assert_operator geometry.fetch("bottom"), :<=, sample.fetch("viewport").last + 1, sample.to_json
      assert sample.fetch("hits").all?, "Covered header control: #{selector}: #{sample.to_json}"
      assert sample.fetch("focusVisible"), sample.to_json
      assert_operator sample.fetch("outlineWidth"), :>=, 2, sample.to_json
      refute_equal "none", sample.fetch("outlineStyle"), sample.to_json
      assert_operator sample.fetch("outlineRatio"), :>=, 3, sample.to_json
      assert sample.fetch("indicatorFits"), "Clipped header focus: #{sample.to_json}"
      sample
    end

    def settle_workspace_layout
      page.evaluate_async_script("const done = arguments[arguments.length - 1]; requestAnimationFrame(() => requestAnimationFrame(done))")
    end

    def assert_header_scroll_movement(before_scroll, sample)
      delta = sample.fetch("surface").fetch("scrollTop") - before_scroll.fetch("surface").fetch("scrollTop")
      diagnostic = { before: before_scroll, after: sample, actual_delta: delta }.to_json
      assert_operator delta, :>=, 699, diagnostic
      %w[surface main].each do |element|
        %w[left top width height].each do |dimension|
          assert_in_delta before_scroll.fetch(element).fetch(dimension), sample.fetch(element).fetch(dimension), 1, diagnostic
        end
      end
      %w[left right width height].each do |dimension|
        assert_in_delta before_scroll.fetch("heading").fetch(dimension), sample.fetch("heading").fetch(dimension), 1, diagnostic
      end
      contexts = %w[viewport windowScroll documentElement body usageOpen]
      assert_equal before_scroll.fetch("scrollContext").slice(*contexts), sample.fetch("scrollContext").slice(*contexts), diagnostic
      assert_in_delta before_scroll.fetch("heading").fetch("bottom") - delta, sample.fetch("heading").fetch("bottom"), 1, diagnostic
    end

    def header_scroll_context
      page.evaluate_script(<<~JS)
        (() => {
          const sample = element => {
            const style = getComputedStyle(element)
            return { geometry: element.getBoundingClientRect().toJSON(), scrollTop: element.scrollTop, scrollLeft: element.scrollLeft,
              scrollHeight: element.scrollHeight, scrollWidth: element.scrollWidth, clientHeight: element.clientHeight, clientWidth: element.clientWidth,
              scrollPaddingStart: style.scrollPaddingBlockStart, scrollPaddingEnd: style.scrollPaddingBlockEnd,
              scrollMarginStart: style.scrollMarginBlockStart, scrollMarginEnd: style.scrollMarginBlockEnd }
          }
          const active = document.activeElement, usage = document.querySelector('#chat-usage-details')
          return { scrollContext: { surface: sample(document.querySelector('[data-application-scroll]')), main: sample(document.querySelector('main')),
            documentElement: sample(document.documentElement), body: sample(document.body),
            active: { tag: active.tagName, id: active.id, geometry: active.getBoundingClientRect().toJSON() },
            usageOpen: usage ? usage.open : null, viewport: [innerWidth, innerHeight], windowScroll: [scrollX, scrollY] } }
        })()
      JS
    end

    def header_geometry
      page.evaluate_script(<<~JS)
        (() => {
          const sample = element => ({ ...element.getBoundingClientRect().toJSON(),
            id: element.id, scrollTop: element.scrollTop, scrollHeight: element.scrollHeight, clientHeight: element.clientHeight })
          return { navigation: sample(document.querySelector('.n-orbite-rail')),
            heading: sample(document.querySelector('main h1')), main: sample(document.querySelector('main')),
            surface: sample(document.querySelector('[data-application-scroll]')),
            syntheticOverflow: !!document.querySelector('[data-header-overflow-fixture]') }
        })()
      JS
    end

    def header_record(label, sample, screenshot: false)
      @header_evidence ||= Dir.mktmpdir("compact-headers-", ENV.fetch("EVIDENCE", Dir.tmpdir))
      context = page.evaluate_script("({ path: location.pathname, query: location.search, locale: document.documentElement.lang, dark: document.documentElement.classList.contains('dark'), viewport: [innerWidth, innerHeight] })")
      @header_source_commit ||= IO.popen([ "git", "-C", Rails.root.to_s, "rev-parse", "HEAD" ], &:read).strip
      entry = context.merge(sourceCommit: @header_source_commit, label: label, sample: sample)
      if screenshot
        entry[:screenshot] = File.join(@header_evidence, "#{label}-#{SecureRandom.hex(4)}.png")
        page.save_screenshot(entry[:screenshot])
      end
      File.open(File.join(@header_evidence, "measurements.jsonl"), "a") { |file| file.puts(entry.to_json) }
      puts "Compact header evidence: #{@header_evidence}; #{entry.to_json}"
    end
end

class CompactAccountHeadersSystemTest < ApplicationSystemTestCase
  include AccountExperienceFixtures
  include OrbiteBrowserChecks

  setup do
    @original_size = page.current_window.size
    page.current_window.resize_to(1400, 1000)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1400, height: 1000, deviceScaleFactor: 1, mobile: false)
    @context_evidence = Dir.mktmpdir("compact-account-context-", ENV.fetch("EVIDENCE", Dir.tmpdir))
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(*@original_size) if @original_size
  end

  test "account uid and viewer role stay visible while heading Details is closed" do
    { owner: @user, member: @member }.each do |role, user|
      visit root_url
      fill_in "email", with: user.email
      fill_in "password", with: AccountExperienceFixtures::PASSWORD
      find("form[action='#{login_path}'] input[type='submit']").click
      assert_selector "[data-dashboard]"

      %i[en fr].each do |locale|
        visit account_path(@second)
        orbite_select_language(locale.to_s.upcase)
        assert_selector "html[lang='#{locale}']"
        assert_selector "[data-account-overview='#{@second.id}']"
        assert_selector ".n-workspace-header details[data-header-details]:not([open])", count: 1
        sample = record_account_context(role, locale)
        expected = "#{@second.uid} · #{I18n.t("nosia.account_experience.roles.#{role}", locale: locale)}"

        assert_selector ".n-workspace-header", text: expected
        assert_selector ".n-workspace-header [data-workspace-scope]", text: expected, exact_text: true, count: 1
        assert_no_selector ".n-workspace-header details [data-workspace-scope]", visible: :all
        assert_no_selector ".n-workspace-header .n-workspace-trail"
        assert sample.fetch("scope").fetch("visible"), sample.to_json
        bounds = sample.fetch("scope").fetch("bounds")
        assert_operator bounds.fetch("left"), :>=, 0, sample.to_json
        assert_operator bounds.fetch("right"), :<=, sample.fetch("viewport").first, sample.to_json
        assert_operator bounds.fetch("top"), :>=, 0, sample.to_json
        assert_operator bounds.fetch("bottom"), :<=, sample.fetch("viewport").last, sample.to_json
        assert sample.fetch("scope").fetch("hits").all?, sample.to_json
        assert_operator sample.fetch("scope").fetch("scrollWidth"), :<=, sample.fetch("scope").fetch("clientWidth"), sample.to_json
        edit = ".n-workspace-header a[href='#{edit_account_path(@second)}']"
        if role == :owner
          assert_selector edit, text: I18n.t("nosia.account_experience.edit_account", locale: locale), count: 1
        else
          assert_no_selector edit, visible: :all
        end
        assert_selector ".n-workspace-header details[data-header-details]:not([open])", count: 1
      end

      orbite_open_utilities
      find("#dropdownUser").click
      find("#dropdown a[href='#{logout_path}']").click
      assert_selector "form[action='#{login_path}']"
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  private
    def record_account_context(role, locale)
      sample = page.evaluate_script(<<~JS)
        (() => {
          const header = document.querySelector('.n-workspace-header'), scope = header.querySelector('[data-workspace-scope]')
          const rect = scope?.getBoundingClientRect()
          const hits = rect && [[rect.x + rect.width / 2, rect.y + rect.height / 2], [rect.left + 2, rect.top + 2], [rect.right - 2, rect.bottom - 2]]
            .map(([x, y]) => { const hit = document.elementFromPoint(x, y); return !!hit && (hit === scope || scope.contains(hit)) })
          return { path: location.pathname, locale: document.documentElement.lang, viewport: [innerWidth, innerHeight],
            closed: !header.querySelector('details[data-header-details]').open, renderedText: header.innerText, allText: header.textContent.trim(),
            scope: scope && { text: scope.textContent, visible: scope.checkVisibility(), bounds: rect.toJSON(), hits,
              scrollWidth: scope.scrollWidth, clientWidth: scope.clientWidth } }
        })()
      JS
      screenshot = File.join(@context_evidence, "#{role}-#{locale}.png")
      page.save_screenshot(screenshot)
      entry = sample.merge("role" => role, "screenshot" => screenshot)
      File.open(File.join(@context_evidence, "measurements.jsonl"), "a") { |file| file.puts(entry.to_json) }
      puts "Account header context evidence: #{entry.to_json}"
      sample
    end
end
