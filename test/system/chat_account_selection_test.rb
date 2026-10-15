require "application_system_test_case"
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

  test "PDF upload lifecycle stays pending until its SGID is registered" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n%%EOF"), filename: "browser-account.pdf", content_type: "application/pdf")
    select "Research team", from: "Account"
    assert_selector "select option[selected][value='#{@second.id}']"
    install_source_fetch_gate
    page.execute_script(<<~JS)
      const editor = document.querySelector('lexxy-editor');
      window.pickerPDF = new File(['%PDF-1.4'], 'browser-account.pdf', { type: 'application/pdf' });
      editor.dispatchEvent(new CustomEvent('lexxy:upload-start', { detail: { file: window.pickerPDF }, bubbles: true }));
    JS
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"

    page.execute_script(<<~JS, blob.attachable_sgid)
      const editor = document.querySelector('lexxy-editor');
      editor.dispatchEvent(new CustomEvent('lexxy:upload-end', { detail: { file: window.pickerPDF, error: null }, bubbles: true }));
      const sgid = arguments[0];
      requestAnimationFrame(() => requestAnimationFrame(() => {
        editor.value = '<action-text-attachment sgid="' + sgid + '" content-type="application/pdf" filename="browser-account.pdf"></action-text-attachment>';
      }));
    JS

    assert_selector "body[data-picker-source-held=true]"
    assert_selector "button[aria-label='Send'][disabled]"
    assert_selector "select[name='chat[account_id]'][disabled]"
    page.execute_script("window.releasePickerSource()")
    assert_selector "input[name='chat[attached_document_ids][]']", count: 2, visible: :all
    assert_equal @second.id, Document.joins(:file_attachment).where(active_storage_attachments: { blob_id: blob.id }).last.account_id
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

  private
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
end
