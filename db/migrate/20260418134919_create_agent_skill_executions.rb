class CreateAgentSkillExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_skill_executions do |t|
      t.references :agent_skill, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true
      t.references :message, null: true, foreign_key: true
      t.string :execution_mode, null: false
      t.string :status, null: false
      t.jsonb :trigger_context, default: {}
      t.jsonb :input, default: {}
      t.jsonb :output, default: {}
      t.text :error_message
      t.integer :duration_ms
      t.timestamps
    end

    add_index :agent_skill_executions, [:chat_id, :created_at]
    add_index :agent_skill_executions, [:agent_skill_id, :created_at]
    add_index :agent_skill_executions, [:status]
    add_index :agent_skill_executions, [:created_at]
  end
end
