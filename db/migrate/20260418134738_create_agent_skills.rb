class CreateAgentSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_skills do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :execution_mode, null: false, default: "llm"
      t.string :trigger_mode, null: false, default: "explicit"
      t.jsonb :metadata, default: {}
      t.boolean :requires_rag_context, default: false
      t.boolean :enabled, default: true
      t.integer :priority, default: 0
      t.timestamps
    end

    add_index :agent_skills, [ :account_id, :name ], unique: true
    add_index :agent_skills, [ :account_id, :enabled ]
    add_index :agent_skills, [ :account_id, :execution_mode ]
    add_index :agent_skills, [ :account_id, :trigger_mode ]
    add_index :agent_skills, [ :name ]
  end
end
