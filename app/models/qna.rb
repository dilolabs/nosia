class Qna < ApplicationRecord
  include Chunkable

  belongs_to :account

  def context
    [ question, answer ].join("\n")
  end
end
