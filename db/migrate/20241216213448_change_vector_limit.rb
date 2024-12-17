class ChangeVectorLimit < ActiveRecord::Migration[8.0]
  def up
    unless ENV.fetch("EMBEDDING_DIMENSIONS", 768).to_i.eql?(768)
      Chunk.update_all(embedding: nil)
      change_column :chunks, :embedding, :vector, limit: ENV.fetch("EMBEDDING_DIMENSIONS", 768).to_i
    end
  end

  def down
    unless ENV.fetch("EMBEDDING_DIMENSIONS", 768).to_i.eql?(768)
      Chunk.update_all(embedding: nil)
      change_column :chunks, :embedding, :vector, limit: 768
    end
  end
end
