class Chunk < ApplicationRecord
  include Vectorizable

  belongs_to :account
  belongs_to :chunkable, polymorphic: true

  def augmented_context
    chunkable.context
  end

  def context
    content
  end
end
