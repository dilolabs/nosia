module Chunk::Vectorizable
  extend ActiveSupport::Concern

  included do
    before_save :generate_embedding, if: :content_changed?
    after_save :record_embedding_usage_if_needed
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
      @pending_embedding_result = embedding_result
    rescue RubyLLM::Error => e
      Rails.logger.error "Error generating embedding for Chunk #{id}: #{e.message}"
      throw :abort
    end
  end

  def generate_embedding!
    generate_embedding
    save! if embedding_changed?
  end

  private

  def record_embedding_usage_if_needed
    return unless @pending_embedding_result&.input_tokens&.positive?
    record_embedding_usage(@pending_embedding_result, chat: nil)
    @pending_embedding_result = nil
  end

  # Record the embedding's input_tokens as a TokenUsage. Indexing embeddings have
  # no chat context (chat: nil). No-op when input_tokens is absent/zero.
  def record_embedding_usage(embedding_result, chat:)
    return unless embedding_result&.input_tokens&.positive?

    TokenUsage.create!(
      account_id: account_id,
      chat_id: chat&.id,
      kind: :embedding,
      source_id: id,
      source_type: self.class.name,
      model_id: ENV["EMBEDDING_MODEL"],
      input_tokens: embedding_result.input_tokens,
      output_tokens: 0
    )
  end
end
