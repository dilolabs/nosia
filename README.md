# Nosia

Nosia is a platform that allows you to run an AI model on your own data.
It is designed to be easy to install and use.

You can follow this README or go to the [Nosia Guides](https://guides.nosia.ai/).

- [Quickstart](#quickstart)
- [API](#api)
- [Upgrade](#upgrade)
- [Start](#start)
- [Stop](#stop)
- [Troubleshooting](#troubleshooting)

## Easy to use

<https://github.com/nosia-ai/nosia/assets/1692273/ce60094b-abb5-4ed4-93aa-f69485e058b0>

![nosia-home](https://github.com/user-attachments/assets/dac211a3-6bc3-4f1c-9b1e-fbde9d81e862)

![nosia-documents](https://github.com/user-attachments/assets/bb71f748-4525-432b-8e11-f46fdc7461c4)

![nosia-chat](https://github.com/user-attachments/assets/a23517ab-7910-4ccc-9312-c0de8310ac86)

![nosia-document](https://github.com/user-attachments/assets/dc147f03-8832-4bb3-b87c-9f77a7eda2b3)

## Easy to install

<https://github.com/nosia-ai/nosia/assets/1692273/671ccb6a-054c-4dc2-bcd9-2b874a888548>

## Quickstart

### One command installation

#### On a macOS, Debian or Ubuntu machine

It will install Docker if needed, and Nosia on a macOS, Debian or Ubuntu machine.

```bash
curl -fsSL https://raw.githubusercontent.com/nosia-ai/nosia-install/main/nosia-install.sh | sh
```

You should see the following output:

```
[x] Setting up environment
[x] Setting up prerequisites
[x] Starting Nosia
```

You can now access Nosia at `https://nosia.localhost` with a self-signed certificate.

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
./script/upgrade
```

## Start

You can start the services with the following command:

```bash
docker compose --env-file .env up
# OR in the background
docker compose --env-file .env up -d
```

## Stop

You can stop the services with the following command:

```bash
docker compose --env-file .env down
```

## Troubleshooting

If you encounter any issue:

- during the installation, you can check the logs at `./log/production.log`
- during the use waiting for an AI response, you can check the jobs at `https://nosia.localhost/jobs`
- with Nosia, you can check the logs with `docker compose logs -f`

If you need further assistance, please open an issue!
