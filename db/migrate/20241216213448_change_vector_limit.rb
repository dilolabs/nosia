class ChangeVectorLimit < ActiveRecord::Migration[8.0]
  def up
    Chunk.update_all(embedding: nil)
    change_column :chunks, :embedding, :vector, limit: ENV.fetch("EMBEDDING_DIMENSIONS", 768).to_i
  end

  def down
    Chunk.update_all(embedding: nil)
    change_column :chunks, :embedding, :vector, limit: 768
  end
end
