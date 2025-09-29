module Chunk::Vectorizable
  extend ActiveSupport::Concern

  included do
    has_neighbors :embedding

    before_save :generate_embedding, if: :content_changed?

    scope :search_by_similarity, ->(query_text, limit: ENV['RETRIEVAL_FETCH_K'] || 5) {
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV['OPENAI_EMBEDDING_API_BASE'] || ENV['OPENAI_API_BASE']
        config.openai_api_key = ENV['OPENAI_API_KEY']
      end
      query_embedding = RubyLLM.embed(query_text, context:).vectors
      nearest_neighbors(:embedding, query_embedding, distance: :cosine).limit(limit)
    }
  end

  private

  def generate_embedding
    return if content.blank?
    Rails.logger.info "Generating embedding for Chunk #{id}..."
    begin
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV['OPENAI_EMBEDDING_API_BASE'] || ENV['OPENAI_API_BASE']
        config.openai_api_key = ENV['OPENAI_API_KEY']
      end
      embedding_result = RubyLLM.embed(content, context:) # Uses default embedding model
      self.embedding = embedding_result.vectors
    rescue RubyLLM::Error => e
      errors.add(:base, "Failed to generate embedding: #{e.message}")
      # Prevent saving if embedding fails (optional, depending on requirements)
      throw :abort
    end
  end
end
