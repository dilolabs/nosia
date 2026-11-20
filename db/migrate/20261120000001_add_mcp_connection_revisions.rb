class AddMcpConnectionRevisions < ActiveRecord::Migration[8.1]
  def change
    change_table :mcp_servers, bulk: true do |t|
      t.bigint :connection_revision, default: 0, null: false
      t.bigint :connection_test_attempt, default: 0, null: false
    end
  end
end
