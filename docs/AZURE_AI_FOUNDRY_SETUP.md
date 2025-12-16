# Azure AI Foundry Integration Guide

This guide explains how to configure Nosia to use Azure AI Foundry models (including GitHub Models).

## Overview

Azure AI Foundry provides access to various AI models through two main endpoints:

1. **Azure OpenAI Service** - Traditional Azure deployment with api-version parameter
2. **GitHub Models / AI Foundry Catalog** - Simpler OpenAI-compatible endpoint

## Option 1: GitHub Models (Recommended - Easiest)

GitHub Models provides free access to various models with an OpenAI-compatible API.

### Configuration

1. Get your GitHub token from: https://github.com/settings/tokens
   - Or use Azure AI Foundry token

2. Update your `.env` file:

```bash
# Azure AI Foundry - GitHub Models
AI_BASE_URL=https://models.inference.ai.azure.com
AI_API_KEY=your-github-token-or-azure-key

# Choose your model
LLM_MODEL=gpt-4o
# Or other available models:
# - gpt-4o-mini
# - gpt-4o
# - Phi-3-medium-128k-instruct
# - Mistral-large
# - Cohere-command-r-plus
# - Meta-Llama-3-70B-Instruct
# - AI21-Jamba-Instruct

# Embedding model (if using Azure embeddings)
EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_DIMENSIONS=1536
```

3. Restart Nosia:
```bash
docker compose down
docker compose up -d
```

## Option 2: Azure OpenAI Service

If you have an Azure OpenAI Service deployment:

### Configuration

1. Get your Azure OpenAI credentials:
   - Endpoint: `https://<your-resource>.openai.azure.com`
   - API Key: From Azure Portal
   - Deployment names: Your model deployments

2. **Important**: Azure OpenAI requires an `api-version` parameter. We need to modify the initializer.

### Update Ruby LLM Initializer

Edit `config/initializers/ruby_llm.rb`:

```ruby
RubyLLM.configure do |config|
  config.default_model = ENV["LLM_MODEL"]
  config.default_embedding_model = ENV["EMBEDDING_MODEL"]
  
  # Azure OpenAI configuration
  if ENV["AZURE_OPENAI_ENDPOINT"]
    config.openai_api_base = "#{ENV['AZURE_OPENAI_ENDPOINT']}/openai/deployments"
    config.openai_api_key = ENV["AZURE_OPENAI_API_KEY"]
    config.openai_api_version = ENV.fetch("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")
  else
    # Standard OpenAI-compatible endpoint
    config.openai_api_base = ENV["AI_BASE_URL"]
    config.openai_api_key = ENV["AI_API_KEY"]
  end
  
  config.openai_use_system_role = true
  config.use_new_acts_as = true
end
```

3. Update `.env` for Azure OpenAI:

```bash
# Azure OpenAI Service
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com
AZURE_OPENAI_API_KEY=your-azure-api-key
AZURE_OPENAI_API_VERSION=2024-08-01-preview

# Use your deployment names (not model names)
LLM_MODEL=your-gpt4-deployment-name
EMBEDDING_MODEL=your-embedding-deployment-name
EMBEDDING_DIMENSIONS=1536
```

## Available Models

### Chat/Completion Models

| Model | Description | Context |
|-------|-------------|---------|
| gpt-4o | OpenAI's latest multimodal model | 128K |
| gpt-4o-mini | Smaller, faster GPT-4o | 128K |
| gpt-4-turbo | Previous generation GPT-4 | 128K |
| Phi-3-medium-128k-instruct | Microsoft's efficient 14B model | 128K |
| Mistral-large | Mistral's flagship model | 32K |
| Llama-3-70B-Instruct | Meta's open model | 8K |
| Cohere-command-r-plus | Cohere's latest model | 128K |

### Embedding Models

| Model | Dimensions | Description |
|-------|-----------|-------------|
| text-embedding-3-small | 1536 | Cost-effective embeddings |
| text-embedding-3-large | 3072 | Higher quality embeddings |
| text-embedding-ada-002 | 1536 | Legacy embeddings |

## Switching from Local to Azure Models

If you already have documents indexed with local embeddings:

1. **Change only the LLM model** (safe - no re-indexing needed):
   ```bash
   LLM_MODEL=gpt-4o-mini
   ```

2. **Change embedding model** (requires re-indexing):
   ```bash
   EMBEDDING_MODEL=text-embedding-3-small
   EMBEDDING_DIMENSIONS=1536
   
   # Re-index all documents
   docker compose exec web bin/rails embeddings:change_dimensions
   ```

## Testing Your Configuration

1. Check the model endpoint:
   ```bash
   curl https://models.inference.ai.azure.com/chat/completions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -d '{
       "model": "gpt-4o-mini",
       "messages": [{"role": "user", "content": "Hello"}]
     }'
   ```

2. Check in Nosia web interface:
   - Open a chat
   - Click "Modell" button
   - Verify current model is displayed

## Troubleshooting

### "Model not found" error
- Verify your deployment name matches exactly
- For Azure OpenAI, use deployment name, not model name
- For GitHub Models, use the full model identifier

### "Invalid API key" error
- Verify your token/key is correct
- Check token has proper permissions
- For GitHub: token needs `read:org` scope

### Slow responses
- Consider using smaller models (gpt-4o-mini, Phi-3)
- Check Azure region latency
- Monitor token usage

## Cost Optimization

| Use Case | Recommended Model | Why |
|----------|------------------|-----|
| Development/Testing | gpt-4o-mini | Cheapest, fast |
| Production - Norwegian | Phi-3 or Mistral | Good multilingual support |
| Production - Complex | gpt-4o | Best quality |
| Embeddings | text-embedding-3-small | Cost-effective |

## References

- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-studio/)
- [GitHub Models](https://github.com/marketplace/models)
- [Azure OpenAI Service](https://learn.microsoft.com/en-us/azure/ai-services/openai/)
