class Qna < ApplicationRecord
  include Chunkable
  include Indexable

  belongs_to :account

  def context
    [ question, answer ].join("\n")
  end
end
