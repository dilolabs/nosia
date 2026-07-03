# Optional Engines Design — OpenAlex & Infomaniak kDrive

**Date:** 2026-07-03
**Branch:** `feat/openalex`
**Status:** Draft (pending review)

## Purpose

Add OpenAlex and Infomaniak kDrive as **optional engines** in Nosia: native Ruby integrations
that wrap external HTTP APIs and expose them as tools the **Nosia chat agent** can call during a
chat. Each engine is **always bundled** (ships in the Gemfile) but **dormant until an account
activates it** — the same per-account toggle already used by the MCP catalog. No external MCP
server surface is required; Nosia is the consumer, not the provider.

This generalizes the in-progress OpenAlex work into a small **optional-engine framework** and
applies the same pattern to a new native **kDrive** engine that replaces the existing
docker-based kDrive catalog entry.

## Goals

- Nosia's LLM can call OpenAlex and kDrive tools directly during a chat (in-process; no network
  transport, no spawned docker container).
- Each account opts in via the existing MCP Catalog / `McpServer` activation flow.
- One tool-authoring format per engine (`MCP::Tool` subclasses), reused by a single adapter.
- Adding a third engine later requires no framework changes — only an engine registration.

## Non-goals

- Exposing Nosia as an MCP server to external clients (Claude Desktop, etc.). The existing
  `McpOpenalexController` HTTP-provider endpoint and `POST /mcp/openalex` route are removed.
- Per-account install-time optionality (the gem is always bundled). Tenant-level enablement is
  the only opt-in layer.
- Mutating kDrive operations (create/upload/rename). kDrive is read-only in this iteration.
- Replacing the docker-based **Calendar** and **kChat** catalog entries. Only the kDrive entry is
  replaced.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Who consumes the integrations? | Nosia's own chat agent (in-process RubyLLM tools). |
| What does "optional" mean? | Always bundled; per-account toggle via MCP Catalog activation. |
| Scope of this spec | Framework + both engines (OpenAlex, native kDrive). |
| Relationship to existing kDrive docker entry | Native engine **replaces** the docker catalog entry. |
| kDrive tool surface | Read-only: search files, list folder contents, get/download a file. |
| Architecture approach | Local transport on `McpServer` + `MCP::Tool`→`RubyLLM::Tool` adapter + registry. |

## Architecture

```
Account ──has_many──> McpServer (transport_type: "local", metadata.engine: "open_alex")
                         │  auth_config: { api_key: "..." }   (encrypted)
                         │  metadata: { catalog_id, icon, capabilities }
                         └─ tools  ──> Engines::Registry["open_alex"].tool_classes
                                          │ adapted by Engines::ToolAdapter
                                          ▼
                                   [RubyLLM::Tool subclasses]
                                          │
Chat ──has_many chat_mcp_sessions──> McpServer
Chat#mcp_tools  ──> collects adapted tools from enabled, ready sessions
Chat::Completionable#complete_with_nosia ──> with_tools(*mcp_tools_list)   (unchanged)
                                          │
                                          ▼  LLM calls a tool
                                   Adapter#execute ──> OpenAlexTools::SearchWorksTool.call(api_key:)
                                          │
                                          ▼
                              OpenAlex::ApiClient  ──HTTP──> api.openalex.org
```

### New pieces (all small)

1. **`McpServer` local transport** — a new `transport_type: "local"` alongside
   `stdio`/`streamable`/`sse`. No `endpoint`; `metadata.engine` names a registered engine;
   `auth_config` holds encrypted credentials. `#tools` and `#test_connection!` branch on it to
   skip the network client.
2. **`Engines::Registry`** (`lib/nosia/engines/registry.rb`) — in-memory registry populated at
   boot via initializers. Each entry is a value object: `id`, `name`, `icon`, `description`,
   `required_config`, `tool_classes` (`MCP::Tool` subclasses), and a `health_check` lambda.
3. **`Engines::ToolAdapter`** — one class that maps an `MCP::Tool` subclass to a
   `RubyLLM::Tool` subclass: name, description, parameters (flat `param` or nested
   `params(schema:)`), and `execute` → `MCP::Tool.call(**args, server_context: <auth>)`, unwrapping
   `MCP::Tool::Response` into a RubyLLM tool result.
4. **Catalog "Built-in engines" section** — `McpCatalog` lists registry entries alongside YAML
   docker servers and routes their activation through the existing `activate_for_account` flow,
   producing a `local` `McpServer`.

### Engines (Rails engines in `lib/`)

- **`open_alex`** (existing): keeps `ApiClient`, `Entities::*`, `OpenAlex::Tool` facade, and the
  `OpenAlexTools::*` `MCP::Tool` subclasses. Adds an `EngineRegistration` + boot initializer.
  Drops `McpOpenalexController` and the `POST /mcp/openalex` route.
- **`kdrive`** (new): `Kdrive::ApiClient` (Infomaniak kDrive REST API), `Kdrive::Tool` facade,
  `KdriveTools::*` `MCP::Tool` subclasses, and an `EngineRegistration`.

## Data model

**No new tables.** Everything rides on the existing `mcp_servers` row + a Ruby registry.

`McpServer` changes (migration-free — `transport_type` is a plain string with an app-level enum):
- `transport_type` validation adds `"local"` to its inclusion list.
- For `local` servers: `endpoint` not required (existing guard already handles this);
  `metadata.engine` holds the registry id; `auth_config` holds credentials (`api_key`, or
  `token` + `drive_id`), already encrypted via `encrypts :auth_config`.
- `#client` returns `nil` for `local` (no `RubyLLM::MCP.client`).
- `#tools` for `local` resolves `Engines::Registry[metadata.engine].tool_classes`, maps each
  through `Engines::ToolAdapter` with `server_context` from decrypted `auth_config`. Returns
  RubyLLM tools.
- `#test_connection!` for `local` calls the engine's `health_check` (lightweight authenticated
  API ping) instead of `client.tools`.

`Engines::Registry` registration shape:

```ruby
Engines::Registry.register(OpenAlex::EngineRegistration.new)
# => id "open_alex", name "OpenAlex", icon "📚", description,
#     required_config [{ name: :api_key, type: :secret, required: false }],
#     tool_classes [OpenAlexTools::SearchWorksTool, ...],
#     health_check: ->(auth) { OpenAlex::ApiClient.new(auth).ping }
```

## Data flow

### Activation (account enables an engine — one click)

1. Admin visits MCP Catalog → "Built-in engines" → clicks OpenAlex (or kDrive).
2. Form collects `required_config` (OpenAlex: API key optional; kDrive: token + drive_id, both
   required).
3. `McpCatalog.activate_for_account` → `McpServer.create!(transport_type: "local",
   metadata: { engine: "open_alex", catalog_id: ... }, auth_config: { api_key: ... })`.
4. `test_connection!` runs the engine's `health_check` → status `ready` (or `error` +
   `last_error`).

### Chat-time tool wiring (unchanged path, new source)

1. User creates/edits a chat, picks the OpenAlex `McpServer` → `chat_mcp_sessions` row.
2. `Chat#complete_with_nosia` calls `mcp_tools` → iterates enabled sessions, finds the local
   server `ready?` → calls `McpServer#tools`.
3. `#tools` resolves `Engines::Registry["open_alex"].tool_classes`, maps each through
   `Engines::ToolAdapter` with `server_context = auth_config`.
4. `with_tools(*adapted)` registers them with RubyLLM. The LLM sees `openalex_search_works`,
   `kdrive_search_files`, etc.

### Tool execution

1. LLM emits a tool call for `openalex_search_works` with `{ query: "..." }`.
2. RubyLLM instantiates the adapted `RubyLLM::Tool`, runs `execute(query: "...")`.
3. Adapter unwraps args, calls `OpenAlexTools::SearchWorksTool.call(query: "...",
   server_context: { api_key: "..." })`.
4. The tool calls `OpenAlex::Tool.search_works` → `ApiClient.get("/works", ...)` →
   `api.openalex.org`.
5. `MCP::Tool::Response` (text + `structured_content`) is unwrapped by the adapter into a
   RubyLLM tool result, streamed back to the chat as the assistant's tool message.
6. The LLM receives the result and continues.

### Credential threading

Credentials reach the tool via `server_context`, **never** as tool parameters. `server_context`
is set at adapter-construction time from the `McpServer`'s decrypted `auth_config`. `api_key` /
`token` / `drive_id` are not in the tool's input schema, so the model never controls them and
they never enter the prompt.

### kDrive specifics

`KdriveTools::SearchFilesTool.call(query:, server_context:)` uses `server_context[:token]` +
`server_context[:drive_id]` to build `https://api.infomaniak.com/2/drive/{drive_id}/...` with
`Authorization: Bearer {token}`. `KdriveTools::GetFileTool` fetches metadata and, for text-able
content types (matching the repo's existing doc-content_type pattern), downloads and inlines a
bounded excerpt; binaries return metadata only with a size hint.

### kDrive tool surface (read-only)

- `kdrive_search_files` — search files/folders by query.
- `kdrive_list_folder` — list contents of a folder (defaults to drive root).
- `kdrive_get_file` — fetch file metadata; inline a bounded text excerpt for text-able types,
  metadata-only otherwise.

## Error handling

Each engine is independent and optional. A failure in one engine never breaks the chat or other
engines; it degrades to "this tool returned an error," surfaced to the LLM so it can explain.

**Authentication / config:**
- `test_connection!` runs the engine's `health_check`. 401/403 → `status: "error"`,
  `last_error: "Invalid credentials for OpenAlex"`. Server stays non-ready; `Chat#mcp_tools`
  skips it. No mid-chat crash.
- Missing required config at activation (kDrive without `drive_id`) →
  `McpCatalog.activate_for_account` raises `ActiveRecord::RecordInvalid`; the controller rescues
  and redirects with the alert, as today.

**Runtime tool errors:**
- The adapter wraps `MCP::Tool.call` in a rescue. Network/timeout/API errors become a RubyLLM
  tool result with a clear `error` text (e.g. `"OpenAlex API timed out (30s)"`), not an
  exception. The LLM gets the error; the chat continues.
- `OpenAlex::ApiClient` / `Kdrive::ApiClient` own retry policy (OpenAlex already has
  `max_retries: 5`, `timeout: 30`; kDrive uses the same shape). Retry 429/5xx with backoff; do
  not retry 4xx.
- Structured results keep a per-tool `output_schema` shape so the adapter's unwrap is
  predictable.

**Schema-translation errors (the spike risk):**
- `Engines::ToolAdapter` validates at registration: every tool's `input_schema` must translate
  cleanly. An unsupported JSON-Schema feature logs a warning and **drops that tool** (the
  engine's other tools still load) rather than failing app boot. Localizes adapter blast radius.
- A test suite covers the shapes we use (flat scalars, nested `params` object, arrays) so
  regressions surface in CI.

**kDrive-specific edges:**
- Token revoked mid-session → tool call returns 401 error text; the LLM tells the user to
  re-activate. Admin can re-run `test_connection!` from the MCP servers UI.
- Large/binary downloads in `GetFileTool` → hard size cap (e.g. 1 MB) + content-type allowlist
  for inlining; oversized/binary files return metadata + a "too large to inline" note.
- Wrong `drive_id` → 404 mapped to `"kDrive not found — check your drive id"`.

**Isolation:** an exception that escapes the adapter's rescue (a bug, not an API error) is
caught at the `with_tools` boundary and turned into a generic tool error, so a faulty engine
cannot take down a completion.

## Testing

**Stack:** Minitest + fixtures (project conventions — no RSpec, no FactoryBot). The OpenAlex
branch's `spec/` (RSpec) comes from the gem's standalone skeleton; engine tests move to `test/`
(Minitest) to match Nosia and `bin/ci`. The `spec/` files are ported or removed.

**Layers:**

1. **`Engines::ToolAdapter` (unit)** — highest-risk, tested most heavily. Flat scalar params →
   `param`; nested-object schema (OpenAlex `params: { per_page, page }`) → `params(schema:)`;
   `execute` delegates with correct `server_context` (assert credentials pass through, never as
   args); `MCP::Tool::Response` unwraps to a RubyLLM result; unsupported schema feature → tool
   dropped, others survive.
2. **`Engines::Registry` (unit)** — register/lookup, duplicate-id handling, boot order.
3. **`McpServer` local transport (model)** — `#tools` returns adapted RubyLLM tools for a `local`
   server; `#client` nil; `test_connection!` calls `health_check` and flips status. Fixtures: a
   `local` openalex server, a `local` kdrive server.
4. **`McpCatalog` activation (model)** — activating a registry engine creates a `local`
   `McpServer` with correct `metadata.engine` + `auth_config`; kDrive missing `drive_id`
   raises; OpenAlex with no key still activates.
5. **API clients (unit, stubbed)** — `OpenAlex::ApiClient` / `Kdrive::ApiClient` with Faraday
   stubs: success, 401, 429-retry, 404, timeout. No real network in CI.
6. **Engine tools (unit)** — each `OpenAlexTools::*` / `KdriveTools::*` tool, facade stubbed,
   asserts `MCP::Tool::Response` shape and that `server_context` credentials reach the facade.
7. **Integration (one request test)** — a chat with an enabled local OpenAlex server, stubbed
   LLM that requests the tool, verifies the adapter's tool is invoked and the result flows
   back. Locks end-to-end wiring without external APIs.
8. **System (minimal)** — Capybara: admin activates kDrive from the catalog, sees `ready`
   status. One journey.

`bin/ci` runs RuboCop + Brakeman + the Minitest suite. The adapter stays explicit (no `eval` of
user data) so Brakeman passes clean.

## Open questions / spikes

- **Schema-translation spike:** confirm the adapter handles every `input_schema` shape the
  OpenAlex and kDrive tools actually use (flat, nested object, arrays). This is the main risk;
  resolved early with a failing test, then the adapter implementation.
- **Infomaniak kDrive API surface:** confirm endpoint shapes for search / list / download
  against current Infomaniak kDrive REST docs, and the auth header format (`Bearer` token).
- **Test-fixture encryption:** how `auth_config` fixtures work under ActiveRecord Encryption in
  test (test credential or plaintext override) — to be settled in implementation.