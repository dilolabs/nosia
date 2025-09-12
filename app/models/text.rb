class Text < ApplicationRecord
  include Chunkable

  belongs_to :account

  def context
    data
  end
end
