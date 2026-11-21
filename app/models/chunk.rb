class Chunk < ApplicationRecord
  include Enrichable, NoteVisibility, Searchable, Vectorizable

  belongs_to :account
  belongs_to :chunkable, polymorphic: true

  # Single source of truth for the embedding width the deployment embeds at;
  # the chunks.embedding column is migrated to match (see
  # AlignChunksEmbeddingDimensions). Keep in sync with install.sh's default.
  def self.embedding_dimensions
    ENV.fetch("EMBEDDING_DIMENSIONS", "768").to_i
  end

  def augmented_context
    previous = previous_chunks(2)
    following = next_chunks(2)
    (previous + [ self ] + following).map(&:context).join("\n")
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

  def note_chunk?
    chunkable_type == "Note"
  end

  def title
    case chunkable_type
    when "Document"
      chunkable.title
    when "Website"
      chunkable.title
    when "Note"
      chunkable&.display_title
    else
      context.first(42)
    end
  end
end
