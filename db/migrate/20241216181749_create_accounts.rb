class CreateAccounts < ActiveRecord::Migration[8.0]
  def up
    create_table :accounts do |t|
      t.string :name
      t.belongs_to :owner, null: false, foreign_key: { to_table: :users }
      t.string :uid

      t.timestamps
    end

    owner = User.order(:created_at).first
    Account.find_or_create_by(name: "First account", owner:)
  end

  def down
    drop_table :accounts
  end
end
