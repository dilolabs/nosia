class CreatePrompts < ActiveRecord::Migration[8.0]
  def up
    create_table :prompts do |t|
      t.belongs_to :account, null: false, foreign_key: true
      t.belongs_to :user, null: true, foreign_key: true
      t.string :name
      t.text :content

      t.timestamps
    end

    Account.find_each do |account|
      Prompt.create!(
        account:,
        user: nil,
        name: "system_prompt",
        content: YAML.load_file(Rails.root.join("config", "prompts.yml"))["system_prompt"]
      )
      account.users.find_each do |user|
        Prompt.create!(
          account:,
          user:,
          name: "system_prompt",
          content: YAML.load_file(Rails.root.join("config", "prompts.yml"))["system_prompt"]
        )
      end
    end
  end

  def down
    drop_table :prompts
  end
end
