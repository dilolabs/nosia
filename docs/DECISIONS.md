# Design Decisions Log

This document records significant architectural and design decisions made during the development of Nosia. Each entry includes the decision, rationale, alternatives considered, and date.

## Decision Format

```markdown
## [YYYY-MM-DD] Decision Title

**Status**: Active / Deprecated / Revisited

**Context**: The problem or situation that led to this decision

**Decision**: What was chosen

**Rationale**: Why this option was selected

**Alternatives Considered**: Other options that were evaluated

**Consequences**: Implications and trade-offs

**Related**: Links to code, documentation, or issues
```

## Decisions

## [2025-09-01] Use PostgreSQL with pgvector instead of dedicated vector databases

**Status**: Active

**Context**: Need to store and search vector embeddings efficiently for RAG. Options included dedicated vector databases (Qdrant, Weaviate, Milvus) vs PostgreSQL with pgvector extension.

**Decision**: Use PostgreSQL 16 with pgvector extension

**Rationale**: 
- Simplifies architecture by using single database
- pgvector is production-ready and performant
- Avoids operational complexity of additional database
- Good Rails integration via ActiveRecord
- Cost-effective for self-hosted deployments

**Alternatives Considered**:
- Qdrant: Dedicated vector database, but adds complexity
- Weaviate: Feature-rich but heavier operational burden
- Milvus: High performance but complex setup

**Consequences**:
- ✅ Simplified deployment and operations
- ✅ Good performance for most use cases
- ⚠️ May need optimization for very large-scale deployments
- ⚠️ Limited advanced vector search features compared to dedicated DBs

**Related**: 
- `db/migrate/20240604194522_enable_vector_extension.rb`
- `app/models/chunk/searchable.rb`

## [2025-09-05] Use Solid Queue instead of Sidekiq/Redis

**Status**: Active

**Context**: Need background job processing. Options included Sidekiq (Redis), GoodJob (Postgres), Solid Queue (Postgres), and raw threads.

**Decision**: Use Solid Queue (Rails 8 default)

**Rationale**:
- No Redis dependency (simpler deployment)
- Database-backed persistence
- Built into Rails 8, good integration
- Mission Control Jobs UI for monitoring
- Suitable for Nosia's workload patterns

**Alternatives Considered**:
- Sidekiq: More mature, but requires Redis
- GoodJob: Similar to Solid Queue, but less feature-rich
- Raw threads: Too primitive, no persistence

**Consequences**:
- ✅ Simplified architecture (no Redis)
- ✅ Reliable job persistence
- ✅ Easy monitoring via Mission Control
- ⚠️ Less mature than Sidekiq
- ⚠️ May need scaling adjustments for high volume

**Related**:
- `config/solid_queue.yml`
- `app/jobs/*`

## [2025-09-10] Implement Model Context Protocol (MCP) Integration

**Status**: Active

**Context**: Need to extend AI capabilities beyond document retrieval. Options included custom tool integrations, LangChain tools, or Model Context Protocol.

**Decision**: Implement Model Context Protocol (MCP) via RubyLLM

**Rationale**:
- MCP is an emerging standard for AI tool integration
- RubyLLM provides clean Ruby interface
- Enables pre-built integrations (Infomaniak services)
- Flexible transport options (stdio, HTTP, SSE)
- Future-proof architecture

**Alternatives Considered**:
- Custom tool system: More control, but reinventing the wheel
- LangChain integration: Python-centric, complex Ruby integration
- Direct API calls: Too inflexible, no standardization

**Consequences**:
- ✅ Standardized tool integration
- ✅ Easy to add new tools and services
- ✅ Pre-built catalog of integrations
- ⚠️ Learning curve for MCP concepts
- ⚠️ Dependency on RubyLLM MCP implementation

**Related**:
- `app/models/mcp_server.rb`
- `app/models/chat/model_context_protocol.rb`
- `lib/mcp_catalog.rb`
- `config/mcp_catalog.yml`

## [2025-09-15] Use Hotwire (Turbo + Stimulus) instead of React/Vue

**Status**: Active

**Context**: Need modern, interactive web UI. Options included React, Vue, Svelte, or Hotwire (Turbo + Stimulus).

**Decision**: Use Hotwire (Turbo + Stimulus)

**Rationale**:
- Aligns with Rails philosophy (convention over configuration)
- Simpler architecture (server-rendered HTML with enhancements)
- Better integration with Rails controllers and models
- Less JavaScript complexity
- Easier to maintain for Rails developers

**Alternatives Considered**:
- React: More flexible, but complex build pipeline
- Vue: Lighter than React, but still SPA complexity
- Svelte: Interesting, but smaller ecosystem

**Consequences**:
- ✅ Faster development for Rails team
- ✅ Simpler deployment (no Node.js build step)
- ✅ Better SEO (server-rendered)
- ⚠️ Less flexible for complex interactive components
- ⚠️ Smaller ecosystem than React/Vue

**Related**:
- `app/javascript/controllers/*`
- `app/views/*`

## [2025-09-20] Implement Guard Models for Quality Control

**Status**: Active

**Context**: Need to ensure RAG response quality. Options included no validation, simple heuristics, or separate guard models.

**Decision**: Implement separate guard models for context and answer relevance

**Rationale**:
- Improves response quality and reliability
- Prevents hallucinations and off-topic answers
- Configurable via environment variables
- Can use smaller, faster models for validation
- Provides safety net for production use

**Alternatives Considered**:
- No validation: Too risky for production
- Simple heuristics: Not reliable enough
- Single model for all tasks: Less specialized

**Consequences**:
- ✅ Better response quality
- ✅ Configurable safety levels
- ✅ Prevents poor-quality responses
- ⚠️ Additional API calls (cost and latency)
- ⚠️ More complex configuration

**Related**:
- `app/models/chat/context_relevance.rb`
- `app/models/chat/answer_relevance.rb`
- `config/prompts.yml` (guard prompts)

## [2025-09-25] Use Baran for Text Splitting

**Status**: Active

**Context**: Need to split documents into chunks for embedding. Options included custom implementation, LangChain text splitters, or Baran gem.

**Decision**: Use Baran gem for text splitting

**Rationale**:
- Ruby-native implementation
- Good performance
- Configurable chunking strategies
- Handles multiple document formats well
- Active maintenance

**Alternatives Considered**:
- Custom implementation: More control, but reinventing the wheel
- LangChain splitters: Python-centric, complex integration

**Consequences**:
- ✅ Reliable chunking
- ✅ Configurable via environment variables
- ✅ Handles various document structures
- ⚠️ Dependency on external gem
- ⚠️ May need customization for specific formats

**Related**:
- `app/models/document/chunkable.rb`
- `app/models/text/chunkable.rb`
- `app/models/website/chunkable.rb`
- `app/models/qna/chunkable.rb`

## [2025-10-01] Implement OpenAI-Compatible API

**Status**: Active

**Context**: Need API for client applications. Options included custom API design or OpenAI-compatible endpoints.

**Decision**: Implement OpenAI-compatible API

**Rationale**:
- Allows use of existing OpenAI client libraries
- Easier migration from OpenAI to Nosia
- Familiar interface for developers
- Reduces client-side changes
- Future-proof as standard evolves

**Alternatives Considered**:
- Custom API design: More flexibility, but higher adoption barrier
- Hybrid approach: Both custom and OpenAI-compatible endpoints

**Consequences**:
- ✅ Easy adoption for existing OpenAI users
- ✅ Works with existing client libraries
- ✅ Familiar developer experience
- ⚠️ Constrained by OpenAI API design choices
- ⚠️ May need to handle OpenAI-specific features

**Related**:
- `app/controllers/api/v1/completions_controller.rb`
- `app/controllers/api/v1/models_controller.rb`

## [2025-10-05] Use RubyLLM for LLM Integration

**Status**: Active

**Context**: Need to integrate with various LLM providers. Options included direct API calls, custom wrapper, or RubyLLM gem.

**Decision**: Use RubyLLM gem

**Rationale**:
- Unified interface for multiple providers
- Handles streaming, retries, error handling
- Supports OpenAI-compatible APIs
- MCP integration built-in
- Active development and maintenance

**Alternatives Considered**:
- Direct API calls: More control, but more code to maintain
- Custom wrapper: Flexible, but reinventing the wheel

**Consequences**:
- ✅ Simplified LLM integration
- ✅ Easy to switch providers
- ✅ Built-in streaming support
- ⚠️ Dependency on external gem
- ⚠️ May need workarounds for provider-specific features

**Related**:
- `config/initializers/ruby_llm.rb`
- `app/models/chat/completionable.rb`
- `app/models/chunk/vectorizable.rb`

## [2025-10-10] Implement Multi-tenancy with ActsAsTenant

**Status**: Active

**Context**: Need to isolate data between accounts. Options included custom scoping, ActsAsTenant gem, or database-level schemas.

**Decision**: Use ActsAsTenant gem for multi-tenancy

**Rationale**:
- Proven solution for Rails multi-tenancy
- Automatic query scoping
- Easy to implement and maintain
- Good performance
- Flexible configuration

**Alternatives Considered**:
- Custom scoping: More control, but error-prone
- Database schemas: Strong isolation, but complex migrations

**Consequences**:
- ✅ Reliable data isolation
- ✅ Automatic query scoping
- ✅ Easy to implement
- ⚠️ Need to ensure all queries are properly scoped
- ⚠️ Some complexity in model associations

**Related**:
- `app/models/account.rb`
- `app/models/current.rb`
- Various model associations

## [2025-10-15] Use Docker Compose for Local Development

**Status**: Active

**Context**: Need consistent development environment. Options included manual setup, Vagrant, or Docker Compose.

**Decision**: Use Docker Compose for local development

**Rationale**:
- Consistent environment across developers
- Easy to set up and tear down
- Includes all dependencies (Postgres, etc.)
- Close to production environment
- Good for CI/CD integration

**Alternatives Considered**:
- Manual setup: More flexible, but inconsistent
- Vagrant: Virtual machine approach, heavier

**Consequences**:
- ✅ Consistent development environment
- ✅ Easy onboarding for new developers
- ✅ Close to production setup
- ⚠️ Slightly more complex than manual setup
- ⚠️ Resource overhead

**Related**:
- `docker-compose.yml`
- `Dockerfile`
- Development setup documentation

## Future Decisions to Consider

### [TBD] Add Redis Caching Layer
**Context**: Improve performance for frequent queries
**Options**: Redis, Memcached, or no caching
**Considerations**: Complexity vs performance gain

### [TBD] Implement Hybrid Search
**Context**: Improve retrieval quality
**Options**: Vector + keyword search combination
**Considerations**: Complexity vs accuracy improvement

### [TBD] Add Rate Limiting
**Context**: Protect API from abuse
**Options**: Rack::Attack, custom middleware, or API gateway
**Considerations**: User experience vs protection

### [TBD] Implement Semantic Chunking
**Context**: Improve document splitting quality
**Options**: LLM-based chunking, custom algorithms
**Considerations**: Performance vs quality improvement

### [TBD] Add Multi-Factor Authentication
**Context**: Improve security
**Options**: TOTP, WebAuthn, or email-based MFA
**Considerations**: Security vs user convenience

## Decision Making Process

1. **Identify the problem**: Clearly define what needs to be decided
2. **Gather context**: Understand requirements and constraints
3. **Explore alternatives**: Research available options
4. **Evaluate trade-offs**: Consider pros and cons of each option
5. **Make decision**: Choose the best option for current needs
6. **Document**: Record the decision in this log
7. **Implement**: Write code and tests
8. **Review**: Assess the decision after implementation

## Revisiting Decisions

Decisions should be revisited when:
- New information becomes available
- Requirements change significantly
- Technology landscape evolves
- Performance or scalability issues arise
- Maintenance burden becomes too high

When revisiting, update the status and add a new entry if the decision changes significantly.