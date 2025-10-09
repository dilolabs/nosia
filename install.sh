#!/bin/bash -e

pull() {
  echo "Pulling latest Caddyfile"
  curl -fsSL https://raw.githubusercontent.com/dilolabs/nosia/main/Caddyfile >Caddyfile

  echo "Pulling latest docker-compose.yml"
  curl -fsSL https://raw.githubusercontent.com/dilolabs/nosia/main/docker-compose.yml >docker-compose.yml

  echo "Pulling latest Nosia"
  docker compose pull
}

setup_env() {
  # Set environment variables for Nosia
  if [ -f .env ]; then
    echo ".env file already exists"
    return
  fi

  echo "Generating .env file"

  if [ -n "$NOSIA_URL" ]; then
    echo "Using NOSIA_URL from environment"
  else
    echo "NOSIA_URL is not set, using default value"
    NOSIA_URL=https://nosia.localhost
  fi

  if [ -n "$AI_BASE_URL" ]; then
    echo "Using AI_BASE_URL from environment"
  else
    echo "AI_BASE_URL is not set, using default value"
    if OS_NAME=$(uname -s) && [ "$OS_NAME" = "Darwin" ]; then
      AI_BASE_URL=http://model-runner.docker.internal/engines/llama.cpp/v1
    else
      AI_BASE_URL=http://172.17.0.1:12434/engines/llama.cpp/v1
    fi
  fi

  if [ -n "$LLM_MODEL" ]; then
    echo "Using LLM_MODEL from environment"
  else
    echo "LLM_MODEL is not set, using default value"
    LLM_MODEL=ai/granite-4.0-h-tiny
  fi

  if [ -n "$EMBEDDING_MODEL" ]; then
    echo "Using EMBEDDING_MODEL from environment"
  else
    echo "EMBEDDING_MODEL is not set, using default value"
    EMBEDDING_MODEL=ai/granite-embedding-multilingual
  fi

  if [ -n "$EMBEDDING_DIMENSIONS" ]; then
    echo "Using EMBEDDING_DIMENSIONS from environment"
  else
    echo "EMBEDDING_DIMENSIONS is not set, using default value"
    EMBEDDING_DIMENSIONS=768
  fi

  POSTGRES_HOST=postgres-db
  POSTGRES_PORT=5432
  POSTGRES_DB=nosia_production
  POSTGRES_USER=nosia
  POSTGRES_PASSWORD=$(openssl rand -hex 32)
  DATABASE_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB
  SECRET_KEY_BASE=$(openssl rand -hex 64)

  echo "NOSIA_URL=$NOSIA_URL" >>.env
  echo "REGISTRATION_ALLOWED=true" >>.env
  echo "SECRET_KEY_BASE=$SECRET_KEY_BASE" >>.env
  echo "AI_BASE_URL=$AI_BASE_URL" >>.env
  echo "AI_API_KEY=" >>.env
  echo "LLM_MODEL=$LLM_MODEL" >>.env
  echo "EMBEDDING_MODEL=$EMBEDDING_MODEL" >>.env
  echo "EMBEDDING_DIMENSIONS=$EMBEDDING_DIMENSIONS" >>.env
  echo "DATABASE_URL=$DATABASE_URL" >.env
  echo "POSTGRES_HOST=$POSTGRES_HOST" >>.env
  echo "POSTGRES_PORT=$POSTGRES_PORT" >>.env
  echo "POSTGRES_DB=$POSTGRES_DB" >>.env
  echo "POSTGRES_USER=$POSTGRES_USER" >>.env
  echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >>.env
  echo "LLM_TEMPERATURE=0.1" >>.env
  echo "LLM_MAX_TOKENS=1_024" >>.env
  echo "LLM_TOP_K=40" >>.env
  echo "LLM_TOP_P=0.9" >>.env
  echo "RETRIEVAL_FETCH_K=4" >>.env
  echo "CHUNK_MAX_TOKENS=512" >>.env
  echo "CHUNK_MIN_TOKENS=128" >>.env
  echo "CHUNK_MERGE_PEERS=true" >>.env
  echo "CHUNK_SIZE=1_500" >>.env
  echo "CHUNK_OVERLAP=250" >>.env
  echo "RAG_SYSTEM_TEMPLATE=\"You are Nosia, a helpful assistant. If necessary, use the information contained in the Nosia helpful content between <context> and </context>. Give a comprehensive answer to the question. Respond only to the question asked, response should be relevant to the question. If the answer cannot be deduced from the Nosia helpful content, do not use the context.\"" >>.env
  echo "AUGMENTED_CONTEXT=false" >>.env
  echo "#GUARD_MODEL=" >>.env
  echo "#DOCLING_SERVE_BASE_URL=" >>.env

  echo ".env file generated"
}

setup_linux() {
  echo "Setting up prerequisites"

  # Check if openssl is installed
  if ! command -v openssl &>/dev/null; then
    sudo apt-get install -y openssl
  fi

  # Check if Docker is installed
  if command -v docker &>/dev/null; then
    echo "Docker is already installed"
    return
  fi

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
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

  # Add the current user to the docker group:
  sudo usermod -aG docker $USER
}

setup_macos() {
  echo "Setting up prerequisites"

  # Install brew if not installed
  if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew"
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | sh
  fi

  # Install openssl if not installed
  if ! brew list openssl &>/dev/null; then
    echo "Installing OpenSSL"
    brew install openssl
  fi

  # Install Docker Desktop if not installed
  if ! brew list docker-desktop &>/dev/null; then
    echo "Installing Docker Desktop"
    brew install --cask docker-desktop
  fi

  echo "Setting up Nosia"

  # Start Docker Desktop
  open -a Docker
  while ! docker system info >/dev/null 2>&1; do
    echo "Waiting for Docker to start..."
    sleep 1
  done
}

case "$OSTYPE" in
linux*) setup_linux ;;
darwin*) setup_macos ;;
*) OS_NAME="Unknown" ;;
esac

setup_env
pull
