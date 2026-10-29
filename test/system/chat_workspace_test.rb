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

  private
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
