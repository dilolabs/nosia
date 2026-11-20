class AddMcpOauthAuthorizations < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_servers, :auth_mode, :string, default: "static", null: false

    create_table :mcp_authorizations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :mcp_server, null: false, foreign_key: true, index: false
      t.references :account_user, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.datetime :reconnect_required_at
      t.timestamps

      t.index [ :mcp_server_id, :account_user_id ], unique: true
    end
  end
end
