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
end
