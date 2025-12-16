RubyLLM.configure do |config|
  config.default_model = ENV["LLM_MODEL"]
  config.default_embedding_model = ENV["EMBEDDING_MODEL"]
  
  # Azure OpenAI Service configuration
  if ENV["AZURE_OPENAI_ENDPOINT"].present?
    # Azure OpenAI uses deployment-based URLs and requires api-version
    config.openai_api_base = "#{ENV['AZURE_OPENAI_ENDPOINT']}/openai/deployments"
    config.openai_api_key = ENV["AZURE_OPENAI_API_KEY"]
    # Set the API version (required by Azure)
    config.openai_api_version = ENV.fetch("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")
  else
    # Standard OpenAI-compatible endpoint (Ollama, OpenAI, GitHub Models, etc.)
    config.openai_api_base = ENV["AI_BASE_URL"]
    config.openai_api_key = ENV["AI_API_KEY"]
  end
  
  config.openai_use_system_role = true # Use 'system' role instead of 'developer'

  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true
end
