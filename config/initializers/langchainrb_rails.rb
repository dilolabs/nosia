# frozen_string_literal: true

Faraday.default_connection_options = Faraday::ConnectionOptions.new({
  timeout: 240
})

if ENV.fetch("AI_PROVIDER", "ollama").eql?("infomaniak")
  # Infomaniak configuration
  LangchainrbRails.configure do |config|
    config.vectorsearch = Langchain::Vectorsearch::Pgvector.new(
      llm: Langchain::LLM::OpenAI.new(
        api_key: ENV.fetch("INFOMANIAK_API_KEY", ""),
        llm_options: {
          uri_base: "https://api.infomaniak.com/1/ai/#{ENV.fetch("INFOMANIAK_PRODUCT_ID", "")}/openai"
        },
        default_options: {
          chat_completion_model_name: ENV.fetch("LLM_MODEL", "mistral24b"),
          completion_model_name: ENV.fetch("LLM_MODEL", "mistral24b"),
          embeddings_model_name: ENV.fetch("EMBEDDING_MODEL", "bge_multilingual_gemma2"),
          temperature: ENV.fetch("LLM_TEMPERATURE", 0.1).to_f,
          num_ctx: ENV.fetch("LLM_NUM_CTX", 4_096).to_i
        }
      )
    )
  end
else
  # Ollama default configuration
  LangchainrbRails.configure do |config|
    config.vectorsearch = Langchain::Vectorsearch::Pgvector.new(
      llm: Langchain::LLM::Ollama.new(
        url: ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434"),
        api_key: ENV.fetch("OLLAMA_API_KEY", ""),
        default_options: {
          chat_completion_model_name: ENV.fetch("LLM_MODEL", "granite3.3:2b"),
          completion_model_name: ENV.fetch("LLM_MODEL", "granite3.3:2b"),
          embeddings_model_name: ENV.fetch("EMBEDDING_MODEL", "granite-embedding:278m"),
          temperature: ENV.fetch("LLM_TEMPERATURE", 0.1).to_f,
          num_ctx: ENV.fetch("LLM_NUM_CTX", 4_096).to_i
        }
      )
    )
  end
end
