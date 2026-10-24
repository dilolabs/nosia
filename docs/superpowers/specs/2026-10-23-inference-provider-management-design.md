# Inference provider management, onboarding, and model selection

**Status:** Written specification approved; implementation planning authorized. Application implementation has not started.

**Date:** 2026-10-23

## Goal

Replace deployment-time inference configuration with RubyLLM-backed management in Nosia. Provide guided setup after the first signup, ongoing management at `/models`, a changeable default chat model, per-new-chat selection, and safe embedding configuration changes.

## Requested scope

- Remove Docker Model Runner as a required deployment dependency, retaining it as an optional provider connection; default to Ollama running on the host, outside Docker.
- Move LLM, embedding, guard, chunking, and retrieval configuration out of `.env` and `docker-compose.yml` into the application.
- Offer onboarding immediately after the first signup and make configuration accessible later under `/models`.
- Initially suggest `qwen3-embedding:8b` with 4096 dimensions on host Ollama. Expose embedding dimensions, chunk size, chunk overlap, and retrieval fetch K.
- Recommend a default chat model using system RAM and the installed Ollama catalog. Prefer a suitable installed model; support automatically pulling the recommended model when it is missing.
- Expose chat-model temperature, max tokens, and top P.
- Allow changing the default LLM at any time and selecting a different model when starting a new chat.
- Warn before changing embedding models because existing content needs new embeddings; handle storage changes when vector dimensions differ.
- Improve onboarding and `/models` using the ui-ux-pro-max skill and browser-based mockups.

## Project findings

- Actual dependencies are Rails 8.0, RubyLLM 2.0.0, PostgreSQL/pgvector, Hotwire, Tailwind, Minitest, and fixtures. Some general repository guidance describes a different database stack; the current application and schema are the relevant baseline.
- `/models` currently exposes a read-only RubyLLM catalog and catalog refresh. It does not persist provider connections or application inference settings.
- Chat and embedding execution hard-code the OpenAI provider with environment-sourced endpoints and credentials.
- Chat creation accepts a model, but completion defaults subsequently select `ENV["LLM_MODEL"]` again. Per-chat selection must survive subsequent turns.
- The checked-in `chunks.embedding` column is `vector(4096)`, while the runtime dimensions fallback is 768; `documents.embedding` is separately `vector(768)`. A shared fixed-width vector column makes account-specific dimensions an architectural decision, not just a form field.
- `install.sh` and `install.ps1` also generate inference-related deployment configuration and must be considered when removing Docker Model Runner.
- Existing UI conventions use neutral surfaces, green accents, light/dark themes, existing fonts/SVG assets, and English/French localization. A feature-specific improvement should not introduce unrelated rebranding or a frontend framework.
- Existing uncommitted files are user work and remain untouched.

## Delivery boundaries

1. Provider connections, persisted inference settings, RubyLLM execution context, and deployment cleanup.
2. First-run onboarding, model recommendations/downloads, `/models` management, and new-chat model selection.
3. Embedding configuration changes, rebuild lifecycle, dimension handling, and retrieval consistency.

These are coupled slices of one feature, not independent products. The implementation plan must order the foundation/import first, generation-safe storage/rebuilds next, and final UI/deployment cutover last, with test/review checkpoints. Do not expose an embedding-change action before safe replacement exists, or remove legacy deployment inputs before the import path is available. This specification is not authorization to implement.

## Interface approaches

1. **Guided onboarding + unified workspace (selected):** First-run steps for connection, model selection, and review/preparation. `/models` foregrounds active conversation and knowledge defaults, readiness, and provider health, with separate provider forms, catalog, and advanced settings. Adds structure but keeps expensive changes explicit and understandable.
2. **Settings-first:** One long editable configuration page. Direct for expert operators, but dense across all RubyLLM providers and harder to distinguish immediate defaults from downloads/rebuilds.
3. **Catalog-first:** Model discovery cards lead, with provider/settings controls attached. Convenient for frequent switching but scatters configuration and obscures current operational state.

Visual comparison: `.superpowers/brainstorm/252746-1792765974/inference-layout-directions.html` (ignored design reference).

## UX research notes

- The initial ui-ux-pro-max design-system search returned a marketing hero/CTA pattern that does not fit this administration workflow. The narrower progressive-disclosure UX retry returned unrelated typography guidance. Neither result is accepted or persisted as the feature's design system.
- Until relevant focused guidance is verified, use clearly labeled general web UX principles and the application's existing visual conventions rather than adopting unrelated generated branding.
- Verified focused `error summary validation` UX guidance: retain inline errors, associate them with fields, and focus a linked error summary after failed multi-field submission.
- Verified focused `progress indicators background tasks` UX guidance: expose explicit steps and progress for multi-step work rather than silent waiting. Apply this to onboarding, downloads, and index rebuilds, with appropriate web accessibility semantics.

## Approved detailed UX

- After first-admin signup, resume a three-step onboarding flow: connect a provider, choose conversation/knowledge models, then review and prepare. Saving a step persists progress; a provider outage does not lose completed fields. Do not require creating another account or reinstalling Nosia to retry.
- Default to host Ollama, using the proper native/Docker host address and verifying connectivity. Expose editable inference-host RAM with detected/confirmed provenance. Do not assume the endpoint is reachable merely because the hostname is populated.
- Prefill `qwen3-embedding:8b`, 4096 dimensions, chunk size 512 characters, overlap 128 characters, and retrieval K 3. Keep the requested embedding choice visible; warn rather than silently substituting a smaller model on low-memory hosts. Dimension support must be verified with the selected provider/model.
- Present generation controls as progressive disclosure, with baseline presets of temperature 0.1, max output tokens 1024, and top P 0.9 where supported. The recommendation rules below may suggest a larger output budget on larger hosts. RAM informs model/context/output-budget recommendations; sampling values are model presets rather than invented RAM-derived statistics.
- Show models, download estimates (or explicitly unknown sizes), and hardware warnings before the confirmation action. Automatically pull missing Ollama models only after confirmation. Preparation has persistent progress and retries; leaving the page must not interrupt work.
- `/models` uses Overview, Providers, Catalog, and Advanced navigation. Overview displays active conversation defaults, knowledge settings, connection health, and any download/rebuild status. Keep configuration forms focused rather than one giant save operation.
- New-chat composition includes a provider-qualified model picker. Saved chats display their selected model read-only; changing the default affects new chats only. Existing account, attachment, skill, and MCP controls remain intact.
- Only admins can manage installation configuration. Other users may browse safe model details and choose ready chat models; credentials, connection diagnostics, and mutation actions are not exposed to them.
- Use existing Nosia fonts, SVGs, neutral/green styling, light/dark support, and both English/French locale files. Support keyboard navigation, clear labels, inline validation plus linked summaries, announced progress, and narrow layouts without clipped fields.

Detailed visual reference: `.superpowers/brainstorm/252746-1792765974/guided-workspace-detail.html`.

## Approved configuration and execution architecture

### Domain boundaries

| Unit | Responsibility and public contract | Dependencies |
| --- | --- | --- |
| Provider connection | Persist a named instance-wide connection, encrypted credentials, provider-specific typed configuration, and connection/catalog health; produce an isolated RubyLLM context. | Installed RubyLLM provider registry; Active Record Encryption. |
| Configured model | Bind a connection to a RubyLLM-owned model record and verified operation capabilities; supply generation presets and readiness. | Provider connection; `RubyLLM::ActiveRecord::Model`. |
| Installation inference settings | Point to the default conversation model, optional guard model, active knowledge generation, and retrieval controls. | Configured models and knowledge generations. |
| Model recommendation | Rank installed suitable Ollama models against confirmed host RAM, with a curated fallback when a download is needed. Return reasons, estimated sizes, warnings, and editable defaults. | Host-memory provenance; Ollama catalog/show metadata; bundled reviewed recommendation profiles. |
| Model download | Persist an idempotent Ollama pull operation with progress, error, and retry state. | Named Ollama connection; Ollama HTTP API; Solid Queue. |
| Chat | Retain its selected configured-model identity and a snapshot of generation options; resolve execution through that connection on every turn. | Configured model; isolated context; existing chat/MCP/source behavior. |
| Knowledge generation | Own immutable embedding/chunk-processing configuration and a complete set of generation-tagged chunks; expose pinned retrieval and readiness. | Configured embedding model; account-owned sources/chunks; pgvector. |
| Knowledge rebuild | Own the pending generation's manifest, per-source revision checkpoints, progress, cancellation, and activation readiness. | Knowledge generation; durable source-change journal; shallow Solid Queue jobs. |

Controllers remain thin REST resources; domain methods own logic, and shallow Solid Queue jobs call domain methods. No new services/queries/policies framework or frontend dependency is introduced. Connection/default state is instance-wide and admin-authorized; all chats, chunks, sources, citations, and usage remain account-scoped.

### Provider coverage and secrets

- Offer every provider registered by the installed RubyLLM version, plus named OpenAI-compatible and Docker Model Runner presets. Current native registry: Anthropic, Azure, Bedrock, Cohere, Deepgram, DeepSeek, ElevenLabs, Gemini, GPUStack, Mistral, Ollama, Ollama Cloud, OpenAI, OpenRouter, Perplexity, Vertex AI, and xAI.
- Connections are not equated with supported operations: speech-only providers can be configured but are not offered as chat/embedding/guard models. This feature does not add speech/image/video workflows.
- Each provider form has typed, allowlisted fields derived from supported configuration metadata with explicit auth-mode validation. Support region/project/location, access keys/session tokens, service-account JSON, and supported workload identity. Never accept executable Ruby, arbitrary credential-provider objects, or server filesystem paths as form values.
- Encrypt secrets at rest, mask existing secrets, preserve them when a field is left blank, and provide an explicit replace/clear operation. Filter credentials, request headers, and sensitive diagnostic bodies from parameters, logs, broadcasts, and normal-user responses.
- Execute and refresh each connection with its own RubyLLM context. Never mutate process-global provider credentials to switch connections. The configured-model binding distinguishes identical provider/model IDs on different endpoints while retaining RubyLLM's model records as catalog metadata.
- Support intentional admin-configured local/private endpoints without relaxing URL validation for uploaded sources or MCP resources. Restrict inference URLs to HTTP(S), reject embedded credentials and metadata/link-local targets, and prevent unapproved redirect/DNS target changes. Do not expose a public inference proxy.
- Changing endpoint/provider identity creates a new connection revision rather than silently reassigning saved chats or a working embedding index. Credential rotation may update credentials for the same connection identity. Prevent deleting connections still referenced by chats, defaults, guards, active indexes, or running operations.

### Recommendations and generation controls

- Recommendation is an estimate, not a hardware benchmark or a guarantee of model quality. Host RAM is the baseline signal; do not infer GPU VRAM or remote-host memory from Nosia's own container.
- Prefer an installed text-chat model with the capabilities needed for Nosia's tools, whose conservative estimated memory fits the host budget including OS/application headroom and the selected embedding model. Exclude embedding-only models from chat recommendations and chat-only models from embedding selection.
- If no installed model is suitable, recommend from the explicit Qwen3 tags in the table below, rather than an unbounded `latest` model. An unverified memory estimate is not a readiness claim.
- Cap output/context settings to verified model/provider limits. Temperature/top P are model presets, not values calculated from RAM. Defaults remain editable; unsupported controls are explained and omitted from outgoing requests rather than blindly passed to every provider. Preserve top K as an advanced setting only for providers/models that support it.
- Verify embedding capability and actual returned vector length before marking a knowledge configuration ready; an editable dimensions field does not imply every model accepts arbitrary widths.
- Pull models through the configured Ollama HTTP API rather than requiring an Ollama executable inside the Rails containers. Persist confirmed requests, deduplicate duplicate submits, report progress, and resume/retry safely after worker restarts. Never install/start Ollama or execute arbitrary commands from the UI.

#### Initial deterministic recommendation policy

Use bytes internally and display memory in GiB. Let `R` be trustworthy, admin-confirmed inference-host RAM. Reserve `max(2 GiB, 25% of R)` for the OS/Nosia/other work. Estimate each model's loaded weight footprint at `1.5 × advertised model-file bytes`; this deliberately conservative heuristic is not an assertion about actual Ollama memory usage. Add 1 GiB of chat runtime/context allowance for a 4096-token context, or 2 GiB for an 8192-token context. Subtract the selected embedding model's estimated weight footprint when it shares the inference host; use confirmed distinct-host information to omit that reservation. In uncertain local-host cases, retain the reservation conservatively. An independent cloud embedding service does not consume the Ollama host's RAM budget.

Installed-model metadata comes from the selected connection's tags/show catalog, not a global catalog with credentials swapped. Among installed text-chat/tool-capable models with known estimated footprints that fit the remaining budget, prefer a fitting candidate from the reviewed Qwen3 family (largest fitting candidate), then another fitting installed model ordered by decreasing advertised file size and model ID as the deterministic tie-break. File size is a resource proxy, not a quality score. If no installed candidate fits, choose the largest fitting fallback from this table:

| Explicit tag | Initial approximate download bytes, decimal GB |
| --- | --- |
| `qwen3:0.6b` | 0.523 GB |
| `qwen3:1.7b` | 1.4 GB |
| `qwen3:4b` | 2.5 GB |
| `qwen3:8b` | 5.2 GB |
| `qwen3:14b` | 9.3 GB |
| `qwen3:32b` | 20 GB |

The requested `qwen3-embedding:8b` has an initial approximate 4.7 GB download. These are reviewed fallback estimates, not exact progress totals; use actual installed metadata or Ollama pull totals when available, and label stale/unknown sizes accordingly. Store the resolved digest for provenance and use the independently addressable embedding identities described below; storing a digest alone does not pin a RubyLLM request. Refreshing/re-pulling an embedding tag to a new digest is an embedding-identity change and needs the same replacement workflow.

| Confirmed RAM | Suggested context ceiling | Suggested max output tokens |
| --- | --- | --- |
| Below 16 GiB | 4096 | 1024 |
| 16 GiB or more | 8192 | 2048 |

Reduce these ceilings to the verified model/provider context/output limits and reserve at least three quarters of the selected context for input/history/tools (output must not exceed one quarter). For cloud or non-Ollama connections, start from the baseline 1024 output tokens, capped by verified limits, rather than applying unrelated local RAM. Model-specific supported sampling controls start at temperature 0.1 and top P 0.9; leave unsupported controls unset with an explanation. A model's advertised context window is not a reason to allocate its full KV cache on a small host.

If RAM, a candidate's footprint, or necessary capabilities cannot be verified, do not label it a hardware-fit recommendation. Ask for RAM confirmation or offer a clearly unverified manual choice. If no candidate fits alongside the requested embedding model, keep the embedding choice visible, show the insufficient-budget warning, and offer a smaller embedding model/manual model choice rather than silently downgrading. The admin may explicitly acknowledge a memory-risk override, but cannot bypass capability, authentication, finite-vector/dimension, or readiness checks. Sample generation/embedding readiness probes run only after the review/confirmation action and disclose potential cloud usage costs; connection/catalog checks before that must not generate paid completions.

### Fresh-install retrieval defaults

- Retrieval K is 3 and augmented adjacent-chunk context is enabled.
- Chunk size is 512 characters and overlap is 128 characters. Document peer merging is disabled initially; its advanced enable/limit controls are persisted configuration, not environment inputs. If enabled, the merged-chunk token limit starts at 1024 and must be positive. Preserve explicitly valid imported behavior rather than overwriting it with these fresh-install defaults.
- Guard checks are disabled initially. Enabling them requires a ready text-chat model/connection. Preserve current relevance-check/skill-detection behavior rather than redesigning guard algorithms in this feature.

### Runtime and deployment transition

- Backfill historical chats to their actual persisted model identities; never overwrite them with today's default. New chats capture the selected connection/model/options; later changes to the default do not change an existing chat's model or sampling snapshot. Request-scoped API overrides remain validated and do not mutate saved global defaults.
- Route chat completions, guard checks, skill detection, enrichment, query embeddings, indexing embeddings, token attribution, and API model/default resolution through persisted settings and isolated contexts. Web and worker processes must not depend on stale process-local environment-derived defaults.
- Provide an idempotent one-time import task for existing environment settings. Preserve existing provider identity, secrets, generation/retrieval values, and the actual stored embedding width. Detect incompatible/mixed old vector data rather than relabeling it as the requested new default.
- Import occurs with the legacy environment available, before removing its entries. An existing deployment is not switched to Qwen embeddings until an explicitly confirmed replacement is ready. New installs start without inference environment configuration.
- Remove Docker Model Runner Compose model declarations and all inference settings from deployment templates, installers, and documentation after the import path exists. Keep database/application/encryption infrastructure settings. Update the user's local `.env` only after a successful import, without printing secrets or modifying unrelated entries.
- Host Ollama uses `localhost:11434` for native Rails and the host-gateway address for Docker. Document Linux host-gateway mapping and safe host binding/firewall access; do not publish an unauthenticated Ollama endpoint to the Internet.
- Fresh database preparation and migration boot cannot query installation settings before their table exists. Remove the historical embedding-dimension migration's dependence on mutable application-model/environment defaults; preserve its historical schema intent while making the new final schema independent of inference configuration. Existing populated data is validated/backfilled before enforcing new generation references.
- The compatibility importer is an explicit operator task, not a database-migration network call or an initializer that imports on every boot. It imports `AI_BASE_URL`, `AI_API_KEY`, optional `EMBEDDING_BASE_URL`, all `LLM_*`/`EMBEDDING_*` configuration used by Nosia, `CHUNK_SIZE`, `CHUNK_OVERLAP`, `CHUNK_MERGE_PEERS`, `CHUNK_MAX_TOKENS`, `RETRIEVAL_FETCH_K`, `GUARD_MODEL`, and `AUGMENTED_CONTEXT` where present. Missing/invalid legacy values are reported for correction rather than silently assigned to existing vectors. Once imported, normal operation reads the database only.
- Preserve distinct legacy embedding/chat endpoints during import. Attach existing chunks to a legacy generation only after checking actual stored vector widths against the imported identity; report unprovable/mixed embedding provenance for admin confirmation/remediation. Historical sampling choices were not persisted, so use imported effective settings as their initial explicit snapshot and report that limitation.
- The ordered upgrade path is: back up data; apply the compatibility schema; run/verify import with old inputs still supplied; start DB-configured web/workers; verify current chat/retrieval; then remove legacy inference entries/model declarations. Never delete unrelated `.env` settings or print their values. Generate fresh-install Compose/installer output without those inputs from the start.

#### API configured-model selection contract

- `GET /v1/models` returns ready chat-capable configured models, one entry per saved connection/model binding. Its canonical `id` is `nosia/<opaque-configured-model-id>`; the opaque ID is stable for that binding and contains no credentials, endpoint, or account identity. Duplicate underlying provider/model names therefore have distinct public identifiers. Keep the existing OpenAI-compatible list envelope and `owned_by: "nosia"`; optional safe display metadata can identify the model and admin-chosen connection label.
- Both chat/completion request routes accept the canonical identifier in the existing `model` field. Resolve it to exactly one ready configured binding before creating the chat or opening an SSE stream. Do not interpret a canonical ID as a raw backend model name or fall through to another connection if it is missing/unavailable.
- An omitted/blank `model` selects the installation's current default once at request creation; snapshot that configured-model identity and the validated effective generation options on the created chat. A subsequent default change cannot reroute the request or a saved chat. Request overrides affect that request/chat, never the installation default.
- For compatibility, an exact legacy bare backend model ID remains accepted only when it matches exactly one ready configured chat model across saved connections. Also accept the old response-style `nosia:<backend-model-id>` prefix as the same legacy lookup. A bare ID matching more than one connection fails with HTTP 400 and error code `ambiguous_model`, directing the client to the canonical IDs from `/v1/models`; never select the default connection implicitly to resolve ambiguity.
- An explicit unknown, unconfigured, disabled, or operation-incompatible model fails with HTTP 400 and code `model_not_found`. Missing installation defaults produce HTTP 503 and code `inference_not_configured`; runtime provider unavailability produces a redacted HTTP 503 with code `inference_provider_unavailable` rather than fallback routing. These errors use an OpenAI-compatible `{ error: { message:, type:, code: } }` envelope (`invalid_request_error` for selection/validation, `server_error` for configuration/provider availability), with actionable messages and no secret values. Reject invalid selections before streaming starts; a provider error after streaming has started is reported as a redacted SSE error event followed by stream closure, not a different HTTP status or a second provider attempt.
- Streaming chunks and nonstreaming completion responses both report the selected canonical identifier in their `model` field. Do not report a different environment/default model or add a second `nosia:` prefix. Preserve account/API-token authorization, message shapes, stream framing, and unrelated API behavior. Document the catalog/identifier compatibility rules in the upgrade guide.

## Approved embedding lifecycle, failure handling, and verification

### Versioned knowledge generations

- Represent embedding connection/model identity, exact dimensions, chunk size/overlap, and chunk-processing options as an immutable knowledge-generation configuration. A distinct active-generation reference controls retrieval for the whole installation, while every source/chunk retains account ownership.
- Add a generation reference to chunks and use pgvector storage that can hold different widths in different generations. Validate each returned vector against its generation's exact width and reject mismatches. Queries bind to one generation and its embedding model before embedding the query; they never compare vectors across generations.
- This intentionally replaces the current fixed shared `vector(n)` column with dimension-flexible storage in a normal deployment migration. There is no destructive live `ALTER COLUMN` issued by an admin form. A later 4096→1024 change writes a separate 1024-dimensional generation while the 4096-dimensional generation remains usable.
- Preserve RubyLLM model metadata and immutable configuration identifiers for both generations. Refreshing a provider catalog or changing global defaults must not relabel existing embeddings.
- Preserve the unrelated unused `documents.embedding` data/column; do not rebuild or delete it as part of active chunk retrieval. Clearly identify chunk embeddings as the configuration managed by this feature.
- Initial generations use exact pgvector distance calculation, including the default 4096-dimensional configuration. The existing full-precision HNSW approach is limited to at most 2000 dimensions and requires fixed dimensionality, so its legacy index is removed safely in the deployment migration rather than attached to mixed-width storage. Preserve relational account/generation indexes. Approximate generation-specific indexing and a new vector database are out of scope; surface the potential exact-search performance trade-off for large imported collections.

#### Independently addressable embedding models

RubyLLM sends a serving model name, not a cached digest. For Ollama, each knowledge generation therefore uses a Nosia-managed, generation-specific model alias created through Ollama's HTTP copy API. Store both the public/source tag and the private serving alias with its verified digest. Build/query requests send the generation's serving alias, while the UI, RubyLLM catalog binding, and usage display retain the recognizable source model identity. Old and replacement aliases must remain independently addressable through rebuild, cutover, and retirement; do not repoint an existing generation's alias to new weights.

Before Nosia re-pulls a source tag, verify that the active generation already has a working private alias resolving to its recorded digest. After the new pull, create a distinct pending-generation alias, verify its digest, and only then run probes/build embeddings. Ordinary base-tag pulls must never change the active alias. Deduplicate/serialize Nosia-managed alias/pull operations per connection, hide internal aliases from ordinary model discovery, and disclose managed alias creation in setup/rebuild confirmation. An alias may share underlying Ollama blobs; do not count a second full weight download unless the underlying digest actually differs.

Verify the serving alias identity at embedding request boundaries, including after a build batch before publishing its vectors. If an expected alias is missing or its digest changes unexpectedly, fail closed: do not substitute the source tag, retry against different weights, or publish a mixed-generation batch. A pending build becomes failed; an affected active index reports knowledge search temporarily unavailable until the admin restores the exact serving identity or completes a replacement. Other chat/configuration functionality remains available. External host administrators must not mutate/delete Nosia-managed aliases; no application can guarantee old-model availability if an operator removes its underlying model data.

Non-Ollama embedding providers must likewise keep old/new serving identities independently addressable when changing an existing model in place—for example, immutable versioned IDs or separate endpoint revisions. If the backend cannot do so, require a distinct model ID/connection before a zero-downtime replacement; do not claim that a stored fingerprint can pin a mutable remote deployment. Retire only Nosia-managed aliases after the corresponding generation is safely unreferenced; never delete operator-owned model tags or unrelated host models automatically.

### Rebuild and cutover

1. Validate the proposed provider/model/dimensions and chunk settings structurally and against available metadata, without unconfirmed downloads or paid probes.
2. Show an impact review with old/new settings, affected source counts across accounts, additional storage/provider-use warnings, and explicit confirmation. After confirmation, pull missing models and run readiness probes; a real embedding probe must return the requested number of finite, nonzero-norm vector values. A model/embedding-connection identity or dimensions change always requires re-embedding, even if the resulting widths match. Chunk size/overlap or effective chunk-processing changes require re-chunking and re-embedding. Changing retrieval K alone does not rebuild stored data.
3. Create a persisted pending generation and durable rebuild operation. Only one replacement build may run at a time; a second settings request must explicitly wait, cancel/replace, or discard its draft rather than overwriting an in-progress target.
4. Build replacement chunks from stored, available source content, without destroying active chunks. Use resumable per-source revision tracking and idempotent writes. Unchanged chunk boundaries may reuse chunk text but must still obtain vectors from the new embedding identity. Do not unnecessarily recrawl websites or call the chat model again solely to switch embedding models.
5. Continue ordinary source indexing into the active generation. Source creates/edits/deletes during a rebuild are journaled durably and reconciled into the pending generation. Workers do not resurrect deleted sources or publish chunks for superseded content revisions. Account ownership and attached-source isolation remain enforced.
6. Activate only after every eligible current source revision is represented (or an existing failed/unavailable source is explicitly reported as excluded), there are no pending source changes, and no rebuild step has failed. Coordinate source-revision commits and the generation-pointer update so a concurrent write cannot be lost at cutover. Brand-new rebuild failures block activation and cannot be silently excluded.
7. Atomically switch the active-generation reference. New retrievals use the new query embedder and matching vectors; retrievals already in flight finish against their pinned old generation. Chat-model selection does not change during this switch.
8. Retain old serving data until no in-flight retrieval/indexing work references it. Garbage-collect obsolete uncited vectors/chunks asynchronously after safe retirement, but preserve chunk text/metadata referenced by historical message citations. Scope adjacent-chunk lookup to the same generation so old and new positions cannot mix. Initial scope includes retry and safe cancellation of pending builds, not a separate user-facing historical-index rollback feature.

#### Concurrency and retirement contract

Source mutations append a monotonically ordered, account-scoped source-revision event in the same database transaction as the content/create/delete change. They briefly coordinate through the installation-settings row; no provider/network call occurs while that row is locked. Rebuild checkpoints record source identity/revision and last reconciled journal sequence. At cutover, acquire the same short settings-row lock, verify that pending work is empty and the reconciled sequence still equals the committed journal high-water mark, then update the active reference. A subsequent source mutation sees the new reference; a prior committed one cannot fall between readiness and activation.

Each chat/API response pins the active generation before generating its query embedding and retains the pin until retrieval, adjacent-context materialization, and message citation persistence finish. PostgreSQL generation-specific shared advisory locks provide the pin; retire/cleanup obtains a nonblocking exclusive lock and skips busy generations. Acquire the initial pin while briefly holding the settings-row lock, but release that row lock before network work. Ensure session locks are released on every exit path; a crashed connection releases its advisory lock. Cleanup checks that the generation is no longer active/pending and that no index job may publish into it; late jobs are fenced by generation/revision checks. Thus cleanup cannot race a response that has not yet recorded its citations. Do not introduce an independent distributed-lock service.

Cleanup may drop obsolete vector values while retaining cited chunk text/metadata and any contextual neighbors needed by the historical citation view. Rebuild-related cleanup must not break historical citations. Explicit user deletion of a source/account continues to honor existing deletion semantics rather than retaining content contrary to that request.

### Failure and validation behavior

- An invalid endpoint, missing authentication, unsupported model operation, unreachable host, or dimension mismatch prevents activation and produces field-level/contextual errors without exposing secrets. A failed connection test is not proof that saved historical chats should be switched elsewhere.
- A download/rebuild failure retains the working generation and shows its failed stage plus retry/cancel controls. Worker crashes and retries must not create duplicate downloads, chunks, activations, or usage events. Persist a heartbeat/checkpoint and recover abandoned operations after restart rather than leaving them permanently running.
- No silent fallback to a different provider, model, or dimension. Low-memory choices and unknown download sizes must be explicitly identified; the admin may acknowledge estimates, but actual readiness checks still must pass.
- Require positive integer chunk size, `0 <= overlap < chunk_size`, retrieval K in `1..100`, positive output limits within verified model bounds, supported sampling ranges, and integer dimensions in `1..16000` further restricted to the selected model/provider's verified supported width/range. Preserve imported out-of-range retrieval K for explicit correction rather than silently broadening ordinary-user requests. Protect concurrent admin edits with stale-update detection.
- Required chat and embedding configuration must both pass readiness checks before completing first-run setup; browsing/editing configuration and logging out remain possible while setup is incomplete. If an existing deployment's imported index is valid, it stays active while replacement settings are drafted.

### Verification scope

- Minitest and fixtures cover encrypted secrets and redaction, admin-only mutation, safe normal-user catalog responses, and concurrent execution through two connections of the same provider without credential/endpoint leakage.
- Test model recommendations for installed/missing/incompatible models, confirmed/unknown memory, small-RAM warnings, embedding headroom, output caps, and deterministic defaults. Fake external services rather than depending on live cloud credentials or downloading large models in tests.
- Test confirmed and deduplicated downloads, stream progress, retries, worker interruption/recovery, and connection-specific catalogs. Exercise all native provider form schemas; contract-test provider contexts/auth shapes without requiring live cloud calls.
- Test chosen models across first/follow-up messages, default changes, restarted workers, API overrides, canonical IDs, omitted defaults, unique legacy aliases, ambiguous/unknown IDs, guards, skills, enrichment, and accurate token/model attribution. Preserve existing account/MCP/composer/source behavior.
- Test dimension changes and same-width model changes, active-tag re-pulls with independently addressable aliases, unexpected alias/digest changes, chunk-setting changes, retrieval-K-only edits, failed/cancelled/restarted builds, concurrent source edits/deletes, atomic activation, per-account retrieval isolation, pinned old-generation reads, and preserved historical citations.
- Test one-time import idempotency, legacy-model/dimension preservation, incompatible legacy data, fresh database preparation without inference environment values, removal of required Compose models, host connectivity guidance, and generated Unix/PowerShell installer output.
- Browser/system tests cover resumable first-run setup, capability-aware forms, model picking, warning confirmation, download/rebuild progress/error/retry, narrow layouts, keyboard access, light/dark themes, and both supported locales. Run relevant regression tests and the repository's full verification commands before claiming implementation completion.

## Decisions

- “Go” after the committed written specification was presented — Approve this written design and proceed to writing the implementation plan; this does not select an execution mode or authorize unplanned application changes.
- “Good” to Design 3 — Approve versioned background index replacement, dimension-flexible pgvector storage with exact per-generation width validation, atomic cutover, safe failure/retry/cancel, historical citation preservation, retrieval-K-only updates without rebuilding, and explicit disclosure of exact-search performance at 4096 dimensions.
- “Yes” to Design 2 — Approve named encrypted provider connections, isolated RubyLLM contexts, installed-model-first resource-aware recommendations, capability-aware generation controls, per-chat connection/model/options persistence, one-time migration, and HTTP-based Ollama downloads without required Docker Model Runner integration.
- “Good” to Design 1 — Approve the detailed onboarding/workspace flow, proposed initial embedding/chunking/retrieval values, new-chat model picker, existing-chat model retention, access boundaries, progress UX, and preservation of Nosia's styling/localization.
- “A” — Choose guided first-run onboarding plus a unified `/models` workspace, keeping current defaults and readiness visible with dedicated provider/configuration screens and a searchable catalog.
- “One-time import (Recommended)” — Import existing environment-based connections/settings into encrypted database configuration once, preserving existing chat selections and the working retrieval index. Do not continue treating environment variables as runtime configuration after import; remove old entries only after successful import.
- “On setup confirmation (Recommended)” for automatic downloads — Show selected models and estimated download sizes, then automatically pull missing models only after the admin confirms “Download and finish setup.” Downloads run in the background with progress and retry controls.
- “Detect + confirm (Recommended)” for hardware — Use trustworthy memory detection when available, disclose its source, and ask the admin to confirm/enter Ollama-host RAM when detection is uncertain. Container/VM memory must not be misrepresented as confirmed inference-host capacity.
- “Background rebuild (Recommended)” — Keep the current retrieval index serving while constructing a replacement after embedding/dimension/chunking changes. Expose progress, activate only a complete ready replacement, and preserve the old active index on failure; temporary additional storage is acceptable.
- “Optional UI setting (Recommended)” for guards — Preserve existing guard-dependent behavior, disabled by default, with a separately selectable provider/model in advanced settings rather than environment configuration.
- “Docker Model Runner + Ollama + every RubyLLM provider. Multiple saved connections, with encrypted credentials.” — Support the installed RubyLLM provider registry, including complex authentication, plus Docker Model Runner as an optional OpenAI-compatible connection. Removing the dependency does not mean removing optional interoperability.
- “Instance-wide (Recommended)” — Admins manage shared provider connections, chat defaults, and embedding settings for the installation. Users may select an available model when starting a chat. This preserves the existing deployment-wide scope without adding per-account vector schemas.
- “Remove the Docker Model Runner dependency.” — Inference should not require Docker Model Runner.
- “Remove the LLM, embeddings and guard configuration from the .env and docker-compose.yml.” — Configuration should be managed through Nosia instead of deployment files.
- “A new onboarding screen after the first sign up and under /models at any moment.” — Setup must be guided initially and editable later.
- “qwen3-embedding:8b with dimensions of 4096 on a local Ollama backend on the host (and not in Docker) by default.” — Provide the requested local embedding baseline, with disclosed hardware estimates and warnings instead of silent model substitution.
- “Choose an embedding model, its dimensions, the chunk size, chunk overlap, retrieval fetch K.” — Make retrieval/indexing controls available in the interface.
- “Choose a default LLM model, its temperature, max tokens, top P.” — Expose model choice and generation controls without environment edits.
- “By default calculated from the RAM of the system and the Ollama models local catalog if a model is already installed or an automatic ollama pull model if not, based on a recommandation.” — Reduce setup work with installed-model-first, disclosed resource estimates and confirmed automatic model provisioning; RAM informs model/token budgets, while sampling values remain model presets.
- “Choose which LLM model is configured by default at any time.” — Defaults remain editable after onboarding.
- “Choose a different model when I start a new chat.” — A chat must retain its own model selection rather than being overwritten by the current default.
- “Add a warning when I want to change an embedding model because of the need of new embeddings calculation and change dimensions on the database if its on a different dimensions.” — Embedding changes require explicit impact disclosure and a safe rebuild/storage design.
- “Yes” to browser-based mockups. — Use the visual companion for layout comparisons; conceptual requirements continue in conversation.

## Research and specification review

- Provider configuration/context contracts were checked against the installed RubyLLM 2.0.0 source and provider registry.
- Ollama reference documentation: [running models](https://docs.ollama.com/api/ps), [embeddings and dimensions](https://docs.ollama.com/api/embed), and [copying a model to an independent serving name](https://docs.ollama.com/api/copy).
- Reviewed fallback model information: [Qwen3 tags/sizes and tool support](https://ollama.com/library/qwen3) and [Qwen3 Embedding sizes/dimensions](https://ollama.com/library/qwen3-embedding). Download sizes remain estimates and are not hardware-fit guarantees.
- Inline review checked placeholders, internal consistency, scope, and ambiguity. Fresh-context review identified mutable Ollama serving identities and ambiguous API model routing; both contracts were clarified, the output/context recommendation table was aligned, and the revised specification was approved by the reviewer with no remaining blocking issues.
- Reviewer approval is a specification-quality check, not the user's written-spec approval or authorization to implement.

## Review and execution gate

The user approved all three presented design sections and then approved the committed written specification with “Go.” The writing-plans skill has been invoked. Application execution remains behind the resulting implementation plan, execution-mode handoff, and test-first gates.
