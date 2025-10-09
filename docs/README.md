# Nosia Documentation

Welcome to the Nosia documentation! This directory contains comprehensive technical documentation for developers, operators, and contributors working with the Nosia platform.

## Overview

Nosia is a self-hosted Retrieval Augmented Generation (RAG) platform that allows you to run AI models on your own data with complete privacy and control. Built on Rails 8, it provides OpenAI-compatible APIs for seamless integration with existing AI applications.

## Documentation Structure

### [Architecture Documentation](ARCHITECTURE.md)
Detailed technical documentation covering the system design and implementation of Nosia.

**Topics covered:**
- System overview and technology stack
- Core components and data models
- RAG (Retrieval Augmented Generation) implementation
- Embedding strategy and vector search
- Document processing pipeline
- Chat completion flow
- Database schema and relationships
- Background job processing
- API architecture and OpenAI compatibility
- Security and multi-tenancy
- Deployment architecture

**Best for:** Developers who want to understand how Nosia works internally, contribute to the codebase, or extend functionality.

### [System Diagrams](DIAGRAMS.md)
Visual representations of system components and data flows using ASCII diagrams.

**Diagrams included:**
- Full system architecture
- RAG processing flow
- Document ingestion pipeline
- Chat completion sequence
- Database schema relationships
- Background job queues
- API request flow
- Deployment topology

**Best for:** Visual learners who want a high-level understanding of system interactions and data flows.

### [Deployment Guide](DEPLOYMENT.md)
Production deployment strategies, best practices, and operational guidance.

**Topics covered:**
- Deployment options (Docker Compose, Kamal, Kubernetes)
- Pre-deployment checklist and infrastructure requirements
- Environment variable management
- Database setup and migrations
- SSL/TLS certificate configuration
- Backup and disaster recovery strategies
- Monitoring and logging setup
- Security hardening best practices
- Scaling strategies for growing workloads
- Common troubleshooting scenarios

**Best for:** DevOps engineers and system administrators responsible for deploying and maintaining Nosia in production environments.

## Quick Links

### Getting Started
- [Main README](../README.md) - Installation and quickstart guide
- [Nosia Guides](https://guides.nosia.ai/) - Official online guides

### Configuration
- [Environment Variables](../README.md#configuration) - Required and optional configuration options
- [.env.example](../.env.example) - Example environment configuration file

### Development
- [Architecture](ARCHITECTURE.md) - Understand the codebase structure
- [Code of Conduct](../CODE_OF_CONDUCT.md) - Community guidelines

### Operations
- [Deployment](DEPLOYMENT.md) - Production deployment strategies
- [Troubleshooting](../README.md#troubleshooting) - Common issues and solutions

## Key Concepts

### Retrieval Augmented Generation (RAG)
Nosia uses RAG to enhance AI responses by retrieving relevant context from your documents before generating completions. This ensures responses are grounded in your specific data rather than relying solely on the model's training data.

### Multi-tenancy
Each account in Nosia is completely isolated, ensuring that users can only access their own data. This makes Nosia suitable for multi-user deployments while maintaining data privacy.

### OpenAI Compatibility
Nosia implements OpenAI-compatible APIs, allowing you to use existing OpenAI client libraries and tools by simply changing the base URL and API key. No code changes required in your applications.

### Vector Search
Documents are split into chunks, embedded using specialized models, and stored in PostgreSQL with the pgvector extension. This enables fast semantic similarity search to find the most relevant context for each query.

## Technology Stack

- **Backend:** Ruby on Rails 8.0
- **Database:** PostgreSQL 16 with pgvector extension
- **Vector Search:** pgvector with cosine similarity
- **Background Jobs:** Solid Queue (database-backed)
- **Real-time:** Action Cable with enhanced PostgreSQL adapter
- **AI Integration:** RubyLLM gem for OpenAI-compatible model access
- **Frontend:** Hotwire (Turbo + Stimulus) with TailwindCSS
- **Deployment:** Docker Compose with Caddy reverse proxy

## Contributing to Documentation

Documentation improvements are always welcome! When contributing:

1. **Keep it current:** Ensure documentation reflects the latest codebase
2. **Be specific:** Include code examples, commands, and expected outputs
3. **Stay organized:** Follow the existing structure and formatting
4. **Add context:** Explain not just what but why
5. **Test instructions:** Verify that steps work on a clean installation

### Documentation Standards

- Use clear, concise language
- Include code blocks with syntax highlighting
- Add diagrams for complex concepts
- Link to related sections and external resources
- Keep table of contents up to date
- Use consistent terminology across documents

## Getting Help

If you encounter issues or have questions:

1. Check the [Troubleshooting](../README.md#troubleshooting) section
2. Review the [Architecture Documentation](ARCHITECTURE.md) for technical details
3. Search existing [GitHub Issues](https://github.com/nosia-ai/nosia/issues)
4. Open a new issue with detailed information about your problem

## License

Nosia is open source software. See [LICENSE](../LICENSE) for details.

## Additional Resources

- **Website:** [nosia.ai](https://nosia.ai/)
- **Online Guides:** [guides.nosia.ai](https://guides.nosia.ai/)
- **GitHub Repository:** [github.com/nosia-ai/nosia](https://github.com/nosia-ai/nosia)
- **Docker Hub:** AI models available at [hub.docker.com/u/ai](https://hub.docker.com/u/ai)
