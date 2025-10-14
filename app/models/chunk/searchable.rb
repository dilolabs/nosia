module Chunk::Searchable
  extend ActiveSupport::Concern

  included do
    has_neighbors :embedding

    scope :search_by_similarity, ->(query_text, limit: ENV["RETRIEVAL_FETCH_K"].to_i || 5) {
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV["EMBEDDING_BASE_URL"] || ENV["AI_BASE_URL"]
        config.openai_api_key = ENV["AI_API_KEY"]
      end
      query_embedding = RubyLLM.embed(query_text, context:, model: ENV["EMBEDDING_MODEL"], dimensions: ENV["EMBEDDING_DIMENSIONS"].to_i, provider: :openai, assume_model_exists: true).vectors
      nearest_neighbors(:embedding, query_embedding, distance: :cosine).limit(limit)
    }
  end
end
