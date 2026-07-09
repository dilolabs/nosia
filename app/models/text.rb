class Text < ApplicationRecord
  include Chunkable
  include Indexable
  include HtmlToMarkdownFormattable

  html_to_markdown_attribute :data

  belongs_to :account

  def context
    data
  end
end
