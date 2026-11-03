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

  private
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
