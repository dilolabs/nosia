# 2026-07-02 Token Calculator for Transparency & Green IT

**Date:** 2026-07-02
**Status:** Draft
**Author:** Cyril Blaecke
**Approvers:** Pending
**Branch context:** `feat/mistakes-transparency`

---

## 1. Overview

### Purpose

Surface the input/output token usage that Nosia already captures — per message, per chat, and per account — and translate it into environmental impact (kWh, gCO2e) using per-model measured consumption from the Comparia benchmark. The goal is **transparency** and **green IT**: let users see the resource cost of their AI usage, aligned with the branch's transparency theme and the project's RGESN eco-design concerns.

### Background & Motivation

Nosia uses the `ruby_llm` gem, which automatically writes `input_tokens`, `output_tokens`, `cached_tokens`, `cache_creation_tokens`, and `thinking_tokens` onto every assistant `Message` (db/schema.rb:233-241). The `Model` catalog stores per-token pricing. **None of this is surfaced to users today** — the only token-related UI is the `$/1M tokens (In/Out)` column on the model catalog page.

Two gaps exist:
- **Embedding token usage** is discarded. `RubyLLM.embed` returns `input_tokens`, but `Chunk::Vectorizable` and `Chunk::Searchable` throw it away. There is no record of RAG indexing or query-embedding cost.
- **Agent-skill LLM calls** (`AgentSkillExecution` with `execution_mode: "llm"`) record no token usage.

This spec fills those gaps and makes all of it visible.

### Energy data source

`data/comparia_model-energy-02_07_2026-license_Etalab_2_0.csv` — published under **Etalab 2.0**. The key field is **`Consumption mWh (1000 tokens)`**: average energy per 1000 tokens per model, in milliwatt-hours. It is a single blended per-token figure (not split input/output). Only open-weights models have measured values; `api-only` models are `N/A`.

---

## 2. Goals & Non-Goals

### Goals

- [ ] Display raw input/output token counts (plus cached/thinking) per assistant message.
- [ ] Display per-chat token totals, broken down by kind (completion / embedding / agent_skill).
- [ ] Display account-wide dashboard rollups (headline totals, per-model, per-kind, per-day).
- [ ] Estimate environmental impact (kWh, gCO2e) from tokens using per-model Comparia consumption, with a transparent fallback for unknown models.
- [ ] Track embedding token usage (indexing and query-time), currently discarded.
- [ ] Track agent-skill LLM token usage.
- [ ] Keep derived figures (kWh/CO2e) computed live from raw tokens + current coefficients, so updating coefficients retroactively corrects all historical figures.

### Non-Goals

- No cost / dollar estimation (Nosia is self-hosted OSS; pricing is not surfaced).
- No API endpoint for token totals.
- No per-user quotas or usage limits.
- No live streaming of partial token counts mid-generation (counts appear when the message finalizes).
- No storage of derived kWh/CO2e — only raw tokens are stored.
- No recovery of pre-feature embedding history (it was never recorded).

---

## 3. Selected Approach

**Approach B — Event log + cached counters**, chosen over:

- **A — Event log + on-demand aggregation only:** cleanest, but the user opted for the faster dashboard reads that cached counters provide.
- **C — SQL view over existing tables:** rejected as a fragile cross-table `UNION` that fights the single-source-of-truth model.

A unified `token_usages` append-only event log records every LLM call. Aggregate headline counters on `chats` and `accounts` optimize the top-line numbers; per-kind / per-model / per-day breakdowns stay as live `GROUP BY` queries (indexed) — caching every dimension would be over-engineering.

---

## 4. Architecture

### Data model — `TokenUsage` (new)

An append-only event log: one row per LLM call. It is the **accounting record**, separate from the **conversational record** (`Message`). They link but stay decoupled.

```ruby
class TokenUsage < ApplicationRecord
  acts_as_tenant :account
  belongs_to :chat, optional: true                          # denormalized for rollups; nil for embeddings
  belongs_to :source, polymorphic: true, optional: true     # Message (completion), Chunk (embedding), AgentSkillExecution (agent_skill)
  enum :kind, { completion: "completion", embedding: "embedding", agent_skill: "agent_skill" }

  # input_tokens, output_tokens, cached_tokens, cache_creation_tokens, thinking_tokens : integer
  # model_id : string (ruby_llm model_id, not an FK — the models catalog is refreshable)
end
```

Source mapping:
- **completion** → `source` = the assistant `Message`; `chat_id` copied from `message.chat_id`.
- **embedding (indexing)** → `source` = the `Chunk`; `chat_id` nil (RAG indexing has no chat context).
- **embedding (query)** → `source` = the `Message` triggering the search; `chat_id` set.
- **agent_skill** → `source` = the `AgentSkillExecution`; `chat_id` set from `execution.chat_id`.

**Why `chat_id` is denormalized alongside the polymorphic `source`:** "all usages for this chat" must be a single indexed lookup for per-chat totals and for the counter increment. A pure polymorphic would force a union through `messages.chat_id` and `agent_skill_executions.chat_id` and require loading the source just to increment the chat counter. The polymorphic handles the *origin* link (navigation, de-duplication, extensibility); `chat_id` handles the *aggregation* axis. Different purposes, justified redundancy.

### Cached counters

- `chats.input_tokens_count`, `chats.output_tokens_count` (integer, default 0)
- `accounts.input_tokens_count`, `accounts.output_tokens_count` (integer, default 0)

Aggregate only — not per-kind. Per-kind / per-model / per-day breakdowns are live `GROUP BY` queries.

### Counter maintenance

`TokenUsage` `after_create` only (append-only, never updated) does:

```ruby
Chat.increment_counter(:input_tokens_count, chat_id)        # if chat_id present
Chat.increment_counter(:output_tokens_count, chat_id)
Account.increment_counter(:input_tokens_count, account_id)
Account.increment_counter(:output_tokens_count, account_id)
chat.touch  # Russian-doll cache invalidation
```

This is treated as the conventional counter-cache exception to the "no side-effect callbacks" rule — pure aggregate maintenance, no business logic, no external calls.

**Drift repair:** `Chat.recount!` / `Account.recount!` recompute counts from `token_usages` (`sum(:input_tokens)`). Wired to an admin rake task / recurring job so any drift (a failed increment) self-heals.

---

## 5. Green-IT Calculation

### Coefficient source

The Comparia CSV is converted to a static lookup `config/model_energy.yml`, keyed by normalized (lowercased) model id → `mwh_per_1000_tokens`, with a `source:` stamp (`"comparia 2026-07-02, license Etalab-2.0"`). This stays **decoupled from the refreshable `models` catalog** — Comparia is a versioned dataset re-imported periodically, not something `ModelsController#refresh` touches.

### `GreenIt` module (`lib/green_it.rb`)

```ruby
GreenIt.energy_kwh(tokens:, model_id:)        # total tokens × per-model kwh/token
GreenIt.co2e_g(kwh:)
GreenIt.grid_intensity_gco2e_per_kwh          # from config/ENV, default 475 (world avg)
GreenIt.fallback_kwh_per_token                # configurable default for unknown models
```

Conversion: `kwh = tokens × mwh_per_1000_tokens × 1e-9` (mWh per 1000 tokens → kWh per token = mWh × 1e-9). The Comparia figure is a blended per-token average, so it is applied to **total tokens (input + output)** — faithful to the source, no invented input/output split.

### Matching & fallback

Lookup by normalized id. `api-only`/`N/A` models and any unmatched ruby_llm `model_id` fall back to `GreenIt.fallback_kwh_per_token` (default: conservative average of the dataset). When the fallback is used, the UI marks the figure with an asterisk + tooltip: *"estimation — modèle absent du benchmark Comparia"*. Uncertainty is surfaced, not hidden.

### Embeddings

Embedding models are generally not in Comparia (chat-focused), so embeddings use a separate configurable `embedding.kwh_per_input_token` default (the same fallback path).

### Config (`config/green_it.yml`)

```yaml
grid_intensity_gco2e_per_kwh: 475        # world average; override with local grid
embedding:
  kwh_per_input_token: 0.0000000100     # fallback for embedding models not in Comparia
fallback_kwh_per_token: 0.0000000900    # conservative default for unknown chat models
```

ENV overrides (highest priority): `GREENIT_GRID_INTENSITY_GCO2E_PER_KWH`, `GREENIT_FALLBACK_KWH_PER_TOKEN`, `GREENIT_EMBEDDING_KWH_PER_INPUT_TOKEN`.

### Deliberate property

Only raw tokens are stored on `token_usages` — never derived kWh/CO2e. Energy and CO2e are always computed live from current tokens + current dataset + current grid intensity. Updating the Comparia import, or setting a local grid intensity via `GREENIT_GRID_INTENSITY_GCO2E_PER_KWH`, **retroactively corrects every historical figure**. This is the point of the feature.

---

## 6. Write Paths

Three explicit creation points (no hidden cross-model business-logic callbacks — the only callback is the counter increment):

### 6.1 Completions — `Chat::Completionable`

After `self.complete` returns, RubyLLM has persisted the assistant message(s) with token columns. A new `Chat#record_completion_usage!` finds assistant messages created by this completion that don't yet have a `TokenUsage` (de-duped via the polymorphic `source` link) and creates one each:

```ruby
TokenUsage.create!(
  kind: :completion, source: assistant_message,
  chat_id: id, account_id:, model_id: assistant_message.model_id,
  input_tokens:, output_tokens:, cached_tokens:, cache_creation_tokens:, thinking_tokens:
)
```

Called from both `complete_with_nosia` and `complete_with_agent_skills` (both end in `self.complete`). Explicit, in the model layer.

### 6.2 Embeddings — `Chunk::Vectorizable` and `Chunk::Searchable`

Both currently discard `RubyLLM.embed`'s `input_tokens`:

- **Indexing** (`Chunk::Vectorizable`): `kind: :embedding`, `source: chunk`, `chat_id: nil`, `model_id: ENV["EMBEDDING_MODEL"]`, `output_tokens: 0`.
- **Query** (`Chunk::Searchable`): `kind: :embedding`, `source: message`, `chat_id: chat.id` (the search runs in a chat context), `model_id: ENV["EMBEDDING_MODEL"]`, `output_tokens: 0`.

### 6.3 Agent skills — skill execution runner

After an `AgentSkillExecution` with `execution_mode: "llm"` call returns: `kind: :agent_skill`, `source: agent_skill_execution`, `chat_id: execution.chat_id`.

> **CRITICAL — implementation TBD:** The exploration did not pin the exact site where agent skills invoke the LLM. The implementation plan must locate it and wire the `TokenUsage` creation there.

---

## 7. Display Surfaces

### 7.1 Per-message footer

`app/views/messages/_assistant.html.erb` — a compact `<footer>` line, shown only when `message.done?` and tokens are present:

```
↑ 1,240 ↓ 320 · 0.006 kWh · 2.1 gCO2e*
```

Reads from the message's token columns + `message.model_id` → `GreenIt`. Renders on the final `broadcast_updated` (when `done` flips true) — no new Turbo plumbing. The `*` appears only when the model used the Comparia fallback, with a tooltip explaining the estimate.

### 7.2 Per-chat totals

`app/views/chats/show.html.erb` — summary header:
- Headline from cached `chat.input_tokens_count` / `output_tokens_count` (instant).
- Per-kind breakdown via one live `chat.token_usages.group(:kind).sum(:input_tokens, :output_tokens)`.
- Derived kWh/CO2e from totals.
- A Turbo Stream (`broadcasts_to chat`) refreshes the header when a new `TokenUsage` is created, so the total ticks up live as the assistant finishes.

### 7.3 Account dashboard section

`app/views/dashboards/show.html.erb`:
- Headline totals from cached `account.input_tokens_count` / `output_tokens_count`.
- Live `GROUP BY` breakdown tables: per-model (top 5 by tokens) and per-kind, each with derived kWh/CO2e.
- Per-day totals sparkline over the last 30 days (one `group_by_day` query), rendered as a tiny inline SVG (no charts library — keeps the build free).
- Russian-doll cached on `account.touch` (invalidated by the counter increment).

### 7.4 Model catalog column

`app/views/models/_model.html.erb` gains a "Conso. moyenne (1000 tokens)" column from the Comparia lookup, "—" when unmatched. Cheap transparency at the model-selection moment.

---

## 8. Migrations

1. `create_table :token_usages` — UUIDv7 (base36 25-char), columns per Section 4, indexes: `(account_id, created_at)`, `(chat_id)`, `(source_type, source_id)`, `(account_id, kind)`, `(account_id, model_id)`.
2. `add_column :chats, :input_tokens_count, :integer, default: 0` + `:output_tokens_count`.
3. `add_column :accounts, :input_tokens_count, :integer, default: 0` + `:output_tokens_count`.
4. Backfill data migration: iterate historical `messages` with `input_tokens` present, create a `TokenUsage(kind: :completion, source: message, ...)` for each, then `Account.recount!` / `Chat.recount!` to set counters. Keeps the event log and counters consistent from day one. Uses `find_each` (scale is small for self-hosted).
5. `config/model_energy.yml` generated from the CSV (committed data file, not a migration).

---

## 9. Testing (Minitest + fixtures)

- `TokenUsageTest` — validations, enum, `acts_as_tenant` scoping, `after_create` counter increments, `energy_kwh`/`co2e_g` delegation.
- `GreenItTest` — conversion math against known CSV rows (e.g. `glm-5.2` → 4095 mWh/1000tok), fallback path, ENV grid-intensity override, retroactive-update property (changing coefficient changes historical figure).
- `Chat::CompletionableTest` — records a `TokenUsage` after complete; idempotent (no dupe on re-run).
- `Chunk::VectorizableTest` / `Chunk::SearchableTest` — embedding usage recorded, `chat_id` nil (indexing) / set (query).
- `ChatTest` / `AccountTest` — `recount!` repairs drift.
- Controller/view tests — footer renders when done, chat totals present, dashboard shows breakdowns.
- Fixtures: `token_usages.yml` across all three kinds.

---

## 10. Limitations

- **Embedding history before this feature is unrecoverable** — it was never recorded. The backfill only covers completion tokens from historical messages.
- **Per-model matching is best-effort** by normalized id; misses use the fallback and are flagged in the UI.
- **Comparia gives a blended per-token figure**, so input and output tokens share one coefficient per model. We do not invent an input/output energy split.

---

## Appendix — References

- Comparia ranking: `data/comparia_model-energy-02_07_2026-license_Etalab_2_0.csv` (license Etalab 2.0)
- Existing token columns: db/schema.rb:233-241, added by migrations `20250926205810_add_tokens_to_messages.rb`, `20251124130414_add_ruby_llm_v1_9_columns.rb`, `20260402102252_add_ruby_llm_v1_10_columns.rb`.
- `ruby_llm` gem ActiveRecord integration: `ruby_llm/active_record/acts_as.rb`.
- Project conventions: `.claude/CLAUDE.md`, `.claude/rules/*.md` (models, multi-tenancy, views, controllers, style).

---

**Approvals:**
- [ ] Design approved by requester
- [ ] Spec document reviewed
- [ ] Ready for implementation planning