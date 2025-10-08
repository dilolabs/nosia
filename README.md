# Nosia

Nosia is a platform that allows you to run an AI model on your own data.
It is designed to be easy to install and use.

You can follow this README or go to the [Nosia Guides](https://guides.nosia.ai/).

**Documentation**:
- [Architecture](docs/ARCHITECTURE.md) - Detailed system design and implementation
- [System Diagrams](docs/DIAGRAMS.md) - Visual representations of system components
- [Deployment Guide](docs/DEPLOYMENT.md) - Production deployment strategies and best practices
- [Code of Conduct](CODE_OF_CONDUCT.md)

**Contents**:
- [Quickstart](#quickstart)
- [Configuration](#configuration)
- [API](#api)
- [Upgrade](#upgrade)
- [Start](#start)
- [Stop](#stop)
- [Troubleshooting](#troubleshooting)

## Quickstart

### One command installation

#### On a macOS, Debian or Ubuntu machine

It will install Docker if needed, and Nosia on a macOS, Debian or Ubuntu machine.

```bash
curl -fsSL https://raw.githubusercontent.com/nosia-ai/nosia-install/main/nosia-install.sh | sh
```

You should see the following output:

```
Setting up prerequisites
Setting up Nosia
Generating .env file
Pulling latest Nosia
[+] Pulling 6/6
 ✔ llm Pulled
 ✔ embedding Pulled
 ✔ web Pulled
 ✔ reverse-proxy Pulled
 ✔ postgres-db Pulled
 ✔ solidq Pulled
```

You can now start Nosia with:

```bash
docker compose up
# OR in the background
docker compose up -d
```

Then you can access Nosia at `https://nosia.localhost` with a self-signed certificate.

### Custom installation

#### With a custom completion model

By default, Nosia uses:

1. Completion model: `ai/granite-4.0-h-tiny`
1. Embeddings model: `ai/granite-embedding-multilingual`

You can use any completion model available on [Docker Hub AI](https://hub.docker.com/u/ai) by setting the `LLM_MODEL` environment variable during the installation.

**Example:**

To use the `ai/mistral` model, run:

```bash
curl -fsSL https://raw.githubusercontent.com/nosia-ai/nosia-install/main/nosia-install.sh \
  | LLM_MODEL=ai/mistral sh
```

#### With a custom embeddings model

By default, Nosia uses `ai/granite-embedding-multilingual` embedding model.

If you use new dimensions by using a new embedding model, you'll need to:

1. Change the `EMBEDDING_MODEL` and `EMBEDDING_DIMENSIONS` environment variables in the `.env` file.

2. Re-build the services:

```bash
docker compose --env-file .env build
```

3. Execute the change embedding dimensions task

```bash
docker compose run web bin/rails embeddings:change_dimensions
```

### Advanced installation

### With Docling serve

If you want to use Docling serve for document processing, you can use the `docker-compose-docling.yml` file, then run the following command:

```bash
docker compose -f docker-compose-docling.yml up
```

This will start a Docling serve instance on port 5001.
Then, you can configure the Docling serve URL in the Nosia environment variables:

```
DOCLING_SERVE_BASE_URL=http://localhost:5001
```

### With augmented context

If you want to use augmented context for chat completions, you can enable it in the Nosia environment variables:

```
AUGMENTED_CONTEXT=true
```

## Configuration

### Environment Variables

Nosia validates required environment variables at startup to prevent runtime failures. If any required variables are missing or invalid, the application will fail to start with a clear error message.

#### Required Variables

- `SECRET_KEY_BASE` - Rails secret key (generate with `bin/rails secret`)
- `AI_BASE_URL` - Base URL for OpenAI-compatible API (e.g., `http://model-runner.docker.internal/engines/llama.cpp/v1`)
- `LLM_MODEL` - Language model identifier (e.g., `ai/mistral`)
- `EMBEDDING_MODEL` - Embedding model identifier (e.g., `ai/granite-embedding-multilingual`)
- `EMBEDDING_DIMENSIONS` - Embedding vector dimensions (e.g., `768`)

#### Optional Variables with Defaults

- `AI_API_KEY` - API key for the AI service (default: empty)
- `LLM_TEMPERATURE` - Model temperature (default: `0.1`)
- `LLM_TOP_K` - Top K sampling (default: `40`)
- `LLM_TOP_P` - Top P sampling (default: `0.9`)
- `RETRIEVAL_FETCH_K` - Number of chunks to retrieve (default: `3`)

See `.env.example` for a complete list of configuration options.

### Setting Up Your Environment

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and update the values for your deployment:
   ```bash
   # Update required values
   SECRET_KEY_BASE=$(bin/rails secret)
   AI_BASE_URL=http://your-ai-service:11434/v1
   LLM_MODEL=your-preferred-model
   EMBEDDING_MODEL=your-embedding-model
   EMBEDDING_DIMENSIONS=768
   ```

3. Test your configuration:
   ```bash
   bin/rails runner "puts 'Configuration valid!'"
   ```

If validation fails, you'll see a detailed error message indicating which variables are missing or invalid.

## API

## Get an API token

1. Go as a logged in user to `https://nosia.localhost/api_tokens`
1. Generate and copy your token
1. Use your favorite OpenAI chat completion API client by configuring API base to `https://nosia.localhost/v1` and API key with your token.

## Start a chat completion

[Follow the guide](https://guides.nosia.ai/api#start-a-chat-completion)

## Upgrade

You can upgrade the services with the following command:

```bash
docker compose pull
```

## Start

You can start the services with the following command:

```bash
docker compose up
# OR in the background
docker compose up -d
```

## Stop

You can stop the services with the following command:

```bash
docker compose down
```

## Troubleshooting

If you encounter any issue:

- during the installation, you can check the logs at `./log/production.log`
- during the use waiting for an AI response, you can check the jobs at `https://nosia.localhost/jobs`
- with Nosia, you can check the logs with `docker compose logs -f`

If you need further assistance, please open an issue!
