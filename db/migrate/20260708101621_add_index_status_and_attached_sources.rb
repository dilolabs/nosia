class AddIndexStatusAndAttachedSources < ActiveRecord::Migration[8.0]
  def up
    [:websites, :documents, :texts, :qnas].each do |table|
      add_column table, :index_status, :integer, default: 0, null: false
      add_column table, :indexed_at,   :datetime
    end
    add_column :messages, :attached_website_ids,  :string, array: true, default: []
    add_column :messages, :attached_document_ids, :string, array: true, default: []

    # Backfill: sources that already have chunks are indexed.
    [:websites, :documents, :texts, :qnas].each do |table|
      execute <<~SQL.squish
        UPDATE #{table} SET index_status = 10, indexed_at = updated_at
        WHERE id IN (SELECT chunkable_id FROM chunks WHERE chunkable_type = '#{table.to_s.classify}')
      SQL
    end
  end

  def down
    [:websites, :documents, :texts, :qnas].each do |table|
      remove_column table, :index_status
      remove_column table, :indexed_at
    end
    remove_column :messages, :attached_website_ids
    remove_column :messages, :attached_document_ids
  end
end