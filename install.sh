#!/bin/sh -e
# Nosia Installation Script
# This script sets up the Nosia application using Docker and Docker Compose.
# It handles prerequisites, environment variable generation, and pulls necessary files.
# Usage:
# curl -fsSL https://get.nosia.ai | sh

pull() {
  echo "Pulling latest Caddyfile..."
  curl -fsSL https://raw.githubusercontent.com/dilolabs/nosia/main/Caddyfile >Caddyfile
  echo "Caddyfile pulled successfully."

  echo "Pulling latest docker-compose.yml..."
  curl -fsSL https://raw.githubusercontent.com/dilolabs/nosia/main/docker-compose.yml >docker-compose.yml
  echo "docker-compose.yml pulled successfully."

  echo "Pulling latest Docker images..."
  docker compose pull
  echo "Docker images pulled successfully."

  echo "Setup complete. You can now start the application with 'docker compose up -d'."
}

setup_env() {
  if [ -f .env ]; then
    echo ".env file already exists, skipping generation"
    return
  fi

  echo "Generating environment variables for .env file"

  if ! [ -n "$NOSIA_URL" ]; then
    NOSIA_URL=https://nosia.localhost
  fi

  if ! [ -n "$AI_BASE_URL" ]; then
    case "$OSTYPE" in
    linux*) AI_BASE_URL=http://172.17.0.1:12434/engines/llama.cpp/v1 ;;
    darwin*) AI_BASE_URL=http://model-runner.docker.internal/engines/llama.cpp/v1 ;;
    cygwin* | msys* | win32) AI_BASE_URL=http://model-runner.docker.internal/engines/llama.cpp/v1 ;;
    esac
  fi

  if ! [ -n "$LLM_MODEL" ]; then
    LLM_MODEL=ai/granite-4.0-h-tiny
  fi

  if ! [ -n "$EMBEDDING_MODEL" ]; then
    EMBEDDING_MODEL=ai/granite-embedding-multilingual
  fi

  if ! [ -n "$EMBEDDING_DIMENSIONS" ]; then
    EMBEDDING_DIMENSIONS=768
  fi

  SECRET_KEY_BASE=$(openssl rand -hex 64)
  POSTGRES_HOST=postgres-db
  POSTGRES_PORT=5432
  POSTGRES_DB=nosia_production
  POSTGRES_USER=nosia
  POSTGRES_PASSWORD=$(openssl rand -hex 32)
  DATABASE_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB

  cat <<EOF >.env
# Nosia Environment Configuration
# Copy this file to .env and update with your actual values

# Application URL
NOSIA_URL=$NOSIA_URL

# Allow user registration (set to false to disable)
REGISTRATION_ALLOWED=true

# Secret Key Base (generate with: bin/rails secret)
# IMPORTANT: Change this in production!
SECRET_KEY_BASE=$SECRET_KEY_BASE

# AI Service Configuration
# Base URL for OpenAI-compatible API (e.g., Ollama, OpenAI, etc.)
AI_BASE_URL=$AI_BASE_URL
AI_API_KEY=$AI_API_KEY

# LLM Model Configuration
LLM_MODEL=$LLM_MODEL
LLM_TEMPERATURE=0.1
LLM_MAX_TOKENS=1_024
LLM_TOP_K=40
LLM_TOP_P=0.9

# Embedding Model Configuration
EMBEDDING_MODEL=$EMBEDDING_MODEL
EMBEDDING_DIMENSIONS=$EMBEDDING_DIMENSIONS

# Optional: Separate embedding service URL (defaults to AI_BASE_URL)
# EMBEDDING_BASE_URL=$EMBEDDING_BASE_URL

# Document Processing Configuration
CHUNK_MAX_TOKENS=512
CHUNK_MIN_TOKENS=128
CHUNK_MERGE_PEERS=true
RETRIEVAL_FETCH_K=3

# Optional: Guard Model for additional validation
GUARD_MODEL=

# Database Configuration (for production)
# Uncomment and configure for production deployments
POSTGRES_HOST=$POSTGRES_HOST
POSTGRES_PORT=$POSTGRES_PORT
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DATABASE_URL=$DATABASE_URL

# Optional: Docling Serve Configuration
# For advanced document processing
DOCLING_SERVE_BASE_URL=

# Optional: Augmented Context
# Enable for enhanced chat completions with context augmentation
AUGMENTED_CONTEXT=false

# Development/Test Database Configuration (handled by config/database.yml)
# DB_HOST=localhost
EOF

  echo ".env file generated successfully."
}

setup_linux() {
  echo "Setting up prerequisites..."

  # Check if openssl is installed
  if command -v openssl &>/dev/null; then
    echo "OpenSSL is already installed."
  else
    echo "Installing OpenSSL..."
    sudo apt-get install -y openssl
    echo "OpenSSL installed successfully."
  fi

  # Check if Docker is installed
  if command -v docker &>/dev/null; then
    echo "Docker is already installed."
    return
  fi

  echo "Installing Docker..."

  # Add Docker's official GPG key:
  sudo apt-get update
  sudo apt-get install ca-certificates curl -y
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update

  # Install Docker:
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-model-plugin -y

  # Add the current user to the docker group:
  sudo usermod -aG docker $USER

  echo "Docker installed successfully."
  echo "Please log out and log back in to apply the Docker group changes."
  echo "After logging back in, rerun this script to continue the setup."
  exit 0
}

setup_macos() {
  echo "Setting up prerequisites..."

  # Return if Docker is already installed
  if command -v docker &>/dev/null; then
    echo "Docker is already installed."
    return
  fi

  # Install prerequisites using Homebrew
  if command -v brew &>/dev/null; then
    # Install openssl if not installed
    if ! brew list openssl &>/dev/null; then
      echo "Installing OpenSSL..."
      brew install openssl
      echo "OpenSSL installed successfully."
    fi

    # Install Docker Desktop if not installed
    if ! brew list docker-desktop &>/dev/null; then
      echo "Installing Docker Desktop..."
      brew install --cask docker-desktop
      echo "Docker Desktop installed successfully."
    fi

    echo "Setting up Docker Desktop..."

    # Start Docker Desktop
    open -a Docker
    while ! docker system info >/dev/null 2>&1; do
      echo "Waiting for Docker to start..."
      sleep 1
    done
  else
    echo "Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop/ or ensure Homebrew is installed from https://brew.sh/"
    exit 1
  fi
}

setup_windows() {
  echo "Setting up prerequisites..."

  # Check if Docker is installed
  if command -v docker &>/dev/null; then
    echo "Docker is already installed."
    return
  else
    echo "Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop/"
    exit 1
  fi
}

do_install() {
  case "$OSTYPE" in
  linux*) setup_linux ;;
  darwin*) setup_macos ;;
  cygwin* | msys* | win32) setup_windows ;;
  *) echo "Unsupported OS: $OSTYPE" ;;
  esac

  setup_env
  pull
}

do_install
