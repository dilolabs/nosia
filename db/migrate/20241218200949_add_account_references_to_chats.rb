class AddAccountReferencesToChats < ActiveRecord::Migration[8.0]
  def up
    add_reference :chats, :account, null: true, foreign_key: true

<<<<<<< HEAD
    account = Account.find_by(name: "First account")
    Chat.update_all(account_id: account.id)
=======
    account = Account.order(:created_at).first
    Chat.update_all(account_id: account.id) if account.present?
>>>>>>> main

    change_column_null :chats, :account_id, false
  end

  def down
    remove_reference :chats, :account
  end
end
