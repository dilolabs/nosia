module Chat::SimilaritySearch
  extend ActiveSupport::Concern

  def similarity_search(question)
    broadcast_thinking_phase("searching", "Searching your documents...")
    chunks = account.chunks.search_by_similarity(question, limit: retrieval_fetch_k, chat: self).to_a
    broadcast_thinking_phase("retrieving", "Retrieving relevant context...")
    augmented_context = ActiveModel::Type::Boolean.new.cast(ENV["AUGMENTED_CONTEXT"])
    # A polymorphic source may be deleted before retrieval finishes, leaving an orphaned chunk.
    chunks.select do |chunk|
      if chunk.chunkable
        context_relevance(augmented_context ? chunk.augmented_context : chunk.context, question: question)
      end
    end
  end
end
