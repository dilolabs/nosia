class AddMetadataToChunks < ActiveRecord::Migration[8.0]
  def change
    add_column :chunks, :metadata, :jsonb, default: {}
    add_column :chunks, :index, :integer
  end
end
