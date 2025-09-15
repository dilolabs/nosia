class CreateAccountUsers < ActiveRecord::Migration[8.0]
  def up
    create_table :account_users do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    account = Account.order(:created_at).first
    if account.present?
      User.all.each do |user|
        user.account_users.find_or_create_by(account:)
      end
    end
  end

  def down
    drop_table :account_users
  end
end
