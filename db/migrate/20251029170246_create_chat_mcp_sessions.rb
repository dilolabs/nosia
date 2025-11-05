class CreateChatMcpSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_mcp_sessions do |t|
      t.references :chat, null: false, foreign_key: true
      t.references :mcp_server, null: false, foreign_key: true
      t.boolean :enabled, default: true
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :chat_mcp_sessions, [:chat_id, :mcp_server_id], unique: true
  end
end
