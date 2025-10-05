class AddMetadataToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :metadata, :jsonb, default: {}
  end
end
