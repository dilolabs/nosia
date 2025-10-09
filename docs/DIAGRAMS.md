# Nosia System Diagrams

This document contains ASCII diagrams that complement the [ARCHITECTURE.md](ARCHITECTURE.md) documentation.

## Full System Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         NOSIA PLATFORM                               │
└──────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                          CLIENT LAYER                               │
├─────────────────────────────────────────────────────────────────────┤
│  Web Browser  │  OpenAI Client  │  cURL/API Client  │  Mobile App   │
└────────┬──────┴────────┬────────┴────────┬──────────┴──────┬────────┘
         │               │                 │                 │
         │               │                 │                 │
         └───────────────┴─────────────────┴─────────────────┘
                                  │
                                  ▼
         ┌────────────────────────────────────────────────┐
         │         Caddy Reverse Proxy (HTTPS)            │
         │     Auto SSL/TLS Certificate Management        │
         └────────────────────┬───────────────────────────┘
                              │
         ┌────────────────────┴───────────────────────┐
         │                                            │
         ▼                                            ▼
┌──────────────────┐                        ┌──────────────────┐
│   Rails Web      │◄──────(shared DB)──────┤  Solid Queue     │
│   Application    │                        │  Workers         │
├──────────────────┤                        ├──────────────────┤
│ • Controllers    │                        │ • real_time      │
│ • Views          │                        │ • background     │
│ • API Endpoints  │                        │ • default        │
│ • Action Cable   │                        │                  │
│ • Real-time UI   │                        │ Job Types:       │
│                  │                        │ • AddDocument    │
│ Puma + Thruster  │                        │ • AddText        │
└────────┬─────────┘                        │ • ChatResponse   │
         │                                  │ • CrawlWebsite   │
         │                                  └────────┬─────────┘
         │                                           │
         └───────────────────┬───────────────────────┘
                             │
                             ▼
┌───────────────────────────────────────────────────────────────┐
│                    PostgreSQL 16 + pgvector                   │
├───────────────────────────────────────────────────────────────┤
│  Primary DB      │  Cache DB       │  Queue DB    │  Cable DB │
│  • accounts      │  • cache_*      │  • jobs      │  • cable  │
│  • users         │                 │  • processes │           │
│  • documents     │                 │              │           │
│  • chunks        │                 │              │           │
│  • chats         │                 │              │           │
│  • messages      │                 │              │           │
│                  │                 │              │           │
│  Vector Index:   │                 │              │           │
│  • embedding     │                 │              │           │
│    (768 dims)    │                 │              │           │
└────────┬──────────────────────────────────────────────────────┘
         │
         │ (External API calls for AI operations)
         │
         ▼
┌───────────────────────────────────────────────────────────────┐
│                    AI Model Services                          │
├───────────────────────────────────────────────────────────────┤
│  LLM Service          │  Embedding Service                    │
│  • Chat Completions   │  • Vector Generation                  │
│  • Streaming          │  • Semantic Search                    │
│  • Configurable       │  • Configurable Dimensions            │
│                       │                                       │
│  Examples:            │  Examples:                            │
│  • Docker DMR         │  • ai/mistral                         │
│  • Ollama             │  • ai/granite-embedding-multilingual  │
│  • OpenAI             │  • bge-m3:567m                        │
│  • Any compatible     │  • nomic-embed-text                   │
└───────────────────────────────────────────────────────────────┘
```

## RAG Pipeline Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                    INDEXING PIPELINE                             │
└──────────────────────────────────────────────────────────────────┘

    ┌─────────┐
    │ Upload  │
    │Document │
    └────┬────┘
         │
         ▼
    ┌─────────────┐
    │   Parse     │
    │  Content    │
    └────┬────────┘
         │
         ▼
    ┌──────────────────────────────────────┐
    │      3-Phase Chunking Strategy       │
    ├──────────────────────────────────────┤
    │ 1. Structural Split                  │
    │    • Divide by headers               │
    │    • Maintain hierarchy              │
    │                                      │
    │ 2. Token Refinement                  │
    │    • Split oversized chunks          │
    │    • Respect boundaries              │
    │                                      │
    │ 3. Merge Optimization                │
    │    • Combine small chunks            │
    │    • Same section only               │
    └────┬─────────────────────────────────┘
         │
         ▼
    ┌─────────────┐         ┌──────────────┐
    │  Generate   │────────▶│  Chunk       │
    │  Embeddings │         │  Metadata    │
    └────┬────────┘         └──────────────┘
         │                   • keywords
         │                   • section_path
         │                   • content_type
         │                   • token_count
         ▼
    ┌─────────────┐
    │   Store in  │
    │  Database   │
    │ (pgvector)  │
    └─────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                    RETRIEVAL PIPELINE                            │
└──────────────────────────────────────────────────────────────────┘

    ┌─────────┐
    │  User   │
    │  Query  │
    └────┬────┘
         │
         ▼
    ┌──────────────┐
    │   Generate   │
    │    Query     │
    │  Embedding   │
    └────┬─────────┘
         │
         ▼
    ┌──────────────────────┐
    │  Vector Similarity   │
    │  Search (Cosine)     │
    │  Top K Chunks        │
    └────┬─────────────────┘
         │
         ▼
    ┌──────────────────────┐
    │  Context Relevance   │
    │  Filter (LLM Guard)  │
    │  Validate Each Chunk │
    └────┬─────────────────┘
         │
         │  ┌──────────────┐
         └─▶│  Relevant    │
            │  Chunks      │
            └──────┬───────┘
                   │
                   ▼
         ┌─────────────────┐
         │  Build Augmented│
         │     Prompt      │
         └─────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                    GENERATION PIPELINE                           │
└──────────────────────────────────────────────────────────────────┘

    ┌────────────────┐
    │  Augmented     │
    │  Prompt        │
    │                │
    │ <context>      │
    │  {chunks}      │
    │ </context>     │
    │ {question}     │
    └────┬───────────┘
         │
         ▼
    ┌──────────────────┐
    │   LLM Service    │
    │   Completion     │
    │   (Streaming)    │
    └────┬─────────────┘
         │
         ▼
    ┌──────────────────┐
    │ Answer Relevance │
    │ Validation       │
    │ (LLM Guard)      │
    └────┬─────────────┘
         │
         ├─── Pass ───▶ Return Response
         │
         └─── Fail ───▶ Fallback Message
```

## Data Model Relationships

```
┌──────────────────────────────────────────────────────────────────┐
│                      CORE ENTITIES                               │
└──────────────────────────────────────────────────────────────────┘

    ┌─────────────┐
    │   Account   │
    │  (Tenant)   │
    └──────┬──────┘
           │
           │ owns
           │
    ┌──────┴───────────────────────────────────┐
    │                                          │
    ▼                                          ▼
┌────────┐                              ┌──────────┐
│  User  │                              │  Chunks  │
└───┬────┘                              └────┬─────┘
    │                                        │
    │ creates                                │ belongs to
    │                                        │
    ▼                                        ▼
┌─────────┐                         ┌────────────────┐
│  Chat   │                         │   Chunkable    │
└────┬────┘                         │  (Polymorphic) │
     │                              └────────┬───────┘
     │ has many                              │
     │                                       │ can be
     ▼                           ┌───────────┼──────────────┐
┌──────────┐                     │           │              │
│ Messages │                     ▼           ▼              ▼
└──────────┘              ┌──────────┐  ┌────────┐  ┌──────────┐
     │                    │ Document │  │  Text  │  │ Website  │
     │ references         └──────────┘  └────────┘  └──────────┘
     │                          │             │            │
     └──────────────────────────┴─────────────┴────────────┘
                                      │
                                      │ all have
                                      ▼
                              ┌───────────────┐
                              │  Attachments  │
                              │   (Active     │
                              │   Storage)    │
                              └───────────────┘
```

---

These diagrams complement the detailed explanations in [ARCHITECTURE.md](ARCHITECTURE.md) and provide
visual reference for understanding Nosia's system design.
