# Run explicitly with: bundle exec ruby test/upgrades/ruby_llm_v2.rb
# Deliberately not a Rails *_test.rb: test_helper would load the current schema.
require "bundler/setup"
require "minitest/autorun"
require "active_record"
require "ruby_llm"
require "pgvector"

class RubyLLMV2UpgradeTest < Minitest::Test
  DATABASE = "nosia_ruby_llm_upgrade_migration_test"
  ROOT = File.expand_path("../..", __dir__)
  PHASES = %w[prepare_ruby_llm_v2_upgrade backfill_ruby_llm_v2_data finish_ruby_llm_v2_upgrade].freeze
  LEGACY_SCHEMA = File.join(ROOT, "test/fixtures/files/ruby_llm_1_16_schema.rb")

  def setup
    @migration_files = PHASES.map do |phase|
      matches = Dir[File.join(ROOT, "db/migrate/*_#{phase}.rb")]
      assert_equal 1, matches.length, "Generate exactly one #{phase} migration before rehearsal"
      matches.first
    end
    @migration_files.each { |file| require file }
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: DATABASE)
    guard_database!
    ActiveRecord::Migration.verbose = false
    # Only these scratch tables are removed. Never drop a database/schema or read
    # Rails configuration, DATABASE_URL, dotenv, credentials, or application models.
    fixture_tables = File.read(LEGACY_SCHEMA).scan(/create_table "([^"]+)"/).flatten
    guard_database!
    (fixture_tables + %w[ruby_llm_models ruby_llm_tool_calls ruby_llm_usages ruby_llm_batches ruby_llm_v2_backfills schema_migrations ar_internal_metadata]).each do |name|
      connection.drop_table(name, if_exists: true, force: :cascade)
    end
    guard_database!
    load LEGACY_SCHEMA
    @tables = {}
    seed_legacy_data
    @before = snapshot
  end

  def test_preserves_legacy_records_content_links_and_historical_usage
    timed("prepare") { prepare.up }
    timed("backfill") { backfill.up }
    timed("finish") { finish.up }

    assert_equal @before, snapshot
    assert_equal 7, table(:messages).count
    assert_equal [ 0, 20, 10, 10, 30, 10, 20 ], table(:messages).order(:id).pluck(:role)
    assert_equal({ "answer" => "preserved" }, table(:messages).find(103).raw_content)
    assert_equal({ "answer" => "preserved" }, JSON.parse(table(:messages).find(103).content))
    assert_equal "empty raw keeps plain text", table(:messages).find(107).content
    assert_equal({}, table(:messages).find(107).raw_content)
    assert_equal "user text", table(:messages).find(102).content
    assert_nil table(:messages).find(102).raw_content

    call = table(:ruby_llm_tool_calls).find(201)
    assert_equal [ "Message", 104, "Message", 105 ], call.attributes.values_at("message_type", "message_id", "result_type", "result_id")
    assert_equal @before.fetch(:tool_calls), table(:ruby_llm_tool_calls).order(:id).pluck(:id, :tool_call_id, :name, :arguments, :thought_signature)
    assert_equal 11, table(:chats).find(21).ruby_llm_model_id
    assert_equal [ 11, 12 ], table(:ruby_llm_models).order(:id).pluck(:id)

    usages = table(:ruby_llm_usages).order(:message_id)
    assert_equal [ 103, 104, 106 ], usages.pluck(:message_id)
    assert_equal [ [ 80, 20, 15, 5, 3 ], [ 12, 4, 2, 1, 6 ], [ nil, nil, nil, nil, nil ] ],
      usages.pluck(:input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens, :thinking_tokens)
    assert_equal [ [ "openai", "legacy-answer" ], [ "anthropic", "legacy-tool" ], [ "openai", "legacy-answer" ] ], usages.pluck(:provider, :model)
    assert_equal [ [ "Chat", 21, "Message", "chat", "succeeded" ] ], usages.distinct.pluck(:chat_type, :chat_id, :message_type, :operation, :status)
    assert_equal [ 92, 24, 17, 6, 9 ], %i[input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens].map { |column| usages.sum(column) }
    assert_equal [ [ nil ] * 6 ] * 3, usages.pluck(:input_cost, :output_cost, :cache_read_cost, :cache_write_cost, :thinking_cost, :total_cost)
    assert_equal table(:messages).where(id: [ 103, 104, 106 ]).order(:id).pluck(:created_at, :updated_at), usages.pluck(:created_at, :updated_at)

    %w[content_raw input_tokens output_tokens cached_tokens cache_creation_tokens thinking_tokens model_id tool_call_id].each do |column|
      assert connection.column_exists?(:messages, column), "No cleanup: retain messages.#{column}"
    end
    assert table(:ruby_llm_v2_backfills).where(task: "finished", completed: true).exists?
    assert_preserved_foreign_keys
  end

  def test_resumes_after_a_committed_usage_batch_and_retries_without_duplicates
    prepare.up
    prepare.up
    migration = backfill
    original_say = migration.method(:say)
    migration.define_singleton_method(:say) do |message, *args|
      original_say.call(message, *args)
      raise "simulated interruption after committed usage batch" if message.start_with?("usages: migrated through")
    end
    error = assert_raises(RuntimeError) { migration.up }
    assert_match(/simulated interruption/, error.message)
    assert_equal 3, table(:ruby_llm_usages).count
    progress = table(:ruby_llm_v2_backfills).find_by!(task: "usages")
    assert_equal 107, progress.last_id
    refute progress.completed
    committed = table(:ruby_llm_usages).order(:id).map(&:attributes)
    backfill.up
    prepare.up
    backfill.up
    assert_equal committed, table(:ruby_llm_usages).order(:id).map(&:attributes)
    assert_equal({ 103 => 1, 104 => 1, 106 => 1 }, table(:ruby_llm_usages).group(:message_id).count)
    finish.up
    assert_equal @before, snapshot
    [ prepare, backfill ].each do |phase|
      error = assert_raises(RuntimeError) { phase.up }
      assert_match(/already finished/, error.message)
    end
  end

  def test_finish_refuses_missing_or_incomplete_backfills
    prepare.up
    error = assert_raises(RuntimeError) { finish.up }
    assert_match(/Run BackfillRubyLlmV2Data before this migration/, error.message)
    refute connection.columns(:messages).find { |column| column.name == "cache_until_here" }.null == false
    connection.create_table(:ruby_llm_v2_backfills, id: false) do |t|
      t.string :task
      t.bigint :last_id
      t.boolean :completed, default: false
    end
    table(:ruby_llm_v2_backfills).insert_all!([ { task: "message_content", completed: true } ])
    error = assert_raises(RuntimeError) { finish.up }
    assert_match(/backfills are incomplete: tool_results, usages/, error.message)
    refute table(:ruby_llm_v2_backfills).where(task: "finished").exists?
    assert_equal @before, snapshot
  end

  def test_prepare_refuses_missing_usage_identity_before_moving_tables
    table(:chats).where(id: 21).update_all(model_id: nil)
    error = assert_raises(RuntimeError) { prepare.up }
    assert_match(/Could not determine provider and model for messages id (103|106)/, error.message)
    assert_match(/Set its model reference, or its chat model reference, before retrying/, error.message)
    assert connection.table_exists?(:models)
    assert connection.table_exists?(:tool_calls)
    refute connection.table_exists?(:ruby_llm_usages)
  end

  def test_all_three_phases_are_irreversible_and_nontransactional
    [ prepare, backfill, finish ].each do |migration|
      assert migration.class.disable_ddl_transaction
      error = assert_raises(ActiveRecord::IrreversibleMigration) { migration.down }
      assert_match(/persisted record ownership/, error.message)
    end
  end

  private
    def connection
      ActiveRecord::Base.connection
    end

    def guard_database!
      unless connection.select_value("SELECT current_database()") == DATABASE
        raise "Refusing migration rehearsal outside the dedicated disposable database #{DATABASE}"
      end
    end

    def table(name)
      @tables[name] ||= Class.new(ActiveRecord::Base) do
        self.table_name = name.to_s
        self.inheritance_column = :_type_disabled
      end
    end

    def prepare
      PrepareRubyLlmV2Upgrade.new
    end

    def backfill
      BackfillRubyLlmV2Data.new
    end

    def finish
      FinishRubyLlmV2Upgrade.new
    end

    def timed(phase)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      warn "#{DATABASE} #{phase}: #{format('%.3f', Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)}s (7 messages, not a production estimate)"
    end

    def insert(name, attributes)
      table(name).insert_all!([ { created_at: Time.utc(2026, 1, 2, 3, 4, 5), updated_at: Time.utc(2026, 1, 2, 3, 4, 6) }.merge(attributes) ])
    end

    def seed_legacy_data
      insert(:users, id: 1, email: "migration@example.invalid")
      insert(:accounts, id: 2, owner_id: 1, name: "Migration fixture", input_tokens_count: 1234, output_tokens_count: 567)
      insert(:account_users, id: 3, account_id: 2, user_id: 1)
      insert(:models, id: 11, model_id: "legacy-answer", name: "Historical answer model", provider: "openai")
      insert(:models, id: 12, model_id: "legacy-tool", name: "Historical tool model", provider: "anthropic")
      insert(:chats, id: 21, user_id: 1, account_id: 2, model_id: 11, input_tokens_count: 789, output_tokens_count: 123)
      insert(:messages, id: 101, chat_id: 21, role: 0, content: "system instruction")
      insert(:messages, id: 102, chat_id: 21, role: 20, content: "user text")
      insert(:messages, id: 103, chat_id: 21, role: 10, content: "stale text loses to structured JSON", content_raw: { answer: "preserved" }, input_tokens: 80, output_tokens: 20, cached_tokens: 15, cache_creation_tokens: 5, thinking_tokens: 3)
      insert(:messages, id: 104, chat_id: 21, role: 10, model_id: 12, content: "calling tool", input_tokens: 12, output_tokens: 4, cached_tokens: 2, cache_creation_tokens: 1, thinking_tokens: 6)
      insert(:tool_calls, id: 201, message_id: 104, tool_call_id: "call_historical", name: "lookup", arguments: { query: "preserved" }, thought_signature: "signature")
      insert(:messages, id: 105, chat_id: 21, role: 30, content: "tool result", tool_call_id: 201)
      insert(:messages, id: 106, chat_id: 21, role: 10, content: "assistant without reported tokens")
      insert(:messages, id: 107, chat_id: 21, role: 20, content: "empty raw keeps plain text", content_raw: {})
      table(:active_storage_blobs).insert_all!([ { id: 301, key: "migration-attachment", filename: "legacy.txt", content_type: "text/plain", service_name: "test", byte_size: 6, created_at: Time.utc(2026, 1, 2) } ])
      table(:active_storage_attachments).insert_all!([ { id: 302, name: "attachments", record_type: "Message", record_id: 102, blob_id: 301, created_at: Time.utc(2026, 1, 2) } ])
      insert(:token_usages, id: 401, account_id: 2, chat_id: 21, source_type: "Message", source_id: 103, kind: "completion", model_id: "legacy-answer", input_tokens: 80, output_tokens: 20, cached_tokens: 15, cache_creation_tokens: 5, thinking_tokens: 3)
      @foreign_keys = foreign_keys
    end

    def snapshot
      {
        messages: table(:messages).order(:id).pluck(:id, :chat_id, :role, :model_id, :tool_call_id, :content_raw, :input_tokens, :output_tokens, :cached_tokens, :cache_creation_tokens, :thinking_tokens),
        text: table(:messages).where.not(id: 103).order(:id).pluck(:id, :content),
        tool_calls: table(connection.table_exists?(:tool_calls) ? :tool_calls : :ruby_llm_tool_calls).order(:id).pluck(:id, :tool_call_id, :name, :arguments, :thought_signature),
        attachments: table(:active_storage_attachments).order(:id).map(&:attributes),
        blobs: table(:active_storage_blobs).order(:id).map(&:attributes),
        ledger: table(:token_usages).order(:id).map(&:attributes),
        accounts: table(:accounts).order(:id).pluck(:id, :input_tokens_count, :output_tokens_count),
        chats: table(:chats).order(:id).pluck(:id, :input_tokens_count, :output_tokens_count)
      }
    end

    def foreign_keys
      connection.tables.flat_map do |name|
        connection.foreign_keys(name).map { |key| [ name, key.column, key.to_table, key.on_delete ] }
      end.sort_by(&:to_s)
    end

    def assert_preserved_foreign_keys
      expected = @foreign_keys.reject { |from, column, _to, _delete| from == "tool_calls" && column == "message_id" }.map do |from, column, to, on_delete|
        [ from, from == "chats" && column == "model_id" ? "ruby_llm_model_id" : column,
          { "models" => "ruby_llm_models", "tool_calls" => "ruby_llm_tool_calls" }.fetch(to, to), on_delete ]
      end.sort_by(&:to_s)
      assert_equal expected, foreign_keys
    end
end
