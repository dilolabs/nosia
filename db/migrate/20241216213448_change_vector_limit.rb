class ChangeVectorLimit < ActiveRecord::Migration[8.0]
  def up
    Chunk.update_all(embedding: nil)
    change_column :chunks, :embedding, :vector, limit: ENV.fetch("EMBEDDING_DIMENSIONS", 384).to_i
  end

  def down
    Chunk.update_all(embedding: nil)
    change_column :chunks, :embedding, :vector, limit: 384
  end
end
