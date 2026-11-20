# MCP OAuth release verification

Task 7 checked implementation `44785dfc031b4308e91c18b765a4b9702f62fcbb`
with Ruby 4.0.10, Rails 8.1.4.1, RubyLLM 2.2.3, and PostgreSQL 18 with
pgvector. The worktree used synthetic encryption keys, an inert LLM URL,
and disposable databases. Rails and Chromium 156 ran with only loopback
networking; Docker smoke tests used `--network none` and a local PostgreSQL
socket. No live MCP, OAuth, or LLM providers or production data were used.
Exact invocations, exits, and redacted logs are in `/tmp/opencode/nosia-task7/`
on the verification host (`status.tsv` is the index).

| Check | Exit | Result |
| --- | ---: | --- |
| `bundle check` | 0 | Locked dependencies satisfied |
| `bin/rails zeitwerk:check` | 0 | Eager load passed |
| `NOSIA_RUBY_LLM_REPLAY_DATABASE=nosia_mcp_oauth_replay_test bundle exec ruby test/upgrades/ruby_llm_v2.rb` | 0 | 12 tests, 154 assertions |
| `bundle exec ruby test/upgrades/ruby_llm_mcp.rb` | 0 | 10 tests, 189 assertions; synthetic historical rows and encrypted settings preserved |
| `bundle exec ruby test/packaging/ruby_llm_mcp.rb` | 0 | 2 tests, 15 assertions; native MCP present, vendored bridge absent |
| `bin/rails test --seed 54485` | 1 | 1,496 tests, 30,614 assertions, 4 failures, 0 errors/skips on the tmpfs rerun |
| Chromium MCP workspace, catalog, connection and chat composer system tests (command below) | 0 | 69 tests, 57,625 assertions, 0 failures/errors/skips |
| `bundle exec rubocop` | 1 | 550 files, 420 offenses; default parser fell back to Ruby 2.7 (baseline: 635 files, 774 offenses) |
| `RUBOCOP_TARGET_RUBY_VERSION=3.3 bundle exec rubocop --no-server` | 1 | 550 files, 234 offenses, all on unchanged lines; baseline at `e5ad1c9`: 635 files, 666 offenses |
| Ruby 3.3 lint of added/modified Ruby against `e5ad1c9` | 123 | 81 files; 250 offenses in the generated schema and two historical migrations only (`xargs` exit) |
| Same targeted lint excluding the generated schema and those two historical migration files | 0 | 78 files, no offenses. All 20 historical-migration offenses are on unchanged lines; generated schema entries use the existing dump format |
| `bundle exec brakeman --no-pager` | 3 | 0 scan errors and 2 warnings; see below |
| `docker build -t nosia:mcp-oauth-check .` | 0 | Built `sha256:8739ee6395f50fbe21858043243e00bcd6e6be53bdb4b8004dc1dc70ca8573fc` |
| `docker run … nosia:mcp-oauth-check bundle exec ruby test/packaging/ruby_llm_mcp.rb -n /native/` | 0 | 1 test, 10 assertions in the image |
| Built image, fresh database (`db:prepare`) | 0 | Final schema/encryption configuration loaded; `GET /up` → 200 |
| Built image, checked-in 2.0 schema snapshot (`db:migrate`) | 0 | All five migrations applied in order; final schema/encryption configuration loaded; `GET /up` → 200 |
| `git diff --check e5ad1c9` with a tmpfs copy of the worktree index, and again on the docs patch | 0 | No whitespace errors; the real worktree index refresh was blocked by host `ENOSPC` (exit 128) |

```sh
bin/rails test test/system/mcp_oauth_workspace_test.rb \
  test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb \
  test/system/mcp_connection_tests_test.rb test/system/chat_composer_ui_test.rb \
  --seed 46524
```

All three standalone suites passed with zero failures, errors, and skips.
The isolated production-mode Puma boots checked the locked RubyLLM version,
the official `mcp` gem, and absence of the vendored bridge inside the image.
They did not exercise the full service supervisor or workers. The populated data
comparison is in the standalone upgrade harness; the image upgrade used
the 2.0 schema snapshot, not a populated production backup.

## Open findings

The stabilized pre-OAuth full-suite baseline was reported as 1,377 tests,
zero failures and errors at seed `54485`. Its saved environment and log
directory were no longer available. On the same local runtime, a read-only
source archive of `e5ad1c9` and a separate scratch database passed the four
affected examples (28 total assertions across two invocations).

- `test/models/chat_test.rb:152`: deleting a chat leaves its RubyLLM usage
  row. Reproduced alone (1 test, 4 assertions, 1 failure) and passed alone
  on `e5ad1c9`. RubyLLM 2.2.3 changes the chat usage association from
  `dependent: :destroy` to `:nullify`. The app's existing deletion contract
  needs review before integration.
- `test/models/message_test.rb:81`: RubyLLM 2.2.3 exposes a
  `RubyLLM::ToolCall::Collection` rather than the `Hash` expected by the
  existing test. The current message tool view uses `each_value`, which the
  collection supports; the return-type compatibility contract needs review.
- `test/controllers/profiles/credential_updates_test.rb:270`: both the email
  and password missing-CSRF tests receive 303 rather than 422 in the full
  run. Running only the OAuth authorization and profile credential test files
  at the same seed reproduced both (52 tests, 1,046 assertions, 2 failures).
  The two profile assertions pass without the OAuth test file.
  The new OAuth CSRF test sets and restores protection directly on
  `ApplicationController`, while the profile tests set it on its parent.
  A test-environment runner confirmed that restoring the subclass value
  masks subsequent parent changes in that process. This is test-state
  leakage; these tests do not establish a production CSRF bypass.
- Brakeman reports the existing API token `account_id` mass-assignment
  warning (also present on `e5ad1c9`) and one new weak HTTP Verb Confusion
  warning for the callback. The action intentionally rejects a signed-in
  `HEAD` with 405 before consuming an attempt; only `GET` completes consent.
  No warning was suppressed.

The first full suite and system invocation hit host `ENOSPC`; the first full
run counted 719 environment errors. The reruns used a new tmpfs-backed
PostgreSQL cluster and tmpfs test logs, storage and assets. The first browser
rerun counted four fixture errors after a diagnostic sharing the same scratch
database caused lock contention. The successful final browser run used its own
database. No schema was dumped.

These results are not rollout approval. Representative backup and
restore, production configuration and proxy logging, provider interoperability,
and untested browser/platform combinations still need separate verification.
