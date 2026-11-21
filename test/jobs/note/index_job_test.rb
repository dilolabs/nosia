require "test_helper"
require "timeout"

class NoteIndexJobTest < ActiveJob::TestCase
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts, :note_folders, :notes

  setup do
    @account = accounts(:picker_first)
    @folder = note_folders(:sessions)
    @owner = users(:picker_owner)
    @vector = [ 1.0 ] + Array.new(Chunk.columns_hash.fetch("embedding").limit - 1, 0.0)
    @original_embed = RubyLLM.method(:embed)
    fake_provider { flunk "unexpected embedding request" }
  end

  teardown do
    RubyLLM.define_singleton_method(:embed, @original_embed) if @original_embed
    Account.where(id: accounts.map(&:id)).destroy_all
    User.where(id: users.map(&:id)).destroy_all
  end

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "a title-only draft indexes after the debounce without contacting the provider at save time" do
    freeze_time do
      note = draft("  Title only  ")

      assert_respond_to note, :embedding_generation
      assert_enqueued_with job: Note::IndexJob, args: [ note.id, 1 ], at: 30.seconds.from_now
      assert_equal "pending", note.embedding_status
      assert_nil note.indexed_generation
      assert_empty note.chunks

      fake_provider do |text|
        assert_equal "Title only", text
        embedding_result
      end
      perform_enqueued_jobs only: Note::IndexJob

      assert_equal "ready", note.reload.embedding_status
      assert_equal 1, note.indexed_generation
      assert_equal [ "Title only" ], note.chunks.pluck(:content)
    end
  end

  test "a formatting-only edit, pin and move leave the canonical generation alone" do
    note = draft("  Field notes  ", body_html: "<p>First</p><p>Second<script>invisible</script></p>")
    fake_provider do |text|
      assert_equal "Field notes\n\nFirst\nSecond", text
      embedding_result
    end
    perform_enqueued_jobs only: Note::IndexJob
    original = note.reload.chunk_ids
    fake_provider { flunk "unexpected embedding request" }

    assert_no_enqueued_jobs only: Note::IndexJob do
      edit(note, "Field notes", body_html: "<h2><em>First</em></h2><p><strong>Second</strong></p>")
      note.pin_in_folder
      note.move_to(note_folders(:reading))
    end

    assert_equal 2, note.reload.content_revision
    assert_equal 1, note.embedding_generation
    assert_equal "ready", note.embedding_status
    assert_equal original, note.chunk_ids
  end

  test "long preformatted notes skip NBSP and control-only parts without changing code" do
    padding = "\u00A0\u200B" * ENV.fetch("CHUNK_SIZE", "512").to_i
    code = "def sample\n  :indented\nend"
    note = draft("Code", body_html: "<pre>#{padding}\n\n#{code}</pre>")
    inputs = []
    fake_provider do |text|
      inputs << text
      embedding_result
    end

    Note::IndexJob.perform_now(note.id, note.embedding_generation)

    assert_equal 2, inputs.size
    assert_equal [ "Code", code ], inputs
    assert_equal "ready", note.reload.embedding_status
    chunks = note.chunks.sort_by { |chunk| chunk.metadata.fetch("position") }
    assert_equal inputs, chunks.map(&:content)
    assert_equal [ @vector, @vector ], chunks.map(&:embedding)
  end

  test "emptying an indexed note clears its live marker and destroys its chunks" do
    note = draft("Temporary content")
    index(note)

    assert_no_enqueued_jobs only: Note::IndexJob do
      edit(note, "\u200B ", body_html: "<p><br></p><script>removed</script>")
    end

    assert_equal 2, note.reload.embedding_generation
    assert_equal "empty", note.embedding_status
    assert_nil note.indexed_generation
    assert_empty note.chunks
  end

  test "enqueues wait for the outer commit and disappear on rollback" do
    assert_no_enqueued_jobs do
      Note.transaction do
        draft("Rolled back")
        raise ActiveRecord::Rollback
      end
    end
    refute @account.notes.exists?(title: "Rolled back")

    note = nil
    assert_enqueued_jobs 1, only: Note::IndexJob do
      Note.transaction do
        note = draft("Saved")
        assert_no_enqueued_jobs only: Note::IndexJob
      end
    end
    assert_enqueued_with job: Note::IndexJob, args: [ note.id, 1 ]

    assert_no_enqueued_jobs do
      Note.transaction do
        edit(note, "Rolled-back edit")
        raise ActiveRecord::Rollback
      end
    end
    assert_equal [ "Saved", 1 ], [ note.reload.title, note.embedding_generation ]
  end

  %w[ActiveJob::EnqueueError SolidQueue::Job::EnqueueError].each do |error_name|
    test "#{error_name} at enqueue leaves a committed draft recoverable by retry" do
      draft_key = SecureRandom.uuid
      params = { account: @account, folder: @folder, draft_key:, title: "Saved anyway", body_html: "" }
      attempts = 0
      note = nil
      private_detail = "queue detail #{SecureRandom.hex}"
      log = Rails.root.join("log/test.log")
      offset = log.size

      failure = ->(*) do
        attempts += 1
        raise error_name.constantize, private_detail
      end
      with_queue_outage(failure) do
        assert_difference -> { @account.notes.count } do
          note = Note.save_draft!(**params)
          assert_equal "failed", note.reload.embedding_status
          assert_equal note.id, Note.save_draft!(**params).id
        end
      end
      assert_equal 1, attempts
      assert_not File.read(log, nil, offset).include?(private_detail), "queue diagnostics must not include raw errors"

      assert_enqueued_jobs 1, only: Note::IndexJob do
        note.retry_index
        note.retry_index
      end
      fake_provider { embedding_result }
      perform_enqueued_jobs only: Note::IndexJob
      assert_equal [ "ready", 1, 1 ], note.reload.values_at(:embedding_status, :embedding_generation, :indexed_generation)
    end
  end

  test "failed enqueue for an older generation does not fail a concurrent revision" do
    attempts = 0
    adapter = queue_adapter
    with_queue_outage(->(job, timestamp) {
      attempts += 1
      if attempts == 1
        edit(Note.find(job.arguments.first), "Newer revision")
        raise SolidQueue::Job::EnqueueError, "first enqueue failed"
      end
      ActiveJob::QueueAdapters::TestAdapter.instance_method(:enqueue_at).bind_call(adapter, job, timestamp)
    }) do
      note = draft("Original revision")
      assert_equal [ "Newer revision", "pending", 2 ], note.reload.values_at(:title, :embedding_status, :embedding_generation)
      assert_enqueued_with job: Note::IndexJob, args: [ note.id, 2 ]
    end
    assert_equal 2, attempts
  end

  test "an aborted enqueue leaves an edited generation failed but does not roll back the edit" do
    note = draft("First revision")
    abort_enqueue = -> { throw :abort }
    Note::IndexJob.set_callback(:enqueue, :before, abort_enqueue)

    assert_no_enqueued_jobs only: Note::IndexJob do
      edit(note, "Accepted revision")
    end
    assert_equal [ "Accepted revision", "failed", 2 ], note.reload.values_at(:title, :embedding_status, :embedding_generation)
  ensure
    Note::IndexJob.skip_callback(:enqueue, :before, abort_enqueue) if abort_enqueue
  end

  test "stale, missing and already-indexed jobs do not contact the provider" do
    note = draft("Original")
    generation = note.embedding_generation
    edit(note, "Current")

    assert_no_enqueued_jobs do
      Note::IndexJob.perform_now(note.id, generation)
      Note::IndexJob.perform_now(0, generation)
    end
    assert_equal "pending", note.reload.embedding_status
    assert_empty note.chunks

    index(note)
    assert_no_changes -> { note.reload.chunk_ids } do
      Note::IndexJob.perform_now(note.id, note.embedding_generation)
    end
  end

  test "an edit on another connection during embedding prevents stale publication" do
    note = draft("Original")
    index(note)
    original = note.reload.chunk_ids
    edit(note, "Older edit")
    generation = note.embedding_generation

    while_computing(note, generation) do
      edit(Note.find(note.id), "Newer edit")
      assert_equal original, note.chunks.ids
    end

    assert_equal [ "pending", generation + 1, 1 ], note.reload.values_at(:embedding_status, :embedding_generation, :indexed_generation)
    assert_equal original, note.chunk_ids
    index(note)
    assert_equal [ "Newer edit" ], note.chunks.pluck(:content)
    assert_equal generation + 1, note.reload.indexed_generation
  end

  test "trashing a branch during embedding blocks publication and its pending note resumes on restore" do
    note = draft("Branch content")

    while_computing(note, note.embedding_generation) { @folder.trash }

    assert_empty note.chunks
    assert_equal "pending", note.reload.embedding_status
    assert_no_enqueued_jobs { Note::IndexJob.perform_now(note.id, note.embedding_generation) }

    assert_enqueued_with job: NoteFolder::ResumeIndexingJob, args: [ @folder.id ] do
      @folder.restore
    end
    perform_enqueued_jobs only: NoteFolder::ResumeIndexingJob
    assert_enqueued_with job: Note::IndexJob, args: [ note.id, note.embedding_generation ]
    index(note)
    assert_equal "ready", note.reload.embedding_status
  end

  test "purging during embedding discards the publication without retry" do
    note = draft("About to disappear")
    assert_no_enqueued_jobs do
      while_computing(note, note.embedding_generation) { Note.find(note.id).trash.purge(by: @owner) }
    end
    refute Note.exists?(note.id)
    assert_empty Chunk.where(chunkable: note)
  end

  test "the final generation check locks the note row against a native reset" do
    note = draft("Active generation")
    fake_provider { embedding_result }
    main_thread = Thread.current
    checked_generation = Queue.new
    allow_publish = Queue.new
    pause_after_check = ->(_name, _started, _finished, _id, payload) do
      if Thread.current != main_thread && payload[:name] == "Note Exists?"
        checked_generation << true
        allow_publish.pop
      end
    end

    worker = nil
    ActiveSupport::Notifications.subscribed(pause_after_check, "sql.active_record") do
      worker = Thread.new { Note::IndexJob.perform_now(note.id, note.embedding_generation) }
      Timeout.timeout(5) { checked_generation.pop }
      assert_raises(ActiveRecord::LockWaitTimeout) { Note.lock("FOR UPDATE NOWAIT").find(note.id) }
      allow_publish << true
      assert worker.join(5), "indexing did not finish after the generation check"
      worker.value
    end
    assert_equal "ready", note.reload.embedding_status
  ensure
    allow_publish&.push(true)
    if worker&.alive?
      worker.kill unless worker.join(5)
    end
  end

  test "a later provider failure leaves old chunks and usage intact through bounded retries" do
    note = draft("Original")
    index(note)
    original = note.reload.chunk_ids
    edit(note, multi_chunk_text)
    calls = 0
    private_body = "synthetic provider body #{SecureRandom.hex}"
    log = Rails.root.join("log/test.log")
    log_offset = log.size
    fake_provider do |_text|
      calls += 1
      raise RubyLLM::Error, private_body if calls.even?
      embedding_result
    end

    assert_no_difference -> { @account.token_usages.count } do
      perform_enqueued_jobs only: Note::IndexJob do
        Note::IndexJob.perform_later(note.id, note.embedding_generation)
      end
    end

    assert_equal 6, calls
    assert_equal [ "failed", 1 ], note.reload.values_at(:embedding_status, :indexed_generation)
    assert_equal original, note.chunk_ids
    refute_includes File.read(log, nil, log_offset), private_body
  end

  test "a later chunk insert failure rolls back replacement and usage" do
    note = draft("Original")
    index(note)
    original = note.reload.chunk_ids
    edit(note, multi_chunk_text)
    stored_before_failure = []
    fail_second_insert = ->(chunk) do
      if chunk.metadata["position"] == 2
        stored_before_failure.concat(note.chunks.ids)
        throw :abort
      end
    end
    Chunk.set_callback(:create, :before, fail_second_insert)
    fake_provider { embedding_result }

    assert_no_difference -> { @account.token_usages.count } do
      assert_raises ActiveRecord::RecordNotSaved do
        Note::IndexJob.perform_now(note.id, note.embedding_generation)
      end
    end
    assert_equal 1, stored_before_failure.size
    assert_equal [ "pending", 1 ], note.reload.values_at(:embedding_status, :indexed_generation)
    assert_equal original, note.chunk_ids
  ensure
    Chunk.skip_callback(:create, :before, fail_second_insert) if fail_second_insert
  end

  test "success replaces all rows and accounts for each chunk of the published generation" do
    note = draft("Original")
    index(note)
    original = note.reload.chunk_ids
    private_text = "synthetic note #{SecureRandom.hex}"
    edit(note, "#{private_text} #{multi_chunk_text}")
    parts = []
    fake_provider do |text|
      parts << text
      embedding_result
    end

    log = Rails.root.join("log/test.log")
    log_offset = log.size
    Note::IndexJob.perform_now(note.id, note.embedding_generation)
    refute_includes File.read(log, nil, log_offset), private_text

    chunks = note.chunks.sort_by { |chunk| chunk.metadata.fetch("position") }
    assert_operator chunks.size, :>, 1
    assert_empty Chunk.where(id: original)
    assert_equal parts, chunks.map(&:content)
    assert_equal (1..chunks.size).to_a, chunks.map { |c| c.metadata["position"] }
    assert_equal [ note.embedding_generation ], chunks.map { |c| c.metadata["note_generation"] }.uniq
    assert_equal [ @account.id ], chunks.map(&:account_id).uniq
    assert_equal [ @vector ], chunks.map(&:embedding).uniq
    usages = @account.token_usages.where(source_type: "Chunk", source_id: chunks.map(&:id))
    assert_equal [ [ "embedding", nil, 8, 0 ] ] * chunks.size, usages.pluck(:kind, :chat_id, :input_tokens, :output_tokens)
    assert_equal [ "ready", note.embedding_generation ], note.reload.values_at(:embedding_status, :indexed_generation)
  end

  test "rolling back publication also rolls back the ready marker and token counters" do
    note = draft("Rollback target")
    fake_provider { embedding_result }

    assert_no_changes -> { @account.reload.input_tokens_count } do
      assert_no_difference -> { @account.token_usages.count } do
        Note.transaction do
          Note::IndexJob.perform_now(note.id, note.embedding_generation)
          assert_equal "ready", note.reload.embedding_status
          assert_not_empty note.chunks
          raise ActiveRecord::Rollback
        end
      end
    end

    assert_equal "pending", note.reload.embedding_status
    assert_nil note.indexed_generation
    assert_empty note.chunks
  end

  test "unusable provider results retry and never publish" do
    malformed = [ nil, [], [ @vector ], [ 1.0 ], @vector.map(&:to_s),
      @vector.dup.fill(0.0), @vector.dup.fill(Float::NAN), @vector.dup.fill(1e100) ]

    malformed.each do |vector|
      note = draft("Invalid vector")
      calls = 0
      fake_provider do
        calls += 1
        embedding_result(vector)
      end

      assert_no_difference -> { @account.token_usages.count } do
        perform_enqueued_jobs only: Note::IndexJob do
          Note::IndexJob.perform_later(note.id, note.embedding_generation)
        end
      end

      assert_equal 3, calls
      assert_equal "failed", note.reload.embedding_status
      assert_nil note.indexed_generation
      assert_empty note.chunks
    end
  end

  test "a result without an embedding vector API is a retryable failure" do
    note = draft("Missing result shape")
    fake_provider { Object.new }

    perform_enqueued_jobs only: Note::IndexJob do
      Note::IndexJob.perform_later(note.id, note.embedding_generation)
    end

    assert_equal "failed", note.reload.embedding_status
    assert_empty note.chunks
  end

  test "malformed OpenAI-compatible responses retry without logging HTTP bodies" do
    private_body = "synthetic reply #{SecureRandom.hex}"
    note = draft("Malformed response")
    assert_respond_to note, :embedding_generation
    RubyLLM.define_singleton_method(:embed, @original_embed)
    logger_output = StringIO.new
    provider_logger = Logger.new(logger_output, level: :debug)
    calls = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/embeddings") do
        calls += 1
        [ 200, { "Content-Type" => "application/json" },
          { data: [ { embedding: nil } ], detail: private_body }.to_json ]
      end
    end
    adapter = Class.new(Faraday::Adapter::Test) do
      define_method(:initialize) { |app, **| super(app, stubs, &nil) }
    end
    original_config = RubyLLM.config.dup
    RubyLLM.configure do |config|
      config.faraday_adapter = adapter
      config.logger = provider_logger
      config.log_bodies = true
    end

    perform_enqueued_jobs only: Note::IndexJob do
      Note::IndexJob.perform_later(note.id, note.embedding_generation)
    end

    assert_equal 3, calls
    assert_equal "failed", note.reload.embedding_status
    assert_empty note.chunks
    refute_includes logger_output.string, private_body
    refute_includes logger_output.string, note.title
  ensure
    RubyLLM.configure do |config|
      config.faraday_adapter = original_config.faraday_adapter
      config.logger = original_config.logger
      config.log_bodies = original_config.log_bodies
    end if original_config
  end

  test "HTTP error diagnostics never log note text or provider echoes across retries" do
    note = draft("Synthetic note #{SecureRandom.hex}")
    provider_only_text = "echo marker #{SecureRandom.hex}"
    ordinary_source = "ordinary source #{SecureRandom.hex}"
    log = Rails.root.join("log/test.log")
    log_offset = log.size
    RubyLLM.define_singleton_method(:embed, @original_embed)
    output = StringIO.new
    provider_logger = Logger.new(output, level: :debug)
    calls = 0
    ordinary_error = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/embeddings") do |request|
        text = JSON.parse(request.body).fetch("input")
        if text == note.title
          calls += 1
          if calls == 1
            ordinary_error = Thread.new do
              Chunk.embed_text(ordinary_source)
            rescue RubyLLM::BadRequestError => error
              error
            end.value
          end
        else
          assert_equal ordinary_source, text
        end
        message = text == note.title ? "#{provider_only_text}: #{text}" : text
        [ 400, { "Content-Type" => "application/json" }, { error: { message: } }.to_json ]
      end
    end
    adapter = Class.new(Faraday::Adapter::Test) do
      define_method(:initialize) { |app, **| super(app, stubs, &nil) }
    end
    original_config = RubyLLM.config.dup
    RubyLLM.configure do |config|
      config.faraday_adapter = adapter
      config.logger = provider_logger
      config.log_bodies = true
      config.redact_error_messages = false
    end

    # An installation may route RubyLLM events into its diagnostic log.
    log_event = ->(_name, _started, _finished, _id, payload) do
      provider_logger.info("Embedding event: #{payload.slice(:input, :exception).inspect}")
    end
    ActiveSupport::Notifications.subscribed(log_event, "embedding.ruby_llm") do
      perform_enqueued_jobs only: Note::IndexJob do
        Note::IndexJob.perform_later(note.id, note.embedding_generation)
      end
    end

    assert_equal 3, calls
    assert_equal "failed", note.reload.embedding_status
    assert_empty note.chunks
    assert_instance_of RubyLLM::BadRequestError, ordinary_error
    assert_includes output.string, ordinary_source
    assert_includes output.string, "error:", "ordinary HTTP diagnostics should still be logged"
    assert_includes output.string, "Embedding event:", "ordinary instrumentation should still reach subscribers"
    assert_same provider_logger, RubyLLM.logger
    logs = output.string + File.read(log, nil, log_offset)
    assert_not logs.include?(note.title), "the note text was recorded in a log"
    assert_not logs.include?(provider_only_text), "the provider error payload was recorded in a log"
  ensure
    RubyLLM.configure do |config|
      config.faraday_adapter = original_config.faraday_adapter
      config.logger = original_config.logger
      config.log_bodies = original_config.log_bodies
      config.redact_error_messages = original_config.redact_error_messages
    end if original_config
  end

  test "oversized usage from a real HTTP response is quarantined without logging or blocking publication" do
    note = draft("Private usage #{SecureRandom.hex}")
    oversized_input = (2**31) + 123457
    output = StringIO.new
    original_config = RubyLLM.config.dup
    RubyLLM.define_singleton_method(:embed, @original_embed)
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/embeddings") do |request|
        assert_equal note.title, JSON.parse(request.body).fetch("input")
        body = { data: [ { embedding: @vector } ], usage: { prompt_tokens: oversized_input } }
        [ 200, { "Content-Type" => "application/json" }, body.to_json ]
      end
    end
    adapter = Class.new(Faraday::Adapter::Test) do
      define_method(:initialize) { |app, **| super(app, stubs, &nil) }
    end
    RubyLLM.configure do |config|
      config.faraday_adapter = adapter
      config.logger = Logger.new(output, level: :debug)
      config.log_bodies = true
    end
    log = Rails.root.join("log/test.log")
    offset = log.size

    assert_no_difference [ -> { @account.token_usages.count }, -> { RubyLLM::ActiveRecord::Usage.count } ] do
      assert_no_changes -> { @account.reload.input_tokens_count } do
        perform_enqueued_jobs only: Note::IndexJob
      end
    end

    assert_equal "ready", note.reload.embedding_status
    assert_equal [ @vector ], note.chunks.reload.map(&:embedding)
    logs = output.string + File.read(log, nil, offset)
    assert_not logs.include?(oversized_input.to_s), "provider usage leaked in diagnostic logs"
    assert_not logs.include?(note.title), "note contents leaked in diagnostic logs"
  ensure
    if original_config
      RubyLLM.configure do |config|
        config.faraday_adapter = original_config.faraday_adapter
        config.logger = original_config.logger
        config.log_bodies = original_config.log_bodies
      end
    end
  end

  test "note usage cannot overflow the account counter" do
    note = draft("Counter at capacity")
    @account.update!(input_tokens_count: (2**31) - 2)
    fake_provider { embedding_result }

    assert_no_changes -> { @account.reload.input_tokens_count } do
      assert_no_difference -> { @account.token_usages.count } do
        Note::IndexJob.perform_now(note.id, note.embedding_generation)
      end
    end
    assert_equal "ready", note.reload.embedding_status
    assert_equal [ @vector ], note.chunks.reload.map(&:embedding)
  end

  test "an exhausted old provider attempt cannot fail a newer generation" do
    note = draft("Old version")
    generation = note.embedding_generation
    attempts = 0
    fake_provider do |_text|
      attempts += 1
      if attempts == 3
        edit(Note.find(note.id), "New version")
      end
      raise RubyLLM::Error, "provider failed"
    end

    perform_enqueued_jobs(only: Note::IndexJob, at: 10.seconds.from_now) do
      Note::IndexJob.perform_later(note.id, generation)
    end

    assert_equal 3, attempts
    assert_equal [ "pending", generation + 1 ], note.reload.values_at(:embedding_status, :embedding_generation)
    assert_empty note.chunks
  end

  test "retry only changes a failed active note and enqueues the same generation after commit" do
    note = draft("Retry me")
    clear_enqueued_jobs
    assert_no_enqueued_jobs { note.retry_index }
    note.update!(embedding_status: "failed")
    generation = note.embedding_generation

    assert_no_enqueued_jobs do
      Note.transaction do
        note.retry_index
        assert_equal "pending", note.reload.embedding_status
        assert_no_enqueued_jobs
        raise ActiveRecord::Rollback
      end
    end
    assert_equal "failed", note.reload.embedding_status

    note.trash
    assert_no_enqueued_jobs { note.retry_index }
    assert_equal "failed", note.reload.embedding_status

    assert_enqueued_with job: Note::IndexJob, args: [ note.id, generation ] do
      note.restore
    end
    assert_equal "pending", note.reload.embedding_status
    note.update!(embedding_status: "failed")

    assert_enqueued_with job: Note::IndexJob, args: [ note.id, generation ] do
      note.retry_index
    end
    assert_equal [ "pending", generation ], note.reload.values_at(:embedding_status, :embedding_generation)
  end

  test "restoring a note with a still-current ready generation reuses its vectors" do
    note = draft("Keep vectors")
    index(note)
    original = note.reload.chunk_ids
    note.trash

    assert_no_enqueued_jobs only: Note::IndexJob do
      note.restore
    end

    assert_equal "ready", note.reload.embedding_status
    assert_equal original, note.chunk_ids
  end

  test "branch resumption queues only pending or failed active notes in that branch" do
    ready = draft("Ready")
    index(ready)
    original = ready.reload.chunk_ids
    pending = draft("Pending")
    failed = draft("Failed", folder: note_folders(:interviews))
    failed.update!(embedding_status: "failed")
    trashed = draft("Directly trashed").trash
    hidden = @account.note_folders.create!(name: "Hidden", parent: @folder)
    inherited = draft("Indirectly trashed", folder: hidden)
    hidden.trash
    outside = draft("Outside", folder: note_folders(:reading))
    @folder.trash
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      NoteFolder.transaction do
        @folder.restore
        raise ActiveRecord::Rollback
      end
    end

    assert_enqueued_jobs 1, only: NoteFolder::ResumeIndexingJob do
      @folder.restore
    end
    assert_no_enqueued_jobs only: Note::IndexJob
    perform_enqueued_jobs only: NoteFolder::ResumeIndexingJob
    assert_equal [ pending, failed ].map { |note| [ note.id, note.embedding_generation ] }.sort,
      enqueued_jobs.select { |job| job[:job] == Note::IndexJob }.map { |job| job[:args] }.sort
    assert_equal "pending", failed.reload.embedding_status
    assert_equal "ready", ready.reload.embedding_status
    assert_equal original, ready.chunk_ids
    refute Note.active_in(@account.id).exists?(id: [ trashed.id, inherited.id ])
    assert Note.active_in(@account.id).exists?(outside.id)
  end

  test "permanent removal cleans up ready chunks including through a stale loaded association" do
    note = draft("Direct")
    stale_note = Note.find(note.id)
    assert_empty stale_note.chunks.load
    index(note)
    assert_not_empty note.reload.chunks
    note.trash
    stale_note.purge(by: @owner)
    assert_empty Chunk.where(chunkable: note)

    branch_note = draft("Branch")
    stale_branch_note = Note.find(branch_note.id)
    assert_empty stale_branch_note.chunks.load
    index(branch_note)
    assert_not_empty branch_note.reload.chunks
    stale_branch_note.destroy!
    assert_empty Chunk.where(chunkable: branch_note)

    child = draft("Child", folder: note_folders(:interviews))
    index(child)
    @folder.trash.purge(by: @owner)
    assert_empty Chunk.where(chunkable: child)
  end

  private
    def with_queue_outage(failure)
      adapter = queue_adapter
      adapter.define_singleton_method(:enqueue_at) { |*args| failure.call(*args) }
      yield
    ensure
      adapter.singleton_class.remove_method(:enqueue_at)
    end

    def draft(title, body_html: "", folder: @folder)
      Note.save_draft!(account: @account, folder:, draft_key: SecureRandom.uuid, title:, body_html:)
    end

    def edit(note, title, body_html: "")
      note.edit_content!(expected_revision: note.content_revision, title:, body_html:)
    end

    def multi_chunk_text
      ("Synthetic note evidence. " * (ENV.fetch("CHUNK_SIZE").to_i / 10)).strip
    end

    def fake_provider(&block)
      RubyLLM.define_singleton_method(:embed) { |text, **| block.call(text) }
    end

    def embedding_result(vector = @vector)
      RubyLLM::Embedding.new(vectors: vector, input_tokens: 8, model: "fake")
    end

    def index(note)
      fake_provider { embedding_result }
      Note::IndexJob.perform_now(note.id, note.embedding_generation)
    ensure
      fake_provider { flunk "unexpected embedding request" }
    end

    def while_computing(note, generation)
      reached_provider = Queue.new
      resume_provider = Queue.new
      fake_provider do |_text|
        ApplicationRecord.with_connection do |connection|
          reached_provider << [ connection, connection.transaction_open? ]
          resume_provider.pop
        end
        embedding_result
      end
      worker = Thread.new { Note::IndexJob.perform_now(note.id, generation) }

      provider_connection, open_transaction = Timeout.timeout(5) { reached_provider.pop }
      refute open_transaction, "provider work must run outside an open transaction"
      Account.transaction do
        Account.with_connection { |connection| refute_same provider_connection, connection }
        assert_equal @account, Account.lock("FOR UPDATE NOWAIT").find(@account.id)
        yield
      end
      resume_provider << true
      assert worker.join(5), "indexing did not finish after the lifecycle change"
      worker.value
    ensure
      if worker&.alive?
        worker.kill
        worker.join(5)
      end
      fake_provider { flunk "unexpected embedding request" }
    end
end
