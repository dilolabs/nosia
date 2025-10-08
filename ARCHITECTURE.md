# Nosia Architecture Documentation

## Table of Contents

1. [System Overview](#system-overview)
2. [Core Components](#core-components)
3. [RAG (Retrieval Augmented Generation) Implementation](#rag-implementation)
4. [Embedding Strategy](#embedding-strategy)
5. [Document Processing Pipeline](#document-processing-pipeline)
6. [Chat Completion Flow](#chat-completion-flow)
7. [Database Schema](#database-schema)
8. [Background Jobs](#background-jobs)
9. [API Architecture](#api-architecture)
10. [Security & Multi-tenancy](#security--multi-tenancy)
11. [Deployment Architecture](#deployment-architecture)

---

## System Overview

Nosia is a self-hosted Retrieval Augmented Generation (RAG) platform built on Rails 8 that enables users to run AI models on their own data. The system provides OpenAI-compatible APIs for chat completions while maintaining complete data privacy and control.

### Key Features

- **RAG-based Chat Completions**: Augments LLM responses with relevant context from user documents
- **Multi-source Document Ingestion**: Supports PDFs, text files, websites, and Q&A pairs
- **Vector Similarity Search**: Uses pgvector for efficient semantic search
- **OpenAI-Compatible API**: Drop-in replacement for OpenAI API clients
- **Real-time Streaming**: Server-sent events for streaming responses
- **Multi-tenancy**: Account-based isolation for secure data separation
- **Background Processing**: Async document processing and embedding generation

### Technology Stack

- **Backend**: Ruby on Rails 8.0
- **Database**: PostgreSQL 16 with pgvector extension
- **Vector Search**: pgvector with cosine similarity
- **Background Jobs**: Solid Queue (database-backed)
- **Real-time**: Action Cable with enhanced PostgreSQL adapter
- **AI Integration**: RubyLLM gem for OpenAI-compatible model access
- **Frontend**: Hotwire (Turbo + Stimulus) with TailwindCSS
- **Deployment**: Docker Compose with Caddy reverse proxy

---

## Core Components

### 1. Models Layer

#### Account
- Multi-tenant isolation boundary
- Contains users, documents, chunks, and chats
- Owner-based access control

#### Document Sources
- **Document**: File uploads (PDF, text, etc.)
- **Text**: Direct text input
- **Website**: Web pages (with crawling)
- **QnA**: Question-answer pairs

All sources implement the `Chunkable` concern for uniform processing.

#### Chunk
The fundamental unit of retrievable knowledge:
- **Content**: Text segment from source document
- **Embedding**: Vector representation (default: 768 dimensions)
- **Metadata**: Enriched information (headers, keywords, context)
- **Chunkable**: Polymorphic relationship to source

#### Chat & Message
- **Chat**: Conversation container with message history
- **Message**: Individual turn (user or assistant)
- Uses RubyLLM's `acts_as_chat` for conversation management

### 2. Concerns Architecture

Nosia uses Rails concerns for modular, composable behavior:

#### Chunk Concerns
- **`Vectorizable`**: Embedding generation and similarity search
- **`Enrichable`**: Metadata enhancement (titles, summaries, keywords)

#### Chat Concerns
- **`Completionable`**: Main chat completion orchestration
- **`SimilaritySearch`**: Retrieval of relevant chunks
- **`AugmentedPrompt`**: Context injection into prompts
- **`ContextRelevance`**: Validates chunk relevance to query
- **`AnswerRelevance`**: Validates answer quality

#### Source Concerns
- **`Chunkable`**: Document-to-chunk transformation
- **`Parsable`**: Content extraction from files
- **`Crawlable`**: Web content fetching

---

## RAG Implementation

Nosia implements a sophisticated RAG pipeline with multiple quality gates:

### 1. Indexing Phase

```
Document Upload → Parse Content → Chunking → Embedding → Store
```

**Chunking Strategy** (3-phase approach):
1. **Structural Split**: Divide by document structure (headers, paragraphs)
2. **Token Refinement**: Split oversized chunks, respecting token limits
3. **Merge Optimization**: Combine undersized consecutive chunks

**Key Features**:
- Header hierarchy preservation
- Code block awareness
- Configurable token limits (CHUNK_MAX_TOKENS, CHUNK_MIN_TOKENS)
- Metadata enrichment (keywords, content type, section path)

### 2. Retrieval Phase

```
User Query → Generate Query Embedding → Similarity Search → Context Filtering
```

**Similarity Search** (`Chunk::Vectorizable`):
- Uses pgvector's cosine similarity
- Configurable retrieval count (RETRIEVAL_FETCH_K)
- Returns nearest neighbors by vector distance

**Context Relevance Filtering** (`Chat::ContextRelevance`):
- LLM-based validation of chunk relevance
- Filters false positives from similarity search
- Uses guard model or main LLM

### 3. Generation Phase

```
Query + Retrieved Chunks → Augmented Prompt → LLM Completion → Answer Validation
```

**Augmented Prompt Structure**:
```
<context>
{chunk1_content}

{chunk2_content}

{chunk3_content}
</context>
{user_question}
```

**Answer Relevance Validation** (`Chat::AnswerRelevance`):
- Post-generation quality check
- Ensures answer addresses the question
- Fallback message if validation fails

### 4. RAG Flow Diagram

```
┌─────────────┐
│ User Query  │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│ Generate Embedding  │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Similarity Search   │
│ (pgvector cosine)   │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Context Relevance   │
│ Filter (LLM Guard)  │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Augment Prompt      │
│ with Context        │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ LLM Completion      │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Answer Relevance    │
│ Validation          │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Return Response     │
└─────────────────────┘
```

---

## Embedding Strategy

### Embedding Model Configuration

Nosia supports any OpenAI-compatible embedding model:

- **Default**: `ai/granite-embedding-multilingual` (768 dimensions)
- **Configuration**: Via `EMBEDDING_MODEL` and `EMBEDDING_DIMENSIONS`
- **Provider**: OpenAI-compatible API (Docker Model Runner, Ollama, Infomaniak, OpenAI, etc.)

### Embedding Generation

**When Embeddings Are Generated**:
- During chunk creation (after document processing)
- Triggered by `before_save` callback if content changes
- Automatic via `Chunk::Vectorizable` concern

**Process** (`generate_embedding` method):
1. Check if content has changed
2. Call embedding API with configured model
3. Store resulting vector in `embedding` column
4. Handle errors gracefully (log and abort save)

### Vector Storage

**Database Schema**:
```ruby
t.vector "embedding", limit: 768  # Configurable via EMBEDDING_DIMENSIONS
```

**Indexing**:
- pgvector extension enabled
- Uses `has_neighbors` from neighbor gem
- Cosine distance for similarity calculation

### Similarity Search

**Query Process**:
```ruby
Chunk.search_by_similarity(query_text, limit: 3)
```

1. Generate query embedding using same model
2. Use `nearest_neighbors` with cosine distance
3. Return top K chunks (configurable)

**Performance Considerations**:
- Indexed vector column for fast similarity search
- Account-scoped queries for multi-tenancy
- Configurable retrieval limit balances quality vs. performance

### Augmented Context Option

When `AUGMENTED_CONTEXT=true`:
- Uses enriched chunk context instead of raw content
- Includes metadata like headers, summaries, keywords
- Provides more context for relevance checking

---

## Document Processing Pipeline

### 1. Upload & Validation

```
User Upload → File Attachment → Validation → Job Enqueue
```

**Supported Sources**:
- Documents: PDF, TXT, MD (via Active Storage)
- Text: Direct text input
- Website: URL crawling
- Q&A: Pre-formatted question-answer pairs

### 2. Content Extraction

**Document Parsing** (`Document::Parsable`):
- PDF: Text extraction with pdf-reader gem
- Optional: Docling serve integration for advanced parsing
- Metadata extraction (title, author, page count)

**Website Crawling** (`Website::Crawlable`):
- HTTP fetch with Faraday
- HTML parsing
- Link extraction for multi-page crawling

### 3. Chunking Algorithm

**Phase 1: Structural Splitting**
```ruby
split_by_structure_with_hierarchy(content, metadata)
```
- Identifies markdown headers (# to ######)
- Maintains header hierarchy stack
- Preserves document structure
- Tracks section paths ("Introduction > Background > History")

**Phase 2: Token-Based Refinement**
```ruby
split_oversized_chunks(structural_chunks)
```
- Calculates token count (rough estimate: text.size / 3)
- Splits chunks exceeding CHUNK_MAX_TOKENS
- Respects paragraph boundaries
- Falls back to sentence splitting for large paragraphs

**Phase 3: Merge Optimization**
```ruby
merge_small_chunks(refined_chunks)
```
- Combines consecutive chunks below CHUNK_MIN_TOKENS
- Only merges within same section (same header path)
- Ensures merged chunks don't exceed CHUNK_MAX_TOKENS
- Configurable via CHUNK_MERGE_PEERS flag

**Chunk Metadata**:
```json
{
  "chunk_index": 0,
  "total_chunks": 15,
  "header_hierarchy": ["Introduction", "Background"],
  "section_path": "Introduction > Background",
  "keywords": ["embedding", "vector", "search"],
  "content_type": ["text", "code"],
  "token_count": 342
}
```

### 4. Embedding Generation

For each chunk:
1. Generate embedding via RubyLLM
2. Store vector in database
3. Handle errors and retry logic

### 5. Background Processing

All heavy processing happens asynchronously:

**AddDocumentJob**:
```ruby
document.titlize!   # Extract title
document.parse!     # Extract content
document.chunkify!  # Create chunks (triggers embedding generation)
```

**Job Queues**:
- `background`: Document processing (2 threads, 5s polling)
- `real_time`: Chat responses (5 threads, 0.1s polling)

---

## Chat Completion Flow

### 1. API Request

**Endpoint**: `POST /v1/chat/completions`

**Request Format** (OpenAI-compatible):
```json
{
  "model": "ai/mistral",
  "messages": [
    {"role": "user", "content": "What is RAG?"}
  ],
  "stream": true,
  "temperature": 0.1
}
```

### 2. Chat Creation

1. Create Chat instance for user/account
2. Populate conversation history from messages array
3. Extract last message as current query

### 3. RAG Pipeline Execution

**In `Chat::Completionable#complete_with_nosia`**:

```ruby
def complete_with_nosia(question, model:, temperature:, ...)
  # 1. Configure LLM
  self.with_model(model, provider: :openai)
  self.with_temperature(temperature)
  self.with_instructions(system_prompt)
  
  # 2. Retrieve relevant chunks
  chunks = self.similarity_search(question)
  
  # 3. Augment prompt if chunks found
  question = self.augmented_prompt(question, chunks:) if chunks.any?
  
  # 4. Stream completion
  self.ask(question) do |chunk|
    yield chunk  # Stream to client
  end
  
  # 5. Validate answer
  message = self.messages.last
  if !self.answer_relevance(message.content, question:)
    message.update(content: "I'm sorry, but I couldn't find relevant information...")
  end
  
  message
end
```

### 4. Response Streaming

**Streaming Enabled** (`stream: true`):
- Uses ActionController::Live
- Sends Server-Sent Events (SSE)
- Format: `data: {json}\n\n`
- Broadcasts chunk-by-chunk via Action Cable

**Non-Streaming** (`stream: false`):
- Waits for complete response
- Returns full JSON response

### 5. Real-time Updates

**Action Cable Integration**:
- Broadcasts to chat-specific channel
- Updates UI in real-time (Turbo Streams)
- Supports multiple concurrent users

---

## Database Schema

### Core Tables

#### accounts
```sql
- id: bigint (primary key)
- name: string
- owner_id: bigint (references users)
- uid: string
- created_at, updated_at
```

#### users
```sql
- id: bigint (primary key)
- email: string
- name: string
- password_digest: string (bcrypt)
- admin: boolean
- created_at, updated_at
```

#### chunks
```sql
- id: bigint (primary key)
- chunkable_id: bigint (polymorphic)
- chunkable_type: string (polymorphic)
- account_id: bigint (tenant isolation)
- content: text
- embedding: vector(768) (configurable dimensions)
- metadata: jsonb (enriched data)
- created_at, updated_at

Indexes:
- account_id
- chunkable_type + chunkable_id
- embedding (vector similarity)
```

#### chats
```sql
- id: bigint (primary key)
- account_id: bigint
- user_id: bigint
- chat_id: bigint (for nested chats)
- model: string
- created_at, updated_at
```

#### messages
```sql
- id: bigint (primary key)
- chat_id: bigint
- role: integer (enum: user/assistant)
- content: string
- similar_chunk_ids: array (references chunks)
- done: boolean
- input_tokens, output_tokens: integer
- created_at, updated_at
```

#### documents
```sql
- id: bigint (primary key)
- account_id: bigint
- author_id: bigint
- title: string
- content: text
- metadata: jsonb
- created_at, updated_at
```

### Vector Extension

**pgvector Setup**:
```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

Enables:
- Vector data type
- Cosine, L2, and inner product distance functions
- Efficient similarity search with indexing

---

## Background Jobs

### Job Architecture

**Queue System**: Solid Queue (Rails 8 default)
- Database-backed (no Redis required)
- Persistent job storage
- Built-in retry logic
- Web UI via Mission Control

### Job Types

#### 1. AddDocumentJob
```ruby
queue_as :background
perform(document_id)
  - Extract title
  - Parse content
  - Generate chunks
  - Trigger embeddings
```

#### 2. AddTextJob
```ruby
queue_as :background
perform(text_id)
  - Process text input
  - Generate chunks
  - Create embeddings
```

#### 3. AddQnaJob
```ruby
queue_as :background
perform(qna_id)
  - Process Q&A pair
  - Generate chunks
  - Create embeddings
```

#### 4. CrawlWebsiteUrlJob
```ruby
queue_as :background
perform(website_id, url)
  - Fetch webpage
  - Parse HTML
  - Extract content
  - Generate chunks
```

#### 5. ChatResponseJob
```ruby
queue_as :real_time
perform(chat_id, content)
  - Execute RAG pipeline
  - Stream response
  - Update UI
```

### Queue Configuration

**Priority Queues** (solid_queue.yml):
- **real_time**: Chat responses (5 threads, 0.1s polling, 3 processes)
- **background**: Document processing (2 threads, 5s polling, 1 process)
- **default**: Other tasks (3 threads, 2s polling)

**Monitoring**:
- Mission Control Jobs at `/jobs`
- Admin-only access
- Job status, retries, failures

---

## API Architecture

### OpenAI-Compatible Endpoints

#### POST /v1/chat/completions
**Complete chat with RAG**

Request:
```json
{
  "model": "ai/mistral",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What is RAG?"}
  ],
  "temperature": 0.1,
  "max_tokens": 1024,
  "stream": false
}
```

Response:
```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "nosia:ai/mistral",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "RAG stands for Retrieval Augmented Generation..."
    },
    "finish_reason": "stop"
  }],
  "system_fingerprint": "fp_nosia"
}
```

#### GET /v1/models
**List available models**

Response:
```json
{
  "object": "list",
  "data": [
    {
      "id": "ai/mistral",
      "object": "model",
      "created": 1677652288,
      "owned_by": "nosia"
    }
  ]
}
```

### Document Upload Endpoints

#### POST /api/v1/files
Upload document for processing

#### POST /api/v1/texts
Submit text for indexing

#### POST /api/v1/websites
Add website URL for crawling

#### POST /api/v1/qnas
Add Q&A pairs

### Authentication

**API Token System**:
- Bearer token authentication
- Tokens managed at `/api_tokens`
- Account-scoped access
- Revocable tokens

**Header**:
```
Authorization: Bearer <token>
```

---

## Security & Multi-tenancy

### Account-Based Isolation

**ActsAsTenant** implementation:
- All queries scoped to current account
- Prevents cross-account data access
- Set via `Current.account` context

**Model Scoping**:
```ruby
class Chunk < ApplicationRecord
  belongs_to :account
  # All queries automatically scoped:
  # account.chunks.where(...)
end
```

### Authentication & Authorization

**Authentication** (bcrypt):
- Secure password hashing
- Session-based for web UI
- Token-based for API

**Authorization** (Pundit):
- Policy-based access control
- Resource-level permissions
- Admin role for system operations

### Data Security

**Environment Variables**:
- Secrets never committed to repo
- Validated at startup
- Production-specific requirements

**API Security**:
- Token-based authentication
- Rate limiting (TODO: recommended)
- CORS configuration for web clients

**Database Security**:
- Account-scoped queries prevent data leakage
- Polymorphic associations validated
- Foreign key constraints enforced

---

## Deployment Architecture

### Docker Compose Stack

```
┌─────────────────┐
│  Reverse Proxy  │  (Caddy)
│  Port 80/443    │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌────────┐
│  Web   │ │ SolidQ │
│ Rails  │ │ Worker │
└───┬────┘ └───┬────┘
    │          │
    └────┬─────┘
         ▼
┌─────────────────┐
│   PostgreSQL    │
│   + pgvector    │
└─────────────────┘
         ▲
         │
┌────────┴────────┐
│  LLM Service    │  (External)
│  Embedding API  │
└─────────────────┘
```

### Services

**reverse-proxy** (Caddy):
- HTTPS termination
- Automatic certificate management
- Request routing

**web** (Rails):
- Main application server
- Puma web server
- Thruster HTTP/2 proxy
- Health check endpoint: `/up`

**solidq** (Background Worker):
- Solid Queue processor
- Multiple queue workers
- Job execution and retry

**postgres-db**:
- PostgreSQL 16
- pgvector extension
- Vector similarity search
- Multiple databases (primary, cache, queue, cable)

**llm & embedding** (Docker AI):
- Model containers via Docker Hub AI
- OpenAI-compatible API
- Configurable model selection

### Environment Configuration

**Required Variables**:
- `DATABASE_URL`: PostgreSQL connection
- `SECRET_KEY_BASE`: Rails secret
- `AI_BASE_URL`: LLM API endpoint
- `LLM_MODEL`: Completion model
- `EMBEDDING_MODEL`: Embedding model
- `EMBEDDING_DIMENSIONS`: Vector size

**Optional Variables**:
- `AUGMENTED_CONTEXT`: Enhanced context flag
- `DOCLING_SERVE_BASE_URL`: Advanced document parsing
- `GUARD_MODEL`: Separate model for validation
- Chunking parameters (MAX_TOKENS, MIN_TOKENS, etc.)
- LLM parameters (TEMPERATURE, TOP_K, TOP_P, etc.)

### Scaling Considerations

**Horizontal Scaling**:
- Multiple web containers behind load balancer
- Multiple worker processes for background jobs
- Shared PostgreSQL database

**Vertical Scaling**:
- Increase worker threads per queue
- Adjust polling intervals
- Configure database connection pool

**Performance Optimization**:
- Redis caching layer (optional)
- CDN for static assets
- Database query optimization
- Vector index tuning

---

## Development Workflow

### Local Setup

```bash
# Clone repository
git clone https://github.com/nosia-ai/nosia.git
cd nosia

# Copy environment template
cp .env.example .env

# Edit configuration
vim .env

# Start services
docker compose up
```

### Database Setup

```bash
# Create databases
bin/rails db:create

# Run migrations
bin/rails db:migrate

# Seed data (optional)
bin/rails db:seed
```

### Running Tests

```bash
# Run all tests
bin/rails test

# Run specific test
bin/rails test test/models/chunk_test.rb

# Run system tests
bin/rails test:system
```

### Development Tools

- **Mailbin**: Email preview in development
- **Web Console**: In-browser debugging
- **Mission Control Jobs**: Job monitoring
- **RuboCop**: Code linting
- **Brakeman**: Security scanning

---

## Future Architecture Considerations

### Recommended Enhancements

1. **Caching Layer**
   - Redis for embedding cache
   - Frequently accessed chunks
   - Query result caching

2. **Advanced Chunking**
   - Semantic chunking with LLM
   - Recursive summarization for long documents
   - Chunk overlap for context continuity

3. **Enhanced Retrieval**
   - Hybrid search (vector + keyword)
   - Re-ranking with cross-encoder
   - Multi-query retrieval

4. **Monitoring & Observability**
   - APM integration (New Relic, Datadog)
   - Structured logging
   - Performance metrics
   - Quality metrics (relevance scores)

5. **Enterprise Features**
   - RBAC (role-based access control)
   - SSO integration
   - Audit logging
   - Data retention policies

---

## Conclusion

Nosia's architecture is designed for:
- **Privacy**: Self-hosted, full data control
- **Flexibility**: OpenAI-compatible API, any model
- **Quality**: Multi-stage RAG pipeline with validation
- **Scalability**: Background processing, queue management
- **Security**: Multi-tenant isolation, token authentication
- **Extensibility**: Modular concerns, clean separation

The system balances simplicity (Rails conventions, Docker Compose) with sophistication (RAG pipeline, vector search, real-time streaming) to provide a production-ready, self-hosted AI platform.
