# Shares the saved Note visibility boundary across ranking, excerpts and citations.
module Chunk::NoteVisibility
  extend ActiveSupport::Concern

  included do
    scope :without_notes, -> { where.not(chunkable_type: "Note").or(where(chunkable_type: nil)) }
  end

  class_methods do
    # @param account_id [Integer] The authorized account.
    # @param include_notes [Boolean] Whether the caller grants access to Notes.
    # @return [ActiveRecord::Relation<Chunk>] Existing Sources and, if authorized, current Notes.
    def with_visible_notes(account_id:, include_notes:)
      sources = without_notes.where(account_id:)
      include_notes ? sources.or(current_note_chunks(account_id)) : sources
    end

    # @param account_id [Integer] The authorized account.
    # @return [ActiveRecord::Relation<Chunk>] Usable rows of the current published Note generations.
    def current_note_chunks(account_id)
      published = Note.indexed_in(account_id)
        .where("notes.id = chunks.chunkable_id")
        .where("chunks.metadata -> 'note_generation' = to_jsonb(notes.indexed_generation)")

      where(account_id:, chunkable_type: "Note").where(published.arel.exists)
        .where.not(embedding: nil)
        .where.not(content: [ nil, "" ])
        .where("vector_dims(chunks.embedding) = ? AND vector_norm(chunks.embedding) > 0", Chunk.embedding_dimensions)
        .where("jsonb_typeof(chunks.metadata -> 'position') = 'number' AND chunks.metadata ->> 'position' ~ '^[1-9][0-9]*$'")
    end
  end
end
