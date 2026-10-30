require "application_system_test_case"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/chat_workspace_browser_checks"

class ChatWorkspaceSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper
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

  test "History contains keyboard focus and returns to the exact unsent editor" do
    set_reader_viewport(1024, 1000)
    visit new_chat_url(account_id: @second.id)
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep this unsent draft")
    page.execute_script("window.savedChatEditor = document.querySelector('lexxy-editor')")
    counts = [ Chat.count, Message.count ]

    click_button "History"

    assert_native_dialog "chat-history"
    12.times { page.driver.browser.action.send_keys(:tab).perform }
    assert_dialog_focus "chat-history"
    page.execute_script("document.querySelector('button[aria-label=Send]').focus()")
    assert_dialog_focus "chat-history"
    page.driver.browser.action.send_keys(:escape).perform

    assert_no_selector "#chat-history[open]", visible: :all
    assert_selector "#workspace-history-trigger:focus"
    assert page.evaluate_script("window.savedChatEditor === document.querySelector('lexxy-editor')")
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this unsent draft"
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "saved Tools is a native modal during generation without losing Stop" do
    set_reader_viewport(1024, 1000)
    @chat.start_generation!
    visit chat_url(@chat)
    assert_button "Stop generating", enable_aria_label: true

    find(".n-composer-tools-trigger").click

    assert_native_dialog "mcp-selector-modal"
    assert_no_selector "#chat-history[open]", visible: :all
    within "#mcp-selector-modal" do
      assert_text "Second tool"
      assert_no_text "First tool"
      click_button "Close", exact: true
    end

    assert_no_selector "#mcp-selector-modal[open]", visible: :all
    assert_selector ".n-composer-tools-trigger:focus"
    click_button "Stop generating", enable_aria_label: true
    assert_button "Send", disabled: false, enable_aria_label: true
    assert_not @chat.reload.generating?
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "Tools returns focus to the current trigger after its composer frame is replaced" do
    @chat.start_generation!
    visit chat_url(@chat)
    assert_button "Stop generating", enable_aria_label: true
    counts = [ Chat.count, Message.count ]
    page.execute_script("window.originalToolsTrigger = document.querySelector('.n-composer-tools-trigger')")
    find(".n-composer-tools-trigger").click
    assert_native_dialog "mcp-selector-modal"

    @chat.stop_generation!
    Current.reset
    replacement = ApplicationController.render(
      inline: '<%= turbo_stream.replace target, partial: "messages/form", locals: { chat: chat } %>',
      locals: { target: "#{dom_id(@chat)}_message_form", chat: @chat }
    )
    page.execute_script("Turbo.renderStreamMessage(arguments[0])", replacement)

    assert_selector "turbo-frame##{dom_id(@chat)}_message_form button[aria-label=Send]:not([disabled])"
    assert_not page.evaluate_script("window.originalToolsTrigger.isConnected")
    assert_native_dialog "mcp-selector-modal"
    assert_dialog_focus "mcp-selector-modal"
    within("#mcp-selector-modal") { click_button "Close", exact: true }

    assert_no_selector "#mcp-selector-modal[open]", visible: :all
    assert_selector "turbo-frame##{dom_id(@chat)}_message_form .n-composer-tools-trigger:focus"
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "History navigates and deletes an authorized conversation" do
    set_reader_viewport(1024, 1000)
    first_chat = workspace(:chats, :workspace_first_chat)
    visit chat_url(@chat)
    click_button "History"
    assert_native_dialog "chat-history"

    within "[data-history-chat='#{first_chat.id}']" do
      click_link "First account question"
    end
    assert_current_path chat_path(first_chat)

    click_button "History"
    assert_native_dialog "chat-history"
    accept_confirm do
      within "[data-history-chat='#{first_chat.id}']" do
        click_button "Delete chat"
      end
    end

    assert_current_path user_root_path
    assert_not Chat.exists?(first_chat.id)
  end

  test "Tools empty state links to its saved account and its named icon closes" do
    @second.mcp_servers.update_all(enabled: false)
    visit chat_url(@chat)
    find(".n-composer-tools-trigger").click

    assert_native_dialog "mcp-selector-modal"
    within "#mcp-selector-modal" do
      assert_selector "a[href='#{account_mcp_servers_path(@second)}']"
      assert_no_text "First tool"
      find("button[aria-label=Close]").click
    end

    assert_no_selector "#mcp-selector-modal[open]", visible: :all
    assert_selector ".n-composer-tools-trigger:focus"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "a second requested dialog replaces the first without stealing its focus" do
    set_reader_viewport(1024, 1000)
    visit chat_url(@chat)
    click_button "History"
    assert_native_dialog "chat-history"

    # Background controls are natively inert; dispatch a second request directly.
    page.execute_script("document.querySelector('.n-composer-tools-trigger').click()")

    assert_native_dialog "mcp-selector-modal"
    assert_selector "dialog[open]", count: 1
    assert_no_selector "#chat-history[open]", visible: :all
    assert_dialog_focus "mcp-selector-modal"
    page.driver.browser.action.send_keys(:tab).perform
    assert_dialog_focus "mcp-selector-modal"

    page.execute_script("document.querySelector('#workspace-history-trigger').click()")

    assert_native_dialog "chat-history"
    assert_selector "dialog[open]", count: 1
    assert_no_selector "#mcp-selector-modal[open]", visible: :all
    assert_dialog_focus "chat-history"
    within("#chat-history") { click_button "Close" }
    assert_selector "#workspace-history-trigger:focus"
  end

  test "History is closed before Turbo caches navigation and remains closed on Back" do
    set_reader_viewport(1024, 1000)
    first_chat = workspace(:chats, :workspace_first_chat)
    visit chat_url(@chat)
    click_button "History"
    assert_native_dialog "chat-history"
    page.execute_script(<<~JS)
      document.addEventListener('turbo:before-cache', () => {
        window.workspaceCachedDialogs = [...document.querySelectorAll('dialog[open]')].map(dialog => dialog.id)
      }, { once: true })
    JS

    within("[data-history-chat='#{first_chat.id}']") { click_link "First account question" }

    assert_current_path chat_path(first_chat)
    assert_equal [], page.evaluate_script("window.workspaceCachedDialogs")
    page.go_back
    assert_current_path chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    assert_no_selector "dialog[open]", visible: :all
    click_button "History"
    assert_native_dialog "chat-history"
    page.driver.browser.action.send_keys(:escape).perform
    assert_selector "#workspace-history-trigger:focus"
  end

  test "dialogs preserve draft account tool choices and pending source coordination" do
    set_reader_viewport(1024, 1000)
    [ new_chat_url(account_id: @second.id), chat_url(@chat) ].each do |url|
      visit url
      assert_selector "lexxy-editor[connected]"
      find("lexxy-editor .lexxy-editor__content").send_keys("Preserve source draft")
      if page.has_selector?("[data-composer-tools]")
        find("[data-composer-tools] summary").click
        check "Second tool"
        find("[data-composer-tools] summary").click
      end
      hold_source_registration
      page.execute_script(<<~JS)
        window.savedChatEditor = document.querySelector('lexxy-editor')
        window.savedChatEditor.dispatchEvent(new CustomEvent('lexxy:insert-link', {
          detail: { url: 'https://second.example/reference' }, bubbles: true
        }))
      JS
      assert_selector "button[aria-label=Send][disabled]"
      counts = [ Chat.count, Message.count, Website.count, Document.count ]
      click_button "History"
      assert_native_dialog "chat-history"
      within("#chat-history") { click_button "Close" }
      assert_selector "#workspace-history-trigger:focus"
      if page.has_selector?(".n-composer-tools-trigger")
        find(".n-composer-tools-trigger").click
        assert_native_dialog "mcp-selector-modal"
        within("#mcp-selector-modal") { click_button "Close", exact: true }
        assert_selector ".n-composer-tools-trigger:focus"
      end

      assert page.evaluate_script("window.savedChatEditor === document.querySelector('lexxy-editor')")
      assert_selector "lexxy-editor .lexxy-editor__content", text: "Preserve source draft"
      assert_selector "[data-composer-sources-account-id-value='#{@second.id}']"
      assert_selector "button[aria-label=Send][disabled]"
      if page.has_selector?("select[name='chat[account_id]']")
        assert_equal @second.id.to_s, find_field("Account", disabled: true).value
        assert_selector "input[name='mcp_server_ids[]']:checked", visible: :all
      else
        assert_selector "[data-chat-account-readonly]", text: "Research team"
      end

      page.execute_script("window.releaseWorkspaceSource()")

      assert_selector "[data-composer-sources-target=websiteIds] ~ input[value='#{websites(:picker_second_website).id}']", visible: :all
      assert_button "Send", disabled: false, enable_aria_label: true
      assert_selector "lexxy-editor .lexxy-editor__content", text: "Preserve source draft"
      assert_equal counts, [ Chat.count, Message.count, Website.count, Document.count ]
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "native formatting keeps workspace editor geometry stable with short and long drafts" do
    samples = []
    [ [ 1400, 844 ], [ 375, 844 ], [ 1400, 600 ], [ 768, 1024 ] ].each do |width, height|
      [ false, true ].each do |dark|
        [ new_chat_url(account_id: @second.id), chat_url(@chat) ].each do |url|
          %w[short long].each do |draft|
            page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
            page.current_window.resize_to(width, height)
            page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
            visit url
            assert_selector "lexxy-editor[connected]"
            page.execute_script(<<~JS, dark, draft)
              document.documentElement.classList.toggle('dark', arguments[0])
              document.querySelector('lexxy-editor').value = arguments[1] === 'long' ?
                Array.from({ length: 40 }, (_, index) => `<div>Draft line ${index + 1}</div>`).join('') : '<div>Short draft</div>'
            JS
            settle_workspace_layout
            page.execute_script("const content = document.querySelector('.lexxy-editor__content'); content.scrollTop = content.scrollHeight")
            page.execute_script("document.querySelector('summary[aria-label=Formatting]').scrollIntoView({ block: 'center' })")
            settle_workspace_layout
            before = formatting_geometry
            find("summary[aria-label=Formatting]").click
            assert_selector ".n-chat-composer[data-formatting-open] lexxy-toolbar"
            settle_workspace_layout
            opened = formatting_geometry
            find("summary[aria-label=Formatting]").click
            settle_workspace_layout
            closed = formatting_geometry
            samples << { url: url, width: width, height: height, dark: dark, draft: draft, before: before, opened: opened, closed: closed }
          end
        end
      end
    end
    evidence = File.join(ENV.fetch("EVIDENCE", "/tmp/opencode"), "dialogs-formatting-geometry-#{SecureRandom.hex(4)}.json")
    File.write(evidence, JSON.pretty_generate(samples))
    puts "Workspace formatting geometry: #{evidence}"

    samples.each do |sample|
      before, opened, closed = sample.values_at(:before, :opened, :closed)
      assert_operator opened.fetch("toolbar").fetch("height"), :>, 0, sample.to_json
      [ opened, closed ].each do |state|
        assert_in_delta before.fetch("editor").fetch("height"), state.fetch("editor").fetch("height"), 1, sample.to_json
        %w[top left width height].each do |dimension|
          assert_in_delta before.fetch("actions").fetch(dimension), state.fetch("actions").fetch(dimension), 1, sample.to_json
        end
        %w[surface main root].each do |name|
          assert_equal before.fetch(name).fetch("scrollTop"), state.fetch(name).fetch("scrollTop"), sample.to_json
        end
      end
      if sample.fetch(:draft) == "long"
        content = opened.fetch("content")
        assert_operator content.fetch("scrollHeight"), :>, content.fetch("clientHeight"), sample.to_json
        assert_equal "auto", content.fetch("overflowY"), sample.to_json
        assert_operator content.fetch("lastChild").fetch("top"), :>=, content.fetch("top"), sample.to_json
        assert_operator content.fetch("lastChild").fetch("bottom"), :<=, content.fetch("bottom"), sample.to_json
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  [ [ 1400, 1000 ], [ 375, 812 ], [ 812, 375 ] ].each do |width, height|
    test "reader follows only by intent while streaming at #{width}x#{height}" do
      visit_reader(width, height)
      pause_reader
      anchor = reader_anchor

      stream_answer(reader_answer(100))

      assert_button "Latest message"
      assert_reader_anchor anchor
      assert_reader_following false
      click_button "Latest message"
      assert_reader_following true
      assert_no_button "Latest message"
      assert_operator reader_gap, :<=, 80

      # A reader can also resume by manually returning within the threshold.
      pause_reader
      page.execute_script("const surface = #{reader_surface}; surface.scrollTop = surface.scrollHeight - surface.clientHeight - 60; surface.dispatchEvent(new Event('scroll'))")
      assert_reader_following true
      stream_answer(reader_answer(110))
      assert_operator reader_gap, :<=, 80
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    test "only a successful own follow-up resumes the reader at #{width}x#{height}" do
      visit_reader(width, height)
      pause_reader
      anchor = reader_anchor
      page.execute_script(<<~JS)
        const form = document.querySelector('form[data-chat-followup]')
        form.dispatchEvent(new CustomEvent('turbo:submit-start', { bubbles: true }))
        form.dispatchEvent(new CustomEvent('turbo:submit-end', { bubbles: true, detail: { success: false } }))
      JS
      assert_reader_following false
      assert_reader_anchor anchor
      assert_no_enqueued_jobs only: ChatResponseJob

      visit chat_url(@chat)
      assert_selector "lexxy-editor[connected]"
      find("lexxy-editor .lexxy-editor__content").send_keys("A real follow-up")
      pause_reader
      assert_selector "lexxy-editor .lexxy-editor__content", text: "A real follow-up", visible: :all
      page.execute_script(<<~JS)
        document.querySelector('form[data-chat-followup]').addEventListener('turbo:submit-end', event => {
          window.readerSubmissionSucceeded = event.detail.success
          window.readerWasPausedAtOutcome = document.querySelector('.n-chat-workspace').dataset.readerFollowing === 'false'
        }, { once: true })
      JS

      assert_enqueued_jobs 1, only: ChatResponseJob do
        # Native click without WebDriver scrolling the offscreen mobile dock first.
        page.execute_script("document.querySelector('button[aria-label=Send]').click()")
        assert_selector "form[data-chat-followup][data-generation-busy=true] lexxy-editor[disabled]"
        assert_reader_following true
      end

      assert page.evaluate_script("window.readerSubmissionSucceeded")
      assert page.evaluate_script("window.readerWasPausedAtOutcome")
      assert_equal "A real follow-up", @chat.messages.user.order(:created_at).last.content.strip
      assert_predicate @chat.reload, :generating?
      assert_operator reader_gap, :<=, 80
    end

    test "same URL refresh preserves paused visible content and stream focus at #{width}x#{height}" do
      visit_reader(width, height)
      pause_reader
      anchor = reader_anchor
      page.execute_script(<<~JS)
        document.documentElement.removeAttribute('data-reader-refresh-finished')
        document.addEventListener('turbo:render', () => { document.documentElement.dataset.readerRefreshFinished = 'true' }, { once: true })
        Turbo.visit(window.location.href, { action: 'replace' })
      JS
      assert_selector "lexxy-editor[connected]"
      assert_selector "html[data-reader-refresh-finished=true]"
      settle_workspace_layout
      assert_reader_following false
      assert_reader_anchor anchor
      page.execute_script("window.readerFocus = document.activeElement")

      stream_answer(reader_answer(100))

      assert_button "Latest message"
      assert_reader_anchor anchor
      assert page.evaluate_script("window.readerFocus === document.activeElement")
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    [ 0, 80 ].each do |gap|
      test "manual return resumes during actual stream growth at #{width}x#{height} with #{gap}px gap" do
        visit_reader(width, height)
        pause_reader
        stream_answer(reader_answer(90))
        assert_button "Latest message"
        assert_reader_following false
        page.execute_script(<<~JS, dom_id(workspace(:messages, :workspace_answer), :content), gap)
          const surface = #{reader_surface}, content = document.getElementById(arguments[0]), gap = arguments[1]
          const root = document.querySelector('.n-chat-workspace--saved'), latest = root.querySelector('[data-scroll-target=latest]')
          window.readerResumeRace = { heightBefore: surface.scrollHeight, topBefore: surface.scrollTop }
          const observer = new MutationObserver(() => {
            observer.disconnect()
            // This return happens after real content growth, before reconciliation.
            const evidence = window.readerResumeRace
            evidence.heightAfter = surface.scrollHeight
            evidence.topBeforeInput = surface.scrollTop
            evidence.followingBeforeInput = root.dataset.readerFollowing
            evidence.latestHiddenBeforeInput = latest.hidden
            surface.scrollTop = surface.scrollHeight - surface.clientHeight - gap
            evidence.requestedGap = surface.scrollHeight - surface.clientHeight - surface.scrollTop
            evidence.returnedTop = surface.scrollTop
            surface.dispatchEvent(new Event('scroll'))
            evidence.followingAfterInput = root.dataset.readerFollowing
            evidence.latestHiddenAfterInput = latest.hidden
            evidence.gapAfterInput = surface.scrollHeight - surface.clientHeight - surface.scrollTop
            evidence.topAfterInput = surface.scrollTop
          })
          observer.observe(content.parentElement, { childList: true })
        JS

        stream_answer(reader_answer(110))

        evidence = page.evaluate_script("window.readerResumeRace")
        puts "Reader resume race #{width}x#{height} gap #{gap}: #{evidence.to_json}"
        assert_operator evidence.fetch("heightAfter"), :>, evidence.fetch("heightBefore")
        assert_operator evidence.fetch("returnedTop"), :>, evidence.fetch("topBeforeInput")
        assert_equal gap, evidence.fetch("requestedGap")
        assert_equal "false", evidence.fetch("followingBeforeInput")
        assert_not evidence.fetch("latestHiddenBeforeInput")
        assert_equal "true", evidence.fetch("followingAfterInput")
        assert evidence.fetch("latestHiddenAfterInput")
        assert_operator evidence.fetch("gapAfterInput"), :<=, 80
        assert_operator evidence.fetch("topAfterInput"), :>, evidence.fetch("topBeforeInput")
        assert_reader_following true
        assert_no_button "Latest message"
        assert_operator reader_gap, :<=, 1
        assert_operator page.evaluate_script("#{reader_surface}.scrollTop"), :>, evidence.fetch("topBeforeInput")
        assert page.evaluate_script("document.getElementById(arguments[0]).querySelectorAll('p')[19].getBoundingClientRect().bottom < #{reader_surface}.getBoundingClientRect().top", dom_id(workspace(:messages, :workspace_answer), :content))

        stream_answer(reader_answer(120))

        assert_reader_following true
        assert_no_button "Latest message"
        assert_operator reader_gap, :<=, 1
        assert_no_enqueued_jobs only: ChatResponseJob
      end
    end

    test "native anchoring without reader movement stays paused during growth at #{width}x#{height}" do
      visit_reader(width, height)
      prepare_native_anchor_fixture(gap: 160)
      page.execute_script(<<~JS, dom_id(workspace(:messages, :workspace_answer), :content))
        const surface = #{reader_surface}
        surface.scrollTop = surface.scrollHeight - surface.clientHeight - 160
        // Even in the short reading zone, pause on a real answer paragraph.
        const paragraph = document.getElementById(arguments[0]).querySelector('p:last-child')
        surface.scrollTop -= Math.max(0, surface.getBoundingClientRect().top + 24 - paragraph.getBoundingClientRect().top)
        surface.dispatchEvent(new Event('scroll'))
      JS
      assert_reader_following false
      anchor = reader_anchor
      page.execute_script(<<~JS, dom_id(workspace(:messages, :workspace_answer), :content))
        const surface = #{reader_surface}, content = document.getElementById(arguments[0])
        const root = document.querySelector('.n-chat-workspace--saved')
        window.readerNativeGrowth = { heightBefore: surface.scrollHeight, topBefore: surface.scrollTop }
        const observer = new MutationObserver(() => {
          observer.disconnect()
          const evidence = window.readerNativeGrowth
          evidence.heightAfter = surface.scrollHeight
          evidence.nativeTop = surface.scrollTop
          const anchor = window.readerNativeAnchorFixture
          evidence.nativeAnchor = anchor && { sameNode: anchor === surface.querySelector('[data-reader-native-anchor-fixture]'),
            connected: anchor.isConnected, bounds: anchor.getBoundingClientRect().toJSON(), overflowAnchor: getComputedStyle(anchor).overflowAnchor }
          // Deliver scroll at the browser's anchored position, without moving it.
          surface.dispatchEvent(new Event('scroll'))
          evidence.followingAfterScroll = root.dataset.readerFollowing
        })
        observer.observe(content.parentElement, { childList: true })
      JS

      native_anchor_diagnostic("native-growth-before-#{width}x#{height}")
      stream_answer(reader_answer(100))

      evidence = page.evaluate_script("window.readerNativeGrowth")
      puts "Reader native growth #{width}x#{height}: #{evidence.to_json}"
      if (native_anchor = evidence.fetch("nativeAnchor"))
        assert native_anchor.fetch("sameNode") && native_anchor.fetch("connected"), evidence.to_json
        assert_operator evidence.fetch("nativeTop"), :>, evidence.fetch("topBefore")
      end
      assert_operator evidence.fetch("heightAfter"), :>, evidence.fetch("heightBefore")
      if width <= 639
        assert_operator evidence.fetch("nativeTop"), :>, evidence.fetch("topBefore")
      else
        # Which surviving element the browser anchors varies with available height.
        assert_operator evidence.fetch("nativeTop"), :>=, evidence.fetch("topBefore")
      end
      assert_equal "false", evidence.fetch("followingAfterScroll")
      assert_reader_following false
      assert_reader_anchor anchor
      assert_button "Latest message"
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    readings = %w[earlier recent]
    readings << "previous" if width <= 639 || height <= 700
    readings.each do |reading|
      test "reader scroll wins after actual stream height growth at #{width}x#{height} while reading #{reading}" do
        visit_reader(width, height)
        prepare_native_anchor_fixture
        page.execute_script(<<~JS, dom_id(workspace(:messages, :workspace_answer), :content), reading)
          const surface = #{reader_surface}, content = document.getElementById(arguments[0])
          const reading = arguments[1]
          const root = document.querySelector('.n-chat-workspace--saved')
          window.readerGrowthRace = { heightBefore: surface.scrollHeight, topBefore: surface.scrollTop }
          const observer = new MutationObserver(() => {
            observer.disconnect()
            // Mutation observers run before the reader's queued reconciliation RAF.
            const evidence = window.readerGrowthRace
            evidence.heightAfter = surface.scrollHeight
            evidence.topBeforeInput = surface.scrollTop
            const anchor = window.readerNativeAnchorFixture
            evidence.nativeAnchor = anchor && { sameNode: anchor === surface.querySelector('[data-reader-native-anchor-fixture]'),
              connected: anchor.isConnected, bounds: anchor.getBoundingClientRect().toJSON(), overflowAnchor: getComputedStyle(anchor).overflowAnchor }
            evidence.contentBottomBeforeInput = document.getElementById(content.id).getBoundingClientRect().bottom
            evidence.surfaceBottom = surface.getBoundingClientRect().bottom
            evidence.followingBeforeInput = root.dataset.readerFollowing
            if (reading === 'earlier') {
              const paragraph = document.getElementById(content.id).querySelectorAll('p')[19]
              surface.scrollTop += paragraph.getBoundingClientRect().top - surface.getBoundingClientRect().top - 24
             } else if (reading === 'recent') {
              const paragraph = document.getElementById(content.id).querySelector('p:last-child')
              surface.scrollTop -= Math.max(160, surface.getBoundingClientRect().top + 24 - paragraph.getBoundingClientRect().top)
            } else {
              surface.scrollTop = evidence.topBefore
            }
            evidence.topAfterInput = surface.scrollTop
            evidence.contentBottomAfterInput = document.getElementById(content.id).getBoundingClientRect().bottom
            const top = surface.getBoundingClientRect().top
            const paragraphs = [...document.querySelectorAll('.n-chat-transcript .ai-response-content p')]
            const visible = paragraphs.find(element => element.getBoundingClientRect().bottom > top)
            evidence.anchor = { text: visible.textContent, offset: visible.getBoundingClientRect().top - top }
            surface.dispatchEvent(new Event('scroll'))
            evidence.followingAfterInput = root.dataset.readerFollowing
          })
          observer.observe(content.parentElement, { childList: true })
        JS

        native_anchor_diagnostic("growth-race-before-#{width}x#{height}-#{reading}")
        stream_answer(reader_answer(100))

        evidence = page.evaluate_script("window.readerGrowthRace")
        puts "Reader growth race #{width}x#{height} #{reading}: #{evidence.to_json}"
        if (native_anchor = evidence.fetch("nativeAnchor"))
          assert native_anchor.fetch("sameNode") && native_anchor.fetch("connected"), evidence.to_json
          assert_operator evidence.fetch("topBeforeInput"), :>, evidence.fetch("topBefore")
        end
        assert_operator evidence.fetch("heightAfter"), :>, evidence.fetch("heightBefore")
        assert_operator evidence.fetch("topAfterInput"), :<, evidence.fetch("topBeforeInput")
        if reading == "previous"
          # Returning to the old numerical scrollTop is still an upward move
          # after native anchoring, not an unchanged reader position.
          assert_equal evidence.fetch("topBefore"), evidence.fetch("topAfterInput")
        elsif reading == "recent" && (width <= 639 || height <= 700)
          # The wheel-sized upward move is smaller than native downward anchoring.
          assert_operator evidence.fetch("topAfterInput"), :>, evidence.fetch("topBefore")
        else
          assert_operator evidence.fetch("topAfterInput"), :<, evidence.fetch("topBefore")
        end
        assert_equal "true", evidence.fetch("followingBeforeInput")
        assert_equal "false", evidence.fetch("followingAfterInput")
        assert_reader_following false
        assert_reader_anchor evidence.fetch("anchor")
        if evidence.fetch("contentBottomAfterInput") > evidence.fetch("surfaceBottom")
          assert_button "Latest message"
        else
          assert_no_button "Latest message"
        end

        stream_answer(reader_answer(120))

        assert_reader_following false
        assert_reader_anchor evidence.fetch("anchor")
        assert_operator page.evaluate_script("document.getElementById(arguments[0]).getBoundingClientRect().bottom - #{reader_surface}.getBoundingClientRect().bottom", dom_id(workspace(:messages, :workspace_answer), :content)), :>, 0
        assert_button "Latest message"
        assert_no_enqueued_jobs only: ChatResponseJob
      end
    end
  end

  test "paused paragraph survives compact header height changes and viewport reflow" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor
    chat_measurement("kind" => "orbite-intermediate-initial-focus", "measurement" => page.evaluate_script(<<~JS))
      ({ active: { id: document.activeElement.id, tag: document.activeElement.tagName },
        autofocus: [...document.querySelectorAll('[autofocus]')].map(node => ({ tag: node.tagName, id: node.id,
          visible: node.checkVisibility(), inHistory: !!node.closest('#chat-history') })),
        historyOpen: document.querySelector('#chat-history').open })
    JS
    page.execute_script(<<~JS)
      window.compactReaderFocus = document.activeElement
      window.compactReaderFocusBefore = { id: document.activeElement.id, tag: document.activeElement.tagName,
        html: document.activeElement.outerHTML.slice(0, 500) }
    JS

    [ true, false ].each do |open|
      # Geometry stimulus only: native disclosure keyboard behavior is covered
      # independently, without scrolling this paused paragraph to its summary.
      before_geometry = task3_reading_geometry
      page.execute_script("document.querySelector('#chat-usage-details').open = arguments[0]", open)
      settle_workspace_layout
      geometry = { before: before_geometry, after: task3_reading_geometry }
      chat_measurement("kind" => "task3-usage-geometry-diagnostic", "sample" => geometry)
      puts "Task3 Usage geometry: #{geometry.to_json}"
      assert_reader_following false
      assert_reader_anchor anchor
      assert_no_button "Latest message"
      assert page.evaluate_script("window.compactReaderFocus === document.activeElement")
    end
    [ [ 375, 812 ], [ 1400, 1000 ] ].each do |width, height|
      set_reader_viewport(width, height)
      settle_workspace_layout
      assert_equal "application-scroll", page.evaluate_script("#{reader_surface}.id")
      assert_reader_following false
      assert_reader_anchor anchor
      assert_no_button "Latest message"
      assert page.evaluate_script("window.compactReaderFocus === document.activeElement")
    end

    stream_answer(reader_answer(100))
    assert_button "Latest message"
    assert_reader_following false
    assert_reader_anchor anchor
    assert page.evaluate_script("window.compactReaderFocus === document.activeElement")
    # Persist the same content without broadcasting a second update; refresh
    # must morph the real GET rather than revert to the shorter fixture answer.
    workspace(:messages, :workspace_answer).update_columns(content: reader_answer(100))
    refresh_workspace
    assert_reader_following false
    assert_reader_anchor anchor
    assert_button "Latest message"
    chat_measurement("kind" => "compact-header-reader-refresh-focus", "measurement" => page.evaluate_script(<<~JS))
      ({ before: window.compactReaderFocusBefore, after: { id: document.activeElement.id, tag: document.activeElement.tagName,
        html: document.activeElement.outerHTML.slice(0, 500) }, sameObject: window.compactReaderFocus === document.activeElement,
        originalConnected: window.compactReaderFocus.isConnected })
    JS
    # Turbo may replace the editor node while retaining its exact focused ID.
    # The unchanged-node identity assertions above still apply to geometry/streams.
    focused_id = page.evaluate_script("window.compactReaderFocusBefore.id")
    assert_equal "message_content-content", focused_id
    assert_selector "##{focused_id}:focus"
    chat_measurement("kind" => "compact-header-reader", "anchor" => anchor, "currentAnchor" => reader_anchor,
      "usageProgrammaticGeometryOnly" => true, "nativeZoomVerified" => false)
    chat_screenshot "compact-header-reader-reflow"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "paused reader keeps its paragraph through surface changes and editor reflow" do
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor

    set_reader_viewport(375, 812)
    settle_workspace_layout
    assert_reader_following false
    assert_reader_anchor anchor
    assert_equal "application-scroll", page.evaluate_script("#{reader_surface}.id")
    page.execute_script("document.querySelector('lexxy-editor').value = '<div>Long draft</div>'.repeat(35)")
    settle_workspace_layout
    assert_reader_anchor anchor
    stream_answer(reader_answer(100))
    assert_button "Latest message"
    assert_reader_anchor anchor

    set_reader_viewport(1400, 1000)
    settle_workspace_layout
    assert_reader_following false
    assert_reader_anchor anchor
    assert_equal "application-scroll", page.evaluate_script("#{reader_surface}.id")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "other tab messages unrelated streams and blocked source submissions do not resume" do
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor
    stream_html(%(<turbo-stream action="update" target="chat-account-help"><template>Account help updated</template></turbo-stream>))
    assert_selector "#chat-account-help", text: "Account help updated"
    assert_no_button "Latest message"
    answer = workspace(:messages, :workspace_answer)
    stream_html(%(<turbo-stream action="update" target="#{dom_id(answer, :response_summary)}"><template>Response details updated</template></turbo-stream>))
    assert_selector "##{dom_id(answer, :response_summary)}", text: "Response details updated", visible: :all
    settle_workspace_layout
    assert_no_button "Latest message"
    stream_html(%(<turbo-stream action="update" target="#{dom_id(answer, :reasoning_content)}"><template>Reasoning metadata updated</template></turbo-stream>))
    assert_selector "##{dom_id(answer, :reasoning_content)}", text: "Reasoning metadata updated", visible: :all
    settle_workspace_layout
    assert_no_button "Latest message"

    incoming = @chat.messages.create!(role: "user", content: "A question from another tab")
    html = ApplicationController.render(partial: "messages/message", locals: { message: incoming })
    stream_html(%(<turbo-stream action="append" target="#{dom_id(@chat, :messages)}"><template>#{html}</template></turbo-stream>))
    assert_selector "##{dom_id(incoming, :messages)}", text: "A question from another tab", visible: :all
    assert_button "Latest message"
    assert_reader_following false
    assert_reader_anchor anchor

    hold_source_registration
    page.execute_script(<<~JS)
      document.querySelector('lexxy-editor').dispatchEvent(new CustomEvent('lexxy:insert-link', {
        detail: { url: 'https://second.example/reference' }, bubbles: true
      }))
    JS
    assert_button "Send", disabled: true, enable_aria_label: true
    pause_reader
    counts = [ Chat.count, Message.count ]
    page.execute_script("document.querySelector('form[data-chat-followup]').requestSubmit()")
    settle_workspace_layout
    assert_reader_following false
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
    page.execute_script("window.releaseWorkspaceSource()")
    assert_button "Send", disabled: false, enable_aria_label: true
  end

  test "Stop and Tools form outcomes never resume a paused reader" do
    @chat.start_generation!
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor
    page.execute_script(<<~JS)
      const form = document.querySelector('#mcp-selector-modal form')
      form.dispatchEvent(new CustomEvent('turbo:submit-start', { bubbles: true }))
      form.dispatchEvent(new CustomEvent('turbo:submit-end', { bubbles: true, detail: { success: true } }))
    JS
    assert_reader_following false
    page.execute_script("document.querySelector('button[aria-label=\"Stop generating\"]').click()")
    assert_button "Send", disabled: false, enable_aria_label: true
    settle_workspace_layout
    assert_reader_following false
    assert_reader_anchor anchor
    assert_not @chat.reload.generating?
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "following positions increments instantly including reduced motion" do
    [ false, true ].each do |reduced|
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: reduced ? "reduce" : "no-preference" } ])
      visit_reader(1400, 1000)
      page.execute_script(<<~JS)
        window.readerSmoothCalls = []
        for (const name of ['scroll', 'scrollTo', 'scrollIntoView']) {
          const original = Element.prototype[name]
          Element.prototype[name] = function(...args) {
            if (args.some(arg => arg?.behavior === 'smooth')) window.readerSmoothCalls.push(name)
            return original.apply(this, args)
          }
        }
      JS
      [ 90, 100, 110 ].each do |count|
        stream_answer(reader_answer(count))
        assert_reader_following true
        assert_operator reader_gap, :<=, 1
      end
      assert_equal [], page.evaluate_script("window.readerSmoothCalls")
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "a replaced explicit child surface preserves the same reader root and paused paragraph" do
    visit_reader(1400, 1000)
    assert_selector "[data-application-scroll]"
    pause_reader
    anchor = reader_anchor
    page.execute_script(<<~JS)
      const oldSurface = document.querySelector('[data-application-scroll]'), top = oldSurface.scrollTop
      window.previousApplicationSurface = oldSurface
      window.preservedReaderRoot = document.querySelector('.n-chat-workspace--saved')
      const surface = oldSurface.cloneNode(false)
      oldSurface.replaceWith(surface)
      surface.append(...oldSurface.childNodes)
      surface.scrollTop = top
    JS
    settle_reader_animations

    puts "Reader explicit surface retarget: #{page.evaluate_script("({ state: window.preservedReaderRoot.chatReaderState, top: document.querySelector('[data-application-scroll]').scrollTop, oldConnected: window.previousApplicationSurface.isConnected, animations: window.preservedReaderRoot.getAnimations({ subtree: true }).length })").to_json}"

    assert page.evaluate_script("window.preservedReaderRoot === document.querySelector('.n-chat-workspace--saved')")
    assert_not page.evaluate_script("window.previousApplicationSurface.isConnected")
    assert_reader_following false
    assert_reader_anchor anchor
    stream_answer(reader_answer(100))
    assert_button "Latest message"
    assert_reader_anchor anchor
    click_button "Latest message"
    assert_reader_following true
    assert_operator reader_gap, :<=, 80
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "a replaced transcript retargets the reader without losing its anchor or pending evidence" do
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor
    answer = workspace(:messages, :workspace_answer)
    answer.update_columns(content: reader_answer(100))
    html = ApplicationController.render(partial: "chats/transcript", locals: { chat: @chat })

    stream_html(%(<turbo-stream action="replace" targets=".n-chat-transcript"><template><section class="n-chat-transcript" data-scroll-target="viewport">#{html}</section></template></turbo-stream>))

    assert_selector "##{dom_id(answer, :content)} p:last-child", text: "Paragraph 100:", visible: :all
    settle_reader_animations
    assert_button "Latest message"
    assert_reader_following false
    assert_reader_anchor anchor
    click_button "Latest message"
    assert_reader_following true
    assert_operator reader_gap, :<=, 80
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "reconnecting the same saved root preserves intent and does not duplicate ownership" do
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor
    page.execute_script(<<~JS)
      const root = document.querySelector('.n-chat-workspace--saved')
      root.dataset.controller = root.dataset.controller.replace(' scroll', '')
    JS
    settle_workspace_layout
    page.execute_script("document.querySelector('.n-chat-workspace--saved').dataset.controller += ' scroll'")
    settle_workspace_layout

    assert_reader_following false
    assert_reader_anchor anchor
    stream_answer(reader_answer(100))
    assert_button "Latest message"
    assert_reader_anchor anchor
    click_button "Latest message"
    assert_reader_following true
    assert_operator reader_gap, :<=, 80
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "reader scroll wins over an already scheduled incremental update" do
    visit_reader(1400, 1000)
    page.execute_script(<<~JS, dom_id(workspace(:messages, :workspace_answer), :content))
      const surface = #{reader_surface}, height = surface.scrollHeight
      const content = document.getElementById(arguments[0])
      const observer = new MutationObserver(() => {
        observer.disconnect()
        window.readerUpdateHeightStable = surface.scrollHeight === height
        const paragraph = document.getElementById(content.id).querySelectorAll('p')[19]
        surface.scrollTop += paragraph.getBoundingClientRect().top - surface.getBoundingClientRect().top - 24
        surface.dispatchEvent(new Event('scroll'))
      })
      observer.observe(content.parentElement, { childList: true })
    JS

    stream_answer(reader_answer(80) + " More.")

    assert page.evaluate_script("window.readerUpdateHeightStable"), "This case must isolate user scrolling, not layout resizing"
    assert_reader_following false
    anchor = reader_anchor
    stream_answer(reader_answer(100))
    assert_button "Latest message"
    assert_reader_anchor anchor
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  [ [ 1400, 1000 ], [ 375, 812 ], [ 812, 375 ] ].each do |width, height|
    [ [ "render", "turbo:render" ], [ "initialize", "lexxy:initialize" ] ].each do |name, event|
      %w[pause resume].each do |intent|
        [ false, true ].each do |growth|
          test "#{name} pending reader #{intent} at #{width}x#{height} with #{growth ? 'growth' : 'stable geometry'}" do
            visit_reader(width, height)
            if intent == "resume"
              pause_reader
              stream_answer(reader_answer(90))
              assert_button "Latest message"
            end

            reader_move_after_lifecycle(event, intent, growth: growth)
            stream_answer(reader_answer(100)) if growth
            settle_workspace_layout

            evidence = page.evaluate_script("window.readerLifecycle")
            puts "Reader lifecycle #{name} #{intent} #{width}x#{height} growth #{growth}: #{evidence.to_json}"
            if growth
              assert_operator evidence.fetch("heightAfterUpdate"), :>, evidence.fetch("heightBefore")
            else
              assert_equal evidence.fetch("heightBefore"), evidence.fetch("heightAfterUpdate")
            end
            assert_equal evidence.fetch("heightBeforeEvent"), evidence.fetch("heightAfterEvent")
            assert_equal evidence.fetch("clientBeforeEvent"), evidence.fetch("clientAfterEvent")
            assert_equal intent == "pause" ? "true" : "false", evidence.fetch("followingBeforeInput")
            assert_equal intent == "pause" ? "false" : "true", evidence.fetch("followingAfterInput")
            assert_reader_following intent == "resume"
            if intent == "pause"
              assert_reader_anchor evidence.fetch("anchor")
            else
              assert_equal 80, evidence.fetch("requestedGap")
              assert evidence.fetch("latestHiddenAfterInput")
              assert_no_button "Latest message"
              assert_operator reader_gap, :<=, 1
            end

            stream_answer(reader_answer(120))

            assert_reader_following intent == "resume"
            if intent == "pause"
              assert_reader_anchor evidence.fetch("anchor")
              assert_button "Latest message"
            else
              assert_no_button "Latest message"
              assert_operator reader_gap, :<=, 1
            end
            assert_no_enqueued_jobs only: ChatResponseJob
          end
        end
      end
    end
  end

  test "long user message preserves its visible paragraph through desktop narrow reflow" do
    message = workspace(:messages, :workspace_question)
    message.update_columns(content: (1..100).map { |index| "User paragraph #{index}: compare the supporting evidence carefully and preserve the reader's place across different screen widths." }.join("\n\n"))
    visit_reader(1400, 1000)
    selector = "##{dom_id(message, :messages)} .n-chat-user-body p"
    assert_selector selector, count: 100, visible: :all
    page.execute_script(<<~JS, selector)
      const surface = #{reader_surface}, paragraph = document.querySelectorAll(arguments[0])[19]
      surface.scrollTop += paragraph.getBoundingClientRect().top - surface.getBoundingClientRect().top - 24
      surface.dispatchEvent(new Event('scroll'))
    JS
    assert_reader_following false
    anchor = user_paragraph_anchor(selector)

    set_reader_viewport(375, 812)
    settle_workspace_layout

    assert_reader_following false
    assert_user_paragraph_anchor anchor, selector
    stream_answer(reader_answer(100))
    assert_button "Latest message"
    assert_user_paragraph_anchor anchor, selector

    set_reader_viewport(1400, 1000)
    settle_workspace_layout

    assert_reader_following false
    assert_user_paragraph_anchor anchor, selector
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "reader animation settling includes a pending Turbo message replacement" do
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor
    message = workspace(:messages, :workspace_answer)
    html = ApplicationController.render(partial: "messages/message", locals: { message: message })
    page.execute_script(<<~JS, dom_id(message, :messages))
      window.pendingReaderMessage = document.getElementById(arguments[0])
      document.addEventListener('turbo:before-stream-render', event => {
        const render = event.detail.render
        event.detail.render = async stream => {
          await new Promise(resolve => {
            window.releaseReaderRender = resolve
            document.querySelector('.n-chat-workspace').dataset.readerRenderPending = 'true'
          })
          await render(stream)
        }
      }, { once: true })
    JS
    stream_html(%(<turbo-stream action="replace" target="#{dom_id(message, :messages)}"><template>#{html}</template></turbo-stream>))
    assert_selector ".n-chat-workspace[data-reader-render-pending=true]"
    assert page.evaluate_script("window.pendingReaderMessage.isConnected")
    page.execute_script("requestAnimationFrame(() => requestAnimationFrame(window.releaseReaderRender))")

    settle_reader_animations

    assert_not page.evaluate_script("window.pendingReaderMessage.isConnected"), "Settling must include the pending replacement, not just animations on the old DOM"
    assert_equal 0, page.evaluate_script("document.querySelector('.n-chat-transcript').getAnimations({ subtree: true }).length")
    assert_reader_following false
    assert_reader_anchor anchor
    assert_no_button "Latest message"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "chrome-only message replacement does not advertise new content or move its reader" do
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor
    message = workspace(:messages, :workspace_answer)
    html = ApplicationController.render(partial: "messages/message", locals: { message: message })

    stream_html(%(<turbo-stream action="replace" target="#{dom_id(message, :messages)}"><template>#{html}</template></turbo-stream>))
    settle_reader_animations
    settle_workspace_layout

    assert_reader_following false
    assert_reader_anchor anchor
    assert_no_button "Latest message"
    stream_html(%(<turbo-stream action="update" target="#{dom_id(message, :response_summary)}"><template>Only response metadata changed</template></turbo-stream>))
    assert_selector "##{dom_id(message, :response_summary)}", text: "Only response metadata changed", visible: :all
    settle_workspace_layout
    assert_reader_anchor anchor
    assert_no_button "Latest message"
    stream_answer(reader_answer(100))
    assert_button "Latest message"
    assert_reader_anchor anchor
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  %i[en fr].each do |locale|
    test "live disclosures retain independent states and focus through broadcasts and refresh in #{locale}" do
      set_workspace_language(locale)
      answer = workspace(:messages, :workspace_answer)
      width = Chunk.columns_hash.fetch("embedding").limit
      chunk = insert_picker_chunk(@second, texts(:picker_second_text), "Saved local evidence", [ 1.0 ] + Array.new(width - 1, 0.0))
      answer.update_columns(similar_chunk_ids: [ chunk.id.to_s ])
      visit chat_url(@chat)
      find("#chat-usage-summary").click
      find("##{dom_id(answer, :sources_summary)}").click
      find("##{dom_id(answer, :response_summary)}").click
      page.execute_script("document.getElementById(arguments[0]).focus()", dom_id(answer, :response_summary))
      assert_selector "##{dom_id(answer, :response_summary)}:focus"

      Current.reset
      totals = capture_turbo_stream_broadcasts([ @chat, :token_totals, locale ]) do
        TokenUsage.create!(account: @second, chat_id: @chat.id, kind: :embedding, input_tokens: 1, output_tokens: 0)
      end
      replacement = totals.find { |stream| stream["target"] == dom_id(@chat, :token_totals) }
      assert replacement, "Expected the actual localized token totals broadcast"
      stream_html(replacement.to_html)
      assert_selector "#chat-usage-details[open] [data-chat-total-input]", text: "126"
      assert_selector "##{dom_id(answer, :response_summary)}:focus"

      deliver_answer_update(answer, locale)
      assert_live_disclosures answer, sources: true, reasoning: false
      refresh_workspace
      assert_live_disclosures answer, sources: true, reasoning: false

      find("##{dom_id(answer, :sources_summary)}").click
      find("##{dom_id(answer, :reasoning_summary)}").click
      find("##{dom_id(answer, :response_summary)}").click
      find("##{dom_id(answer, :response_summary)}").click
      page.execute_script("document.getElementById(arguments[0]).focus()", dom_id(answer, :response_summary))
      deliver_answer_update(answer, locale)
      refresh_workspace
      assert_live_disclosures answer, sources: false, reasoning: true
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    test "live phases announce changes once and actual finish unlocks the composer in #{locale}" do
      set_workspace_language(locale)
      @chat.messages.assistant.destroy_all
      @chat.start_generation!
      visit chat_url(@chat)
      assert_selector "#thinking_animation", count: 1
      assert_selector "#thinking_animation_content", count: 1
      assert_workspace_status I18n.t("nosia.chat.phases.preparing.title", locale: locale)
      page.execute_script(<<~JS)
        const status = document.querySelector('[data-chat-feedback-target=status]')
        window.workspaceStatus = status
        window.workspaceAnnouncements = []
        window.workspaceStatusObserver = new MutationObserver(() => window.workspaceAnnouncements.push(status.textContent))
        window.workspaceStatusObserver.observe(status, { childList: true, subtree: true, characterData: true })
      JS
      refresh_workspace
      assert_workspace_status I18n.t("nosia.chat.phases.preparing.title", locale: locale)
      assert page.evaluate_script("window.workspaceStatus === document.querySelector('[data-chat-feedback-target=status]')")
      assert_equal [], page.evaluate_script("window.workspaceAnnouncements")
      # Replay each captured server payload once; do not also consume its cable
      # delivery while deliberately stepping through intermediate DOM states.
      page.execute_script("document.querySelectorAll('turbo-cable-stream-source').forEach(source => source.remove())")
      assert_no_selector "turbo-cable-stream-source", visible: :all

      2.times do
        streams = capture_turbo_stream_broadcasts([ @chat, :messages, locale ]) { @chat.broadcast_thinking_phase("searching") }
        stream_html(streams.find { |stream| stream["target"] == "thinking_animation_content" }.to_html)
        assert_workspace_status I18n.t("nosia.chat.phases.searching.title", locale: locale)
      end
      assert_equal [ I18n.t("nosia.chat.phases.searching.title", locale: locale) ], page.evaluate_script("window.workspaceAnnouncements")

      answer = nil
      created = capture_turbo_stream_broadcasts([ @chat, :messages, locale ]) do
        answer = @chat.messages.create!(role: :assistant, content: "", done: false)
      end
      assert created.any? { |stream| stream["action"] == "append" && stream["target"] == dom_id(@chat, :messages) }
      File.write(File.join(chat_evidence_directory, "created-#{locale}.html"), created.map(&:to_html).join)
      stream_html(created.map(&:to_html).join)
      assert_selector "##{dom_id(answer, :messages)}", count: 1
      assert_selector "##{dom_id(answer, :content)}", count: 1
      assert_workspace_status I18n.t("nosia.chat.phases.generating.title", locale: locale)
      3.times do |index|
        streams = capture_turbo_stream_broadcasts([ @chat, :messages, locale ]) { answer.broadcast_streamed_content("## Actual delta #{index}\n\n**Formatted evidence**") }
        stream_html(streams.find { |stream| stream["target"] == dom_id(answer, :content) }.to_html)
        assert_selector "##{dom_id(answer, :content)} h2", text: "Actual delta #{index}"
        assert_selector "##{dom_id(answer, :content)} strong", text: "Formatted evidence"
      end
      answer.update_columns(content: "## Final answer\n\n**Formatted evidence** remains readable.", done: true)
      deliver_answer_update(answer, locale)
      assert_selector "##{dom_id(answer, :content)} h2", text: "Final answer"
      assert_selector "##{dom_id(answer, :messages)}", count: 1
      assert_selector "##{dom_id(answer, :content)}", count: 1
      assert_equal %w[searching generating].map { |phase| I18n.t("nosia.chat.phases.#{phase}.title", locale: locale) }, page.evaluate_script("window.workspaceAnnouncements")
      assert_no_selector ".ai-response-content[aria-live]", visible: :all

      Current.reset
      streams = capture_turbo_stream_broadcasts([ @chat, :messages, locale ]) { @chat.finish_generation! }
      unlock = streams.find { |stream| stream["target"] == "#{dom_id(@chat)}_message_form" }
      assert_equal "replace", unlock["action"]
      stream_html(unlock.to_html)
      assert_button I18n.t("nosia.chat.send", locale: locale), disabled: false, enable_aria_label: true
      assert_workspace_status I18n.t("nosia.chat_workspace.completed", locale: locale)
      assert page.evaluate_script("window.workspaceStatus === document.querySelector('[data-chat-feedback-target=status]')")
      assert_equal 3, page.evaluate_script("window.workspaceAnnouncements.length")
      page.execute_script("document.querySelector('.n-chat-workspace').dataset.controller = document.querySelector('.n-chat-workspace').dataset.controller.replace(' chat-feedback', '')")
      settle_workspace_layout
      page.execute_script("document.querySelector('.n-chat-workspace').dataset.controller += ' chat-feedback'")
      settle_workspace_layout
      assert_equal 3, page.evaluate_script("window.workspaceAnnouncements.length")
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    test "remote Stop unlock announces stopped before refresh and a fresh turn completes in #{locale}" do
      set_workspace_language(locale)
      @chat.messages.assistant.destroy_all
      @chat.start_generation!
      visit chat_url(@chat)
      assert_workspace_status I18n.t("nosia.chat.phases.preparing.title", locale: locale)
      assert_selector ".n-chat-workspace[data-chat-generation-stopped=false]"
      # Replay the actual worker payloads once, without also receiving their Cable copy.
      page.execute_script("document.querySelectorAll('turbo-cable-stream-source').forEach(source => source.remove())")
      assert_no_selector "turbo-cable-stream-source", visible: :all
      observe_workspace_announcements

      Current.reset
      worker = Chat.find(@chat.id)
      web = Chat.find(@chat.id)
      assert_not_same worker, web
      web.stop_generation!
      refute_predicate worker, :generation_stopped?, "The already-loaded worker must still hold the pre-Stop value"
      assert_predicate Chat.find(@chat.id), :generation_stopped?
      streams = capture_turbo_stream_broadcasts([ @chat, :messages, locale ]) { worker.finish_generation! }
      refute_predicate worker, :generation_stopped?, "Presentation must not reload the worker"
      assert_equal %w[replace remove refresh], streams.map { |stream| stream["action"] }
      unlock, removal, refresh = streams
      assert_equal "#{dom_id(@chat)}_message_form", unlock["target"]
      File.write(File.join(chat_evidence_directory, "remote-stop-#{locale}.html"), streams.map(&:to_html).join)
      stream_html(unlock.to_html)

      assert_button I18n.t("nosia.chat.send", locale: locale), disabled: false, enable_aria_label: true
      assert_selector ".n-chat-workspace[data-chat-generation-stopped=false]"
      assert_workspace_status I18n.t("nosia.chat_workspace.stopped", locale: locale)
      assert_no_selector "[data-chat-feedback-target=status]", text: I18n.t("nosia.chat_workspace.completed", locale: locale), visible: :all
      assert_equal [ I18n.t("nosia.chat_workspace.stopped", locale: locale) ], page.evaluate_script("window.workspaceAnnouncements")

      stream_html(removal.to_html)
      assert_no_selector "#thinking_animation", visible: :all
      stream_html(refresh.to_html)
      assert_selector ".n-chat-workspace[data-chat-generation-stopped=true]"
      assert_workspace_status I18n.t("nosia.chat_workspace.stopped", locale: locale)
      reconnect_workspace_feedback
      assert_workspace_status I18n.t("nosia.chat_workspace.stopped", locale: locale)
      assert page.evaluate_script("window.workspaceStatus === document.querySelector('[data-chat-feedback-target=status]')")
      assert_equal [ I18n.t("nosia.chat_workspace.stopped", locale: locale) ], page.evaluate_script("window.workspaceAnnouncements")
      assert_no_enqueued_jobs only: ChatResponseJob

      # The real morph restores subscriptions. Detach them again before replaying
      # the next turn's captured broadcasts, rather than mixing two deliveries.
      assert_selector "turbo-cable-stream-source", visible: :all
      page.execute_script("document.querySelectorAll('turbo-cable-stream-source').forEach(source => source.remove())")
      assert_no_selector "turbo-cable-stream-source", visible: :all
      find("lexxy-editor .lexxy-editor__content").send_keys("A fresh follow-up")
      fresh_turn = capture_turbo_stream_broadcasts([ @chat, :messages, locale ]) do
        assert_enqueued_jobs 1, only: ChatResponseJob do
          click_button I18n.t("nosia.chat.send", locale: locale), enable_aria_label: true
          assert_selector "form[data-chat-followup][data-generation-busy=true]"
        end
      end
      assert fresh_turn.any? { |stream| stream["action"] == "append" && stream["target"] == dom_id(@chat, :messages) }
      fresh_turn.each { |stream| stream_html(stream.to_html) }
      refute_predicate @chat.reload, :generation_stopped?
      assert_workspace_status I18n.t("nosia.chat.phases.preparing.title", locale: locale)
      assert_selector ".n-chat-workspace[data-chat-generation-stopped=true]"
      assert_selector "form[data-chat-followup][data-generation-busy=true][data-generation-stopped=false]"
      Current.reset
      completion = capture_turbo_stream_broadcasts([ @chat, :messages, locale ]) { @chat.finish_generation! }
      assert_equal %w[replace remove refresh], completion.map { |stream| stream["action"] }
      File.write(File.join(chat_evidence_directory, "fresh-completion-#{locale}.html"), completion.map(&:to_html).join)
      stream_html(completion.first.to_html)
      assert_button I18n.t("nosia.chat.send", locale: locale), disabled: false, enable_aria_label: true
      assert_workspace_status I18n.t("nosia.chat_workspace.completed", locale: locale)
      completion.drop(1).each { |stream| stream_html(stream.to_html) }
      assert_selector ".n-chat-workspace[data-chat-generation-stopped=false]"
      reconnect_workspace_feedback
      assert_workspace_status I18n.t("nosia.chat_workspace.completed", locale: locale)
      assert_equal [ I18n.t("nosia.chat_workspace.stopped", locale: locale), I18n.t("nosia.chat.phases.preparing.title", locale: locale),
        I18n.t("nosia.chat_workspace.completed", locale: locale) ], page.evaluate_script("window.workspaceAnnouncements")
    end

    test "live stopped feedback is truthful without an assistant answer in #{locale}" do
      set_workspace_language(locale)
      @chat.messages.assistant.destroy_all
      @chat.start_generation!
      visit chat_url(@chat)
      assert_workspace_status I18n.t("nosia.chat.phases.preparing.title", locale: locale)

      click_button I18n.t("nosia.chat.stop", locale: locale), enable_aria_label: true

      assert_button I18n.t("nosia.chat.send", locale: locale), disabled: false, enable_aria_label: true
      assert_workspace_status(locale == :fr ? "Génération arrêtée." : "Generation stopped.")
      assert_predicate @chat.reload, :generation_stopped?
      assert_equal 0, @chat.messages.assistant.count
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "live disclosure ownership never competes with dialogs or leaks to another conversation" do
    set_reader_viewport(1024, 1000)
    answer = workspace(:messages, :workspace_answer)
    visit chat_url(@chat)
    find("#chat-usage-summary").click
    find("##{dom_id(answer, :response_summary)}").click
    click_button "History"
    assert_native_dialog "chat-history"
    page.execute_script(<<~JS)
      window.orbiteRefreshTrace = []
      const record = event => {
        const panel = document.querySelector('#chat-history'), root = document.querySelector('.n-chat-workspace--saved')
        window.orbiteRefreshTrace.push({ event, open: panel.open, modal: panel.matches(':modal'),
          active: { id: document.activeElement.id, tag: document.activeElement.tagName },
          historyInsideChat: root.contains(panel), oldDisclosureDialogFound: !!root.querySelector('dialog.n-chat-dialog[open]') })
      }
      record('before-refresh')
      for (const event of ['turbo:before-cache', 'turbo:before-render', 'turbo:render']) document.addEventListener(event, () => record(event))
    JS
    refresh_workspace
    chat_measurement("kind" => "orbite-intermediate-history-refresh", "trace" => page.evaluate_script("window.orbiteRefreshTrace"))
    assert_native_dialog "chat-history"
    assert_dialog_focus "chat-history"
    deliver_answer_update(answer, :en)
    assert_dialog_focus "chat-history"
    within("#chat-history") { click_button "Close" }
    assert_selector "#workspace-history-trigger:focus"

    first_chat = workspace(:chats, :workspace_first_chat)
    click_button "History"
    within("[data-history-chat='#{first_chat.id}']") { click_link "First account question" }
    assert_current_path chat_path(first_chat)
    assert_no_selector "#chat-usage-details[open]", visible: :all
    assert_no_selector "dialog[open]", visible: :all
    assert_selector "[data-chat-feedback-target=status]", text: "", visible: :all
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "live disclosures do not steal intentional focus or resurrect deleted answer focus" do
    set_reader_viewport(1024, 1000)
    answer = workspace(:messages, :workspace_answer)
    width = Chunk.columns_hash.fetch("embedding").limit
    chunk = insert_picker_chunk(@second, texts(:picker_second_text), "Saved local evidence", [ 1.0 ] + Array.new(width - 1, 0.0))
    answer.update_columns(similar_chunk_ids: [ chunk.id.to_s ])
    visit chat_url(@chat)
    find("##{dom_id(answer, :response_summary)}").click
    find("##{dom_id(answer, :sources_summary)}").click
    page.execute_script(<<~JS, dom_id(answer, :search_content))
      document.getElementById(arguments[0]).querySelector('a').focus()
      document.addEventListener('turbo:before-stream-render', event => {
        const render = event.detail.render
        event.detail.render = stream => {
          render(stream)
          document.querySelector('button[aria-label=Send]').focus({ preventScroll: true })
        }
      }, { once: true })
    JS
    deliver_answer_update(answer, :en)
    assert_selector "button[aria-label=Send]:focus"
    assert_selector "##{dom_id(answer, :response_details)}[open]"

    page.execute_script("document.getElementById(arguments[0]).focus()", dom_id(answer, :response_summary))
    stream_html(%(<turbo-stream action="remove" target="#{dom_id(answer, :messages)}"></turbo-stream>))
    assert_no_selector "##{dom_id(answer, :messages)}", visible: :all
    find("#workspace-history-trigger").click
    assert_native_dialog "chat-history"
    stream_html(%(<turbo-stream action="update" target="chat-account-help"><template>Unrelated update</template></turbo-stream>))
    assert_dialog_focus "chat-history"
    within("#chat-history") { click_button "Close" }
    assert_selector "#workspace-history-trigger:focus"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  # The approved Keep Turbo decision accepts only its native ID-restoration race.
  # Assert the native caller explicitly; separate ID-less tests protect our restorer.
  [ [ "send", false ], [ "send", true ], [ "removed", true ], [ "modal", true ], [ "outside", true ], [ "early", true ], [ "early_removed", true ] ].each do |destination, asynchronous|
    test "standard Turbo #{destination == 'modal' ? 'retains modal focus' : 'characterizes native summary restoration'} for #{destination} during #{asynchronous ? 'async' : 'sync'} rendering" do
      set_reader_viewport(1024, 1000) if destination == "modal"
      answer = workspace(:messages, :workspace_answer)
      visit chat_url(@chat)
      find("##{dom_id(answer, :response_summary)}").click
      page.execute_script(<<~JS, dom_id(answer, :response_summary), dom_id(answer, :messages), destination, asynchronous)
        const summary = document.getElementById(arguments[0]), target = arguments[1]
        const destination = arguments[2], asynchronous = arguments[3]
        const root = document.querySelector('.n-chat-workspace--saved')
        summary.focus()
        window.focusRaceTimeline = []
        window.focusRaceRenderCalls = 0
        window.nativeFocusRestorations = 0
        const record = name => window.focusRaceTimeline.push({ name, active: document.activeElement.id || document.activeElement.getAttribute('aria-label') || document.activeElement.tagName })
        document.addEventListener('focusin', event => {
          record('focusin')
          const caller = new Error().stack.split('\\n')[2] || ''
          if (event.target.id === summary.id && window.intentionalFocus && caller.includes('/turbo.min-')) window.nativeFocusRestorations++
        }, true)
        document.addEventListener('turbo:before-stream-render', event => {
          if (event.target.getAttribute('target') === target) record('stream-arrived')
        }, true)
        document.addEventListener('turbo:before-stream-render', event => {
          if (event.target.getAttribute('target') !== target) return
          if (destination.startsWith('early')) requestAnimationFrame(() => {
            window.intentionalFocus = root.querySelector('button[aria-label=Send]')
            window.intentionalFocus.focus({ preventScroll: true })
            if (destination === 'early_removed') window.intentionalFocus.remove()
            record('intentional-focus-before-render')
          })
          const render = event.detail.render
          event.detail.render = async stream => {
            window.focusRaceRenderCalls++
            record('render-start')
            const result = render(stream)
            record('body-updated')
            if (destination.startsWith('early')) {
              record('keep-earlier-intent')
            } else if (destination === 'modal') {
              root.querySelector('#workspace-history-trigger').click()
              window.intentionalFocus = document.activeElement
            } else {
              window.intentionalFocus = destination === 'outside' ? document.getElementById('workspace-utilities-trigger') : root.querySelector('button[aria-label=Send]')
              window.intentionalFocus.focus({ preventScroll: true })
              if (destination === 'removed') window.intentionalFocus.remove()
            }
            record('intentional-focus')
            await result
            if (asynchronous) await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
            record('render-resolved')
            root.dataset.focusRaceRendered = 'true'
          }
        }, { capture: true, once: true })
      JS

      deliver_answer_update(answer, :en)
      assert_selector ".n-chat-workspace[data-focus-race-rendered=true]"
      settle_workspace_layout
      puts "Keep Turbo characterization #{destination} async=#{asynchronous}: #{page.evaluate_script('window.focusRaceTimeline').to_json}"
      assert_equal 1, page.evaluate_script("window.focusRaceRenderCalls")
      if destination == "modal"
        assert page.evaluate_script("window.intentionalFocus === document.activeElement"), page.evaluate_script("document.activeElement.outerHTML.slice(0, 300)")
        assert_dialog_focus "chat-history"
      else
        assert_not page.evaluate_script("window.intentionalFocus.isConnected") if destination.include?("removed")
        assert_operator page.evaluate_script("window.nativeFocusRestorations"), :>=, 1, "Expected the accepted Turbo-native focus caller, not application restoration"
        assert_selector "##{dom_id(answer, :response_summary)}:focus"
        if destination.include?("removed")
          stream_html(%(<turbo-stream action="update" target="chat-account-help"><template>Unrelated update</template></turbo-stream>))
          settle_workspace_layout
          assert_selector "##{dom_id(answer, :response_summary)}:focus"
        end
      end
      assert_selector "##{dom_id(answer, :response_details)}[open]", visible: :all
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "standard Turbo keeps a deliberate summary return after its native focus pass" do
    answer = workspace(:messages, :workspace_answer)
    visit chat_url(@chat)
    find("##{dom_id(answer, :response_summary)}").click
    page.execute_script(<<~JS, dom_id(answer, :response_summary), dom_id(answer, :messages))
      const summaryId = arguments[0], messageId = arguments[1]
      document.getElementById(summaryId).focus()
      window.focusReturnTimeline = []
      document.addEventListener('focusin', event => {
        window.focusReturnTimeline.push(document.activeElement.id || document.activeElement.getAttribute('aria-label'))
      }, true)
      document.addEventListener('turbo:before-stream-render', event => {
        if (event.target.getAttribute('target') !== messageId) return
        requestAnimationFrame(() => requestAnimationFrame(() => {
          document.querySelector('button[aria-label=Send]').focus({ preventScroll: true })
          window.focusReturnAway = document.activeElement.getAttribute('aria-label')
          document.getElementById(summaryId).focus({ preventScroll: true })
          window.focusReturnBack = document.activeElement.id
        }))
        const render = event.detail.render
        event.detail.render = async stream => {
          const result = await render(stream)
          document.querySelector('.n-chat-workspace').dataset.focusReturnRendered = 'true'
          return result
        }
      }, { capture: true, once: true })
    JS

    deliver_answer_update(answer, :en)
    assert_selector ".n-chat-workspace[data-focus-return-rendered=true]"
    settle_workspace_layout
    assert_equal "Send", page.evaluate_script("window.focusReturnAway")
    assert_equal dom_id(answer, :response_summary), page.evaluate_script("window.focusReturnBack")
    puts "Away-and-back focus timeline: #{page.evaluate_script('window.focusReturnTimeline').to_json}"
    assert_selector "##{dom_id(answer, :response_summary)}:focus"
    assert_selector "##{dom_id(answer, :response_details)}[open]"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "application disclosure restoration falls back from an ID-less source link to its own summary" do
    answer = workspace(:messages, :workspace_answer)
    width = Chunk.columns_hash.fetch("embedding").limit
    chunk = insert_picker_chunk(@second, texts(:picker_second_text), "Saved local evidence", [ 1.0 ] + Array.new(width - 1, 0.0))
    answer.update_columns(similar_chunk_ids: [ chunk.id.to_s ])
    visit chat_url(@chat)
    find("##{dom_id(answer, :sources_summary)}").click
    page.execute_script(<<~JS, dom_id(answer, :search_content))
      window.sourceFocusLink = document.getElementById(arguments[0]).querySelector('a')
      window.sourceFocusLink.focus()
    JS
    assert_equal "", page.evaluate_script("window.sourceFocusLink.id")
    assert page.evaluate_script("window.sourceFocusLink === document.activeElement")

    deliver_answer_update(answer, :en)

    assert_not page.evaluate_script("window.sourceFocusLink.isConnected"), "The actual answer-body update must replace the focused link"
    assert_selector "##{dom_id(answer, :sources)}[open]"
    assert_selector "##{dom_id(answer, :sources_summary)}:focus"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  %w[outside removed].each do |destination|
    test "application disclosure restoration respects #{destination} intentional focus during an async update" do
      answer = workspace(:messages, :workspace_answer)
      width = Chunk.columns_hash.fetch("embedding").limit
      chunk = insert_picker_chunk(@second, texts(:picker_second_text), "Saved local evidence", [ 1.0 ] + Array.new(width - 1, 0.0))
      answer.update_columns(similar_chunk_ids: [ chunk.id.to_s ])
      visit chat_url(@chat)
      find("##{dom_id(answer, :sources_summary)}").click
      page.execute_script(<<~JS, dom_id(answer, :search_content), dom_id(answer, :messages), destination)
        const link = document.getElementById(arguments[0]).querySelector('a'), target = arguments[1], destination = arguments[2]
        link.focus()
        window.ownerFocusOriginId = link.id
        document.addEventListener('turbo:before-stream-render', event => {
          if (event.target.getAttribute('target') !== target) return
          const render = event.detail.render
          event.detail.render = async stream => {
            const result = render(stream)
            window.ownerIntentionalFocus = destination === 'outside' ? document.getElementById('workspace-utilities-trigger') : document.querySelector('button[aria-label=Send]')
            window.ownerIntentionalFocus.focus({ preventScroll: true })
            if (destination === 'removed') window.ownerIntentionalFocus.remove()
            await result
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
            document.querySelector('.n-chat-workspace').dataset.ownerFocusRendered = 'true'
          }
        }, { capture: true, once: true })
      JS

      deliver_answer_update(answer, :en)
      assert_selector ".n-chat-workspace[data-owner-focus-rendered=true]"
      settle_workspace_layout
      assert_equal "", page.evaluate_script("window.ownerFocusOriginId"), "This isolates application restoration from Turbo's ID-based preservation"
      if destination == "outside"
        assert page.evaluate_script("window.ownerIntentionalFocus === document.activeElement")
      else
        assert_not page.evaluate_script("window.ownerIntentionalFocus.isConnected")
        assert_equal "BODY", page.evaluate_script("document.activeElement.tagName")
        assert_no_selector "##{dom_id(answer, :sources_summary)}:focus"
      end
      assert_selector "##{dom_id(answer, :sources)}[open]"
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "incomplete composer metadata does not invent completion before an authoritative unlock" do
    %w[data-generation-busy data-generation-stopped].each do |attribute|
      @chat.messages.assistant.destroy_all
      @chat.start_generation!
      visit chat_url(@chat)
      preparing = I18n.t("nosia.chat.phases.preparing.title")
      assert_workspace_status preparing
      page.execute_script("document.querySelectorAll('turbo-cable-stream-source').forEach(source => source.remove())")
      assert_no_selector "turbo-cable-stream-source", visible: :all
      observe_workspace_announcements

      Current.reset
      @chat.stop_generation!
      streams = capture_turbo_stream_broadcasts([ @chat, :messages, :en ]) { @chat.finish_generation! }
      unlock = streams.first
      # This guard case deliberately omits metadata; the cross-tab regressions
      # above replay the unmodified server payloads in both locales.
      incomplete = unlock.dup
      incomplete.at_css("template form[data-chat-followup]").remove_attribute(attribute)
      stream_html(incomplete.to_html)
      assert_selector "form[data-chat-followup]:not([#{attribute}])", visible: :all
      settle_workspace_layout
      assert_workspace_status preparing
      assert_equal [], page.evaluate_script("window.workspaceAnnouncements")

      stream_html(unlock.to_html)
      assert_workspace_status I18n.t("nosia.chat_workspace.stopped")
      assert_equal [ I18n.t("nosia.chat_workspace.stopped") ], page.evaluate_script("window.workspaceAnnouncements")
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "live completion after a stopped turn follows the new busy composer rather than stale stop state" do
    @chat.messages.assistant.destroy_all
    @chat.start_generation!
    visit chat_url(@chat)
    click_button "Stop generating", enable_aria_label: true
    assert_workspace_status "Generation stopped."
    find("lexxy-editor .lexxy-editor__content").send_keys("A fresh follow-up")
    assert_enqueued_jobs 1, only: ChatResponseJob do
      click_button "Send", enable_aria_label: true
      assert_selector "form[data-generation-busy=true]"
    end
    refute_predicate @chat.reload, :generation_stopped?
    Current.reset
    streams = capture_turbo_stream_broadcasts([ @chat, :messages, :en ]) { @chat.finish_generation! }
    stream_html(streams.find { |stream| stream["target"] == "#{dom_id(@chat)}_message_form" }.to_html)

    assert_button "Send", disabled: false, enable_aria_label: true
    assert_workspace_status "Response complete."
  end

  %i[en fr].each do |locale|
    test "responsive visual keyboard matrix in #{locale}" do
      @second.update!(name: "CompteDeRecherche" * 12)
      answer = workspace(:messages, :workspace_answer)
      answer.update_columns(content: answer.content + "\n\n```ruby\n" + "long_code_identifier_" * 30 + "\n```")
      set_workspace_language(locale)
      counts = [ Chat.count, Message.count ]
      [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
        [ false, true ].each do |dark|
          { new: new_chat_url(account_id: @second.id), saved: chat_url(@chat) }.each do |entry, url|
            state = "#{locale}-#{entry}-#{dark ? 'dark' : 'light'}-#{width}x#{height}"
            chat_viewport(width, height)
            visit url
            assert_selector "html[lang=#{locale}]"
            assert_selector "lexxy-editor[connected]"
            chat_theme(dark)
            before_bounds_geometry = task3_reading_geometry if height <= 700
            assert_chat_bounds
            if height <= 700
              geometry = { before: before_bounds_geometry, after: task3_reading_geometry }
              chat_measurement("kind" => "task3-landscape-title-diagnostic", "sample" => geometry)
              before, after = geometry.values_at(:before, :after)
              puts "Task3 landscape title geometry: #{ { before: before.fetch('boxes'), after: after.fetch('boxes'), account: after.fetch('account'), actionChildren: after.fetch('actionChildren') }.to_json}"
              [ before, after ].each do |sample|
                assert_equal 0, sample.fetch("documentTop"), sample.to_json
                assert_equal height, sample.fetch("boxes").fetch("html").fetch("height"), sample.to_json
                assert_equal 1, sample.fetch("primaryCount")
                assert_equal 0, sample.fetch("boxes").fetch("main").fetch("top")
              end
              if entry == :new
                reading = after.fetch("boxes").fetch("[data-application-scroll]").fetch("bounds")
                title = after.fetch("boxes").fetch("h1.n-chat-title").fetch("bounds")
                assert_operator title.fetch("top"), :>=, reading.fetch("top"), geometry.to_json
                assert_operator title.fetch("bottom"), :<=, reading.fetch("bottom"), geometry.to_json
                assert after.fetch("titleHit"), geometry.to_json
              end
            end
            chat_contrast "h1.n-chat-title"
            if width >= 1280
              assert_selector "#chat-history[data-inline=true][open]"
              assert_no_selector "#chat-history:modal"
              chat_keyboard_focus "#workspace-history-rail-trigger", reverse: true
              chat_contrast "#workspace-history-rail-trigger", minimum: 3, outline: true
              page.driver.browser.action.send_keys(:enter).perform
              assert_no_selector "#chat-history[open]", visible: :all
              assert_selector "#workspace-history-rail-trigger[aria-expanded=false]:focus"
              page.driver.browser.action.send_keys(:space).perform
              assert_selector "#chat-history[data-inline=true][open]"
              assert_selector "#workspace-history-rail-trigger[aria-expanded=true]:focus"
            else
              chat_keyboard_focus "#workspace-history-trigger", reverse: true
              chat_reachable "#workspace-history-trigger"
              chat_contrast "#workspace-history-trigger", minimum: 3, outline: true
              chat_screenshot "#{state}-header" if width <= 639 || height <= 700
              page.driver.browser.action.send_keys(:enter).perform
              assert_native_dialog "chat-history"
              close = find("#chat-history button", text: I18n.t("nosia.chat_workspace.close", locale: locale), exact_text: true)
              chat_reachable "#chat-history button[data-action='workspace-navigation#close']"
              assert_equal I18n.t("nosia.chat_workspace.close", locale: locale), close.text
              close.click
              assert_no_selector "#chat-history[open]", visible: :all
              assert_selector "#workspace-history-trigger:focus"
            end
            chat_keyboard_focus ".n-composer-send"
            chat_reachable ".n-composer-send"
            chat_contrast ".n-composer-send", minimum: 3, outline: true
            assert_chat_bounds
            chat_screenshot state
          rescue Minitest::Assertion, StandardError
            chat_screenshot "FAILED-#{state}"
            raise
          end
        end
      end
      assert_equal counts, [ Chat.count, Message.count ]
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  [ false, true ].each do |dark|
    test "responsive stateful evidence details and retry in #{dark ? 'dark' : 'light'} theme" do
      @second.update!(name: "CompteDeRecherche" * 12)
      answer = workspace(:messages, :workspace_answer)
      vector = [ 1.0 ] + Array.new(Chunk.columns_hash.fetch("embedding").limit - 1, 0.0)
      chunk = insert_picker_chunk(@second, texts(:picker_second_text), "Local supporting evidence", vector)
      columns = (1..24).map { |index| "Column #{index}" }
      table = [ columns.join(" | "), Array.new(24, "---").join(" | "), columns.map { |column| "Wide evidence #{column}" }.join(" | ") ].join("\n")
      answer.update_columns(similar_chunk_ids: [ chunk.id.to_s ], content: "<think>Evidence was compared carefully.</think>\n\n## Three findings\n\nReadable supporting answer.\n\n#{table}\n\n```ruby\n#{'long_code_identifier_' * 30}\n```")
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      chat_viewport(375, 812)
      visit chat_url(@chat)
      assert_selector "lexxy-editor[connected]"
      chat_theme(dark)
      assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
      assert_chat_bounds
      [ ".n-chat-user-body p", ".n-chat-assistant-name", ".ai-response-content h2", ".n-composer-meta #chat-account-help", ".n-composer-hints", ".n-composer-notice" ].each { |selector| chat_contrast selector }
      assert_selector ".ai-response-content .table-wrapper table"
      overflow = page.evaluate_script(<<~JS)
        (() => {
        const wrapper = document.querySelector('.ai-response-content .table-wrapper')
        const before = document.documentElement.scrollWidth
        wrapper.scrollLeft = 120
        return { left: wrapper.scrollLeft, before, after: document.documentElement.scrollWidth, viewportWidth: innerWidth, overflow: getComputedStyle(wrapper).overflowX }
        })()
      JS
      chat_measurement(overflow.merge("kind" => "wide-table-local-scroll"))
      assert_operator overflow.fetch("left"), :>, 0, overflow.to_json
      assert_equal overflow.fetch("before"), overflow.fetch("after")
      assert_operator overflow.fetch("after"), :<=, overflow.fetch("viewportWidth")

      [ "sources_summary", "response_summary" ].each do |prefix|
        selector = "##{dom_id(answer, prefix)}"
        chat_keyboard_focus selector
        chat_contrast selector, minimum: 3, outline: true
        page.driver.browser.action.send_keys(:enter).perform
      end
      chat_contrast ".n-chat-source p.font-medium"
      chat_contrast "##{dom_id(answer, :response_details)} .n-workspace-help:not([data-estimate-note])"
      chat_contrast "##{dom_id(answer, :response_details)} .n-chat-values > div:first-child dd"
      chat_keyboard_focus "#chat-usage-summary", reverse: true
      chat_contrast "#chat-usage-summary", minimum: 3, outline: true
      page.driver.browser.action.send_keys(:enter).perform
      chat_contrast "[data-chat-total-input]"
      chat_contrast "[data-chat-total-output]"
      chat_contrast ".n-chat-user-body", minimum: 3, border: true
      chat_contrast ".n-chat-assistant-body", minimum: 3, border: true
      chat_contrast ".n-chat-source", minimum: 3, border: true
      chat_reachable "##{dom_id(answer, :sources_summary)}"
      chat_screenshot "details-#{dark ? 'dark' : 'light'}-375x812"

      chat_viewport(812, 375)
      chat_keyboard_focus "#workspace-history-trigger", reverse: true
      page.driver.browser.action.send_keys(:enter).perform
      assert_native_dialog "chat-history"
      chat_dialog_sample "chat-history"
      chat_reachable "#chat-history button[data-action='workspace-navigation#close']"
      chat_screenshot "history-#{dark ? 'dark' : 'light'}-812x375"
      within("#chat-history") { click_button "Close" }
      chat_keyboard_focus ".n-composer-tools-trigger"
      page.driver.browser.action.send_keys(:enter).perform
      assert_native_dialog "mcp-selector-modal"
      chat_dialog_sample "mcp-selector-modal"
      chat_reachable "#mcp-selector-modal button[aria-label=Close]"
      chat_screenshot "tools-#{dark ? 'dark' : 'light'}-812x375"
      counts = [ Chat.count, Message.count ]
      within("#mcp-selector-modal") do
        click_button "Add", exact: true
        assert_button "Remove", exact: true
        assert_equal [ mcp_servers(:picker_second_tool).id ], @chat.chat_mcp_sessions.pluck(:mcp_server_id)
        click_button "Remove", exact: true
        assert_button "Add", exact: true
        assert_empty @chat.chat_mcp_sessions.reload
      end
      assert_equal counts, [ Chat.count, Message.count ]
      assert_no_enqueued_jobs only: ChatResponseJob
      within("#mcp-selector-modal") { find("button[aria-label=Close]").click }
      find("##{dom_id(answer, :reasoning_summary)}").click
      chat_reachable "##{dom_id(answer, :reasoning_summary)}"
      chat_screenshot "reasoning-#{dark ? 'dark' : 'light'}-812x375"

      answer.update_columns(done: false)
      @chat.start_generation!
      visit chat_url(@chat)
      chat_theme(dark)
      assert_button "Stop generating", enable_aria_label: true
      assert_selector "#thinking_animation .n-chat-phase-title", text: "Preparing"
      chat_scroll_to find("#thinking_animation .n-chat-phase-title")
      chat_screenshot "generation-phase-#{dark ? 'dark' : 'light'}-812x375"
      chat_reachable ".n-composer-stop"
      chat_screenshot "generation-pending-#{dark ? 'dark' : 'light'}-812x375"
      partial = "## Partial answer\n\n**Retained partial evidence**"
      answer.update_columns(content: partial)
      streams = capture_turbo_stream_broadcasts([ @chat, :messages, :en ]) { answer.broadcast_streamed_content(partial) }
      stream_html(streams.find { |stream| stream["target"] == dom_id(answer, :content) }.to_html)
      assert_selector "##{dom_id(answer, :content)} strong", text: "Retained partial evidence", visible: :all
      counts = [ Chat.count, Message.count ]
      click_button "Stop generating", enable_aria_label: true
      assert_button "Send", disabled: false, enable_aria_label: true
      assert_selector "##{dom_id(answer, :content)} strong", text: "Retained partial evidence", visible: :all
      assert_equal partial, answer.reload.content
      refute_predicate answer, :done?
      assert_equal counts, [ Chat.count, Message.count ]
      assert_no_enqueued_jobs only: ChatResponseJob

      answer.content = "## Response unavailable\n\nPlease retry this question."
      answer.metadata = answer.metadata.merge("original_question" => "Retry this exact original question")
      html = with_singleton_replacement(answer, :error?, -> { true }) do
        with_singleton_replacement(answer, :retryable?, -> { true }) do
          ApplicationController.render(partial: "messages/body", locals: { message: answer })
        end
      end
      stream_html(%(<turbo-stream action="update" target="#{dom_id(answer, :messages)}"><template>#{html}</template></turbo-stream>))
      assert_selector "[role=alert][data-chat-error=true]", text: "Response unavailable"
      assert_no_selector "details form", visible: :all
      [ [ 375, 812 ], [ 812, 375 ] ].each do |width, height|
        chat_viewport(width, height)
        chat_contrast "[role=alert] h2"
        chat_reachable "[role=alert] form button"
        chat_screenshot "error-#{dark ? 'dark' : 'light'}-#{width}x#{height}"
      end
      counts = [ Chat.count, Message.count ]
      assert_enqueued_jobs 1, only: ChatResponseJob do
        click_button "Retry"
        assert_selector "form[data-chat-followup][data-generation-busy=true] lexxy-editor[disabled]"
      end
      assert_equal "Retry this exact original question", @chat.messages.user.order(:created_at).last.content.strip
      assert_equal [ counts.first, counts.last + 1 ], [ Chat.count, Message.count ]
      ids = page.evaluate_script("[...document.querySelectorAll('[id]')].map(node => node.id)")
      assert_equal ids.uniq, ids
    rescue Minitest::Assertion, StandardError
      chat_screenshot "FAILED-stateful-#{dark ? 'dark' : 'light'}"
      raise
    end
  end

  test "browser measurement reserves its page context keys" do
    visit chat_url(@chat)
    chat_measurement("kind" => "context-guard-probe")
    evidence = File.join(chat_evidence_directory, "measurements.jsonl")
    original = File.read(evidence)

    %w[theme locale viewport path].each do |key|
      [ key, key.to_sym ].each do |reserved|
        error = assert_raises(ArgumentError) { chat_measurement(reserved => "must not replace context") }
        assert_includes error.message, key
      end
    end

    assert_equal original, File.read(evidence), "Rejected payloads must not alter the evidence file"
  end

  %i[en fr].each do |locale|
    [ false, true ].each do |dark|
      test "native Tools close glyph has independent contrast in #{locale} #{dark ? 'dark' : 'light'}" do
        set_workspace_language(locale)
        [ [ 812, 375 ], [ 375, 812 ] ].each do |width, height|
          chat_viewport(width, height)
          visit chat_url(@chat)
          assert_selector "lexxy-editor[connected]"
          chat_theme(dark)
          chat_keyboard_focus ".n-composer-tools-trigger"
          page.driver.browser.action.send_keys(:enter).perform
          assert_native_dialog "mcp-selector-modal"
          selector = "#mcp-selector-modal button[aria-label='#{I18n.t('nosia.chat_workspace.close', locale: locale)}']"
          assert_selector "#{selector}:focus"
          chat_reachable selector, scroll: false
          screenshot = chat_screenshot "close-glyph-#{locale}-#{dark ? 'dark' : 'light'}-#{width}x#{height}"
          chat_native_close_contrast selector, screenshot: screenshot
          page.driver.browser.action.send_keys(:enter).perform
          assert_no_selector "#mcp-selector-modal[open]", visible: :all
          assert_selector ".n-composer-tools-trigger:focus"
          assert_no_enqueued_jobs only: ChatResponseJob
        end
      end
    end
  end

  private
    def observe_workspace_announcements
      page.execute_script(<<~JS)
        const status = document.querySelector('[data-chat-feedback-target=status]')
        window.workspaceStatus = status
        window.workspaceAnnouncements = []
        window.workspaceStatusObserver = new MutationObserver(() => window.workspaceAnnouncements.push(status.textContent))
        window.workspaceStatusObserver.observe(status, { childList: true, subtree: true, characterData: true })
      JS
    end

    def reconnect_workspace_feedback
      page.execute_script("document.querySelector('.n-chat-workspace').dataset.controller = document.querySelector('.n-chat-workspace').dataset.controller.replace(' chat-feedback', '')")
      settle_workspace_layout
      page.execute_script("document.querySelector('.n-chat-workspace').dataset.controller += ' chat-feedback'")
      settle_workspace_layout
    end

    def set_workspace_language(locale)
      orbite_select_language(locale.to_s.upcase)
      assert_selector "html[lang=#{locale}]"
    end

    def deliver_answer_update(answer, locale)
      streams = capture_turbo_stream_broadcasts([ @chat, :messages, locale ]) { answer.broadcast_updated }
      update = streams.find { |stream| stream["action"] == "update" && stream["target"] == dom_id(answer, :messages) }
      assert update, "Expected the actual whole-answer body update"
      stream_html(update.to_html)
      settle_workspace_layout
    end

    def refresh_workspace
      page.execute_script(<<~JS)
        document.documentElement.removeAttribute('data-workspace-refreshed')
        document.addEventListener('turbo:render', () => document.documentElement.dataset.workspaceRefreshed = 'true', { once: true })
        Turbo.visit(location.href, { action: 'replace' })
      JS
      assert_selector "html[data-workspace-refreshed=true]"
      settle_workspace_layout
    end

    def assert_live_disclosures(answer, sources:, reasoning:)
      assert_selector "#chat-usage-details[open]"
      assert_selector "##{dom_id(answer, :response_details)}[open]"
      assert_selector "##{dom_id(answer, :response_summary)}:focus"
      { sources: sources, reasoning_details: reasoning }.each do |prefix, open|
        assert_selector "##{dom_id(answer, prefix)}#{open ? '[open]' : ':not([open])'}", visible: :all
      end
    end

    def assert_workspace_status(text)
      assert_selector "[role=status][aria-live=polite][aria-atomic=true][data-chat-feedback-target=status]", count: 1, text: text, visible: :all
      assert_no_selector ".n-chat-transcript [role=status]", visible: :all
      assert_no_selector ".ai-response-content[aria-live]", visible: :all
    end

    def reader_move_after_lifecycle(event, intent, growth:)
      page.execute_script(<<~JS, { event: event, intent: intent, growth: growth }, dom_id(workspace(:messages, :workspace_answer), :content))
        const options = arguments[0], contentId = arguments[1], surface = #{reader_surface}
        const root = document.querySelector('.n-chat-workspace--saved')
        window.readerLifecycle = { heightBefore: surface.scrollHeight }
        const move = () => {
          const evidence = window.readerLifecycle
          evidence.heightAfterUpdate = surface.scrollHeight
          evidence.heightBeforeEvent = surface.scrollHeight
          evidence.clientBeforeEvent = surface.clientHeight
          const target = options.event === 'turbo:render' ? document : root.querySelector('lexxy-editor')
          target.dispatchEvent(new CustomEvent(options.event, { bubbles: true }))
          evidence.heightAfterEvent = surface.scrollHeight
          evidence.clientAfterEvent = surface.clientHeight
          evidence.followingBeforeInput = root.dataset.readerFollowing
          if (options.intent === 'pause') {
            const paragraph = document.getElementById(contentId).querySelectorAll('p')[19]
            surface.scrollTop += paragraph.getBoundingClientRect().top - surface.getBoundingClientRect().top - 24
            const top = surface.getBoundingClientRect().top
            const visible = [...document.querySelectorAll('.ai-response-content p')].find(element => element.getBoundingClientRect().bottom > top)
            evidence.anchor = { text: visible.textContent, offset: visible.getBoundingClientRect().top - top }
          } else {
            surface.scrollTop = surface.scrollHeight - surface.clientHeight - 80
            evidence.requestedGap = surface.scrollHeight - surface.clientHeight - surface.scrollTop
          }
          surface.dispatchEvent(new Event('scroll'))
          evidence.followingAfterInput = root.dataset.readerFollowing
          evidence.latestHiddenAfterInput = root.querySelector('[data-scroll-target=latest]').hidden
        }
        if (options.growth) {
          const observer = new MutationObserver(() => { observer.disconnect(); move() })
          observer.observe(document.getElementById(contentId).parentElement, { childList: true })
        } else {
          move()
        }
      JS
    end

    def user_paragraph_anchor(selector)
      page.evaluate_script(<<~JS, selector)
        (() => {
          const top = #{reader_surface}.getBoundingClientRect().top
          const paragraph = [...document.querySelectorAll(arguments[0])].find(element => element.getBoundingClientRect().bottom > top)
          return { text: paragraph.textContent, offset: paragraph.getBoundingClientRect().top - top }
        })()
      JS
    end

    def assert_user_paragraph_anchor(anchor, selector)
      settle_workspace_layout
      current = user_paragraph_anchor(selector)
      assert_equal anchor.fetch("text"), current.fetch("text"), current.to_json
      assert_in_delta anchor.fetch("offset"), current.fetch("offset"), 1, current.to_json
      assert_operator reader_gap, :>, 80
    end

    def set_reader_viewport(width, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
    end

    def visit_reader(width, height)
      set_reader_viewport(width, height)
      visit chat_url(@chat)
      assert_selector "lexxy-editor[connected]"
      settle_reader_animations
      assert_equal "none", page.evaluate_script("getComputedStyle(#{reader_surface}).overflowAnchor")
      assert_reader_following true
      assert_operator reader_gap, :<=, 80
    end

    def reader_surface
      "document.querySelector('[data-application-scroll]')"
    end

    def settle_reader_animations
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        // Turbo inserts replacements after its next repaint; the old DOM may have no animations.
        new Promise(resolve => {
          const observer = new MutationObserver(check)
          function check() {
            if ((window.readerReplacementTargets || []).every(target => !target.isConnected)) {
              observer.disconnect()
              window.readerReplacementTargets = []
              resolve()
            }
          }
          observer.observe(document, { childList: true, subtree: true })
          check()
        })
          .then(() => Promise.all(document.querySelector('.n-chat-transcript').getAnimations({ subtree: true })
            .filter(animation => animation.effect.getTiming().iterations !== Infinity)
            .map(animation => animation.finished.catch(() => {}))))
          .then(() => requestAnimationFrame(() => requestAnimationFrame(done)))
      JS
    end

    def pause_reader
      page.execute_script(<<~JS, dom_id(workspace(:messages, :workspace_answer), :content))
        const surface = #{reader_surface}, paragraph = document.getElementById(arguments[0]).querySelectorAll('p')[19]
        surface.scrollTop += paragraph.getBoundingClientRect().top - surface.getBoundingClientRect().top - 24
        surface.dispatchEvent(new Event('scroll'))
      JS
      assert_reader_following false
      settle_workspace_layout
    end

    def assert_reader_following(following)
      assert_selector ".n-chat-workspace[data-reader-following=#{following}]"
      settle_workspace_layout
      assert_equal [ 0, 0 ], page.evaluate_script("[document.querySelector('main').scrollTop, document.querySelector('.n-chat-transcript').scrollTop]")
    end

    def reader_gap
      settle_workspace_layout
      page.evaluate_script("(() => { const surface = #{reader_surface}; return surface.scrollHeight - surface.clientHeight - surface.scrollTop })()")
    end

    def reader_anchor
      page.evaluate_script(<<~JS)
        (() => {
          const surface = #{reader_surface}, top = surface.getBoundingClientRect().top
          const paragraphs = [...document.querySelectorAll('.n-chat-transcript .ai-response-content p')]
          const paragraph = paragraphs.find(element => element.getBoundingClientRect().bottom > top)
          return { index: paragraphs.indexOf(paragraph), text: paragraph.textContent, offset: paragraph.getBoundingClientRect().top - top }
        })()
      JS
    end

    def assert_reader_anchor(anchor)
      settle_workspace_layout
      current = reader_anchor
      assert_equal anchor.fetch("text"), current.fetch("text"), current.to_json
      assert_in_delta anchor.fetch("offset"), current.fetch("offset"), 1, current.to_json
      assert_operator reader_gap, :>, 80
    end

    def task3_reading_geometry
      page.evaluate_script(<<~JS)
        (() => {
          const selectors = ['html', 'body', '#orbite-shell', 'main', '.n-chat-workspace', '[data-application-scroll]', '.n-chat-header',
            '.n-chat-transcript', '.n-chat-transcript > div', '.n-chat-start', 'h1.n-chat-title', '.n-chat-dock', 'lexxy-editor']
          const describe = node => {
            const style = getComputedStyle(node), bounds = node.getBoundingClientRect()
            return { tag: node.tagName, id: node.id, class: node.className, bounds: bounds.toJSON(),
              documentBottom: bounds.bottom + scrollY, position: style.position,
              offsetParent: node.offsetParent && { tag: node.offsetParent.tagName, id: node.offsetParent.id, class: node.offsetParent.className },
              top: node.scrollTop, clientHeight: node.clientHeight, height: node.scrollHeight,
              width: style.width, minWidth: style.minWidth, maxWidth: style.maxWidth, flex: style.flex, order: style.order,
              minHeight: style.minHeight, padding: style.padding, gap: style.gap,
              insetTop: style.top, insetBottom: style.bottom, marginTop: style.marginTop, marginBottom: style.marginBottom,
              scrollMarginBlock: style.scrollMarginBlock, scrollPaddingBlock: style.scrollPaddingBlock, clipPath: style.clipPath }
          }
          const rail = document.querySelector('#orbite-shell > .n-orbite-rail')
          const actions = document.querySelector('.n-composer-actions')
          const title = document.querySelector('h1.n-chat-title'), titleRect = title?.getBoundingClientRect()
          const hit = titleRect && document.elementFromPoint(titleRect.x + titleRect.width / 2, titleRect.y + titleRect.height / 2)
          return { viewport: [innerWidth, innerHeight], documentTop: document.scrollingElement.scrollTop,
            primaryCount: document.querySelectorAll('[data-application-scroll]').length,
            rail: rail && describe(rail), railItems: rail && [...rail.children].map(describe),
            railLabels: rail && [...rail.querySelectorAll('.sr-only')].map(describe),
            actionChildren: actions && [...actions.children].map(describe),
            account: actions && describe(actions.querySelector('.n-composer-account')),
            picker: actions?.querySelector('select') && describe(actions.querySelector('select')),
            titleHit: !!hit && (hit === title || title.contains(hit)), titleHitTag: hit?.tagName,
            active: document.activeElement.id, boxes: Object.fromEntries(selectors.map(selector => {
              const node = document.querySelector(selector)
              if (!node) return [selector, null]
              const style = getComputedStyle(node)
              return [selector, { bounds: node.getBoundingClientRect().toJSON(), top: node.scrollTop,
                height: node.scrollHeight, clientHeight: node.clientHeight, overflow: style.overflow,
                display: style.display, minHeight: style.minHeight, flex: style.flex, gridRows: style.gridTemplateRows,
                visible: node.checkVisibility({ contentVisibilityAuto: true }) }]
            })) }
        })()
      JS
    end

    def prepare_native_anchor_fixture(gap: 0)
      return unless page.evaluate_script("matchMedia('(max-width: 639px), (max-height: 700px)').matches")

      # Adversarial geometry only: production anchoring stays disabled. The real
      # dock no longer supplies an eligible survivor inside the reading surface,
      # and the transcript excludes all of its descendants from native anchoring.
      page.execute_script(<<~JS, gap)
        const surface = #{reader_surface}, transcript = document.querySelector('.n-chat-transcript')
        const paragraph = transcript.querySelector('.ai-response-content p:last-child')
        const tail = transcript.getBoundingClientRect().bottom - paragraph.getBoundingClientRect().bottom
        const anchor = document.createElement('div'), spacer = document.createElement('div')
        anchor.dataset.readerNativeAnchorFixture = ''
        anchor.inert = true
        // The transparent box spans only the existing tail after the last real
        // paragraph, so it intersects even a short reading zone without opting
        // actual transcript descendants back into anchoring or copying content.
        anchor.style.cssText = `height:${tail + 2}px;margin-top:-${tail}px;overflow-anchor:auto;pointer-events:none`
        spacer.dataset.readerNativeAnchorSpacer = ''
        spacer.inert = true
        spacer.style.cssText = `height:${arguments[0] + Math.max(1, Math.floor(surface.clientHeight / 4))}px;overflow-anchor:none;pointer-events:none`
        surface.style.overflowAnchor = 'auto'
        surface.append(anchor, spacer)
        window.readerNativeAnchorFixture = anchor
        surface.scrollTop = surface.scrollHeight
        surface.dispatchEvent(new Event('scroll'))
      JS
      settle_reader_animations
    end

    def native_anchor_diagnostic(label)
      sample = page.evaluate_script(<<~JS)
        (() => {
          const sample = node => ({ tag: node.tagName, id: node.id, class: node.className,
            overflowAnchor: getComputedStyle(node).overflowAnchor, bounds: node.getBoundingClientRect().toJSON() })
          const surface = document.querySelector('[data-application-scroll]')
          const content = document.querySelector('.ai-response-content')
          const ancestors = []; for (let node = content; node; node = node.parentElement) ancestors.push(sample(node))
          const anchor = surface.querySelector('[data-reader-native-anchor-fixture]')
          return { geometryOnly: true, productionPolicyOverriddenByFixture: surface.style.overflowAnchor === 'auto',
            surface: { ...sample(surface), top: surface.scrollTop, height: surface.scrollHeight, clientHeight: surface.clientHeight },
            ancestors, fixture: anchor && { ...sample(anchor), sameNode: anchor === window.readerNativeAnchorFixture,
              inert: anchor.inert, parentId: anchor.parentElement.id,
              visibleHeight: Math.min(anchor.getBoundingClientRect().bottom, surface.getBoundingClientRect().bottom) - Math.max(anchor.getBoundingClientRect().top, surface.getBoundingClientRect().top) },
            spacer: surface.querySelector('[data-reader-native-anchor-spacer]') && sample(surface.querySelector('[data-reader-native-anchor-spacer]')),
            survivingNodes: [...document.querySelectorAll('.n-chat-transcript details > summary, .n-chat-dock')].map(sample) }
        })()
      JS
      chat_measurement("kind" => "adversarial-native-anchor-diagnostic", "label" => label, "sample" => sample)
      puts "Native anchor diagnostic #{label}: #{sample.to_json}"
      if (fixture = sample.fetch("fixture"))
        assert fixture.fetch("sameNode"), fixture.to_json
        assert fixture.fetch("inert"), fixture.to_json
        assert_equal "application-scroll", fixture.fetch("parentId")
        assert_equal "auto", fixture.fetch("overflowAnchor")
        assert_operator fixture.fetch("bounds").fetch("height"), :>, 0
        assert_operator fixture.fetch("visibleHeight"), :>, 0, fixture.to_json
      end
    end

    def reader_answer(count)
      "## Three findings\n\n" + (1..count).map { |index| "Paragraph #{index}: efficient resource use and clearer evaluation criteria." }.join("\n\n")
    end

    def stream_answer(text)
      message = workspace(:messages, :workspace_answer)
      html = ApplicationController.render(partial: "messages/streaming_content",
        locals: { message: message, content_html: Message.render_markdown_content(text) })
      stream_html(%(<turbo-stream action="replace" target="#{dom_id(message, :content)}"><template>#{html}</template></turbo-stream>))
      assert_selector "##{dom_id(message, :content)} p:last-child", text: text.split("\n\n").last, visible: :all
      settle_workspace_layout
    end

    def stream_html(html)
      page.execute_script(<<~JS, html)
        window.readerReplacementTargets ||= []
        const remember = event => {
          const stream = event.target
          if (stream.action === 'replace' && stream.getAttribute('method') !== 'morph') {
            window.readerReplacementTargets.push(...stream.targetElements)
          }
        }
        document.addEventListener('turbo:before-stream-render', remember, true)
        try {
          Turbo.renderStreamMessage(arguments[0])
        } finally {
          document.removeEventListener('turbo:before-stream-render', remember, true)
        }
      JS
    end

    def settle_workspace_layout
      page.evaluate_async_script("const done = arguments[arguments.length - 1]; requestAnimationFrame(() => requestAnimationFrame(done))")
    end

    def formatting_geometry
      page.evaluate_script(<<~JS)
        (() => Object.fromEntries(Object.entries({
          toolbar: 'lexxy-toolbar', editor: 'lexxy-editor', content: '.lexxy-editor__content',
          actions: '.n-composer-actions', center: '.n-chat-start', surface: '[data-application-scroll]', main: '.n-chat-main', root: '.n-chat-workspace',
          form: '.n-chat-composer', eyebrow: '.n-chat-eyebrow', title: '.n-chat-start h1', help: '.n-chat-start > .n-workspace-help',
          meta: '.n-composer-meta', notice: '.n-composer-notice'
        }).map(([name, selector]) => {
          const element = document.querySelector(selector)
          if (!element) return [name, null]
          const style = getComputedStyle(element), bounds = element.getBoundingClientRect()
          return [name, { ...bounds.toJSON(), scrollHeight: element.scrollHeight, clientHeight: element.clientHeight,
            scrollTop: element.scrollTop, overflowY: style.overflowY, display: style.display, visibility: style.visibility,
            minBlockSize: style.minBlockSize, maxBlockSize: style.maxBlockSize, flex: style.flex,
            justifyContent: style.justifyContent, lastChild: element.lastElementChild?.getBoundingClientRect().toJSON() }]
        })))()
      JS
    end

    def assert_native_dialog(id)
      assert_selector "dialog##{id}[open]"
      assert page.evaluate_script("document.getElementById(arguments[0]).matches(':modal')", id)
    end

    def assert_dialog_focus(id)
      assert page.evaluate_script("document.getElementById(arguments[0]).contains(document.activeElement)", id),
        page.evaluate_script("JSON.stringify({ active: document.activeElement.outerHTML.slice(0, 500), focused: document.hasFocus() })")
      assert_selector "dialog##{id} :focus"
    end

    def hold_source_registration
      page.execute_script(<<~JS, websites(:picker_second_website).id)
        const id = arguments[0], original = window.fetch
        window.fetch = (input, options) => {
          const url = new URL(input instanceof Request ? input.url : input, location.href)
          if (url.pathname !== '/chat_sources') return original(input, options)
          return new Promise(resolve => {
            window.releaseWorkspaceSource = () => {
              window.fetch = original
              resolve(new Response(JSON.stringify({ id }), { headers: { 'Content-Type': 'application/json' } }))
            }
          })
        }
      JS
    end
end
