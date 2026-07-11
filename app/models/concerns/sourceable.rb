# Uniform interface every knowledge-base source (Document, Text, Qna, Website)
# exposes so the unified Sources list can render any of them with one partial.
# Including models MUST define #source_subtitle and a `search` scope; they MAY
# override #display_title. Requires Indexable (index_status) to be included too.
module Sourceable
  extend ActiveSupport::Concern

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
end
