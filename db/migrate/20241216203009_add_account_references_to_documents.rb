class AddAccountReferencesToDocuments < ActiveRecord::Migration[8.0]
  def up
    add_reference :documents, :account, null: true, foreign_key: true

    account = Account.find_by(name: "First account")
    Document.update_all(account_id: account.id)

    change_column_null :documents, :account_id, false
  end

  def down
    remove_reference :documents, :account
  end
end
