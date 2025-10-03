module Chat::SimilaritySearch
  extend ActiveSupport::Concern

  def similarity_search(question)
    chunks = account.chunks.search_by_similarity(question, limit: retrieval_fetch_k)
    augmented_context = ENV.fetch("AUGMENTED_CONTEXT", "false") == "true"
    chunks.select { |chunk| context_relevance(augmented_context ? chunk.augmented_context : chunk.context, question:) }
  end
end
