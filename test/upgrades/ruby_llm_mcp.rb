# Source the disposable Active Record encryption settings and pre-create
# nosia_mcp_oauth_upgrade_test (empty PostgreSQL database with pgvector available).
# Run with: bundle exec ruby test/upgrades/ruby_llm_mcp.rb
# Takes the 2.0 schema from Git, not the current schema or the Rails test helper.
require "bundler/setup"
require "minitest/autorun"
require "active_record"
require "neighbor"
require "open3"
require "tempfile"

class RubyLLMMcpUpgradeTest < Minitest::Test
  DATABASE = "nosia_mcp_oauth_upgrade_test"
  ROOT = File.expand_path("../..", __dir__)
  BASE_SCHEMA = "8f1fecf7f0ac7c79868cdb1e2867613ad87061e9:db/schema.rb"
  MIGRATION_2_1 = 20261119000001
  MIGRATION_2_2 = 20261119000002
  SNAPSHOT_TABLES = %w[
    ruby_llm_models chats messages ruby_llm_tool_calls ruby_llm_usages accounts token_usages
    active_storage_attachments active_storage_blobs mcp_servers chat_mcp_sessions
  ].freeze
  AUTH_CONFIG = { "token" => "disposable-static-token" }.freeze
  CONNECTION_CONFIG = { "headers" => { "X-Example" => "disposable-header" } }.freeze

  class EncryptedConnector < ActiveRecord::Base
    self.table_name = "mcp_servers"
    encrypts :auth_config, :connection_config
  end

  def setup
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: DATABASE)
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Encryption.configure(
      primary_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"),
      deterministic_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"),
      key_derivation_salt: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
    )
  end

  def test_upgrades_existing_2_0_data_without_rewriting_chat_history
    with_stable_2_0 do
      assert_encrypted_connector
      before = persisted_records_snapshot
      refute connection.column_exists?(:ruby_llm_tool_calls, :provider_id)

      migrate_to MIGRATION_2_1
      assert_2_1_schema
      assert_equal before, persisted_records_snapshot
      %w[judgment video research].each { |operation| insert_usage(operation) }
      assert_rejects_usage "code_execution"
      before_2_2 = persisted_records_snapshot

      migrate_to MIGRATION_2_2
      assert connection.column_exists?(:ruby_llm_tool_calls, :provider_call_id, :string)
      assert connection.column_exists?(:ruby_llm_tool_calls, :namespace, :string)
      assert_equal [ [ "call_historical", nil ] ], table(:ruby_llm_tool_calls).pluck(:tool_call_id, :provider_call_id)
      assert_equal before_2_2, persisted_records_snapshot
      assert_encrypted_connector
      insert_usage "code_execution"
      assert_rejects_usage "not_a_ruby_llm_operation"
    end
  end

  def test_upgrades_existing_2_1_provider_ids_and_mcp_payloads
    with_stable_2_0 do
      migrate_to MIGRATION_2_1
      # Some installations have the intermediate provider_id column. Exercise
      # the rename with a value distinct from the existing internal call ID.
      connection.add_column :ruby_llm_tool_calls, :provider_id, :string
      state = { "task_id" => "task-fixture" }
      result = { "content" => [ { "type" => "text", "text" => "preserved" } ] }
      table(:ruby_llm_tool_calls).where(id: 201).update_all(provider_id: "provider-fixture", mcp_state: state, mcp_result: result)
      before = persisted_records_snapshot

      migrate_to MIGRATION_2_2
      refute connection.column_exists?(:ruby_llm_tool_calls, :provider_id)
      assert_equal [ [ "provider-fixture", state, result ] ], table(:ruby_llm_tool_calls).pluck(:provider_call_id, :mcp_state, :mcp_result)
      assert_equal before, persisted_records_snapshot
      assert_refuses_rollback MIGRATION_2_2
    end
  end

  def test_refuses_to_roll_back_2_1_and_lose_mcp_data
    with_stable_2_0 do
      migrate_to MIGRATION_2_1
      insert(:ruby_llm_mcp_credentials, key: "fixture", owner_type: "User", owner_id: 1)
      assert_refuses_rollback MIGRATION_2_1
      assert_equal [ "fixture" ], table(:ruby_llm_mcp_credentials).pluck(:key)
    end
  end

  private
    def with_stable_2_0
      assert_equal DATABASE, connection.select_value("SELECT current_database()")
      assert_empty connection.data_sources, "Use an empty, dedicated PostgreSQL database"
      # PostgreSQL can roll back the schema load and both upgrades along with
      # the fixture data, leaving the dedicated database empty for another run.
      connection.transaction do
        load_base_schema
        seed_2_0_data
        @snapshot_columns = SNAPSHOT_TABLES.index_with { |name| connection.columns(name).map(&:name) }
        yield
        raise ActiveRecord::Rollback
      end
    end

    def connection
      ActiveRecord::Base.connection
    end

    def load_base_schema
      schema, error, status = Open3.capture3("git", "-C", ROOT, "show", BASE_SCHEMA)
      assert status.success?, "Could not read the pinned 2.0 schema: #{error}"
      Tempfile.create([ "ruby-llm-2-0-schema", ".rb" ]) do |file|
        file.write(schema)
        file.flush
        load file.path
      end
    end

    def seed_2_0_data
      insert(:users, id: 1, email: "migration@example.invalid")
      insert(:accounts, id: 2, owner_id: 1, input_tokens_count: 120, output_tokens_count: 60)
      insert(:ruby_llm_models, id: 11, model_id: "fixture-model", provider: "openai", name: "Fixture model")
      insert(:chats, id: 21, account_id: 2, user_id: 1, ruby_llm_model_id: 11, input_tokens_count: 80, output_tokens_count: 20)
      insert(:messages, id: 101, chat_id: 21, role: 20, content: "user text")
      insert(:messages, id: 102, chat_id: 21, role: 10, model_id: 11, content: '{"answer":"remembered"}', raw_content: { answer: "remembered" })
      insert(:messages, id: 103, chat_id: 21, role: 30, content: "tool result")
      insert(:ruby_llm_tool_calls, id: 201, message_type: "Message", message_id: 102,
        result_type: "Message", result_id: 103, tool_call_id: "call_historical", name: "lookup", arguments: { query: "remembered" })
      table(:messages).where(id: 103).update_all(tool_call_id: 201)
      insert(:ruby_llm_usages, id: 301, chat_type: "Chat", chat_id: 21, message_type: "Message", message_id: 102,
        operation: "chat", provider: "openai", model: "fixture-model", status: "succeeded", input_tokens: 80, output_tokens: 20, total_cost: "0.012")
      insert(:token_usages, id: 401, account_id: 2, chat_id: 21, source_type: "Message", source_id: 102,
        kind: "completion", model_id: "fixture-model", input_tokens: 80, output_tokens: 20)
      insert(:active_storage_blobs, id: 501, key: "mcp-migration-attachment", filename: "fixture.txt", service_name: "test", byte_size: 7)
      insert(:active_storage_attachments, id: 502, name: "attachments", record_type: "Message", record_id: 101, blob_id: 501)
      EncryptedConnector.reset_column_information
      EncryptedConnector.create!(id: 601, account_id: 2, name: "Static fixture", endpoint: "https://example.invalid/mcp",
        auth_config: AUTH_CONFIG, connection_config: CONNECTION_CONFIG)
      insert(:chat_mcp_sessions, id: 602, chat_id: 21, mcp_server_id: 601)
    end

    def insert(name, attributes)
      table(name).insert_all!([ attributes ])
    end

    # DDL can leave a stale pool-level schema cache even for a fresh class.
    def table(name)
      Class.new(ActiveRecord::Base) { self.table_name = name.to_s }.tap(&:reset_column_information)
    end

    def assert_encrypted_connector
      ciphertext = connection.select_one("SELECT auth_config, connection_config FROM mcp_servers WHERE id = 601")
      refute_includes ciphertext.fetch("auth_config"), AUTH_CONFIG.fetch("token")
      refute_includes ciphertext.fetch("connection_config"), CONNECTION_CONFIG.dig("headers", "X-Example")
      connector = EncryptedConnector.find(601)
      assert_equal AUTH_CONFIG, connector.auth_config
      assert_equal CONNECTION_CONFIG, connector.connection_config
    end

    def persisted_records_snapshot
      @snapshot_columns.to_h do |name, columns|
        projection = columns.map { |column| connection.quote_column_name(column) }.join(", ")
        [ name, connection.select_all("SELECT #{projection} FROM #{connection.quote_table_name(name)} ORDER BY id").to_a ]
      end
    end

    def migrate_to(version)
      context = connection.pool.migration_context
      assert context.migrations.any? { |migration| migration.version == version }, "Missing RubyLLM migration #{version}"
      context.migrate(version)
      assert_equal version, context.current_version
    end

    def assert_refuses_rollback(version)
      context = connection.pool.migration_context
      error = assert_raises(StandardError) { context.rollback }
      assert_instance_of ActiveRecord::IrreversibleMigration, error.cause
      assert_equal version, context.current_version
    end

    def assert_2_1_schema
      assert connection.table_exists?(:ruby_llm_mcp_credentials)
      assert connection.index_exists?(:ruby_llm_mcp_credentials, :key, unique: true)
      %i[mcp_state mcp_result].each do |column|
        assert connection.column_exists?(:ruby_llm_tool_calls, column, :jsonb)
      end
    end

    def insert_usage(operation)
      insert(:ruby_llm_usages, operation: operation, provider: "sandbox", model: "fixture", status: "succeeded")
    end

    def assert_rejects_usage(operation)
      error = assert_raises(ActiveRecord::StatementInvalid) do
        connection.transaction(requires_new: true) { insert_usage(operation) }
      end
      assert_instance_of PG::CheckViolation, error.cause
    end
end
