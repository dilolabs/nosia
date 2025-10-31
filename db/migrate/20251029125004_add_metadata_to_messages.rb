class AddMetadataToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :metadata, :jsonb, default: {}, null: false
    add_index :messages, :metadata, using: :gin
  end
end
