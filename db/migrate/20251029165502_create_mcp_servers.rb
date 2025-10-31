class CreateMcpServers < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_servers do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :transport_type, null: false, default: "streamable"
      t.text :endpoint
      t.jsonb :auth_config, default: {}
      t.jsonb :connection_config, default: {}
      t.boolean :enabled, default: true
      t.string :status, default: "disconnected"
      t.datetime :last_connected_at
      t.text :last_error
      t.integer :latency_ms
      t.text :notes
      t.string :tags
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :mcp_servers, [:account_id, :name], unique: true
    add_index :mcp_servers, :status
    add_index :mcp_servers, :enabled
  end
end
