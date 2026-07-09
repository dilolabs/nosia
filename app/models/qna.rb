class Qna < ApplicationRecord
  include Chunkable
  include Indexable
  include HtmlToMarkdownFormattable

  html_to_markdown_attribute :answer

  belongs_to :account

  def context
    [ question, answer ].join("\n")
  end
end
