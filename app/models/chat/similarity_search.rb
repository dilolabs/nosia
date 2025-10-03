module Chat::SimilaritySearch
  extend ActiveSupport::Concern

  def similarity_search(question)
    chunks = account.chunks.search_by_similarity(question, limit: retrieval_fetch_k)
    chunks.select { |chunk| context_relevance(chunk.context, question:) }
  end
end
