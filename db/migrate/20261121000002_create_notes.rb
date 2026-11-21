class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes do |t|
      t.bigint :account_id, null: false
      t.bigint :note_folder_id, null: false
      t.uuid :draft_key, null: false
      t.text :title, default: "", null: false
      t.text :body_html, default: "", null: false
      t.text :body_text, default: "", null: false
      t.integer :content_revision, null: false
      t.datetime :content_updated_at, null: false
      t.timestamps

      t.index [ :account_id, :draft_key ], unique: true
      t.index [ :account_id, :content_updated_at, :id ]
      t.index [ :account_id, :note_folder_id, :content_updated_at, :id ]
    end

    create_table :note_tags do |t|
      t.bigint :account_id, null: false
      t.text :key, null: false
      t.timestamps

      t.index [ :account_id, :key ], unique: true
    end

    create_table :note_taggings do |t|
      t.bigint :account_id, null: false
      t.bigint :note_id, null: false
      t.bigint :note_tag_id, null: false
      t.timestamps

      t.index [ :note_id, :note_tag_id ], unique: true
      t.index [ :note_tag_id, :note_id ]
    end

    create_table :note_trashings do |t|
      t.bigint :account_id, null: false
      t.bigint :note_id, null: false
      t.timestamps

      t.index :note_id, unique: true
    end
  end
end
