require "application_system_test_case"
require_relative "../support/orbite_browser_checks"

class NotesWorkspaceBrowserTest < ApplicationSystemTestCase
  include OrbiteBrowserChecks

  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users, :note_folders, :notes

  setup do
    @account = accounts(:picker_first)
    @note = notes(:field_notes)
    visit root_path
    fill_in "email", with: users(:picker_owner).email
    fill_in "password", with: "picker-password-123"
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1400)
  end

  test "the medium layout keeps its list and editor, and moves one sidebar into a keyboard dialog" do
    orbite_viewport(960, 850)
    visit account_notes_workspace_path(@account)
    assert_selector "[data-notes-list]"
    assert_selector ".n-notes-reader"
    assert_no_selector "[data-notes-sidebar]"

    trigger = find(".n-notes-folder-trigger")
    trigger.send_keys(:enter)
    assert_selector "#notes-folders-dialog:modal [data-notes-sidebar]"
    assert_selector "[data-notes-sidebar]", count: 1, visible: :all
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#notes-folders-dialog[open]", visible: :all
    assert_equal "n-notes-button n-notes-folder-trigger", page.evaluate_script("document.activeElement.className")

    trigger.click
    assert_selector "#notes-folders-dialog:modal"
    orbite_viewport(1280, 850)
    assert_no_selector "#notes-folders-dialog[open]", visible: :all
    assert_selector ".n-notes-sidebar-slot [data-notes-sidebar]"
    assert_selector "[data-notes-list]"
    assert_selector ".n-notes-reader"
  end

  test "on mobile the real Lexxy form saves and Back returns to the filtered list" do
    orbite_viewport(375, 850)
    visit notes_entry_path
    assert_selector "[data-notes-sidebar]"
    assert_no_selector "[data-notes-list]"
    fill_in "Search all notes in this account", with: "Interview outline"
    click_on "Search"
    assert_selector "[data-notes-screen='list']"
    assert_no_selector "[data-notes-sidebar]"
    click_on "Field notes"
    assert_selector "[data-notes-screen='editor'] lexxy-editor[connected][attachments='false']"
    assert_no_selector "[data-notes-list]"
    fill_in "Title (optional)", with: "Browser title"
    find(".lexxy-editor__content").send_keys(:end, " revised")
    click_on "Save note"
    assert_field "Title (optional)", with: "Browser title"
    assert_text "Interview outline revised"
    click_on "Back to list"
    assert_selector "[data-notes-screen='list']"
    assert_field "Search all notes in this account", with: "Interview outline"
    assert_text "Browser title"
    assert_equal [ "Browser title", "Interview outline revised", 2 ], @note.reload.values_at(:title, :body_text, :content_revision)
  end

  test "saving leaves the tablet drawer semantics and opened note actions intact" do
    orbite_viewport(768, 850)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-folder-trigger[aria-haspopup='dialog']"
    summary = find(".n-notes-editor-actions summary")
    summary.click
    fill_in "Title (optional)", with: "Updated from tablet"
    assert_save_status "Saved"
    assert_selector ".n-notes-editor-actions[open]"
    assert_selector ".n-notes-folder-trigger[aria-haspopup='dialog']"
  end

  test "medium screens can still reach the folder pane without scripts" do
    orbite_viewport(960, 850)
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit account_notes_workspace_path(@account)
    assert_no_selector "[data-notes-sidebar]"
    click_on "Folders and tags"
    assert_selector "[data-notes-sidebar]"
    assert_no_selector "#notes-folders-dialog[open]", visible: :all
    within "[data-notes-sidebar]" do
      click_on "All Notes"
    end
    assert_selector "[data-notes-list]", text: "Field notes"
    assert_no_selector "[data-notes-sidebar]"
  end

  test "Turbo Back reloads the same search after another tab trashes a result" do
    @note.edit_content!(expected_revision: 1, title: @note.title, body_html: "<p>Interview outline #archived</p>")
    search_path = account_notes_workspace_path(@account, q: "outline")
    visit search_path
    assert_selector "[data-note-id='#{@note.id}']", text: @note.title
    assert_link "#archived"
    within(".n-orbite-rail") { click_on "Home" }
    assert_current_path user_root_path

    other_tab = open_new_window
    within_window(other_tab) do
      visit account_note_path(@account, @note)
      find("summary", text: "Note actions").click
      click_button "Trash note"
      assert_selector "[data-notes-trash-note='#{@note.id}']", text: @note.title
    end

    page.go_back
    assert_current_path search_path
    assert_field "Search all notes in this account", with: "outline"
    assert_no_selector "[data-note-id='#{@note.id}']"
    assert_no_link "#archived"
  ensure
    other_tab&.close
  end

  test "long French labels fit the mobile editor in light and dark themes" do
    @account.update!(name: "CompteDeRecherche" * 6)
    orbite_select_language("FR")
    orbite_viewport(375, 850)
    visit account_note_path(@account, @note)

    [ false, true ].each do |dark|
      orbite_theme(dark)
      assert_selector "h2", text: "Éditeur de note"
      assert_selector "[data-notes-accounts]", text: /CompteDeRecherche/
      assert_no_text(/translation missing|missing translation/i)
      overflow = page.evaluate_script(<<~JS)
        (() => {
          const main = document.querySelector("main")
          return [...main.querySelectorAll(".n-notes *")]
            .filter(element => element.getBoundingClientRect().right > main.getBoundingClientRect().left + main.clientWidth + 1)
            .map(element => [element.tagName, element.className, element.getBoundingClientRect().right])
        })()
      JS
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1"), overflow.inspect
    end
  end

  test "Lexxy autosaves a formatted new note and changes identity without remounting the editor" do
    visit account_notes_workspace_path(@account, q: "Research")
    click_link "New note"
    editor = find("lexxy-editor[connected] .lexxy-editor__content")
    page.execute_script("window.originalNoteEditor = document.querySelector('lexxy-editor')")
    history_length = page.evaluate_script("history.length")
    fill_in "Title (optional)", with: "Research notes"
    editor.send_keys([ :control, "b" ], "Ideas", [ :control, "b" ], " #research")
    assert_save_status "Saved"
    assert page.evaluate_script("window.dispatchEvent(new Event('beforeunload', { cancelable: true }))")

    saved = @account.notes.find_by!(title: "Research notes")
    assert_equal [ "research" ], saved.note_tags.pluck(:key)
    assert saved.note_folder.general?
    assert_current_path account_note_path(@account, saved, q: "Research")
    assert_equal history_length, page.evaluate_script("history.length")
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
    assert_selector "[data-note-id='#{saved.id}'] a[aria-current='page']", text: "Research notes"
    assert_selector "h2", text: "Note editor"
    assert_selector "summary", text: "Note actions"
    assert_equal account_note_path(@account, saved, q: "Research"),
      find(".n-language-preference input[name='return_to']", visible: :all).value
    refresh
    assert_selector "lexxy-editor[connected] .lexxy-editor__content strong", text: "Ideas"
    assert_text "#research"
  end

  test "hydrating a blank or seeded Lexxy editor sends no autosave request" do
    @note.edit_content!(expected_revision: 1, title: @note.title, body_html: "<p>#research</p>")
    [ {}, { tag: "research" } ].each do |context|
      visit new_account_note_path(@account, **context)
      page.execute_script(<<~JS)
        window.noteWrites = 0
        const ordinaryFetch = window.fetch
        window.fetch = (url, options) => {
          if (options?.method === "POST") window.noteWrites += 1
          return ordinaryFetch(url, options)
        }
      JS
      editor = find("lexxy-editor[connected] .lexxy-editor__content")
      assert_equal(context[:tag] ? "#research" : "", editor.text)
      page.evaluate_async_script("const done = arguments[0]; setTimeout(done, 750)")
      assert_equal 0, page.evaluate_script("window.noteWrites")
    end
    assert_equal 1, @account.notes.count
  end

  test "a stale editor can copy its draft and explicitly load the saved version" do
    visit account_note_path(@account, @note, q: "outline")
    find("lexxy-editor[connected]")
    other_tab = open_new_window
    within_window(other_tab) do
      visit account_note_path(@account, @note)
      find("lexxy-editor[connected]")
      find_field("Title (optional)").send_keys([ :control, "a" ], "Other tab title")
      assert_field "Title (optional)", with: "Other tab title"
      assert_save_status "Saved"
    end

    fill_in "Title (optional)", with: "Unsaved title"
    find(".lexxy-editor__content").send_keys(:end, " locally edited")
    assert_save_status "This note changed after you opened it. Your changes were not saved."
    assert_field "Title (optional)", with: "Unsaved title"
    assert_selector ".lexxy-editor__content", text: "Interview outline locally edited"
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
        writeText(text) { window.copiedNote = text; return Promise.resolve() }
      } })
    JS
    click_on "Copy draft"
    assert_text "Draft copied"
    assert_equal "Unsaved title\n\nInterview outline locally edited", page.evaluate_script("window.copiedNote")
    click_on "Load saved version"
    assert_field "Title (optional)", with: "Other tab title"
    assert_selector "lexxy-editor[connected] .lexxy-editor__content", exact_text: "Interview outline"
    assert_current_path account_note_path(@account, @note, q: "outline")
    assert_equal [ "Other tab title", "Interview outline", 2 ], @note.reload.values_at(:title, :body_text, :content_revision)
    find(".lexxy-editor__content").send_keys(:end, " after reload")
    assert_save_status "Saved"
    assert_equal [ "Interview outline after reload", 3 ], @note.reload.values_at(:body_text, :content_revision)
  ensure
    other_tab&.close
  end

  test "an unavailable editor preserves the draft and offers copying without a dead reload link" do
    visit account_note_path(@account, @note)
    find("lexxy-editor[connected]")
    @note.trash
    fill_in "Title (optional)", with: "Still my draft"
    assert_save_status "This change is not available."
    assert_field "Title (optional)", with: "Still my draft"
    assert_button "Copy draft"
    assert_no_button "Load saved version"
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
  end

  test "a lost first acknowledgement retries the exact snapshot before patching later local edits" do
    visit new_account_note_path(@account)
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS)
      const ordinaryFetch = window.fetch
      window.noteWrites = []
      window.fetch = async (url, options) => {
        if (!["POST", "PATCH"].includes(options?.method)) return ordinaryFetch(url, options)
        window.noteWrites.push([options.method, options.body.get("note[draft_key]"),
          options.body.get("note[expected_revision]"), options.body.get("note[title]")])
        const response = await ordinaryFetch(url, options)
        if (window.noteWrites.length === 1) {
          await new Promise(resolve => { window.releaseFirstSave = resolve })
          throw new TypeError("Simulated lost response")
        }
        return response
      }
    JS
    fill_in "Title (optional)", with: "First snapshot"
    assert_save_status "Saving"
    Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
      page.evaluate_script("typeof window.releaseFirstSave === 'function'")
    end
    fill_in "Title (optional)", with: "Newer local title"
    assert_equal 1, page.evaluate_script("window.noteWrites.length")
    assert @account.notes.exists?(title: "First snapshot")
    page.execute_script("window.releaseFirstSave()")
    assert_save_status "Could not save"
    assert_field "Title (optional)", with: "Newer local title"
    click_on "Retry"
    assert_save_status "Saved"
    saved = @account.notes.find_by!(title: "Newer local title")
    assert_equal 2, @account.notes.count
    assert_equal 2, saved.content_revision
    requests = page.evaluate_script("window.noteWrites")
    assert_equal requests[0], requests[1]
    assert_equal [ "PATCH", "1", "Newer local title" ], requests[2].values_at(0, 2, 3)
  end

  test "a definitive validation failure allows a corrected first POST on the same draft" do
    visit new_account_note_path(@account)
    editor = find("lexxy-editor[connected] .lexxy-editor__content")
    editor.send_keys("##{'x' * (NoteTag::MAX_KEY_BYTES + 1)}")
    assert_save_status "A hashtag is too long"
    assert_equal 1, @account.notes.count
    key = find("input[name='note[draft_key]']", visible: :all).value
    assert_selector ".lexxy-editor__content", text: /#xxx/
    editor.send_keys([ :control, "a" ], "Corrected #short")
    assert_save_status "Saved"
    assert_equal [ "short" ], @account.notes.find_by!(draft_key: key).note_tags.pluck(:key)
  end

  test "dirty drafts cancel normal Turbo visits and Back without losing text" do
    list = account_notes_workspace_path(@account, q: "outline")
    visit list
    click_link "Field notes"
    editor_path = account_note_path(@account, @note, q: "outline")
    assert_current_path editor_path
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS)
      const ordinaryFetch = window.fetch
      window.fetch = (url, options) => options?.method === "PATCH" ?
        Promise.reject(new TypeError("Simulated connection outage")) : ordinaryFetch(url, options)
    JS
    fill_in "Title (optional)", with: "Unsaved navigation draft"
    assert_save_status "Could not save"
    refute page.evaluate_script("window.dispatchEvent(new Event('beforeunload', { cancelable: true }))")

    message = dismiss_confirm { click_on "Back to list" }
    assert_match(/unsaved/i, message)
    assert_current_path editor_path
    assert_field "Title (optional)", with: "Unsaved navigation draft"
    page.execute_script(<<~JS)
      window.ordinaryConfirm = window.confirm
      window.confirm = message => { window.restoreWarning = message; return false }
      history.back()
    JS
    Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
      page.evaluate_script("typeof window.restoreWarning === 'string'")
    end
    assert_match(/unsaved/i, page.evaluate_script("window.restoreWarning"))
    assert_current_path editor_path
    assert_field "Title (optional)", with: "Unsaved navigation draft"
    page.execute_script("window.confirm = window.ordinaryConfirm")

    accept_confirm { click_on "Back to list" }
    assert_current_path list
    assert_text "Field notes"
  end

  test "cancelling either folder trash confirmation leaves the dirty note protected and saveable" do
    folder = @note.note_folder
    visit account_note_path(@account, @note, folder_id: folder.id)
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS)
      window.ordinaryFetch = window.fetch
      window.fetch = (url, options) => options?.method === "PATCH" ?
        Promise.reject(new TypeError("Simulated connection outage")) : window.ordinaryFetch(url, options)
      window.ordinaryConfirm = window.confirm
      window.confirmations = []
      window.confirm = message => {
        window.confirmations.push(message)
        return !message.includes("all its folders and notes")
      }
    JS
    fill_in "Title (optional)", with: "Keep the draft after cancelling"
    assert_save_status "Could not save"

    within "#notes-list" do
      find("summary", text: "Trash folder").click
      click_on "Trash folder"
    end
    assert_field "Title (optional)", with: "Keep the draft after cancelling"
    refute page.evaluate_script("window.dispatchEvent(new Event('beforeunload', { cancelable: true }))"),
      "cancelling folder trash must not clear the dirty draft"
    assert_match(/all its folders and notes/, page.evaluate_script("window.confirmations").sole)

    page.execute_script(<<~JS)
      window.confirmations = []
      window.confirm = message => {
        window.confirmations.push(message)
        return !message.includes("unsaved changes")
      }
    JS
    within("#notes-list") { click_on "Trash folder" }
    assert_button "Trash folder"
    action, discard = page.evaluate_script("window.confirmations")
    assert_match(/all its folders and notes/, action)
    assert_match(/unsaved changes/i, discard)
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)

    page.execute_script("window.confirm = window.ordinaryConfirm; window.fetch = window.ordinaryFetch")
    dismiss_confirm(/unsaved changes/i) { click_on "Back to list" }
    click_on "Save note"
    assert_save_status "Saved"
    assert_equal [ "Keep the draft after cancelling", 2 ], @note.reload.values_at(:title, :content_revision)
  end

  test "an approved departure that fails keeps the draft dirty but does not restart autosave" do
    folder = @note.note_folder
    visit account_note_path(@account, @note, folder_id: folder.id)
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS, account_note_folder_trashing_path(@account, folder))
      const trashPath = arguments[0]
      window.ordinaryFetch = window.fetch
      window.noteWrites = 0
      window.fetch = (url, options) => {
        if (options?.method === "PATCH" && ++window.noteWrites === 1) {
          return new Promise((_resolve, reject) => options.signal.addEventListener("abort", () => {
            window.abortedSave = true
            reject(new DOMException("Aborted", "AbortError"))
          }, { once: true }))
        }
        if (new URL(url, location.origin).pathname === trashPath) {
          window.trashAttempted = true
          return Promise.reject(new TypeError("Simulated connection outage"))
        }
        return window.ordinaryFetch(url, options)
      }
      window.ordinaryConfirm = window.confirm
      window.confirm = () => true
    JS
    fill_in "Title (optional)", with: "Draft during departure"
    assert_save_status "Saving"
    within "#notes-list" do
      find("summary", text: "Trash folder").click
      click_on "Trash folder"
      assert_button "Trash folder"
    end
    assert page.evaluate_script("window.abortedSave && window.trashAttempted")
    assert_field "Title (optional)", with: "Draft during departure"
    refute page.evaluate_script("window.dispatchEvent(new Event('beforeunload', { cancelable: true }))"),
      "the failed departure left the editor mounted, so the draft must still be protected"

    find(".lexxy-editor__content").send_keys(:end, " still here")
    page.evaluate_async_script("const done = arguments[0]; setTimeout(done, 750)")
    assert_equal 1, page.evaluate_script("window.noteWrites")
    assert_equal [ "Field notes", "Interview outline", 1 ], @note.reload.values_at(:title, :body_text, :content_revision)
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)

    page.execute_script("window.confirm = window.ordinaryConfirm")
    dismiss_confirm(/unsaved changes/i) { click_on "Back to list" }
    click_on "Save note"
    assert_save_status "Saved"
    assert_equal [ "Draft during departure", "Interview outline still here", 2 ], @note.reload.values_at(:title, :body_text, :content_revision)
  end

  test "a real 409 from a stale folder trash action keeps the draft mounted and recoverable" do
    folder = @note.note_folder
    parent = folder.parent
    editor_path = account_note_path(@account, @note, folder_id: folder.id)
    visit editor_path
    watch_dirty_departure("Keep the 409 draft")
    find(".lexxy-editor__content").send_keys(:end, " in the open editor")

    other_tab = open_new_window
    within_window(other_tab) do
      visit account_notes_workspace_path(@account, folder_id: parent.id)
      within "#notes-list" do
        find("summary", text: "Trash folder").click
        accept_confirm(/all its folders and notes/) { click_on "Trash folder" }
      end
      assert_current_path account_notes_workspace_path(@account, view: "trash")
    end

    within "#notes-list" do
      find("summary", text: "Trash folder").click
      click_on "Trash folder"
    end
    assert_http_departure_status 409
    assert_current_path editor_path
    assert_save_status "This change is not available."
    assert_field "Title (optional)", with: "Keep the 409 draft"
    assert_selector ".lexxy-editor__content", exact_text: "Interview outline in the open editor"
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
    assert_equal 2, page.evaluate_script("window.departureConfirmations")
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)
    assert_equal [ "Field notes", "Interview outline", 1 ], @note.reload.values_at(:title, :body_text, :content_revision)

    click_on "Copy draft"
    assert_text "Draft copied"
    assert_equal "Keep the 409 draft\n\nInterview outline in the open editor", page.evaluate_script("window.copiedNote")
    page.execute_script("window.confirm = window.ordinaryConfirm; window.fetch = window.ordinaryFetch")
    dismiss_confirm(/unsaved changes/i) { click_on "Back to list" }
    click_on "Save note"
    assert_save_status "This change is not available."
    assert_button "Copy draft"
    assert_no_button "Load saved version"
    assert_equal 1, @note.reload.content_revision
  ensure
    other_tab&.close
  end

  test "a real 404 from a stale note link keeps the original draft saveable" do
    destination = Note.save_draft!(account: @account, folder: @note.note_folder, draft_key: SecureRandom.uuid,
      title: "Another note", body_html: "")
    editor_path = account_note_path(@account, @note, folder_id: @note.note_folder_id)
    visit editor_path
    watch_dirty_departure("Keep the 404 draft")
    destination.trash

    within("#notes-list") { click_on "Another note" }
    assert_http_departure_status 404
    assert_current_path editor_path
    assert_save_status "Could not open that page. Your draft is still here."
    assert_field "Title (optional)", with: "Keep the 404 draft"
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
    assert_equal 1, page.evaluate_script("window.departureConfirmations")
    refute page.evaluate_script("document.documentElement.hasAttribute('aria-busy')")
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)

    page.execute_script("window.confirm = window.ordinaryConfirm; window.fetch = window.ordinaryFetch")
    dismiss_confirm(/unsaved changes/i) { click_on "Back to list" }
    click_on "Save note"
    assert_save_status "Saved"
    assert_equal [ "Keep the 404 draft", 2 ], @note.reload.values_at(:title, :content_revision)
  end

  test "an edit made during a GET from a clean editor requires approval before rendering" do
    list = account_notes_workspace_path(@account, q: "outline")
    editor_path = account_note_path(@account, @note, q: "outline")
    visit editor_path
    hold_notes_get(list)
    history_length = page.evaluate_script("history.length")
    page.execute_script(<<~JS)
      document.addEventListener("turbo:before-render", event => {
        event.preventDefault()
        window.releaseNotesRender = event.detail.resume
      }, { once: true })
    JS
    click_on "Back to list"
    wait_for_held_notes_get
    page.execute_script("window.releaseNotesGet()")
    Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
      page.evaluate_script("typeof window.releaseNotesRender === 'function'")
    end
    find_field("Title (optional)").send_keys([ :control, "a" ], "Typed during the GET")
    assert_save_status "Could not save"
    page.execute_script("window.releaseNotesRender()")
    orbite_settle

    assert_current_path editor_path
    assert_field "Title (optional)", with: "Typed during the GET"
    assert_equal 1, page.evaluate_script("window.visitWarnings")
    assert_equal history_length, page.evaluate_script("history.length")
    refute page.evaluate_script("document.documentElement.hasAttribute('aria-busy')")
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
  end

  test "editing after approval requires new consent and accepting it completes the visit" do
    list = account_notes_workspace_path(@account, q: "outline")
    visit account_note_path(@account, @note, q: "outline")
    hold_notes_get(list, answers: [ true, true ])
    fill_in "Title (optional)", with: "Initially approved draft"
    assert_save_status "Could not save"
    click_on "Back to list"
    wait_for_held_notes_get
    find(".lexxy-editor__content").send_keys(:end, " edited after consent")
    page.execute_script("window.releaseNotesGet()")

    assert_current_path list
    assert_selector "[data-notes-screen='list']"
    assert_equal 2, page.evaluate_script("window.visitWarnings")
    assert_equal [ "Field notes", "Interview outline", 1 ], @note.reload.values_at(:title, :body_text, :content_revision)
  end

  test "cancelling a second visit does not clear recovery for the first pending GET" do
    destination = Note.save_draft!(account: @account, folder: @note.note_folder, draft_key: SecureRandom.uuid,
      title: "Pending destination", body_html: "")
    editor_path = account_note_path(@account, @note, folder_id: @note.note_folder_id)
    destination_path = account_note_path(@account, destination, folder_id: @note.note_folder_id)
    visit editor_path
    hold_notes_get(destination_path, answers: [ true, false ])
    fill_in "Title (optional)", with: "Keep after two visits"
    assert_save_status "Could not save"
    destination.trash

    within("#notes-list") { click_on "Pending destination" }
    wait_for_held_notes_get
    click_on "Back to list"
    assert_equal 2, page.evaluate_script("window.visitWarnings")
    page.execute_script("window.releaseNotesGet()")
    assert_selector "[data-note-autosave-target='status'], .rails-default-error-page"

    assert_current_path editor_path
    assert_save_status "Could not open that page. Your draft is still here."
    assert_equal 404, page.evaluate_script("window.departureStatus")
    assert_field "Title (optional)", with: "Keep after two visits"
    assert_button "Copy draft"
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
  end

  test "a failed GET with a dirty draft does not invoke Turbo's full-page fallback" do
    list = account_notes_workspace_path(@account, q: "outline")
    editor_path = account_note_path(@account, @note, q: "outline")
    visit editor_path
    hold_notes_get(list, answers: [ true ])
    fill_in "Title (optional)", with: "Keep after network error"
    assert_save_status "Could not save"
    click_on "Back to list"
    wait_for_held_notes_get
    page.execute_script(<<~JS)
      document.addEventListener("turbo:reload", () => { window.fallbackRequested = true })
      window.releaseNotesGet({ fail: true })
    JS
    # On the broken behavior Chromium may pause at its native leave dialog.
    begin
      assert_save_status "Could not open that page. Your draft is still here."
    rescue Selenium::WebDriver::Error::UnexpectedAlertOpenError
      flunk "Turbo fell back to a full-page load despite the dirty draft"
    end
    assert_current_path editor_path
    assert_field "Title (optional)", with: "Keep after network error"
    refute page.evaluate_script("window.fallbackRequested || document.documentElement.hasAttribute('aria-busy')")
    assert_button "Copy draft"
    refute page.evaluate_script("window.dispatchEvent(new Event('beforeunload', { cancelable: true }))")
    page.execute_script("window.fetch = window.ordinaryFetch")
    click_on "Save note"
    assert_save_status "Saved"
    assert_equal [ "Keep after network error", 2 ], @note.reload.values_at(:title, :content_revision)
  end

  test "list reorder during autosave keeps keyboard focus on the same note link" do
    folder = @note.note_folder
    other_note = Note.save_draft!(account: @account, folder:, draft_key: SecureRandom.uuid,
      title: "Keep keyboard focus here", body_html: "")
    visit account_note_path(@account, @note, folder_id: folder.id)
    find("lexxy-editor[connected]")
    assert_equal [ other_note.id, @note.id ], browser_list_note_ids
    page.execute_script(<<~JS)
      const ordinaryFetch = window.fetch
      window.fetch = (url, options) => options?.method === "PATCH" ?
        new Promise(resolve => { window.releaseNoteSave = () => resolve(ordinaryFetch(url, options)) }) :
        ordinaryFetch(url, options)
    JS
    fill_in "Title (optional)", with: "Move to the top"
    assert_save_status "Saving"
    focused = "[data-note-id='#{other_note.id}'] a"
    page.execute_script("document.querySelector(arguments[0]).focus()", focused)
    assert_selector "#{focused}:focus"
    page.execute_script("window.releaseNoteSave()")
    assert_save_status "Saved"

    assert_equal [ @note.id, other_note.id ], browser_list_note_ids
    assert_selector "#{focused}:focus"
    assert_equal account_note_path(@account, other_note, folder_id: folder.id),
      page.evaluate_script("document.activeElement.getAttribute('href')")
    page.send_keys(:enter)
    assert_current_path account_note_path(@account, other_note, folder_id: folder.id)
  end

  test "a missing destination in Turbo Back keeps the draft and restores the editor URL" do
    destination = Note.save_draft!(account: @account, folder: @note.note_folder, draft_key: SecureRandom.uuid,
      title: "Previous note", body_html: "")
    editor_path = account_note_path(@account, @note, folder_id: @note.note_folder_id)
    visit account_note_path(@account, destination, folder_id: @note.note_folder_id)
    click_on "Field notes"
    assert_current_path editor_path
    watch_dirty_departure("Keep the Back draft")
    destination.trash

    page.execute_script("history.back()")
    assert_http_departure_status 404
    assert_current_path editor_path
    assert_save_status "Could not open that page. Your draft is still here."
    assert_field "Title (optional)", with: "Keep the Back draft"
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
    assert_equal 1, page.evaluate_script("window.departureConfirmations")
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
  end

  test "a membership 404 still follows normal access handling after approved departure" do
    visit account_note_path(@account, @note, folder_id: @note.note_folder_id)
    watch_dirty_departure("Local text after access ends")
    @account.account_users.find_by!(user: users(:picker_owner)).destroy!

    click_on "Back to list"
    assert_http_departure_status 404
    assert_current_path account_notes_workspace_path(@account, folder_id: @note.note_folder_id)
    assert_no_selector "lexxy-editor"
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
  end

  test "confirming folder trash and draft discard follows the redirect without another prompt" do
    folder = @note.note_folder
    visit account_note_path(@account, @note, folder_id: folder.id)
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS)
      const ordinaryFetch = window.fetch
      window.fetch = (url, options) => options?.method === "PATCH" ?
        Promise.reject(new TypeError("Simulated connection outage")) : ordinaryFetch(url, options)
      window.confirmations = []
      window.confirm = message => {
        window.confirmations.push(message)
        return window.confirmations.length <= 2
      }
    JS
    fill_in "Title (optional)", with: "Do not save this draft"
    assert_save_status "Could not save"
    within "#notes-list" do
      find("summary", text: "Trash folder").click
      click_on "Trash folder"
    end

    assert_current_path account_notes_workspace_path(@account, view: "trash")
    action, discard = page.evaluate_script("window.confirmations")
    assert_equal 2, page.evaluate_script("window.confirmations.length")
    assert_match(/all its folders and notes/, action)
    assert_match(/unsaved changes/i, discard)
    assert NoteFolderTrashing.exists?(note_folder_id: folder.id)
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
  end

  test "confirmed discard followed by a same-note action opens a fresh editor" do
    editor_path = account_note_path(@account, @note, folder_id: @note.note_folder_id)
    visit editor_path
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS)
      const ordinaryFetch = window.fetch
      window.fetch = (url, options) => options?.method === "PATCH" ?
        Promise.reject(new TypeError("Simulated connection outage")) : ordinaryFetch(url, options)
      window.originalNoteForm = document.querySelector(".n-notes-form")
      window.pinWarnings = 0
      window.confirm = () => ++window.pinWarnings === 1
    JS
    find(".lexxy-editor__content").send_keys(:end, " discarded")
    assert_save_status "Could not save"

    find(".n-notes-editor-actions summary").click
    click_on "Pin in folder"

    assert_current_path editor_path
    assert_selector "[data-note-id='#{@note.id}']", text: "Pinned"
    assert_selector ".lexxy-editor__content", exact_text: "Interview outline"
    refute page.evaluate_script("window.originalNoteForm === document.querySelector('.n-notes-form')")
    assert_equal 1, page.evaluate_script("window.pinWarnings")
    assert_equal [ "Interview outline", 1 ], @note.reload.values_at(:body_text, :content_revision)
  end

  test "the ordinary HTML note form works when Lexxy is present but autosave is not" do
    visit account_note_path(@account, @note)
    editor = find("lexxy-editor[connected] .lexxy-editor__content")
    page.execute_script("document.querySelector('.n-notes-form').removeAttribute('data-controller')")
    editor.send_keys(:end, " from the form")
    click_on "Save note"
    assert_selector "input[name='note[expected_revision]'][value='2']", visible: :all
    assert_selector "lexxy-editor[connected] .lexxy-editor__content", text: "Interview outline from the form"
    assert_equal 2, @note.reload.content_revision
  end

  test "formatting stays opt-in, keyboard reachable and within the editor at responsive breakpoints" do
    visit account_note_path(@account, @note)
    find("lexxy-editor[connected]")
    [ [ 375, 850 ], [ 667, 375 ], [ 767, 850 ], [ 768, 850 ], [ 769, 850 ],
      [ 1023, 850 ], [ 1024, 850 ], [ 1025, 850 ], [ 1440, 900 ] ].each do |width, height|
      orbite_viewport(width, height)
      assert_button "Formatting"
      toggle = find_button("Formatting")
      assert_equal "false", toggle["aria-expanded"]
      assert_no_selector "lexxy-toolbar"
      toggle.send_keys(:tab)
      assert page.evaluate_script("document.activeElement.matches('.lexxy-editor__content')")
      toggle.send_keys(:enter)
      assert_equal "true", toggle["aria-expanded"]
      assert_selector "lexxy-toolbar button", visible: true
      assert page.evaluate_script("document.activeElement.closest('lexxy-toolbar') !== null")
      page.send_keys(:tab)
      assert page.evaluate_script("document.activeElement.matches('.lexxy-editor__content')")
      assert page.evaluate_script(<<~JS), "Horizontal overflow at #{width}x#{height}"
        (() => {
          const main = document.querySelector('main')
          return main.scrollWidth <= main.clientWidth + 1 && document.documentElement.scrollWidth <= innerWidth + 1
        })()
      JS
      toggle.send_keys(:enter)
      assert_no_selector "lexxy-toolbar"
    end
  end

  private
    def hold_notes_get(path, answers: [ false ])
      find("lexxy-editor[connected]")
      page.execute_script(<<~JS, path, answers)
        const [path, answers] = arguments
        const destination = new URL(path, location.origin).href
        window.ordinaryFetch = window.fetch
        window.visitWarnings = 0
        window.confirm = () => answers[window.visitWarnings++] ?? false
        window.fetch = (url, options) => {
          if (options?.method === "PATCH") return Promise.reject(new TypeError("Hold the autosave"))
          if (options?.method === "GET" && url === destination && !(new Headers(options.headers)).has("X-Sec-Purpose")) {
            return new Promise((resolve, reject) => {
              window.releaseNotesGet = ({ fail = false } = {}) => {
                if (fail) reject(new TypeError("Simulated navigation network failure"))
                else resolve(window.ordinaryFetch(url, { ...options, cache: "no-store" }))
              }
            })
          }
          return window.ordinaryFetch(url, options)
        }
        document.addEventListener("turbo:before-fetch-response", event => {
          if (event.target === document.documentElement) window.departureStatus = event.detail.fetchResponse.statusCode
        })
      JS
    end

    def wait_for_held_notes_get
      Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
        page.evaluate_script("typeof window.releaseNotesGet === 'function'")
      end
    end

    def browser_list_note_ids
      all("#notes-list [data-note-id]").map { |item| item["data-note-id"].to_i }
    end

    def watch_dirty_departure(title)
      find("lexxy-editor[connected]")
      page.execute_script(<<~JS)
        window.originalNoteEditor = document.querySelector("lexxy-editor")
        window.ordinaryFetch = window.fetch
        window.fetch = (url, options) => options?.method === "PATCH" ?
          Promise.reject(new TypeError("Hold the autosave")) : window.ordinaryFetch(url, options)
        window.ordinaryConfirm = window.confirm
        window.departureConfirmations = 0
        window.confirm = () => { window.departureConfirmations++; return true }
        document.addEventListener("turbo:before-fetch-response", event => {
          if (event.target === document.documentElement || event.target.matches("#notes-list form")) {
            window.departureStatus = event.detail.fetchResponse.statusCode
          }
        })
        Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
          writeText(text) { window.copiedNote = text; return Promise.resolve() }
        } })
      JS
      fill_in "Title (optional)", with: title
      assert_save_status "Could not save"
      refute page.evaluate_script("window.dispatchEvent(new Event('beforeunload', { cancelable: true }))")
    end

    def assert_http_departure_status(status)
      Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
        page.evaluate_script("window.departureStatus") == status
      end
      # Give Turbo a repaint to process the fetched HTML, if it didn't intercept it.
      orbite_settle
    end

    def assert_save_status(text)
      assert_selector "[data-note-autosave-target='status'][role='status']", text:
    end
end
