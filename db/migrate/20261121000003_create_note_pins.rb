class CreateNotePins < ActiveRecord::Migration[8.1]
  def change
    create_table :note_pins do |t|
      t.bigint :account_id, null: false
      t.bigint :note_id, null: false
      t.timestamps

      t.index :note_id, unique: true
    end
  end
end
