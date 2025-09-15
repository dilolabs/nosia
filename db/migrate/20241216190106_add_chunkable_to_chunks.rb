class AddChunkableToChunks < ActiveRecord::Migration[8.0]
  def up
    add_column :chunks, :chunkable_type, :string
    Chunk.update_all(chunkable_type: "Document")
    remove_index :chunks, :document_id
    rename_column :chunks, :document_id, :chunkable_id
    add_index :chunks, [ :chunkable_type, :chunkable_id ]

    add_reference :chunks, :account, null: true, foreign_key: true

    account = Account.order(:created_at).first
    Chunk.update_all(account_id: account.id) if account.present?

    change_column_null :chunks, :account_id, false
  end

  def down
    remove_reference :chunks, :account

    remove_index :chunks, [ :chunkable_type, :chunkable_id ]
    rename_column :chunks, :chunkable_id, :document_id
    add_index :chunks, :document_id
    remove_column :chunks, :chunkable_type
  end
end
