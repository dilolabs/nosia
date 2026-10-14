RubyLLM.configure do |config|
  config.default_model = ENV["LLM_MODEL"]
  config.default_embedding_model = ENV["EMBEDDING_MODEL"]
  config.openai_api_base = ENV["AI_BASE_URL"]
  config.openai_api_key = ENV["AI_API_KEY"]
  config.openai_protocol = :chat_completions
  config.openai_use_system_role = true # Use 'system' role instead of 'developer'
end
