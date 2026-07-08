module Indexable
  extend ActiveSupport::Concern

  included do
    enum :index_status, { pending: 0, indexed: 10, failed: 20 }
  end

  def mark_indexed!
    update!(index_status: :indexed, indexed_at: Time.current)
  end

  def mark_indexing_failed!
    update!(index_status: :failed)
  end
end
