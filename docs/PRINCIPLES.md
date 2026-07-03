# Nosia — Guiding Principles

> Grounded in [The Rails Doctrine](https://rubyonrails.org/doctrine) by DHH  
> and [Vanilla Rails is Plenty](https://dev.37signals.com/vanilla-rails-is-plenty/) by 37signals.  
> These aren't style opinions — they encode the accumulated taste of the team so agents and contributors produce consistent, idiomatic code.

***

## I. Optimize for Programmer Happiness

Rails was built on the Principle of the Bigger Smile. Code in Nosia should feel like plain English when read aloud.

**Apply this in Nosia like so:**

```ruby
# ✅ Reads like English. The chat is the subject.
chat.complete(user_message)
chunk.vectorize!
document.ingest

# ❌ Shifts the burden of composition to the caller. Procedural soup.
ChatCompletionService.execute(chat, user_message)
VectorizationService.new(chunk).call
DocumentIngestionInteractor.run!(document)
```

When naming a method feels awkward, it is a signal: the concept doesn't have a natural home yet. Find it.

***

## II. Convention over Configuration

You're not a beautiful and unique snowflake. Rails already decided most things. Trust those decisions.

- Table names, foreign keys, association names, callback order — don't re-litigate them
- Concern names follow the pattern `Model::ConcernName` (e.g., `Chunk::Vectorizable`, `Chat::Completionable`) — keep it
- Background jobs are named `[Model][Action]Job` (e.g., `Document::EmbedJob`)
- API routes follow Rails resource conventions — no bespoke verbs

**Environment constants live in one place:**

```ruby
# config/initializers/nosia.rb — the single source of truth
EMBEDDING_MODEL        = ENV.fetch("EMBEDDING_MODEL", "text-embedding-3-small")
EMBEDDING_DIMENSIONS   = ENV.fetch("EMBEDDING_DIMENSIONS", 768).to_i
CHUNK_MAX_TOKENS       = ENV.fetch("CHUNK_MAX_TOKENS", 512).to_i
RETRIEVAL_FETCH_K      = ENV.fetch("RETRIEVAL_FETCH_K", 10).to_i
```

Never hardcode these values in a model, concern, or job. The constant is the convention.

***

## III. The Menu is Omakase — Trust the Stack

Nosia's stack was chosen deliberately. Don't swap components for novelty.

| What you have | Why it's enough |
|---|---|
| `pgvector` (PostgreSQL) | No Qdrant, no Weaviate — vector search co-located with relational data |
| `Solid Queue` | No Redis, no Sidekiq — background jobs backed by the same Postgres |
| `RubyLLM` | No raw `Faraday` to AI providers — unified streaming, retries, credentials |
| `Hotwire` (Turbo + Stimulus) | No React, no separate SPA — server-rendered HTML with live updates |
| `Kamal` | No Kubernetes, no ECS — single-server deployment, zero-ops |

If you feel the urge to add a service, ask: does the existing menu truly fail here, or am I just reaching for something familiar?

***

## IV. No One Paradigm — Use the Right Tool per Layer

Rails is a quilt, not a single cut of cloth. Apply the best paradigm per layer:

| Layer | Preferred paradigm |
|---|---|
| `app/models/` | Object-oriented, rich domain model. Concerns for composition. |
| `app/controllers/` | Thin. Calls domain model methods directly. Validates input, renders output. |
| `app/views/` | Declarative templates. Helpers are a flat namespace — that's fine here. |
| `app/jobs/` | Procedural delegation to domain models. Jobs are not domain logic. |
| `app/concerns/` | Modular OO — concerns isolate responsibilities, not architectures. |

Avoid applying DDD's application/domain split dogmatically. 37signals ships Basecamp with 400 controllers and 500 models talking to each other directly — and it works.

***

## V. Rich Domain Models — Not Anemic Shells

Controllers and jobs invoke domain models. Domain models do the work.

**The 37signals pattern applied to Nosia:**

```ruby
# Rich public API on the domain model
class Chat < ApplicationRecord
  include Completionable, SimilaritySearch, AugmentedPrompt,
          ContextRelevance, AnswerRelevance, ModelContextProtocol

  def complete(user_message)
    # The concern orchestrates — the model is the entry point
    run_completion(user_message)
  end
end

# Controller is thin — it knows nothing about RAG
class Api::V1::ChatsController < ApplicationController
  def create
    @chat = current_account.chats.create!(chat_params)
    render json: @chat, status: :created
  end
end

class Api::V1::MessagesController < ApplicationController
  def create
    @message = @chat.complete(params[:content])  # domain model does the work
    render json: @message
  end
end
```

The controller's job: parse the boundary, delegate to the domain model, render the result.

***

## VI. Concerns are Composition — Not a Junk Drawer

Following 37signals' `Recording::Incineratable` pattern: each concern owns one responsibility and, when complexity justifies it, delegates to a plain Ruby object inside it.

```
app/models/concerns/
├── chat/
│   ├── completionable.rb    # Orchestrates the completion pipeline
│   ├── similarity_search.rb # Retrieves relevant chunks via pgvector
│   ├── augmented_prompt.rb  # Injects chunks into the system prompt
│   ├── context_relevance.rb # LLM-based gate: are these chunks relevant?
│   ├── answer_relevance.rb  # LLM-based gate: is this answer grounded?
│   └── model_context_protocol.rb  # MCP server connection management
└── chunk/
    ├── vectorizable.rb      # Embedding generation + cosine similarity
    └── enrichable.rb        # Metadata: keywords, section path, content type
```

**When a concern grows complex, delegate — don't inflate:**

```ruby
# chat/completionable.rb delegates to a plain Ruby object for the pipeline
module Chat::Completionable
  def run_completion(user_message)
    Chat::Completion.new(self, user_message).run
  end
end

# A focused, cohesive object — not a "Service"
class Chat::Completion
  def initialize(chat, message)
    @chat, @message = chat, message
  end

  def run
    chunks  = @chat.retrieve_relevant_chunks(@message)
    prompt  = @chat.build_augmented_prompt(chunks, @message)
    @chat.call_llm(prompt)
  end
end
```

Notice: `Chat::Completion` is a domain concept given a proper class — not a `CompletionService`. It lives in `app/models/chat/`. It is domain logic, not an application layer.

***

## VII. POROs Belong in `app/models/`

Whether persisted or not, a domain concept is a model. Don't exile non-AR classes to `app/services/` or `lib/`.

```
app/models/
├── chat.rb                  # Active Record
├── chunk.rb                 # Active Record
├── chat/
│   ├── completion.rb        # PORO — orchestrates a completion run
│   └── augmented_prompt_builder.rb  # PORO — constructs the context prompt
├── chunk/
│   └── splitter.rb          # PORO — implements the 3-phase chunking strategy
└── document/
    └── ingestion.rb         # PORO — orchestrates the full ingestion pipeline
```

The Rails router, not arbitrary folder names, is what defines the architecture.

***

## VIII. Exalt Beautiful Code

The RAG pipeline is Nosia's heart. It should read like a lucid description of retrieval-augmented generation:

```ruby
# Reading this aloud describes the algorithm
module Chat::Completionable
  def run_completion(user_message)
    chunks  = retrieve_similar_chunks(user_message)
    context = chunks.select { |c| relevant_to?(c, user_message) }
    prompt  = build_augmented_prompt(context, user_message)
    answer  = generate_completion(prompt)
    answer if grounded_in?(answer, context)
  end
end
```

Prefer expressive method names over comments. A well-named method makes the comment redundant.

```ruby
# ❌ Needs explaining
def process(q, k=10)
  Chunk.nearest_neighbors(:embedding, embed(q), distance: "cosine").limit(k)
end

# ✅ Self-documenting
def retrieve_similar_chunks(query, limit: RETRIEVAL_FETCH_K)
  Chunk.nearest_neighbors(:embedding, embed(query), distance: "cosine").limit(limit)
end
```

***

## IX. Value the Integrated System — The Majestic Monolith

Nosia is a Rails monolith. Keep it that way until distribution is truly necessary.

- The RAG pipeline, MCP integration, document ingestion, and the web UI are one codebase, one process, one deploy
- No internal microservices, no "document processing service", no separate embedding API
- Background jobs (Solid Queue) are part of the monolith — they share the same models, concerns, and constants
- OpenAI-compatible API is a Rails engine inside the monolith, not a separate service

**The test:** Before splitting anything out, ask whether the pain of distribution (failure states, latency, deploy coupling, duplicated models) is less than the pain of the monolith. In Nosia's current scale, it never is.

***

## Anti-Patterns — What 37signals Would Delete on Sight

These patterns look architectural but add indirection without value:

| Anti-pattern | Why it fails in Nosia | The Rails alternative |
|---|---|---|
| `ChatCompletionService` | Shifts composition burden to caller, creates anemic `Chat` model | `chat.complete(message)` |
| `DocumentIngestionInteractor` | Application layer with no domain logic — pure boilerplate | `document.ingest!` via `Document::Ingestion` PORO |
| `Repositories::ChunkRepository` | Wraps Active Record for no gain | `Chunk.similar_to(query)` scope |
| `app/services/` folder | Signals architectural confusion | POROs in `app/models/` with namespacing |
| `EmbeddingFacade.new(chunk).embed` | Unnecessary delegation layer over RubyLLM | Inline in `Chunk::Vectorizable` |
| Mocking `RubyLLM` in integration tests | Hides real bugs in the pipeline | Fixture chunks with known embeddings in pgvector |

> "We don't default to create services, actions, commands, or interactors to implement controller actions." — Jorge Manrubia, 37signals

***

## When to Deviate

These principles are guides, not laws. The doctrine itself says: *"No one paradigm."*

Deviate when:
- A concern genuinely can't find a natural home in a domain model
- An external integration (a new transport protocol, a cloud SDK) is inherently infrastructure — then `lib/nosia/` is the right place
- The team explicitly decides to: record the deviation in `docs/DECISIONS.md` with date and rationale

The goal is not purity. The goal is a codebase where the next contributor — human or agent — can orient immediately and build with confidence.
