class CreateNoteImports < ActiveRecord::Migration[8.1]
  def change
    create_table :note_imports do |t|
      t.bigint :account_id, null: false
      t.bigint :initiator_id, null: false
      t.uuid :confirmation_key, null: false
      t.string :root_name, null: false
      t.string :status, default: "uploading", null: false
      t.jsonb :manifest, null: false
      t.jsonb :ignored_counts, null: false
      t.jsonb :report
      t.bigint :root_note_folder_id
      t.datetime :activity_at, null: false
      t.datetime :sealed_at
      t.datetime :enqueued_at
      t.datetime :claim_expires_at
      t.uuid :claim_token
      t.timestamps

      t.index [ :account_id, :initiator_id, :confirmation_key ], unique: true
      t.index [ :status, :activity_at ]
    end

    create_table :note_import_staged_files do |t|
      t.bigint :account_id, null: false
      t.bigint :note_import_id, null: false
      t.text :path, null: false
      t.text :payload, null: false
      t.string :digest, null: false
      t.timestamps

      t.index [ :note_import_id, :path ], unique: true, name: "index_note_import_files_on_import_and_path"
    end
  end
end
