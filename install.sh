#!/bin/sh -e
# Nosia Installation Script
# Usage: curl -fsSL https://get.nosia.ai | sh

# Detect system resources and set exported variables
detect_system_resources() {
  echo "Detecting system resources..."

  # Get total RAM in GB
  SYSTEM_RAM_GB=0
  if command -v free &>/dev/null; then
    SYSTEM_RAM_GB=$(( $(free -g | awk '/^Mem:/{print $2}') ))
  elif command -v sysctl &>/dev/null; then
    mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    SYSTEM_RAM_GB=$(( mem_bytes / 1073741824 ))
  fi

  # Get CPU cores/threads
  CPU_CORES=1
  if command -v nproc &>/dev/null; then
    CPU_CORES=$(nproc)
  elif command -v sysctl &>/dev/null; then
    CPU_CORES=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
  elif [ -f /proc/cpuinfo ]; then
    CPU_CORES=$(grep -c processor /proc/cpuinfo 2>/dev/null || echo 1)
  fi

  # Detect GPU type and VRAM
  GPU_TYPE="none"
  GPU_VRAM_GB=0

  if command -v nvidia-smi &>/dev/null; then
    GPU_TYPE="nvidia"
    vram_output=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -n1)

    if echo "$vram_output" | grep -qi "MiB"; then
      vram_mb=$(echo "$vram_output" | grep -oE '[0-9]+' | head -n1)
      GPU_VRAM_GB=$(( vram_mb / 1024 ))
    elif echo "$vram_output" | grep -qi "GiB"; then
      GPU_VRAM_GB=$(echo "$vram_output" | grep -oE '[0-9]+' | head -n1)
    fi

    [ "$GPU_VRAM_GB" -lt 1 ] && GPU_VRAM_GB=0
    echo "Detected NVIDIA GPU with ${GPU_VRAM_GB}GB VRAM"
  elif command -v rocm-smi &>/dev/null; then
    GPU_TYPE="amd"
    vram_gb=$(rocm-smi --showmeminfo vram 2>/dev/null | awk '/Total.*:/ {sum += $NF} END {print int(sum/1024)}' 2>/dev/null || echo 0)
    GPU_VRAM_GB=$vram_gb
    [ "$GPU_VRAM_GB" -lt 1 ] && GPU_VRAM_GB=0
    echo "Detected AMD GPU with ${GPU_VRAM_GB}GB VRAM"
  elif command -v lspci &>/dev/null; then
    if lspci | grep -i vga | grep -qi "intel\|amd\|ati"; then
      GPU_TYPE="integrated"
      echo "Detected integrated GPU"
    fi
  fi

  # If no GPU found, estimate based on RAM
  if [ "$GPU_TYPE" = "none" ]; then
    if [ "$SYSTEM_RAM_GB" -ge 16 ]; then
      GPU_TYPE="cpu_highmem"
      echo "No GPU detected, treating as CPU with high RAM"
    else
      GPU_TYPE="cpu"
      echo "No GPU detected, treating as CPU with standard RAM"
    fi
  fi

  # Export for use in setup_env
  DETECTED_SYSTEM_RAM_GB=$SYSTEM_RAM_GB
  DETECTED_CPU_CORES=$CPU_CORES
  DETECTED_GPU_TYPE=$GPU_TYPE
  DETECTED_GPU_VRAM_GB=$GPU_VRAM_GB

  echo "System resources: ${SYSTEM_RAM_GB}GB RAM, ${CPU_CORES} CPU cores, ${GPU_TYPE} (${GPU_VRAM_GB}GB VRAM)"
}

# Memory available to model inference: the larger of GPU VRAM (GPU/offloaded
# inference) or system RAM (CPU inference). Docker Model Runner can run on
# either, so the bigger pool bounds the largest model that fits.
usable_memory_gb() {
  gpu_vram=$1
  system_ram=$2

  if [ "$gpu_vram" -gt "$system_ram" ]; then
    echo "$gpu_vram"
  else
    echo "$system_ram"
  fi
}

# Select LLM model based on system resources.
# Footprints (approx, with context + a concurrent embedding model):
#   ai/mistral-small4:119B ~70GB  | ai/gemma4:26B ~16GB
#   ai/gemma4:E4B ~4GB            | ai/gemma4:E2B ~2GB
select_llm_model() {
  gpu_vram=$1
  system_ram=$2
  available=$(usable_memory_gb "$gpu_vram" "$system_ram")

  if [ "$available" -ge 96 ]; then
    echo "ai/mistral-small4:119B|32768|1024|256"
  elif [ "$available" -ge 24 ]; then
    echo "ai/gemma4:26B|32768|1024|256"
  elif [ "$available" -ge 8 ]; then
    echo "ai/gemma4:E4B|32768|512|128"
  else
    echo "ai/gemma4:E2B|32768|512|128"
  fi
}

# Select embedding model based on system resources.
# ai/qwen3-embedding:8B-F16 needs ~16GB on top of the LLM, so it is reserved
# for machines that also comfortably run a large LLM. Everything else uses the
# tiny ~0.6GB ai/granite-embedding-multilingual:278M-F16.
select_embedding_model() {
  gpu_vram=$1
  system_ram=$2
  available=$(usable_memory_gb "$gpu_vram" "$system_ram")

  if [ "$available" -ge 48 ]; then
    echo "ai/qwen3-embedding:8B-F16|4096|1024|256"
  else
    echo "ai/granite-embedding-multilingual:278M-F16|768|512|128"
  fi
}

# Generate docker-compose.yml
generate_docker_compose() {
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
      - EMBEDDING_MODEL=\${EMBEDDING_MODEL}
      - EMBEDDING_DIMENSIONS=\${EMBEDDING_DIMENSIONS}
      - CHUNK_SIZE=\${CHUNK_SIZE}
      - CHUNK_OVERLAP=\${CHUNK_OVERLAP}
      - RETRIEVAL_FETCH_K=\${RETRIEVAL_FETCH_K}
      - GUARD_MODEL=\${GUARD_MODEL}
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
      - EMBEDDING_MODEL=\${EMBEDDING_MODEL}
      - EMBEDDING_DIMENSIONS=\${EMBEDDING_DIMENSIONS}
      - CHUNK_SIZE=\${CHUNK_SIZE}
      - CHUNK_OVERLAP=\${CHUNK_OVERLAP}
      - RETRIEVAL_FETCH_K=\${RETRIEVAL_FETCH_K}
      - GUARD_MODEL=\${GUARD_MODEL}
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
}

# Setup environment file
setup_env() {
  local system_ram="$1"
  local gpu_vram="$2"

  if [ -f .env ]; then
    echo ".env file exists, checking for missing encryption keys..."

    # Add missing encryption keys
    if ! grep -q "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=" .env; then
      echo "Adding ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY..."
      echo "" >> .env
      echo "# Active Record Encryption Keys (generated by install script)" >> .env
      echo "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)" >> .env
    fi

    if ! grep -q "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=" .env; then
      echo "Adding ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY..."
      echo "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)" >> .env
    fi

    if ! grep -q "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=" .env; then
      echo "Adding ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT..."
      echo "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)" >> .env
    fi

    echo "Encryption keys check complete."
    return
  fi

  echo "Generating environment variables..."

  # Set NOSIA_URL
  NOSIA_URL=${NOSIA_URL:-https://nosia.localhost}

  # Set AI_BASE_URL based on OS
  case "$OSTYPE" in
    linux*) AI_BASE_URL=http://172.17.0.1:12434/engines/llama.cpp/v1 ;;
    darwin*|cygwin*|msys*|win32) AI_BASE_URL=http://model-runner.docker.internal/engines/llama.cpp/v1 ;;
    *) AI_BASE_URL=http://172.17.0.1:12434/engines/llama.cpp/v1 ;;
  esac
  AI_BASE_URL=${AI_BASE_URL:-}

  # Auto-select LLM model if not set
  if [ -z "$LLM_MODEL" ]; then
    echo "Auto-selecting LLM model based on system resources..."
    llm_config=$(select_llm_model "$gpu_vram" "$system_ram")
    LLM_MODEL=$(echo "$llm_config" | cut -d'|' -f1)
    LLM_MAX_TOKENS=$(echo "$llm_config" | cut -d'|' -f2)
    CHUNK_SIZE=$(echo "$llm_config" | cut -d'|' -f3)
    CHUNK_OVERLAP=$(echo "$llm_config" | cut -d'|' -f4)
    echo "Selected ${LLM_MODEL}"
  fi

  # Auto-select embedding model if not set
  if [ -z "$EMBEDDING_MODEL" ]; then
    echo "Auto-selecting embedding model..."
    embedding_config=$(select_embedding_model "$gpu_vram" "$system_ram")
    EMBEDDING_MODEL=$(echo "$embedding_config" | cut -d'|' -f1)
    EMBEDDING_DIMENSIONS=$(echo "$embedding_config" | cut -d'|' -f2)
    CHUNK_SIZE=$(echo "$embedding_config" | cut -d'|' -f3)
    CHUNK_OVERLAP=$(echo "$embedding_config" | cut -d'|' -f4)
    echo "Selected ${EMBEDDING_MODEL}"
  fi

  # Set embedding dimensions if not set but model is
  if [ -z "$EMBEDDING_DIMENSIONS" ] && [ -n "$EMBEDDING_MODEL" ]; then
    case "$EMBEDDING_MODEL" in
      *granite-embedding*|*278M*) EMBEDDING_DIMENSIONS=768 ;;
      *qwen3-embedding*|*8B*) EMBEDDING_DIMENSIONS=4096 ;;
      *384*|*384d*) EMBEDDING_DIMENSIONS=384 ;;
      *768*|*768d*) EMBEDDING_DIMENSIONS=768 ;;
      *) EMBEDDING_DIMENSIONS=768 ;;
    esac
  fi

  # Generate secrets
  SECRET_KEY_BASE=$(openssl rand -hex 64)
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)
  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)
  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)
  POSTGRES_PASSWORD=$(openssl rand -hex 32)

  # Database configuration
  POSTGRES_HOST=postgres-db
  POSTGRES_PORT=5432
  POSTGRES_DB=nosia_production
  POSTGRES_USER=nosia
  DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}

  # Optional: Augmented Context
  # Enable for enhanced chat completions with context augmentation
  AUGMENTED_CONTEXT=true

  cat >.env <<EOF
# Nosia Environment Configuration

# Application URL
NOSIA_URL=${NOSIA_URL}

# Allow user registration
REGISTRATION_ALLOWED=true

# Secret Key Base
SECRET_KEY_BASE=${SECRET_KEY_BASE}

# Active Record Encryption Keys
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY}
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY}
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT}

# AI Service Configuration
AI_BASE_URL=${AI_BASE_URL}
AI_API_KEY=${AI_API_KEY}

# LLM Model Configuration
LLM_MODEL=${LLM_MODEL}
LLM_TEMPERATURE=0.1
LLM_MAX_TOKENS=${LLM_MAX_TOKENS}
LLM_TOP_P=0.9

# Embedding Model Configuration
EMBEDDING_MODEL=${EMBEDDING_MODEL}
EMBEDDING_DIMENSIONS=${EMBEDDING_DIMENSIONS}

# Document Processing Configuration
CHUNK_SIZE=${CHUNK_SIZE}
CHUNK_OVERLAP=${CHUNK_OVERLAP}
RETRIEVAL_FETCH_K=3

# Optional: Guard Model
GUARD_MODEL=

# Database Configuration
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_URL=${DATABASE_URL}

# Optional: Augmented Context
AUGMENTED_CONTEXT=${AUGMENTED_CONTEXT}
EOF

  echo ".env file generated successfully."
}

# Setup Linux prerequisites
setup_linux() {
  echo "Setting up Linux prerequisites..."

  if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install ca-certificates curl -y
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-model-plugin -y
    sudo usermod -aG docker $USER
    echo "Docker installed. Please log out and log back in to apply group changes."
    echo "After logging back in, rerun this script."
    exit 0
  fi

  echo "Docker is already installed."
}

# Setup macOS prerequisites
setup_macos() {
  echo "Setting up macOS prerequisites..."

  if command -v docker &>/dev/null; then
    echo "Docker is already installed."
    return
  fi

  if ! command -v brew &>/dev/null; then
    echo "Please install Homebrew from https://brew.sh/"
    exit 1
  fi

  # Install Docker Desktop
  if ! brew list docker-desktop &>/dev/null; then
    echo "Installing Docker Desktop..."
    brew install --cask docker-desktop
  fi

  echo "Starting Docker Desktop..."
  open -a Docker
  while ! docker system info >/dev/null 2>&1; do
    echo "Waiting for Docker to start..."
    sleep 1
  done
}

# Setup Windows prerequisites
setup_windows() {
  echo "Setting up Windows prerequisites..."

  if command -v docker &>/dev/null; then
    echo "Docker is already installed."
    return
  fi

  echo "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
  exit 1
}

# Main installation
do_install() {
  # Detect system resources
  detect_system_resources

  # Generate docker-compose.yml
  generate_docker_compose

  # Setup environment
  setup_env "$DETECTED_SYSTEM_RAM_GB" "$DETECTED_GPU_VRAM_GB"

  # Install prerequisites based on OS
  case "$OSTYPE" in
    linux*) setup_linux ;;
    darwin*) setup_macos ;;
    cygwin*|msys*|win32) setup_windows ;;
    *) echo "Unsupported OS: $OSTYPE" ;;
  esac

  # Pull latest files
  echo "Pulling latest Caddyfile..."
  curl -fsSL https://raw.githubusercontent.com/dilolabs/nosia/main/Caddyfile >Caddyfile
  echo "Caddyfile pulled successfully."

  echo "Pulling latest Docker images..."
  docker compose pull
  echo "Docker images pulled successfully."

  echo "Setup complete. Start with: docker compose up -d"
}

# Run installation
do_install
