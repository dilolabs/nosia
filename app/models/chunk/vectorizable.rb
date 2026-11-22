module Chunk::Vectorizable
  extend ActiveSupport::Concern

  PRIVATE_EMBEDDING_LOGGER = Logger.new(File::NULL)
  private_constant :PRIVATE_EMBEDDING_LOGGER

  included do
    before_save :generate_embedding, if: :content_changed?
    after_save :record_embedding_usage_if_needed
  end

  class_methods do
    # Requests one text embedding using the configured source embedding provider.
    # @param text [String] Text to embed.
    # @param private_input [Boolean] Suppress provider diagnostics and leave retries to Note indexing.
    # @return [RubyLLM::Embedding] The vector and normalized usage.
    # @raise [RubyLLM::Error] If the provider request fails.
    def embed_text(text, private_input: false)
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV["EMBEDDING_BASE_URL"] || ENV["AI_BASE_URL"]
        config.openai_api_key = ENV["AI_API_KEY"]
        if private_input
          # Only the Note job can recheck generation and visibility before retrying.
          config.max_retries = 0
          # Faraday logs exception messages separately from bodies. The default
          # instrumenter also exposes input and exceptions to log subscribers.
          config.log_bodies = false
          config.logger = PRIVATE_EMBEDDING_LOGGER
          config.instrumenter = nil
          config.redact_error_messages = true
        end
      end
      dimensions = private_input ? embedding_dimensions : ENV["EMBEDDING_DIMENSIONS"].to_i
      owner = Nosia::PrivateEmbeddingUsage::OWNER if private_input
      RubyLLM.embed(text, context:, model: ENV["EMBEDDING_MODEL"], dimensions:, provider: :openai, assume_model_exists: true, owner:)
    end
  end

  # In-memory result supplied only by the Note indexing worker for a chunk save.
  # @param result [RubyLLM::Embedding] The prepared vector and usage.
  attr_writer :prepared_embedding_result

  def generate_embedding
    return if content.blank?

    if chunkable_type == "Note"
      # Never call the provider as a fallback while the worker is publishing.
      throw :abort unless @prepared_embedding_result

      self.embedding = @prepared_embedding_result.vectors
      @pending_embedding_result = @prepared_embedding_result
      @prepared_embedding_result = nil
    else
      generate_source_embedding
    end
  end

  # Rebuilds a legacy source embedding synchronously. Note vectors are only
  # written by the generation worker.
  # @return [Boolean, nil] The save result, or nil when no save is needed.
  def generate_embedding!
    return if chunkable_type == "Note"

    generate_embedding
    save! if embedding_changed?
  end

  private

  def generate_source_embedding
    Rails.logger.info "Generating embedding for Chunk #{id}..."
    begin
      embedding_result = self.class.embed_text(content)
      self.embedding = embedding_result.vectors
      @pending_embedding_result = embedding_result
    rescue RubyLLM::Error => e
      Rails.logger.error "Error generating embedding for Chunk #{id}: #{e.message}"
      throw :abort
    end
  end

  def record_embedding_usage_if_needed
    return unless @pending_embedding_result&.tokens&.input&.positive?
    record_embedding_usage(@pending_embedding_result, chat: nil)
    @pending_embedding_result = nil
  end

  # Record the embedding's normalized input as a TokenUsage. Indexing embeddings
  # have no chat context (chat: nil). No-op when input is absent/zero.
  def record_embedding_usage(embedding_result, chat:)
    return unless embedding_result&.tokens&.input&.positive?

    TokenUsage.create!(
      account_id: account_id,
      chat_id: chat&.id,
      kind: :embedding,
      source_id: id,
      source_type: self.class.name,
      model_id: ENV["EMBEDDING_MODEL"],
      input_tokens: embedding_result.tokens.input,
      output_tokens: 0
    )
  end
end
