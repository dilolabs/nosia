# Nosia

**Self-hosted Retrieval Augmented Generation (RAG) Platform**

Nosia is a platform that allows you to run AI models on your own data with complete privacy and control. It is designed to be easy to install and use, providing OpenAI-compatible APIs that work seamlessly with existing AI applications.

## Features

- **🔒 Private & Secure** - Your data stays on your infrastructure
- **🤖 OpenAI-Compatible API** - Drop-in replacement for OpenAI clients
- **📚 RAG-Powered** - Augment AI responses with your documents
- **🔄 Real-time Streaming** - Server-sent events for live responses
- **📄 Multi-format Support** - PDFs, text files, websites, and Q&A pairs
- **🎯 Semantic Search** - Vector similarity search with pgvector
- **🐳 Easy Deployment** - Docker Compose with one-command setup
- **🔑 Multi-tenancy** - Account-based isolation for secure data separation

## Preview

### Install

![nosia-install](https://github.com/user-attachments/assets/0b303da3-ac70-4809-8af2-ebf8aa93ecec)

### Start and First Run

![nosia-start](https://github.com/user-attachments/assets/4b802c43-6b34-4ec2-8a12-f5de5d730030)

https://github.com/user-attachments/assets/4720f8a3-8a91-4e51-b4af-0ba7d66fa65e

## Quick Links

- 📖 [Nosia Guides](https://guides.nosia.ai/) - Step-by-step tutorials
- 🏗️ [Architecture Documentation](docs/README.md) - Technical deep dive
- 💬 [Community Support](https://github.com/nosia-ai/nosia/issues) - Get help

## Documentation

- [📐 Architecture](docs/ARCHITECTURE.md) - Detailed system design and implementation
- [📊 System Diagrams](docs/DIAGRAMS.md) - Visual representations of system components
- [🚀 Deployment Guide](docs/DEPLOYMENT.md) - Production deployment strategies and best practices
- [📋 Documentation Index](docs/README.md) - Complete documentation overview
- [🤝 Code of Conduct](CODE_OF_CONDUCT.md) - Community guidelines

## Table of Contents

- [Quickstart](#quickstart)
  - [One Command Installation](#one-command-installation)
  - [Custom Installation](#custom-installation)
  - [Advanced Installation](#advanced-installation)
- [Configuration](#configuration)
- [Using Nosia](#using-nosia)
  - [Web Interface](#web-interface)
  - [API Access](#api-access)
- [Managing Your Installation](#managing-your-installation)
  - [Start](#start)
  - [Stop](#stop)
  - [Upgrade](#upgrade)
  - [Logs](#logs)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Quickstart

### One Command Installation

Get Nosia up and running in minutes on macOS, Debian, or Ubuntu.

#### Prerequisites

- macOS, Debian, or Ubuntu operating system
- Internet connection
- sudo/root access (for Docker installation if needed)

#### Installation

The installation script will:
1. Install Docker and Docker Compose if not already present
2. Download Nosia configuration files
3. Generate a secure `.env` file
4. Pull all required Docker images

```bash
curl -fsSL https://get.nosia.ai | sh
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

#### Starting Nosia

Start all services with:

```bash
docker compose up
# OR run in the background
docker compose up -d
```

#### Accessing Nosia

Once started, access Nosia at:
- **Web Interface:** `https://nosia.localhost`
- **API Endpoint:** `https://nosia.localhost/v1`

> **Note:** The default installation uses a self-signed SSL certificate. Your browser will show a security warning on first access. For production deployments, see the [Deployment Guide](docs/DEPLOYMENT.md) for proper SSL certificate configuration.

### Custom Installation

#### Default Models

By default, Nosia uses:

- **Completion model:** `ai/granite-4.0-h-tiny`
- **Embeddings model:** `ai/granite-embedding-multilingual`

#### Using a Custom Completion Model

You can use any completion model available on [Docker Hub AI](https://hub.docker.com/u/ai) by setting the `LLM_MODEL` environment variable during installation.

**Example with Granite 4.0 32B:**

```bash
curl -fsSL https://get.nosia.ai | LLM_MODEL=ai/granite-4.0-h-small sh
```

**Model options:**
- `ai/granite-4.0-h-micro` - 3B long-context instruct model by IBM
- `ai/granite-4.0-h-tiny` - 7B long-context instruct model by IBM (default)
- `ai/granite-4.0-h-small` - 32B long-context instruct model by IBM
- `ai/mistral` - Efficient open model (7B) with top-tier performance and fast inference by Mistral AI
- `ai/magistral-small-3.2` - 24B multimodal instruction model by Mistral AI
- `ai/devstral-small` - Agentic coding LLM (24B) fine-tuned from Mistral-Small 3.1 by Mistral AI
- `ai/llama3.3` - Meta's Llama 3.3 model
- `ai/gemma3` - Google's Gemma 3 model
- `ai/qwen3` - Alibaba's Qwen 3 model
- `ai/deepseek-r1-distill-llama` - DeepSeek's distilled Llama model
- Browse more at [Docker Hub AI](https://hub.docker.com/u/ai)

#### Using a Custom Embeddings Model

By default, Nosia uses `ai/granite-embedding-multilingual` for generating document embeddings.

**To change the embeddings model:**

1. Update the environment variables in your `.env` file:
   ```bash
   EMBEDDING_MODEL=your-preferred-embedding-model
   EMBEDDING_DIMENSIONS=768  # Adjust based on your model's output dimensions
   ```

2. Restart Nosia to apply changes:
   ```bash
   docker compose down
   docker compose up -d
   ```

3. Update existing embeddings (if you have documents already indexed):
   ```bash
   docker compose run web bin/rails embeddings:change_dimensions
   ```

> **Important:** Different embedding models produce vectors of different dimensions. Ensure `EMBEDDING_DIMENSIONS` matches your model's output size, or vector search will fail.

### Advanced Installation

#### With Docling Document Processing

[Docling](https://github.com/DS4SD/docling) provides enhanced document processing capabilities for complex PDFs and documents.

**To enable Docling:**

1. Start Nosia with the Docling compose file:
   ```bash
   docker compose -f docker-compose-docling.yml up
   ```

2. Configure the Docling URL in your `.env` file:
   ```env
   DOCLING_SERVE_BASE_URL=http://localhost:5001
   ```

This starts a Docling serve instance on port 5001 that Nosia will use for advanced document parsing.

#### With Augmented Context (RAG)

Enable Retrieval Augmented Generation to enhance AI responses with relevant context from your documents.

**To enable RAG:**

Add to your `.env` file:
```env
AUGMENTED_CONTEXT=true
```

When enabled, Nosia will:
1. Search your document knowledge base for relevant chunks
2. Include the most relevant context in the AI prompt
3. Generate responses grounded in your specific data

**Additional RAG configuration:**
```env
RETRIEVAL_FETCH_K=3          # Number of document chunks to retrieve
LLM_TEMPERATURE=0.1          # Lower temperature for more factual responses
```

## Configuration

### Environment Variables

Nosia validates required environment variables at startup to prevent runtime failures. If any required variables are missing or invalid, the application will fail to start with a clear error message.

#### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SECRET_KEY_BASE` | Rails secret key for session encryption | Generate with `bin/rails secret` |
| `AI_BASE_URL` | Base URL for OpenAI-compatible API | `http://model-runner.docker.internal/engines/llama.cpp/v1` |
| `LLM_MODEL` | Language model identifier | `ai/mistral`, `ai/granite-4.0-h-tiny` |
| `EMBEDDING_MODEL` | Embedding model identifier | `ai/granite-embedding-multilingual` |
| `EMBEDDING_DIMENSIONS` | Embedding vector dimensions | `768`, `384`, `1536` |

#### Optional Variables with Defaults

| Variable | Description | Default | Range/Options |
|----------|-------------|---------|---------------|
| `AI_API_KEY` | API key for the AI service | empty | Any string |
| `LLM_TEMPERATURE` | Model creativity (lower = more factual) | `0.1` | `0.0` - `2.0` |
| `LLM_TOP_K` | Top K sampling parameter | `40` | `1` - `100` |
| `LLM_TOP_P` | Top P (nucleus) sampling | `0.9` | `0.0` - `1.0` |
| `RETRIEVAL_FETCH_K` | Number of document chunks to retrieve for RAG | `3` | `1` - `10` |
| `AUGMENTED_CONTEXT` | Enable RAG for chat completions | `false` | `true`, `false` |
| `DOCLING_SERVE_BASE_URL` | Docling document processing service URL | empty | `http://localhost:5001` |

See `.env.example` for a complete list of configuration options.

### Setting Up Your Environment

#### For Docker Compose (Recommended)

The installation script automatically generates a `.env` file. To customize:

1. Edit the `.env` file in your installation directory:
   ```bash
   nano .env
   ```

2. Update values as needed and restart:
   ```bash
   docker compose down
   docker compose up -d
   ```

#### For Manual/Development Setup

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Generate a secure secret key:
   ```bash
   SECRET_KEY_BASE=$(bin/rails secret)
   echo "SECRET_KEY_BASE=$SECRET_KEY_BASE" >> .env
   ```

3. Update other required values in `.env`:
   ```env
   AI_BASE_URL=http://your-ai-service:11434/v1
   LLM_MODEL=ai/mistral
   EMBEDDING_MODEL=ai/granite-embedding-multilingual
   EMBEDDING_DIMENSIONS=768
   ```

4. Test your configuration:
   ```bash
   bin/rails runner "puts 'Configuration valid!'"
   ```

If validation fails, you'll see a detailed error message indicating which variables are missing or invalid.

## Using Nosia

### Web Interface

After starting Nosia, access the web interface at `https://nosia.localhost`:

1. **Create an account** or log in
2. **Upload documents** - PDFs, text files, or add website URLs
3. **Create Q&A pairs** - Add domain-specific knowledge
4. **Start chatting** - Ask questions about your documents

### API Access

Nosia provides an OpenAI-compatible API that works with existing OpenAI client libraries.

#### Getting an API Token

1. Log in to Nosia web interface
2. Navigate to `https://nosia.localhost/api_tokens`
3. Click "Generate Token" and copy your API key
4. Store it securely - it won't be shown again

#### Using the API

Configure your OpenAI client to use Nosia:

**Python Example:**
```python
from openai import OpenAI

client = OpenAI(
    base_url="https://nosia.localhost/v1",
    api_key="your-nosia-api-token"
)

response = client.chat.completions.create(
    model="default",  # Nosia uses your configured model
    messages=[
        {"role": "user", "content": "What is in my documents about AI?"}
    ],
    stream=True
)

for chunk in response:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="")
```

**cURL Example:**
```bash
curl https://nosia.localhost/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-nosia-api-token" \
  -d '{
    "model": "default",
    "messages": [
      {"role": "user", "content": "Summarize my documents"}
    ]
  }'
```

**Node.js Example:**
```javascript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'https://nosia.localhost/v1',
  apiKey: 'your-nosia-api-token'
});

const response = await client.chat.completions.create({
  model: 'default',
  messages: [
    { role: 'user', content: 'What information do you have about my project?' }
  ]
});

console.log(response.choices[0].message.content);
```

For more API examples and details, see the [API Guide](https://guides.nosia.ai/api#start-a-chat-completion).

## Managing Your Installation

### Start

Start all Nosia services:

```bash
# Start in foreground (see logs in real-time)
docker compose up

# Start in background (detached mode)
docker compose up -d
```

Check that all services are running:
```bash
docker compose ps
```

### Stop

Stop all running services:

```bash
# Stop services (keeps data)
docker compose down

# Stop and remove all data (⚠️ destructive)
docker compose down -v
```

### Upgrade

Keep Nosia up to date with the latest features and security fixes:

```bash
# Pull latest images
docker compose pull

# Restart services with new images
docker compose up -d

# View logs to ensure successful upgrade
docker compose logs -f web
```

**Upgrade checklist:**
1. Backup your data before upgrading (see [Deployment Guide](docs/DEPLOYMENT.md))
2. Review release notes for breaking changes
3. Pull latest images
4. Restart services
5. Verify functionality

### Logs

View logs for troubleshooting:

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f web
docker compose logs -f postgres-db
docker compose logs -f llm

# Last 100 lines
docker compose logs --tail=100 web
```

### Health Check

Verify Nosia is running correctly:

```bash
# Check service status
docker compose ps

# Check web application health
curl -k https://nosia.localhost/up

# Check background jobs
docker compose exec web bin/rails runner "puts SolidQueue::Job.count"
```

## Troubleshooting

### Common Issues

#### Installation Problems

**Docker not found:**
```bash
# Verify Docker is installed
docker --version

# Install Docker if needed (Ubuntu/Debian)
curl -fsSL https://get.docker.com | sh
```

**Permission denied:**
```bash
# Add your user to docker group
sudo usermod -aG docker $USER

# Log out and back in, then try again
```

#### Runtime Issues

**Services won't start:**
```bash
# Check logs for errors
docker compose logs

# Verify .env file exists and has required variables
cat .env | grep -E 'SECRET_KEY_BASE|AI_BASE_URL|LLM_MODEL'

# Restart services
docker compose down && docker compose up -d
```

**Slow AI responses:**
1. Check background jobs: `https://nosia.localhost/jobs`
2. View job logs:
   ```bash
   docker compose logs -f solidq
   ```
3. Ensure your hardware meets minimum requirements (see [Deployment Guide](docs/DEPLOYMENT.md))

**Can't access web interface:**
```bash
# Check if services are running
docker compose ps

# Verify reverse-proxy is healthy
docker compose logs reverse-proxy

# Test connectivity
curl -k https://nosia.localhost/up
```

**Database connection errors:**
```bash
# Check PostgreSQL is running
docker compose ps postgres-db

# View database logs
docker compose logs postgres-db

# Test database connection
docker compose exec web bin/rails runner "ActiveRecord::Base.connection.execute('SELECT 1')"
```

#### Document Processing Issues

**Documents not processing:**
1. Check background jobs: `https://nosia.localhost/jobs`
2. View processing logs:
   ```bash
   docker compose logs -f web
   ```
3. Verify embedding service is running:
   ```bash
   docker compose ps embedding
   ```

**Embedding errors:**
```bash
# Verify EMBEDDING_DIMENSIONS matches your model
docker compose exec web bin/rails runner "puts ENV['EMBEDDING_DIMENSIONS']"

# Rebuild embeddings if dimensions changed
docker compose run web bin/rails embeddings:change_dimensions
```

### Log Locations

| Issue Type | Log Location | Command |
|------------|--------------|---------|
| Installation | `./log/production.log` | `tail -f log/production.log` |
| Runtime errors | Docker logs | `docker compose logs -f web` |
| Background jobs | Jobs dashboard | Visit `https://nosia.localhost/jobs` |
| Database | PostgreSQL logs | `docker compose logs postgres-db` |
| AI model | LLM container logs | `docker compose logs llm` |

### Getting Help

If you need further assistance:

1. **Check Documentation:**
   - [Architecture Guide](docs/ARCHITECTURE.md) - Understand how Nosia works
   - [Deployment Guide](docs/DEPLOYMENT.md) - Advanced configuration

2. **Search Existing Issues:**
   - [GitHub Issues](https://github.com/nosia-ai/nosia/issues)
   - Someone may have encountered the same problem

3. **Open a New Issue:**
   - Include your Nosia version: `docker compose images | grep web`
   - Describe the problem with steps to reproduce
   - Include relevant logs (remove sensitive information)
   - Specify your OS and Docker version

4. **Community Support:**
   - [GitHub Discussions](https://github.com/nosia-ai/nosia/discussions)
   - Share your use case and get advice from the community

## Contributing

We welcome contributions! Here's how you can help:

- **Report bugs** - Open an issue with details and reproduction steps
- **Suggest features** - Share your ideas in GitHub Discussions
- **Improve documentation** - Submit PRs for clarity and accuracy
- **Write code** - Fix bugs or implement new features
- **Share your experience** - Write blog posts or tutorials

See [CONTRIBUTING.md](CONTRIBUTING.md) if available, or start by opening an issue to discuss your ideas.

## License

Nosia is open source software. See [LICENSE](LICENSE) for details.

## Additional Resources

- **Website:** [nosia.ai](https://nosia.ai/)
- **Documentation:** [guides.nosia.ai](https://guides.nosia.ai/)
- **Source Code:** [github.com/nosia-ai/nosia](https://github.com/nosia-ai/nosia)
- **Docker Hub:** [hub.docker.com/u/ai](https://hub.docker.com/u/ai)

---

**Built with ❤️ by the Nosia community**
