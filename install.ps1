# Nosia Installation Script for Windows
# Usage: Invoke-WebRequest https://get.nosia.ai/install.ps1 -OutFile install.ps1; .\install.ps1

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"



# Detect system resources and return as hashtable
function Detect-SystemResources {
    Write-Host "Detecting system resources..."
    
    # Get total RAM in GB
    $SYSTEM_RAM_GB = 0
    $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computerInfo.TotalPhysicalMemory) {
        $SYSTEM_RAM_GB = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 0)
    }
    
    # Get CPU cores/threads
    $CPU_CORES = 1
    $processorInfo = Get-CimInstance -ClassName Win32_Processor
    if ($processorInfo) {
        $CPU_CORES = $processorInfo.NumberOfLogicalProcessors
    }
    
    # Detect GPU type and VRAM - Windows specific
    $GPU_TYPE = "none"
    $GPU_VRAM_GB = 0
    
    try {
        $gpuInfo = Get-CimInstance -ClassName Win32_VideoController | Select-Object -First 1
        if ($gpuInfo) {
            $adapterRAM = $gpuInfo.AdapterRAM
            if ($adapterRAM -gt 0) {
                $GPU_VRAM_GB = [math]::Round($adapterRAM / 1GB, 0)
                
                # Try to detect GPU type
                $description = $gpuInfo.Description -replace "\s+", " "
                if ($description -match "NVIDIA|GeForce|RTX|GTX") {
                    $GPU_TYPE = "nvidia"
                    Write-Host "Detected NVIDIA GPU with $GPU_VRAM_GB GB VRAM"
                } elseif ($description -match "AMD|Radeon|ATI") {
                    $GPU_TYPE = "amd"
                    Write-Host "Detected AMD GPU with $GPU_VRAM_GB GB VRAM"
                } elseif ($description -match "Intel|HD Graphics|Iris") {
                    $GPU_TYPE = "integrated"
                    Write-Host "Detected integrated GPU"
                }
            }
        }
    } catch {
        # GPU detection failed, continue with defaults
    }
    
    # If no GPU found, estimate based on RAM
    if ($GPU_TYPE -eq "none") {
        if ($SYSTEM_RAM_GB -ge 16) {
            $GPU_TYPE = "cpu_highmem"
            Write-Host "No GPU detected, treating as CPU with high RAM"
        } else {
            $GPU_TYPE = "cpu"
            Write-Host "No GPU detected, treating as CPU with standard RAM"
        }
    }
    
    Write-Host "System resources: $SYSTEM_RAM_GB GB RAM, $CPU_CORES CPU cores, $GPU_TYPE ($GPU_VRAM_GB GB VRAM)"
    
    return @{
        SYSTEM_RAM_GB = $SYSTEM_RAM_GB
        CPU_CORES = $CPU_CORES
        GPU_TYPE = $GPU_TYPE
        GPU_VRAM_GB = $GPU_VRAM_GB
    }
}

# Select LLM model based on system resources
function Select-LLMModel {
    param(
        [int]$gpu_vram,
        [int]$system_ram
    )
    
    if ($gpu_vram -lt 4) {
        if ($system_ram -lt 8) {
            return "ai/ministral3:3B-Q4_K_M|32768|512|128"
        } else {
            return "ai/ministral3:8B-Q4_K_M|32768|512|128"
        }
    } elseif ($gpu_vram -ge 4 -and $gpu_vram -lt 8) {
        if ($system_ram -ge 16 -and $system_ram -lt 32) {
            return "ai/magistral-small-3.2:24B-UD-IQ2_XXS|32768|1024|256"
        } else {
            return "ai/ministral3:8B-Q4_K_M|32768|512|128"
        }
    } else {
        if ($system_ram -ge 32) {
            return "ai/ministral3:14B-BF16|32768|1024|256"
        } else {
            return "ai/ministral3:8B-BF16|32768|1024|256"
        }
    }
}

# Select embedding model based on system resources
function Select-EmbeddingModel {
    param(
        [int]$gpu_vram,
        [int]$system_ram
    )
    
    if ($system_ram -ge 16 -and $gpu_vram -ge 4) {
        return "ai/qwen3-0.6B-F16|4096|1024|256"
    } elseif ($gpu_vram -ge 4) {
        return "ai/qwen3-0.6B-F16|4096|1024|256"
    } else {
        return "ai/granite-embedding-multilingual:278M-F16|278|512|128"
    }
}

# Generate docker-compose.yml
function Generate-DockerCompose {
    # Set default NOSIA_URL if not defined
    if (-not (Test-Path variable:global:NOSIA_URL)) {
        $global:NOSIA_URL = "https://nosia.localhost"
    }
    
    $composeContent = @"
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
"@

    $composeContent | Out-File -FilePath "docker-compose.yml" -Encoding utf8
}

# Setup environment file
function Setup-Env {
    param(
        [int]$system_ram,
        [int]$gpu_vram
    )
    
    if (Test-Path ".env") {
        Write-Host ".env file exists, checking for missing encryption keys..."
        
        $envContent = Get-Content ".env" -Raw
        
        # Add missing encryption keys
        if ($envContent -notmatch "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=") {
            Write-Host "Adding ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY..."
            $envContent += "`n" + "# Active Record Encryption Keys (generated by install script)`n"
            $envContent += "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=" + (Get-RandomHexString 32) + "`n"
        }
        
        if ($envContent -notmatch "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=") {
            Write-Host "Adding ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY..."
            $envContent += "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=" + (Get-RandomHexString 32) + "`n"
        }
        
        if ($envContent -notmatch "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=") {
            Write-Host "Adding ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT..."
            $envContent += "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=" + (Get-RandomHexString 32) + "`n"
        }
        
        $envContent | Out-File -FilePath ".env" -Encoding utf8 -Force
        Write-Host "Encryption keys check complete."
        return
    }
    
    Write-Host "Generating environment variables..."
    
    # Set NOSIA_URL
    $NOSIA_URL = $env:NOSIA_URL
    if ([string]::IsNullOrEmpty($NOSIA_URL)) {
        $NOSIA_URL = "https://nosia.localhost"
    }
    
    # Set AI_BASE_URL for Windows
    $AI_BASE_URL = $env:AI_BASE_URL
    if ([string]::IsNullOrEmpty($AI_BASE_URL)) {
        $AI_BASE_URL = "http://model-runner.docker.internal/engines/llama.cpp/v1"
    }
    
    # Auto-select LLM model if not set
    $LLM_MODEL = $env:LLM_MODEL
    if ([string]::IsNullOrEmpty($LLM_MODEL)) {
        Write-Host "Auto-selecting LLM model based on system resources..."
        $llm_config = Select-LLMModel -gpu_vram $gpu_vram -system_ram $system_ram
        $llm_parts = $llm_config -split '\|'
        $LLM_MODEL = $llm_parts[0]
        $LLM_MAX_TOKENS = $llm_parts[1]
        $CHUNK_SIZE = $llm_parts[2]
        $CHUNK_OVERLAP = $llm_parts[3]
        Write-Host "Selected $LLM_MODEL"
    }
    
    # Auto-select embedding model if not set
    $EMBEDDING_MODEL = $env:EMBEDDING_MODEL
    if ([string]::IsNullOrEmpty($EMBEDDING_MODEL)) {
        Write-Host "Auto-selecting embedding model..."
        $embedding_config = Select-EmbeddingModel -gpu_vram $gpu_vram -system_ram $system_ram
        $embedding_parts = $embedding_config -split '\|'
        $EMBEDDING_MODEL = $embedding_parts[0]
        $EMBEDDING_DIMENSIONS = $embedding_parts[1]
        $CHUNK_SIZE = $embedding_parts[2]
        $CHUNK_OVERLAP = $embedding_parts[3]
        Write-Host "Selected $EMBEDDING_MODEL"
    }
    
    # Set embedding dimensions if not set but model is
    if ([string]::IsNullOrEmpty($EMBEDDING_DIMENSIONS) -and -not [string]::IsNullOrEmpty($EMBEDDING_MODEL)) {
        switch -Regex ($EMBEDDING_MODEL) {
            "granite-278M|278M" { $EMBEDDING_DIMENSIONS = 278 }
            "qwen3-0.6B|0.6B" { $EMBEDDING_DIMENSIONS = 4096 }
            "384|384d" { $EMBEDDING_DIMENSIONS = 384 }
            "768|768d" { $EMBEDDING_DIMENSIONS = 768 }
            default { $EMBEDDING_DIMENSIONS = 768 }
        }
    }
    
    # Generate secrets
    $SECRET_KEY_BASE = Get-RandomHexString 64
    $ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY = Get-RandomHexString 32
    $ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY = Get-RandomHexString 32
    $ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT = Get-RandomHexString 32
    $POSTGRES_PASSWORD = Get-RandomHexString 32
    
    # Database configuration
    $POSTGRES_HOST = "postgres-db"
    $POSTGRES_PORT = 5432
    $POSTGRES_DB = "nosia_production"
    $POSTGRES_USER = "nosia"
    
    # Docling configuration
    $DOCLING_SERVE_BASE_URL = ""
    $AUGMENTED_CONTEXT = "false"
    
    $envContent = @"
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
AI_API_KEY=${env:AI_API_KEY}

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
GUARD_MODEL=${env:GUARD_MODEL}

# Database Configuration
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}

# Optional: Docling Serve Configuration
DOCLING_SERVE_BASE_URL=${DOCLING_SERVE_BASE_URL}

# Optional: Augmented Context
AUGMENTED_CONTEXT=${AUGMENTED_CONTEXT}
"@

    $envContent | Out-File -FilePath ".env" -Encoding utf8
    Write-Host ".env file generated successfully."
}

# Helper function to generate random hex string
function Get-RandomHexString {
    param([int]$length)
    
    $bytes = New-Object byte[]($length)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    return [System.BitConverter]::ToString($bytes).Replace("-", "").ToLower()
}

# Setup Windows prerequisites
function Setup-Windows {
    Write-Host "Setting up Windows prerequisites..."
    
    # Check if Docker is installed
    try {
        $dockerVersion = docker --version
        Write-Host "Docker is already installed: $dockerVersion"
        return
    } catch {
        Write-Host "Docker is not installed."
    }
    
    Write-Host "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    Write-Host "After installing Docker Desktop, restart your computer and run this script again."
    exit 1
}

# Main installation
function Do-Install {
    # Detect system resources
    $resources = Detect-SystemResources
    $SYSTEM_RAM_GB = $resources.SYSTEM_RAM_GB
    $GPU_VRAM_GB = $resources.GPU_VRAM_GB
    
    # Generate docker-compose.yml
    Generate-DockerCompose
    
    # Setup environment
    Setup-Env -system_ram $SYSTEM_RAM_GB -gpu_vram $GPU_VRAM_GB
    
    # Install prerequisites
    Setup-Windows
    
    # Pull latest files
    Write-Host "Pulling latest Caddyfile..."
    try {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dilolabs/nosia/main/Caddyfile" -OutFile "Caddyfile"
        Write-Host "Caddyfile pulled successfully."
    } catch {
        Write-Host "Warning: Could not download Caddyfile - $_"
    }
    
    Write-Host "Pulling latest Docker images..."
    docker compose pull
    Write-Host "Docker images pulled successfully."
    
    Write-Host "Setup complete. Start with: docker compose up -d"
}

# Run installation
try {
    Do-Install
} catch {
    Write-Host "Error during installation: $_" -ForegroundColor Red
    exit 1
}
