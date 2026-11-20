# PostgreSQL expansion of RubyLLM v2.1.0's upgrade_ruby_llm_to_2_1.rb.tt.
# Copyright (c) 2025 Carmine Paolino (MIT; see support/ruby_llm_v2_legacy_content_sql.rb).
class UpgradeRubyLlmTo21 < ActiveRecord::Migration[8.1]
  SOURCE_USAGE_OPERATIONS = %w[chat embedding moderation image speech transcription ocr rerank].freeze
  USAGE_OPERATIONS = (SOURCE_USAGE_OPERATIONS + %w[judgment video research]).freeze

  # Rails hashes the original SQL, so loading a deparsed dump can change the name.
  # 2.0: prepare migration, checked-in 2.0 schema, and its PostgreSQL 18 re-dump.
  SOURCE_USAGE_CHECK_NAMES = %w[chk_rails_71abd85d6e chk_rails_e93d6d7e68 chk_rails_5a75d411f0].freeze
  # 2.1: this migration and its Rails schema dump.
  USAGE_CHECK_NAMES = %w[chk_rails_68fa7685c9 chk_rails_b21c7a9cfb].freeze

  def up
    unless table_exists?(:ruby_llm_mcp_credentials)
      create_table :ruby_llm_mcp_credentials, id: :bigint do |t|
        t.references :owner, polymorphic: true, type: :bigint
        t.string :key, null: false
        t.text :data
        t.timestamps

        t.index :key, unique: true
      end
    end

    unless column_exists?(:ruby_llm_tool_calls, :mcp_state)
      if column_exists?(:ruby_llm_tool_calls, :pending_input)
        rename_column :ruby_llm_tool_calls, :pending_input, :mcp_state
      else
        add_column :ruby_llm_tool_calls, :mcp_state, :jsonb
      end
    end

    unless column_exists?(:ruby_llm_tool_calls, :mcp_result)
      add_column :ruby_llm_tool_calls, :mcp_result, :jsonb
    end

    unless column_exists?(:ruby_llm_usages, :server_tool_use)
      add_column :ruby_llm_usages, :server_tool_use, :jsonb
    end

    if columns(:ruby_llm_usages).any? { |column| column.name == "chat_id" && !column.null }
      change_column_null :ruby_llm_usages, :chat_type, true
      change_column_null :ruby_llm_usages, :chat_id, true
    end

    unless column_exists?(:ruby_llm_usages, :owner_id)
      add_reference :ruby_llm_usages, :owner, polymorphic: true, type: :bigint, index: true
    end

    upgrade_usage_operations

    unless column_exists?(:messages, :cache_ttl)
      add_column :messages, :cache_ttl, :string
    end

    unless table_exists?(:ruby_llm_provider_files)
      create_table :ruby_llm_provider_files, id: :bigint do |t|
        t.string :blob_key, null: false
        t.string :provider, null: false
        t.string :account, null: false
        t.text :file_id, null: false
        t.datetime :expires_at
        t.timestamps

        t.index [ :blob_key, :provider, :account ], unique: true, name: "index_ruby_llm_provider_files_uniqueness"
      end
    end
  end

  def down
    # The upstream conditional changes don't record which columns were renamed
    # or added, and RubyLLM may already have written credentials and usage rows.
    raise ActiveRecord::IrreversibleMigration, "Restore a pre-upgrade database backup to roll back RubyLLM 2.1"
  end

  private
    def upgrade_usage_operations
      matches = check_constraints(:ruby_llm_usages).select do |check|
        case check.name
        when *SOURCE_USAGE_CHECK_NAMES
          stock_usage_operations(check.expression) == SOURCE_USAGE_OPERATIONS.sort
        when *USAGE_CHECK_NAMES
          stock_usage_operations(check.expression) == USAGE_OPERATIONS.sort
        end
      end
      check = matches.first
      unless matches.one? && check.validate?
        raise "Expected one validated stock RubyLLM 2.0 or 2.1 usage operation check, found #{matches.size} matching checks. Review ruby_llm_usages constraints before retrying."
      end

      if SOURCE_USAGE_CHECK_NAMES.include?(check.name)
        remove_check_constraint :ruby_llm_usages, name: check.name
        values = USAGE_OPERATIONS.map { |operation| connection.quote(operation) }.join(", ")
        add_check_constraint :ruby_llm_usages, "operation::text IN (#{values})"
      end
    end

    # Keep this matcher local to the migration. PostgreSQL deparses IN as
    # = ANY, with varchar/text casts that vary across dump versions.
    def stock_usage_operations(expression)
      value = /'[a-z_]+'(?:::text|::character varying(?:::text)?)?|\('[a-z_]+'::character varying\)::text/
      list = expression.squish[/
        \A (?:operation|\(operation\)) (?:::text)? \s* = \s* ANY \s* \(
        ARRAY\[ ((?:#{value})(?:,\s*(?:#{value}))*) \] (?:::text\[\])? \) \z
      /x, 1]
      list.scan(/'([a-z_]+)'/).flatten.sort if list
    end
end
