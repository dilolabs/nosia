class Chunk < ApplicationRecord
  include Enrichable, Searchable, Vectorizable

  belongs_to :account
  belongs_to :chunkable, polymorphic: true

  def augmented_context
    previous = previous_chunks(2)
    following = next_chunks(2)
    (previous + [self] + following).map(&:context).join("\n")
  end

  def context
    content
  end

  def next_chunks(limit = 2)
    return [] unless metadata.dig("position").is_a?(Integer)
    chunkable.chunks.where("metadata ->> 'position' > ?", metadata["position"].to_s)
      .order(Arel.sql("(metadata ->> 'position')::int ASC"))
      .limit(limit)
  end

  def previous_chunks(limit = 2)
    return [] unless metadata.dig("position").is_a?(Integer)
    chunkable.chunks.where("metadata ->> 'position' < ?", metadata["position"].to_s)
      .order(Arel.sql("(metadata ->> 'position')::int ASC"))
      .limit(limit)
  end

  def source
    ""
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
