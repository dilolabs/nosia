# Uniform interface every knowledge-base source (Document, Text, Qna, Website)
# exposes so the unified Sources list can render any of them with one partial.
# Including models MUST define #source_subtitle and a `search` scope; they MAY
# override #display_title. Requires Indexable (index_status) to be included too.
module Sourceable
  extend ActiveSupport::Concern

  included do
    after_create_commit :broadcast_source_created
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

  # A brand-new source is prepended to the list for viewers whose current
  # filter it matches (see #created_list_scopes), then updates in place via
  # #broadcast_source_status_change once indexing finishes. Drag-and-drop
  # uploads rely on this to appear without a reload.
  def broadcast_source_created
    created_list_scopes.each do |scope|
      broadcast_prepend_to [ account, "sources", "list:#{scope}" ],
        target: "sources_list",
        partial: "sources/source",
        locals: { row: SourceRow.new(self, chunks_count: chunks.count) }
    end
    broadcast_source_counts
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
    # The (type:status) filter combinations a newly-created source belongs to,
    # matching the stream the index subscribes to (list:<type>:<status>). Only
    # the always-visible type/status views are covered; searched views opt out
    # of live prepends (they don't subscribe) since the row may not match the query.
    def created_list_scopes
      [ "all:all", "all:#{index_status}", "#{source_type_key}:all", "#{source_type_key}:#{index_status}" ]
    end

    # Each sidebar count is its own live target (dom id "source_count_<key>"),
    # so a status change refreshes every badge in place without re-rendering the
    # nav links -- which keeps each viewer's active-filter highlight intact.
    def broadcast_source_counts
      count_badges(SourceRow.counts_for(account)).each do |key, value, variant|
        broadcast_replace_to [ account, "sources" ],
          target: "source_count_#{key}",
          partial: "sources/counts",
          locals: { key:, value:, variant: }
      end
    end

    def count_badges(counts)
      badges = [ [ "all", counts[:total], :neutral ] ]
      SourceRow::TYPES.each { |type| badges << [ "type-#{type}", counts[:by_type][type], :neutral ] }
      badges << [ "status-failed", counts[:by_status]["failed"], :error ]
      badges << [ "status-pending", counts[:by_status]["pending"], :pending ]
      badges
    end
end
