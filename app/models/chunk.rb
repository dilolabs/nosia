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

  def title
    case chunkable_type
    when "Document"
      chunkable.title
    when "Website"
      chunkable.title
    else
      context.first(42)
    end
  end
end
