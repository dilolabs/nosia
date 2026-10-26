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
│ Puma (port 3000) │                        │ • AddText        │
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
│  • Tool Calling       │  • Configurable Dimensions            │
│                       │                                       │
│  Examples:            │  Examples:                            │
│  • Docker DMR         │  • ai/mistral                         │
│  • Ollama             │  • ai/granite-embedding-multilingual  │
│  • OpenAI             │  • bge-m3:567m                        │
│  • Any compatible     │  • nomic-embed-text                   │
└───────────────────────────────────────────────────────────────┘
         ▲
         │ (MCP connections for external tools)
         │
┌───────────────────────────────────────────────────────────────┐
│                    MCP Server Ecosystem                       │
├───────────────────────────────────────────────────────────────┤
│  External Services    │  Custom Integrations                  │
│  • Calendar APIs      │  • Database Access                    │
│  • File Storage       │  • Custom Tools                       │
│  • Chat Platforms     │  • Automation Scripts                 │
│  • GitHub             │  • Internal APIs                      │
└───────────────────────────────────────────────────────────────┘
```

## Signed-in Dashboard Entry Points

```text
Authenticated /
  ├─ Inline composer → existing chat create → saved conversation
  ├─ Usage overview → global /token_usage (current memberships)
  ├─ Eight labeled shortcuts → existing tool/directory routes
  └─ Your five recent root chats → your saved conversation

Composer account selection ≠ default tool account ≠ aggregate report scope
```

Recent conversation content remains personal. Usage is account-wide across
current memberships. Explicit account reports stay scoped to their URL account.
See [Signed-in dashboard](dashboard.md) for dates, empty states, and verification.

## Account Experience Entry Points

```text
Accounts index (current memberships)
  └─ Account hub (explicit authorized account)
       ├─ New conversation → existing composer with account_id
       ├─ Sources → documents / texts / Q&As / websites
       ├─ Your history → your saved chat
       ├─ Usage → account-wide reporting
       ├─ Your API tokens → your tokens ∩ this account
       ├─ Shared prompt → member read / owner edit
       └─ Details + users → owner-only administration
```

The URL carries account context, not a global preference. Membership is rechecked
on subsequent requests; conversation history and tokens remain personal even for
owners. See [Account experience](account-experience.md) for boundaries and
verification limits.

## Sources Workspace Entry Points

```text
/sources (default account)       /accounts/:account_id/sources (URL account)
          \                                  /
           +-- type + status + query + sort --+
                           |
                 50-row list + Load more
                 |                 |
        existing dropzone     title -> detail -> edit
        browse/drop/retry          |               |
                 |             Retry/Delete    Save/Cancel
                 +---------- existing CRUD/jobs ---+
                                      |
                     localized row + seven count targets

Legacy new: membership filing picker; scoped new: fixed URL account
All edit: fixed record account; neither changes the default account
```

Upload completion and indexing are different states. Live row replacement does
not continuously re-sort or re-filter a loaded page, and searched lists do not
promise live prepends. Reading workspace pages does not enqueue processing.
See [Sources workspace](sources-workspace.md) for navigation, safety, and
verification boundaries.

## Token Usage Workspace

```text
/token_usage                         /accounts/:account_id/token_usage
current memberships                 current URL-account membership
       |                                         |
30 local dates + lifetime counters  lifetime counters + existing rolling query
       \                                         /
        +-- overview / static trend / daily table --+
        |          secondary context + estimates   |
        +-- lifetime model/type details + method --+

Scoped lifetime fragments: locale + account + counters + version + section
Recent chart/table/date labels: outside lifetime fragments
Dashboard overview: existing independent presentation, unchanged
```

Global and account recent periods deliberately remain different. All supplied
account date buckets are preserved; neither route changes the default account.
See [Token usage workspace](token-usage-workspace.md) for scope and limitations.

## Agent Skills Workspace Entry Points

```text
Settings -> /agent_skills (default account)
Account hub -> /accounts/:account_id/agent_skills (authorized URL account)
                              |
                     Structured rows + counts
                       |       |        |
                    Create   View     Enable/Disable
                       |       |        |
                       |   Full details + saved raw SKILL.md
                       |       |                     |
                       +---- Edit                Confirm Delete
                              |                     |
                  Source + Behavior + Advanced     Existing execution cleanup
                              |                     |
                   Save -> same-context list <-----+
                   422 -> retained form + linked errors
```

URL account context is not a global preference. Enabled is not verified execution;
source parsing, runtime behavior and API contracts remain unchanged. See
[Agent skills workspace](agent-skills-workspace.md) for compatibility limits.

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
    ┌──────────────────┐      ┌─────────────────┐
    │   LLM Service    │ ◄────┤  MCP Tools      │
    │   Completion     │      │  (if enabled)   │
    │   (Streaming)    │      └─────────────────┘
    └────┬─────────────┘
         │
         ├─── Tool Call? ──▶ ┌───────────────┐
         │                   │ Execute MCP   │
         │                   │ Tool          │
         │ ◄─── Result ──────┴───────────────┘
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

## MCP Integration Flow

```
┌──────────────────────────────────────────────────────────────────┐
│              MODEL CONTEXT PROTOCOL (MCP) FLOW                   │
└──────────────────────────────────────────────────────────────────┘

    ┌─────────────┐
    │ User Query  │
    └──────┬──────┘
           │
           ▼
    ┌──────────────────┐
    │ Chat with MCP    │
    │ Servers Enabled  │
    └──────┬───────────┘
           │
           ▼
    ┌──────────────────┐         ┌─────────────────┐
    │ Load Available   │────────▶│  MCP Servers    │
    │ Tools            │         │  • Calendar     │
    └──────┬───────────┘         │  • File Storage │
           │                     │  • GitHub       │
           │                     │  • Custom       │
           ▼                     └─────────────────┘
    ┌──────────────────┐
    │ LLM with Tools   │
    │ + RAG Context    │
    └──────┬───────────┘
           │
           ├──── No Tool Needed ────▶ Standard RAG Response
           │
           └──── Tool Needed ─────┐
                                  │
                                  ▼
                         ┌────────────────┐
                         │  Select Tool   │
                         │  from MCP      │
                         └────────┬───────┘
                                  │
                                  ▼
                         ┌────────────────┐
                         │  MCP Server    │
                         │  Execute Tool  │
                         │  • stdio       │
                         │  • streamable  │
                         │  • sse         │
                         └────────┬───────┘
                                  │
                                  ▼
                         ┌────────────────┐
                         │  Tool Result   │
                         │  (JSON data)   │
                         └────────┬───────┘
                                  │
                                  ▼
                         ┌────────────────┐
                         │  LLM Processes │
                         │  Result        │
                         └────────┬───────┘
                                  │
                                  ├─── More Tools? ──┐
                                  │                  │
                                  │  Yes ────────────┘
                                  │
                                  │  No
                                  ▼
                         ┌────────────────┐
                         │ Final Response │
                         │ to User        │
                         └────────────────┘
```

## MCP Server Types

```
┌──────────────────────────────────────────────────────────────────┐
│                    MCP TRANSPORT TYPES                           │
└──────────────────────────────────────────────────────────────────┘

┌─────────────────┐
│  STDIO          │  Local process communication
├─────────────────┤
│ Nosia           │  ┌─────────────────────┐
│   ↓             │  │ npx mcp-server      │
│ stdin/stdout ←──┼─▶│ (Node.js process)   │
│                 │  └─────────────────────┘
│ Examples:       │
│ • npm packages  │
│ • Python CLIs   │
└─────────────────┘

┌─────────────────┐
│  STREAMABLE     │  HTTP streaming connections
├─────────────────┤
│ Nosia           │  ┌─────────────────────┐
│   ↓             │  │ Remote MCP Server   │
│ HTTP POST   ────┼─▶│ https://api.com/mcp │
│   ↑             │  └─────────────────────┘
│ Response        │
│                 │
│ Examples:       │
│ • Cloud APIs    │
│ • Remote tools  │
└─────────────────┘

┌─────────────────┐
│  SSE            │  Server-Sent Events
├─────────────────┤
│ Nosia           │  ┌─────────────────────┐
│   ↓             │  │ SSE MCP Server      │
│ EventSource ────┼─▶│ Real-time updates   │
│   ↑             │  └─────────────────────┘
│ Events stream   │
│                 │
│ Examples:       │
│ • Live data     │
│ • Notifications │
└─────────────────┘
```

---

These diagrams complement the detailed explanations in [ARCHITECTURE.md](ARCHITECTURE.md) and provide
visual reference for understanding Nosia's system design, including the new Model Context Protocol integration.
