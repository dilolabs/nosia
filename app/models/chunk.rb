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

  # Builds the positional window on an already scoped, current Note relation.
  # @param scope [ActiveRecord::Relation<Chunk>] The same Note and generation as this row.
  # @param augmented [Boolean] Whether to include neighboring positions.
  # @return [ActiveRecord::Relation<Chunk>] Fresh passages in order, including the center if still visible.
  def note_passages(scope, augmented:)
    position = metadata.fetch("position")
    if augmented
      scope.where("chunks.metadata -> 'position' BETWEEN CAST(? AS jsonb) AND CAST(? AS jsonb)",
        (position - 2).to_s, (position + 2).to_s)
        .order(Arel.sql("chunks.metadata -> 'position' ASC, chunks.id ASC"))
    else
      scope.where(id:)
    end
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
