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
    def assert_save_status(text)
      assert_selector "[data-note-autosave-target='status'][role='status']", text:
    end
end
