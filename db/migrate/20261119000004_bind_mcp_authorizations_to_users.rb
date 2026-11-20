class BindMcpAuthorizationsToUsers < ActiveRecord::Migration[8.1]
  def up
    add_reference :mcp_authorizations, :user, foreign_key: true
    execute <<~SQL
      UPDATE mcp_authorizations AS grants
      SET user_id = memberships.user_id
      FROM account_users AS memberships
      WHERE grants.account_user_id = memberships.id
        AND grants.account_id = memberships.account_id
    SQL
    change_column_null :mcp_authorizations, :user_id, false
  end

  def down
    remove_reference :mcp_authorizations, :user, foreign_key: true
  end
end
