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

  test "rounded Orbite notes keep one paper surface and visible keyboard controls" do
    orbite_viewport(1440, 900)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-identity h1", text: "Notes"
    assert_selector ".n-notes-identity [data-notes-accounts]"
    row = "[data-note-id='#{@note.id}'] a[aria-current='page']"
    new_note = ".n-notes-header .n-notes-primary"

    [ false, true ].each do |dark|
      orbite_theme(dark)
      assert_selector row, text: "Field notes"
      orbite_tab_to(".n-notes-search input[type=search]")
      target = orbite_tab_to(new_note)
      assert_operator target.fetch("height"), :>=, 44
      assert_operator target.fetch("width"), :>=, 44

      styles = page.evaluate_script(<<~JS, row, new_note)
        (() => {
          const style = (selector) => getComputedStyle(document.querySelector(selector));
          const primary = style(arguments[1]);
          const selected = style(arguments[0]);
          const preview = style(`${arguments[0]} .n-notes-preview`);
          const luminance = (color) => color.match(/[0-9]+/g).slice(0, 3)
            .map(channel => Number(channel) / 255)
            .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
            .reduce((sum, channel, i) => sum + channel * [0.2126, 0.7152, 0.0722][i], 0);
          const contrast = (foreground, background) => {
            const [low, high] = [luminance(foreground), luminance(background)].sort((a, b) => a - b);
            return (high + 0.05) / (low + 0.05);
          };
          return {
            radius: parseFloat(primary.borderRadius),
            primaryFill: primary.backgroundColor,
            selectedShadow: selected.boxShadow,
            paneFills: ['.n-notes-sidebar-slot', '.n-notes-list', '.n-notes-reader'].map(selector => style(selector).backgroundColor),
            primaryContrast: contrast(primary.color, primary.backgroundColor),
            focusContrast: contrast(primary.outlineColor, primary.backgroundColor),
            previewContrast: contrast(preview.color, selected.backgroundColor)
          };
        })()
      JS
      transparent = "rgba(0, 0, 0, 0)"
      assert_operator styles.fetch("radius"), :>=, 8
      refute_equal transparent, styles.fetch("primaryFill")
      assert_includes styles.fetch("selectedShadow"), "inset"
      assert_equal [ transparent ] * 3, styles.fetch("paneFills")
      assert_operator styles.fetch("primaryContrast"), :>=, 4.5
      assert_operator styles.fetch("focusContrast"), :>=, 3, "New note focus ring contrast (dark: #{dark})"
      assert_operator styles.fetch("previewContrast"), :>=, 4.5
      orbite_tab_to(row)
    end
  end

  test "the rounded Lexxy surface keeps saving and indexing separate across layouts" do
    @note.edit_content!(expected_revision: @note.content_revision, title: @note.title,
      body_html: "<h1>Interview outline</h1><h2>Next steps</h2><p>Prepare questions.</p>")

    [ [ 1440, 900 ], [ 900, 768 ], [ 375, 800 ], [ 667, 375 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      assert_selector ".lexxy-editor__content h1", text: "Interview outline"
      assert_selector ".lexxy-editor__content h2", text: "Next steps"
      assert_selector ".n-notes-save-row [data-note-autosave-target='status']", visible: :all
      assert_selector ".n-notes-index-status [data-note-index-status-target='message']"

      [ false, true ].each do |dark|
        orbite_theme(dark)
        styles = page.evaluate_script(<<~JS)
          (() => {
            const main = document.querySelector("main");
            const style = (selector) => getComputedStyle(document.querySelector(selector));
            return {
              overflow: main.scrollWidth - main.clientWidth,
              radius: parseFloat(style("#notes-body").borderRadius),
              titleSize: parseFloat(style("#note_title").fontSize),
              h1Size: parseFloat(style(".lexxy-editor__content h1").fontSize),
              h2Size: parseFloat(style(".lexxy-editor__content h2").fontSize),
              bodySize: parseFloat(style(".lexxy-editor__content").fontSize)
            };
          })()
        JS
        label = "notes-polish-#{width}-#{height}-#{dark ? 'dark' : 'light'}"
        assert_operator styles.fetch("overflow"), :<=, 1, label
        assert_operator styles.fetch("radius"), :>=, 12, label
        assert_operator styles.fetch("titleSize"), :>, styles.fetch("h1Size"), "#{label}: note title vs body h1"
        assert_operator styles.fetch("h1Size"), :>, styles.fetch("h2Size"), "#{label}: body h1 vs h2"
        assert_operator styles.fetch("h2Size"), :>, styles.fetch("bodySize"), "#{label}: body h2 vs text"
        if ENV["NOTES_POLISH_EVIDENCE"]
          selector, alignment = height < 400 ? [ "#note_title", "start" ] : [ ".n-notes-index-status", "nearest" ]
          page.execute_script("document.querySelector(arguments[0]).scrollIntoView({ block: arguments[1] })", selector, alignment)
          orbite_settle
          orbite_record(label, styles, screenshot: true)
        end
      end
    end
  end

  test "the compact editor gives a short note more visible writing space" do
    [ [ 1440, 900 ], [ 900, 768 ], [ 375, 650 ], [ 667, 375 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      assert_button "Formatting"

      [ false, true ].each do |dark|
        orbite_theme(dark)
        sample = notes_writing_space
        label = "writing-space-#{width}-#{height}-#{dark ? 'dark' : 'light'}"
        orbite_record(label, sample, screenshot: true) if ENV["NOTES_WRITING_EVIDENCE"] == "1"
        if height == 375
          page.execute_script("document.getElementById('notes-editor-heading').scrollIntoView({ block: 'start' })")
          orbite_settle
          scrolled = notes_writing_space
          orbite_record("#{label}-scrolled", scrolled, screenshot: true) if ENV["NOTES_WRITING_EVIDENCE"] == "1"
          page.execute_script("document.querySelector('main').scrollTop = 0")
          orbite_settle
        end
        assert_selector "#notes-editor-heading .n-notes-editor-toolbar"
        assert_selector ".n-notes-body-heading label[for='notes-body'] ~ button[aria-controls='notes-formatting']"

        within "#notes-editor-heading .n-notes-editor-toolbar" do
          assert_link "Back to list"
          assert_button "Note actions"
        end
        heading = find(".n-notes-reader[aria-labelledby='notes-reader-heading'] h2#notes-reader-heading.sr-only", visible: :all)
        assert_equal "Note editor", heading.native.accessible_name
        assert_selector ".n-notes-body-heading label[for='notes-body']", exact_text: "Note text"
        assert_equal "Note text", find("#notes-body [role=textbox]").native.accessible_name
        assert_in_delta sample.fetch("labelCenter"), sample.fetch("formattingCenter"), 1, label
        if width == 1440
          assert_operator sample.fetch("bodyHeight"), :>=, 320, sample.inspect
          assert_operator sample.fetch("visible"), :>=, 320, sample.inspect
        end
        # Keep the body at least one 44px control row higher than the former stacked layout.
        assert_operator sample.fetch("top"), :<=, 481, label if width == 900
        assert_operator sample.fetch("top"), :<=, 571, label if width == 375
        assert_operator scrolled.fetch("visible"), :>=, 150, label if height == 375
        assert_operator sample.fetch("overflow"), :<=, 1, label
        assert_operator sample.fetch("pageOverflow"), :<=, 1, label
      end
    end
  end

  [ [ "empty", "No text to index" ], [ "failed", "Échec de l’indexation" ] ].each do |state, message|
    test "the desktop editor keeps the #{state} indexing status in view without scrolling" do
      if state == "failed"
        @note.update!(embedding_status: :failed, embedding_generation: 2)
        orbite_select_language("FR")
      end
      orbite_viewport(1440, 900)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      assert_selector ".n-notes-index-status [role=status][data-note-index-status='#{state}']", exact_text: message
      assert_button "Relancer l’indexation" if state == "failed"

      samples = [ false, true ].map do |dark|
        orbite_theme(dark)
        sample = notes_writing_space.merge(notes_index_geometry)
        label = "desktop-index-#{state}-#{dark ? 'dark' : 'light'}"
        orbite_record(label, sample, screenshot: true) if ENV["NOTES_WRITING_EVIDENCE"] == "1"
        sample
      end

      samples.each do |sample|
        assert_equal 0, sample.fetch("mainScroll"), sample.inspect
        assert_equal 0, sample.fetch("pageScroll"), sample.inspect
        assert_operator sample.fetch("visible"), :>=, 320, sample.inspect
        %w[message retry].filter_map { |control| sample[control] }.each do |bounds|
          assert_operator bounds.fetch("top"), :>=, sample.fetch("viewportTop"), sample.inspect
          assert_operator bounds.fetch("bottom"), :<=, sample.fetch("viewportBottom"), sample.inspect
        end
      end
    end
  end

  test "long desktop notes grow past the writing minimum and scroll with the workspace" do
    body = (1..40).map { |number| "<p>Interview question #{number}</p>" }.join
    @note.edit_content!(expected_revision: @note.content_revision, title: @note.title, body_html: body)
    orbite_viewport(1440, 900)
    visit account_note_path(@account, @note)
    assert_selector "lexxy-editor[connected] .lexxy-editor__content p:last-child", exact_text: "Interview question 40"
    assert_operator notes_writing_space.fetch("bodyHeight"), :>, 900
    page.execute_script("document.querySelector('[data-note-index-status-target=message]').scrollIntoView({ block: 'nearest' })")
    orbite_settle
    sample = notes_index_geometry
    assert_operator sample.fetch("mainScroll"), :>, 0, sample.inspect
    assert_equal 0, sample.fetch("pageScroll"), sample.inspect
    assert_operator sample.fetch("message").fetch("bottom"), :<=, sample.fetch("viewportBottom"), sample.inspect
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

  test "note actions float in the viewport without shifting the editor" do
    [ [ 1440, 900 ], [ 900, 768 ], [ 375, 650 ], [ 667, 375 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      [ false, true ].each do |dark|
        orbite_theme(dark)
        assert_notes_dropdown("note-actions-#{@note.id}", "#note_title")
      end
    end
  end

  test "account choices float above the editor with long French labels" do
    @account.update!(name: "ÉquipeDeRecherche" * 5)
    orbite_select_language("FR")
    trigger = "[data-notes-accounts] button[popovertarget='notes-accounts']"

    [ [ 1440, 900 ], [ 900, 768 ], [ 375, 650 ], [ 667, 375 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"

      [ false, true ].each do |dark|
        orbite_theme(dark)
        assert_selector trigger, exact_text: "Compte : #{@account.name}"
        assert_notes_dropdown("notes-accounts", "#note_title") do |panel|
          assert_selector "#{trigger}:focus"
          anchor = assert_anchored_notes_dropdown("notes-accounts").fetch("anchor")
          assert_operator anchor.fetch("height"), :>=, 44
          assert_operator anchor.fetch("width"), :>=, 44
          assert_account_label_fits(find("#{trigger} > span"))
          within "#{panel} ul[aria-label='Changer de compte pour Notes']" do
            current = find("a[aria-current='true']", exact_text: @account.name)
            other = find_link(accounts(:picker_second).name)
            [ current, other ].each do |link|
              target = link.native.rect
              assert_operator target.height, :>=, 44
              assert_operator target.width, :>=, 44
            end
            refute other["aria-current"]
            assert_includes page.evaluate_script("getComputedStyle(arguments[0]).boxShadow", current), "inset"
            current_fill, other_fill = page.evaluate_script("[...arguments].map(link => getComputedStyle(link).backgroundColor)", current, other)
            refute_equal current_fill, other_fill
            assert_account_label_fits(current)
          end
        end
      end
    end
  end

  test "Tab past the last account link closes the switcher and leaves search focused" do
    panel = "#notes-accounts:popover-open"
    search = ".n-notes-search input[type=search]"

    [ [ 375, 650 ], [ 1440, 900 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      orbite_tab_to("button[popovertarget='notes-accounts']")
      page.driver.browser.action.send_keys(:enter).perform
      [ @account, accounts(:picker_second) ].each do |account|
        page.driver.browser.action.send_keys(:tab).perform
        assert_selector "#{panel} a:focus", exact_text: account.name
      end

      page.driver.browser.action.send_keys(:tab).perform
      assert_selector "#{search}:focus"
      assert_no_selector panel, visible: :all
      assert orbite_assert_reachable("#{search}:focus").fetch("focusVisible")
    end
  end

  test "the account switcher respects a dirty draft before switching to a different account" do
    other = accounts(:picker_second)
    editor_path = account_note_path(@account, @note)
    visit editor_path
    watch_dirty_departure("Unsaved account draft")
    page.execute_script("window.confirm = window.ordinaryConfirm")

    assert_button "Account: #{@account.name}"
    click_button "Account: #{@account.name}"
    within "#notes-accounts:popover-open" do
      dismiss_confirm(/unsaved changes/i) { click_link other.name }
    end
    assert_current_path editor_path
    assert_field "Title (optional)", with: "Unsaved account draft"
    assert_no_selector "[data-note-id='#{notes(:second_team_note).id}']"

    accept_confirm(/unsaved changes/i) { within("#notes-accounts:popover-open") { click_link other.name } }
    assert_current_path account_notes_workspace_path(other)
    assert_selector "[data-notes-screen='folders']"
    assert_selector "[data-notes-accounts] button", text: "Account: #{other.name}"
    assert_selector "[data-notes-list] [data-note-id='#{notes(:second_team_note).id}']"
    assert_no_selector "[data-note-id='#{@note.id}'], lexxy-editor", visible: :all
    assert_equal "Field notes", @note.reload.title
  end

  test "the account switcher opens and navigates without scripts" do
    other = accounts(:picker_second)
    orbite_viewport(375, 650)
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit account_note_path(@account, @note)

    assert_button "Account: #{@account.name}"
    click_button "Account: #{@account.name}"
    assert_anchored_notes_dropdown("notes-accounts")
    page.driver.browser.action.send_keys(:tab).perform
    assert_selector "#notes-accounts:popover-open a[aria-current='true']:focus"
    page.driver.browser.action.send_keys(:tab).perform
    assert_selector "#notes-accounts:popover-open a[href='#{account_notes_workspace_path(other)}']:focus"
    page.driver.browser.action.send_keys(:enter).perform

    assert_current_path account_notes_workspace_path(other)
    assert_button "Account: #{other.name}"
    within("[data-notes-sidebar]") { click_link "All Notes" }
    assert_selector "[data-notes-list] [data-note-id='#{notes(:second_team_note).id}']"
    assert_no_selector "[data-note-id='#{@note.id}']"
  end

  test "folder actions cancel and explicitly submit the native confirmation without scripts" do
    folder = note_folders(:interviews)
    orbite_viewport(375, 650)
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit account_notes_workspace_path(@account, folder_id: folder.id, view: "list")

    assert_button "Folder actions"
    click_button "Folder actions"
    assert_link "Edit folder", href: edit_account_note_folder_path(@account, folder, folder_id: folder.id, view: "list")
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)

    click_button "Trash folder"
    panel = "#trash-folder-#{folder.id}:modal"
    assert_selector panel, text: "Move “Interviews” and all its folders and notes to Trash?"
    assert_anchored_notes_dropdown("trash-folder-#{folder.id}")
    assert_selector "#{panel} button:focus", exact_text: "Cancel"
    page.driver.browser.action.send_keys(:tab).perform
    assert_selector "#{panel} button[type=submit]:focus", exact_text: "Trash folder"
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)
    within(panel) { click_button "Cancel" }
    assert_no_selector panel
    assert_selector "#folder-actions-#{folder.id}:popover-open button:focus", exact_text: "Trash folder"
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)

    page.driver.browser.action.send_keys(:enter).perform
    assert_selector panel
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector panel
    assert_selector "#folder-actions-#{folder.id}:popover-open button:focus", exact_text: "Trash folder"
    click_button "Trash folder"
    within(panel) { click_button "Trash folder" }
    assert_selector "[data-notes-trash]"
    assert NoteFolderTrashing.exists?(note_folder_id: folder.id)
  end

  test "folder confirmation can cancel and submit with native popovers but no dialog commands or scripts" do
    folder = note_folders(:interviews)
    orbite_viewport(375, 650)
    visit account_notes_workspace_path(@account, folder_id: folder.id, view: "list")
    # Model a browser that ignores dialog commands but implements native popovers.
    page.execute_script(<<~JS)
      document.querySelectorAll("#notes-list [commandfor]").forEach(button => {
        button.removeAttribute("commandfor")
        button.removeAttribute("command")
      })
    JS
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)

    click_button "Folder actions"
    click_button "Trash folder"
    panel = "#trash-folder-#{folder.id}:popover-open"
    assert_selector panel, text: "Move “Interviews” and all its folders and notes to Trash?"
    assert_selector "#{panel} button:focus", exact_text: "Cancel"
    page.driver.browser.action.send_keys(:tab).perform
    assert_selector "#{panel} button[type=submit]:focus", exact_text: "Trash folder"
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)
    within(panel) { click_button "Cancel" }
    assert_no_selector panel
    assert_selector "#folder-actions-#{folder.id}:popover-open"
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)

    click_button "Trash folder"
    within(panel) { click_button "Trash folder" }
    assert_selector "[data-notes-trash]"
    assert NoteFolderTrashing.exists?(note_folder_id: folder.id)
  end

  test "folder confirmation floats with safe Tab, Cancel and Escape on narrow and wide layouts" do
    folder = note_folders(:interviews)
    actions = "#folder-actions-#{folder.id}:popover-open"
    actions_trigger = "button[popovertarget='folder-actions-#{folder.id}']"
    confirmation = "#trash-folder-#{folder.id}:popover-open"
    confirmation_trigger = "button[commandfor='trash-folder-#{folder.id}'][command=show-modal]"
    reference = "[data-note-id='#{@note.id}']"

    [ [ 375, 650, true ], [ 667, 375, false ], [ 900, 768, true ], [ 1440, 900, false ] ].each do |width, height, dark|
      orbite_viewport(width, height)
      visit account_notes_workspace_path(@account, folder_id: folder.id, view: "list")
      orbite_theme(dark)
      orbite_tab_to(actions_trigger)
      before = notes_layout(reference)
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector actions
      assert_equal before, notes_layout(reference)
      orbite_tab_to("#{actions} a")
      target = orbite_tab_to(confirmation_trigger)
      assert_operator target.fetch("height"), :>=, 44
      assert_operator target.fetch("width"), :>=, 44
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#{confirmation}[aria-labelledby='trash-folder-#{folder.id}-heading'] h3", exact_text: "Trash folder"
      assert_selector "#{confirmation} button:focus", exact_text: "Cancel"
      cancel = orbite_assert_reachable("#{confirmation} button:focus")
      assert_operator cancel.fetch("height"), :>=, 44
      assert_operator cancel.fetch("width"), :>=, 44
      assert_anchored_notes_dropdown("trash-folder-#{folder.id}")
      assert_equal before, notes_layout(reference)
      page.driver.browser.action.send_keys(:tab).perform
      assert_selector "#{confirmation} button[type=submit]:focus", exact_text: "Trash folder"
      target = orbite_assert_reachable("#{confirmation} button[type=submit]:focus")
      assert_operator target.fetch("height"), :>=, 44
      assert_operator target.fetch("width"), :>=, 44
      page.driver.browser.action.send_keys(:tab).perform
      assert_no_selector confirmation
      assert_no_selector actions
      orbite_assert_reachable("#{reference} a:focus")

      before = notes_layout(reference)
      click_button "Folder actions"
      find(confirmation_trigger).click
      assert_equal before, notes_layout(reference)
      within(confirmation) { click_button "Cancel" }
      assert_no_selector confirmation
      assert_selector "#{actions} #{confirmation_trigger}:focus"
      assert_equal before, notes_layout(reference)
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector confirmation
      page.driver.browser.action.send_keys(:escape).perform
      assert_no_selector confirmation
      assert_selector "#{actions} #{confirmation_trigger}:focus"
      page.driver.browser.action.send_keys(:escape).perform
      assert_no_selector actions
      assert_selector "#{actions_trigger}:focus"
      assert_equal before, notes_layout(reference)
      refute NoteFolderTrashing.exists?(note_folder_id: folder.id)
    end
  end

  test "one outside pointer click closes both folder panels and keeps the clicked control focused" do
    folder = note_folders(:interviews)
    [ [ 375, 650, true ], [ 667, 375, false ], [ 1440, 900, false ] ].each do |width, height, dark|
      orbite_viewport(width, height)
      if width == 1440
        visit account_note_path(@account, @note, folder_id: folder.id)
        assert_selector "lexxy-editor[connected]"
        target = "#note_title"
      else
        visit account_notes_workspace_path(@account, folder_id: folder.id, view: "list")
        target = ".n-notes-search input[type=search]"
      end
      orbite_theme(dark)
      reference = "[data-note-id='#{@note.id}']"
      before = notes_layout(reference)

      actions = "#folder-actions-#{folder.id}:popover-open"
      confirmation = open_folder_trash_confirmation(folder)
      assert_selector actions
      assert_equal before, notes_layout(reference)
      point = page.evaluate_script(<<~JS, find(target))
        (() => {
          const target = arguments[0], rect = target.getBoundingClientRect()
          const y = Math.round(rect.top + rect.height / 2)
          return [rect.right - 12, rect.left + rect.width / 2, rect.left + 12]
            .map(x => [Math.round(x), y]).find(([x, y]) => document.elementFromPoint(x, y) === target)
        })()
      JS
      assert point, "No exposed part of #{target} at #{width}x#{height}"
      page.driver.browser.action.move_to_location(*point).click.perform

      assert_no_selector "#{actions}, #{confirmation}"
      assert_selector "#{target}:focus"
      assert_equal before, notes_layout(reference)
      refute NoteFolderTrashing.exists?(note_folder_id: folder.id)
    end
  end

  test "permanent deletion in Trash can cancel and explicitly submit without scripts" do
    orbite_viewport(375, 650)
    visit account_note_path(@account, @note)
    click_button "Note actions"
    click_button "Trash note"

    entry = "[data-notes-trash-note='#{@note.id}']"
    id = "purge-note-#{@note.id}"
    panel = "##{id}:is(:modal, :popover-open)"
    assert_selector entry, text: @note.title
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit account_notes_workspace_path(@account, view: "trash")

    within(entry) do
      assert_button "Delete permanently…"
      click_button "Delete permanently…"
    end
    assert_selector panel, text: "Permanently delete “#{@note.title}”? This cannot be undone."
    within(panel) { click_button "Cancel" }
    assert_no_selector panel
    assert_selector "#{entry} button[commandfor='#{id}']:focus", exact_text: "Delete permanently…"
    assert Note.exists?(@note.id)

    page.driver.browser.action.send_keys(:enter).perform
    within(panel) { click_button "Confirm permanent deletion" }
    assert_selector "[data-notes-trash]", text: "Trash is empty."
    assert_no_selector entry
    refute Note.exists?(@note.id)
  end

  test "note and folder purge confirmations float above their own entries in Trash" do
    folder = note_folders(:reading)
    @note.trash
    folder.trash
    note_entry = "[data-notes-trash-note='#{@note.id}']"
    folder_entry = "[data-notes-trash-folder='#{folder.id}']"
    entries = [
      [ note_entry, "purge-note-#{@note.id}", "Permanently delete “#{@note.title}”? This cannot be undone." ],
      [ folder_entry, "purge-folder-#{folder.id}", "Permanently delete “#{folder.name}” and all its folders and notes, including items trashed separately? This cannot be undone." ]
    ]
    open_panel = "[data-notes-trash] dialog:popover-open"
    search = ".n-notes-search input[type=search]"

    [ [ 375, 650 ], [ 1440, 900 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_notes_workspace_path(@account, view: "trash")
      find("#{folder_entry} summary", text: folder.name).click
      orbite_settle
      before = [ note_entry, folder_entry ].map { |entry| notes_layout(entry) }

      entries.each do |entry, id, copy|
        panel = "##{id}:popover-open"
        trigger = "#{entry} button[commandfor='#{id}'][command=show-modal]"
        within(entry) do
          assert_button "Delete permanently…"
          click_button "Delete permanently…"
        end
        assert_selector open_panel, count: 1
        assert_selector "#{panel} h3", exact_text: "Delete permanently…"
        assert_selector "#{panel} p", exact_text: copy
        assert_selector "#{panel} button:focus", exact_text: "Cancel"
        assert_anchored_notes_dropdown(id)
        assert_equal before, [ note_entry, folder_entry ].map { |row| notes_layout(row) }

        dismiss_confirm(copy) { within(panel) { click_button "Confirm permanent deletion" } }
        assert_selector note_entry, text: @note.title
        assert_selector folder_entry, text: folder.name
        assert Note.exists?(@note.id)
        assert NoteFolder.exists?(folder.id)

        page.driver.browser.action.send_keys(:escape).perform
        assert_no_selector open_panel
        assert_selector "#{trigger}:focus"
        assert_equal before, [ note_entry, folder_entry ].map { |row| notes_layout(row) }

        page.driver.browser.action.send_keys(:enter).perform
        assert_selector "#{panel} button:focus", exact_text: "Cancel"
        page.driver.browser.action.send_keys(:tab).perform
        submit = "#{panel} button[type=submit]:focus"
        assert_selector submit, exact_text: "Confirm permanent deletion"
        orbite_assert_reachable(submit)

        page.driver.browser.action.send_keys(:escape).perform
        assert_no_selector open_panel
        assert_selector "#{trigger}:focus"
        assert_equal before, [ note_entry, folder_entry ].map { |row| notes_layout(row) }
        assert Note.exists?(@note.id)
        assert NoteFolder.exists?(folder.id)

        page.driver.browser.action.send_keys(:enter).perform
        assert_selector panel
        find(search).click
        assert_no_selector open_panel
        assert_selector "#{search}:focus"
        assert_equal before, [ note_entry, folder_entry ].map { |row| notes_layout(row) }
      end
    end
  end

  test "Edit folder in Folder actions keeps the same filtered workspace destination" do
    folder = note_folders(:interviews)
    options = { folder_id: folder.id, view: "list" }
    visit account_notes_workspace_path(@account, **options)
    click_button "Folder actions"
    within "#folder-actions-#{folder.id}:popover-open" do
      click_link "Edit folder", href: edit_account_note_folder_path(@account, folder, **options)
    end
    assert_current_path edit_account_note_folder_path(@account, folder, **options)
    assert_field "Folder name", with: folder.name

    visit account_notes_workspace_path(@account, folder_id: @account.general_note_folder.id, view: "list")
    assert_no_button "Folder actions"
  end

  test "Tab past the last Note actions command closes the panel and leaves the title focused" do
    panel = "#note-actions-#{@note.id}:popover-open"

    [ [ 375, 650 ], [ 1440, 900 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      orbite_tab_to("button[popovertarget='note-actions-#{@note.id}']")
      page.driver.browser.action.send_keys(:enter).perform
      [ "Pin in folder", "Move note", "Trash note" ].each do |command|
        page.driver.browser.action.send_keys(:tab).perform
        assert_selector "#{panel} button:focus", exact_text: command
      end

      page.driver.browser.action.send_keys(:tab).perform
      assert_selector "#note_title:focus"
      assert_no_selector panel, visible: :all
      assert orbite_assert_reachable("#note_title:focus").fetch("focusVisible")
    end
  end

  test "Escape closes nested move before note actions and returns focus in order" do
    orbite_viewport(375, 650)
    visit account_note_path(@account, @note)
    assert_selector "lexxy-editor[connected]"
    actions = "button[popovertarget='note-actions-#{@note.id}']"
    move = notes_move_trigger
    actions_panel = "#note-actions-#{@note.id}:popover-open"
    move_panel = notes_open_move_panel
    assert_selector actions
    orbite_tab_to(actions)
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector actions_panel
    orbite_tab_to(move)
    page.driver.browser.action.send_keys(:enter).perform
    page.driver.browser.action.send_keys(:tab).perform unless page.has_selector?("#{move_panel} select:focus", wait: 0)
    assert_selector "#{move_panel} select:focus"

    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector move_panel
    assert_selector "#{actions_panel} #{move}:focus"
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector actions_panel
    assert_selector "#{actions}:focus"
  end

  test "one outside click dismisses Note actions and Move and focuses the editor title" do
    failures = []
    [ [ 375, 650 ], [ 667, 375 ], [ 1440, 900 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      page.execute_script(<<~JS)
        const title = document.getElementById("note_title")
        if (title.getBoundingClientRect().bottom > innerHeight) title.scrollIntoView({ block: "center" })
      JS
      orbite_settle
      before = notes_layout("#note_title")
      click_button "Note actions"
      click_button "Move note"
      actions = "#note-actions-#{@note.id}:popover-open"
      move = notes_open_move_panel
      assert_selector actions
      assert_selector move
      assert_equal before, notes_layout("#note_title")
      point = page.evaluate_script(<<~JS, actions, move)
        (() => {
          const title = document.getElementById("note_title").getBoundingClientRect()
          const panels = [...document.querySelectorAll(`${arguments[0]}, ${arguments[1]}`)]
            .map(panel => panel.getBoundingClientRect())
          for (const y of [title.top + 5, title.bottom - 5].map(Math.round)) {
            for (const x of [title.left + 12, (title.left + title.right) / 2, title.right - 12].map(Math.round)) {
              if (x >= 0 && x < innerWidth && y >= 0 && y < innerHeight &&
                  !panels.some(panel => x >= panel.left && x < panel.right && y >= panel.top && y < panel.bottom)) return [x, y]
            }
          }
          return null
        })()
      JS
      assert point, "No part of the editor title exposed at #{width}x#{height}"
      page.driver.browser.action.move_to_location(*point).click.perform
      orbite_settle

      open = page.has_selector?("#{actions}, #{move}", visible: :all, wait: 0)
      focused = page.has_selector?("#note_title:focus", wait: 0)
      failures << "#{width}x#{height}: panel open=#{open}, title focused=#{focused}" if open || !focused
      assert_equal before, notes_layout("#note_title")
      refute NotePin.exists?(account: @account, note: @note)
      assert Note.active_in(@account.id).exists?(@note.id)
      assert_equal note_folders(:interviews), @note.reload.note_folder
    end
    assert_empty failures
  end

  test "tabbing past Move submit does not leave focus behind the open picker" do
    [ [ 375, 650 ], [ 1440, 900 ] ].each do |width, height|
      orbite_viewport(width, height)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      actions = "#note-actions-#{@note.id}:popover-open"
      move = notes_open_move_panel
      orbite_tab_to("button[popovertarget='note-actions-#{@note.id}']")
      page.driver.browser.action.send_keys(:enter).perform
      orbite_tab_to(notes_move_trigger)
      before = notes_layout("#note_title")
      page.driver.browser.action.send_keys(:enter).perform
      orbite_assert_reachable(move)
      assert_equal before, notes_layout("#note_title")
      orbite_tab_to("#{move} input[type=submit]")
      page.driver.browser.action.send_keys(:tab).perform
      assert_selector "#{move} button:focus", text: "Cancel"
      page.driver.browser.action.send_keys(:tab).perform
      assert_no_selector move
      assert_selector "#{actions} button:focus", text: "Trash note"
      assert_equal before, notes_layout("#note_title")
      page.driver.browser.action.send_keys(:escape).perform
      assert_no_selector actions
      assert_selector "button[popovertarget='note-actions-#{@note.id}']:focus"
      assert_equal before, notes_layout("#note_title")
    end
  end

  test "native Escape returns focus from the Move destination without scripts" do
    orbite_viewport(375, 650)
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit account_note_path(@account, @note)
    id = "note-actions-#{@note.id}"
    move_trigger = notes_move_trigger
    move_panel = "#note-move-#{@note.id}:modal"
    click_button "Note actions"
    assert_anchored_notes_dropdown(id)
    find(move_trigger).click
    page.driver.browser.action.send_keys(:tab).perform unless page.has_selector?("#{move_panel} select:focus", wait: 0)
    assert_selector "#{move_panel} select:focus"
    assert_anchored_notes_dropdown("note-move-#{@note.id}")
    page.driver.browser.action.send_keys(:escape).perform

    assert_no_selector move_panel
    assert_selector "##{id}:popover-open #{move_trigger}:focus"
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "##{id}:popover-open"
    assert_selector "button[popovertarget='#{id}']:focus"
  end

  test "note actions still move a note without scripts" do
    destination = note_folders(:reading)
    orbite_viewport(375, 650)
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit account_note_path(@account, @note)

    assert_button "Note actions"
    click_button "Note actions"
    click_button "Move note"
    within notes_open_move_panel do
      select "Research / Reading", from: "Destination folder"
      click_button "Move note"
    end

    assert_current_path account_note_path(@account, @note, folder_id: destination.id)
    assert_selector "#notes-editor-heading .n-notes-meta", text: "Research / Reading"
    assert_equal destination, @note.reload.note_folder

    click_link "Back to list"
    assert_current_path account_notes_workspace_path(@account, folder_id: destination.id)
    assert_selector "#notes-list-heading", text: "Research / Reading"
    assert_selector "#notes-list [data-note-id='#{@note.id}']"
  end

  test "Move still opens and cancels when declarative dialog commands are unavailable" do
    visit account_note_path(@account, @note)
    assert_selector "lexxy-editor[connected]"
    click_button "Note actions"
    trigger = find(notes_move_trigger)
    page.execute_script(<<~JS, trigger)
      const trigger = arguments[0]
      Object.defineProperty(trigger, "commandForElement", { value: undefined })
      trigger.removeAttribute("command")
      trigger.removeAttribute("commandfor")
    JS
    trigger.click
    assert_selector "#{notes_open_move_panel} select:focus"
    click_button "Cancel"
    assert_no_selector notes_open_move_panel
    assert_selector "#{notes_move_trigger}:focus"
  end

  test "note actions stay anchored without CSS anchor support through scroll resize and autosave" do
    browser = page.driver.browser
    script = browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      const supports = CSS.supports.bind(CSS)
      CSS.supports = (...args) => args[0] === "position-area" && args[1] === "block-end span-all" ? false : supports(...args)
    JS
    orbite_viewport(667, 375)
    visit account_note_path(@account, @note)
    assert_selector "lexxy-editor[connected]"
    assert_equal 1, remove_notes_support_rules("position-area")
    hold_note_save_response
    fill_in "Title (optional)", with: "Saved while the fallback is open"
    id = "note-actions-#{@note.id}"
    move_id = "note-move-#{@note.id}"
    trigger = "button[popovertarget='#{id}']"
    orbite_tab_to(trigger)
    before = notes_layout("#note_title")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "##{id}:popover-open"
    orbite_settle
    initial = assert_anchored_notes_dropdown(id)
    assert_equal before, notes_layout("#note_title")
    orbite_tab_to(notes_move_trigger)
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#{notes_open_move_panel} select:focus"
    orbite_settle
    initial_move = assert_anchored_notes_dropdown(move_id)
    assert_equal before, notes_layout("#note_title")

    page.execute_script("window.releaseNoteSave()")
    assert_save_status "Saved"
    assert_equal initial, assert_anchored_notes_dropdown(id)
    assert_equal initial_move, assert_anchored_notes_dropdown(move_id)
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector notes_open_move_panel
    assert_selector "#{notes_move_trigger}:focus"

    page.execute_script("document.querySelector('main').scrollTop += 24")
    orbite_settle
    after_scroll = assert_anchored_notes_dropdown(id)
    refute_equal initial.fetch("anchor").fetch("top"), after_scroll.fetch("anchor").fetch("top")
    orbite_viewport(690, 480)
    assert_anchored_notes_dropdown(id)
  ensure
    browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script.fetch("identifier")) if script
  end

  test "nested folder confirmation stays anchored when position-area works but anchor scoping does not" do
    browser = page.driver.browser
    script = browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      const supports = CSS.supports.bind(CSS)
      CSS.supports = (...args) => args[0] === "anchor-scope" ? false : supports(...args)
      // Keep real popovers, but model showPopover before its source option.
      const showPopover = HTMLElement.prototype.showPopover
      HTMLElement.prototype.showPopover = function() { return showPopover.call(this) }
    JS
    folder = note_folders(:interviews)
    parent_id = "folder-actions-#{folder.id}"
    confirmation_id = "trash-folder-#{folder.id}"
    orbite_viewport(667, 375)
    visit account_notes_workspace_path(@account, folder_id: folder.id, view: "list")
    assert_equal [ true, false ], page.evaluate_script("[CSS.supports('position-area', 'block-end span-all'), CSS.supports('anchor-scope', '--notes-confirmation')]")
    assert_equal 1, remove_notes_support_rules("anchor-scope")
    open_folder_trash_confirmation(folder)
    assert_selector "##{confirmation_id}:popover-open"
    orbite_settle

    assert_anchored_notes_dropdown(parent_id)
    before = assert_anchored_notes_dropdown(confirmation_id)
    page.execute_script("document.querySelector('main').scrollTop += 24")
    orbite_settle
    assert_anchored_notes_dropdown(parent_id)
    after_scroll = assert_anchored_notes_dropdown(confirmation_id)
    refute_equal before.fetch("anchor").fetch("top"), after_scroll.fetch("anchor").fetch("top")

    orbite_viewport(690, 480)
    assert_anchored_notes_dropdown(parent_id)
    assert_anchored_notes_dropdown(confirmation_id)
  ensure
    browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script.fetch("identifier")) if script
  end

  test "saving leaves the tablet drawer semantics and opened note actions intact" do
    orbite_viewport(768, 850)
    options = { folder_id: @note.note_folder_id }
    visit account_note_path(@account, @note, **options)
    assert_selector "lexxy-editor[connected]"
    assert_selector ".n-notes-folder-trigger[aria-haspopup='dialog']"
    hold_note_save_response
    fill_in "Title (optional)", with: "Updated from tablet"
    click_button "Note actions"
    assert_selector "#note-actions-#{@note.id}:popover-open"
    page.execute_script("window.releaseNoteSave()")
    assert_save_status "Saved"
    panel = "#note-actions-#{@note.id}:popover-open"
    pin_form = "#{panel} form[action='#{account_note_pin_path(@account, @note, **options)}'][method=post]"
    assert_selector "#{pin_form} button", text: "Pin in folder"
    assert_selector ".n-notes-folder-trigger[aria-haspopup='dialog']"
    orbite_tab_to("#{pin_form} button")
    page.driver.browser.action.send_keys(:enter).perform
    assert_current_path account_note_path(@account, @note, **options)
    assert_selector "[data-note-id='#{@note.id}']", text: "Pinned"
    assert NotePin.exists?(account: @account, note: @note)
    assert_field "Title (optional)", with: "Updated from tablet"
  end

  test "an autosave keeps the chosen Move destination while the submit button has focus" do
    original_folder_id = @note.note_folder_id
    destination = note_folders(:reading)
    options = { folder_id: original_folder_id }
    visit account_note_path(@account, @note, **options)
    assert_selector "lexxy-editor[connected]"
    hold_note_save_response
    fill_in "Title (optional)", with: "Updated while choosing a destination"
    assert_save_status "Saving"
    choose_move_destination("Research / Reading")
    page.driver.browser.action.send_keys(:tab).perform
    submit = "#{notes_open_move_panel} input[type=submit]"
    assert_selector "#{submit}:focus"

    page.execute_script("window.releaseNoteSave()")
    assert_save_status "Saved"
    form = "#{notes_open_move_panel} form[action='#{account_note_movement_path(@account, @note, **options)}'][method=post]"
    assert_selector "#{form} input[type=submit]:focus"
    within form do
      assert_select "Destination folder", selected: "Research / Reading"
      assert_equal destination.id.to_s, find_field("Destination folder").value
    end

    page.driver.browser.action.send_keys(:enter).perform
    assert_current_path account_note_path(@account, @note, folder_id: destination.id)
    assert_selector "#notes-editor-heading .n-notes-meta", text: "Research / Reading"
    assert_equal destination.id, @note.reload.note_folder_id
  end

  [ :submit, :select ].each do |focused|
    test "autosave removes an unavailable Move destination without substituting it with #{focused} focused" do
      original_folder_id = @note.note_folder_id
      destination = note_folders(:reading)
      visit account_note_path(@account, @note)
      assert_selector "lexxy-editor[connected]"
      hold_note_save_response(hold_request: true)
      fill_in "Title (optional)", with: "Updated while a destination is being removed"
      choose_move_destination("Research / Reading")
      panel = notes_open_move_panel
      submit = "#{panel} input[type=submit]"
      select = "#{panel} select"
      page.driver.browser.action.send_keys(:tab).perform if focused == :submit
      focus = focused == :submit ? submit : select
      assert_selector "#{focus}:focus"
      assert_save_status "Saving"
      destination.trash

      page.execute_script("window.releaseNoteSave()")
      assert_save_status "Saved"
      assert_selector "#{focus}:focus"
      assert_no_selector "#{select} option[value='#{destination.id}']", visible: :all
      within panel do
        assert_equal "", find_field("Destination folder").value
      end
      page.driver.browser.action.send_keys(:tab).perform if focused == :select
      assert_selector "#{submit}:focus"
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#{select}:invalid:focus"
      assert_equal original_folder_id, @note.reload.note_folder_id
    end
  end

  test "autosave resets the destination of a closed Move picker from the server" do
    visit account_note_path(@account, @note)
    assert_selector "lexxy-editor[connected]"
    hold_note_save_response
    fill_in "Title (optional)", with: "Updated after closing the picker"
    choose_move_destination("Research / Reading")
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector notes_open_move_panel

    page.execute_script("window.releaseNoteSave()")
    assert_save_status "Saved"
    click_button "Move note"
    within notes_open_move_panel do
      assert_equal @note.note_folder_id.to_s, find_field("Destination folder").value
    end
  end

  test "a native HTML conflict lets a keyboard user select the draft and load the saved note" do
    visit account_note_path(@account, @note)
    assert_selector "lexxy-editor[connected]"
    @note.edit_content!(expected_revision: 1, title: "Newer saved title", body_html: "<p>Newer saved body</p>")
    page.execute_script(<<~JS)
      const form = document.querySelector(".n-notes-form")
      form.dataset.turbo = "false"
      form.elements["note[title]"].value = "My draft title"
      form.elements["note[body_html]"].value = "<p>My draft text</p>"
      HTMLFormElement.prototype.submit.call(form)
    JS

    assert_selector ".n-notes-identity h1", text: "Notes"
    assert_selector "[role=alert]", text: /Your changes were not saved/
    assert_selector "input#notes-draft-title[readonly]"
    body = find_field("Submitted note text")
    assert_equal "My draft text", body.value
    find_field("Submitted title").send_keys(:tab)
    assert_equal body[:id], page.evaluate_script("document.activeElement.id")
    body.send_keys([ :control, "a" ])
    assert_equal "My draft text", page.evaluate_script(<<~JS)
      document.activeElement.value.slice(document.activeElement.selectionStart, document.activeElement.selectionEnd)
    JS
    body.send_keys(:tab, :enter)
    assert_field "Title (optional)", with: "Newer saved title"
    assert_text "Newer saved body"
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
      click_button "Note actions"
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
    names = [ "Carnets de recherche documentaire", "Séances de préparation collective", "Entretiens et comptes rendus détaillés" ]
    %i[ research sessions interviews ].zip(names).each { |folder, name| note_folders(folder).update!(name:) }
    path = names.join(" / ")
    orbite_select_language("FR")
    orbite_viewport(375, 650)
    visit account_note_path(@account, @note)
    assert_selector "lexxy-editor[connected]"

    [ false, true ].each do |dark|
      orbite_theme(dark)
      assert_selector "h2#notes-reader-heading.sr-only", exact_text: "Éditeur de note", visible: :all
      assert_selector "[data-notes-accounts]", text: /CompteDeRecherche/
      assert_no_text(/translation missing|missing translation/i)
      context = find(".n-notes-editor-context", exact_text: path)
      assert_equal path, context[:title]
      context_layout = page.evaluate_script(<<~JS, context)
        (() => {
          const element = arguments[0], style = getComputedStyle(element)
          return { height: element.clientHeight, lineHeight: parseFloat(style.lineHeight),
                   truncated: element.scrollWidth > element.clientWidth, ellipsis: style.textOverflow === "ellipsis" }
        })()
      JS
      assert_in_delta context_layout.fetch("lineHeight"), context_layout.fetch("height"), 1
      assert context_layout.fetch("truncated")
      assert context_layout.fetch("ellipsis")
      overflow = page.evaluate_script(<<~JS)
        (() => {
          const main = document.querySelector("main")
          return [...main.querySelectorAll(".n-notes *")]
            .filter(element => element.getBoundingClientRect().right > main.getBoundingClientRect().left + main.clientWidth + 1)
            .map(element => [element.tagName, element.className, element.getBoundingClientRect().right])
        })()
      JS
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1"), overflow.inspect

      label = "writing-space-french-#{dark ? 'dark' : 'light'}"
      orbite_record(label, context_layout.merge(notes_writing_space), screenshot: true) if ENV["NOTES_WRITING_EVIDENCE"] == "1"
      {
        "a[data-notes-back]" => "Retour à la liste",
        "button[popovertarget^='note-actions-']" => "Actions de la note",
        ".n-notes-body-heading button" => "Mise en forme"
      }.each do |selector, name|
        assert_equal name, find(selector).native.accessible_name
        target = orbite_tab_to(selector)
        assert_operator target.fetch("height"), :>=, 44
        assert_operator target.fetch("width"), :>=, 44
      end
    end
  end

  test "Lexxy autosaves a formatted new note and changes identity without remounting the editor" do
    visit account_notes_workspace_path(@account, q: "Research")
    click_link "New note"
    editor = find("lexxy-editor[connected] .lexxy-editor__content")
    assert_selector "h2#notes-reader-heading.sr-only", exact_text: "New note", visible: :all
    within ".n-notes-editor-toolbar" do
      assert_link "Back to list"
      assert_no_button "Note actions"
    end
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
    assert_selector "h2#notes-reader-heading.sr-only", exact_text: "Note editor", visible: :all
    assert_button "Note actions"
    assert_equal account_note_path(@account, saved, q: "Research"),
      find(".n-language-preference input[name='return_to']", visible: :all).value
    refresh
    assert_selector "lexxy-editor[connected] .lexxy-editor__content strong", text: "Ideas"
    assert_text "#research"
  end

  test "keyboard index retry keeps a failed autosave draft and announces indexing on the same editor" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [role='status'][data-note-index-status='failed']", text: "Indexing failed"
    assert_selector ".n-notes-sharing", text: /saved, active notes are shared.*titles and text.*sent.*configured embedding provider.*relevant excerpts.*sent.*account chats.*authorized API requests.*local or remote/i
    watch_dirty_departure("Unsaved draft for indexing")

    retry_button = ".n-notes-index-status button"
    orbite_tab_to(retry_button)
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector ".n-notes-index-status [data-note-index-status='pending']:focus", text: "Indexing in progress"
    @note.update!(embedding_status: :ready, indexed_generation: 2)
    assert_selector ".n-notes-index-status [role='status'][data-note-index-status='ready']:focus", text: "Note indexed", wait: 8
    assert_no_selector retry_button
    assert_save_status "Could not save"
    assert_field "Title (optional)", with: "Unsaved draft for indexing"
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
    assert_current_path account_note_path(@account, @note)
    assert_equal 0, page.evaluate_script("window.departureConfirmations")
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
  end

  test "a queue outage after accepting the retry announces failure and preserves the dirty draft" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']", text: "Indexing failed"
    watch_dirty_departure("Dirty while the queue is unavailable")
    fail_enqueue = -> { raise SolidQueue::Job::EnqueueError, "Synthetic queue outage" }
    Note::IndexJob.set_callback(:enqueue, :before, fail_enqueue)
    retry_button = ".n-notes-index-status button"
    orbite_tab_to(retry_button)
    page.driver.browser.action.send_keys(:enter).perform

    assert_selector ".n-notes-index-status [role='status']", text: "Indexing retry failed to start. Try again."
    assert_selector ".n-notes-index-status [data-note-index-status='failed']", text: "Indexing failed"
    assert_selector "#{retry_button}:focus:enabled"
    assert_save_status "Could not save"
    assert_field "Title (optional)", with: "Dirty while the queue is unavailable"
    assert_equal [ "Field notes", 1, "failed" ], @note.reload.values_at(:title, :content_revision, :embedding_status)
    assert_current_path account_note_path(@account, @note)
    assert_equal 0, page.evaluate_script("window.departureConfirmations")
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
  ensure
    Note::IndexJob.skip_callback(:enqueue, :before, fail_enqueue) if fail_enqueue
  end

  test "index polls suspend while hidden stop at ready and restart on new save acknowledgments" do
    visit new_account_note_path(@account)
    assert_selector ".n-notes-index-status [data-note-index-status='empty']"
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS)
      window.originalNoteEditor = document.querySelector("lexxy-editor")
      window.indexPolls = 0
      window.hideNotesPage = hidden => {
        Object.defineProperty(document, "visibilityState", { configurable: true, value: hidden ? "hidden" : "visible" })
        Object.defineProperty(document, "hidden", { configurable: true, value: hidden })
        document.dispatchEvent(new Event("visibilitychange"))
      }
      const ordinaryFetch = window.fetch
      window.fetch = (url, options) => {
        if (new URL(url, location.origin).pathname.endsWith("/index_status")) window.indexPolls++
        return ordinaryFetch(url, options)
      }
      window.hideNotesPage(true)
    JS

    fill_in "Title (optional)", with: "Index new note"
    assert_save_status "Saved"
    assert_selector ".n-notes-index-status [data-note-index-status='pending']"
    saved = @account.notes.find_by!(title: "Index new note")
    saved.update!(embedding_status: :ready, indexed_generation: saved.embedding_generation)
    assert_poll_count_stays(0)

    page.execute_script("window.hideNotesPage(false)")
    assert_selector ".n-notes-index-status [data-note-index-status='ready']", wait: 8
    assert_poll_count_stays(1)

    fill_in "Title (optional)", with: "Index a later edit"
    assert_save_status "Saved"
    assert_selector ".n-notes-index-status [data-note-index-status='pending']"
    saved.reload.mark_index_failed(saved.embedding_generation)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']", wait: 8
    assert_save_status "Saved"
    assert_button "Retry indexing"
    assert_equal 2, page.evaluate_script("window.indexPolls")
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
  end

  test "a delayed retry response cannot overwrite a newer index generation on the same content revision" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    find("lexxy-editor[connected]")
    fail_enqueue = -> { throw :abort }
    Note::IndexJob.set_callback(:enqueue, :before, fail_enqueue)
    hold_index_retry(@note)
    click_button "Retry indexing"
    assert_selector ".n-notes-index-status[aria-busy=true]"
    assert_equal 200, retrieve_held_retry_status
    # An embedding-space rebuild can advance the generation without editing the note.
    @note.update_columns(embedding_generation: 3, embedding_status: :pending)
    fill_in "Title (optional)", with: "Field notes  "
    assert_save_status "Saved"
    assert_equal 1, @note.reload.content_revision
    assert_selector ".n-notes-index-status [data-note-index-status='pending']", text: "Indexing in progress"

    release_index_retry
    assert_no_selector ".n-notes-index-status[aria-busy=true]"
    assert_selector ".n-notes-index-status [data-note-index-status='pending']", text: "Indexing in progress", wait: 0
    assert_no_text "Indexing retry failed to start. Try again.", wait: 0
    assert_save_status "Saved"
  ensure
    Note::IndexJob.skip_callback(:enqueue, :before, fail_enqueue) if fail_enqueue
  end

  test "a newly failed generation can retry before an older retry response returns" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    fail_enqueue = -> { raise SolidQueue::Job::EnqueueError, "Synthetic queue outage" }
    Note::IndexJob.set_callback(:enqueue, :before, fail_enqueue)
    hold_index_retry(@note)
    click_button "Retry indexing"
    assert_equal 200, retrieve_held_retry_status(2)

    fill_in "Title (optional)", with: "Field notes  "
    assert_save_status "Saved"
    assert_equal [ 1, 2 ], @note.reload.values_at(:content_revision, :embedding_generation)
    refute page.evaluate_script("window.heldIndexRetries[2].signal.aborted")

    fill_in "Title (optional)", with: "Saved generation three"
    assert_save_status "Saved"
    assert_selector ".n-notes-index-status[data-generation='3'] [data-note-index-status='failed']", wait: 8
    assert_equal [ 2, 3, "failed" ], @note.reload.values_at(:content_revision, :embedding_generation, :embedding_status)
    Note::IndexJob.skip_callback(:enqueue, :before, fail_enqueue)
    fail_enqueue = nil

    watch_dirty_departure("My unsaved follow-up")
    retry_button = ".n-notes-index-status button"
    orbite_tab_to(retry_button)
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#{retry_button}:focus[aria-disabled='true']"
    assert_equal 200, retrieve_held_retry_status(3)
    assert page.evaluate_script("window.heldIndexRetries[2].signal.aborted")
    refute page.evaluate_script("window.heldIndexRetries[3].signal.aborted")

    release_index_retry(2)
    assert_selector ".n-notes-index-status[aria-busy='true']", wait: 0
    assert_selector "#{retry_button}:focus[aria-disabled='true']", wait: 0
    assert_no_text "Indexing retry failed to start. Try again.", wait: 0

    release_index_retry(3)
    assert_selector ".n-notes-index-status [data-note-index-status='pending']:focus"
    assert_no_selector ".n-notes-index-status[aria-busy='true']"
    assert_field "Title (optional)", with: "My unsaved follow-up"
    assert_save_status "Could not save"
    assert_equal [ "Saved generation three", 2, 3, "pending" ],
      @note.reload.values_at(:title, :content_revision, :embedding_generation, :embedding_status)
    assert_equal 0, page.evaluate_script("window.departureConfirmations")
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
  ensure
    Note::IndexJob.skip_callback(:enqueue, :before, fail_enqueue) if fail_enqueue
  end

  test "a delayed retry from a previous note cannot claim a new editor or its retry form" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    previous_frame = find("turbo-frame.n-notes-index-status")[:id]
    previous_id = @note.id
    fail_previous_retry = -> { throw :abort if arguments.first == previous_id }
    Note::IndexJob.set_callback(:enqueue, :before, fail_previous_retry)
    hold_index_retry(@note)
    click_button "Retry indexing"
    assert_equal 200, retrieve_held_retry_status
    assert @note.reload.embedding_failed?

    click_link "New note"
    assert_current_path new_account_note_path(@account), ignore_query: true
    assert_selector ".n-notes-index-status [data-note-index-status='empty']"
    find("lexxy-editor[connected]")
    page.execute_script("window.newNoteEditor = document.querySelector('lexxy-editor')")
    assert page.evaluate_script("window.heldIndexRetry.signal.aborted")
    release_index_retry
    assert_selector ".n-notes-index-status [data-note-index-status='empty']", wait: 0
    assert_no_button "Retry indexing", wait: 0
    assert_nil find("turbo-frame.n-notes-index-status")["data-status-url"]

    fill_in "Title (optional)", with: "Unrelated new note"
    assert_save_status "Saved"
    saved = @account.notes.find_by!(title: "Unrelated new note")
    assert_current_path account_note_path(@account, saved), ignore_query: true
    assert_selector ".n-notes-index-status [data-note-index-status='pending']"
    assert_equal account_note_index_status_path(@account, saved), find("turbo-frame.n-notes-index-status")["data-status-url"]

    saved.mark_index_failed(saved.embedding_generation)
    retry_path = account_note_index_retry_path(@account, saved)
    assert_selector ".n-notes-index-status form[action='#{retry_path}']", wait: 8
    frame = find("turbo-frame.n-notes-index-status")[:id]
    refute_equal previous_frame, frame
    assert_selector "##{frame} form[action='#{retry_path}'][data-turbo='false']"
    orbite_tab_to("##{frame} button")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector ".n-notes-index-status [data-note-index-status='pending']:focus"
    assert saved.reload.embedding_pending?
    assert @note.reload.embedding_failed?
    assert page.evaluate_script("window.newNoteEditor === document.querySelector('lexxy-editor')")
  ensure
    Note::IndexJob.skip_callback(:enqueue, :before, fail_previous_retry) if fail_previous_retry
  end

  test "a delayed retry cannot replace or announce in a reopened editor for the same note" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    other = Note.save_draft!(account: @account, folder: @note.note_folder, draft_key: SecureRandom.uuid,
      title: "Other note to open", body_html: "")
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    fail_enqueue = -> { throw :abort }
    Note::IndexJob.set_callback(:enqueue, :before, fail_enqueue)
    hold_index_retry(@note)
    page.execute_script("window.originalNoteEditor = document.querySelector('lexxy-editor')")
    click_button "Retry indexing"
    assert_equal 200, retrieve_held_retry_status

    click_link "Other note to open"
    assert_current_path account_note_path(@account, other), ignore_query: true
    click_link "Field notes"
    assert_current_path account_note_path(@account, @note), ignore_query: true
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    refute page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
    page.execute_script(<<~JS)
      window.reopenedEditor = document.querySelector("lexxy-editor")
      window.reopenedFrame = document.querySelector(".n-notes-index-status")
    JS
    assert page.evaluate_script("window.heldIndexRetry.signal.aborted")
    release_index_retry
    assert_no_text "Indexing retry failed to start. Try again.", wait: 0
    assert_selector ".n-notes-index-status [data-note-index-status='failed']", wait: 0
    assert_button "Retry indexing"
    assert_current_path account_note_path(@account, @note), ignore_query: true
    assert page.evaluate_script("window.reopenedEditor === document.querySelector('lexxy-editor')")
    assert page.evaluate_script("window.reopenedFrame === document.querySelector('.n-notes-index-status')")
  ensure
    Note::IndexJob.skip_callback(:enqueue, :before, fail_enqueue) if fail_enqueue
  end

  test "a stale retry observes newer pending work without enqueueing it again" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    @note.edit_content!(expected_revision: 1, title: "Edited in another window", body_html: @note.body_html)
    assert_equal [ "pending", 3 ], @note.reload.values_at(:embedding_status, :embedding_generation)

    click_button "Retry indexing"
    assert_selector ".n-notes-index-status [role='status']", text: "Indexing state changed."
    assert_selector ".n-notes-index-status [data-note-index-status='pending']", wait: 0
    assert_no_button "Retry indexing"
    assert_field "Title (optional)", with: "Field notes"
  end

  test "a stale retry refreshes the current failed status without saving a dirty draft" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    watch_dirty_departure("My local draft")
    member = users(:picker_outsider)
    @account.account_users.grant_to(member)
    editor = ActionDispatch::Integration::Session.new(Rails.application)
    editor.post login_path, params: { email: member.email, password: "picker-password-123" }
    editor.patch account_note_path(@account, @note), params: {
      note: { title: "Saved by another member", body_html: "<p>Member's saved text</p>", expected_revision: 1 }
    }
    assert_equal 303, editor.response.status
    @note.reload.mark_index_failed(3)
    before_retry = @note.reload.values_at(:title, :body_html, :content_revision, :embedding_generation)
    retry_button = ".n-notes-index-status button"

    orbite_tab_to(retry_button)
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector ".n-notes-index-status [role='status']", text: "Indexing state changed. Check the current status before retrying."
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    assert_selector "#{retry_button}:focus:enabled"
    assert @note.reload.embedding_failed?
    assert_equal before_retry, @note.values_at(:title, :body_html, :content_revision, :embedding_generation)
    assert_field "Title (optional)", with: "My local draft"
    assert_save_status "Could not save"
    assert_equal 0, page.evaluate_script("window.departureConfirmations")
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")

    page.driver.browser.action.send_keys(:enter).perform
    assert_selector ".n-notes-index-status [data-note-index-status='pending']:focus"
    assert @note.reload.embedding_pending?
    assert_equal before_retry, @note.values_at(:title, :body_html, :content_revision, :embedding_generation)
    assert_field "Title (optional)", with: "My local draft"
  end

  test "an in-flight index poll is canceled by a newer autosave and cannot show its stale result" do
    @note.update!(embedding_status: :pending, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='pending']"
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS)
      window.originalNoteEditor = document.querySelector("lexxy-editor")
      window.indexPolls = 0
      const ordinaryFetch = window.fetch
      window.fetch = async (url, options) => {
        if (!new URL(url, location.origin).pathname.endsWith("/index_status") || ++window.indexPolls !== 1) {
          return ordinaryFetch(url, options)
        }
        window.oldPollSignal = options.signal
        const response = await ordinaryFetch(url, options)
        const html = await response.text()
        return new Promise(resolve => {
          window.releaseOldPoll = () => resolve({ ok: true, text: async () => {
            window.deliveredOldPoll = true
            return html
          } })
        })
      }
    JS
    @note.update!(embedding_status: :ready, indexed_generation: 2)
    Selenium::WebDriver::Wait.new(timeout: 8).until { page.evaluate_script("Boolean(window.releaseOldPoll)") }

    fill_in "Title (optional)", with: "A real newer revision"
    assert_save_status "Saved"
    assert_equal [ 2, 3 ], @note.reload.values_at(:content_revision, :embedding_generation)
    assert page.evaluate_script("window.oldPollSignal.aborted")
    page.execute_script("window.releaseOldPoll()")
    orbite_settle
    assert page.evaluate_script("window.deliveredOldPoll")
    assert_selector ".n-notes-index-status [data-note-index-status='pending']", wait: 0
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")

    @note.mark_index_failed(3)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']", wait: 8
    assert_save_status "Saved"
    assert_poll_count_stays(2)
  end

  test "a same-generation save leaves a pending index poll in flight" do
    @note.update!(embedding_status: :pending, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='pending']"
    page.execute_script(<<~JS)
      const ordinaryFetch = window.fetch
      window.fetch = async (url, options) => {
        const response = await ordinaryFetch(url, options)
        if (!new URL(url, location.origin).pathname.endsWith("/index_status") || window.releaseSameGenerationPoll) return response

        window.sameGenerationPoll = options.signal
        const body = await response.text()
        return new Promise(resolve => {
          window.releaseSameGenerationPoll = () => resolve(new Response(body, { status: response.status, headers: response.headers }))
        })
      }
    JS
    Selenium::WebDriver::Wait.new(timeout: 8).until { page.evaluate_script("Boolean(window.releaseSameGenerationPoll)") }

    fill_in "Title (optional)", with: "Field notes  "
    assert_save_status "Saved"
    assert_equal [ 1, 2 ], @note.reload.values_at(:content_revision, :embedding_generation)
    refute page.evaluate_script("window.sameGenerationPoll.aborted")

    page.execute_script("window.releaseSameGenerationPoll()")
    @note.mark_index_failed(2)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']", wait: 8
    assert_save_status "Saved"
  end

  test "an indexing status error stops the poll without replacing the editor or save feedback" do
    @note.update!(embedding_status: :pending, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='pending']"
    find("lexxy-editor[connected]")
    page.execute_script(<<~JS)
      window.originalNoteEditor = document.querySelector("lexxy-editor")
      window.indexPolls = 0
      const ordinaryFetch = window.fetch
      window.fetch = (url, options) => {
        if (!new URL(url, location.origin).pathname.endsWith("/index_status")) return ordinaryFetch(url, options)
        window.indexPolls++
        return Promise.resolve(new Response("", { status: 404 }))
      }
    JS
    assert_selector ".n-notes-index-status [role='status']", text: "Could not check indexing status.", wait: 8
    assert_poll_count_stays(1)
    assert_field "Title (optional)", with: "Field notes"
    assert_no_selector "[data-note-autosave-target='status']", text: "Could not"
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
  end

  test "a retry request error leaves a keyboard user at the retry control" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"
    page.execute_script(<<~JS)
      const ordinaryFetch = window.fetch
      window.fetch = (url, options) => {
        if (!new URL(url, location.origin).pathname.endsWith("/index_retry")) return ordinaryFetch(url, options)
        return new Promise(resolve => { window.failIndexRetry = () => resolve(new Response("", { status: 503 })) })
      }
    JS
    orbite_tab_to(".n-notes-index-status button")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector ".n-notes-index-status[aria-busy=true]"
    # Let Chromium update focus after Turbo disables the submit button.
    orbite_settle
    page.execute_script("window.failIndexRetry()")

    assert_selector ".n-notes-index-status [role='status']", text: "Could not retry indexing."
    assert_selector ".n-notes-index-status button:focus:enabled"
    assert_current_path account_note_path(@account, @note)
  end

  test "a note can retry indexing without scripts" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']"

    click_button "Retry indexing"
    assert_current_path account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='pending']"
    assert_equal [ "Field notes", 1, 2, "pending" ],
      @note.reload.values_at(:title, :content_revision, :embedding_generation, :embedding_status)
  end

  test "French indexing controls fit narrow and tablet panes in both themes" do
    @note.update!(embedding_status: :failed, embedding_generation: 2)
    orbite_select_language("FR")
    visit account_note_path(@account, @note)
    assert_selector ".n-notes-index-status [data-note-index-status='failed']", text: "Échec de l’indexation"
    assert_selector ".n-notes-sharing", text: /notes enregistrées et actives.*partagées.*titres et textes.*envoyés.*fournisseur d’embeddings configuré.*extraits pertinents.*envoyés.*conversations du compte.*requêtes API autorisées.*locaux ou distants/i

    [ [ 375, 340, false ], [ 667, 375, true ], [ 768, 850, false ], [ 1024, 850, true ], [ 1440, 850, false ] ].each do |width, height, dark|
      orbite_viewport(width, height)
      orbite_theme(dark)
      assert_button "Relancer l’indexation"
      orbite_tab_to(".n-notes-index-status button") if width == 1024
      assert page.evaluate_script(<<~JS)
        (() => {
          const button = document.querySelector(".n-notes-index-status button").getBoundingClientRect()
          const main = document.querySelector("main")
          return button.width >= 44 && button.height >= 44 && main.scrollWidth <= main.clientWidth + 1
        })()
      JS
    end
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

    submit_folder_trash(folder)
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
    submit_folder_trash(folder)
    assert_selector "#trash-folder-#{folder.id}:popover-open button[type=submit]", text: "Trash folder"
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
    submit_folder_trash(folder)
    assert_selector "#trash-folder-#{folder.id}:popover-open button[type=submit]", text: "Trash folder"
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
      accept_confirm(/all its folders and notes/) { submit_folder_trash(parent) }
      assert_current_path account_notes_workspace_path(@account, view: "trash")
    end

    submit_folder_trash(folder)
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

  test "a failed visit superseding Turbo Back returns to the original editor history entry" do
    list = account_notes_workspace_path(@account, q: "outline")
    editor_path = account_note_path(@account, @note, q: "outline")
    new_note = new_account_note_path(@account, q: "outline")
    visit list
    click_on "Field notes"
    assert_current_path editor_path
    hold_notes_get(list, new_note, answers: [ true, true ])
    editor_history = page.evaluate_script("[history.length, history.state.turbo]")
    fill_in "Title (optional)", with: "Keep after superseding Back"
    assert_save_status "Could not save"

    page.execute_script("history.back()")
    wait_for_held_notes_get(list)
    assert_current_path list
    click_on "New note"
    wait_for_held_notes_get(new_note)
    assert page.evaluate_script("window.abortedNotesGets.includes(arguments[0])", list)
    page.execute_script("window.releaseNotesGet({ fail: true })")
    assert_save_status "Could not open that page. Your draft is still here."

    assert_current_path editor_path
    assert_equal editor_history, page.evaluate_script("[history.length, history.state.turbo]")
    assert_field "Title (optional)", with: "Keep after superseding Back"
    assert_equal 2, page.evaluate_script("window.visitWarnings")
    page.execute_script("window.fetch = window.ordinaryFetch")
    click_on "Save note"
    assert_save_status "Saved"
    assert_current_path editor_path
    assert_equal [ "Keep after superseding Back", 2 ], @note.reload.values_at(:title, :content_revision)

    page.go_back
    assert_current_path list
    assert_selector "[data-notes-screen='list']"
    page.go_forward
    assert_current_path editor_path
    assert_field "Title (optional)", with: "Keep after superseding Back"
    assert_equal editor_history, page.evaluate_script("[history.length, history.state.turbo]")
  end

  test "declining a real unmarked 404 after a late edit retains the Notes head and styling" do
    destination = Note.save_draft!(account: @account, folder: @note.note_folder, draft_key: SecureRandom.uuid,
      title: "Deleted destination", body_html: "")
    editor_path = account_note_path(@account, @note, folder_id: @note.note_folder_id)
    destination_path = account_note_path(@account, destination, folder_id: @note.note_folder_id)
    visit editor_path
    hold_notes_get(destination_path)
    page.execute_script(<<~JS)
      window.originalNoteEditor = document.querySelector("lexxy-editor")
      window.notePageHead = () => [document.title,
        Array.from(document.head.querySelectorAll("link[rel=stylesheet]"), link => link.href),
        getComputedStyle(document.querySelector(".n-notes-workspace")).display]
    JS
    original_head = page.evaluate_script("window.notePageHead()")
    assert_equal "grid", original_head.last
    refute_empty original_head[1]
    original_history = page.evaluate_script("[history.length, history.state.turbo]")
    destination.trash
    destination.purge(by: users(:picker_owner))

    within("#notes-list") { click_on "Deleted destination" }
    wait_for_held_notes_get
    assert_equal 0, page.evaluate_script("window.visitWarnings")
    fill_in "Title (optional)", with: "Keep the styled draft"
    assert_save_status "Could not save"
    page.execute_script("window.releaseNotesGet()")
    assert_http_departure_status 404
    assert_nil page.evaluate_script("window.departureRecovery")

    assert_current_path editor_path
    assert_field "Title (optional)", with: "Keep the styled draft"
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
    assert_equal 1, page.evaluate_script("window.visitWarnings")
    assert_equal original_history, page.evaluate_script("[history.length, history.state.turbo]")
    assert_equal original_head, page.evaluate_script("window.notePageHead()")
    refute page.evaluate_script("document.documentElement.hasAttribute('aria-busy')")
    refute page.evaluate_script("window.dispatchEvent(new Event('beforeunload', { cancelable: true }))")
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

  test "declining the late discard for a Pin 404 keeps the styled draft and lets it be copied" do
    editor_path = account_note_path(@account, @note, folder_id: @note.note_folder_id)
    pin_path = account_note_pin_path(@account, @note, folder_id: @note.note_folder_id)
    visit editor_path
    hold_notes_requests(pin_path)
    original_history = page.evaluate_script("[history.length, history.state.turbo]")
    page.execute_script(<<~JS)
      window.originalNoteEditor = document.querySelector("lexxy-editor")
      window.noteHead = () => [document.title,
        Array.from(document.head.querySelectorAll("link[rel=stylesheet]"), link => link.href),
        getComputedStyle(document.querySelector(".n-notes-workspace")).display]
    JS
    head = page.evaluate_script("window.noteHead()")
    assert_equal "grid", head.last
    click_button "Note actions"
    click_on "Pin in folder"
    wait_for_held_notes_request(pin_path)
    assert_equal 0, page.evaluate_script("window.visitWarnings")

    fill_in "Title (optional)", with: "Local draft after a failed pin"
    assert_save_status "Could not save"
    @note.trash
    @note.purge(by: users(:picker_owner))
    page.execute_script("window.releaseNotesRequest()")
    assert_stored_form_error 404

    assert_current_path editor_path
    assert_field "Title (optional)", with: "Local draft after a failed pin"
    assert_nil page.evaluate_script("sessionStorage.getItem('notesFormRecovery')")
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
    assert_equal head, page.evaluate_script("window.noteHead()")
    assert_equal original_history, page.evaluate_script("[history.length, history.state.turbo]")
    assert_save_status "Could not complete that action. Your draft is still here."
    assert_equal 1, page.evaluate_script("window.visitWarnings")
    click_on "Copy draft"
    assert_text "Draft copied"
    assert_equal "Local draft after a failed pin\n\nInterview outline", page.evaluate_script("window.copiedNote")
    refute page.evaluate_script("window.dispatchEvent(new Event('beforeunload', { cancelable: true }))")
    refute NotePin.exists?(note_id: @note.id)
  end

  test "accepting late discard after a Pin membership 404 shows the actual error without reloading" do
    editor_path = account_note_path(@account, @note, folder_id: @note.note_folder_id)
    visit editor_path
    pin_path = account_note_pin_path(@account, @note, folder_id: @note.note_folder_id)
    hold_notes_requests(pin_path, answers: [ true ])
    page.execute_script("window.pinDocument = true")
    click_button "Note actions"
    click_on "Pin in folder"
    wait_for_held_notes_request(pin_path)
    fill_in "Title (optional)", with: "Discard after pin fails"
    assert_save_status "Could not save"
    @account.account_users.find_by!(user: users(:picker_owner)).destroy!
    page.execute_script("window.releaseNotesRequest()")

    assert_stored_form_error 404
    assert_selector "body .exception-message, body.rails-default-error-page"
    assert_no_selector "lexxy-editor"
    assert page.evaluate_script("window.pinDocument")
    assert_current_path editor_path
    assert_equal 1, page.evaluate_script("window.visitWarnings")
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
    refute NotePin.exists?(note_id: @note.id)
  end

  test "a real folder trash 409 superseding Back restores the original editor history" do
    list = account_notes_workspace_path(@account, q: "outline")
    folder = @note.note_folder
    editor_path = account_note_path(@account, @note, folder_id: folder.id)
    trash_path = account_note_folder_trashing_path(@account, folder)
    visit list
    page.execute_script("Turbo.visit(arguments[0])", editor_path)
    assert_current_path editor_path
    hold_notes_requests(list, trash_path, answers: [ true, true, true ])
    original_history = page.evaluate_script("[history.length, history.state.turbo]")
    fill_in "Title (optional)", with: "Keep through failed trash"
    assert_save_status "Could not save"

    page.execute_script("history.back()")
    wait_for_held_notes_request(list)
    assert_current_path list
    folder.parent.trash
    submit_folder_trash(folder)
    wait_for_held_notes_request(trash_path)
    assert page.evaluate_script("window.abortedNotesRequests.includes(arguments[0])", list)
    page.execute_script("window.releaseNotesRequest()")
    assert_http_departure_status 409
    assert_save_status "This change is not available."
    assert_current_path editor_path
    assert_equal original_history, page.evaluate_script("[history.length, history.state.turbo]")
    assert_field "Title (optional)", with: "Keep through failed trash"
    assert_button "Copy draft"
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)
  end

  test "late edits can stop a successful Pin redirect without losing the draft" do
    editor_path = account_note_path(@account, @note, folder_id: @note.note_folder_id)
    visit editor_path
    pin_path = account_note_pin_path(@account, @note, folder_id: @note.note_folder_id)
    hold_notes_requests(pin_path)
    page.execute_script("window.originalNoteEditor = document.querySelector('lexxy-editor')")
    click_button "Note actions"
    click_on "Pin in folder"
    wait_for_held_notes_request(pin_path)
    fill_in "Title (optional)", with: "Keep despite successful pin"
    assert_save_status "Could not save"
    page.execute_script("window.releaseNotesRequest()")
    assert_http_departure_status 200

    assert_field "Title (optional)", with: "Keep despite successful pin"
    assert page.evaluate_script("window.originalNoteEditor === document.querySelector('lexxy-editor')")
    assert_equal 1, page.evaluate_script("window.visitWarnings")
    assert_current_path editor_path
    assert_button "Copy draft"
    assert NotePin.exists?(note_id: @note.id)
    assert_equal [ "Field notes", 1 ], @note.reload.values_at(:title, :content_revision)
    page.execute_script("window.fetch = window.ordinaryFetch")
    click_on "Save note"
    assert_save_status "Saved"
    assert_equal [ "Keep despite successful pin", 2 ], @note.reload.values_at(:title, :content_revision)
  end

  test "cancelling a folder trash action that supersedes Back restores the editor entry" do
    list = account_notes_workspace_path(@account, q: "outline")
    folder = @note.note_folder
    editor_path = account_note_path(@account, @note, folder_id: folder.id)
    visit list
    page.execute_script("Turbo.visit(arguments[0])", editor_path)
    assert_current_path editor_path
    hold_notes_requests(list, answers: [ true, false ])
    original_history = page.evaluate_script("[history.length, history.state.turbo]")
    fill_in "Title (optional)", with: "Keep after cancelled trash"
    assert_save_status "Could not save"

    page.execute_script("history.back()")
    wait_for_held_notes_request(list)
    assert_current_path list
    submit_folder_trash(folder)
    Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
      page.evaluate_script("window.visitWarnings === 2")
    end
    assert_current_path editor_path
    assert_equal original_history, page.evaluate_script("[history.length, history.state.turbo]")
    assert_field "Title (optional)", with: "Keep after cancelled trash"
    refute NoteFolderTrashing.exists?(note_folder_id: folder.id)

    page.execute_script("window.fetch = window.ordinaryFetch")
    click_on "Save note"
    assert_save_status "Saved"
    click_on "New note"
    assert_current_path new_account_note_path(@account, folder_id: folder.id)
    assert_field "Title (optional)", with: ""
    assert_equal original_history.last.fetch("restorationIndex") + 1, page.evaluate_script("history.state.turbo.restorationIndex")
    page.go_back
    assert_current_path editor_path
    assert_field "Title (optional)", with: "Keep after cancelled trash"
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
    submit_folder_trash(folder)

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

    click_button "Note actions"
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
      closed = notes_writing_space
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
      assert_equal "false", toggle["aria-expanded"]
      assert_in_delta closed.fetch("bodyHeight"), notes_writing_space.fetch("bodyHeight"), 1
    end
  end

  test "formatting the note text and closing the toolbar preserves the draft" do
    orbite_viewport(375, 650)
    visit account_note_path(@account, @note)
    editor = find("lexxy-editor[connected] .lexxy-editor__content")
    editor.send_keys([ :control, "a" ])
    orbite_tab_to(".n-notes-body-heading button", reverse: true)
    page.driver.browser.action.send_keys(:enter).perform
    bold = find("lexxy-toolbar button[name=bold]")
    bold.click
    assert_selector ".lexxy-editor__content strong", exact_text: "Interview outline"
    find_button("Formatting").send_keys(:enter)
    assert_no_selector "lexxy-toolbar"
    assert_selector ".n-notes-body-heading button[aria-expanded=false]:focus"
    assert_selector ".lexxy-editor__content strong", exact_text: "Interview outline"
    click_on "Save note"
    assert_save_status "Saved"
    assert_includes @note.reload.body_html, "<strong>Interview outline</strong>"
  end

  private
    def notes_index_geometry
      page.evaluate_script(<<~JS)
        (() => {
          const main = document.querySelector("main")
          const contentTop = main.getBoundingClientRect().top + main.clientTop
          const bounds = (selector) => {
            const rect = document.querySelector(selector)?.getBoundingClientRect()
            return rect ? { top: rect.top, bottom: rect.bottom } : null
          }
          return {
            mainScroll: main.scrollTop,
            pageScroll: window.scrollY,
            viewportTop: Math.max(0, contentTop),
            viewportBottom: Math.min(innerHeight, contentTop + main.clientHeight),
            message: bounds("[data-note-index-status-target=message]"),
            retry: bounds(".n-notes-index-status button")
          }
        })()
      JS
    end

    def notes_writing_space
      page.evaluate_script(<<~JS)
        (() => {
          const main = document.querySelector("main")
          const rect = (selector) => document.querySelector(selector).getBoundingClientRect()
          const box = rect("lexxy-editor[connected] .lexxy-editor__content")
          const center = ({ top, height }) => top + height / 2
          return {
            top: box.top,
            visible: Math.max(0, Math.min(box.bottom, innerHeight, main.getBoundingClientRect().bottom) - Math.max(0, box.top)),
            bodyHeight: box.height,
            overflow: main.scrollWidth - main.clientWidth,
            pageOverflow: document.documentElement.scrollWidth - innerWidth,
            labelCenter: center(rect("label[for='notes-body']")),
            formattingCenter: center(rect("button[aria-controls='notes-formatting']"))
          }
        })()
      JS
    end

    def choose_move_destination(label)
      click_button "Note actions"
      click_button "Move note"
      within notes_open_move_panel do
        select label, from: "Destination folder"
        assert_select "Destination folder", selected: label
      end
      assert_selector "#{notes_open_move_panel} select:focus"
    end

    def notes_move_trigger
      id = "note-move-#{@note.id}"
      "button:is([popovertarget='#{id}'], [commandfor='#{id}']):not([popovertargetaction=hide])"
    end

    def notes_open_move_panel
      "#note-move-#{@note.id}:is(:popover-open, :modal)"
    end

    def open_folder_trash_confirmation(folder)
      actions = "#folder-actions-#{folder.id}:popover-open"
      confirmation = "#trash-folder-#{folder.id}:is(:popover-open, :modal)"
      within "#notes-list" do
        click_button "Folder actions" unless has_selector?(actions, wait: 0)
        within(actions) { click_button "Trash folder" } unless has_selector?(confirmation, wait: 0)
      end
      confirmation
    end

    def submit_folder_trash(folder)
      within(open_folder_trash_confirmation(folder)) { click_button "Trash folder" }
    end

    def notes_layout(reference)
      page.evaluate_script(<<~JS, reference)
        (() => {
          const main = document.querySelector("main")
          const box = document.querySelector(arguments[0]).getBoundingClientRect()
          return [box.toJSON(), main.scrollTop, main.scrollLeft, window.scrollY]
        })()
      JS
    end

    def assert_anchored_notes_dropdown(id)
      sample = page.evaluate_script(<<~JS, id)
        (() => {
          const trigger = document.querySelector(`button[popovertarget="${arguments[0]}"]:not([popovertargetaction="hide"]),
            button[commandfor="${arguments[0]}"][command=show-modal]`)
          const panel = document.getElementById(arguments[0])
          return { anchor: trigger.getBoundingClientRect().toJSON(), panel: panel.getBoundingClientRect().toJSON(),
            open: panel.matches(":popover-open, :modal"), viewport: [innerWidth, innerHeight] }
        })()
      JS
      assert sample.fetch("open")
      panel, anchor = sample.values_at("panel", "anchor")
      width, height = sample.fetch("viewport")
      assert_operator panel.fetch("left"), :>=, 0, sample.inspect
      assert_operator panel.fetch("right"), :<=, width, sample.inspect
      assert_operator panel.fetch("top"), :>=, 0, sample.inspect
      assert_operator panel.fetch("bottom"), :<=, height, sample.inspect
      gap = [ panel.fetch("top") - anchor.fetch("bottom"), anchor.fetch("top") - panel.fetch("bottom") ].max
      assert_operator gap, :>=, 0, sample.inspect
      assert_operator gap, :<=, 8, sample.inspect
      assert_operator panel.fetch("left"), :<=, anchor.fetch("right"), sample.inspect
      assert_operator panel.fetch("right"), :>=, anchor.fetch("left"), sample.inspect
      sample
    end

    def remove_notes_support_rules(property)
      page.evaluate_script(<<~JS, property)
        (() => {
          const property = arguments[0]
          const removeRules = (sheet) => {
            let removed = 0
            for (let i = sheet.cssRules.length - 1; i >= 0; i--) {
              const rule = sheet.cssRules[i]
              if (rule instanceof CSSSupportsRule && rule.conditionText.includes(`(${property}:`)) {
                sheet.deleteRule(i)
                removed++
              } else if (rule.cssRules) {
                removed += removeRules(rule)
              }
            }
            return removed
          }
          return [...document.styleSheets].reduce((count, sheet) => count + removeRules(sheet), 0)
        })()
      JS
    end

    def hold_note_save_response(hold_request: false)
      page.execute_script(<<~JS, hold_request)
        const normalFetch = window.fetch
        const gate = new Promise(resolve => { window.releaseNoteSave = resolve })
        const holdRequest = arguments[0]
        window.fetch = (...args) => {
          if (args[1]?.method !== "PATCH") return normalFetch(...args)
          if (holdRequest) return gate.then(() => normalFetch(...args))

          const result = normalFetch(...args)
          return result.then(response => gate.then(() => response))
        }
      JS
    end

    def assert_notes_dropdown(id, reference)
      trigger = "button[popovertarget='#{id}']"
      panel = "##{id}:popover-open"
      first_item = "#{panel} > form:first-child > button, #{panel} > ul > li:first-child > a"
      assert_selector trigger
      orbite_tab_to(trigger)
      before = notes_layout(reference)

      page.driver.browser.action.send_keys(:enter).perform
      assert_selector panel
      orbite_assert_reachable(panel)
      assert_equal before, notes_layout(reference)
      yield panel if block_given?
      orbite_tab_to(first_item)
      page.driver.browser.action.send_keys(:escape).perform
      assert_no_selector panel, visible: :all
      assert_selector "#{trigger}:focus"
      assert_equal before, notes_layout(reference)

      page.driver.browser.action.send_keys(:enter).perform
      assert_selector panel
      orbite_tab_to(first_item)
      page.driver.browser.action.move_to_location(2, 2).click.perform
      assert_no_selector panel, visible: :all
      assert_no_selector "#{trigger}:focus"
      assert_equal before, notes_layout(reference)
    end

    def assert_account_label_fits(label)
      assert page.evaluate_script(<<~JS, label), "The account label should wrap inside #{label.tag_name}"
        (() => {
          const label = arguments[0], bounds = label.getBoundingClientRect()
          const range = document.createRange()
          range.selectNodeContents(label)
          const text = range.getBoundingClientRect()
          return text.left >= bounds.left - 1 && text.right <= bounds.right + 1 &&
            text.top >= bounds.top - 1 && text.bottom <= bounds.bottom + 1
        })()
      JS
    end

    def hold_notes_requests(*paths, answers: [ false ])
      find("lexxy-editor[connected]")
      page.execute_script(<<~JS, paths, answers)
        const [paths, answers] = arguments
        const destinations = new Map(paths.map(path => [new URL(path, location.origin).href, path]))
        window.ordinaryFetch = window.fetch
        window.visitWarnings = 0
        window.abortedNotesRequests = []
        sessionStorage.removeItem("notesFormStatus")
        sessionStorage.removeItem("notesFormRecovery")
        window.confirm = () => {
          const answer = answers[window.visitWarnings++] ?? false
          return answer
        }
        window.fetch = (url, options) => {
          if (options?.method === "PATCH") return Promise.reject(new TypeError("Hold the autosave"))
          if (!destinations.has(url) || (new Headers(options.headers)).has("X-Sec-Purpose")) return window.ordinaryFetch(url, options)
          const path = destinations.get(url)
          return new Promise((resolve, reject) => {
            window.heldNotesRequest = path
            window.releaseNotesRequest = () => resolve(window.ordinaryFetch(url, { ...options, cache: "no-store" }))
            options.signal.addEventListener("abort", () => {
              window.abortedNotesRequests.push(path)
              reject(new DOMException("Aborted", "AbortError"))
            }, { once: true })
          })
        }
        document.addEventListener("turbo:before-fetch-response", event => {
          if (event.target === document.documentElement || event.target.matches("form")) {
            const response = event.detail.fetchResponse
            window.departureStatus = response.statusCode
            window.departureRecovery = response.header("X-Notes-Draft-Recovery")
            if (event.target.matches("form")) {
              sessionStorage.setItem("notesFormStatus", response.statusCode)
              if (window.departureRecovery) sessionStorage.setItem("notesFormRecovery", window.departureRecovery)
            }
          }
        })
        Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
          writeText(text) { window.copiedNote = text; return Promise.resolve() }
        } })
      JS
    end

    def wait_for_held_notes_request(path)
      Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
        page.evaluate_script("window.heldNotesRequest === arguments[0]", path)
      end
    end

    def assert_stored_form_error(status)
      Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
        page.evaluate_script("Number(sessionStorage.getItem('notesFormStatus'))") == status
      end
      orbite_settle
    end

    def hold_notes_get(*paths, answers: [ false ])
      find("lexxy-editor[connected]")
      page.execute_script(<<~JS, paths, answers)
        const [paths, answers] = arguments
        const destinations = new Map(paths.map(path => [new URL(path, location.origin).href, path]))
        window.ordinaryFetch = window.fetch
        window.visitWarnings = 0
        window.abortedNotesGets = []
        window.confirm = () => answers[window.visitWarnings++] ?? false
        window.fetch = (url, options) => {
          if (options?.method === "PATCH") return Promise.reject(new TypeError("Hold the autosave"))
          if (options?.method === "GET" && destinations.has(url) && !(new Headers(options.headers)).has("X-Sec-Purpose")) {
            const path = destinations.get(url)
            return new Promise((resolve, reject) => {
              window.heldNotesGet = path
              window.releaseNotesGet = ({ fail = false } = {}) => {
                if (fail) reject(new TypeError("Simulated navigation network failure"))
                else resolve(window.ordinaryFetch(url, { ...options, cache: "no-store" }))
              }
              options.signal.addEventListener("abort", () => {
                window.abortedNotesGets.push(path)
                reject(new DOMException("Aborted", "AbortError"))
              }, { once: true })
            })
          }
          return window.ordinaryFetch(url, options)
        }
        document.addEventListener("turbo:before-fetch-response", event => {
          if (event.target === document.documentElement) {
            const response = event.detail.fetchResponse
            window.departureStatus = response.statusCode
            window.departureRecovery = response.header("X-Notes-Draft-Recovery")
          }
        })
      JS
    end

    def wait_for_held_notes_get(path = nil)
      Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
        page.evaluate_script("typeof window.releaseNotesGet === 'function' && (!arguments[0] || window.heldNotesGet === arguments[0])", path)
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

    def hold_index_retry(note)
      page.execute_script(<<~JS, account_note_index_retry_path(@account, note))
        const retryUrl = new URL(arguments[0], location.origin).href
        const ordinaryFetch = window.fetch
        window.heldIndexRetries = {}
        window.fetch = async (url, options) => {
          const response = await ordinaryFetch(url, options)
          if (new URL(url, location.origin).href !== retryUrl || options?.method?.toUpperCase() !== "POST") return response

          // Capture the real response before disconnect can abort its body.
          const body = await response.text()
          return new Promise(resolve => {
            const generation = options.body.get("expected_generation")
            window.heldIndexRetries[generation] = window.heldIndexRetry = { status: response.status, signal: options.signal, release: () => {
              resolve(new Response(body, { status: response.status, headers: response.headers }))
            } }
          })
        }
      JS
    end

    def retrieve_held_retry_status(generation = nil)
      Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
        page.evaluate_script("(arguments[0] ? window.heldIndexRetries[arguments[0]] : window.heldIndexRetry)?.status", generation)
      end
    end

    def release_index_retry(generation = nil)
      page.execute_script("(arguments[0] ? window.heldIndexRetries[arguments[0]] : window.heldIndexRetry).release()", generation)
      orbite_settle
    end

    def assert_poll_count_stays(count)
      # Observe a full polling interval; no condition can prove a request did not start.
      sleep 5.5
      assert_equal count, page.evaluate_script("window.indexPolls")
    end
end
