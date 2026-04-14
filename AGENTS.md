# Nosia — Agent Guide

> This file is a **map**, not a manual. ~100 lines.
> Follow links for depth. Inspired by OpenAI Harness Engineering.

---

## Repository Purpose

Nosia is a self-hosted AI RAG + MCP Platform on Rails 8.
Users run AI models on private data. Privacy-first, OpenAI-compatible.

Stack: Ruby on Rails 8 · PostgreSQL 16 + pgvector · Solid Queue
       RubyLLM · Hotwire · Docker Compose · Caddy

---

## How to Work Here

1. Read this file — orient, then pull the relevant doc from `docs/`
2. For any change: write a plan (see Plans below), implement, verify
3. Run `bin/ci` before opening a PR (rubocop + full test suite)
4. If blocked: identify the missing capability, don't guess

---

## Knowledge Base

| Topic                     | File                        |
|---------------------------|-----------------------------|
| Architecture & domain map | `docs/ARCHITECTURE.md`      |
| System diagrams           | `docs/DIAGRAMS.md`          |
| Deployment guide          | `docs/DEPLOYMENT.md`        |
| Guiding principles        | `docs/PRINCIPLES.md`        |
| Quality scores by domain  | `docs/QUALITY.md`           |
| Design decisions log      | `docs/DECISIONS.md`         |
| Known technical debt      | `docs/DEBT.md`              |
| Active execution plans    | `docs/plans/active/`        |
| Completed plans           | `docs/plans/done/`          |
| MCP Catalog Configuration | `config/mcp_catalog.yml`   |
| Prompts Configuration     | `config/prompts.yml`       |

---

## Domain Map

app/
├── models/
│   ├── account.rb          # Multi-tenant isolation boundary
│   ├── chunk.rb            # Fundamental unit of retrievable knowledge
│   ├── chat.rb             # Conversation container (acts_as_chat)
│   ├── message.rb          # Individual turn + optional tool metadata
│   ├── mcp_server.rb       # MCP server configuration
│   ├── chat_mcp_session.rb # Links chats to MCP servers
│   └── sources/            # Document, Text, Website, QnA
│
├── concerns/
│   ├── chunk/
│   │   ├── vectorizable.rb        # Embedding generation + similarity search
│   │   ├── searchable.rb           # Vector similarity search
│   │   └── enrichable.rb          # Metadata enhancement
│   ├── chat/
│   │   ├── completionable.rb      # Main orchestration — START HERE
│   │   ├── similarity_search.rb   # Chunk retrieval
│   │   ├── augmented_prompt.rb    # Context injection into prompts
│   │   ├── context_relevance.rb   # LLM-based chunk validation gate
│   │   ├── answer_relevance.rb    # Answer quality gate
│   │   └── model_context_protocol.rb  # MCP — SINGLE entry point
│   └── source/
│       ├── chunkable.rb    # Document → chunks
│       ├── parsable.rb     # Content extraction
│       └── crawlable.rb    # Web fetching
│
├── jobs/          # ALL background work (Solid Queue only)
├── controllers/   # API v1 + web UI
└── views/         # Hotwire (Turbo + Stimulus)

---

## Architectural Invariants  ← CI-enforced, PR-blocking

1. Boundary parsing   — all external data parsed at entry (strong params / schema)
2. Concerns composable — no direct coupling between unrelated concerns
3. Chunk is the unit  — all retrievable knowledge lives in Chunk records
4. MCP via one door   — always Chat::ModelContextProtocol, nothing else
5. Structured logs    — always Rails.logger with structured payloads (LogQL-ready)
6. Jobs via SolidQueue — no raw threads, no Kernel#spawn
7. LLM via RubyLLM    — no raw HTTP to AI providers
8. EMBEDDING_DIMENSIONS constant — never hardcode a dimension number
9. Account isolation  — all queries scoped to current account via acts_as_tenant

---

## Plans

- Simple/ephemeral  → inline in the PR description
- Complex tasks     → docs/plans/active/YYYY-MM-DD-task-name.md
                      (goal · acceptance criteria · steps · decision log)
- On completion     → move to docs/plans/done/

---

## Tooling

| Command                  | Purpose                          |
|--------------------------|----------------------------------|
| bin/rails test           | Full test suite                  |
| bundle exec rubocop      | Style + custom architecture cops |
| bin/rails db:test:prepare test test:system | Full test suite with system tests |
| docker compose up        | Local stack                      |
| bin/rails console        | REPL for exploration             |
| bin/brakeman              | Security vulnerability scanner   |
| bin/importmap audit       | JavaScript dependency auditor    |

---

## Context Loading Order

1. This file (you are here)
2. docs/ARCHITECTURE.md  — domain understanding
3. docs/PRINCIPLES.md    — guiding principles and patterns
4. Task-specific doc from table above
5. Relevant model/concern source files

> "Give the agent a map, not a 1,000-page manual." — Ryan Lopopolo, OpenAI
