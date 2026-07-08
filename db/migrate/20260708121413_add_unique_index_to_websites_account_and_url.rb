class AddUniqueIndexToWebsitesAccountAndUrl < ActiveRecord::Migration[8.0]
  def up
    # Dedupe any pre-existing (account_id, url) duplicates before adding the
    # unique index, keeping the most recent row per pair. Delete the orphaned
    # chunks of the discarded rows too — a raw SQL DELETE bypasses Rails'
    # dependent: :destroy on chunks, which would leave them polluting vector
    # retrieval.
    execute <<~SQL.squish
      WITH dups AS (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id, url ORDER BY created_at DESC, id DESC) AS rn
          FROM websites
        ) ranked WHERE rn > 1
      )
      DELETE FROM chunks WHERE chunkable_type = 'Website' AND chunkable_id IN (SELECT id FROM dups)
    SQL
    execute <<~SQL.squish
      WITH dups AS (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id, url ORDER BY created_at DESC, id DESC) AS rn
          FROM websites
        ) ranked WHERE rn > 1
      )
      DELETE FROM websites WHERE id IN (SELECT id FROM dups)
    SQL
    add_index :websites, [:account_id, :url], unique: true
  end

  def down
    remove_index :websites, column: [:account_id, :url]
  end
end
