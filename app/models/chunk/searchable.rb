module Chunk::Searchable
  extend ActiveSupport::Concern

  included do
    has_neighbors :embedding

    scope :search_by_similarity, ->(query_text, limit: ENV["RETRIEVAL_FETCH_K"].to_i || 5, chat: nil) {
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV["EMBEDDING_BASE_URL"] || ENV["AI_BASE_URL"]
        config.openai_api_key = ENV["AI_API_KEY"]
      end
      embedding_result = RubyLLM.embed(query_text, context:, model: ENV["EMBEDDING_MODEL"], dimensions: ENV["EMBEDDING_DIMENSIONS"].to_i, provider: :openai, assume_model_exists: true)
      Chunk::Searchable.record_query_embedding_usage(embedding_result, chat:)
      nearest_neighbors(:embedding, embedding_result.vectors, distance: :cosine).limit(limit)
    }
  end

  # Records the query-embedding TokenUsage for a chat-scoped similarity search.
  # The chat is the source (the scope runs before the triggering user message is
  # reliably persisted in all flows); chat_id carries the aggregation axis.
  # No-op when there is no chat or no input_tokens.
  def self.record_query_embedding_usage(embedding_result, chat:)
    return unless chat && embedding_result&.input_tokens&.positive?

    TokenUsage.create!(
      account_id: chat.account_id,
      chat_id: chat.id,
      kind: :embedding,
      source: chat,
      model_id: ENV["EMBEDDING_MODEL"],
      input_tokens: embedding_result.input_tokens,
      output_tokens: 0
    )
  end
end