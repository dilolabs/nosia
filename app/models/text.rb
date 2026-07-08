class Text < ApplicationRecord
  include Chunkable
  include Indexable

  belongs_to :account

  def context
    data
  end
end
