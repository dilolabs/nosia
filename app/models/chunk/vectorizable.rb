module Chunk::Vectorizable
  extend ActiveSupport::Concern

  included do
    has_neighbors :embedding

    before_save :generate_embedding, if: :content_changed?

    scope :search_by_similarity, ->(query_text, limit: ENV["RETRIEVAL_FETCH_K"] || 5) {
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV["EMBEDDING_BASE_URL"] || ENV["AI_BASE_URL"]
        config.openai_api_key = ENV["AI_API_KEY"]
      end
      query_embedding = RubyLLM.embed(query_text, context:, model: ENV["EMBEDDING_MODEL"], dimensions: ENV["EMBEDDING_DIMENSIONS"].to_i, provider: :openai, assume_model_exists: true).vectors
      nearest_neighbors(:embedding, query_embedding, distance: :cosine).limit(limit)
    }
  end

  private

  def generate_embedding
    return if content.blank?
    Rails.logger.info "Generating embedding for Chunk #{id}..."
    begin
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV["EMBEDDING_BASE_URL"] || ENV["AI_BASE_URL"]
        config.openai_api_key = ENV["AI_API_KEY"]
      end
      embedding_result = RubyLLM.embed(content, context:, model: ENV["EMBEDDING_MODEL"], dimensions: ENV["EMBEDDING_DIMENSIONS"].to_i, provider: :openai, assume_model_exists: true) # Uses default embedding model
      self.embedding = embedding_result.vectors
    rescue RubyLLM::Error => e
      errors.add(:base, "Failed to generate embedding: #{e.message}")
      # Prevent saving if embedding fails (optional, depending on requirements)
      throw :abort
    end
  end
end
