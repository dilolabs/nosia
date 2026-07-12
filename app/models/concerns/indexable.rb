module Indexable
  extend ActiveSupport::Concern

  included do
    enum :index_status, { pending: 0, indexed: 10, failed: 20 }
  end

  def mark_indexed!
    update!(index_status: :indexed, indexed_at: Time.current)
  end

  def mark_pending!
    update!(index_status: :pending, indexed_at: nil)
  end

  def mark_indexing_failed!
    # Bypass validation so a record can be marked failed even when it's
    # otherwise invalid (e.g. a blank-url website hitting crawl_url!'s guard).
    update_columns(index_status: :failed)
  end
end
