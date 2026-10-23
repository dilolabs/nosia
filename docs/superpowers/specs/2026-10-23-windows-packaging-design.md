# Nosia Windows Packaging

Design approved in conversation; written-spec review pending.

## Goal

Ship a distributable, native Nosia package for Windows 11 x64 without Docker or nested virtualization. Bundle the application and database dependencies, but connect to an AI engine installed separately by the user. Shadow.tech is a conditional compatibility target, not an always-on hosting environment.

## Decisions

- **“Distributable Windows package.”** Create an installer for Windows users generally, with Shadow as one target environment, rather than a one-off setup for one Shadow desktop.
  - Rationale: reusable distribution is the goal, not a machine-specific workaround.
- **Windows 11 on Shadow without Docker.** Do not make Docker Desktop or nested virtualization a prerequisite.
  - Rationale: virtualization-based deployment is unavailable in the requested target environment.
- **“Use existing local engine.”** Users install Ollama or LM Studio separately; Nosia connects to it rather than bundling an inference runtime or managing model downloads.
  - Rationale: keep GPU-driver, model-download, and inference-engine lifecycle management outside this package.
- **“Bundle them.”** Include private Ruby, gems, and PostgreSQL/pgvector so users do not need to install application or database prerequisites themselves.
  - Rationale: eliminate end-user development setup and global dependency conflicts.
- **“Approve this direction.”** Approve the native, browser-based desktop architecture described below, with a per-user Windows 11 x64 installer, privately bundled application/database runtimes, loopback-only access, and no Windows service, autostart, or Electron wrapper in the first release.
  - Rationale: provide a focused desktop experience without adding virtualization or a second UI stack.
- **“Approve requirements.”** Approve the data-safety and release requirements below: persistent user data and keys, backed-up manual upgrades, non-destructive uninstall, visible failures, Windows validation, and signed public releases.
  - Rationale: protect user data and make distribution supportable before public release.

## Alternatives considered

1. **Native self-contained application/database installer — selected.** Best end-user experience, at the cost of maintaining Windows runtime builds.
2. **Installer requiring separately installed Ruby/PostgreSQL.** Smaller distribution, but adds setup steps and increases dependency/version conflicts.
3. **Windows client with a remotely hosted Nosia backend.** Avoids most native runtime work, but is not a self-contained Nosia deployment and requires separate hosting.

## Existing application constraints

- `install.ps1` currently generates Docker Compose configuration and requires Docker Desktop.
- The checked-in application targets Ruby 4 and Rails 8.0, with PostgreSQL and pgvector. SQLite is not a drop-in replacement for its current vector storage.
- Runtime components include Puma, Solid Queue, and PostgreSQL-backed Action Cable.
- The current Puma and process-monitor configuration uses Unix-oriented process/signal behavior; native Windows execution requires validation and targeted adaptations.
- Dependencies include native Ruby extensions, including `blingfire`, `commonmarker`, and Rust-based `html-to-markdown`.
- Docker Model Runner is replaced by the user's existing local inference engine. Compatibility must cover completion, streaming, and embeddings; a working chat endpoint alone is insufficient for RAG.

## Shadow-specific constraints

[Shadow’s official restrictions](https://support.shadow.tech/hc/en-us/articles/32731830348305-Rules-and-Restrictions-on-Shadow) prohibit server hosting by default, modifications to enable virtualization, and bypassing automatic shutdown. A Windows package must not promise always-on Shadow hosting. Whether its intended personal, loopback-only desktop use is permitted must be confirmed with Shadow for the applicable offer; the restrictions do not explicitly settle this case.

## Approved architecture

- Distribute a Windows 11 x64 per-user EXE installer using Inno Setup. Do not require Docker, WSL, virtual machines, RubyInstaller, compilers, or a system-wide PostgreSQL installation on the end user's machine.
- Bundle a pinned Ruby 4 runtime, Windows-built gems and their runtime libraries, precompiled assets, and private PostgreSQL 16 binaries with a matching pgvector extension.
- Build and package native extensions on Windows against the bundled Ruby ABI. Record exact runtime, gem, PostgreSQL, and extension versions in each release manifest. End-user machines must not compile dependencies or fetch application gems at startup.
- Provide Start Nosia, Open Nosia, and Stop Nosia shortcuts backed by a session-bound launcher. The launcher starts the private database, prepares the Rails databases, starts single-process Puma and a separate Solid Queue process in async supervisor mode, waits for readiness, and opens the default browser. Closing the browser tab does not stop Nosia; Stop Nosia does.
- Use the bundled runtime and standard Windows facilities for launch/control; do not require separately installed Node, Python, or .NET runtimes, or execution-policy bypasses.
- Bind application and database listeners explicitly to IPv4 loopback only. Use HTTP at `http://127.0.0.1:3000` by default; use port 55432 for the private database. Allow explicit persistent port overrides, but do not silently change browser origins on each launch. Keep hosted deployment TLS defaults unchanged.
- Provide an isolated desktop runtime configuration for loopback binding, static assets, writable paths, local URLs, host/origin restrictions, and actual boolean SSL settings. Do not rely on passing the string `"false"` to disable a Rails setting. Retain application authentication and CSRF protection.
- Let the user configure an existing OpenAI-compatible local AI engine and select chat/embedding models. Validate both capabilities and embedding dimensions rather than merely checking that a port is open.
- Do not bundle an inference engine or AI models. Do not install a Windows service or add automatic startup in the first release.
- Keep the browser-based Rails UI; no Electron/Tauri shell in the first release.

### Component responsibilities

| Component | Responsibility and boundary |
| --- | --- |
| Installer | Place private runtimes and application files, register shortcuts/uninstaller, and orchestrate a manual upgrade; do not install global Ruby/PostgreSQL or alter GPU drivers. |
| Launcher | Load per-user configuration, control only package-owned processes, enforce a single instance for the data directory, check readiness, and open the browser. |
| Rails web process | Serve the existing Nosia UI/API and assets using a Windows-compatible production profile and single-process Puma. |
| Queue process | Run the existing job classes with Solid Queue's async supervisor, retaining dedicated real-time/background queue behavior and appropriately sized shared database pools. |
| Private PostgreSQL | Persist the configured Rails databases and vector data using the matching pgvector build; do not replace pgvector with a new vector backend. |
| User's local AI engine | Provide completion, streaming, embeddings, and any model-specific tool capabilities; installation, models, drivers, and GPU allocation remain the user's responsibility. |

### Configuration and startup flow

1. Start Nosia acquires the per-data-directory instance lock. If Nosia is already healthy, open its existing URL rather than starting duplicate processes.
2. On first use, collect the local engine base URL, chat model ID, embedding model ID, and embedding dimensions, plus an API key if required. Store these as per-user settings using the existing `AI_BASE_URL`, `AI_API_KEY`, `LLM_MODEL`, `EMBEDDING_MODEL`, and `EMBEDDING_DIMENSIONS` meanings. Provide a documented way to edit settings and restart.
3. The launcher injects settings into child processes explicitly; do not assume production loads `.env` through the development-only dotenv dependency. Generate application/database credentials and encryption keys once, and initialize the private PostgreSQL cluster only when absent.
4. Wait for database readiness; prepare all configured Rails databases on initial installation or version change. Validate database configuration for the main application and Solid Queue rather than assuming a single `DATABASE_URL` provisions every connection correctly.
5. Start the web and queue processes, confirm both are ready, and open the configured loopback URL. Use checks with deadlines rather than fixed startup sleeps.
6. Validate the AI engine with completion, streaming, and embedding requests. Engine unavailability must not destroy data or prevent diagnostics/settings access; explain the missing capability and allow retry after the user fixes their engine.

Ollama's and LM Studio's OpenAI-compatible local endpoints are intended engine targets. Qualify specific engine/model versions through tests before advertising them as supported. Do not imply every OpenAI-compatible engine supports every model or MCP tool-calling feature. Changing embedding models must not silently reuse semantically incompatible stored vectors, even if their dimensions match; require an explicit reindexing workflow.

## Data safety and release behavior

- Store versioned application binaries under `%LOCALAPPDATA%\Programs\Nosia` and persistent databases, uploads, configuration, encryption keys, backups, and logs under `%LOCALAPPDATA%\Nosia`.
- Generate installation-specific secrets once, restrict their filesystem access to the user and necessary Windows administration identities, and preserve them across upgrades. Protect backups containing these secrets as well. Do not bundle shared application secrets, use trust-only database authentication, or log API keys/passwords.
- Deliver updates through a replacement installer, not a background updater. Stop the existing web process and workers, keep PostgreSQL available to dump all configured databases, and back up uploads and configuration/keys while application writes are stopped. Only proceed with migrations after a verified complete backup. Preserve backups until explicitly removed by the user.
- If backup or migration fails, do not report success or silently reset data. A schema-changing upgrade cannot be reversed by swapping binaries alone; recovery must restore a matching full backup with explicit user approval.
- Uninstall removes the application but preserves user data by default. Deleting data is a separate explicit operation.
- Show actionable startup/engine errors, wait on actual readiness checks, and report port conflicts without terminating unrelated processes.
- Stop Nosia stops the package-owned web process and workers before shutting down the database cleanly. It does not stop the user's AI engine. Sudden session shutdown must not require a factory reset or silently discard failed jobs; expose interrupted-job failures for user review rather than assuming every job can safely be retried.
- Launching and stopping must use Windows-supported process control, not assume POSIX `TERM`, `CLD`, or `SIGPROF` behavior. Time-bound graceful shutdown; report any forced termination and make subsequent recovery visible.
- Keep PostgreSQL's major version at 16 for the first release series. A later PostgreSQL major-version upgrade requires a separately designed migration procedure; never open an old data directory with incompatible binaries.
- Public installers must be Authenticode-signed and accompanied by checksums and dependency/license notices. Internal unsigned test builds are not public release artifacts.

## Verification and release gates

### Native compatibility gate

Before installer polish, demonstrate on Windows that the exact runtime/dependency set can load the Rails application and execute real work. Check `pg`, `bcrypt`, `bootsnap`, `blingfire`, `commonmarker`, `html-to-markdown`, and other resolved native dependencies. Verify PostgreSQL/pgvector, the vendored MCP bridge, single-process Puma, and the locked Solid Queue version's async mode. Assets must be built during release creation, not on the user's machine.

If the native dependency or process model cannot be supported reliably, stop and revise this design. Do not silently switch Ruby versions, remove features, substitute SQLite, or introduce WSL as an unapproved workaround.

### Functional and packaging validation

- Run applicable Minitest coverage and Windows-specific launcher/configuration checks in Windows automation; preserve Linux/Docker regression coverage.
- Test the finished package on clean Windows 11 x64 without global Ruby, PostgreSQL, Docker, compilers, or developer tooling, using a standard non-administrator account. Test paths containing spaces and non-ASCII characters.
- Verify initial database creation, sign-in, document upload/parsing, job processing, embedding storage, pgvector retrieval, streamed RAG answers, and browser updates through PostgreSQL-backed Action Cable.
- Exercise engine-down, missing-model, invalid-key, embedding-dimension mismatch, occupied-port, missing-library, insufficient-disk, and failed-migration paths. Do not weaken existing SSRF or MCP endpoint validation to make local inference work.
- Verify repeated start/open/stop, browser-tab closure, launcher interruption, Windows restart, and interrupted-job visibility without duplicate processes or silent data loss.
- Verify upgrade backup/restore, persistence of encryption keys and uploads, failed-upgrade handling, and data-preserving uninstall.
- Test the exact advertised Ollama/LM Studio engine/model combinations, including simultaneous or sequential chat and embedding availability as required by the RAG workflow. The launcher must never stop or reconfigure a shared external engine.
- Run a Shadow session smoke test only after permitted use is confirmed for the relevant offer. Respect automatic shutdown; do not advertise always-on availability.
- Confirm artifact signatures, published checksums, version manifest, and third-party distribution/license notices before public release.

## Scope boundaries

- First release: Windows 11 x64, per-user desktop execution, bundled application/database runtimes, and separately managed local inference.
- Not included: Windows ARM64/Windows Server qualification, system services, background autoupdates, public hosting, GPU-driver changes, engine/model distribution, or a new native UI framework.
- Do not bundle runtimes for arbitrary third-party stdio MCP commands. Existing opt-in controls remain in place; users enabling these commands supply their external runtimes and Windows-compatible commands. Normal app installation does not require Node or Python.
- Do not guarantee offline operation of external integrations or inference engines. Nosia's application/database installation itself must not require fetching gems or compiling code on the target machine.
- Preserve current Linux/Docker installation behavior and unrelated user work. Packaging-specific adaptations must be isolated rather than becoming a general application rewrite.

## Evidence and remaining external dependency

- Repository references: `.ruby-version`, `Gemfile`, `Gemfile.lock`, `Dockerfile`, `install.ps1`, `Procfile`, `bin/boot`, `bin/start-app`, `config/puma.rb`, `config/database.yml`, `config/queue.yml`, `config/storage.yml`, `config/cable.yml`, and `config/environments/production.rb`.
- [pgvector documents native Windows builds](https://github.com/pgvector/pgvector#windows).
- [Solid Queue documents its non-forking async supervisor](https://github.com/rails/solid_queue#fork-vs-async-mode); the locked 1.4.0 source also contains separate fork and async supervisors. This is a design basis, not proof of the packaged Windows lifecycle.
- [Ollama documents native Windows execution](https://docs.ollama.com/windows); no inference runtime is included in this design.
- [Shadow restrictions](https://support.shadow.tech/hc/en-us/articles/32731830348305-Rules-and-Restrictions-on-Shadow) remain a permitted-use gate for Shadow-specific support claims, independent of technical Windows compatibility.

## Approval state

The architecture and safety/release requirements were approved in conversation. The user must review this written spec before implementation planning. No implementation code has been written or authorized by this document alone.
