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

  test "start, stage, and seal a private receipt without publishing or enqueueing" do
    assert_no_enqueued_jobs do
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
        assert_equal({ "status" => "sealed", "uploaded_count" => 1, "total" => 1 }, private_json)
        assert_predicate @account.note_imports.sole, :sealed?
        assert_not_nil @account.note_imports.sole.sealed_at

        get receipt.fetch("status_url"), headers: JSON_HEADERS
        assert_response :ok
        assert_equal({ "status" => "sealed", "uploaded_count" => 1, "total" => 1 }, private_json)
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
      post_json receipt.fetch("seal_url"), {}
      assert_response :accepted
      assert_equal sealed_at, record.reload.sealed_at
    end

    post_batch receipt.fetch("batch_url")
    assert_error 409, "not_uploading"
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
      assert_select "input[type='file']", count: 0
      [ ROOT, CGI.escapeHTML(ROOT), PATH, MARKDOWN, record.confirmation_key ].each { |value| refute_includes response.body, value }
    end
    assert_select "[role='status']", text: /Fichiers envoyés : 1 sur 1/
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
