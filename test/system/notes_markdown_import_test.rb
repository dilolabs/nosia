require "application_system_test_case"
require_relative "../support/orbite_browser_checks"

class NotesMarkdownImportTest < ApplicationSystemTestCase
  include OrbiteBrowserChecks
  include ActiveJob::TestHelper

  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users

  PICKER = "input[type=file][webkitdirectory]"
  VAULT = Rails.root.join("test/fixtures/files/notes_markdown_import/Coffre")

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @account = accounts(:picker_first)
    visit root_path
    fill_in "email", with: users(:picker_owner).email
    fill_in "password", with: "picker-password-123"
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    if @script
      page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @script)
    end
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1400)
  end

  test "a native folder preview discloses sharing and indexing without sending and can be canceled" do
    visit account_notes_workspace_path(@account, view: "trash")
    assert_no_link "Import a Markdown folder"
    visit account_notes_workspace_path(@account)
    click_link "Import a Markdown folder"
    observe_import_posts
    assert_text "Account: #{@account.name}"
    assert_text "separate folder"
    assert_text "shared with members"
    assert_text "configured indexing provider, which may be remote"
    assert_button "Upload and import", disabled: true

    select_folder
    assert_selector "[role=status]", text: /Coffre.*Notes: 2.*Folders \(including root\): 2.*Obsidian files ignored: 1.*Other files ignored: 1/m
    assert_button "Upload and import", disabled: false
    assert_empty page.evaluate_script("window.importPosts")
    assert_empty @account.note_imports
    click_link "Cancel"
    assert_current_path account_notes_workspace_path(@account)
    page.go_back
    assert_current_path new_account_note_import_path(@account)
    assert_selector "[role=status]", text: /Nothing is sent until you confirm/
    assert_button "Upload and import", disabled: true
    assert_empty @account.note_imports
  end

  test "going Back during confirmation does not let a late receipt start uploading" do
    workspace = account_notes_workspace_path(@account)
    visit workspace
    click_link "Import a Markdown folder"
    select_folder
    hold_import_response(account_note_imports_path(@account))
    click_button "Upload and import"
    wait_for_browser_gate "releaseImportResponse"
    receipt = @account.note_imports.sole

    back_before_rendering "#notes-header-actions"
    assert_selector "[data-controller='note-import']"
    release_import_response
    assert_equal [ account_note_imports_path(@account) ], page.evaluate_script("window.importPosts")

    page.execute_script("window.releaseBackDestination()")
    assert_current_path workspace
    assert_selector "#notes-header-actions"
    assert_predicate receipt.reload, :uploading?
    assert_empty receipt.staged_files
    assert_no_enqueued_jobs only: NoteImport::PublishJob

    page.go_forward
    assert_current_path new_account_note_import_path(@account)
    assert_button "Upload and import", disabled: true
    assert_equal [ account_note_imports_path(@account) ], page.evaluate_script("window.importPosts")
  end

  test "going Back from a status page wins over a late successful poll" do
    importer = new_account_note_import_path(@account)
    visit importer
    select_folder
    click_button "Upload and import"
    assert_selector "[role=status]", text: /Waiting to import/
    receipt = @account.note_imports.find_by!(status: :queued)
    hold_import_response(account_note_import_path(@account, receipt), "GET")
    perform_enqueued_jobs(only: NoteImport::PublishJob)
    assert_predicate receipt.reload, :succeeded?
    wait_for_browser_gate "releaseImportResponse"

    back_before_rendering "[data-controller='note-import']"
    release_import_response
    assert_equal [ importer ], page.evaluate_script("window.importVisits")
    page.execute_script("window.releaseBackDestination()")
    assert_current_path importer
    assert_button "Upload and import", disabled: true
  end

  test "going Back during discard keeps the committed result but does not reopen its receipt" do
    importer = new_account_note_import_path(@account)
    initiator = users(:picker_owner)
    receipt = NoteImport.start!(account: @account, initiator:, root_name: "Original", confirmation_key: SecureRandom.uuid,
      files: [ { path: "Original.md", size: 0 } ], ignored_counts: { obsidian: 0, other: 0 })
    visit importer
    click_link "Review unfinished upload"
    assert_current_path account_note_import_path(@account, receipt)
    hold_import_response(account_note_import_cancellation_path(@account, receipt))
    accept_confirm(/discard/i) { click_button "Discard upload" }
    wait_for_browser_gate "releaseImportResponse"
    assert_predicate receipt.reload, :failed?

    back_before_rendering "[data-controller='note-import']"
    release_import_response
    assert_equal [ importer ], page.evaluate_script("window.importVisits")
    page.execute_script("window.releaseBackDestination()")
    assert_current_path importer
    assert_button "Upload and import", disabled: true
  end

  test "a canceled Turbo visit does not clear a selected folder" do
    visit new_account_note_import_path(@account)
    select_folder
    assert_button "Upload and import", disabled: false
    page.execute_script('document.addEventListener("turbo:before-visit", event => event.preventDefault(), { once: true })')
    click_link "Cancel"
    orbite_settle

    assert_current_path new_account_note_import_path(@account)
    assert_selector "[role=status]", text: /Selected folder: Coffre/
    assert_button "Upload and import", disabled: false
    assert_empty @account.note_imports
  end

  test "an unsupported browser has no fallback file path" do
    @script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument",
      source: "delete HTMLInputElement.prototype.webkitdirectory").fetch("identifier")
    visit new_account_note_import_path(@account)
    assert_selector "[role=status]", text: /browser does not support choosing folders/
    assert_selector "#{PICKER}:disabled"
    assert_button "Upload and import", disabled: true
    assert_empty @account.note_imports
  end

  test "folder import works without the secure-context randomUUID API" do
    @script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument",
      source: "delete Crypto.prototype.randomUUID").fetch("identifier")
    visit new_account_note_import_path(@account)
    refute page.evaluate_script('typeof crypto.randomUUID === "function"')
    assert_selector "#{PICKER}:enabled"

    select_folder
    assert_selector "[role=status]", text: /Selected folder: Coffre/
    assert_empty @account.note_imports
    click_button "Upload and import"
    assert_selector "[role=status]", text: /Waiting to import/

    receipt = @account.note_imports.sole
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, receipt.confirmation_key)
    perform_enqueued_jobs(only: NoteImport::PublishJob)
    assert_selector "[data-note-import-report]", text: "Import report: Coffre"
  end

  test "mobile keyboard focus and over-limit preview block requests" do
    orbite_viewport(375, 800)
    visit new_account_note_import_path(@account)
    observe_import_posts
    [ false, true ].each do |dark|
      orbite_theme(dark)
      target = orbite_tab_to(PICKER)
      assert_operator target.fetch("outlineWidth"), :>=, 2
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
    end

    Dir.mktmpdir("notes-import-", "/tmp/opencode") do |directory|
      101.times { |index| File.write(File.join(directory, "#{index}.md"), "") }
      select_folder(directory)
      assert_selector "[role=alert]:focus", text: /between 1 and 100 Markdown files/
      assert_button "Upload and import", disabled: true
    end
    assert_empty page.evaluate_script("window.importPosts")
    assert_empty @account.note_imports
  end

  test "a queued import opens its private report and keeps editable same-copy links across repeat imports" do
    first = import_vault
    assert_text "Import report: Coffre"
    assert_text "Indexing may still be pending"
    assert_text "1 unresolved link"
    page.go_back
    assert_current_path new_account_note_import_path(@account)
    page.go_forward
    assert_selector "[data-note-import-report]", text: "Import report: Coffre"
    click_link "Accueil"
    assert_selector "lexxy-editor[connected]"
    link = find(".lexxy-editor__content a", text: "la réunion")
    first_destination = link[:href]
    find(".lexxy-editor__content").send_keys(:end, " revised")
    assert_selector ".n-notes-save-row [role=status]", text: /Saved/
    visit account_note_path(@account, @account.notes.find_by!(title: "Accueil"))
    assert_selector ".lexxy-editor__content", text: "revised"
    assert_imported_link_opens first_destination

    second = import_vault
    assert_text "Import report: Coffre (2)"
    refute_equal first.root_note_folder_id, second.root_note_folder_id
    click_link "Accueil"
    assert_selector "lexxy-editor[connected]"
    second_destination = find(".lexxy-editor__content a", text: "la réunion")[:href]
    refute_equal first_destination, second_destination
    assert_imported_link_opens second_destination
    visit account_note_import_path(@account, second)
    assert_link "Open imported folder"
    assert_current_path account_note_import_path(@account, second)
  end

  test "lost batch and seal responses retry the same confirmation without duplicate staging or sealing" do
    visit new_account_note_import_path(@account)
    select_folder
    assert_button "Upload and import", disabled: false
    observe_import_posts(lose: %w[ /batches /seal ])
    click_button "Upload and import"
    assert_selector "[role=alert]:focus", text: /Retry upload/
    receipt = @account.note_imports.sole
    assert_equal 2, receipt.staged_files.count
    assert_nil receipt.sealed_at

    click_button "Retry upload"
    assert_selector "[role=alert]:focus", text: /Retry upload/
    sealed_at = receipt.reload.sealed_at
    assert_not_nil sealed_at
    click_button "Retry upload"
    assert_current_path account_note_import_path(@account, receipt, continue: 1)
    assert_selector "[role=status]", text: /Waiting to import/
    assert_equal 1, @account.note_imports.count
    assert_equal 2, receipt.staged_files.count
    assert_equal sealed_at, receipt.reload.sealed_at
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == NoteImport::PublishJob }
  end

  test "a rejected upload can be discarded and the corrected folder imported with a new key" do
    visit new_account_note_import_path(@account)
    Dir.mktmpdir("notes-import-", "/tmp/opencode") do |directory|
      File.write(File.join(directory, "Okay.md"), "Readable")
      File.binwrite(File.join(directory, "Invalid.md"), "\xFF")
      select_folder(directory)
      assert_button "Upload and import", disabled: false
      assert_no_difference [ "Note.count", "NoteFolder.count" ] do
        click_button "Upload and import"
        assert_selector "[role=alert]:focus", text: /not valid UTF-8/
        assert_button "Upload and import", disabled: true

        receipt = @account.note_imports.sole
        assert_nil receipt.sealed_at
        assert_empty receipt.staged_files
        assert_no_enqueued_jobs only: NoteImport::PublishJob
        click_link "Review unfinished upload"
        assert_current_path account_note_import_path(@account, receipt)
        dismiss_confirm(/discard/i) { click_button "Discard upload" }
        assert_predicate receipt.reload, :uploading?
        accept_confirm(/discard/i) { click_button "Discard upload" }
        assert_selector "[role=status]", text: /Upload discarded/
      end

      discarded = @account.note_imports.sole
      File.write(File.join(directory, "Invalid.md"), "Now valid.")
      click_link "Import a Markdown folder"
      select_folder(directory)
      click_button "Upload and import"
      assert_selector "[role=status]", text: /Waiting to import/
      corrected = @account.note_imports.find_by!(status: :queued)
      refute_equal discarded.confirmation_key, corrected.confirmation_key
      perform_enqueued_jobs(only: NoteImport::PublishJob)
      assert_predicate corrected.reload, :succeeded?
      assert_equal 1, @account.note_folders.where(id: corrected.root_note_folder_id).count
    end
  end

  test "a separate new confirmation blocked by a live upload offers review, not a retry" do
    visit new_account_note_import_path(@account)
    select_folder
    initiator = users(:picker_owner)
    receipt = NoteImport.start!(account: @account, initiator:, root_name: "Original", confirmation_key: SecureRandom.uuid,
      files: [ { path: "Original.md", size: 0 } ], ignored_counts: { obsidian: 0, other: 0 })

    click_button "Upload and import"
    assert_selector "[role=alert]:focus", text: /already have an import in progress/
    assert_no_button "Retry upload"
    click_link "Find your current import"
    assert_link "Review unfinished upload", href: account_note_import_path(@account, receipt)
    assert_predicate receipt.reload, :uploading?
  end

  test "a job finished before the first receipt GET still opens the report once" do
    visit new_account_note_import_path(@account)
    select_folder
    # Hold the real seal reply before the client can make the first receipt visit.
    page.execute_script(<<~JS)
      const fetch = window.fetch
      window.fetch = async (url, options) => {
        const reply = await fetch(url, options)
        if (options?.method === "POST" && url.endsWith("/seal")) {
          await new Promise(resolve => { window.releaseSeal = resolve })
        }
        return reply
      }
    JS
    click_button "Upload and import"
    assert_equal true, page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      function waitForSeal() {
        if (window.releaseSeal) done(true)
        else requestAnimationFrame(waitForSeal)
      }
      waitForSeal()
    JS
    assert_current_path new_account_note_import_path(@account)
    receipt = @account.note_imports.find_by!(status: :queued)
    perform_enqueued_jobs(only: NoteImport::PublishJob)
    assert_predicate receipt.reload, :succeeded?
    page.execute_script("window.releaseSeal()")

    result = account_notes_workspace_path(@account, folder_id: receipt.root_note_folder_id, import_id: receipt.id)
    assert_current_path result, wait: 10
    assert_selector "[data-note-import-report]", text: "Import report: Coffre"
    page.go_back
    assert_current_path new_account_note_import_path(@account)
    visit result
    click_link "View import status"
    assert_current_path account_note_import_path(@account, receipt)
    assert_link "Open imported folder", href: result
  end

  test "retrying after a lost seal response opens the already saved report" do
    visit new_account_note_import_path(@account)
    select_folder
    assert_button "Upload and import", disabled: false
    observe_import_posts(lose: [ "/seal" ])
    click_button "Upload and import"
    assert_selector "[role=alert]:focus", text: /Retry upload/
    receipt = @account.note_imports.find_by!(status: :queued)
    sealed_at = receipt.sealed_at
    perform_enqueued_jobs(only: NoteImport::PublishJob)
    assert_predicate receipt.reload, :succeeded?

    click_button "Retry upload"
    assert_current_path account_notes_workspace_path(@account, folder_id: receipt.root_note_folder_id, import_id: receipt.id), wait: 10
    assert_selector "[data-note-import-report]", text: "Import report: Coffre"
    assert_equal [ "/note-imports", "/batches", "/seal", "/note-imports" ],
      page.evaluate_script("window.importPosts").map { |path| "/#{path.split('/').last}" }
    assert_equal sealed_at, receipt.reload.sealed_at
    assert_equal 1, @account.note_imports.count
  end

  test "refresh after a failed poll still opens the imported folder" do
    visit new_account_note_import_path(@account)
    select_folder
    page.execute_script(<<~JS)
      const fetch = window.fetch
      let failNextPoll = true
      window.fetch = (url, options) => {
        const path = new URL(url, location.href).pathname
        const accepts = new Headers(options?.headers).get("Accept")
        if (failNextPoll && !options?.method && accepts === "application/json" && path.includes("/note-imports/")) {
          failNextPoll = false
          return Promise.reject(new TypeError("Test: status poll lost"))
        }
        return fetch(url, options)
      }
    JS
    click_button "Upload and import"
    assert_selector "[role=status]", text: /Could not check the import/, wait: 10
    receipt = @account.note_imports.find_by!(status: :queued)
    assert_current_path account_note_import_path(@account, receipt, continue: 1)

    click_link "Refresh status"
    assert_selector "[role=status]", text: /Waiting to import/
    perform_enqueued_jobs(only: NoteImport::PublishJob)
    assert_predicate receipt.reload, :succeeded?
    result = account_notes_workspace_path(@account, folder_id: receipt.root_note_folder_id, import_id: receipt.id)
    assert_current_path result, wait: 10
    assert_selector "[data-note-import-report]", text: "Import report: Coffre"

    page.go_back
    assert_current_path new_account_note_import_path(@account)
    visit result
    click_link "View import status"
    assert_current_path account_note_import_path(@account, receipt)
    assert_link "Open imported folder", href: result
  end

  test "polling stops at a failed receipt and offers a fresh selection" do
    visit new_account_note_import_path(@account)
    select_folder
    click_button "Upload and import"
    assert_selector "[role=status]", text: /Waiting to import/
    receipt = @account.note_imports.sole
    assert_no_difference [ "Note.count", "NoteFolder.count" ] do
      receipt.update!(sealed_at: 25.hours.ago)
      receipt.fail_expired
      assert_predicate receipt.reload, :failed?
      assert_link "Import a Markdown folder", href: new_account_note_import_path(@account), wait: 10
    end
    assert_current_path account_note_import_path(@account, receipt)
    assert_selector "[role=status]", text: /The import did not start in time/
    assert_no_link "Open imported folder"
    assert_no_selector "[data-controller='note-import-status']"
  end

  test "the browser batches at most sixteen files and three MiB of Markdown per request" do
    visit new_account_note_import_path(@account)
    observe_import_posts
    Dir.mktmpdir("notes-import-", "/tmp/opencode") do |directory|
      33.times { |index| File.write(File.join(directory, "Small#{index}.md"), "") }
      2.times { |index| File.write(File.join(directory, "Large#{index}.md"), "a" * 2.megabytes) }
      select_folder(directory)
      click_button "Upload and import"
      assert_selector "[role=status]", text: /Files uploaded: 35 of 35/
    end
    batches = page.evaluate_script("window.importBatches")
    assert_operator batches.length, :>=, 3
    assert_equal 35, batches.sum { |batch| batch.fetch("files") }
    assert_equal 4.megabytes, batches.sum { |batch| batch.fetch("bytes") }
    batches.each do |batch|
      assert_operator batch.fetch("files"), :<=, 16
      assert_operator batch.fetch("bytes"), :<=, 3.megabytes
    end
  end

  test "a note that cannot fit the advertised proxy budget is rejected before upload" do
    previous = ENV["NOTES_IMPORT_BATCH_WIRE_BYTES"]
    ENV["NOTES_IMPORT_BATCH_WIRE_BYTES"] = 1.megabyte.to_s
    visit new_account_note_import_path(@account)
    observe_import_posts
    Dir.mktmpdir("notes-import-", "/tmp/opencode") do |directory|
      File.write(File.join(directory, "Large.md"), "a" * 1.megabyte)
      select_folder(directory)
      assert_selector "[role=alert]:focus", text: /too large for this server’s upload limit/
      assert_button "Upload and import", disabled: true
    end
    assert_empty page.evaluate_script("window.importPosts")
    assert_empty @account.note_imports
  ensure
    ENV["NOTES_IMPORT_BATCH_WIRE_BYTES"] = previous
  end

  private
    def hold_import_response(match_path, match_method = "POST")
      page.execute_script(<<~JS, match_path, match_method)
        const [matchPath, matchMethod] = arguments
        const fetch = window.fetch
        window.importPosts = []
        window.fetch = async (resource, options) => {
          const path = new URL(resource instanceof Request ? resource.url : resource, location.href).pathname
          const method = options?.method || "GET"
          if (method === "POST" && path.includes("/note-imports")) window.importPosts.push(path)
          const reply = await fetch(resource, options)
          if (path === matchPath && method === matchMethod && new Headers(options?.headers).get("Accept") === "application/json") {
            // The server already replied; deliver its real JSON late, independent of abort timing.
            const body = await reply.json()
            await new Promise(resolve => { window.releaseImportResponse = resolve })
            reply.json = () => Promise.resolve(body)
          }
          return reply
        }
      JS
    end

    def back_before_rendering(selector)
      page.execute_script(<<~JS, selector)
        const selector = arguments[0]
        window.importVisits = []
        document.addEventListener("turbo:visit", ({ detail }) => window.importVisits.push(new URL(detail.url).pathname))
        document.addEventListener("turbo:before-render", event => {
          if (!event.detail.newBody.querySelector(selector)) return
          event.preventDefault()
          window.releaseBackDestination = event.detail.resume
        }, { once: true })
        history.back()
      JS
      wait_for_browser_gate "releaseBackDestination"
    end

    def release_import_response
      page.execute_script("window.releaseImportResponse()")
      orbite_settle
    end

    def wait_for_browser_gate(name)
      assert_equal true, page.evaluate_async_script(<<~JS, name)
        const [gate, done] = arguments
        function waitForGate() {
          if (window[gate]) done(true)
          else requestAnimationFrame(waitForGate)
        }
        waitForGate()
      JS
    end

    def select_folder(path = VAULT)
      assert_selector "#{PICKER}:enabled"
      browser = page.driver.browser
      document = browser.execute_cdp("DOM.getDocument").fetch("root").fetch("nodeId")
      node = browser.execute_cdp("DOM.querySelector", nodeId: document, selector: PICKER).fetch("nodeId")
      browser.execute_cdp("DOM.setFileInputFiles", nodeId: node, files: [ path.to_s ])
    end

    def import_vault
      visit new_account_note_import_path(@account)
      select_folder
      click_button "Upload and import"
      assert_selector "[role=status]", text: /Waiting to import/
      receipt = @account.note_imports.find_by!(status: :queued)
      perform_enqueued_jobs(only: NoteImport::PublishJob)
      receipt.reload
    assert_predicate receipt, :succeeded?
      assert_current_path account_notes_workspace_path(@account, folder_id: receipt.root_note_folder_id, import_id: receipt.id), wait: 10
      receipt
    end

    def assert_imported_link_opens(destination)
      # Lexxy opens an editable link in a separate tab with the platform modifier.
      link = find(".lexxy-editor__content a", text: "la réunion")
      modifier = page.evaluate_script("/Mac/.test(navigator.platform)") ? :command : :control
      opened = window_opened_by { link.click(modifier) }
      within_window(opened) do
        assert_current_path destination, url: true
        assert_selector "lexxy-editor[connected]"
        assert_selector "#note_title[value='Réunion']"
      end
    ensure
      opened&.close
    end

    def observe_import_posts(lose: [])
      page.execute_script(<<~JS, lose)
        const fetch = window.fetch, lose = arguments[0];
        window.importPosts = [];
        window.importBatches = [];
        window.fetch = async (url, options) => {
          const path = new URL(url instanceof Request ? url.url : url, location.href).pathname;
          const importing = options?.method === "POST" && path.includes("/note-imports");
          if (importing) window.importPosts.push(path);
          if (importing && path.endsWith("/batches")) {
            const files = options.body.getAll("entries[][file]");
            window.importBatches.push({ files: files.length, bytes: files.reduce((total, file) => total + file.size, 0) });
          }
          const response = await fetch(url, options);
          if (importing && lose[0] && path.endsWith(lose[0])) {
            lose.shift();
            throw new TypeError("Test: lost upload response");
          }
          return response;
        };
      JS
    end
end
