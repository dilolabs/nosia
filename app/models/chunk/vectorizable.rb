module Chunk::Vectorizable
  extend ActiveSupport::Concern

  included do
    before_save :generate_embedding, if: :content_changed?
  end

  def generate_embedding
    return if content.blank?
    Rails.logger.info "Generating embedding for Chunk #{id}..."
    begin
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV["EMBEDDING_BASE_URL"] || ENV["AI_BASE_URL"]
        config.openai_api_key = ENV["AI_API_KEY"]
      end
      embedding_result = RubyLLM.embed(content, context:, model: ENV["EMBEDDING_MODEL"], dimensions: ENV["EMBEDDING_DIMENSIONS"].to_i, provider: :openai, assume_model_exists: true)
      self.embedding = embedding_result.vectors
    rescue RubyLLM::Error => e
      Rails.logger.error "Error generating embedding for Chunk #{id}: #{e.message}"
      throw :abort
    end
  end

  def generate_embedding!
    generate_embedding
    save! if embedding_changed?
  end
end
