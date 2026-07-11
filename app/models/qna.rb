class Qna < ApplicationRecord
  include Chunkable
  include Indexable
  include Sourceable
  include HtmlToMarkdownFormattable

  html_to_markdown_attribute :answer

  belongs_to :account

  scope :search, ->(query) {
    query.present? ? where("question ILIKE :q OR answer ILIKE :q", q: "%#{query}%") : all
  }

  def context
    [ question, answer ].join("\n")
  end

  def source_type_label
    "Q&A"
  end

  def display_title
    title.presence || question.to_s.strip.first(80)
  end

  def source_subtitle
    "A: #{answer.to_s.strip.first(60)}"
  end
end
