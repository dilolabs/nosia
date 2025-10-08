module Chat::SimilaritySearch
  extend ActiveSupport::Concern

  def similarity_search(question)
    chunks = account.chunks.search_by_similarity(question, limit: retrieval_fetch_k)
    augmented_context = ActiveModel::Type::Boolean.new.cast(ENV["AUGMENTED_CONTEXT"])
    chunks.select { |chunk| context_relevance(augmented_context ? chunk.augmented_context : chunk.context, question:) }
  end
end
