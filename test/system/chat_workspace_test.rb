require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"

class ChatWorkspaceSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

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
    assert_selector "button[aria-controls=chat-history]:focus"
    assert page.evaluate_script("window.savedChatEditor === document.querySelector('lexxy-editor')")
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this unsent draft"
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "saved Tools is a native modal during generation without losing Stop" do
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

    page.execute_script("document.querySelector('button[aria-controls=chat-history]').click()")

    assert_native_dialog "chat-history"
    assert_selector "dialog[open]", count: 1
    assert_no_selector "#mcp-selector-modal[open]", visible: :all
    assert_dialog_focus "chat-history"
    within("#chat-history") { click_button "Close" }
    assert_selector "button[aria-controls=chat-history]:focus"
  end

  test "History is closed before Turbo caches navigation and remains closed on Back" do
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
    assert_selector "button[aria-controls=chat-history]:focus"
  end

  test "dialogs preserve draft account tool choices and pending source coordination" do
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
      assert_selector "button[aria-controls=chat-history]:focus"
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
        %w[main root].each do |name|
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
  end

  test "paused reader keeps its paragraph through surface changes and editor reflow" do
    visit_reader(1400, 1000)
    pause_reader
    anchor = reader_anchor

    set_reader_viewport(375, 812)
    settle_workspace_layout
    assert_reader_following false
    assert_reader_anchor anchor
    assert_equal "n-chat-main", page.evaluate_script("#{reader_surface}.className")
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
    assert_equal "n-chat-transcript", page.evaluate_script("#{reader_surface}.className")
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

  private
    def set_reader_viewport(width, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
    end

    def visit_reader(width, height)
      set_reader_viewport(width, height)
      visit chat_url(@chat)
      assert_selector "lexxy-editor[connected]"
      settle_reader_animations
      assert_reader_following true
      assert_operator reader_gap, :<=, 80
    end

    def reader_surface
      "(matchMedia('(max-width: 639px), (max-height: 700px)').matches ? document.querySelector('main.n-chat-main') : document.querySelector('.n-chat-transcript'))"
    end

    def settle_reader_animations
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        Promise.all(document.querySelector('.n-chat-transcript').getAnimations({ subtree: true })
          .filter(animation => animation.effect.getTiming().iterations !== Infinity)
          .map(animation => animation.finished.catch(() => {}))).then(done)
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
      page.execute_script("Turbo.renderStreamMessage(arguments[0])", html)
    end

    def settle_workspace_layout
      page.evaluate_async_script("const done = arguments[arguments.length - 1]; requestAnimationFrame(() => requestAnimationFrame(done))")
    end

    def formatting_geometry
      page.evaluate_script(<<~JS)
        (() => Object.fromEntries(Object.entries({
          toolbar: 'lexxy-toolbar', editor: 'lexxy-editor', content: '.lexxy-editor__content',
          actions: '.n-composer-actions', center: '.n-chat-start', main: '.n-chat-main', root: '.n-chat-workspace',
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
