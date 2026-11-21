require "test_helper"
require "rake"
require "tmpdir"
require_relative "../../support/chat_account_fixtures"

class NativeIndexTasksTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("nosia_native:prepare_empty_index")
    @native_environment_keys = %w[NOSIA_NATIVE_LOCAL EMBEDDING_DIMENSIONS NOSIA_NATIVE_SCHEMA_VERSION NOSIA_NATIVE_EMBEDDING_FINGERPRINT]
    @previous_native_environment = ENV.to_h.slice(*@native_environment_keys)
    ENV["NOSIA_NATIVE_LOCAL"] = "1"
    ENV["EMBEDDING_DIMENSIONS"] = "768"
    ENV["NOSIA_NATIVE_EMBEDDING_FINGERPRINT"] = "native-test-space"
    @native_root = Pathname(Dir.mktmpdir("nosia-native-index"))
    @native_root.join("storage").mkpath
    @native_root.join("db").mkpath
    File.symlink(Rails.root.join("db/migrate"), @native_root.join("db/migrate"))
    hide_shared_note_fixtures
    Chunk.unscoped.delete_all
    connection = ActiveRecord::Base.connection
    connection.remove_index(:chunks, :embedding) if connection.index_exists?(:chunks, :embedding)
    connection.execute("ALTER TABLE chunks ALTER COLUMN embedding TYPE vector(4096)")
  end

  teardown do
    if @previous_native_environment
      @native_environment_keys.each { |key| ENV.delete(key) }
      ENV.update(@previous_native_environment)
    end
    FileUtils.remove_entry(@native_root) if @native_root
    Chunk.reset_column_information
  end

  test "fresh schema is aligned before the first document is imported" do
    prepare_empty_index
    assert_equal "vector(768)", embedding_column_type
    assert ActiveRecord::Base.connection.index_exists?(:chunks, :embedding)
  end

  test "existing vectors cannot be discarded by preparation" do
    insert_picker_chunk(@first, texts(:picker_first_text), "existing content", [ 0.1 ] * 4096)
    assert_raises(RuntimeError) { prepare_empty_index }
    assert_equal "vector(4096)", embedding_column_type
    assert_equal 1, Chunk.unscoped.where.not(embedding: nil).count
  end

  test "standard deployments cannot invoke the native schema adaptation" do
    ENV.delete("NOSIA_NATIVE_LOCAL")
    assert_raises(Nosia::NativeStack::ConfigurationError) { prepare_empty_index }
    assert_equal "vector(4096)", embedding_column_type
  end

  test "validation derives the supported schema from packaged migrations" do
    prepare_empty_index
    ENV.delete("NOSIA_NATIVE_SCHEMA_VERSION")
    invoke_native_task("validate_index")
    assert_equal "native-test-space", @native_root.join("storage/.native-embedding-fingerprint").read
  end

  test "a runtime schema override cannot authorize a newer database" do
    prepare_empty_index
    ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('99990101000000')")
    ENV["NOSIA_NATIVE_SCHEMA_VERSION"] = "99990101000000"
    error = assert_raises(RuntimeError) { invoke_native_task("validate_index") }
    assert_match(/schema/i, error.message)
    refute @native_root.join("storage/.native-embedding-fingerprint").exist?
  end

  test "index maintenance cannot mutate a newer database" do
    insert_picker_chunk(@first, texts(:picker_first_text), "existing content", [ 0.1 ] * 4096)
    ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('99990101000000')")
    %w[prepare_empty_index reindex].each do |name|
      error = assert_raises(RuntimeError) { invoke_native_task(name) }
      assert_match(/schema/i, error.message)
    end
    assert_equal "vector(4096)", embedding_column_type
    assert_equal 1, Chunk.unscoped.where.not(embedding: nil).count
    refute @native_root.join("storage/.native-reindex-target").exist?
  end

  test "validation refuses a database with pending migrations" do
    prepare_empty_index
    ENV["NOSIA_NATIVE_SCHEMA_VERSION"] = latest_schema_version.to_s
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations WHERE version = (SELECT MAX(version) FROM schema_migrations)")
    error = assert_raises(RuntimeError) { invoke_native_task("validate_index") }
    assert_match(/schema/i, error.message)
  end

  test "an interrupted reindex is never validated even in the previous space" do
    prepare_empty_index
    ENV["NOSIA_NATIVE_SCHEMA_VERSION"] = latest_schema_version.to_s
    @native_root.join("storage/.native-embedding-fingerprint").write("native-test-space")
    @native_root.join("storage/.native-reindex-target").write("native-test-space")
    error = assert_raises(RuntimeError) { invoke_native_task("validate_index") }
    assert_match(/reindex/i, error.message)
  end

  test "blank fingerprints cannot authorize an embedding space" do
    prepare_empty_index
    ENV["NOSIA_NATIVE_SCHEMA_VERSION"] = latest_schema_version.to_s
    ENV["NOSIA_NATIVE_EMBEDDING_FINGERPRINT"] = "  "
    assert_raises(Nosia::NativeStack::ConfigurationError) { invoke_native_task("validate_index") }
    refute @native_root.join("storage/.native-embedding-fingerprint").exist?
  end

  test "blank fingerprints cannot discard existing vectors during reindex" do
    insert_picker_chunk(@first, texts(:picker_first_text), "first account", [ 0.1 ] * 4096)
    ENV["NOSIA_NATIVE_EMBEDDING_FINGERPRINT"] = ""
    assert_raises(Nosia::NativeStack::ConfigurationError) { invoke_native_task("reindex") }
    assert_equal "vector(4096)", embedding_column_type
    assert_equal 1, Chunk.unscoped.where.not(embedding: nil).count
  end

  test "reindex does not resume a marker with incompatible dimensions" do
    insert_picker_chunk(@first, texts(:picker_first_text), "first account", [ 0.1 ] * 4096)
    insert_picker_chunk(@second, texts(:picker_second_text), "other account", [ 0.2 ] * 4096)
    @native_root.join("storage/.native-reindex-target").write("native-test-space")
    embed = ->(*) { Struct.new(:vectors, :tokens).new([ 0.3 ] * 768, nil) }
    with_singleton_replacement(RubyLLM, :embed, embed) { invoke_native_task("reindex") }
    assert_equal "vector(768)", embedding_column_type
    assert_equal 2, Chunk.unscoped.where.not(embedding: nil).count
    assert_equal "native-test-space", @native_root.join("storage/.native-embedding-fingerprint").read
    refute @native_root.join("storage/.native-reindex-target").exist?
  end

  test "an interrupted reindex resumes only the remaining vectors across accounts" do
    insert_picker_chunk(@first, texts(:picker_first_text), "first account", [ 0.1 ] * 4096)
    insert_picker_chunk(@second, texts(:picker_second_text), "other account", [ 0.2 ] * 4096)
    @native_root.join("storage/.native-embedding-fingerprint").write("native-test-space")
    ActsAsTenant.current_tenant = @first
    calls = 0
    embed = ->(*) do
      calls += 1
      raise "inference interrupted" if calls == 2
      Struct.new(:vectors, :tokens).new([ 0.3 ] * 768, nil)
    end
    with_singleton_replacement(RubyLLM, :embed, embed) do
      error = assert_raises(RuntimeError) { invoke_native_task("reindex") }
      assert_equal "inference interrupted", error.message
    end
    assert_equal 1, Chunk.unscoped.where.not(embedding: nil).count
    assert_raises(RuntimeError) { invoke_native_task("validate_index") }

    calls = 0
    embed = ->(*) do
      calls += 1
      Struct.new(:vectors, :tokens).new([ 0.3 ] * 768, nil)
    end
    with_singleton_replacement(RubyLLM, :embed, embed) { invoke_native_task("reindex") }
    assert_equal 1, calls
    assert_equal 2, Chunk.unscoped.where.not(embedding: nil).count
    invoke_native_task("validate_index")
    refute @native_root.join("storage/.native-reindex-target").exist?
  end

  test "manual re-embedding skips a note and still handles a later source chunk" do
    note, source = mixed_chunks
    new_vector = [ 0.5 ] * Chunk.columns_hash.fetch("embedding").limit
    inputs = []

    with_singleton_replacement(RubyLLM, :embed, ->(text, **) {
      inputs << text
      RubyLLM::Embedding.new(vectors: new_vector, model: "fake")
    }) do
      Chunk.where(id: [ note.id, source.id ]).order(:id).each(&:generate_embedding!)
    end

    assert_equal [ source.content ], inputs
    assert_equal [ 0.25 ] * new_vector.length, note.reload.embedding
    assert_equal new_vector, source.reload.embedding
  end

  test "legacy same-width model switch rebuilds active note generations without sending hidden text" do
    old_chunk, source = mixed_chunks
    note = old_chunk.chunkable
    generation = note.embedding_generation
    note.update!(embedding_status: :ready, indexed_generation: generation)
    hidden = draft_note("Hidden")
    hidden.update!(embedding_status: :ready, indexed_generation: hidden.embedding_generation)
    hidden.trash
    new_vector = [ 0.5 ] * Chunk.columns_hash.fetch("embedding").limit
    old_hidden = insert_picker_chunk(@first, hidden, "old hidden chunk", [ 0.25 ] * new_vector.length)
    requests = []
    ENV["EMBEDDING_DIMENSIONS"] = new_vector.length.to_s
    previous_model = ENV["EMBEDDING_MODEL"]
    ENV["EMBEDDING_MODEL"] = "synthetic-same-width-switch"

    with_singleton_replacement(STDIN, :gets, -> { "yes\n" }) do
      with_singleton_replacement(RubyLLM, :embed, ->(text, model:, dimensions:, **) {
        requests << [ text, model, dimensions ]
        RubyLLM::Embedding.new(vectors: new_vector, model: "fake")
      }) do
        task = Rake::Task["embeddings:rebuild"]
        task.reenable
        assert_queries_match(/SELECT "chunks"\.\*.*"chunks"\."chunkable_type" !=/) { task.invoke }
      end
    end

    assert_equal [ source.content, note.title ].map { |text| [ text, "synthetic-same-width-switch", new_vector.length ] }, requests
    assert_equal [ "ready", generation + 1, generation + 1 ], embedding_state(note)
    refute Chunk.exists?(old_chunk.id)
    assert_equal [ new_vector ], note.chunks.reload.map(&:embedding)
    assert_equal [ "pending", 2, nil ], embedding_state(hidden)
    assert_equal [ old_hidden.id ], hidden.chunks.reload.ids
    assert_equal new_vector, source.reload.embedding
  ensure
    ENV["EMBEDDING_MODEL"] = previous_model
  end

  test "native reindex rebuilds note chunks through the new generation not the legacy selector" do
    old_chunk, source = mixed_chunks
    note = old_chunk.chunkable
    original_generation = note.embedding_generation
    note.update!(embedding_status: :ready, indexed_generation: original_generation)
    inputs = []
    new_vector = [ 0.5 ] * 768

    with_singleton_replacement(RubyLLM, :embed, ->(text, **) {
      inputs << text
      RubyLLM::Embedding.new(vectors: new_vector, model: "fake")
    }) do
      assert_queries_match(/SELECT "chunks"\.\*.*"chunks"\."chunkable_type" !=/) do
        invoke_native_task("reindex")
      end
    end

    assert_equal [ source.content, note.title ], inputs
    assert_equal "vector(768)", embedding_column_type
    assert_equal new_vector, source.reload.embedding
    assert_equal [ "ready", original_generation + 1, original_generation + 1 ], embedding_state(note)
    refute Chunk.exists?(old_chunk.id)
    assert_equal [ new_vector ], note.chunks.reload.map(&:embedding)
    assert_equal [ original_generation + 1 ], note.chunks.map { |chunk| chunk.metadata["note_generation"] }
    assert_equal "native-test-space", @native_root.join("storage/.native-embedding-fingerprint").read
    refute @native_root.join("storage/.native-reindex-target").exist?
  end

  test "interrupted native note rebuild resumes its target without re-embedding ready notes" do
    original_width = Chunk.columns_hash.fetch("embedding").limit
    ready, hidden, pending, failed = [ "Ready", "Hidden", "Pending", "Failed" ].map { |title| draft_note(title) }
    later_text = "later segment " * (ENV.fetch("CHUNK_SIZE", "512").to_i / 5)
    pending.edit_content!(expected_revision: pending.content_revision, title: pending.title, body_html: "<p>#{later_text}</p>")
    [ ready, hidden ].each do |note|
      note.update!(embedding_status: :ready, indexed_generation: note.embedding_generation)
      insert_picker_chunk(@first, note, note.title, [ 0.25 ] * original_width)
    end
    old_generation = pending.embedding_generation
    failed.update!(embedding_status: :failed)
    hidden.note_folder.trash
    empty = draft_note("Becomes empty")
    empty.edit_content!(expected_revision: empty.content_revision, title: "\u200B", body_html: "")
    empty_generation = empty.embedding_generation
    completed = @native_root.join("storage/.native-embedding-fingerprint")
    target = @native_root.join("storage/.native-reindex-target")
    completed.write("old-space")
    calls = []

    embed = ->(text, **) do
      calls << text
      if text == ready.title
        # A queued request for the previous space must exit before calling RubyLLM.
        Note::IndexJob.perform_now(pending.id, old_generation)
      elsif text.start_with?("later segment")
        raise RubyLLM::Error, "private provider error"
      end
      RubyLLM::Embedding.new(vectors: [ 0.5 ] * 768, model: "fake")
    end

    with_singleton_replacement(RubyLLM, :embed, embed) do
      error = assert_raises(Note::Indexable::EmbeddingError) { invoke_native_task("reindex") }
      assert_equal "Embedding provider request failed", error.message
      assert_nil error.cause
    end
    assert_equal [ ready.title, pending.title ], calls.first(2)
    assert_equal 3, calls.size
    assert_match(/\Alater segment/, calls.last)
    assert_equal [ "ready", 2, 2 ], embedding_state(ready)
    ready_chunks = ready.chunk_ids
    assert_equal [ "pending", old_generation + 1, nil ], embedding_state(pending)
    assert_empty pending.chunks
    assert_equal [ "pending", 2, nil ], embedding_state(failed)
    assert_equal [ "pending", 2, nil ], embedding_state(hidden)
    assert_equal [ nil ], hidden.chunks.reload.map(&:embedding)
    assert_equal [ "empty", empty_generation, nil ], embedding_state(empty)
    assert_equal "old-space", completed.read
    assert_equal({ "fingerprint" => "native-test-space", "dimensions" => 768 }, JSON.parse(target.read))
    assert_match(/Incomplete reindex/, assert_raises(RuntimeError) { invoke_native_task("validate_index") }.message)

    calls.clear
    with_singleton_replacement(RubyLLM, :embed, ->(text, **) {
      calls << text
      RubyLLM::Embedding.new(vectors: [ 0.75 ] * 768, model: "fake")
    }) { invoke_native_task("reindex") }

    assert_equal pending.title, calls.first
    assert_equal failed.title, calls.last
    assert calls[1...-1].all? { |text| text.match?(/\A(?:later|segment) /) }
    refute_includes calls, ready.title
    refute_includes calls, hidden.title
    assert_equal ready_chunks, ready.reload.chunk_ids
    assert_equal [ "ready", old_generation + 1, old_generation + 1 ], embedding_state(pending)
    assert_equal calls.size - 1, pending.chunks.count
    assert_equal [ "ready", 2, 2 ], embedding_state(failed)
    assert_equal [ "pending", 2, nil ], embedding_state(hidden)
    assert_equal "native-test-space", completed.read
    refute target.exist?
    invoke_native_task("validate_index")

    assert_enqueued_with job: NoteFolder::ResumeIndexingJob, args: [ hidden.note_folder_id ] do
      hidden.note_folder.restore
    end
    perform_enqueued_jobs only: NoteFolder::ResumeIndexingJob
    assert_enqueued_with job: Note::IndexJob, args: [ hidden.id, 2 ]
    with_singleton_replacement(RubyLLM, :embed, ->(*, **) {
      RubyLLM::Embedding.new(vectors: [ 0.5 ] * 768, model: "fake")
    }) { Note::IndexJob.perform_now(hidden.id, 2) }
    assert_equal [ "ready", 2, 2 ], embedding_state(hidden)
    assert_equal [ [ 0.5 ] * 768 ], hidden.chunks.reload.map(&:embedding)
  end

  private
    def hide_shared_note_fixtures
      # Other suites can load these fixtures before their per-test transactions.
      # Hide only those notes for this instance-wide rebuild test; rollback restores them.
      fixture_ids = %i[field_notes second_team_note].map { |label| ActiveRecord::FixtureSet.identify(label) }
      [ @first, @second ].each do |account|
        Note.active_in(account.id).where(id: fixture_ids).find_each(&:trash)
      end
    end

    def draft_note(title)
      folder = @first.note_folders.create!(name: "#{title} folder")
      Note.save_draft!(account: @first, folder:, draft_key: SecureRandom.uuid, title:, body_html: "")
    end

    def embedding_state(note)
      note.reload.values_at(:embedding_status, :embedding_generation, :indexed_generation)
    end

    def mixed_chunks
      width = Chunk.columns_hash.fetch("embedding").limit
      note = Note.save_draft!(account: @first, folder: @first.general_note_folder, draft_key: SecureRandom.uuid,
        title: "Note vector", body_html: "")
      stored_note = insert_picker_chunk(@first, note, "note content", [ 0.25 ] * width)
      stored_source = insert_picker_chunk(@first, texts(:picker_first_text), "later source content", [ 0.25 ] * width)
      [ stored_note, stored_source ]
    end

    def prepare_empty_index
      invoke_native_task("prepare_empty_index")
    end

    def invoke_native_task(name)
      task = Rake::Task["nosia_native:#{name}"]
      task.reenable
      root = @native_root
      with_singleton_replacement(Rails, :root, -> { root }) { task.invoke }
    end

    def latest_schema_version
      ActiveRecord::Base.connection.select_value("SELECT MAX(version)::bigint FROM schema_migrations").to_i
    end

    def embedding_column_type
      ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT format_type(atttypid, atttypmod)
        FROM pg_attribute
        WHERE attrelid = 'chunks'::regclass AND attname = 'embedding'
      SQL
    end
end
