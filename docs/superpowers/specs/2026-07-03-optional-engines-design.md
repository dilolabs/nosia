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
   docker servers and routes their activation through `activate_for_account`, producing a
   `local` `McpServer`. See "McpCatalog changes" below for the concrete shape — the existing
   `activate_for_account` is hard-shaped around YAML templates (command/args/env/url/headers)
   and cannot handle registry entries as-is, so a new branch is required.

### Engines (Rails engines in `lib/`)

- **`open_alex`** (existing): keeps `ApiClient`, `Entities::*`, `OpenAlex::Tool` facade, and the
  `OpenAlexTools::*` `MCP::Tool` subclasses. Adds an `EngineRegistration` + boot initializer.
  Drops `McpOpenalexController` and the `POST /mcp/openalex` route.
- **`kdrive`** (new): `Kdrive::ApiClient` (Infomaniak kDrive REST API), `Kdrive::Tool` facade,
  `KdriveTools::*` `MCP::Tool` subclasses, and an `EngineRegistration`.

### McpCatalog changes (concrete)

The existing `McpCatalog` (`lib/mcp_catalog.rb`) is hard-shaped around YAML templates:
`activate_for_account` branches on `is_stdio`, builds `connection_config` from
`template[:command]/[:args]/[:env]` or `template[:url]/[:headers]`, sets `endpoint: template[:url]`,
and interpolates `{{vars}}` from `template[:auth_config]`/`template[:env]`. Registry entries have
a different shape (no command/args/env/url/headers; they carry `tool_classes`, `health_check`,
`required_config`). To handle them without breaking the YAML path:

- **Listing:** `McpCatalog.all`/`find` merge registry entries into the same list, each tagged
  `source: :registry` (YAML entries carry `source: :yaml` implicitly). `load_catalog` becomes
  `yaml_servers + Engines::Registry.all.map(&:to_catalog_entry)`. `to_catalog_entry` emits the full
  hash the catalog/UI reads: `{ id:, name:, icon:, description:, category: "engines", source:
  :registry, capabilities: <engine-declared or []>, requires_config: }` (key matches the
  YAML catalog + views convention so the activation form renders unchanged) — `category` is a fixed
  `"engines"` (used for `tags` and grouping), `capabilities` is engine-declared (defaults to
  `[]`). The catalog controller and views are source-agnostic — they render from `@servers`, so
  registry entries appear with no template-specific UI changes beyond a "Built-in" badge.
- **Activation:** `activate_for_account` branches on `template[:source]`. For `:registry` it
  builds a `local` server directly — `transport_type: "local"`, `endpoint: nil`,
  `connection_config: {}`, `metadata: { engine: template[:id], catalog_id: template[:id], icon:,
  capabilities: }`, and `auth_config` from the submitted `config_values` validated against the
  entry's `requires_config` (required keys present, else raise `ActiveRecord::RecordInvalid`).
  The YAML/stdio branch is untouched.

### Engine `ApiClient` changes (concrete)

To thread `server_context` credentials into the engines, the API clients must accept auth at
construction (they do not today):

- **`OpenAlex::ApiClient` / `OpenAlex::Configuration`** (`lib/open_alex/api_client.rb`,
  `lib/open_alex/configuration.rb`): `ApiClient.new` accepts an optional auth hash
  (`{ api_key: }`) that overrides `Configuration`'s ENV-derived default, and gains a lightweight
  `ping` (e.g. one-row `/works?per-page=1`) for `health_check`. The `OpenAlex::Tool` facade
  passes the auth through from `server_context`.
- **`Kdrive::ApiClient`** (new): constructed with `{ token:, drive_id: }` from `server_context`;
  exposes a `ping` (e.g. drive root listing) for `health_check`.

These are listed engine changes, not assumptions about the current `ApiClient`.

## Data model

**No new tables.** Everything rides on the existing `mcp_servers` row + a Ruby registry.

`McpServer` changes (migration-free — `transport_type` is a plain string with an app-level `inclusion` validation, not a Rails `enum`; the only change is adding `"local"` to that inclusion list):
- `transport_type` validation adds `"local"` to its inclusion list.
- For `local` servers: `endpoint` not required (existing guard already handles this);
  `metadata.engine` holds the registry id; `auth_config` holds credentials (`api_key`, or
  `token` + `drive_id`), already encrypted via `encrypts :auth_config`.
- `#client` returns `nil` for `local` (no `RubyLLM::MCP.client`).
- `metadata.engine` is read directly off the JSONB `metadata` (`metadata[:engine]`); no new
  `store_accessor` is added (the existing accessors for `:capabilities` etc. are untouched).
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
#     health_check: ->(auth) { OpenAlex::ApiClient.new(auth).ping }   # ApiClient modified to accept auth — see "Engine ApiClient changes"
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
`Authorization: Bearer {token}`. `KdriveTools::InfoTool` fetches metadata and, for text-able
content types (matching the repo's existing doc-content_type pattern), downloads and inlines a
bounded excerpt; binaries return metadata only with a size hint. `KdriveTools::DownloadFileTool`
returns any file's content as base64, refusing files over `DOWNLOAD_CAP_BYTES` (it fetches
metadata first to check size, so an oversized file is rejected before its body is downloaded).

### kDrive tool surface (read-only)

- `kdrive_search_files` — search files/folders by query.
- `kdrive_list_folder` — list contents of a folder (defaults to drive root).
- `kdrive_info` — fetch file metadata; inline a bounded text excerpt for text-able types,
  metadata-only otherwise. `file_id` is a number.
- `kdrive_download_file` — download a file and return its content as a base64-encoded string
  (use `kdrive_info` for the MIME type). Refuses files over the cap. `file_id` is a number.

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
- Large/binary downloads in `InfoTool` → hard size cap (1 MB) + content-type allowlist
  for inlining; oversized/binary files return metadata + a "too large to inline" note.
- `DownloadFileTool` → 5 MB `DOWNLOAD_CAP_BYTES`; metadata is fetched first so an oversized
  file is refused before its body is downloaded, returning a "file too large" error text.
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
  resolved early with a failing test, then the adapter implementation. Note: `RubyLLM::Tool`
  derives its tool `name` from the Ruby class name (normalize + `delete_suffix('_tool')`), not
  from a `param` — so the adapter must create a properly-named class (e.g.
  `OpenalexSearchWorksTool`) to produce the `openalex_search_works` tool name the LLM sees.
  Prefixing by engine avoids cross-engine collisions.
- **Infomaniak kDrive API surface:** confirm endpoint shapes for search / list / download
  against current Infomaniak kDrive REST docs, and the auth header format (`Bearer` token).
- **Test-fixture encryption:** how `auth_config` fixtures work under ActiveRecord Encryption in
  test (test credential or plaintext override) — to be settled in implementation.

## kDrive API findings (post-spike)

Researched 2026-07-04. Sources (URLs actually fetched/read):

- Official developer portal search hits (developer.infomaniak.com) confirming individual
  endpoint paths — the portal pages are JS-rendered so WebFetch returned only the page shell,
  but search result snippets quote the official paths verbatim:
  - `GET /2/drive/{drive_id}/files/{file_id}/download`
    (https://developer.infomaniak.com/docs/api/get/2/drive/%7Bdrive_id%7D/files/%7Bfile_id%7D/download)
  - `GET /3/drive/{drive_id}/files/{file_id}/count`
  - `GET /3/drive/{drive_id}/files/recents`, `.../largest`, `.../most_versions`,
    `.../shared_with_me`
  - `POST /3/drive/{drive_id}/files/{file_id}/directory`
- `https://api.infomaniak.com/doc` (redirects to the developer portal) — search snippet
  confirms the standard JSON return format with `data`, `error`, and `context` fields.
- Community MCP server source (read via `git clone`, not just README): `ddanssaert/kdrive-mcp`
  `src/client.js` — implements the same four operations against the live API and unwraps the
  response envelope as `json.result === 'success'` then `json.data`. Its paths match the
  official portal snippets above. https://github.com/ddanssaert/kdrive-mcp
- Official `@infomaniak/mcp-server-kdrive` README (npm/GitHub) — confirms env vars
  `KDRIVE_TOKEN` + `KDRIVE_ID` and that drive id is the numeric id in the webapp URL
  (`https://ksuite.infomaniak.com/all/kdrive/app/drive/12` → `12`).

### Confirmed endpoint list

- **Base:** `https://api.infomaniak.com` (no global version prefix — the version is per-path:
  `/2/...` for file-metadata/download, `/3/...` for search/list/recents/etc.). The spec's
  expected `https://api.infomaniak.com/2` base is **wrong**; use the host root and put the
  version in each path.
- **Auth:** `Authorization: Bearer <token>` (token created at
  https://manager.infomaniak.com/v3/ng/accounts/token/list with `drive` scope; also needs
  `user_info` + `user_email` for some operations).
- **Drive scope:** all paths are `/drive/{drive_id}/...` where `drive_id` is the numeric drive
  id from the webapp URL.
- **Search (full-text, indexed content):**
  `GET /3/drive/{drive_id}/files/search?query=<q>&limit=<n>&with_path=true`
  - Param name is `query` (confirmed). `limit` 1–50. `with_path=true` includes the file path.
  - Binary files (xlsx, pdf, docx, …) are NOT indexed — for filename lookup use the list
    endpoint recursively. # SPIKE: confirm the exact official doc page (portal is JS-rendered;
    path confirmed via the community client calling the live API successfully).
- **List folder contents:** `GET /3/drive/{drive_id}/files/{file_id}/files`
  - Path-based, NOT `?parent_id=`. The folder id is a path segment.
  - **Root folder id is `1`** (NOT `0`). Confirmed by both the community client default and the
    official `@infomaniak/mcp-server-kdrive` tool descriptions ("default: root=1").
  - Returns an array of `{ id, name, type: "dir"|"file", mime_type, size, ... }`; paginated via
    `cursor` / `has_more` / `response_at`. # SPIKE: confirm pagination param names against the
    official doc page.
- **File metadata:** `GET /2/drive/{drive_id}/files/{file_id}`
  - Note this is the **v2** path (the spec's expected `/drive/{drive_id}/files/{file_id}` was
    missing the version segment). Returns the full file object.
- **Download raw bytes:** `GET /2/drive/{drive_id}/files/{file_id}/download`
  - Confirmed official (developer portal search hit). Returns `application/octet-stream`
  (binary); may `302`-redirect to the actual storage URL. Supports `?as=pdf|text` for
  conversion and an `x-kdrive-file-password` header for protected files. The spec's expected
  `/files/{file_id}/file` path is **wrong** — the correct suffix is `/download`.
- **Response envelope:** `{ "result": "success"|"error"|"asynchronous", "data": <payload or
  array>, "error": <...>, "context": <...> }` — NOT the bare `{ "data": ... }` the spec
  expected. The client must check `result == "success"` then read `data`. Confirmed by both
  the community client (`json.result !== 'success'` → raise; `return json.data`) and the
  `api.infomaniak.com/doc` snippet ("JSON return format with `data`, `error`, and `context`
  fields"). Paginated list endpoints put `cursor`, `has_more`, `response_at` inside `data`
  (or alongside it). # SPIKE: confirm whether `cursor`/`has_more` live at the envelope top
  level or nested in `data` for the list/search endpoints.

### Corrections to the pre-spike assumptions in this doc

The "kDrive specifics" section above and the task prompt assumed:
- base `https://api.infomaniak.com/2` → actually `https://api.infomaniak.com` (version per path)
- search `GET /drive/{drive_id}/search?query=...&with=files` → actually
  `GET /3/drive/{drive_id}/files/search?query=...&limit=...&with_path=true`
- list `GET /drive/{drive_id}/files?parent_id=0` → actually
  `GET /3/drive/{drive_id}/files/{file_id}/files` with root id `1` (path segment, not query)
- download `GET /drive/{drive_id}/files/{file_id}/file` → actually
  `GET /2/drive/{drive_id}/files/{file_id}/download`
- envelope `{ "data": ... }` → actually `{ "result": ..., "data": ..., "error": ..., "context": ... }`

`Kdrive::ApiClient` must be implemented against the corrected paths above.