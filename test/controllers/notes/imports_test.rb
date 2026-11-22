require "test_helper"
require "stringio"

class NotesImportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :account_users

  PATH = "Nested/private-title.md"
  MARKDOWN = "# private content\n"
  ROOT = "<private-vault>"
  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @account = accounts(:picker_first)
    @initiator = users(:picker_owner)
    sign_in @initiator
  end

  test "start, stage, and seal a private receipt with one enqueue but no publication" do
    assert_enqueued_jobs 1 do
      assert_no_difference [ "Note.count", "NoteFolder.count" ] do
        receipt = start_receipt
        assert_equal "uploading", receipt.fetch("status")
        assert_equal "#{imports_path}/#{@account.note_imports.sole.id}", receipt.fetch("status_url")
        assert_equal "#{receipt.fetch('status_url')}/batches", receipt.fetch("batch_url")
        assert_equal "#{receipt.fetch('status_url')}/seal", receipt.fetch("seal_url")

        post_batch receipt.fetch("batch_url")
        assert_response :ok
        assert_equal({ "status" => "uploading", "accepted_count" => 1, "uploaded_count" => 1, "total" => 1 }, private_json)
        assert_equal MARKDOWN, @account.note_imports.sole.staged_files.sole.payload

        post_json receipt.fetch("seal_url"), {}
        assert_response :accepted
        assert_equal({ "status" => "queued", "uploaded_count" => 1, "total" => 1 }, private_json)
        assert_predicate @account.note_imports.sole, :queued?
        assert_not_nil @account.note_imports.sole.sealed_at

        get receipt.fetch("status_url"), headers: JSON_HEADERS
        assert_response :ok
        assert_equal({ "status" => "queued", "uploaded_count" => 1, "total" => 1, "message" => "Waiting to import" }, private_json)
      end
    end
  end

  test "confirmation retries reuse the receipt and changed metadata conflicts" do
    manifest = manifest_params
    original = start_receipt(manifest)

    assert_no_difference "NoteImport.count" do
      post_json imports_path, manifest
      assert_response :ok
      assert_equal original, private_json

      post_json imports_path, manifest.merge(root_name: "Changed")
      assert_error 409, "confirmation_conflict"

      post_json imports_path, manifest.merge(confirmation_key: SecureRandom.uuid)
      assert_error 409, "import_in_progress"
    end
  end

  test "batch retries do not add rows and changed bytes conflict" do
    receipt = start_receipt
    post_batch receipt.fetch("batch_url")
    assert_response :ok

    assert_no_difference "NoteImport::StagedFile.count" do
      post_batch receipt.fetch("batch_url")
      assert_response :ok
      assert_equal 1, private_json.fetch("uploaded_count")

      post_batch receipt.fetch("batch_url"), [ upload(bytes: "x" * MARKDOWN.bytesize) ]
      assert_error 409, "content_conflict"
    end
  end

  test "seal rejects incomplete uploads and retries leave the seal timestamp unchanged" do
    receipt = start_receipt
    record = @account.note_imports.sole
    post_json receipt.fetch("seal_url"), {}
    assert_error 422, "incomplete_upload"
    assert_predicate record.reload, :uploading?

    post_batch receipt.fetch("batch_url")
    assert_response :ok
    post_json receipt.fetch("seal_url"), {}
    assert_response :accepted
    sealed_at = record.reload.sealed_at
    travel 1.minute do
      assert_no_enqueued_jobs { post_json receipt.fetch("seal_url"), {} }
      assert_response :accepted
      assert_equal sealed_at, record.reload.sealed_at
    end

    post_batch receipt.fetch("batch_url")
    assert_error 409, "not_uploading"
  end

  test "progress remains complete after sealed staging is purged but not for an expired upload" do
    record = seed_import
    record.stage!([ { path: PATH, bytes: MARKDOWN } ])
    record.seal!
    record.update!(status: :succeeded)
    record.purge_staging!
    get "#{imports_path}/#{record.id}", headers: JSON_HEADERS
    assert_response :ok
    assert_equal({ "status" => "succeeded", "uploaded_count" => 1, "total" => 1, "message" => "Notes imported" }, private_json)

    expired = seed_import
    expired.update!(status: :expired)
    expired.purge_staging!
    get "#{imports_path}/#{expired.id}", headers: JSON_HEADERS
    assert_response :ok
    assert_equal({ "status" => "expired", "uploaded_count" => 0, "total" => 1,
      "message" => "This upload expired. Select the folder again to start a new import." }, private_json)
  end

  test "sealing a terminal receipt returns its status without changing it" do
    record = seed_import

    NoteImport::TERMINAL_STATUSES.each do |status|
      record.update!(status:)
      assert_no_changes -> { record.reload.attributes } do
        post_json "#{imports_path}/#{record.id}/seal", {}
        assert_response :ok
        assert_equal status, private_json.fetch("status")
      end
    end
  end

  test "a different member cannot query or mutate an initiator receipt" do
    record = seed_import
    member = users(:picker_outsider)
    @account.account_users.grant_to(member)
    sign_in member

    assert_private_not_found "#{imports_path}/#{record.id}"
  end

  test "an initiator cannot look up their import through a different account" do
    record = seed_import
    [ accounts(:picker_second), accounts(:picker_foreign) ].each do |account|
      assert_private_not_found "/accounts/#{account.id}/note-imports/#{record.id}"
    end
  end

  test "revoked membership blocks reading, starting, staging and sealing" do
    record = seed_import
    account_users(:picker_first_membership).destroy!

    assert_private_not_found "#{imports_path}/#{record.id}"
    assert_no_difference "NoteImport.count" do
      post_json imports_path, manifest_params
      assert_error 404, "not_found"
    end
  end

  test "only the path supplies account and import ids, and only the body supplies the manifest" do
    manifest = manifest_params
    post_json "#{imports_path}?confirmation_key=#{manifest.fetch(:confirmation_key)}", manifest.except(:confirmation_key)
    assert_error 422, "invalid_confirmation_key"

    other_account = accounts(:picker_second)
    post_json "#{imports_path}?account_id=#{other_account.id}", manifest.merge(initiator_id: users(:picker_outsider).id)
    assert_response :created
    receipt = private_json
    record = @account.note_imports.sole
    assert_equal @initiator.id, record.initiator_id
    assert_empty other_account.note_imports

    post_batch "#{receipt.fetch('batch_url')}?note_import_id=0&account_id=#{other_account.id}"
    assert_response :ok
    assert_equal 1, record.staged_files.count
    post_batch "#{imports_path}/0/batches?note_import_id=#{record.id}"
    assert_error 404, "not_found"
  end

  test "rejects oversized, malformed, or non-file batches without partially staging them" do
    batch_path = "#{imports_path}/#{seed_import.id}/batches"
    assert_no_difference "NoteImport::StagedFile.count" do
      post_batch batch_path, Array.new(17) { upload }
      assert_error 422, "invalid_batch"

      post batch_path, params: { entries: [ upload ], extra: Array.new(16) { upload.fetch(:file) } }, headers: JSON_HEADERS
      assert_error 422, "invalid_batch"

      post_batch batch_path, [ upload, { path: "other.md", file: "not an uploaded file" } ]
      assert_error 422, "invalid_batch"

      post_batch batch_path, [ upload(bytes: "different length") ]
      assert_error 422, "size_mismatch"

      post_batch batch_path, [ upload(path: "invalid-name.md") ]
      assert_error 422, "unexpected_path"

      post_json batch_path, { entries: [] }
      assert_error 415, "unsupported_media_type"
    end
  end

  test "manifest validates integer sizes and exact ignored counts" do
    assert_no_difference "NoteImport.count" do
      post_json imports_path, manifest_params.merge(files: [ { path: PATH, bytes: MARKDOWN.bytesize } ])
      assert_error 422, "invalid_file_size"

      post_json imports_path, manifest_params.merge(ignored_counts: { obsidian: 0, other: 0, extra: 1 })
      assert_error 422, "invalid_ignored_counts"
    end
  end

  test "launch caps reject over-limit manifests before opening a receipt" do
    {
      "invalid_file_count" => Array.new(101) { |i| { path: "#{i}.md", size: 0 } },
      "folder_limit_exceeded" => Array.new(60) { |i| { path: "#{i}/Plan.md", size: 0 } },
      "total_size_exceeded" => [ 2.megabytes, 2.megabytes, 1 ].map.with_index { |size, i| { path: "#{i}.md", size: } }
    }.each do |code, files|
      assert_no_difference "NoteImport.count" do
        post_json imports_path, manifest_params.merge(files:)
        assert_error 422, code
      end
    end
  end

  test "oversized raw bodies are rejected for Rails path aliases before either body parser" do
    record = seed_import
    encoded_account = @account.id.to_s.bytes.map { |byte| "%%%02x" % byte }.join

    {
      "#{imports_path}.json/" => [ 1.megabyte, "application/json" ],
      "/accounts//#{encoded_account}//note-imports///#{record.id}/batches.json/" =>
        [ 4.megabytes, "multipart/form-data; boundary=Boundary" ],
      "#{imports_path}/#{record.id}/seal.xml//" => [ 16.kilobytes, "application/json" ]
    }.each do |path, (limit, media_type)|
      post path, params: "not a parsable body", headers: JSON_HEADERS.merge(
        "CONTENT_TYPE" => media_type, "CONTENT_LENGTH" => (limit + 1).to_s
      )
      assert_error 413, "payload_too_large"
    end
  end

  test "new and status pages are translated and cannot be cached or display private input" do
    record = seed_import
    record.stage!([ { path: PATH, bytes: MARKDOWN } ])
    { "#{imports_path}/new" => "Importer un dossier Markdown",
      "#{imports_path}/#{record.id}" => "État de l’importation" }.each do |path, title|
      get path, headers: { "Accept-Language" => "fr" }
      assert_response :ok
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select "meta[name='turbo-cache-control'][content='no-cache']"
      assert_select "h1", text: title
      assert_select "input[type='file'][webkitdirectory][multiple][disabled]", count: path.end_with?("/new") ? 1 : 0
      refute_match(/translation missing/i, response.body)
      [ ROOT, CGI.escapeHTML(ROOT), PATH, MARKDOWN, record.confirmation_key ].each { |value| refute_includes response.body, value }
    end
    assert_select "[role='status']", text: /Fichiers envoyés : 1 sur 1/
  end

  test "the picker advertises a configured lower proxy budget with multipart headroom" do
    previous = ENV["NOTES_IMPORT_BATCH_WIRE_BYTES"]
    ENV["NOTES_IMPORT_BATCH_WIRE_BYTES"] = 1.megabyte.to_s
    get new_account_note_import_path(@account)

    assert_response :ok
    assert_select "[data-note-import-limits-value]" do |elements|
      limits = JSON.parse(elements.sole["data-note-import-limits-value"])
      assert_equal 1.megabyte - 64.kilobytes, limits["batchBytes"]
      assert_equal 2.megabytes, limits["fileBytes"]
    end
  ensure
    ENV["NOTES_IMPORT_BATCH_WIRE_BYTES"] = previous
  end

  test "the successful receipt and matching root show an escaped private bounded report without caching" do
    record, root = published_receipt
    result_path = account_notes_workspace_path(@account, folder_id: root.id, import_id: record.id)
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)

    [ "#{imports_path}/#{record.id}", result_path ].each do |path|
      get path, headers: { "Accept-Language" => "fr" }
      assert_response :ok
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select "meta[name='turbo-cache-control'][content='no-cache']"
      assert_select "[data-note-import-report] h2", text: "Rapport d’importation : #{ROOT}"
      assert_select "[data-note-import-report] li", count: 100
      assert_select "[data-note-import-report] li", text: /<source-note\.md>.*<unresolved-target>/
      assert_select "[data-note-import-report] li", text: "Excerpt.md → #{"é" * 255}x", count: 1
      refute_includes response.body, "should-not-appear"
      assert_select "[data-note-import-report] li a, source-note, unresolved-target", count: 0
      assert_select "[data-note-import-report]", text: /101 liens non résolus/
      refute_includes response.body, MARKDOWN
      refute_includes response.body, "beyond-report-limit"
    end
    assert_select "a[href*='import_id=']", count: 0 # Never carry the receipt into normal Notes links.
    assert_select "[data-note-import-report] a[href='#{account_note_import_path(@account, record)}']"
    get "#{imports_path}/#{record.id}", headers: JSON_HEADERS
    assert_equal({ "status" => "succeeded", "uploaded_count" => 1, "total" => 1,
      "message" => "Notes imported", "result_url" => result_path }, private_json)
    [ ROOT, MARKDOWN, "<source-note.md>", "<unresolved-target>" ].each { |text| refute_includes log.string, text }
  ensure
    Rails.logger.stop_broadcasting_to(logger) if logger
  end

  test "the report does not follow a receipt id to other folders or account members" do
    record, root = published_receipt
    other = @account.note_folders.create!(name: "Other folder")
    get account_notes_workspace_path(@account, folder_id: other.id, import_id: record.id)
    assert_response :ok
    assert_select "[data-note-import-report]", count: 0
    get account_notes_workspace_path(@account, folder_id: root.id, import_id: { id: record.id })
    assert_response :ok
    assert_select "[data-note-import-report]", count: 0

    foreign = accounts(:picker_second)
    foreign_folder = foreign.note_folders.create!(name: "Other account folder")
    get account_notes_workspace_path(foreign, folder_id: foreign_folder.id, import_id: record.id)
    assert_response :ok
    assert_select "[data-note-import-report]", count: 0

    member = users(:picker_outsider)
    @account.account_users.grant_to(member)
    sign_in member
    get account_notes_workspace_path(@account, folder_id: root.id, import_id: record.id)
    assert_response :ok
    assert_select "[data-note-import-report]", count: 0
    refute_includes response.body, "unresolved-target"

    sign_in @initiator
    account_users(:picker_first_membership).destroy!
    get account_notes_workspace_path(@account, folder_id: root.id, import_id: record.id)
    assert_response :not_found
    assert_select "[data-note-import-report]", count: 0
  end

  test "a trashed root keeps its historical report but no active result link" do
    record, root = published_receipt
    root.trash
    get "#{imports_path}/#{record.id}", headers: JSON_HEADERS
    assert_equal "succeeded", private_json.fetch("status")
    refute private_json.key?("result_url")

    get "#{imports_path}/#{record.id}"
    assert_response :ok
    assert_select "[data-note-import-report] h2", text: "Import report: #{ROOT}"
    assert_select "a", text: "Open imported folder", count: 0
    assert_select "p", text: "The imported folder is no longer active in Notes."
  end

  test "only a marked HTML continuation redirects to an active successful result" do
    record, root = published_receipt
    path = "#{imports_path}/#{record.id}"
    target = account_notes_workspace_path(@account, folder_id: root.id, import_id: record.id)

    get "#{path}?continue=1"
    assert_response :see_other
    assert_redirected_to target
    assert_equal "no-store", response.headers["Cache-Control"]

    get "#{path}?continue=1", headers: JSON_HEADERS
    assert_equal target, private_json.fetch("result_url")

    get "#{path}?continue=1&extra=unused-receipt-parameter"
    assert_response :ok
    refute_includes request.filtered_path, "unused-receipt-parameter"

    get path
    assert_response :ok
    assert_select "a[href='#{target}']", text: "Open imported folder"
    root.trash
    get "#{path}?continue=1"
    assert_redirected_to path
    follow_redirect!
    assert_response :ok
    assert_select "a", text: "Open imported folder", count: 0
  end

  test "refresh keeps the continuation only on marked live receipt links" do
    receipt = seed_import
    path = account_note_import_path(@account, receipt)
    marked_path = account_note_import_path(@account, receipt, continue: 1)
    get path
    assert_response :ok
    assert_select "a[href='#{path}']", text: "Refresh status"
    get marked_path
    assert_response :ok
    assert_select "a[href='#{marked_path}']", text: "Refresh status"
    assert_select "[data-note-import-status-url-value='#{path}']"
  end

  test "discard terminalizes only the unsealed upload and retries never resurrect its key" do
    manifest = manifest_params
    receipt = start_receipt(manifest)
    path = receipt.fetch("status_url")
    record = @account.note_imports.sole
    post_batch receipt.fetch("batch_url")
    assert_response :ok
    assert_no_difference [ "Note.count", "NoteFolder.count", "NoteImport.count" ] do
      post_json "#{path}/cancellation", {}
      assert_response :ok
      assert_equal "failed", private_json.fetch("status")
      assert_equal({ "error" => "upload_discarded" }, record.reload.report)
      assert_empty record.staged_files
      assert_no_changes -> { record.reload.attributes } do
        post_json "#{path}/cancellation", {}
        assert_response :ok
        post_json imports_path, manifest
        assert_response :ok
        assert_equal "failed", private_json.fetch("status")
        post_batch receipt.fetch("batch_url")
        assert_error 409, "not_uploading"
        post_json receipt.fetch("seal_url"), {}
        assert_response :ok
        assert_equal "failed", private_json.fetch("status")
      end
    end
    assert_equal "uploading", start_receipt(manifest.merge(confirmation_key: SecureRandom.uuid)).fetch("status")
  end

  test "discard keeps a sealed upload and its files untouched" do
    record = seed_import
    record.stage!([ { path: PATH, bytes: MARKDOWN } ])
    record.seal!
    %w[sealed queued running succeeded].each do |state|
      record.update!(status: state)
      assert_no_changes -> { record.reload.attributes } do
        post_json "#{imports_path}/#{record.id}/cancellation", {}
        assert_error 409, "not_uploading"
        assert_equal MARKDOWN, record.staged_files.sole.payload
      end
    end
  end

  test "discard cannot cross a membership or initiator boundary" do
    record = seed_import
    member = users(:picker_outsider)
    @account.account_users.grant_to(member)
    assert_no_changes -> { record.reload.attributes } do
      sign_in member
      post_json "#{imports_path}/#{record.id}/cancellation", {}
      assert_error 404, "not_found"
      get "#{imports_path}/#{record.id}?continue=1"
      assert_response :not_found
      assert_nil response.headers["Location"]

      sign_in @initiator
      post_json "/accounts/#{accounts(:picker_second).id}/note-imports/#{record.id}/cancellation", {}
      assert_error 404, "not_found"

      account_users(:picker_first_membership).destroy!
      post_json "#{imports_path}/#{record.id}/cancellation", {}
      assert_error 404, "not_found"
    end
  end

  test "discard requires CSRF and rejects oversized writes with no-store" do
    record = seed_import
    path = "#{imports_path}/#{record.id}/cancellation.json/"
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_changes -> { record.reload.attributes } do
      post_json path, {}
      assert_response 422
      assert_equal "no-store", response.headers.fetch("Cache-Control")
      post path, params: "not parsed", headers: JSON_HEADERS.merge("CONTENT_LENGTH" => (16.kilobytes + 1).to_s,
        "CONTENT_TYPE" => "application/json")
      assert_error 413, "payload_too_large"
    end
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "terminal messages are localized and never expose unknown stored errors" do
    record = seed_import
    (NoteImport::Publication::FAILURE_CODES + %i[processing_timeout worker_claim_expired upload_discarded]).each do |code|
      record.update!(status: :failed, report: { error: code })
      %i[en fr].each do |locale|
        get "#{imports_path}/#{record.id}", headers: JSON_HEADERS.merge("Accept-Language" => locale.to_s)
        assert_kind_of String, private_json["message"]
        assert_equal I18n.t!("nosia.notes.imports.failures.#{code}", locale:), private_json.fetch("message")
      end
    end
    record.update!(report: { error: "private exception" })
    get "#{imports_path}/#{record.id}", headers: JSON_HEADERS
    assert_equal "failed", private_json.fetch("status")
    refute_includes response.body, "private exception"
  end

  test "no import endpoint is available outside the account Notes scope" do
    get "/note-imports/new"
    assert_response :not_found
    post_json "/note-imports", manifest_params
    assert_response :not_found
    post_json "/accounts/#{@account.id}/notes/note-imports", manifest_params
    assert_response :not_found
  end

  test "Rails guards import methods before Rack method override and the request logger" do
    stack = Rails.application.middleware.map(&:klass)
    guard = stack.index(NotesImportRequestLimit)
    assert_operator guard, :<, stack.index(Rack::MethodOverride)
    assert_operator guard, :<, stack.index(Rails::Rack::Logger)

    record = seed_import
    [ "#{imports_path}/new.json/", "#{imports_path}/#{record.id}.json/" ].each do |path|
      assert_post_rejected_without_reading(path)
    end
  end

  test "an import start cannot be rerouted using the method override header" do
    post imports_path, params: manifest_params, as: :json, headers: JSON_HEADERS.merge("X-HTTP-Method-Override" => "GET")

    assert_response :created
    assert_equal "POST", request.request_method
    assert_equal "uploading", private_json.fetch("status")
  end

  test "a batch cannot be rerouted using its multipart method field and private fields stay out of instrumentation" do
    receipt = start_receipt
    events = []
    subscriber = ->(event) { events << event.payload if event.payload.fetch(:controller) == "Notes::Imports::BatchesController" }

    ActiveSupport::Notifications.subscribed(subscriber, "start_processing.action_controller") do
      post receipt.fetch("batch_url"), params: { entries: [ upload ], _method: "delete", "unexpected private field" => "private value" },
        headers: JSON_HEADERS
    end

    assert_response :ok
    assert_equal 1, private_json.fetch("accepted_count")
    assert_equal "POST", events.sole.fetch(:method)
    refute_includes events.sole.fetch(:params).keys, "_method"
    refute_includes events.sole.fetch(:params).inspect, "unexpected private field"
    refute_includes events.sole.fetch(:params).inspect, "private value"
  end

  test "parameter logs omit private and unexpected import input while leaving unrelated parameters alone" do
    events = []
    subscriber = ->(event) { events << event.payload.fetch(:params) if event.payload.fetch(:controller).start_with?("Notes::Import") }
    ActiveSupport::Notifications.subscribed(subscriber, "start_processing.action_controller") do
      receipt = start_receipt(manifest_params.merge("unexpected private key" => "unexpected manifest secret"))
      post_batch receipt.fetch("batch_url"), [ upload ], query: "?error_input=unexpected-query-secret"
      assert_response :ok
    end

    assert_equal 2, events.size
    [ ROOT, PATH, MARKDOWN, "untrusted-original-name.md", "unexpected private key", "unexpected manifest secret", "unexpected-query-secret" ].each do |secret|
      refute_includes events.inspect, secret
    end
    refute_includes request.filtered_path, "unexpected-query-secret"

    unrelated = ActionDispatch::Request.new("action_dispatch.parameter_filter" => Rails.application.config.filter_parameters)
    assert_equal({ "entries" => "ordinary", "files" => "elsewhere" },
      unrelated.parameter_filter.filter("entries" => "ordinary", "files" => "elsewhere"))
  end

  test "malformed JSON does not echo or log its raw contents" do
    secret = "sensitive malformed manifest"
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)

    post imports_path, params: "{\"files\":#{secret}}", headers: JSON_HEADERS.merge("CONTENT_TYPE" => "application/json"),
      env: { "action_dispatch.logger" => logger }

    assert_error 400, "invalid_request"
    refute_includes log.string, secret
  end

  test "malformed multipart fields do not echo or log parser details" do
    secret = "private_multipart_field_name"
    body = <<~BODY.gsub("\n", "\r\n")
      --Boundary
      Content-Disposition: form-data; name="#{secret}"

      one
      --Boundary
      Content-Disposition: form-data; name="#{secret}[]"

      two
      --Boundary--
    BODY
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    post "#{imports_path}/#{seed_import.id}/batches", params: body,
      headers: JSON_HEADERS.merge("CONTENT_TYPE" => "multipart/form-data; boundary=Boundary"),
      env: { "action_dispatch.logger" => logger }

    assert_error 400, "invalid_request"
    refute_includes response.body, secret
    refute_includes log.string, secret
  end

  test "SQL debug logs do not include import paths or root names" do
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)

    receipt = start_receipt
    post_batch receipt.fetch("batch_url")
    assert_response :ok

    [ ROOT, PATH, MARKDOWN ].each { |secret| refute_includes log.string, secret }
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  test "import writes still require the authenticated session and CSRF token" do
    record = seed_import
    anonymous = open_session
    anonymous.post imports_path, params: manifest_params, as: :json, headers: JSON_HEADERS
    assert_equal 404, anonymous.response.status
    anonymous.get "#{imports_path}/#{record.id}.json"
    assert_equal 404, anonymous.response.status
    assert_equal "no-store", anonymous.response.headers["Cache-Control"]

    original = Notes::Imports::BatchesController.allow_forgery_protection
    Notes::Imports::BatchesController.allow_forgery_protection = true
    assert_no_difference "NoteImport::StagedFile.count" do
      post_batch "#{imports_path}/#{record.id}/batches"
      assert_response 422
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  ensure
    Notes::Imports::BatchesController.allow_forgery_protection = original if defined?(original)
  end

  private
    def published_receipt
      record = seed_import
      record.stage!([ { path: PATH, bytes: MARKDOWN } ])
      record.seal!
      root = @account.note_folders.create!(name: ROOT)
      examples = Array.new(99) { { path: "<source-note.md>", target: "<unresolved-target>" } }
      examples << { path: "Excerpt.md", target: "#{"é" * 255}xéshould-not-appear" }
      examples << { path: "beyond-report-limit.md", target: "beyond-report-limit" }
      record.update!(status: :succeeded, root_note_folder_id: root.id, report: {
        root_name: ROOT, note_count: 1, folder_count: 2, ignored_counts: { obsidian: 1, other: 2 },
        unresolved_count: 101, unresolved_examples: examples
      })
      [ record, root ]
    end

    def assert_post_rejected_without_reading(path)
      env = Rack::MockRequest.env_for(path, method: "POST", "CONTENT_TYPE" => "multipart/form-data; boundary=Example",
        "CONTENT_LENGTH" => "2", "HTTP_ACCEPT_LANGUAGE" => "fr")
      input = StringIO.new
      input.define_singleton_method(:read) { |*| raise "unsupported request read its body" }
      env[Rack::RACK_INPUT] = input

      status, headers, body = Rails.application.call(env)
      assert_equal 405, status
      assert_equal "GET, HEAD", headers.fetch("allow")
      assert_equal "no-store", headers.fetch("cache-control")
      assert_equal "fr", headers.fetch("content-language")
      assert_equal "method_not_allowed", JSON.parse(body.join).fetch("error")
    ensure
      body.close if body.respond_to?(:close)
    end

    def sign_in(user)
      post login_path, params: { email: user.email, password: "picker-password-123" }
      assert_response :redirect
    end

    def imports_path
      "/accounts/#{@account.id}/note-imports"
    end

    def manifest_params
      { root_name: ROOT, confirmation_key: SecureRandom.uuid, files: [ { path: PATH, size: MARKDOWN.bytesize } ],
        ignored_counts: { obsidian: 1, other: 2 } }
    end

    def seed_import
      NoteImport.start!(account: @account, initiator: @initiator, **manifest_params)
    end

    def start_receipt(manifest = manifest_params)
      post_json imports_path, manifest
      assert_response :created
      private_json
    end

    def post_json(path, params)
      post path, params:, as: :json, headers: JSON_HEADERS
    end

    def post_batch(path, entries = [ upload ], query: "")
      post "#{path}#{query}", params: { entries: }, headers: JSON_HEADERS
    end

    def upload(path: PATH, bytes: MARKDOWN)
      { path:, file: Rack::Test::UploadedFile.new(StringIO.new(bytes), "text/markdown", original_filename: "untrusted-original-name.md") }
    end

    def private_json
      assert_equal "no-store", response.headers.fetch("Cache-Control")
      assert_equal "application/json", response.media_type
      response.parsed_body
    end

    def assert_error(status, code)
      assert_response status
      body = private_json
      assert_equal code, body.fetch("error")
      assert_equal %w[error message], body.keys.sort
      assert_not_empty body.fetch("message")
      [ ROOT, PATH, MARKDOWN, "invalid-name.md" ].each { |value| refute_includes response.body, value }
    end

    def assert_private_not_found(status_path)
      staging_queries = []
      subscriber = ->(event) do
        staging_queries << event.payload[:sql] if event.payload[:sql].include?("note_import_staged_files")
      end
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get status_path, headers: JSON_HEADERS
        assert_error 404, "not_found"
        get status_path
        assert_response :not_found
        assert_equal "no-store", response.headers.fetch("Cache-Control")
        assert_empty response.body
        post_batch "#{status_path}/batches"
        assert_error 404, "not_found"
        post_json "#{status_path}/seal", {}
        assert_error 404, "not_found"
      end
      assert_empty staging_queries
    end
end
