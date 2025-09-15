class AddAccountReferencesToApiTokens < ActiveRecord::Migration[8.0]
  def up
    add_reference :api_tokens, :account, null: true, foreign_key: true

    account = Account.order(:created_at).first
    ApiToken.update_all(account_id: account.id) if account.present?

    change_column_null :api_tokens, :account_id, false
  end

  def down
    remove_reference :api_tokens, :account
  end
end
