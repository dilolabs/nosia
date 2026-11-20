# PostgreSQL expansion of RubyLLM v2.2.3's upgrade_ruby_llm_to_2_2.rb.tt.
# Copyright (c) 2025 Carmine Paolino (MIT; see support/ruby_llm_v2_legacy_content_sql.rb).
class UpgradeRubyLlmTo22 < ActiveRecord::Migration[8.1]
  SOURCE_USAGE_OPERATIONS = %w[chat embedding moderation image speech transcription ocr rerank judgment video research].freeze
  USAGE_OPERATIONS = (SOURCE_USAGE_OPERATIONS + %w[code_execution]).freeze

  # Rails hashes the original SQL, so loading a deparsed dump can change the name.
  # Each pair is the name from the migration and the name from reloading its dump.
  SOURCE_USAGE_CHECK_NAMES = %w[chk_rails_68fa7685c9 chk_rails_b21c7a9cfb].freeze
  USAGE_CHECK_NAMES = %w[chk_rails_6a1e6be1a0 chk_rails_5b032552ee].freeze

  def up
    unless column_exists?(:ruby_llm_tool_calls, :provider_call_id)
      if column_exists?(:ruby_llm_tool_calls, :provider_id)
        rename_column :ruby_llm_tool_calls, :provider_id, :provider_call_id
      else
        add_column :ruby_llm_tool_calls, :provider_call_id, :string
      end
    end

    add_column :ruby_llm_tool_calls, :namespace, :string unless column_exists?(:ruby_llm_tool_calls, :namespace)

    unless column_exists?(:chats, :claim_token)
      add_column :chats, :claim_token, :string
    end

    unless column_exists?(:chats, :claimed_until)
      add_column :chats, :claimed_until, :datetime
    end

    unless index_exists?(:chats, :claimed_until)
      add_index :chats, :claimed_until, where: "claim_token IS NOT NULL"
    end

    unless column_exists?(:ruby_llm_tool_calls, :claimed_until)
      add_column :ruby_llm_tool_calls, :claimed_until, :datetime
    end

    unless column_exists?(:messages, :phase)
      add_column :messages, :phase, :string
    end

    unless column_exists?(:messages, :continuation)
      add_column :messages, :continuation, :text
    end

    %i[workflow_id workflow_name workflow_step_id workflow_step_name].each do |column|
      add_column :ruby_llm_usages, column, :string unless column_exists?(:ruby_llm_usages, column)
    end
    add_index :ruby_llm_usages, :workflow_id unless index_exists?(:ruby_llm_usages, :workflow_id)

    add_column :ruby_llm_usages, :characters, :integer unless column_exists?(:ruby_llm_usages, :characters)
    unless column_exists?(:ruby_llm_usages, :audio_seconds)
      add_column :ruby_llm_usages, :audio_seconds, :decimal, precision: 16, scale: 6
    end
    add_column :ruby_llm_usages, :search_units, :integer unless column_exists?(:ruby_llm_usages, :search_units)
    %i[characters_cost audio_seconds_cost search_units_cost].each do |column|
      unless column_exists?(:ruby_llm_usages, column)
        add_column :ruby_llm_usages, column, :decimal, precision: 16, scale: 10
      end
    end

    unless table_exists?(:ruby_llm_queued_messages)
      create_table :ruby_llm_queued_messages, id: :bigint do |t|
        t.references :chat, polymorphic: true, null: false, type: :bigint, index: false
        t.references :sender, polymorphic: true, type: :bigint, index: false
        t.text :content
        t.boolean :steer, default: true, null: false
        t.timestamps

        t.index [ :chat_type, :chat_id ]
        t.index [ :sender_type, :sender_id ]
      end
    end

    unless table_exists?(:ruby_llm_chat_files)
      create_table :ruby_llm_chat_files, id: :bigint do |t|
        t.references :chat, polymorphic: true, null: false, type: :bigint, index: false
        t.references :owner, polymorphic: true, type: :bigint, index: false
        t.string :path, null: false
        t.string :content_type
        t.bigint :byte_size
        t.string :digest
        t.text :text
        t.string :read_digest
        t.timestamps

        t.index [ :chat_type, :chat_id, :path ]
        t.index [ :owner_type, :owner_id ]
      end
    end
    unless column_exists?(:ruby_llm_chat_files, :read_digest)
      add_column :ruby_llm_chat_files, :read_digest, :string
    end

    upgrade_usage_operations
    # A check of the application's may still refuse the row.
    warn_about_code_execution_usage unless usage_accepts_code_execution?
  end

  def down
    # The upstream rollback would drop provider_call_id even if it held IDs
    # carried over by the provider_id rename.
    raise ActiveRecord::IrreversibleMigration, "Restore a pre-upgrade database backup to roll back RubyLLM 2.2"
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
        raise "Expected one validated stock RubyLLM 2.1 or 2.2 usage operation check, found #{matches.size} matching checks. Review ruby_llm_usages constraints before retrying."
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

    # Asks the database, since each one prints a check differently: a check
    # refusing the row leaves code runs unmetered, with only a warning at run time.
    def usage_accepts_code_execution?
      connection.transaction(requires_new: true) do
        execute <<~SQL.squish
          INSERT INTO ruby_llm_usages (operation, provider, model, status, created_at, updated_at)
          VALUES ('code_execution', 'sandbox', 'upgrade check', 'succeeded', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
        raise ActiveRecord::Rollback
      end
      true
    rescue ActiveRecord::StatementInvalid
      false
    end

    def warn_about_code_execution_usage
      checks = check_constraints(:ruby_llm_usages).select { |check| check.expression.match?(/\boperation\b/) }
        .map(&:name).join(", ")
      say "RubyLLM: ruby_llm_usages refuses 'code_execution' rows, so code runs will go unmetered with only a " \
          "warning in the log. Check these constraints, or any NOT NULL column you added: #{checks}. Allow the " \
          'value in a new migration: see "Code Runs Write Usage Rows" in the upgrading guide.'
    end
end
