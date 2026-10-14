# RubyLLM 2.0 Upgrade

Status: Written specification reviewed and approved by the user.

## Goal

Upgrade Nosia to RubyLLM 2.0.0 using the supplied upgrade guide, preserving
existing conversations, attachments, tool results, streaming behavior, MCP
integrations, and application-owned usage accounting.

## Current Findings

- `Gemfile.lock` locks RubyLLM at 1.14.0. The supplied guide starts at 1.16,
  so the intermediate upgrade needs verification first.
- `ruby_llm-mcp` 1.0.1 requires RubyLLM `~> 1.9`; upstream main currently
  declares the same restriction. Compatibility needs more than a lockfile update.
- The checked-in application uses PostgreSQL, bigint IDs, an integer message
  role enum, and custom chat/message behavior. Preserve those existing choices.
- Nosia owns a `TokenUsage` ledger and cached account/chat totals. Keep them
  separate from RubyLLM's new provider-attempt usage ledger.
- The application `Model` and `ToolCall` classes use the old supporting-record
  declarations. The model catalog controller and views also need migration.
- OpenAI-compatible endpoints currently use Chat Completions. Preserve that
  protocol explicitly rather than silently adopting the Responses API.
- Existing unrelated changes include `Procfile.dev` and untracked earlier
  planning documents. Do not modify or commit them.

## Decisions

1. **Include compatibility work.** The user authorized the MCP compatibility
   work needed for RubyLLM 2.0, preserving existing MCP features.
2. **Rename (Recommended).** The user selected the default migration strategy:
   pause AI activity through prepare, backfill, and finish; recover by restoring
   the tested backup and matching application version together.
3. **Approve patched MCP approach.** The user approved a documented, narrowly
   patched vendored copy of MCP 1.0.1 and the upgrade design presented below.
   This preserves existing transports without a separate MCP SDK migration.
4. **Proceed with known baseline.** After testing the unchanged application in
   the isolated worktree, the user authorized continuing with the existing crawl
   test's live embedding request recorded as a baseline error. Do not expand
   upgrade scope to fix unrelated crawl-test isolation.

## MCP Compatibility

Use a narrowly patched, vendored copy of the locked `ruby_llm-mcp` 1.0.1
release. Preserve its transports and the existing `McpServer` interface; port
its RubyLLM-facing tool, content, attachment, message, prompt, and resource
integration to supported 2.0 APIs. Keep the upstream license and provenance,
document the patch, and constrain the dependency to the versions actually
tested. Do not merely relax its gemspec or recreate removed RubyLLM APIs.

An alternative is replacing the bridge with the official `mcp` SDK and an
application-owned tool adapter. That requires a broader SDK upgrade and an
explicit solution for legacy SSE, beyond Streamable HTTP's SSE responses.
Do not silently remove existing transports or return only text for previously
supported multimodal tool results.

## Application and Data Design

- Verify 1.15 and 1.16 compatibility before 2.0, including normalized input and
  cache token semantics. Keep existing historical application totals intact.
- Pin RubyLLM to 2.0.0 rather than implicitly taking the latest 2.x release.
- Generate and review the standard rename-mode prepare, backfill, and finish
  migrations. Account for the existing integer role enum and foreign keys.
- Retain the application chat/message models, IDs, relationships, attachments,
  and custom behavior. Remove old supporting classes from the 2.0 build only;
  let the migration own their tables.
- Replace old API calls throughout completion, relevance checks, enrichment,
  agent skills, tools, embeddings, catalog views, and usage displays.
- Read tokens and provider/model identity through 2.0 public APIs. Keep Nosia's
  `TokenUsage` ledger, Green IT estimates, and counters separate from RubyLLM's
  provider-attempt ledger; avoid replaying historical usage into app counters.
- Preserve Chat Completions explicitly for the existing OpenAI-compatible
  endpoint. Preserve streaming, stop-generation partial answers, blank-message
  cleanup, and instruction append/replacement behavior with regression tests.
- Rehearse migrations only against a disposable PostgreSQL database. Include
  historical text/raw content, tool-result links, usage, integer roles, and
  attachments. Do not migrate the existing development or production database.
- Document backup/restore, the AI maintenance window, phase commands, packaged
  model loading, audits, and restart order. Do not generate or run cleanup in
  this initial deployment; document it as a separately approved later step.
- Run focused Minitest tests, the full suite, Zeitwerk validation, and targeted
  lint/security checks. Use fake provider responses and local MCP transports
  rather than real paid API calls or production MCP credentials.

## Components and Data Flow

The Rails initializer selects the existing endpoint and Chat Completions
protocol. Nosia's chat/message models retain domain behavior, while RubyLLM
owns its registry, tool-call records, and provider-attempt usages. Catalog
controllers and views read metadata through `RubyLLM.models`, using provider
and model identifiers rather than old application-model primary keys.

Completion, embeddings, and agent skills read tokens from their result's
`tokens` object and continue writing Nosia's application-owned usage records.
Existing ledger column names may remain unchanged: this is an adapter change,
not a rewrite of historical application accounting. Preserve idempotency and
the established account/chat counter behavior. UI estimates use the same
provider model identifiers and normalized token buckets as the new readers.

MCP server clients continue to support local, stdio, legacy SSE, and Streamable
HTTP integrations. The vendored bridge translates remote tools and results
through RubyLLM 2.0 public APIs; Nosia's existing engine adapter does the same
for local tools. Preserve authentication configuration and the deployment's
stdio opt-in and URL validation. Credentials must not enter tool schemas.

Keep existing application role enums and querying behavior, updating queries
that currently assume `tool_calls` is an application association. Use the
internal persisted tool-call association where a database query is required,
and the public tool-call hash where actual RubyLLM calls are required.

## Migration and Failure Handling

The initial release contains prepare, backfill, and finish migrations only.
Do not drop supporting tables manually. Review generated SQL against existing
foreign keys and integer role encoding in every phase, including raw SQL that
might compare roles to strings such as `'assistant'`. Verify fresh schema loading and
migration rehearsal against representative legacy data.

Production deployment requires a tested backup, completion or cancellation of
pending legacy tool calls, and paused AI web requests, workers, schedulers,
and retries throughout all three phases. Do not enable automatic deletion of
incomplete tool calls. Load the packaged model registry after migration, audit
the converted records, then restart processes and resume activity.

If a phase fails, keep affected activity paused, repair the reported condition,
and retry according to RubyLLM's supported progress tracking. Do not bypass
verification or fabricate missing model identity or historical prices. To
abandon rename mode, restore the pre-upgrade backup and matching 1.16 build
together; changing the gem version alone is not recovery. Document that full
database restoration also removes unrelated writes made after the backup.

Cleanup remains a later deployment after production verification and separate
approval. New 2.0 writes do not maintain the retained legacy columns.

## Verification and Acceptance

1. Bundler resolves RubyLLM 2.0.0 and the documented local MCP dependency, with
   unrelated dependency updates avoided unless required by compatibility.
2. Regression tests cover instruction replacement/appending, model selection,
   completion and embedding token recording, agent-skill accounting, model
   catalog rendering, streaming, stop-generation partial persistence, and
   preservation of legitimate blank tool-calling assistant messages.
3. MCP tests cover keyword tool invocation, schemas including nested inputs,
   credentials kept out of schemas, text and structured results, attachments,
   prompts/resources, errors, and transport lifecycle behavior used by Nosia.
4. A disposable PostgreSQL rehearsal verifies unchanged chat/message IDs and
   counts, integer roles, text and raw content precedence, attachment links,
   tool-result links, historical usage, and unchanged application ledger totals.
   Retry testing establishes that a resumed backfill does not duplicate usage.
5. No application runtime code relies on removed supporting-record classes or
   old RubyLLM API names. Historical migrations are reviewed for removed calls
   and tested through fresh setup without unnecessary historical rewrites.
6. Focused and full Minitest results, Zeitwerk checks, and lint/security results
   are recorded accurately. Environment blockers are reported, not represented
   as successful verification.
7. Deployment documentation includes the 1.16 prerequisite, migration timings
   from rehearsal, pause/drain instructions, audit commands, model loading,
   restart order, backup recovery, and deferred cleanup.

## Scope Exclusions

- No production deployment or mutation of existing development data.
- No automatic cleanup, copy-mode compatibility code, or canary version switch.
- No protocol switch to OpenAI Responses and no new AI product features.
- No replacement of Nosia's usage ledger, billing policy, or Green IT dataset.
- No changes to unrelated user work, stack choices, IDs, or tenancy design.

## Design Review Record

- [x] Explore project context and recent changes.
- [x] Confirm whether MCP compatibility work is in scope.
- [x] Choose migration mode and recovery requirements.
- [x] Compare implementation approaches and approve the design.
- [x] Finalize and self-review this specification for scope and consistency.
- [x] Independent specification review: approved, with no blocking issues.
- [x] User reviewed and approved the committed written specification.

Application and dependency changes begin only after the implementation planning
step. The isolated-worktree baseline has 328 runs, 1030 assertions, no failures,
and one accepted error: the existing public-host crawl test reaches an unstubbed
embedding request. Fake credentials and an unreachable local endpoint ensure
the verification process cannot make a paid provider request.

## References

- User-supplied RubyLLM 1.16 to 2.0.0 upgrade guide (authoritative upgrade scope).
- [RubyLLM 1.x upgrade guide](https://rubyllm.com/v1/upgrading/).
- [RubyLLM v2.0.0 source](https://github.com/crmne/ruby_llm/tree/v2.0.0),
  including its versioned documentation and migration generators.
- [ruby_llm-mcp v1.0.1 source](https://github.com/patvice/ruby_llm-mcp/tree/v1.0.1).
