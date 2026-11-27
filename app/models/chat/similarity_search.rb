module Chat::SimilaritySearch
  extend ActiveSupport::Concern

  # @param question [String] Query to embed for rank and optional relevance checks.
  # @param note_access [Chat::NoteRetrieval, nil] Trusted authority for the current turn.
  # @return [Array<Chunk>] Ranked, relevant evidence candidates.
  def similarity_search(question, note_access: nil)
    broadcast_thinking_phase("searching")
    search_options = { limit: retrieval_fetch_k, chat: self }
    search_options[:note_access] = note_access if note_access
    chunks = account.chunks.search_by_similarity(question, **search_options).to_a
    broadcast_thinking_phase("retrieving")
    augmented_context = ActiveModel::Type::Boolean.new.cast(ENV["AUGMENTED_CONTEXT"])
    eligible_note_ids = note_access&.current_candidate_ids(self, chunks.select { |chunk| chunk.try(:note_chunk?) })
    # A polymorphic source may be deleted before retrieval finishes, leaving an orphaned chunk.
    chunks.select do |chunk|
      if chunk.try(:note_chunk?)
        eligible_note_ids&.include?(chunk.id) &&
          context_relevance(nil, question:) { note_access.current_excerpts(self, [ chunk ], augmented: augmented_context)[chunk.id]&.last }
      elsif chunk.chunkable
        context_relevance(augmented_context ? chunk.augmented_context : chunk.context, question: question)
      end
    end
  end
end
