#!/bin/sh -e
# Nosia Installation Script
# This script sets up the Nosia application using Docker and Docker Compose.
# It handles prerequisites, environment variable generation, and pulls necessary files.
# Usage:
# curl -fsSL https://get.nosia.ai | sh

# Detect architecture and return appropriate platform string
get_platform() {
  case "$(uname -m)" in
    aarch64|arm64)
      case "$OSTYPE" in
        darwin*) echo "linux/arm64" ;;  # Apple M-series
        *) echo "linux/arm64" ;;
      esac
      ;;
    x86_64|amd64)
      case "$OSTYPE" in
        darwin*) echo "linux/amd64" ;;  # Apple Intel
        *) echo "linux/amd64" ;;
      esac
      ;;
    *)
      # Default to amd64 for unknown architectures
      echo "linux/amd64"
      ;;
  esac
}

# Generate docker-compose.yml with optional docling-serve service
generate_docker_compose() {
  local platform="$1"

  cat > docker-compose.yml <<EOF
services:
  reverse-proxy:
    image: caddy:latest
    depends_on:
      - web
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      - NOSIA_URL=\${NOSIA_URL}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-config:/config
      - caddy-data:/data

  db-migrate:
    image: dilolabs/nosia:latest
    command: bundle exec rails db:prepare
    environment:
      - DATABASE_URL=\${DATABASE_URL}
      - SECRET_KEY_BASE=\${SECRET_KEY_BASE}
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=\${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY}
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=\${ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY}
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=\${ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT}
    depends_on:
      postgres-db:
        condition: service_healthy
    restart: "no"

  web:
    image: dilolabs/nosia:latest
    environment:
      - DATABASE_URL=\${DATABASE_URL}
      - SECRET_KEY_BASE=\${SECRET_KEY_BASE}
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=\${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY}
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=\${ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY}
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=\${ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT}
      - AI_BASE_URL=\${AI_BASE_URL}
      - AI_API_KEY=\${AI_API_KEY}
      - LLM_MODEL=\${LLM_MODEL}
      - LLM_TEMPERATURE=\${LLM_TEMPERATURE}
      - LLM_MAX_TOKENS=\${LLM_MAX_TOKENS}
      - LLM_TOP_P=\${LLM_TOP_P}
      - LLM_TOP_K=\${LLM_TOP_K}
      - EMBEDDING_MODEL=\${EMBEDDING_MODEL}
      - EMBEDDING_DIMENSIONS=\${EMBEDDING_DIMENSIONS}
      - CHUNK_SIZE=\${CHUNK_SIZE}
      - CHUNK_OVERLAP=\${CHUNK_OVERLAP}
      - RETRIEVAL_FETCH_K=\${RETRIEVAL_FETCH_K}
      - GUARD_MODEL=\${GUARD_MODEL}
      - DOCLING_SERVE_BASE_URL=\${DOCLING_SERVE_BASE_URL}
      - AUGMENTED_CONTEXT=\${AUGMENTED_CONTEXT}
    models:
      - llm
      - embedding
    volumes:
      - rails-storage:/rails/storage
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/up"]
      interval: 2s
      timeout: 5s
      retries: 30
    depends_on:
      postgres-db:
        condition: service_healthy
      db-migrate:
        condition: service_completed_successfully
    restart: on-failure:5

  postgres-db:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_DB=\${POSTGRES_DB}
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
    volumes:
      - postgres-db-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}
      interval: 2s
      timeout: 5s
      retries: 30
    restart: on-failure:5

  solidq:
    image: dilolabs/nosia:latest
    command: bundle exec rake solid_queue:start
    environment:
      - DATABASE_URL=\${DATABASE_URL}
      - SECRET_KEY_BASE=\${SECRET_KEY_BASE}
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=\${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY}
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=\${ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY}
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=\${ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT}
      - AI_BASE_URL=\${AI_BASE_URL}
      - AI_API_KEY=\${AI_API_KEY}
      - LLM_MODEL=\${LLM_MODEL}
      - LLM_TEMPERATURE=\${LLM_TEMPERATURE}
      - LLM_MAX_TOKENS=\${LLM_MAX_TOKENS}
      - LLM_TOP_P=\${LLM_TOP_P}
      - LLM_TOP_K=\${LLM_TOP_K}
      - EMBEDDING_MODEL=\${EMBEDDING_MODEL}
      - EMBEDDING_DIMENSIONS=\${EMBEDDING_DIMENSIONS}
      - CHUNK_SIZE=\${CHUNK_SIZE}
      - CHUNK_OVERLAP=\${CHUNK_OVERLAP}
      - RETRIEVAL_FETCH_K=\${RETRIEVAL_FETCH_K}
      - GUARD_MODEL=\${GUARD_MODEL}
      - DOCLING_SERVE_BASE_URL=\${DOCLING_SERVE_BASE_URL}
      - AUGMENTED_CONTEXT=\${AUGMENTED_CONTEXT}
    models:
      - llm
      - embedding
    volumes:
      - rails-storage:/rails/storage
    depends_on:
      postgres-db:
        condition: service_healthy
      web:
        condition: service_healthy
    restart: on-failure:5

EOF

  # Add docling-serve service if ADVANCED_DOCUMENTS_UNDERSTANDING is true
  if [ "$ADVANCED_DOCUMENTS_UNDERSTANDING" = "true" ]; then
    cat >> docker-compose.yml <<EOF
  docling-serve:
    image: quay.io/docling-project/docling-serve:latest
    platform: ${platform}
    ports:
      - "5001:5001"
    environment:
      - DOCLING_SERVE_ENABLE_UI=0
      - DOCLING_SERVE_HOST=0.0.0.0
      - DOCLING_SERVE_PORT=5001
    volumes:
      - docling-data:/app/data
    restart: unless-stopped
EOF
  fi

  # Add volumes section
  cat >> docker-compose.yml <<EOF

models:
  llm:
    model: \${LLM_MODEL}
  embedding:
    model: \${EMBEDDING_MODEL}

volumes:
  caddy-config:
  caddy-data:
  postgres-db-data:
  rails-storage:
EOF

  # Add docling-data volume if ADVANCED_DOCUMENTS_UNDERSTANDING is true
  if [ "$ADVANCED_DOCUMENTS_UNDERSTANDING" = "true" ]; then
    echo "  docling-data:" >> docker-compose.yml
  fi
}

pull() {
  echo "Pulling latest Caddyfile..."
  curl -fsSL https://raw.githubusercontent.com/dilolabs/nosia/main/Caddyfile >Caddyfile
  echo "Caddyfile pulled successfully."

  echo "Pulling latest Docker images..."
  docker compose pull
  echo "Docker images pulled successfully."

  echo "Setup complete. You can now start the application with 'docker compose up -d'."
}

setup_env() {
  if [ -f .env ]; then
    echo ".env file already exists, checking for missing encryption keys..."

    # Check and add missing encryption keys
    if ! grep -q "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=" .env; then
      echo "Adding ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY..."
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)
      echo "" >> .env
      echo "# Active Record Encryption Keys (generated by install script)" >> .env
      echo "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" >> .env
    fi

    if ! grep -q "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=" .env; then
      echo "Adding ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY..."
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)
      echo "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" >> .env
    fi

    if ! grep -q "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=" .env; then
      echo "Adding ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT..."
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)
      echo "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" >> .env
    fi

    echo "Encryption keys check complete."

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
    LLM_MODEL=ai/ministral3:3B-BF16
  fi

  if ! [ -n "$EMBEDDING_MODEL" ]; then
    EMBEDDING_MODEL=ai/granite-embedding-multilingual:278M-F16
  fi

  if ! [ -n "$EMBEDDING_DIMENSIONS" ]; then
    EMBEDDING_DIMENSIONS=768
  fi

  SECRET_KEY_BASE=$(openssl rand -hex 64)
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)
  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)
  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)
  POSTGRES_HOST=postgres-db
  POSTGRES_PORT=5432
  POSTGRES_DB=nosia_production
  POSTGRES_USER=nosia
  POSTGRES_PASSWORD=$(openssl rand -hex 32)
  DATABASE_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB

  # Set DOCLING_SERVE_BASE_URL if ADVANCED_DOCUMENTS_UNDERSTANDING is enabled
  if [ "$ADVANCED_DOCUMENTS_UNDERSTANDING" = "true" ]; then
    DOCLING_SERVE_BASE_URL=http://docling-serve:5001
  else
    DOCLING_SERVE_BASE_URL=
  fi

  cat <<EOF >.env
# Nosia Environment Configuration

# Application URL
NOSIA_URL=$NOSIA_URL

# Allow user registration (set to false to disable)
REGISTRATION_ALLOWED=true

# Secret Key Base (generate with: bin/rails secret)
SECRET_KEY_BASE=$SECRET_KEY_BASE

# Active Record Encryption Keys (generate with: bin/rails db:encryption:init)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT

# AI Service Configuration
# Base URL for OpenAI-compatible API (e.g., Ollama, OpenAI, etc.)
AI_BASE_URL=$AI_BASE_URL
AI_API_KEY=$AI_API_KEY

# LLM Model Configuration
LLM_MODEL=$LLM_MODEL
LLM_TEMPERATURE=0.1
LLM_MAX_TOKENS=32_768
LLM_TOP_K=40
LLM_TOP_P=0.9

# Embedding Model Configuration
EMBEDDING_MODEL=$EMBEDDING_MODEL
EMBEDDING_DIMENSIONS=$EMBEDDING_DIMENSIONS

# Optional: Separate embedding service URL (defaults to AI_BASE_URL)
# EMBEDDING_BASE_URL=$EMBEDDING_BASE_URL

# Document Processing Configuration
CHUNK_SIZE=512
CHUNK_OVERLAP=128
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
# For advanced documents understanding
DOCLING_SERVE_BASE_URL=$DOCLING_SERVE_BASE_URL

# Optional: Augmented Context
# Enable for enhanced chat completions with context augmentation
AUGMENTED_CONTEXT=true

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

  # Detect platform for docling-serve
  PLATFORM=$(get_platform)

  # Generate docker-compose.yml
  generate_docker_compose "$PLATFORM"

  setup_env
  pull
}

do_install
