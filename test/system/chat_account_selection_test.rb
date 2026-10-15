require "application_system_test_case"
require "tempfile"
require_relative "../support/chat_account_fixtures"

class ChatAccountSelectionSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  test "empty switching refreshes account options on both entry points" do
    [ user_root_url(model: "picker-test-model"), new_chat_url(model: "picker-test-model") ].each do |url|
      visit url
      select "Research team", from: "Account"

      assert_selector "select option[selected][value='#{@second.id}']"
      assert_selector "#chat-form input[type=checkbox][value='#{mcp_servers(:picker_second_tool).id}']", visible: :all
      assert_equal [ "second-skill" ], browser_skills
      assert_selector "#chat-form input[name='chat[model]'][value='picker-test-model']", visible: :all
      assert_equal({ "model" => "picker-test-model", "account_id" => @second.id.to_s }, URI.decode_www_form(URI.parse(current_url).query).to_h)
    end
  end

  test "cancel preserves the draft and confirm resets it without moving saved sources" do
    write_draft("Keep this draft")

    dismiss_confirm(/clears your unsent message/) { select "Research team", from: "Account" }

    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
    assert_includes draft_html, "Keep this draft"

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }

    assert_selector "select option[selected][value='#{@second.id}']"
    assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
    assert_not_includes draft_html, "Keep this draft"
    assert_equal @first.id, websites(:picker_first_website).reload.account_id
  end

  test "sending fixes the account across reload follow-up and unlock" do
    visit new_chat_url(model: "picker-test-model")
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    write_draft("Research question")

    find("button[aria-label='Send']").click

    assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
    assert_no_selector "select[name='chat[account_id]']"
    assert_selector "form[data-generation-busy='true'] lexxy-editor[disabled]"
    chat = @user.chats.order(:id).last
    assert_current_path chat_path(chat)
    assert_equal @second.id, chat.account_id
    assert_predicate chat.reload, :generating?
    assert_equal "Research question", chat.messages.user.last.content.strip
    assert_enqueued_jobs 1, only: ChatResponseJob

    page.refresh

    assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
    assert_selector "form[data-generation-busy='true'] lexxy-editor[disabled]"
    chat.finish_generation!
    visit chat_url(chat)
    assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
    assert_no_selector "select[name='chat[account_id]']"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "form[data-generation-busy='false'] lexxy-editor:not([disabled]):not([inert])"
    write_draft("Follow-up question")

    find("button[aria-label='Send']").click

    assert_selector "form[data-generation-busy='true'] lexxy-editor[disabled]"
    assert_empty find("lexxy-editor .lexxy-editor__content").text.strip
    assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
    assert_no_selector "select[name='chat[account_id]']"
    assert_equal @second.id, chat.reload.account_id
    assert_equal "Follow-up question", chat.messages.user.last.content.strip
    assert_equal 2, chat.messages.user.count
    assert_enqueued_jobs 2, only: ChatResponseJob

    visit new_chat_url

    assert_selector "select option[selected][value='#{@first.id}']"
    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
  end

  test "account selection cannot change while the first-message POST is pending" do
    visit new_chat_url(model: "picker-test-model")
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    write_draft("Fixed at send time")
    counts = [ Chat.count, Message.count ]
    page.execute_script(<<~JS)
      const original = window.fetch;
      window.fetch = (...args) => {
        const url = new URL(args[0] instanceof Request ? args[0].url : args[0], location.href);
        if (url.pathname !== '/chats' || (args[1]?.method || 'GET').toUpperCase() !== 'POST') return original(...args);
        return new Promise((resolve, reject) => {
          window.releasePickerChat = () => { window.fetch = original; original(...args).then(resolve, reject); };
          document.body.dataset.pickerChatHeld = 'true';
        });
      };
    JS

    find("button[aria-label='Send']").click

    assert_selector "body[data-picker-chat-held=true]"
    assert_selector "select[name='chat[account_id]'][disabled]"
    page.execute_script(<<~JS, @first.id.to_s)
      const picker = document.querySelector('select[name="chat[account_id]"]');
      picker.value = arguments[0];
      picker.dispatchEvent(new Event('change', { bubbles: true }));
    JS
    assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob

    page.execute_script("window.releasePickerChat()")

    assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
    assert_selector "form[data-generation-busy='true'] lexxy-editor[disabled]"
    assert_equal @second.id, @user.chats.order(:id).last.account_id
    assert_enqueued_jobs 1, only: ChatResponseJob
  end

  test "footer selection is keyboard accessible on a narrow viewport" do
    page.current_window.resize_to(390, 844)
    picker = find_field("Account")
    assert_selector "label[for='#{picker[:id]}']", text: "Account"
    assert_selector "##{picker['aria-describedby']}", text: "Searches and attachments use this account."
    picker.send_keys(:home)
    assert_selector "select[name='chat[account_id]']:focus"

    picker.send_keys(:end)

    assert_selector "select option[selected][value='#{@second.id}']"
    assert_no_selector "html[aria-busy='true']"
    assert_equal @second.id.to_s, find_field("Account").value
    bounds = page.evaluate_script(<<~JS)
      (() => {
        const picker = document.querySelector('select[name="chat[account_id]"]');
        const bounds = picker.getBoundingClientRect();
        return { left: bounds.left, right: bounds.right, viewport: window.innerWidth };
      })()
    JS
    assert_operator bounds.fetch("viewport"), :<=, 390
    assert_operator bounds.fetch("left"), :>=, 0
    assert_operator bounds.fetch("right"), :<=, bounds.fetch("viewport")
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "a pending account switch blocks Send Enter and requestSubmit from sending the old draft" do
    visit new_chat_url(model: "picker-test-model")
    write_draft("This belongs to the first account")
    hold_account_switch
    counts = [ Chat.count, Message.count ]

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_selector "body[data-account-switch-held=true]"

    submission_counts = page.evaluate_script(<<~JS)
      (() => {
        const form = document.querySelector("#chat-form")
        window.accountSwitchSubmissionAttempts = 0
        window.accountSwitchEscapedSubmissions = 0
        form.addEventListener("submit", () => window.accountSwitchSubmissionAttempts++, { capture: true })
        document.addEventListener("submit", event => {
          if (event.target === form) window.accountSwitchEscapedSubmissions++
        })
        form.querySelector("button[aria-label='Send']").click()
        form.querySelector(".lexxy-editor__content").dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
        form.requestSubmit()
        return [window.accountSwitchSubmissionAttempts, window.accountSwitchEscapedSubmissions]
      })()
    JS

    assert_equal [ 2, 0 ], submission_counts
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"
    assert_selector "[data-controller~='chat-account'][inert] lexxy-editor[disabled]"
    page.driver.browser.action.send_keys(:enter).perform
    assert_equal [ 2, 0 ], page.evaluate_script("[window.accountSwitchSubmissionAttempts, window.accountSwitchEscapedSubmissions]")

    page.execute_script("window.releaseAccountSwitch()")

    assert_selector "select option[selected][value='#{@second.id}']"
    assert_selector "lexxy-editor .lexxy-editor__content"
    assert_not_includes draft_html, "This belongs to the first account"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_equal counts, [ Chat.count, Message.count ]
    assert_equal 0, page.evaluate_script("window.accountSwitchPostCount")
    assert_no_enqueued_jobs only: ChatResponseJob

    page.go_back

    assert_selector "select option[selected][value='#{@first.id}']"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
  end

  test "a canceled Turbo visit restores the old account and draft and permits retry" do
    write_draft("Keep this canceled navigation draft")
    page.execute_script(<<~JS)
      window.addEventListener("turbo:before-visit", event => {
        event.preventDefault()
        document.body.dataset.accountSwitchCanceled = "true"
      }, { once: true })
    JS

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }

    assert_selector "body[data-account-switch-canceled=true]"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
    assert_includes draft_html, "Keep this canceled navigation draft"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
    assert_current_path user_root_path

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_not_includes draft_html, "Keep this canceled navigation draft"
    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
  end

  test "a cached account preview blocks submissions until the fresh account response renders" do
    visit new_chat_url(model: "picker-test-model")
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_no_selector "html[aria-busy='true']"
    select "First team", from: "Account"
    assert_selector "select option[selected][value='#{@first.id}']"
    assert_no_selector "html[aria-busy='true']"
    hold_account_switch
    counts = [ Chat.count, Message.count ]

    select "Research team", from: "Account"

    assert_selector "html[data-turbo-preview][data-account-switch-held=true]"
    assert_selector "select option[selected][value='#{@second.id}']"
    write_draft("Do not send from this preview")

    submission_counts = page.evaluate_script(<<~JS)
      (() => {
        const form = document.querySelector("#chat-form")
        window.accountSwitchSubmissionAttempts = 0
        window.accountSwitchEscapedSubmissions = 0
        form.addEventListener("submit", () => window.accountSwitchSubmissionAttempts++, { capture: true })
        document.addEventListener("submit", event => {
          if (event.target === form) window.accountSwitchEscapedSubmissions++
        })
        form.querySelector("button[aria-label='Send']").click()
        form.querySelector(".lexxy-editor__content").dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
        form.requestSubmit()
        return [window.accountSwitchSubmissionAttempts, window.accountSwitchEscapedSubmissions]
      })()
    JS

    assert_equal [ 2, 0 ], submission_counts
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"
    assert_selector "[data-controller~='chat-account'][inert] lexxy-editor[disabled]"
    page.driver.browser.action.send_keys(:enter).perform
    assert_equal [ 2, 0 ], page.evaluate_script("[window.accountSwitchSubmissionAttempts, window.accountSwitchEscapedSubmissions]")
    page.execute_script(<<~JS, @first.id.to_s)
      const picker = document.querySelector("select[name='chat[account_id]']")
      picker.value = arguments[0]
      picker.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
    assert_selector "html[data-turbo-preview]"

    page.execute_script("window.releaseAccountSwitch()")

    assert_no_selector "html[data-turbo-preview]"
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_empty find("lexxy-editor .lexxy-editor__content").text.strip
    assert_equal counts, [ Chat.count, Message.count ]
    assert_equal 0, page.evaluate_script("window.accountSwitchPostCount")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "a failed account switch uses Turbo recovery with a fresh intended account and no side effects" do
    visit new_chat_url(model: "picker-test-model")
    write_draft("Discard this confirmed navigation draft")
    find("summary", text: /MCP Tools/).click
    check "First tool"
    page.execute_script(<<~JS, websites(:picker_first_website).id.to_s)
      document.querySelector('[data-composer-sources-target="websiteIds"]').value = arguments[0]
      document.querySelector('[data-composer-sources-target="documentIds"]').value = "draft-document"
    JS
    hold_account_switch
    counts = [ Chat.count, Message.count, Website.count, Document.count, Text.count ]

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_selector "body[data-account-switch-held=true]"

    page.execute_script("window.failAccountSwitch()")

    assert_selector "select option[selected][value='#{@second.id}']"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_selector "lexxy-editor .lexxy-editor__content"
    assert_not_includes draft_html, "Discard this confirmed navigation draft"
    assert_no_selector "input[name='mcp_server_ids[]']:checked", visible: :all
    assert_equal "", find("[data-composer-sources-target='websiteIds']", visible: :all).value
    assert_equal "", find("[data-composer-sources-target='documentIds']", visible: :all).value
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_current_path new_chat_path, ignore_query: true
    assert_equal({ "model" => "picker-test-model", "account_id" => @second.id.to_s }, URI.decode_www_form(URI.parse(current_url).query).to_h)
    assert_selector "input[name='chat[model]'][value='picker-test-model']", visible: :all
    assert_no_selector "html[aria-busy='true']"
    assert_no_selector ".turbo-progress-bar", visible: :all
    assert_equal counts, [ Chat.count, Message.count, Website.count, Document.count, Text.count ]
    assert_equal @first.id, websites(:picker_first_website).reload.account_id
    assert_no_enqueued_jobs only: ChatResponseJob

    page.go_back

    assert_selector "select option[selected][value='#{@first.id}']"
    assert_selector "lexxy-editor .lexxy-editor__content"
    assert_not_includes draft_html, "Discard this confirmed navigation draft"
    assert_no_selector "input[name='mcp_server_ids[]']:checked", visible: :all
    assert_equal "", find("[data-composer-sources-target='websiteIds']", visible: :all).value
    assert_equal "", find("[data-composer-sources-target='documentIds']", visible: :all).value

    page.go_forward

    assert_selector "select option[selected][value='#{@second.id}']"
    select "First team", from: "Account"
    assert_selector "select option[selected][value='#{@first.id}']"
    assert_no_selector "html[aria-busy='true']"
    assert_no_selector ".turbo-progress-bar", visible: :all
    assert_equal counts, [ Chat.count, Message.count, Website.count, Document.count, Text.count ]
  end

  test "Turbo history does not restore unsent text references or tool choices" do
    write_draft("Do not cache this draft")
    find("summary", text: /MCP Tools/).click
    check "First tool"
    page.execute_script(<<~JS, websites(:picker_first_website).id.to_s)
      document.querySelector('[data-composer-sources-target="websiteIds"]').value = arguments[0]
      document.querySelector('[data-composer-sources-target="documentIds"]').value = "draft-document"
      const hiddenTool = document.createElement("input")
      hiddenTool.type = "hidden"
      hiddenTool.name = "mcp_server_ids[]"
      hiddenTool.value = "draft-tool"
      document.querySelector("#mcp-server-hidden-fields").append(hiddenTool)
    JS

    click_link "New Chat"
    assert_current_path new_chat_path
    page.go_back

    assert_current_path user_root_path
    assert_selector "lexxy-editor .lexxy-editor__content"
    assert_not_includes draft_html, "Do not cache this draft"
    assert_no_selector "input[name='mcp_server_ids[]']:checked", visible: :all
    assert_no_selector "#mcp-server-hidden-fields input", visible: :all
    assert_selector "#mcp-selected-count", text: "0", visible: :all
    assert_equal "", find("[data-composer-sources-target='websiteIds']", visible: :all).value
    assert_equal "", find("[data-composer-sources-target='documentIds']", visible: :all).value
    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
  end

  test "Turbo Back and Forward never restore cross-account references or tool choices" do
    write_draft("Discard this first-account draft")
    find("summary", text: /MCP Tools/).click
    check "First tool"
    dispatch_link("https://history-first.example/reference")
    assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
    assert_equal 1, browser_website_ids.size

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }

    assert_selector "select option[selected][value='#{@second.id}']"
    assert_no_selector "html[aria-busy='true']"
    assert_equal [ "second-skill" ], browser_skills
    assert_not_includes draft_html, "Discard this first-account draft"
    assert_no_selector "input[type=checkbox][name='mcp_server_ids[]']:checked", visible: :all
    assert_no_selector "#mcp-server-hidden-fields input", visible: :all
    assert_empty browser_website_ids

    page.go_back

    assert_selector "select option[selected][value='#{@first.id}']"
    assert_no_selector "html[aria-busy='true']"
    assert_equal [ "first-skill" ], browser_skills
    assert_not_includes draft_html, "Discard this first-account draft"
    assert_no_selector "input[type=checkbox][name='mcp_server_ids[]']:checked", visible: :all
    assert_no_selector "#mcp-server-hidden-fields input", visible: :all
    assert_empty browser_website_ids

    page.go_forward

    assert_selector "select option[selected][value='#{@second.id}']"
    assert_no_selector "html[aria-busy='true']"
    assert_equal [ "second-skill" ], browser_skills
    assert_not_includes draft_html, "Discard this first-account draft"
    assert_no_selector "input[type=checkbox][name='mcp_server_ids[]']:checked", visible: :all
    assert_no_selector "#mcp-server-hidden-fields input", visible: :all
    assert_empty browser_website_ids
    assert @first.websites.exists?(url: "https://history-first.example/reference")
    assert_not @second.websites.exists?(url: "https://history-first.example/reference")
  end

  test "a pasted URL is registered in the selected account" do
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    write_draft("Use the linked source")

    dispatch_link("https://browser-source.example/reference")

    assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
    assert @second.websites.exists?(url: "https://browser-source.example/reference")
    assert_not @first.websites.exists?(url: "https://browser-source.example/reference")
  end

  test "pending registration blocks account changes and Enter submission" do
    install_source_fetch_gate
    write_draft("Wait for this source")
    counts = [ Chat.count, Message.count ]

    dispatch_link("https://pending-source.example/reference")

    assert_selector "select[name='chat[account_id]'][disabled]"
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
    find("lexxy-editor .lexxy-editor__content").send_keys(" while editing")
    assert_includes draft_html, "while editing"
    assert_source_submission_blocked
    page.execute_script("window.releasePickerSource()")
    assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "a failed registration blocks send and can be retried" do
    page.execute_script(<<~JS)
      window.originalPickerFetch = window.fetch;
      window.fetch = (...args) => {
        const url = new URL(args[0] instanceof Request ? args[0].url : args[0], location.href);
        if (url.pathname === '/chat_sources') return Promise.resolve(new Response(JSON.stringify({ error: 'Source registration failed' }), { status: 422, headers: { 'Content-Type': 'application/json' } }));
        return window.originalPickerFetch(...args);
      };
    JS
    write_draft("Retry this source")
    counts = [ Chat.count, Message.count ]

    dispatch_link("https://retry-source.example/reference")

    assert_text "Source registration failed"
    assert_selector "button[aria-label='Send'][disabled]"
    assert_source_submission_blocked
    page.execute_script("window.fetch = window.originalPickerFetch")
    observe_source_requests
    page.execute_script(<<~JS)
      window.addEventListener('turbo:before-visit', event => {
        Array.from(document.querySelectorAll('[data-composer-sources-target="errors"] button')).find(button => button.textContent === 'Retry source').click();
        event.preventDefault();
        document.body.dataset.accountSwitchCanceled = 'true';
      }, { once: true });
    JS
    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_selector "body[data-account-switch-canceled=true]"
    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
    assert_empty page.evaluate_script("window.pickerSourceRequests")
    assert_text "Source registration failed"
    click_on "Retry source"
    assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_no_text "Source registration failed"
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "resetting a failed source clears only the unsent draft" do
    write_draft("Unsaved draft")
    dispatch_link("https://reset-saved.example/reference")
    assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
    counts = [ Chat.count, Message.count, Website.count ]
    page.execute_script(<<~JS)
      const original = window.fetch;
      window.fetch = (...args) => {
        const url = new URL(args[0] instanceof Request ? args[0].url : args[0], location.href);
        if (url.pathname !== '/chat_sources') return original(...args);
        window.fetch = original;
        return Promise.reject(new TypeError('Network unavailable'));
      };
    JS

    dispatch_link("https://reset-failure.example/reference")

    assert_selector "button[aria-label='Send'][disabled]"
    assert_text "Network unavailable"
    accept_confirm(/Reset this unsent draft/) { click_on "Reset draft" }

    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_equal @first.id.to_s, find_field("Account").value
    assert_empty find("lexxy-editor .lexxy-editor__content").text.strip
    assert_not_includes draft_html, "Unsaved draft"
    assert_no_selector "[data-composer-sources-target='errors']:not([hidden])"
    assert_empty browser_website_ids
    assert_equal counts, [ Chat.count, Message.count, Website.count ]
    assert_equal @first.id, websites(:picker_first_website).reload.account_id
    assert @first.websites.exists?(url: "https://reset-saved.example/reference")
    assert_not @first.websites.exists?(url: "https://reset-failure.example/reference")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "PDF upload lifecycle stays pending until its SGID is registered" do
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    install_source_fetch_gate
    start_held_pdf_uploads("browser-account.pdf")
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"

    page.execute_script("window.releasePickerUpload('browser-account.pdf')")

    assert_selector "body[data-picker-source-held=true]"
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"
    page.execute_script("window.releasePickerSource()")
    assert_selector "input[name='chat[attached_document_ids][]']", count: 2, visible: :all
    assert_equal @second.id, Document.joins(file_attachment: :blob).where(active_storage_blobs: { filename: "browser-account.pdf" }).last.account_id
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
  end

  test "saved chat registration sends chat authority once and uses message attachment fields" do
    chat = chats(:picker_second_chat)
    visit chat_url(chat)
    assert_selector "[data-chat-account-readonly]", text: "Research team"
    page.execute_script(<<~JS)
      const original = window.fetch;
      window.pickerSourcePayloads = [];
      window.fetch = (input, options = {}) => {
        const url = new URL(input instanceof Request ? input.url : input, location.href);
        if (url.pathname === '/chat_sources') window.pickerSourcePayloads.push(JSON.parse(options.body));
        return original(input, options);
      };
    JS
    write_draft("Saved chat source")

    2.times { dispatch_link("https://saved-browser-source.example/reference") }

    assert_selector "input[name='message[attached_website_ids][]']", count: 2, visible: :all
    assert_equal [ { "url" => "https://saved-browser-source.example/reference", "chat_id" => chat.id.to_s } ], page.evaluate_script("window.pickerSourcePayloads")
    assert @second.websites.exists?(url: "https://saved-browser-source.example/reference")
    assert_not @first.websites.exists?(url: "https://saved-browser-source.example/reference")
  end

  test "scoped reset aborts registration and ignores a late response in the new account" do
    install_source_fetch_gate(ignore_abort: true)
    write_draft("Discard this pending source")
    dispatch_link("https://late-browser-source.example/reference")
    assert_selector "body[data-picker-source-held=true]"
    page.execute_script(<<~JS)
      window.dispatchEvent(new CustomEvent('chat-account:reset', { detail: { root: document.createElement('div') } }));
    JS
    assert_selector "button[aria-label='Send'][disabled]"
    assert_includes draft_html, "Discard this pending source"
    page.execute_script(<<~JS)
      window.dispatchEvent(new CustomEvent('chat-account:reset', { detail: { root: document.querySelector('[data-controller="chat-account"]') } }));
    JS
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_empty find("lexxy-editor .lexxy-editor__content").text.strip
    assert page.evaluate_script("window.pickerSourceSignal.aborted")

    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    page.execute_script("window.releasePickerSource()")
    assert_selector "body[data-picker-source-released=true]"
    assert_selector "input[name='chat[attached_website_ids][]']", count: 1, visible: :all
    assert_equal "", find("[data-composer-sources-target='websiteIds']", visible: :all).value
    assert @first.websites.exists?(url: "https://late-browser-source.example/reference")
    assert_not @second.websites.exists?(url: "https://late-browser-source.example/reference")
    assert_selector "button[aria-label='Send']:not([disabled])"
  end

  test "upload failures remain blocking until a confirmed draft reset" do
    write_draft("Failed PDF draft")
    page.execute_script(<<~JS)
      const editor = document.querySelector('lexxy-editor');
      const file = new File(['%PDF-1.4'], 'failed.pdf', { type: 'application/pdf' });
      editor.dispatchEvent(new CustomEvent('lexxy:upload-start', { detail: { file }, bubbles: true }));
      editor.dispatchEvent(new CustomEvent('lexxy:upload-end', { detail: { file, error: new Error('Upload failed') }, bubbles: true }));
    JS

    assert_text "PDF upload failed"
    assert_selector "button[aria-label='Send'][disabled]"
    assert_no_button "Retry source"
    dismiss_confirm(/Reset this unsent draft/) { click_on "Reset draft" }
    assert_includes draft_html, "Failed PDF draft"
    assert_selector "button[aria-label='Send'][disabled]"
    accept_confirm(/Reset this unsent draft/) { click_on "Reset draft" }
    assert_empty find("lexxy-editor .lexxy-editor__content").text.strip
    assert_no_selector "[data-composer-sources-target='errors']:not([hidden])"
    assert_selector "button[aria-label='Send']:not([disabled])"
  end

  test "a live account switch rejects queued URL and PDF registration in the old composer" do
    observe_source_requests
    hold_account_switch

    select "Research team", from: "Account"

    assert_selector "body[data-account-switch-held=true]"
    assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
    assert_equal @first.id.to_s, find("[data-composer-sources-account-id-value]")["data-composer-sources-account-id-value"]
    assert_queued_sources_blocked("https://old-switch-source.example/reference")
    assert_selector "[data-controller~='chat-account'][inert] lexxy-editor[disabled]"

    page.execute_script("window.releaseAccountSwitch()")

    assert_selector "select option[selected][value='#{@second.id}']"
    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
    write_draft("Research account source")
    dispatch_link("https://fresh-switch-source.example/reference")
    assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
    assert @second.websites.exists?(url: "https://fresh-switch-source.example/reference")
    assert_not @first.websites.exists?(url: "https://fresh-switch-source.example/reference")
  end

  test "a cached account preview rejects queued sources until the fresh composer renders" do
    visit new_chat_url(model: "picker-test-model")
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_no_selector "html[aria-busy='true']"
    select "First team", from: "Account"
    assert_selector "select option[selected][value='#{@first.id}']"
    assert_no_selector "html[aria-busy='true']"
    observe_source_requests
    hold_account_switch

    select "Research team", from: "Account"

    assert_selector "html[data-turbo-preview][data-account-switch-held=true]"
    assert_queued_sources_blocked("https://preview-switch-source.example/reference")
    assert_selector "[data-controller~='chat-account'][inert] lexxy-editor[disabled]"

    page.execute_script("window.releaseAccountSwitch()")

    assert_no_selector "html[data-turbo-preview]"
    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
    assert_selector "input[name='chat[attached_website_ids][]']", count: 1, visible: :all
    assert_selector "input[name='chat[attached_document_ids][]']", count: 1, visible: :all
    find("lexxy-editor .lexxy-editor__content").send_keys("Fresh research draft")
    assert_includes draft_html, "Fresh research draft"
  end

  test "submission disables source entry without making the conversation inert and restores editing on failure" do
    observe_source_requests
    page.execute_script("document.querySelector('#chat-form').dispatchEvent(new CustomEvent('turbo:submit-start', { bubbles: true }))")

    assert_queued_sources_blocked("https://submitting-source.example/reference")
    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor[disabled]"

    page.execute_script("document.querySelector('#chat-form').dispatchEvent(new CustomEvent('turbo:submit-end', { detail: { success: false }, bubbles: true }))")

    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
    find("lexxy-editor .lexxy-editor__content").send_keys("Edit after failure")
    assert_includes draft_html, "Edit after failure"
    assert_selector "button[aria-label='Send']:not([disabled])"
  end

  test "generation disables source entry but leaves the saved conversation interactive" do
    chat = chats(:picker_second_chat)
    chat.update!(generating: true)
    visit chat_url(chat)
    assert_selector "form[data-generation-busy='true'] lexxy-editor[disabled]"
    observe_source_requests

    assert_queued_sources_blocked("https://generating-source.example/reference")

    assert_selector "[data-controller~='chat-account']:not([inert])"
    find("button[data-modal-open-target-value='mcp-selector-modal']").click
    assert_selector "#mcp-selector-modal:not(.hidden)"
    chat.update!(generating: false)
    visit chat_url(chat)
    assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
  end

  test "generation prevents real keyboard editing without freezing conversation controls" do
    chat = chats(:picker_second_chat)
    chat.update!(generating: true)
    visit chat_url(chat)
    write_draft("Keep the generation draft unchanged")
    before = draft_html
    page.execute_script("document.querySelector('lexxy-editor .lexxy-editor__content').focus()")

    page.driver.browser.action.send_keys(" forbidden typing").perform

    assert_equal before, draft_html
    assert_selector "lexxy-editor[disabled][inert]"
    assert_selector "[data-controller~='chat-account']:not([inert])"
    find("button[data-modal-open-target-value='mcp-selector-modal']").click
    assert_selector "#mcp-selector-modal:not(.hidden)"
  end

  test "submission prevents real toolbar formatting and restores it when submission ends" do
    write_draft("Keep this formatting")
    find("lexxy-editor .lexxy-editor__content").send_keys([ :control, "a" ])
    page.execute_script("document.querySelector('#chat-form').dispatchEvent(new CustomEvent('turbo:submit-start', { bubbles: true }))")
    before = draft_html

    page.driver.browser.action.move_to(find("lexxy-editor button[data-command='bold']").native).click.perform

    assert_equal before, draft_html
    assert_selector "lexxy-editor[disabled][inert]"
    page.execute_script("document.querySelector('#chat-form').dispatchEvent(new CustomEvent('turbo:submit-end', { bubbles: true }))")
    assert_selector "lexxy-editor:not([disabled]):not([inert])"
    find("lexxy-editor .lexxy-editor__content").send_keys([ :control, "a" ])
    find("lexxy-editor button[data-command='bold']").click
    assert_selector "lexxy-editor .lexxy-editor__content strong", text: "Keep this formatting"
  end

  test "deleting a held direct upload clears pending without an upload-end event" do
    observe_source_requests
    start_held_pdf_uploads("deleted-upload.pdf")
    assert_selector "button[aria-label='Send'][disabled]"

    find("lexxy-editor .lexxy-editor__content").send_keys([ :control, "a" ], :backspace)

    assert_no_selector "lexxy-editor figure progress"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_equal [ true ], page.evaluate_script("window.pickerUploads.map(upload => upload.aborted)")
    assert_empty page.evaluate_script("window.pickerUploadEnds")
    page.execute_script("window.releasePickerUpload('deleted-upload.pdf')")
    assert_empty page.evaluate_script("window.pickerSourceRequests")
    assert_no_enqueued_jobs only: AddDocumentJob
    find("lexxy-editor .lexxy-editor__content").send_keys("Continue this draft")
    assert_includes draft_html, "Continue this draft"
  end

  test "canceling one of several uploads preserves the text and remaining upload" do
    observe_source_requests
    write_draft("Surviving draft text")
    find("lexxy-editor .lexxy-editor__content").send_keys([ :control, :end ])
    start_held_pdf_uploads("cancel-one.pdf", "keep-two.pdf", reverse_requests: true)
    find("lexxy-editor figure", text: "cancel-one.pdf").click
    page.driver.browser.action.send_keys(:backspace).perform

    assert_no_selector "lexxy-editor figure", text: "cancel-one.pdf"
    assert_selector "lexxy-editor figure", text: "keep-two.pdf"
    assert_includes draft_html, "Surviving draft text"
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"
    assert_equal [ "keep-two.pdf", "cancel-one.pdf" ], page.evaluate_script("window.pickerUploads.map(upload => upload.filename)")
    assert_equal({ "cancel-one.pdf" => true, "keep-two.pdf" => false },
      page.evaluate_script("Object.fromEntries(window.pickerUploads.map(upload => [upload.filename, upload.aborted]))"))
    page.execute_script("window.releasePickerUpload('cancel-one.pdf'); window.releasePickerUpload('keep-two.pdf')")

    assert_selector "input[name='chat[attached_document_ids][]']", count: 2, visible: :all
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_includes draft_html, "Surviving draft text"
    assert_equal [ "keep-two.pdf" ], Document.joins(file_attachment: :blob).pluck("active_storage_blobs.filename")
    assert_equal 1, page.evaluate_script("window.pickerSourceRequests.length")
    assert_equal [ "keep-two.pdf" ], page.evaluate_script("window.pickerUploadEnds")
    assert_enqueued_jobs 1, only: AddDocumentJob
  end

  test "retry after a committed PDF registration response is lost reuses its document and index job" do
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    page.execute_script(<<~JS)
      const original = window.fetch;
      window.pickerRegistrationIds = [];
      window.fetch = async (input, options = {}) => {
        const response = await original(input, options);
        const url = new URL(input instanceof Request ? input.url : input, location.href);
        if (url.pathname === '/chat_sources') {
          const data = await response.clone().json();
          window.pickerRegistrationIds.push(data.id);
          if (window.pickerRegistrationIds.length === 1) throw new TypeError('Source response lost after commit');
        }
        return response;
      };
    JS
    start_held_pdf_uploads("ambiguous-registration.pdf")
    page.execute_script("window.releasePickerUpload('ambiguous-registration.pdf')")
    assert_text "Source response lost after commit"
    assert_selector "button[aria-label='Send'][disabled]"
    assert_equal 1, @second.documents.count
    assert_enqueued_jobs 1, only: AddDocumentJob

    click_on "Retry source"

    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "input[name='chat[attached_document_ids][]']", count: 2, visible: :all
    ids = page.evaluate_script("window.pickerRegistrationIds")
    assert_equal 2, ids.size
    assert_equal 1, ids.uniq.size
    assert_equal [ ids.first.to_s ], all("input[name='chat[attached_document_ids][]']", visible: :all).map(&:value).reject(&:blank?)
    assert_equal 1, @second.documents.count
    assert_equal 0, @first.documents.count
    assert_enqueued_jobs 1, only: AddDocumentJob
    assert_equal [ "ambiguous-registration.pdf" ], page.evaluate_script("window.pickerUploadEnds")
  end

  test "dashboard uploads file into the selected account" do
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    with_picker_pdf do |path|
      find("[data-dropzone-target='input']", visible: :all).set(path)
      assert_selector "[data-upload-status='success']"
      assert @second.documents.exists?(title: File.basename(path))
      assert_not @first.documents.exists?(title: File.basename(path))
      accept_confirm(/Saved sources remain/) { select "First team", from: "Account" }
      assert_no_selector "[data-upload-status]"
      assert @second.documents.exists?(title: File.basename(path))
    end
  end

  test "pending dashboard upload blocks switching and sending until complete" do
    install_dashboard_upload_gate
    with_picker_pdf do |path|
      find("[data-dropzone-target='input']", visible: :all).set(path)
      assert_selector "select[name='chat[account_id]'][disabled]"
      assert_selector "button[aria-label='Send'][disabled]"
      assert_source_submission_blocked
      assert_selector "[data-controller~='chat-account']:not([inert]) lexxy-editor:not([disabled])"
      find("lexxy-editor .lexxy-editor__content").send_keys("Edit while uploading")
      assert_includes draft_html, "Edit while uploading"
      page.execute_script("window.releasePickerUpload()")
      assert_selector "[data-upload-status='success']"
      assert_selector "select[name='chat[account_id]']:not([disabled])"
      assert_selector "button[aria-label='Send']:not([disabled])"
    end
  end

  test "failed dashboard uploads can retry and then unblock sending" do
    page.execute_script(<<~JS)
      const original = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(body) {
        XMLHttpRequest.prototype.send = original;
        queueMicrotask(() => this.onerror(new ProgressEvent('error')));
      };
    JS
    with_picker_pdf do |path|
      find("[data-dropzone-target='input']", visible: :all).set(path)
      assert_text "Upload failed. Retry or remove."
      assert_selector "button[aria-label='Send'][disabled]"
      find("[data-action='dropzone#retryFile']").click
      assert_selector "[data-upload-status='success']"
      assert_selector "button[aria-label='Send']:not([disabled])"
    end
  end

  test "dashboard retry after a committed response is lost reuses its document and index job" do
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    page.execute_script(<<~JS)
      const open = XMLHttpRequest.prototype.open;
      const send = XMLHttpRequest.prototype.send;
      window.pickerDashboardIds = [];
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.pickerUploadPath = new URL(url, location.href).pathname;
        return open.call(this, method, url, ...rest);
      };
      XMLHttpRequest.prototype.send = function(body) {
        if (this.pickerUploadPath === '/sources/documents') {
          const loaded = this.onload;
          this.onload = event => {
            if (this.status >= 200 && this.status < 300) {
              window.pickerDashboardIds.push(JSON.parse(this.responseText).id);
              if (window.pickerDashboardIds.length === 1) return this.onerror(new ProgressEvent('error'));
            }
            loaded.call(this, event);
          };
        }
        return send.call(this, body);
      };
    JS
    with_picker_pdf do |path|
      find("[data-dropzone-target='input']", visible: :all).set(path)
      assert_text "Upload failed. Retry or remove."
      assert_selector "button[aria-label='Send'][disabled]"
      assert_equal 1, @second.documents.count
      assert_enqueued_jobs 1, only: AddDocumentJob

      click_on "Retry"

      assert_selector "[data-upload-status='success']"
      assert_selector "button[aria-label='Send']:not([disabled])"
      ids = page.evaluate_script("window.pickerDashboardIds")
      assert_equal 2, ids.size
      assert_equal 1, ids.uniq.size
      assert_equal 1, @second.documents.count
      assert_equal 0, @first.documents.count
      assert_enqueued_jobs 1, only: AddDocumentJob
    end
  end

  test "queued dashboard uploads remain pending and removing an active upload starts the next" do
    install_dashboard_upload_gate
    page.execute_script("document.querySelector('[data-controller=dropzone]').dataset.dropzoneParallelLimitValue = '1'")
    with_picker_pdf do |first|
      with_picker_pdf do |removed|
        with_picker_pdf do |last|
          find("[data-dropzone-target='input']", visible: :all).set([ first, removed, last ])
          assert_selector "[data-upload-status='uploading']", count: 1
          assert_selector "[data-upload-status='pending']", count: 2
          assert_equal 1, page.evaluate_script("window.pickerDashboardUploads.length")
          find("[data-file-name]", text: File.basename(removed)).find("button[aria-label='Remove upload']").click
          assert_selector "[data-upload-status='pending']", count: 1
          assert_selector "button[aria-label='Send'][disabled]"
          find("[data-file-name]", text: File.basename(first)).find("button[aria-label='Remove upload']").click
          assert_selector "body[data-dashboard-uploads-held='2']"
          assert_equal [ true, false ], page.evaluate_script("window.pickerDashboardUploads.map(upload => upload.aborted)")
          assert_no_selector "[data-upload-status='pending']"
          assert_selector "button[aria-label='Send'][disabled]"
          page.execute_script("window.pickerDashboardUploads[0].error(); window.releasePickerUpload(1)")
          assert_selector "[data-upload-status='success']", count: 1
          assert_selector "button[aria-label='Send']:not([disabled])"
          assert_equal [ File.basename(last) ], @first.documents.pluck(:title)
          assert_enqueued_jobs 1, only: AddDocumentJob
        end
      end
    end
  end

  test "scoped dashboard reset aborts active uploads without starting queued uploads or reviving late rows" do
    install_dashboard_upload_gate
    page.execute_script("document.querySelector('[data-controller=dropzone]').dataset.dropzoneParallelLimitValue = '1'")
    with_picker_pdf do |first|
      with_picker_pdf do |second|
        find("[data-dropzone-target='input']", visible: :all).set([ first, second ])
        assert_selector "[data-upload-status]", count: 2
        page.execute_script("window.dispatchEvent(new CustomEvent('chat-account:reset', { detail: { root: document.createElement('div') } }))")
        assert_selector "[data-upload-status]", count: 2
        assert_selector "button[aria-label='Send'][disabled]"
        page.execute_script("window.dispatchEvent(new CustomEvent('chat-account:reset', { detail: { root: document.querySelector('[data-controller=chat-account]') } }))")
        assert_no_selector "[data-upload-status]"
        assert_selector "button[aria-label='Send']:not([disabled])"
        assert_selector "select[name='chat[account_id]']:not([disabled])"
        assert_equal [ true ], page.evaluate_script("window.pickerDashboardUploads.map(upload => upload.aborted)")
        assert_equal "", find("[data-dropzone-target='input']", visible: :all).value
        page.execute_script("window.pickerDashboardUploads[0].loaded(); window.pickerDashboardUploads[0].error(); window.releasePickerUpload()")
        assert_no_selector "[data-upload-status]"
        assert_equal 1, page.evaluate_script("window.pickerDashboardUploads.length")
        assert_equal 0, Document.count
        assert_no_enqueued_jobs only: AddDocumentJob
      end
    end
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
  end

  test "removing a pending dashboard publisher unlocks the remaining composer without starting queued uploads" do
    install_dashboard_upload_gate
    write_draft("Keep the remaining composer draft")
    page.execute_script("document.querySelector('[data-controller=dropzone]').dataset.dropzoneParallelLimitValue = '1'")
    with_picker_pdf do |active|
      with_picker_pdf do |queued|
        find("[data-dropzone-target='input']", visible: :all).set([ active, queued ])
        assert_selector "[data-upload-status='uploading']", count: 1
        assert_selector "[data-upload-status='pending']", count: 1
        assert_selector "select[name='chat[account_id]'][disabled]"
        assert_selector "button[aria-label='Send'][disabled]"
        page.execute_script(<<~JS)
          window.pickerRemainingRoot = document.querySelector('[data-controller=chat-account]');
          window.pickerRemainingForm = document.querySelector('#chat-form');
          window.pickerRemovedDropzone = document.querySelector('[data-controller=dropzone]');
          window.pickerRemovedDropzone.remove();
        JS

        assert_no_selector "[data-controller=dropzone]"
        assert page.evaluate_script("window.pickerRemainingRoot === document.querySelector('[data-controller=chat-account]') && window.pickerRemainingForm === document.querySelector('#chat-form')")
        assert_equal [ [ File.basename(active), true ] ], page.evaluate_script("window.pickerDashboardUploads.map(upload => [upload.body.get('document[file]').name, upload.aborted])")
        assert page.evaluate_script("window.pickerDashboardUploads.every(({ xhr }) => xhr.onload === null && xhr.onerror === null && xhr.onabort === null)")
        assert_selector "select[name='chat[account_id]']:not([disabled])"
        assert_selector "button[aria-label='Send']:not([disabled])"
        assert_includes draft_html, "Keep the remaining composer draft"
        assert_equal 0, Document.count
        assert_no_enqueued_jobs only: AddDocumentJob

        page.execute_script("window.pickerDashboardUploads[0].loaded(); window.pickerDashboardUploads[0].error(); window.releasePickerUpload()")

        assert_no_selector "[data-upload-status]"
        assert_equal 2, page.evaluate_script("window.pickerRemovedDropzone.querySelector('[data-dropzone-target=list]').children.length")
        assert_equal 0, page.evaluate_script("window.pickerRemovedDropzone.querySelectorAll('[data-upload-status=success], [data-upload-status=error]').length")
        assert_equal 1, page.evaluate_script("window.pickerDashboardUploads.length")
        assert_selector "select[name='chat[account_id]']:not([disabled])"
        assert_selector "button[aria-label='Send']:not([disabled])"
        assert_equal 0, Document.count
        assert_no_enqueued_jobs only: AddDocumentJob
      end
    end
  end

  test "form replacement prunes its old publisher while an attached dashboard upload stays blocking" do
    install_source_fetch_gate
    install_dashboard_upload_gate
    website_count = Website.count
    with_picker_pdf do |path|
      find("[data-dropzone-target='input']", visible: :all).set(path)
      dispatch_link("https://replaced-composer.example/reference")
      assert_selector "body[data-picker-source-held=true]"
      assert_selector "button[aria-label='Send'][disabled]"
      page.execute_script(<<~JS)
        window.pickerRemainingRoot = document.querySelector('[data-controller=chat-account]');
        window.pickerReplacedForm = document.querySelector('#chat-form');
        window.pickerReplacedForm.replaceWith(window.pickerReplacedForm.cloneNode(true));
      JS

      assert page.evaluate_script("window.pickerRemainingRoot === document.querySelector('[data-controller=chat-account]') && window.pickerReplacedForm !== document.querySelector('#chat-form')")
      assert page.evaluate_script("window.pickerSourceSignal.aborted")
      assert_selector "[data-upload-status='uploading']"
      assert_selector "select[name='chat[account_id]'][disabled]"
      assert_selector "button[aria-label='Send'][disabled]"

      page.execute_script("window.releasePickerUpload()")

      assert_selector "[data-upload-status='success']"
      assert_selector "select[name='chat[account_id]']:not([disabled])"
      assert_selector "button[aria-label='Send']:not([disabled])"
      page.execute_script("window.releasePickerSource()")
      assert_selector "body[data-picker-source-released=true]"
      assert_selector "input[name='chat[attached_website_ids][]']", count: 1, visible: :all
      assert_selector "button[aria-label='Send']:not([disabled])"
      assert_equal website_count, Website.count
      assert @first.documents.exists?(title: File.basename(path))
      assert_enqueued_jobs 1, only: AddDocumentJob
      assert_no_enqueued_jobs only: CrawlWebsiteUrlJob
    end
  end

  test "dashboard validation errors are safe removable rows that unblock Send" do
    name = "invalid\"'][<img src=x onerror=alert(1)>.exe"
    attempt_dashboard_upload(name, type: "application/zip")

    assert_selector "[data-upload-status='error'] [role='alert']", text: "Invalid file: #{name}"
    assert_no_selector "[data-dropzone-target='list'] img"
    assert_selector "button[aria-label='Send'][disabled]"
    click_on "Remove upload"
    assert_no_selector "[data-upload-status]"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_equal 0, Document.count
    assert_no_enqueued_jobs only: AddDocumentJob
  end

  test "invalid dashboard rows reserve their exact filename until removed" do
    install_dashboard_upload_gate
    page.execute_script("document.querySelector('[data-controller=dropzone]').dataset.dropzoneMaxFileSizeValue = '1'")
    attempt_dashboard_upload("report.pdf", size: 1024 * 1024 + 1)
    assert_selector "[data-upload-status='error']", count: 1
    assert_text "Invalid file: report.pdf"
    assert_selector "button[aria-label='Send'][disabled]"

    attempt_dashboard_upload("report.pdf")

    assert_selector "[data-file-name]", count: 1
    assert_selector "[data-upload-status='error']", count: 1
    assert_no_selector "[data-upload-status='pending'], [data-upload-status='uploading']"
    assert_empty page.evaluate_script("window.pickerDashboardUploads")
    assert_selector "button[aria-label='Send'][disabled]"
    assert_equal 0, Document.count
    assert_no_enqueued_jobs only: AddDocumentJob

    click_on "Remove upload"

    assert_no_selector "[data-upload-status]"
    assert_empty page.evaluate_script("window.pickerDashboardUploads")
    assert_selector "button[aria-label='Send']:not([disabled])"
    attempt_dashboard_upload("report.pdf")
    assert_selector "[data-upload-status='uploading']", count: 1
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"
    assert_equal [ [ "report.pdf", false ] ], page.evaluate_script("window.pickerDashboardUploads.map(upload => [upload.body.get('document[file]').name, upload.aborted])")

    page.execute_script("window.releasePickerUpload()")

    assert_selector "[data-upload-status='success']", count: 1
    assert_no_selector "[data-upload-status='pending'], [data-upload-status='error']"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_equal [ false ], page.evaluate_script("window.pickerDashboardUploads.map(upload => upload.aborted)")
    assert_equal [ "report.pdf" ], @first.documents.pluck(:title)
    assert_enqueued_jobs 1, only: AddDocumentJob
  end

  test "duplicate exact filenames in one dashboard FileList create one removable upload intent" do
    install_dashboard_upload_gate
    page.execute_script(<<~JS)
      const files = new DataTransfer();
      files.items.add(new File(['%PDF-1.4 first upload %%EOF'], 'report.pdf', { type: 'application/pdf' }));
      files.items.add(new File(['%PDF-1.4 duplicate upload %%EOF'], 'report.pdf', { type: 'application/pdf' }));
      const input = document.querySelector('[data-dropzone-target=input]');
      input.files = files.files;
      window.pickerDuplicateSelection = { nativeFileList: input.files instanceof FileList, names: [...input.files].map(file => file.name) };
      input.dispatchEvent(new Event('change', { bubbles: true }));
    JS
    assert_equal({ "nativeFileList" => true, "names" => [ "report.pdf", "report.pdf" ] }, page.evaluate_script("window.pickerDuplicateSelection"))
    assert_selector "[data-file-name]", count: 1
    assert_selector "[data-upload-status='uploading']", count: 1
    assert_no_selector "[data-upload-status='pending'], [data-upload-status='error']"
    assert_equal 1, page.evaluate_script("window.pickerDashboardUploads.length")
    assert_equal "%PDF-1.4 first upload %%EOF", page.evaluate_async_script("const done = arguments[0]; window.pickerDashboardUploads[0].body.get('document[file]').text().then(done)")
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"

    find("button[aria-label='Remove upload']").click

    assert_no_selector "[data-upload-status]"
    assert_equal [ [ "report.pdf", true ] ], page.evaluate_script("window.pickerDashboardUploads.map(upload => [upload.body.get('document[file]').name, upload.aborted])")
    assert page.evaluate_script("window.pickerDashboardUploads.every(({ xhr }) => xhr.onload === null && xhr.onerror === null && xhr.onabort === null)")
    page.execute_script("window.pickerDashboardUploads[0].loaded(); window.pickerDashboardUploads[0].error(); window.releasePickerUpload()")
    assert_no_selector "[data-upload-status]"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_equal 0, Document.count
    assert_no_enqueued_jobs only: AddDocumentJob

    page.execute_script("document.querySelector('[data-controller=dropzone]').dataset.dropzoneMaxFileSizeValue = '1'")
    attempt_dashboard_upload("report.pdf", size: 1024 * 1024 + 1)
    assert_selector "[data-upload-status='error']", count: 1
    assert_selector "button[aria-label='Send'][disabled]"
    page.execute_script("window.dispatchEvent(new CustomEvent('chat-account:reset', { detail: { root: document.querySelector('[data-controller=chat-account]') } }))")
    assert_no_selector "[data-upload-status]"
    assert_selector "button[aria-label='Send']:not([disabled])"

    attempt_dashboard_upload("report.pdf")

    assert_selector "[data-upload-status='uploading']", count: 1
    assert_equal [ true, false ], page.evaluate_script("window.pickerDashboardUploads.map(upload => upload.aborted)")
    assert page.evaluate_script("window.pickerDashboardUploads[0].body.get('document[upload_id]') !== window.pickerDashboardUploads[1].body.get('document[upload_id]')")
    page.execute_script("window.pickerDashboardUploads[0].loaded(); window.pickerDashboardUploads[0].error()")
    assert_selector "[data-upload-status='uploading']", count: 1
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"

    page.execute_script("window.releasePickerUpload(1)")

    assert_selector "[data-upload-status='success']", count: 1
    assert_no_selector "[data-upload-status='pending'], [data-upload-status='error']"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_equal 2, page.evaluate_script("window.pickerDashboardUploads.length")
    assert_equal [ "report.pdf" ], @first.documents.pluck(:title)
    assert_enqueued_jobs 1, only: AddDocumentJob
  end

  test "quoted dashboard filenames can upload remove and intentionally upload again" do
    with_picker_pdf("quoted'\"[<b>") do |path|
      2.times do |index|
        find("[data-dropzone-target='input']", visible: :all).set(path)
        assert_selector "[data-upload-status='success'] .file-name", text: File.basename(path)
        assert_no_selector "[data-dropzone-target='list'] b"
        find("button[aria-label='Remove upload']").click
        assert_no_selector "[data-upload-status]"
        assert_equal index + 1, @first.documents.where(title: File.basename(path)).count
      end
      assert_enqueued_jobs 2, only: AddDocumentJob
    end
  end

  test "generic dropzones without account context still upload into the default account" do
    visit sources_url
    assert_selector "[data-controller='dropzone']:not([data-dropzone-account-id-value])"
    page.execute_script(<<~JS)
      const send = XMLHttpRequest.prototype.send;
      window.pickerUploadAccounts = [];
      XMLHttpRequest.prototype.send = function(body) {
        if (body instanceof FormData) window.pickerUploadAccounts.push(body.get('document[account_id]'));
        return send.call(this, body);
      };
    JS
    2.times do |index|
      page.execute_script("document.querySelector('[data-controller=dropzone]').dataset.dropzoneAccountIdValue = ' '") if index == 1
      with_picker_pdf do |path|
        find("[data-dropzone-target='input']", visible: :all).set(path)
        assert_selector "[data-upload-status='success']", count: index + 1
        assert @first.documents.exists?(title: File.basename(path))
        assert_not @second.documents.exists?(title: File.basename(path))
      end
    end
    assert_equal [ nil, nil ], page.evaluate_script("window.pickerUploadAccounts")
  end

  test "dashboard HTTP and abort failures remain retryable without hiding validation failures" do
    page.execute_script(<<~JS)
      const send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(body) {
        XMLHttpRequest.prototype.send = send;
        body.delete('document[file]');
        return send.call(this, body);
      };
    JS
    with_picker_pdf do |path|
      find("[data-dropzone-target='input']", visible: :all).set(path)
      assert_text "Upload failed. Retry or remove."
      assert_equal 0, Document.count
      assert_no_enqueued_jobs only: AddDocumentJob
      install_dashboard_upload_gate
      click_on "Retry"
      assert_selector "[data-upload-status='uploading']"
      page.execute_script("window.pickerDashboardUploads[0].xhr.onabort(new ProgressEvent('abort'))")
      assert_selector "[data-upload-status='error']"
      assert_selector "button[aria-label='Send'][disabled]"
      click_on "Retry"
      assert_selector "body[data-dashboard-uploads-held='2']"
      page.execute_script("window.releasePickerUpload(1)")
      assert_selector "[data-upload-status='success']"
      assert_selector "button[aria-label='Send']:not([disabled])"
      assert_equal 1, Document.count
      assert_enqueued_jobs 1, only: AddDocumentJob
    end
  end

  test "dashboard navigation rejects new files retries and disconnected old input events" do
    page.execute_script(<<~JS)
      const send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(body) {
        XMLHttpRequest.prototype.send = send;
        queueMicrotask(() => this.onerror(new ProgressEvent('error')));
      };
    JS
    with_picker_pdf do |path|
      find("[data-dropzone-target='input']", visible: :all).set(path)
      assert_selector "[data-upload-status='error']"
      install_dashboard_upload_gate
      hold_account_switch
      page.execute_script("window.pickerOldUploadInput = document.querySelector('[data-dropzone-target=input]')")
      accept_confirm(/Saved sources remain/) { select "Research team", from: "Account" }
      assert_selector "body[data-account-switch-held=true]"
      page.execute_script("document.querySelector('[data-action=\"dropzone#retryFile\"]').click()")
      attempt_dashboard_upload("navigation.pdf")
      assert_selector "[data-upload-status='error']", count: 1
      assert_empty page.evaluate_script("window.pickerDashboardUploads")
      page.execute_script("window.releaseAccountSwitch()")
      assert_selector "select option[selected][value='#{@second.id}']"
      attempt_dashboard_upload("disconnected.pdf", old_input: true)
      assert_no_selector "[data-upload-status]"
      assert_empty page.evaluate_script("window.pickerDashboardUploads")
      assert_equal 0, Document.count
      assert_no_enqueued_jobs only: AddDocumentJob
    end
  end

  test "cached dashboard previews reject file entry until the fresh account renders" do
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_no_selector "html[aria-busy='true']"
    select "First team", from: "Account"
    assert_selector "select option[selected][value='#{@first.id}']"
    assert_no_selector "html[aria-busy='true']"
    install_dashboard_upload_gate
    hold_account_switch
    select "Research team", from: "Account"
    assert_selector "html[data-turbo-preview][data-account-switch-held=true]"

    attempt_dashboard_upload("preview.pdf")

    assert_no_selector "[data-upload-status]"
    assert_empty page.evaluate_script("window.pickerDashboardUploads")
    assert_equal 0, Document.count
    page.execute_script("window.releaseAccountSwitch()")
    assert_no_selector "html[data-turbo-preview]"
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_no_enqueued_jobs only: AddDocumentJob
  end

  private
    def attempt_dashboard_upload(name, type: "application/pdf", old_input: false, size: nil)
      page.execute_script(<<~JS, name, type, old_input, size)
        const input = arguments[2] ? window.pickerOldUploadInput : document.querySelector('[data-dropzone-target=input]');
        const files = new DataTransfer();
        const content = arguments[3] === null ? '%PDF-1.4 %%EOF' : new Uint8Array(arguments[3]);
        files.items.add(new File([content], arguments[0], { type: arguments[1] }));
        input.files = files.files;
        input.dispatchEvent(new Event('change', { bubbles: true }));
      JS
    end

    def with_picker_pdf(prefix = "chat-account")
      Tempfile.create([ prefix, ".pdf" ]) do |file|
        file.write("%PDF-1.4\n% Upload-registration fixture; no parser is run.\n%%EOF\n")
        file.flush
        yield file.path
      end
    end

    def install_dashboard_upload_gate
      page.execute_script(<<~JS)
        const open = XMLHttpRequest.prototype.open;
        const send = XMLHttpRequest.prototype.send;
        const abort = XMLHttpRequest.prototype.abort;
        window.pickerDashboardUploads = [];
        XMLHttpRequest.prototype.open = function(method, url, ...rest) {
          this.pickerUploadPath = new URL(url, location.href).pathname;
          return open.call(this, method, url, ...rest);
        };
        XMLHttpRequest.prototype.send = function(body) {
          if (this.pickerUploadPath !== '/sources/documents') return send.call(this, body);
          this.pickerDashboardUpload = { xhr: this, body, loaded: this.onload, error: this.onerror, aborted: false };
          window.pickerDashboardUploads.push(this.pickerDashboardUpload);
          document.body.dataset.dashboardUploadsHeld = window.pickerDashboardUploads.length;
        };
        XMLHttpRequest.prototype.abort = function() {
          if (this.pickerDashboardUpload) this.pickerDashboardUpload.aborted = true;
          return abort.call(this);
        };
        window.releasePickerUpload = (index = 0) => {
          const upload = window.pickerDashboardUploads[index];
          if (!upload.aborted) send.call(upload.xhr, upload.body);
        };
      JS
    end

    def start_held_pdf_uploads(*filenames, reverse_requests: false)
      page.execute_script(<<~JS, filenames, reverse_requests)
        const filenames = arguments[0];
        const reverseRequests = arguments[1];
        window.pickerUploads = [];
        window.pickerUploadEnds = [];
        document.querySelector('lexxy-editor').addEventListener('lexxy:upload-end', event => window.pickerUploadEnds.push(event.detail.file.name));
        const open = XMLHttpRequest.prototype.open;
        const send = XMLHttpRequest.prototype.send;
        const abort = XMLHttpRequest.prototype.abort;
        const storageFilenames = new Map();
        const blobRequests = new Map();
        const blobOrder = [...filenames].reverse();
        const sendNextBlobRequest = () => {
          const request = blobRequests.get(blobOrder.shift());
          if (request) send.call(request.xhr, request.body);
        };
        XMLHttpRequest.prototype.open = function(method, url, ...args) {
          const requestUrl = new URL(url, location.href);
          this.pickerStorage = method.toUpperCase() === 'PUT' && requestUrl.pathname.startsWith('/rails/active_storage/disk/');
          this.pickerBlobRecord = method.toUpperCase() === 'POST' && requestUrl.pathname === '/rails/active_storage/direct_uploads';
          this.pickerStorageUrl = requestUrl.href;
          if (this.pickerBlobRecord) {
            // Read the real response before Active Storage consumes direct_upload.
            this.addEventListener('load', () => {
              if (this.status >= 200 && this.status < 300) {
                const blob = this.response;
                storageFilenames.set(new URL(blob.direct_upload.url, location.href).href, blob.filename);
              }
            });
          }
          return open.call(this, method, url, ...args);
        };
        XMLHttpRequest.prototype.send = function(body) {
          if (this.pickerBlobRecord && reverseRequests) {
            blobRequests.set(JSON.parse(body).blob.filename, { xhr: this, body });
            // Make PUT arrival order the reverse of file insertion, without sleeps.
            if (blobRequests.size === filenames.length) sendNextBlobRequest();
            return;
          }
          if (!this.pickerStorage) return send.call(this, body);
          const upload = { xhr: this, body, filename: storageFilenames.get(this.pickerStorageUrl), aborted: false };
          this.pickerUpload = upload;
          window.pickerUploads.push(upload);
          document.body.dataset.pickerUploadsHeld = window.pickerUploads.length;
          if (reverseRequests) sendNextBlobRequest();
        };
        XMLHttpRequest.prototype.abort = function() {
          if (this.pickerUpload) this.pickerUpload.aborted = true;
          return abort.call(this);
        };
        window.releasePickerUpload = filename => {
          const upload = window.pickerUploads.find(upload => upload.filename === filename);
          if (!upload) throw new Error(`No held upload for ${filename}`);
          if (!upload.aborted) send.call(upload.xhr, upload.body);
        };
        const files = new DataTransfer();
        for (const name of filenames) files.items.add(new File(['%PDF-1.4 %%EOF'], name, { type: 'application/pdf' }));
        document.querySelector('lexxy-editor .lexxy-editor__content').dispatchEvent(new ClipboardEvent('paste', { clipboardData: files, bubbles: true, cancelable: true }));
      JS
      assert_selector "body[data-picker-uploads-held='#{filenames.size}']"
      assert_selector "lexxy-editor figure progress", count: filenames.size
    end

    def observe_source_requests
      page.execute_script(<<~JS)
        const original = window.fetch;
        window.pickerSourceRequests = [];
        window.pickerSourceResponses = [];
        window.fetch = (input, options = {}) => {
          const url = new URL(input instanceof Request ? input.url : input, location.href);
          const response = original(input, options);
          if (url.pathname === '/chat_sources') {
            window.pickerSourceRequests.push(JSON.parse(options.body));
            window.pickerSourceResponses.push(response.then(result => result.clone().text()));
          }
          return response;
        };
      JS
    end

    def assert_queued_sources_blocked(url)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n%%EOF"), filename: "queued-account.pdf", content_type: "application/pdf")
      counts = [ Website.count, Document.count ]
      page.evaluate_async_script(<<~JS, url, blob.attachable_sgid)
        const [url, sgid, done] = arguments;
        const editor = document.querySelector('lexxy-editor');
        const file = new File(['%PDF-1.4'], 'queued-account.pdf', { type: 'application/pdf' });
        editor.dispatchEvent(new CustomEvent('lexxy:insert-link', { detail: { url }, bubbles: true }));
        editor.dispatchEvent(new CustomEvent('lexxy:upload-start', { detail: { file }, bubbles: true }));
        editor.value = '<action-text-attachment sgid="' + sgid + '" content-type="application/pdf" filename="queued-account.pdf"></action-text-attachment>';
        editor.dispatchEvent(new CustomEvent('lexxy:upload-end', { detail: { file, error: null }, bubbles: true }));
        requestAnimationFrame(() => Promise.allSettled(window.pickerSourceResponses).then(() => requestAnimationFrame(done)));
      JS

      assert_equal counts, [ Website.count, Document.count ], "Queued source events must not save into an unresolved account"
      assert_empty page.evaluate_script("window.pickerSourceRequests")
      assert_selector "input[name*='[attached_website_ids]']", count: 1, visible: :all
      assert_selector "input[name*='[attached_document_ids]']", count: 1, visible: :all
      assert_no_enqueued_jobs only: [ CrawlWebsiteUrlJob, AddDocumentJob, ChatResponseJob ]
    end

    def dispatch_link(url)
      page.execute_script("document.querySelector('lexxy-editor').dispatchEvent(new CustomEvent('lexxy:insert-link', { detail: { url: arguments[0] }, bubbles: true }))", url)
    end

    def install_source_fetch_gate(ignore_abort: false)
      page.execute_script(<<~JS, ignore_abort)
        const ignoreAbort = arguments[0];
        const original = window.fetch;
        window.fetch = (input, options = {}) => {
          const url = new URL(input instanceof Request ? input.url : input, location.href);
          if (url.pathname !== '/chat_sources') return original(input, options);
          window.pickerSourceSignal = options.signal;
          return new Promise((resolve, reject) => {
            window.releasePickerSource = () => {
              window.fetch = original;
              original(input, ignoreAbort ? { ...options, signal: undefined } : options).then(resolve, reject).finally(() => {
                requestAnimationFrame(() => { document.body.dataset.pickerSourceReleased = 'true'; });
              });
            };
            document.body.dataset.pickerSourceHeld = 'true';
          });
        };
      JS
    end

    def assert_source_submission_blocked
      submission_counts = page.evaluate_script(<<~JS)
        (() => {
          const form = document.querySelector('#chat-form');
          const attempts = [];
          let escaped = 0;
          form.addEventListener('submit', event => attempts.push(event), { capture: true });
          document.addEventListener('submit', event => { if (event.target === form) escaped++; });
          form.querySelector("button[aria-label='Send']").click();
          form.querySelector('.lexxy-editor__content').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
          form.requestSubmit();
          return [attempts.length, escaped, attempts.every(event => event.defaultPrevented)];
        })()
      JS
      assert_equal [ 2, 0, true ], submission_counts
      assert_no_enqueued_jobs only: ChatResponseJob
    end

    def hold_account_switch
      page.execute_script(<<~JS, @second.id.to_s)
        const accountId = arguments[0]
        const originalFetch = window.fetch
        window.accountSwitchPostCount = 0
        let held = false
        window.fetch = async (input, options = {}) => {
          const url = new URL(input instanceof Request ? input.url : input, window.location.href)
          const method = (options.method || "GET").toUpperCase()
          if (method === "POST" && url.pathname === "/chats") window.accountSwitchPostCount++
          const response = await originalFetch(input, options)
          if (!held && method === "GET" && url.searchParams.get("account_id") === accountId) {
            held = true
            return new Promise((resolve, reject) => {
              window.releaseAccountSwitch = () => resolve(response)
              window.failAccountSwitch = () => reject(new TypeError("Account switch connection failed"))
              document.body.dataset.accountSwitchHeld = "true"
              document.documentElement.dataset.accountSwitchHeld = "true"
            })
          }
          return response
        }
      JS
    end

    def write_draft(text)
      assert_selector "lexxy-editor .lexxy-editor__content"
      editor = find("lexxy-editor")
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new CustomEvent('lexxy:change', { bubbles: true }))", editor, "<p>#{text}</p>")
    end

    def draft_html
      page.evaluate_script("document.querySelector('lexxy-editor').value")
    end

    def browser_skills
      page.evaluate_script("JSON.parse(document.querySelector('[data-composer-skills-value]').dataset.composerSkillsValue).map(skill => skill.name)")
    end

    def browser_website_ids
      page.evaluate_script("Array.from(document.querySelectorAll('input[name=\"chat[attached_website_ids][]\"]')).map(input => input.value).filter(Boolean)")
    end
end
