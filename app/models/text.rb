class Text < ApplicationRecord
  include Chunkable
  include Indexable
  include Sourceable
  include HtmlToMarkdownFormattable

  html_to_markdown_attribute :data

  belongs_to :account

  scope :search, ->(query) {
    query.present? ? where("data ILIKE :q OR title ILIKE :q", q: "%#{query}%") : all
  }

  def context
    data
  end

  def display_title
    title.presence || data.to_s.strip.first(42)
  end

  def source_subtitle
    "Pasted text · #{data.to_s.split.size} words"
  end
end
