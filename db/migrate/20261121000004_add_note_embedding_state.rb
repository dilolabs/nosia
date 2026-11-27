# Tracks the desired generation and the last atomically published generation.
class AddNoteEmbeddingState < ActiveRecord::Migration[8.1]
  def change
    add_column :notes, :embedding_generation, :bigint, default: 0, null: false
    add_column :notes, :indexed_generation, :bigint
    add_column :notes, :embedding_status, :string, default: "empty", null: false
  end
end
