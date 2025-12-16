#!/bin/bash
# Script to switch between Local and Azure OpenAI configurations
# Usage: ./scripts/switch_ai_provider.sh [local|azure]

set -e

ENV_FILE=".env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found!"
    exit 1
fi

show_usage() {
    echo "Usage: $0 [local|azure|status]"
    echo ""
    echo "Commands:"
    echo "  local   - Switch to local Granite models"
    echo "  azure   - Switch to Azure OpenAI Service"
    echo "  status  - Show current configuration"
    echo ""
    echo "Examples:"
    echo "  $0 local"
    echo "  $0 azure"
    echo "  $0 status"
}

show_status() {
    echo "Current AI Configuration:"
    echo "========================="
    
    if grep -q "^AZURE_OPENAI_ENDPOINT=" "$ENV_FILE" 2>/dev/null && ! grep -q "^#AZURE_OPENAI_ENDPOINT=" "$ENV_FILE"; then
        echo "Provider: Azure OpenAI Service"
        echo ""
        grep "^AZURE_OPENAI_ENDPOINT=" "$ENV_FILE" || echo "  (not set)"
        grep "^LLM_MODEL=" "$ENV_FILE" || echo "  LLM_MODEL: (not set)"
        grep "^EMBEDDING_MODEL=" "$ENV_FILE" || echo "  EMBEDDING_MODEL: (not set)"
    else
        echo "Provider: Local/Ollama Models"
        echo ""
        grep "^AI_BASE_URL=" "$ENV_FILE" || echo "  AI_BASE_URL: (not set)"
        grep "^LLM_MODEL=" "$ENV_FILE" || echo "  LLM_MODEL: (not set)"
        grep "^EMBEDDING_MODEL=" "$ENV_FILE" || echo "  EMBEDDING_MODEL: (not set)"
    fi
}

switch_to_local() {
    echo "Switching to Local Granite models..."
    
    # Comment out Azure variables
    sed -i.bak 's/^AZURE_OPENAI_ENDPOINT=/#AZURE_OPENAI_ENDPOINT=/g' "$ENV_FILE"
    sed -i.bak 's/^AZURE_OPENAI_API_KEY=/#AZURE_OPENAI_API_KEY=/g' "$ENV_FILE"
    sed -i.bak 's/^AZURE_OPENAI_API_VERSION=/#AZURE_OPENAI_API_VERSION=/g' "$ENV_FILE"
    
    # Uncomment local variables if they're commented
    sed -i.bak 's/^#AI_BASE_URL=/AI_BASE_URL=/g' "$ENV_FILE"
    sed -i.bak 's/^#AI_API_KEY=/AI_API_KEY=/g' "$ENV_FILE"
    
    # Set local models
    sed -i.bak 's/^LLM_MODEL=.*/LLM_MODEL=ai\/granite-4.0-h-tiny/g' "$ENV_FILE"
    sed -i.bak 's/^EMBEDDING_MODEL=.*/EMBEDDING_MODEL=ai\/granite-embedding-multilingual/g' "$ENV_FILE"
    sed -i.bak 's/^EMBEDDING_DIMENSIONS=.*/EMBEDDING_DIMENSIONS=768/g' "$ENV_FILE"
    
    rm -f "$ENV_FILE.bak"
    
    echo "✓ Switched to local models"
    echo ""
    echo "Configuration:"
    echo "  LLM: ai/granite-4.0-h-tiny"
    echo "  Embedding: ai/granite-embedding-multilingual (768 dims)"
    echo ""
    echo "Restart Nosia to apply changes:"
    echo "  docker compose restart web"
}

switch_to_azure() {
    echo "Switching to Azure OpenAI Service..."
    
    # Check if Azure variables are already set
    if ! grep -q "^AZURE_OPENAI_ENDPOINT=" "$ENV_FILE" && ! grep -q "^#AZURE_OPENAI_ENDPOINT=" "$ENV_FILE"; then
        echo ""
        echo "Azure OpenAI variables not found in .env file."
        echo "Please add the following to your .env file first:"
        echo ""
        echo "AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com"
        echo "AZURE_OPENAI_API_KEY=your-azure-api-key"
        echo "AZURE_OPENAI_API_VERSION=2024-08-01-preview"
        echo ""
        echo "Then set your deployment names:"
        echo "LLM_MODEL=your-gpt4-deployment-name"
        echo "EMBEDDING_MODEL=your-embedding-deployment-name"
        echo "EMBEDDING_DIMENSIONS=1536"
        echo ""
        exit 1
    fi
    
    # Comment out local variables
    sed -i.bak 's/^AI_BASE_URL=/#AI_BASE_URL=/g' "$ENV_FILE"
    sed -i.bak 's/^AI_API_KEY=/#AI_API_KEY=/g' "$ENV_FILE"
    
    # Uncomment Azure variables
    sed -i.bak 's/^#AZURE_OPENAI_ENDPOINT=/AZURE_OPENAI_ENDPOINT=/g' "$ENV_FILE"
    sed -i.bak 's/^#AZURE_OPENAI_API_KEY=/AZURE_OPENAI_API_KEY=/g' "$ENV_FILE"
    sed -i.bak 's/^#AZURE_OPENAI_API_VERSION=/AZURE_OPENAI_API_VERSION=/g' "$ENV_FILE"
    
    rm -f "$ENV_FILE.bak"
    
    echo "✓ Switched to Azure OpenAI"
    echo ""
    echo "Make sure your .env has valid Azure credentials and deployment names:"
    grep "^AZURE_OPENAI_ENDPOINT=" "$ENV_FILE" || echo "  AZURE_OPENAI_ENDPOINT: (not set)"
    grep "^LLM_MODEL=" "$ENV_FILE" || echo "  LLM_MODEL: (not set)"
    echo ""
    echo "Restart Nosia to apply changes:"
    echo "  docker compose restart web"
}

case "${1:-}" in
    local)
        switch_to_local
        ;;
    azure)
        switch_to_azure
        ;;
    status)
        show_status
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
