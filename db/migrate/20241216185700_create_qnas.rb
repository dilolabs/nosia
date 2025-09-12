class CreateQnas < ActiveRecord::Migration[8.0]
  def change
    create_table :qnas do |t|
      t.references :account, null: false, foreign_key: true
      t.text :question
      t.text :answer

      t.timestamps
    end
  end
end
