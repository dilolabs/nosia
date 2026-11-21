class CreateNoteFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :note_folders do |t|
      t.bigint :account_id, null: false
      t.bigint :parent_id
      t.string :name, null: false
      t.string :system_key
      t.timestamps

      t.index [ :account_id, :parent_id ]
      t.index [ :account_id, :system_key ], unique: true, where: "system_key IS NOT NULL"
    end

    create_table :note_folder_trashings do |t|
      t.bigint :account_id, null: false
      t.bigint :note_folder_id, null: false
      t.timestamps

      t.index :note_folder_id, unique: true
    end
  end
end
