# Native local runtime contract (version 1)

The official `dilolabs/nosia` image supports an opt-in local mode for Nosia.app.
Without `NOSIA_NATIVE_LOCAL=1`, the entrypoint forwards the existing `bin/boot`
command or operator-supplied arguments unchanged. Production SSL and session
settings remain in effect.

With that flag, `NOSIA_URL` must be an explicit `http://127.0.0.1:<unprivileged-port>`
origin. The native initializer configures local cookies, Rails URL generation
and Action Cable for that origin. CSRF protection remains enabled. Publish the
guest Puma port 3000 on host loopback only. Do not publish PostgreSQL or inference
servers on the LAN. Native HTTP is for this private installation only.

The macOS orchestrator supplies `DATABASE_URL`, `DB_HOST`, `AI_BASE_URL`,
`EMBEDDING_BASE_URL`, `AI_API_KEY`, `LLM_MODEL`, `EMBEDDING_MODEL`,
`EMBEDDING_DIMENSIONS`, encryption/session secrets and
`NOSIA_NATIVE_EMBEDDING_FINGERPRINT`. Container loopback is not the Mac: inference
URLs use the observed private host gateway. The two model endpoints use a private
API key and separate aliases. Never log these credentials.

The lifecycle is:

1. Run `ruby bin/nosia-native-capabilities` and compare its protocol, source commit
   and schema with the app's signed resource manifest, before any migration.
2. Back up existing PostgreSQL databases, `/rails/storage` and recovery secrets.
3. Run `bundle exec rails db:prepare nosia_native:prepare_empty_index` without web
   or workers. The second task aligns an empty vector column only; existing
   vectors require an explicit reindex. On an explicit reindex, run `db:prepare`
   first without that empty-index task, then `nosia_native:reindex`.
4. Run `bundle exec rails nosia_native:validate_index`.
5. Start `ruby bin/nosia-native-boot`, with `/rails/storage` attached to this one
   VM only. It supervises Puma and one Solid Queue supervisor; do not start a
   second worker container. Queue-specific worker counts remain configurable.
6. Check `/up`, authenticated `/native/ready`, `nosia_native:check` and actual
   inference requests from Rails. Readiness requires SQL and a fresh Worker
   heartbeat, not just a running supervisor.
7. TERM stops both child process groups; KILL follows after 25 seconds if needed.
   Give the container at least 30 seconds to stop before forcibly killing it.

Temporary native operations can mount a private `/nosia-control` directory and
set a UUID `NOSIA_OPERATION_TOKEN`. The entrypoint validates the token and control
mount before running the command, clears any previous completion for that token,
and atomically publishes `<token>.complete` only on success. Use a fresh token per
operation, so a container CLI returning zero cannot conceal a failed migration.
`nosia-native-backup /backups/<name>.tar.partial` archives the document volume;
the app promotes the archive only after verifying completion.

Changing an embedding model, even at identical dimensions, requires a new
nonblank fingerprint and explicit reindex after backup. An interrupted reindex
blocks index validation, even if the previous fingerprint is unchanged. Retry
`nosia_native:reindex` to resume vectors in the same target space and dimensions;
a different target invalidates all vectors. These offline tasks deliberately
cover every account in the private installation. No automatic migration of Docker
volumes or deletion of existing resources is performed. Schema rollback requires
restoring database, documents and secrets together into an isolated installation;
an older image alone does not undo migrations.

The image labels are `io.nosia.native.protocol=1`, `io.nosia.native.schema` (maximum
14-digit migration prefix) and `org.opencontainers.image.revision` (full Git SHA).
The publishing workflow derives them from the source being built. Build args
`GIT_REVISION` and `NATIVE_SCHEMA_VERSION` must agree with the capabilities script.
Index validation reads the supported schema from the packaged migrations, not
from a runtime schema override, and rejects newer or unmigrated databases.
An incompatible contract change requires a new protocol version. Runtime clients
pin the Linux ARM64 manifest digest rather than following a mutable tag.

`.github/workflows/publish-image.yml` tests the contract and database tasks,
builds and checks an ARM64 candidate, then publishes version/commit tags for
AMD64 and ARM64. Configure `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` and the
`dockerhub-release` environment. Keep one publisher for each tag. Promote
`latest` only after real macOS streaming, document/RAG, crash recovery and update
tests; Linux/QEMU checks do not validate Metal or Apple virtualization.
