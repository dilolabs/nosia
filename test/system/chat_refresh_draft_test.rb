require "application_system_test_case"
require "tempfile"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class ChatRefreshDraftSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include OrbiteBrowserChecks
  include ActionView::RecordIdentifier

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
    orbite_viewport(1400, 1000)
    visit chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    page.execute_script(<<~JS)
      window.refreshDraftEditor = document.querySelector('lexxy-editor')
      window.refreshDraftEvents = []
      for (const type of ['turbo:before-cache', 'turbo:before-render', 'turbo:render', 'lexxy:initialize']) {
        document.addEventListener(type, event => {
          const editor = document.querySelector('lexxy-editor')
          window.refreshDraftEvents.push({ event: type, method: event.detail?.renderMethod,
            sameEditor: editor === window.refreshDraftEditor, value: editor?.value,
            busy: document.querySelector('[data-chat-followup]')?.dataset.generationBusy })
        })
      }
    JS
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(*@original_size) if @original_size
  end

  %w[focused blurred].each do |focus|
    test "same chat morph retains native bold link serialization while #{focus}" do
      content = find("lexxy-editor .lexxy-editor__content")
      content.send_keys("Native formatted draft", [ :control, "a" ])
      find("summary[aria-label=Formatting]").send_keys(:enter)
      find("lexxy-toolbar button[name=bold]").click
      assert_selector "lexxy-editor strong", text: "Native formatted draft"
      content.send_keys([ :control, "a" ], [ :control, "k" ])
      assert_selector "lexxy-link-dropdown input[type=url]:focus"
      find("lexxy-link-dropdown input[type=url]").send_keys(websites(:picker_second_website).url, :enter)
      assert_selector "lexxy-editor a[href='#{websites(:picker_second_website).url}'] strong", text: "Native formatted draft"
      if focus == "focused"
        content.click
        assert_selector "lexxy-editor .lexxy-editor__content:focus"
      else
        find("#workspace-history-rail-trigger").click
        assert_selector "#workspace-history-rail-trigger:focus"
      end
      before = record_draft("formatted-#{focus}-before")
      assert_equal before.fetch("value"), before.fetch("submitted")

      refresh_draft_page

      after = record_draft("formatted-#{focus}-after")
      assert_equal before.fetch("value"), after.fetch("value"), after.to_json
      assert_equal before.fetch("submitted"), after.fetch("submitted"), after.to_json
      assert after.fetch("sameEditor"), after.to_json
      assert_selector "lexxy-editor a[href='#{websites(:picker_second_website).url}'] strong", text: "Native formatted draft"
      assert_no_enqueued_jobs only: [ ChatResponseJob, CrawlWebsiteUrlJob, AddDocumentJob ]
    end
  end

  test "native typing during a same chat refresh request preserves the latest serialized draft" do
    content = find("lexxy-editor .lexxy-editor__content")
    content.send_keys("Draft before request")
    record_draft("typing-request-before")
    # Controlled network-latency fixture, not a held renderer or a measurement
    # of a physical network. The actual GET and native input remain unmodified.
    page.driver.browser.execute_cdp("Network.enable")
    network_enabled = true
    page.driver.browser.execute_cdp("Network.emulateNetworkConditions",
      offline: false, latency: 2000, downloadThroughput: -1, uploadThroughput: -1)
    page.execute_script(<<~JS)
      const root = document.querySelector('.n-chat-workspace--saved')
      const editor = root.querySelector('lexxy-editor'), form = editor.form
      window.typingRefreshEvents = []
      for (const type of ['turbo:before-visit', 'beforeinput', 'input', 'lexxy:change',
        'turbo:before-cache', 'turbo:before-render', 'turbo:render', 'lexxy:initialize']) {
        document.addEventListener(type, event => {
          const current = document.querySelector('lexxy-editor')
          window.typingRefreshEvents.push({ event: type, time: performance.now(), trusted: event.isTrusted,
            value: current?.value, submitted: current?.form && new FormData(current.form).get(current.getAttribute('name')),
            sameEditor: current === editor, sameForm: current?.form === form,
            sameRoot: document.querySelector('.n-chat-workspace--saved') === root,
            preview: document.documentElement.hasAttribute('data-turbo-preview'), method: event.detail?.renderMethod })
        }, { passive: true })
      }
      Turbo.cache.clear()
      document.documentElement.removeAttribute('data-typing-refreshed')
      document.addEventListener('turbo:render', event => {
        document.documentElement.dataset.typingRefreshed = event.detail.renderMethod
      }, { once: true })
      Turbo.visit(location.href, { action: 'replace' })
    JS
    content.send_keys(" while loading")
    expected = "<p>Draft before request while loading</p>"
    interval = page.evaluate_script("window.typingRefreshEvents")
    in_flight = draft_sample
    orbite_record("typing-request-in-flight", { latencyMs: 2000, trace: interval, native: in_flight }, screenshot: true)
    visit_event = interval.find { |event| event.fetch("event") == "turbo:before-visit" }
    change = interval.find { |event| event.fetch("event") == "lexxy:change" && event.fetch("value") == expected }
    refute_nil visit_event, interval.to_json
    refute_nil change, interval.to_json
    assert_operator visit_event.fetch("time"), :<, change.fetch("time"), interval.to_json
    assert interval.any? { |event| event.fetch("event") == "beforeinput" && event.fetch("trusted") && event.fetch("time") > visit_event.fetch("time") && event.fetch("time") <= change.fetch("time") }, interval.to_json
    refute interval.any? { |event| %w[turbo:before-cache turbo:before-render].include?(event.fetch("event")) }, interval.to_json
    assert_equal expected, in_flight.fetch("value")
    assert_equal expected, in_flight.fetch("submitted")
    refute in_flight.fetch("disabled")
    refute in_flight.fetch("inert")

    assert_selector "html[data-typing-refreshed=morph]"
    assert_selector "lexxy-editor[connected]"
    orbite_settle
    after = record_draft("typing-request-after")
    trace = page.evaluate_script("window.typingRefreshEvents")
    orbite_record("typing-request-lifecycle", { latencyMs: 2000, trace: trace, native: after })
    cache = trace.find { |event| event.fetch("event") == "turbo:before-cache" }
    render = trace.find { |event| event.fetch("event") == "turbo:before-render" }
    initialized = trace.find { |event| event.fetch("event") == "lexxy:initialize" }
    [ cache, render, initialized ].each { |event| refute_nil event, trace.to_json }
    assert_operator change.fetch("time"), :<, cache.fetch("time"), trace.to_json
    assert_operator cache.fetch("time"), :<=, render.fetch("time"), trace.to_json
    assert_operator render.fetch("time"), :<, initialized.fetch("time"), trace.to_json
    assert_equal "morph", render.fetch("method")
    assert_equal expected, render.fetch("value")
    assert trace.all? { |event| event.fetch("sameEditor") && event.fetch("sameForm") && event.fetch("sameRoot") && !event.fetch("preview") }, trace.to_json
    assert_equal expected, after.fetch("value"), after.to_json
    assert_equal expected, after.fetch("submitted"), after.to_json
    assert_no_enqueued_jobs only: [ ChatResponseJob, AddDocumentJob, CrawlWebsiteUrlJob ]
  ensure
    if network_enabled
      page.driver.browser.execute_cdp("Network.emulateNetworkConditions",
        offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
      page.driver.browser.execute_cdp("Network.disable")
      orbite_record("typing-network-cleanup", { controlledLatencyMs: 2000, resetLatencyMs: 0, networkDisabled: true })
    end
  end

  test "remote generation morph retains native text without bypassing locks or the Stop owner" do
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep the remote draft")
    before = record_draft("idle-before-remote-generation")
    @chat.start_generation!

    refresh_draft_page

    assert_selector "form[data-chat-followup][data-generation-busy=true] lexxy-editor[disabled][inert]"
    assert_selector "[data-chat-account-target=editingTools][inert][aria-disabled=true]"
    assert_button "Attach PDF", disabled: true, enable_aria_label: true
    assert_no_selector "button[aria-label=Send]:not([disabled])", visible: :all
    stop = find("button[aria-label='Stop generating']")
    assert_equal dom_id(@chat, :composer_stop), stop["form"]
    assert_selector "form##{dom_id(@chat, :composer_stop)}[action='#{stop_chat_path(@chat)}'][data-turbo-frame=_top]", visible: :all
    assert_no_selector "form form", visible: :all
    orbite_assert_reachable(".n-composer-stop")
    locked = record_draft("remote-generation-locked")
    assert_equal before.fetch("value"), locked.fetch("value"), locked.to_json
    assert_nil locked.fetch("submitted"), "Native disabled form-associated editor must not submit its draft"
    page.driver.browser.action.move_to(find("lexxy-editor .lexxy-editor__content").native).click.send_keys(" forbidden typing", :enter).perform
    assert_equal locked.fetch("value"), draft_sample.fetch("value")
    assert_no_enqueued_jobs only: ChatResponseJob

    stop.click
    assert_selector "button[aria-label=Send]:not([disabled])"
    assert_selector "lexxy-editor[connected]:not([disabled]):not([inert])"
    assert_no_selector ".n-composer-stop", visible: :all
    refute_predicate @chat.reload, :generating?
    unlocked = record_draft("native-Stop-unlocked")
    refresh_draft_page
    after = record_draft("idle-after-Stop-refresh")
    assert_equal unlocked.fetch("value"), after.fetch("value")
    assert_equal after.fetch("value"), after.fetch("submitted")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "a successful own submission is never restored by the next same chat morph" do
    find("lexxy-editor .lexxy-editor__content").send_keys("This draft was actually sent")
    record_draft("own-submission-before")
    assert_enqueued_jobs 1, only: ChatResponseJob do
      click_button "Send", enable_aria_label: true
      assert_selector "form[data-generation-busy=true] lexxy-editor[disabled][inert]"
    end
    assert_equal "This draft was actually sent", @chat.messages.user.order(:created_at).last.content.strip
    refute_includes draft_sample.fetch("value"), "This draft was actually sent"
    record_draft("own-submission-cleared")
    @chat.stop_generation!
    Current.reset

    refresh_draft_page

    assert_selector "button[aria-label=Send]:not([disabled])"
    after = record_draft("own-submission-not-resurrected")
    refute_includes after.fetch("value"), "This draft was actually sent"
    assert_equal after.fetch("value"), after.fetch("submitted")
    assert_enqueued_jobs 1, only: ChatResponseJob
  end

  test "saved conversation navigation and Back Forward never carry a refresh draft into another account" do
    find("lexxy-editor .lexxy-editor__content").send_keys("Do not carry this saved draft")
    record_draft("saved-navigation-before")
    other = workspace(:chats, :workspace_first_chat)
    within("[data-history-chat='#{other.id}']") { click_link "First account question" }
    assert_current_path chat_path(other)
    assert_selector "lexxy-editor[connected]"
    assert_selector "[data-chat-account-readonly]", text: @first.name
    assert_no_carried_draft("saved-navigation-other")
    page.go_back
    assert_current_path chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    assert_no_carried_draft("saved-navigation-back")
    page.go_forward
    assert_current_path chat_path(other)
    assert_selector "lexxy-editor[connected]"
    assert_no_carried_draft("saved-navigation-forward")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "a failed native PDF registration stays blocking and is not revived by text handoff" do
    find("lexxy-editor .lexxy-editor__content").send_keys("Source-bearing draft is not eligible")
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (input, options = {}) => {
        const url = new URL(input instanceof Request ? input.url : input, location.href)
        if (url.pathname === '/chat_sources') return Promise.resolve(new Response(JSON.stringify({ error: 'Local registration refused' }),
          { status: 422, headers: { 'Content-Type': 'application/json' } }))
        return original(input, options)
      }
    JS
    Tempfile.create([ "refresh-source-", ".pdf" ], ENV.fetch("EVIDENCE", Dir.tmpdir)) do |file|
      file.write("%PDF-1.4\n%%EOF")
      file.flush
      attach_file(file.path) { click_button "Attach PDF", enable_aria_label: true }
      assert_selector "[data-composer-sources-target=errors]", text: "Local registration refused"
      assert_button "Send", disabled: true, enable_aria_label: true
      assert_includes draft_sample.fetch("value"), "action-text-attachment"
      record_draft("failed-native-source-before", content: false)

      refresh_draft_page

      assert_button "Send", disabled: true, enable_aria_label: true
      sample = record_draft("failed-native-source-not-revived", content: false)
      refute sample.fetch("hasAttachment")
      assert_empty sample.fetch("sourceIds")
      refute_includes draft_sample.fetch("value"), "Source-bearing draft is not eligible"
      other = workspace(:chats, :workspace_first_chat)
      within("[data-history-chat='#{other.id}']") { click_link "First account question" }
      assert_current_path chat_path(other)
      assert_selector "button[aria-label=Send]:not([disabled])"
      assert_no_carried_draft("failed-source-other-account")
    end
    assert_no_enqueued_jobs only: [ ChatResponseJob, AddDocumentJob, CrawlWebsiteUrlJob ]
  end

  private
    def refresh_draft_page
      page.execute_script(<<~JS)
        document.documentElement.removeAttribute('data-draft-refreshed')
        document.addEventListener('turbo:render', event => {
          document.documentElement.dataset.draftRefreshed = event.detail.renderMethod
        }, { once: true })
        Turbo.visit(location.href, { action: 'replace' })
      JS
      assert_selector "html[data-draft-refreshed=morph]"
      assert_selector "lexxy-editor[connected]"
      orbite_settle
    end

    def draft_sample
      page.evaluate_script(<<~JS)
        (() => {
          const editor = document.querySelector('lexxy-editor'), form = editor.form
          return { value: editor.value, submitted: new FormData(form).get(editor.getAttribute('name')),
            sameEditor: editor === window.refreshDraftEditor, busy: form.dataset.generationBusy,
            disabled: editor.hasAttribute('disabled'), inert: editor.inert,
            hasAttachment: !!editor.querySelector('action-text-attachment, figure, img'),
            sourceIds: [...form.querySelectorAll('input[name*="[attached_website_ids]"], input[name*="[attached_document_ids]"]')].map(input => input.value).filter(Boolean),
            hiddenContentCount: form.querySelectorAll('input[type=hidden][name="message[content]"]').length,
            events: window.refreshDraftEvents }
        })()
      JS
    end

    def record_draft(label, content: true)
      sample = draft_sample
      evidence = content ? sample : sample.except("value", "submitted", "events")
      orbite_record(label, evidence, screenshot: true)
      sample
    end

    def assert_no_carried_draft(label)
      sample = record_draft(label)
      refute_includes sample.fetch("value"), "Do not carry this saved draft"
      refute_includes sample.fetch("value"), "Source-bearing draft is not eligible"
      assert_empty sample.fetch("sourceIds")
      refute sample.fetch("hasAttachment")
      assert_equal sample.fetch("value"), sample.fetch("submitted")
    end
end
