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
    find("lexxy-editor .lexxy-editor__content").send_keys(:enter)
    assert_equal [ 3, 0 ], page.evaluate_script("[window.accountSwitchSubmissionAttempts, window.accountSwitchEscapedSubmissions]")

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
    assert_current_path user_root_path

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_not_includes draft_html, "Keep this canceled navigation draft"
  end

  test "a failed account switch reports the error and restores the old account and draft for retry" do
    write_draft("Keep this failed navigation draft")
    hold_account_switch

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_selector "body[data-account-switch-held=true]"

    accept_alert(/Could not change account/) { page.execute_script("window.failAccountSwitch()") }

    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
    assert_includes draft_html, "Keep this failed navigation draft"
    assert_selector "button[aria-label='Send']:not([disabled])"
    assert_current_path user_root_path

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_not_includes draft_html, "Keep this failed navigation draft"
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

  private
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
