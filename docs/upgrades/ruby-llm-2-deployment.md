# RubyLLM 2.0: operator runbook

**Code integration is verified with the known baseline exceptions; production
rollout is not approved by these tests.** See [verification evidence](ruby-llm-2.md#task-8-final-integration-evidence).
This is PostgreSQL rename mode, pinned to RubyLLM **2.0.0** and the locally patched
MCP **1.0.1**. It is not a rolling/online migration. Do not follow the README's
ordinary image-restart procedure for this upgrade.

## Before scheduling maintenance

- Preserve the exact 1.16 application/lockfile checkpoint
  **`a5d446f77e02612da02575b414eaf0822c11b541`**, plus its deployable artifact,
  configuration, secrets, and attachment storage. The verified 1.15 checkpoint is
  `ed873506d0ca30799e19b7afd159bb866918d0ea`. Source commits are **not backups**.
- Take a production-sized snapshot into an isolated environment. Rehearse these
  exact migrations, audits, model load, and recovery using that copy. Measure
  backfill throughput, disk headroom, concurrent index creation, DDL/validation
  locks, and downtime there. The seven-message local fixture's subsecond phase
  timings are **not production estimates**.
- **Test restoring a consistent full database backup and matching 1.16 build
  together before production.** Include attachment files/object storage and any
  separate queue/cache/cable databases in the recovery plan. Record the chosen
  recovery point and prove the restored application works. Neither this restore
  nor a production-sized rehearsal has been performed by the upgrade agents.
- Review all pending migration versions, the deployment entrypoint, and automatic
  restart/migration hooks. Prepare an operator job that survives deployment
  timeouts. Verify the intended database/server identity explicitly; do not rely
  on a default Rails environment or inferred database name. Do not copy the fake
  test keys or scratch database settings into production.
- Arrange maintenance to stop **all AI entrypoints and affected writers**:
  web/API requests (including existing streams), completion/embedding/indexing
  workers, skill execution, scheduled jobs, delayed retries, and external
  integrations. Drain running work before stopping workers; block new work while
  draining. Finish or explicitly cancel pending tool calls under 1.16 and inspect
  their persisted state. There is **no automatic discard option** in this plan.
- Do not start any 2.0 application process on the old schema. Keep AI paused from
  **before prepare through all three phases, model loading, audits, and controlled
  restart**. Stop non-AI writers that touch affected tables too. A whole-database
  restore also loses unrelated writes, so prefer full write maintenance.

These are release gates, not completed checklist claims. Live authenticated MCP
interoperability with the deployment's real servers is also an operator gate.

## Capture the 1.16 baseline while writers are stopped

Use the read-only [before audit](ruby-llm-2-audit-before.sql), which includes the
[shared audit](ruby-llm-2-audit-common.sql). Its names are the **old** `models`,
`tool_calls`, and `chats.model_id`, not the 2.0 schema. Save complete ordered rows,
not just aggregate counts or an assumed matching hash. Output includes private
conversation and storage data: use restricted permissions and secure retention.

```sh
# OPERATOR ONLY: maintenance active, intended database identity checked,
# tested backup/restore and matching 1.16 artifact available.
# REVIEWED_DATABASE_URL and PRIVATE_AUDIT_DIR are explicit operator selections.
umask 077
psql -X --dbname "$REVIEWED_DATABASE_URL" \
  --file docs/upgrades/ruby-llm-2-audit-before.sql > "$PRIVATE_AUDIT_DIR/before.txt"
```

Record message IDs/counts and roles (**system 0, assistant 10, user 20, tool 30**),
all five retained token buckets, original content/raw JSON, attachment/blob links,
tool external/internal IDs and result links, provider-qualified model identities,
the application's complete `token_usages`, and account/chat counters. Retain the
original snapshot too: the content audit intentionally computes the **expected
transformed** plaintext using 2.0.0's renderer, rather than expecting every old
plaintext string to remain identical. Nonblank raw JSON wins over stale text;
blank JSON/NULL preserves plaintext, including NULL.

Resolve unknown provider/model identities before starting; do not invent model
identities or historical prices. A candidate includes every assistant (role 10),
even with all token buckets NULL, plus any message with a reported bucket.

## Execute the checked-in phases, still in maintenance

**Only after all preconditions above:** select the reviewed 2.0 build's environment
and explicit database configuration through the deployment's secret mechanism.
Run migrations from that build without serving traffic or starting workers.
No generator, cleanup, discard, schema load, or database reset belongs here.

The three checked-in versions, in order, can be run separately in the persistent
operator job, outside deployment timeouts:

```sh
# OPERATOR ONLY: tested backup/restore, maintenance, drained/cancelled AI work,
# verified target DB, reviewed 2.0 build; keep every affected writer stopped.
bin/rails db:migrate:up VERSION=20261014152719
bin/rails db:migrate:up VERSION=20261014152720
bin/rails db:migrate:up VERSION=20261014152721
```

Alternatively, under **the same preconditions**, `bin/rails db:migrate` runs
**all pending migrations**, including all three phases. It does not pause between
them; inspect any other pending migrations first. Do not run both alternatives
as a replay procedure. DDL transactions are disabled; backfill batches (default
10,000) commit progress. Concurrent indexes do not make the renames online.

The generated SQL has three narrowly reviewed Nosia adaptations:

1. Assistant-candidate predicates in **each** phase use historical integer **10**,
   not `'assistant'`, without loading today's `Message` model.
2. Backfill/finish verification uses the upstream renderer and null-safe
   comparisons for blank raw JSON/NULL plaintext, still rejecting corruption.
3. Finish preserves the obsolete `messages.tool_call_id` FK but changes its delete
   action to **ON DELETE SET NULL**. RubyLLM 2.0 deletes its internal call before
   the historical result; clearing only that obsolete pointer allows deletion
   without deleting the result. Other existing FKs remain, except the generated
   removal of the old monomorphic tool-call owner FK when ownership becomes
   polymorphic. The replacement is validated and retry-aware; it still takes locks.

## Audit, load the packaged registry, and restart deliberately

1. Run [the after audit](ruby-llm-2-audit-after.sql) against the **new** schema while
   writers remain stopped, **before** loading models. It names `ruby_llm_models`,
   `ruby_llm_tool_calls`, `ruby_llm_usages`, and `chats.ruby_llm_model_id` correctly.
   Its first transaction has the same ordered projections as the before audit;
   compare those sections row-for-row. Its second transaction adds 2.0-only gates.

   ```sh
   # OPERATOR ONLY: same maintenance and verified target as above, after finish.
   psql -X --dbname "$REVIEWED_DATABASE_URL" \
     --file docs/upgrades/ruby-llm-2-audit-after.sql > "$PRIVATE_AUDIT_DIR/after.txt"
   ```

2. Require unchanged message IDs/count/roles, retained columns, attachment/blob
   rows, tool IDs/arguments/signatures/owners/results, and historical provider/model
   identities. Compare expected converted content and raw payloads, including
   NULL/blank variants. Require exactly one succeeded chat usage for every
   historical candidate, with the original five buckets and timestamps. Compare
   per-provider/model bucket totals, not just grand totals. The duplicate and
   raw-mismatch queries must return no rows.
3. All six historical cost fields must remain **NULL**, not zero or recalculated
   from current registry prices. The original Nosia schema has no cost columns;
   its priced-historical count must be zero before any new provider work. Require
   the entire application `token_usages` ledger and account/chat input/output
   counters to be unchanged. **Do not re-backfill the application ledger** from
   `ruby_llm_usages` or recount/replay events as part of this release: that would
   double-count existing history.
4. Require the `message_content`, `tool_results`, `usages`, and `finished` journal
   entries completed and all three migration versions recorded. Inspect indexes,
   constraints, and validated FK actions in the audit output. A fresh schema-based
   install has no migrated history and an **empty** journal; that is different
   from an existing-database upgrade and is valid only for a fresh install.
5. Still paused, load the **packaged offline registry**, not a network refresh:

   ```sh
   # OPERATOR ONLY: finish/audits accepted, same maintenance and verified DB/build.
   bin/rails ruby_llm:load_models
   ```

   The 2.0 task uses `load_from_json` and `save_to_database`. Recheck historical
   ID/provider/model mappings and usage costs afterward. Registry rows/metadata
   can legitimately be added/updated; immutable historical usage is not repriced.
   Network `RubyLLM.models.refresh` is an optional **later**, separately operated
   action, not needed to complete migration.
6. Start only the reviewed 2.0 processes in a controlled maintenance window; verify
   health, authenticated catalog, historical chats/tools/files, JSON and SSE
   completion, streaming/stop, local/remote MCP, embeddings, and new five-bucket
   usage/counter increments. Confirm provider options/temperature support with
   the actual backend (2.0 no longer rewrites unsupported temperatures). Then
   explicitly resume ingress, workers, schedules, and retries. Never let old 1.16
   writers resume against the 2.0 schema.

## Failure and recovery: no `down`

Keep **all AI paused** on any phase, audit, model-load, or smoke-test failure.
Inspect `schema_migrations` and `ruby_llm_v2_backfills`, diagnose the exact phase,
repair through a reviewed forward fix, and retry the failed phase. Prepare and
backfill support pre-finish retry; backfill resumes committed cursors without
duplicating usages. After `finished`, prepare/backfill deliberately reject replay.
Do not delete journal rows, skip validation, or invoke private migration methods
to force progress. RubyLLM copy-mode resume/rollback tasks do not apply to rename.

All three `down` methods are irreversible. To abandon the upgrade, restore the
**tested full database backup and matching 1.16 application together**, plus
consistent storage/configuration. A gem downgrade alone or `db:rollback` is not
recovery. Restoring the whole database loses **all writes since the recovery
point, including unrelated application writes**; communicate that before acting.

Legacy message columns are retained but **not maintained by new 2.0 writes**.
They are not a rollback copy. Cleanup was neither generated nor run and must be
a later, separately approved deployment after reference/FK review and new backups.

## Fresh installs and patch maintenance

Fresh setup uses the checked-in `db/schema.rb` via `bin/rails db:prepare`, as
`bin/setup` already does. Task 8 tested that path in a new guarded scratch database,
not `bin/setup`'s package installation/log cleanup. Full historical replay is
**not supported/verified on this 2.0 build**: the unchanged
`20250926205326_create_models.rb` calls removed `load_from_json!` and application
`Model.save_to_database`. Do not replay it with 2.0 or add runtime legacy aliases;
use schema-based fresh setup. Existing 1.16 databases run only pending migrations.

Keep [MCP PATCHES.md](../../vendor/gems/ruby_llm-mcp/PATCHES.md) and its MIT license,
archive provenance, exact 2.0.0 target, and eleven-file narrow port inventory.
The HTTP-resource validator fails closed until installed; Nosia installs its
existing `UrlGuard` policy. HTTPX does not follow resource redirects by default.
The known DNS-rebinding/validation-to-connect **TOCTOU window remains**; no IP
pinning or general SSRF elimination is claimed. Do not weaken stdio opt-in, URL
guards, or credential boundaries. Replace/remove the vendor path only after a
reviewed upstream release passes the same persistence, binary, sampling,
transport, security, and application contracts—not by loosening its version pin.
