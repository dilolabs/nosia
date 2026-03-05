class CreatePrompts < ActiveRecord::Migration[8.0]
  def up
    create_table :prompts do |t|
      t.belongs_to :account, null: true, foreign_key: true
      t.belongs_to :user, null: true, foreign_key: true
      t.string :name
      t.text :content

      t.timestamps
    end

    Account.find_each do |account|
      account.create_default_system_prompt!
      account.users.find_each do |user|
        user.create_default_system_prompt!(account:)
      end
    end
    User.find_each(&:create_default_system_prompt!)
  end

  def down
    drop_table :prompts
  end
end
