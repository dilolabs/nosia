# Uniform interface every knowledge-base source (Document, Text, Qna, Website)
# exposes so the unified Sources list can render any of them with one partial.
# Including models MUST define #source_subtitle and a `search` scope; they MAY
# override #display_title. Requires Indexable (index_status) to be included too.
module Sourceable
  extend ActiveSupport::Concern

  included do
    after_update_commit :broadcast_source_status_change, if: :saved_change_to_index_status?
    after_destroy_commit :broadcast_source_removed
  end

  # Human label + url-safe key, derived from the class name by default and
  # overridable per model (Qna -> "Q&A").
  def source_type_label
    model_name.human
  end

  def source_type_key
    model_name.element # "document", "text", "qna", "website"
  end

  # Best available one-line title. Override per model; this fallback covers the
  # common "title column is present" case and degrades to a blank string.
  def display_title
    title.presence || ""
  end

  # One-line contextual detail shown under the title. MUST be implemented by
  # each including model (file size, crawl progress, answer preview, word count).
  def source_subtitle
    raise NotImplementedError, "#{self.class} must implement #source_subtitle"
  end

  # A short human reason a source failed, or nil. Overridable per model.
  def failure_reason
    nil
  end

  # Indexable#mark_indexing_failed! uses update_columns, which skips the
  # after_update_commit callback above -- so broadcast the change explicitly.
  def mark_indexing_failed!
    super
    broadcast_source_status_change
  end

  def broadcast_source_status_change
    broadcast_replace_to [ account, "sources" ],
      target: ActionView::RecordIdentifier.dom_id(self, :source_row),
      partial: "sources/source",
      locals: { row: SourceRow.new(self, chunks_count: chunks.count) }
    broadcast_source_counts
  end

  def broadcast_source_removed
    broadcast_remove_to [ account, "sources" ],
      target: ActionView::RecordIdentifier.dom_id(self, :source_row)
    broadcast_source_counts
  end

  private

  def broadcast_source_counts
    broadcast_replace_to [ account, "sources" ],
      target: "sources_counts",
      partial: "sources/counts",
      locals: { counts: SourceRow.counts_for(account) }
  end
end
