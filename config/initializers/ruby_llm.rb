RubyLLM.configure do |config|
  # Azure OpenAI Service configuration
  if ENV["AZURE_OPENAI_ENDPOINT"].present?
    # Use Azure deployment name if provided, otherwise fallback to LLM_MODEL
    config.default_model = ENV.fetch("AZURE_LLM_DEPLOYMENT", ENV["LLM_MODEL"])
    # Azure OpenAI uses deployment-based URLs
    # API version is handled via query parameter by the underlying HTTP client
    config.openai_api_base = "#{ENV['AZURE_OPENAI_ENDPOINT']}/openai/deployments"
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
