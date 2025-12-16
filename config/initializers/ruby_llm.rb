RubyLLM.configure do |config|
  # Azure OpenAI Service configuration
  if ENV["AZURE_OPENAI_ENDPOINT"].present?
    # For Azure, we need to use the GitHub Models / AI Foundry endpoint format instead
    # as it's simpler and doesn't require api-version in the URL
    config.default_model = "gpt-5-chat"  # This is the model name in Azure AI Foundry
    config.openai_api_base = ENV["AZURE_OPENAI_ENDPOINT"]
    config.openai_api_key = ENV["AZURE_OPENAI_API_KEY"]
  else
    # Standard OpenAI-compatible endpoint (Ollama, OpenAI, GitHub Models, etc.)
    config.default_model = ENV["LLM_MODEL"]
    config.openai_api_base = ENV["AI_BASE_URL"]
    config.openai_api_key = ENV["AI_API_KEY"]
  end
  
  config.default_embedding_model = ENV["EMBEDDING_MODEL"]
  
  config.openai_use_system_role = true # Use 'system' role instead of 'developer'

  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true
end
