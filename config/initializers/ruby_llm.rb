RubyLLM.configure do |config|
  config.default_model = ENV["LLM_MODEL"]
  config.default_embedding_model = ENV["EMBEDDING_MODEL"]
  config.openai_api_base = ENV["AI_BASE_URL"]
  config.openai_api_key = ENV["AI_API_KEY"]
  config.openai_use_system_role = true # Use 'system' role instead of 'developer'

  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true
end
