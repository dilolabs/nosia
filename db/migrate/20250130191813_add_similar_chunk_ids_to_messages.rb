class AddSimilarChunkIdsToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :similar_chunk_ids, :string, array: true, default: []
  end
end
