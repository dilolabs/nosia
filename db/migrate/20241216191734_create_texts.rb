class CreateTexts < ActiveRecord::Migration[8.0]
  def change
    create_table :texts do |t|
      t.references :account, null: false, foreign_key: true
      t.text :data

      t.timestamps
    end
  end
end
