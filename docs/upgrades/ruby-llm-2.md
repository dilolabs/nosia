# RubyLLM 2.0 upgrade: verification evidence

## Status

**Code integration verified with known baseline exceptions; not production
approval.** RubyLLM is pinned to **2.0.0**, with the narrow vendored MCP **1.0.1**
port. Tasks 1–7 and the Task 8 integration checks are recorded below; the original
RED-stage sections are historical evidence, not outstanding compatibility failures.
The final full suite has **445 runs, 1919 assertions, 0 failures, 1 accepted crawl
error**, not an all-pass result. Default full lint and security scans are also
non-green; their precise baseline comparisons are in the Task 8 evidence.

Start with the [operator runbook](ruby-llm-2-deployment.md), not the incremental
history below. It covers maintenance, three-phase execution, read-only before/
after audits, offline model loading, and irreversible recovery. Verification used
Ruby **4.0.7**, Rails **8.0.5.1**, and only three explicitly disposable PostgreSQL
databases. No development/production database, real paid provider, deployment,
cleanup, push, or merge was used. Production-sized rehearsal, tested backup/
restore, live authenticated MCP interoperability, and the parent's fresh final
integration/data-safety review remain outstanding release gates.

## Verified application checkpoints

Final integration evidence is collected in [Task 8](#task-8-final-integration-evidence).
The sections between here and Task 8 preserve the chronological implementation
and review record; references to later tasks being pending describe that checkpoint.

Each prerequisite has its own committed application source and exact dependency
lockfile, preserved as a recovery reference before later 2.0 work:

| RubyLLM | Commit | Focused test result | Seed |
| --- | --- | --- | --- |
| 1.14.0 baseline | `1ebf4b8d23e1050af22689d91ebc324d2d52bcde` | 48 runs, 143 assertions, 0 failures, 0 errors, 0 skips | 27070 |
| 1.15.0 prerequisite | `ed873506d0ca30799e19b7afd159bb866918d0ea` | 49 runs, 148 assertions, 0 failures, 0 errors, 0 skips | 13561 |
| 1.16.0 prerequisite | `a5d446f77e02612da02575b414eaf0822c11b541` | 49 runs, 148 assertions, 0 failures, 0 errors, 0 skips | 37497 |

Both updates used `bundle update ruby_llm --conservative`. Each lockfile diff
changes only the RubyLLM version and its exact direct dependency requirement;
no transitive gem versions changed. `bundle check` succeeded at both checkpoints.
`ruby_llm-mcp` remains 1.0.1 with its upstream `ruby_llm (~> 1.9)` requirement,
which accepts these prerequisites but not 2.0. No MCP compatibility patch was
made in this task.

These commits preserve application builds, not database backups. No database
backup or restore was performed or verified in Task 1, and these checks do not
constitute production recovery validation.

## Reproducing the focused checks

Run from the selected checkpoint in an isolated worktree with the scratch test
database already prepared. Every Rails invocation in Task 1 used this safe
environment with fake credentials and a deliberately unreachable local AI URL:

```sh
env \
  RAILS_ENV=test \
  DATABASE_URL=postgresql:///nosia_ruby_llm_upgrade_test \
  PARALLEL_WORKERS=1 \
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=11111111111111111111111111111111 \
  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=22222222222222222222222222222222 \
  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=33333333333333333333333333333333 \
  AI_API_KEY=test-only \
  AI_BASE_URL=http://127.0.0.1:9/v1 \
  LLM_MODEL=test-model \
  EMBEDDING_MODEL=test-embedding \
  EMBEDDING_DIMENSIONS=4096 \
  CHUNK_SIZE=512 \
  CHUNK_OVERLAP=128 \
  RETRIEVAL_FETCH_K=3 \
  bin/rails test \
  test/models/chat_test.rb \
  test/models/chat/completionable_test.rb \
  test/models/chat/stop_generation_test.rb \
  test/models/chunk/vectorizable_test.rb \
  test/models/chunk/searchable_test.rb \
  test/models/agent_skill/executor_test.rb \
  test/lib/engines/tool_adapter_test.rb \
  test/models/mcp_server_test.rb \
  test/models/mcp_server_local_test.rb \
  test/integration/token_footer_test.rb \
  test/integration/models_consumption_column_test.rb \
  test/lib/ruby_llm_tokens_test.rb
```

The 1.14.0 baseline used the same command without the final token regression
file, which did not yet exist. The 1.15.0 and 1.16.0 runs included that file.
At both prerequisite versions, `bundle exec rubocop Gemfile
test/lib/ruby_llm_tokens_test.rb` inspected 2 files with no offenses, and
`git diff --check` was clean.

## Token semantics characterization

`test/lib/ruby_llm_tokens_test.rb` was added before changing the dependency.
On 1.14.0, its standalone run failed as intended because `RubyLLM::Tokens`
does not respond to `cache_read` (1 run, 1 assertion, 1 failure, 0 errors;
seed 39304). It passes in both verified prerequisite builds.

The installed 1.15.0 and 1.16.0 implementations were inspected and their
constructor parameters confirmed at runtime. Both accept `cached:` and
`cache_creation:`, **not** `cache_read:` and `cache_write:`. The latter names
are reader aliases. The regression uses the supported constructor:

```ruby
tokens = RubyLLM::Tokens.new(input: 80, output: 20, cached: 15, cache_creation: 5)
assert_equal 80, tokens.input
assert_equal 100, tokens.input + tokens.cache_read + tokens.cache_write
assert_equal 20, tokens.output
```

It also asserts that both cache readers are available. This characterizes the
1.15 normalized contract: standard input is distinct from cache reads and
writes; total request-side input activity sums all three buckets. It does not
recalculate historical usage or change how application counters are updated.
Bundler displayed the upstream 1.15 token-normalization upgrade notice for
both installs. The focused Rails runs emitted no deprecation warnings.

## Existing 1.x schema prerequisites

`db/migrate/20260402102301_add_ruby_llm_v1_14_columns.rb` already changes
`tool_calls.thought_signature` from `string` to `text` when needed. The earlier
`20260402102252_add_ruby_llm_v1_10_columns.rb` creates that column as `string`;
the later migration widens it. No duplicate 1.x migrations were added or run.
The existing RubyLLM migration files cover 1.9, 1.10, and 1.14.

Read-only runtime checks at both verified versions confirmed the connected
database was `nosia_ruby_llm_upgrade_test` and that the column's SQL type was
already `text`. Only the normal focused tests wrote scratch test data.

## Verification boundary

No real provider calls or production/development database changes were needed.
The full suite was not rerun in Task 1. The previously reported unchanged
baseline was 328 runs, 1030 assertions, 0 failures, and 1 error:
`Website::CrawlableTest#test_crawl_url!_still_crawls_public_hosts` reaches an
unstubbed embedding request to `127.0.0.1:9`. Proceeding with that known baseline
was explicitly approved; no unrelated crawler fix is included here.

At the Task 1 checkpoint the dependency was intentionally left at 1.16.0.
RubyLLM 2.0 dependency changes,
MCP compatibility work, the approved rename migration, and application
accounting changes are outside this completed prerequisite task.

## Task 2: test-first 2.0 contracts (intentionally RED)

Verified on 2026-10-14 with the same scratch test database and safe environment
as Task 1. Only six test files and this evidence note change. No application
code, dependencies, configuration, migrations, schema, shared test helpers, or
historical accounting records change. RubyLLM 2.0 was not installed at that checkpoint.

### Contract coverage

- `test/lib/ruby_llm_mcp_compatibility_test.rb` requires exactly RubyLLM 2.0.0.
  Its MCP attachment contract starts with `Base64.strict_encode64("binary payload".b)`
  and requires decoded content, the original re-encoded wire payload, decoded
  byte size, and the supplied PDF MIME type. The current failure is at decoded
  content; the later assertions will run after that compatibility fix.
- `test/lib/engines/tool_adapter_test.rb` adds a keyword call with
  `query: "einstein"`, nested `parameters_schema` properties, required `query`,
  and exclusion of `server_context`, `api_key`, and the secret value from the
  schema. All original positional-call tests are retained. The keyword call
  itself works on 1.16; the missing new schema reader is the RED boundary.
- `test/models/chat/completionable_test.rb` uses a real persisted message as
  the application's polymorphic usage source. Only that instance exposes
  normalized `tokens` (80 input, 20 output, 15 cache read, 5 cache write,
  3 thinking), a string model `glm-5.2`, and a legacy `input_tokens` reader
  that raises `legacy token reader used`. Assertions require all five ledger
  buckets, source/account/chat/model identity, one-time creation, and account
  and chat counter increments of 80 input / 20 output, with no increments on
  a repeated call. Existing behavior assertions remain unchanged.
- Both chunk test files now use `Struct.new(:vectors, :tokens, :model)` with
  `Struct.new(:input)` token objects, not top-level embedding token readers.
  Positive embeddings report 8 input tokens. Existing chat/source/model and
  no-op assertions are retained; zero input, unreported input, absent tokens,
  and absent embedding results have separate coverage. Search also retains
  the no-chat path.
- `test/models/agent_skill/executor_test.rb` retains the original usage test
  and adds normalized token/string model coverage on a persisted returned
  message. All five legacy token readers on that instance reject access.
  The new contract preserves the existing 200 input / 80 output assertions
  and checks cache/thinking buckets and the completed execution source.

These local singleton methods and structs describe the new public boundary;
they do not globally shim RubyLLM or change application accounting. No
`RubyLLM::Tokens` constructor is given unsupported 1.16 keyword names.

### Observed RED results

Each changed test file was run separately with seed `202602`; all six commands
exited 1 for the expected compatibility boundary, not syntax or Rails setup.

| Test file | Runs | Assertions | Failures | Errors | Observed reason |
| --- | ---: | ---: | ---: | ---: | --- |
| `test/lib/ruby_llm_mcp_compatibility_test.rb` | 2 | 2 | 2 | 0 | Expected version 2.0.0, actual 1.16.0; expected `binary payload`, actual `YmluYXJ5IHBheWxvYWQ=` |
| `test/lib/engines/tool_adapter_test.rb` | 9 | 20 | 0 | 1 | `NoMethodError: undefined method 'parameters_schema'` on the adapted nested tool |
| `test/models/chat/completionable_test.rb` | 10 | 21 | 0 | 1 | `RuntimeError: legacy token reader used` from `app/models/chat.rb:75` |
| `test/models/chunk/vectorizable_test.rb` | 5 | 2 | 0 | 4 | `NoMethodError: undefined method 'input_tokens'` at `app/models/chunk/vectorizable.rb:42` for positive/zero/unreported/absent tokens |
| `test/models/chunk/searchable_test.rb` | 6 | 4 | 0 | 4 | `NoMethodError: undefined method 'input_tokens'` at `app/models/chunk/searchable.rb:23` for positive/zero/unreported/absent tokens |
| `test/models/agent_skill/executor_test.rb` | 2 | 7 | 0 | 1 | `RuntimeError: legacy token reader used` from `app/models/agent_skill/executor.rb:84` |

The absent embedding result paths and the no-chat search path already pass.
The old completion, skill, and positional tool tests also pass in these runs.
The normalized accounting guards intentionally stop before the new persisted
usage/counter assertions; those assertions are not claimed to pass yet.

A final combined run included all six files and the unchanged
`test/integration/token_footer_test.rb`: **37 runs, 76 assertions, 2 failures,
11 errors, 0 skips**, exit 1, seed `202602`. It reproduced exactly the RED
boundaries above. The three existing footer tests passed with their original
assertions. The new footer contract is deferred to Task 6 so its setup can
exercise the persisted 2.0 usage ledger rather than inventing a global shim
or prematurely fixing the current legacy-reader partial.

### Exact reproduction commands

The function below expands every Rails invocation to the approved environment;
run these commands from this worktree. The first six are the individual runs;
the final invocation is the combined verification.

```sh
safe_rails_test() {
  env \
    RAILS_ENV=test \
    DATABASE_URL=postgresql:///nosia_ruby_llm_upgrade_test \
    PARALLEL_WORKERS=1 \
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=11111111111111111111111111111111 \
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=22222222222222222222222222222222 \
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=33333333333333333333333333333333 \
    AI_API_KEY=test-only \
    AI_BASE_URL=http://127.0.0.1:9/v1 \
    LLM_MODEL=test-model \
    EMBEDDING_MODEL=test-embedding \
    EMBEDDING_DIMENSIONS=4096 \
    CHUNK_SIZE=512 \
    CHUNK_OVERLAP=128 \
    RETRIEVAL_FETCH_K=3 \
    bin/rails test "$@" --seed 202602
}

safe_rails_test test/lib/ruby_llm_mcp_compatibility_test.rb
safe_rails_test test/lib/engines/tool_adapter_test.rb
safe_rails_test test/models/chat/completionable_test.rb
safe_rails_test test/models/chunk/vectorizable_test.rb
safe_rails_test test/models/chunk/searchable_test.rb
safe_rails_test test/models/agent_skill/executor_test.rb
safe_rails_test \
  test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/engines/tool_adapter_test.rb \
  test/models/chat/completionable_test.rb \
  test/models/chunk/vectorizable_test.rb \
  test/models/chunk/searchable_test.rb \
  test/models/agent_skill/executor_test.rb \
  test/integration/token_footer_test.rb
```

### Static verification and review boundary

The default RuboCop invocation uses an effective Ruby 2.7 parser because the
project has no explicit `TargetRubyVersion`; it rejects the existing
`context:` shorthand at executor test line 28 as well as the new one. No
project configuration or existing syntax was changed to address that tooling
issue. A temporary configuration at
`/tmp/opencode/nosia-rubyllm2-task2-rubocop.yml` contains only:

```yaml
inherit_from: /home/cbldev/gitd/dilolabs/nosia/.worktrees/ruby-llm-2-upgrade/.rubocop.yml

AllCops:
  TargetRubyVersion: 4.0
```

With that runtime-matching parser, the following inspected all six changed test
files with **no offenses**:

```sh
bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/engines/tool_adapter_test.rb \
  test/models/chat/completionable_test.rb \
  test/models/chunk/vectorizable_test.rb \
  test/models/chunk/searchable_test.rb \
  test/models/agent_skill/executor_test.rb
git diff --check
```

Self-review confirmed the diff is test/evidence-only, existing behavior
assertions and positional-call coverage remain, and no global API shim or real
provider call was added. This is completion of the approved **RED test stage**,
not a green upgrade, full-suite verification, or deployment approval. The known
crawler baseline and production fixes remain outside Task 2.

## Task 3: verified vendoring and exact 2.0 dependency (intermediate build)

Implemented from Task 2 commit `c8f1239` on 2026-10-14. This task changes only
dependency packaging/pins, supported initializer configuration, the new
configuration contract, and this evidence. **Do not deploy this intermediate
build.** No application model, transport implementation, migration, or schema
was changed. No migration or model-registry load command was run.

### Archive provenance and local patch

The published MCP 1.0.1 archive was fetched and unpacked outside the repository:

```sh
cd /tmp/opencode/nosia-rubyllm2-research
gem fetch ruby_llm-mcp --version 1.0.1
gem unpack ruby_llm-mcp-1.0.1.gem
sha256sum ruby_llm-mcp-1.0.1.gem
```

All three commands exited 0. The archive hash is
`22121bfdea1874935debdd9cee0235d02473885ce8347cf745a323f0707fd248`.
It was checked programmatically against the `sha` returned by
<https://rubygems.org/api/v2/rubygems/ruby_llm-mcp/versions/1.0.1.json>
and the expected hash before importing any source. The metadata response is
saved outside Git as `ruby_llm-mcp-1.0.1-rubygems.json` in that scratch directory.

`vendor/gems/ruby_llm-mcp/` contains 120 byte-identical upstream files:
`lib/ruby_llm/`, all `lib/generators/` and their templates, `README.md`, and
`LICENSE`. The only omitted published files are the upstream development
release/smoke tasks under `lib/tasks/`; neither is loaded by the Railtie.
No caches, downloaded archives, installed gems, or upstream development
checkout are committed. Runtime source is deliberately unmodified in Task 3.

The published archive omits a source gemspec. The local gemspec was reconstructed
from `Gem::Package.new(archive).spec`, not a Git-dependent repository gemspec.
A read-only comparison verified all 13 selected identity/runtime metadata
fields (`name`, `version`, `authors`, `email`, `summary`, `description`,
`homepage`, `licenses`, `date`, `required_ruby_version`,
`required_rubygems_version`, `metadata`, and `require_paths`). All original
runtime dependencies match except the explicitly patched RubyLLM requirement:
upstream `~> 1.9` excludes 2.0, so this local gem requires **`= 2.0.0`**.
MCP's version remains **1.0.1**. The packaging list includes only retained
published files and the local `PATCHES.md` note, with no Git calls.

`vendor/gems/ruby_llm-mcp/PATCHES.md` records provenance, the local constraint
patch, the incomplete runtime port, and the upstream replacement/removal path.
This pin is a compatibility target, **not** a claim that upstream 1.0.1 works
on 2.0. Task 7 must document and test each later runtime adaptation there.

### Dependency and configuration inspection

```sh
bundle update ruby_llm ruby_llm-mcp --conservative
bundle check
```

Both exited 0. The complete lockfile diff was inspected:

- RubyLLM changes from 1.16.0 to exactly 2.0.0.
- MCP 1.0.1 moves from RubyGems to the explicit vendor path, requiring 2.0.0.
- `schematist` 1.1.0 replaces `ruby_llm-schema` 0.3.0.
- RubyLLM's JSON requirement is now `< 3`, and its Marcel requirement is
  `>= 1.0, < 3`. The existing root `json < 3` constraint remains unchanged;
  JSON stays at 2.21.2 and Marcel at 1.2.1.
- No other gem versions, Rails version, Ruby version, platforms, or Bundler
  version change. No new HTTP dependency was needed: the locked Faraday and
  HTTPX dependencies already satisfy the published specs.

The installed/unpacked 2.0 source was inspected: OpenAI still registers
`openai_use_system_role`, and Chat Completions still uses it to select the
`system` role. Provider registration declares `openai_protocol`. The initializer
retains the configured API base/key and model/embedding environment variables,
keeps `openai_use_system_role = true`, explicitly selects
`:chat_completions`, and removes the ignored `use_new_acts_as` setting. No
temperature default or provider endpoint was changed.

### TDD and intermediate test evidence

Every Rails command used the same fake-key/local-port-9 environment and scratch
database as above, with seed `202603`. The version contract was run before any
dependency/configuration edit. The protocol configuration contract was then
added and observed RED before changing the initializer/dependencies.

| Check | Runs | Assertions | Failures | Errors | Exit | Observed boundary |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Version contract before update | 1 | 1 | 1 | 0 | 1 | Expected 2.0.0, actual 1.16.0 |
| New configuration contract before update | 1 | 1 | 1 | 0 | 1 | 1.16 config lacks `openai_protocol` |
| Version contract after update | 1 | 1 | 0 | 0 | 0 | Loaded exactly 2.0.0 |
| Configuration contract after update | 1 | 7 | 0 | 0 | 0 | Chat Completions, endpoint/key, models, and system role preserved |
| Entire MCP compatibility file after update | 3 | 9 | 1 | 0 | 1 | Attachment content still returns encoded data, pending Task 7 |
| Combined Task 2 contract/footer set after update | 38 | 15 | 1 | 32 | 1 | Expected incomplete application/MCP adoption, detailed below |

The combined run reports 21 setup errors at `app/models/model.rb:2` because
`acts_as_model` was removed, 7 local-tool adapter errors because `params` was
removed, 4 embedding errors from the old `input_tokens` reader, and the MCP
attachment assertion failure. Repeated failed adapter setup also emits
constant-redefinition warnings. The remaining 5 tests pass. These are upgrade
gaps, not the authorized baseline crawl error. Tasks 4/5 must complete schema
and supporting-model/reader adoption; Task 6 must finish the other application
API/UI changes; Task 7 must port MCP/tool schemas and attachment/content
conversions. No compatibility shim or premature model deletion was added here.

Exact Rails commands (run from the application worktree):

```sh
task3_test() {
  env \
    RAILS_ENV=test \
    DATABASE_URL=postgresql:///nosia_ruby_llm_upgrade_test \
    PARALLEL_WORKERS=1 \
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=11111111111111111111111111111111 \
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=22222222222222222222222222222222 \
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=33333333333333333333333333333333 \
    AI_API_KEY=test-only \
    AI_BASE_URL=http://127.0.0.1:9/v1 \
    LLM_MODEL=test-model \
    EMBEDDING_MODEL=test-embedding \
    EMBEDDING_DIMENSIONS=4096 \
    CHUNK_SIZE=512 \
    CHUNK_OVERLAP=128 \
    RETRIEVAL_FETCH_K=3 \
    bin/rails test "$@" --seed 202603
}

# Before update: version RED, then new configuration RED.
# --name worked but Minitest requested --include for subsequent runs.
task3_test test/lib/ruby_llm_mcp_compatibility_test.rb \
  --name test_loads_the_exact_RubyLLM_2.0_release
task3_test test/lib/ruby_llm_mcp_compatibility_test.rb \
  --include test_keeps_the_configured_endpoint_on_the_Chat_Completions_protocol

# After update: these two targeted contracts are GREEN.
task3_test test/lib/ruby_llm_mcp_compatibility_test.rb \
  --include test_loads_the_exact_RubyLLM_2.0_release
task3_test test/lib/ruby_llm_mcp_compatibility_test.rb \
  --include test_keeps_the_configured_endpoint_on_the_Chat_Completions_protocol

# Intentionally incomplete broader compatibility checks, exit 1.
task3_test test/lib/ruby_llm_mcp_compatibility_test.rb
task3_test \
  test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/engines/tool_adapter_test.rb \
  test/models/chat/completionable_test.rb \
  test/models/chunk/vectorizable_test.rb \
  test/models/chunk/searchable_test.rb \
  test/models/agent_skill/executor_test.rb \
  test/integration/token_footer_test.rb
```

### Packaging, static verification, and self-review

A standalone `bundle exec ruby` check required `ruby_llm/mcp` and verified
the loaded versions are RubyLLM 2.0.0 / MCP 1.0.1 and MCP's real gem path is
this worktree's `vendor/gems/ruby_llm-mcp`, not an installed RubyGems copy
(exit 0). This verifies loading/selection only, not bridge execution.

```sh
# Run inside vendor/gems/ruby_llm-mcp; output stays outside the repository.
gem build ruby_llm-mcp.gemspec \
  --output /tmp/opencode/nosia-rubyllm2-research/ruby_llm-mcp-1.0.1-nosia-task3.gem

# Run from the application worktree.
bundle exec rubocop Gemfile config/initializers/ruby_llm.rb \
  test/lib/ruby_llm_mcp_compatibility_test.rb \
  vendor/gems/ruby_llm-mcp/ruby_llm-mcp.gemspec
git diff --check
```

The gem build succeeded; RuboCop inspected the 4 locally authored/changed Ruby
files with no offenses; the diff check was clean. Upstream runtime sources
were hash-compared, not reformatted to application style. Self-review checked
task ownership, exact dependency constraints, the entire lockfile diff, vendor
completeness/license, no Git-dependent gemspec, preserved configuration, and
honest RED/green boundaries. No new public runtime methods need YARD in this
task. Full-suite, migration rehearsal, and deployment approval remain outside
Task 3; the existing crawler baseline was not rerun or fixed.

### Task 3 review follow-up: preserve the Docker path dependency

Quality review found a packaging gap in the initial Task 3 checkpoint
`5183cbe9cfbfb7d4158467c75fa6694a2f933c9e`: Docker's combined
`COPY Gemfile Gemfile.lock vendor ./` copies the contents of `vendor` into
`/rails`, not `/rails/vendor`. The new Gemfile path therefore did not exist at
the first `bundle install`. The earlier local Bundler checks did not exercise
this image-build boundary.

The fix changes only that instruction into:

```dockerfile
COPY Gemfile Gemfile.lock ./
COPY vendor ./vendor
```

The base image, multistage structure, dependency-install command, application
copy, and final runtime behavior are unchanged. `.dockerignore` was inspected
and does not exclude `vendor`; it required no change.

`test/packaging/ruby_llm_path_dependency.rb` is a standalone Minitest executable,
with no Rails helper, database connection, credentials, or provider requests.
It requires both copy instructions before the first bundle install and checks
that MCP's exact Gemfile path contains its gemspec. Its filename deliberately
does not match normal Rails `*_test.rb` discovery. Run explicitly:

```sh
bundle exec ruby test/packaging/ruby_llm_path_dependency.rb --seed 202603
```

Before the Dockerfile edit: **2 runs, 6 assertions, 1 failure, 0 errors**, exit 1,
because `COPY vendor ./vendor` was missing. After: **2 runs, 8 assertions,
0 failures, 0 errors**, exit 0. RuboCop inspected the new test with no offenses:

```sh
bundle exec rubocop test/packaging/ruby_llm_path_dependency.rb
git diff --check
```

Docker client/server 29.8.2 were available. A lightweight packaging-only build
was run, rather than waiting for native compilation or attempting the incomplete
2.0 application's asset build. A temporary Dockerfile outside Git was generated
from the actual pre-install `COPY` instructions, prefixed with `FROM scratch`
and `WORKDIR /rails`. It uses the real repository build context and its actual
`.dockerignore`:

```sh
docker build \
  --file /tmp/opencode/nosia-rubyllm2-research/task3-packaging/Dockerfile.packaging \
  --output type=local,dest=/tmp/opencode/nosia-rubyllm2-research/task3-packaging/rootfs .

env BUNDLE_GEMFILE=/tmp/opencode/nosia-rubyllm2-research/task3-packaging/rootfs/rails/Gemfile \
  bundle check
```

Both commands exited 0. Hash comparison verified all **124 files** (Gemfile,
lockfile, and 122 vendored MCP files) were retained byte-identically under the
exported `/rails`, confirming `.dockerignore` permits this dependency. Separate
`bundle exec ruby` checks against the repository Gemfile and Docker-exported
Gemfile required `ruby_llm/mcp` and verified MCP 1.0.1 resolves from the respective
`vendor/gems/ruby_llm-mcp` directory with RubyLLM 2.0.0. These use host-installed
dependencies; they are path-resolution checks, **not** an in-image bundle install.

The **full multistage application image was not built**. No Rails or database
commands were run in this follow-up. Self-review confirms only `Dockerfile`,
the standalone regression, and this evidence change; Tasks 4–7 and the known
intermediate runtime failures remain untouched.

## Task 4: guarded rename-mode migration rehearsal

Implemented from `620e46e` on 2026-10-14. This verifies only the migration task,
not the whole upgrade or a production rollout. The original `38faaab:db/schema.rb`
is byte-identically preserved in
`test/fixtures/files/ruby_llm_1_16_schema.rb`, committed in `72309c2` **before**
dumping the upgraded schema. The fixture retains PostgreSQL bigint IDs, integer
roles, pgvector columns, all application tables, and the real foreign keys.

### Safety and reproduction

Create the dedicated rehearsal database once, using a local PostgreSQL role
allowed to create databases and enable the existing `vector` extension:

```sh
createdb nosia_ruby_llm_upgrade_migration_test
bundle exec ruby test/upgrades/ruby_llm_v2.rb
```

The standalone Minitest file deliberately does **not** match `*_test.rb` and does
not require `test_helper`, boot the application, read dotenv/database.yml or
credentials, or instantiate the obsolete `Model`/`ToolCall` classes. It requires
Active Record, RubyLLM, and Neighbor (the existing pgvector schema DSL support).
It connects with an explicit adapter/database hash, ignoring `DATABASE_URL`.
Before any table drops or legacy fixture loading it checks
`SELECT current_database()` equals **exactly**
`nosia_ruby_llm_upgrade_migration_test`, failing closed otherwise. It drops only
the named fixture/upgrade/AR metadata tables in that disposable database, never
an entire database or schema. Do not run simultaneous rehearsals against it.

Rails commands below use the same fake keys and port-9 endpoint as prior tasks.
The `-u CI` prevents test-environment eager loading of the old supporting classes:

```sh
task4_rails() {
  env -u CI \
    RAILS_ENV=test \
    DATABASE_URL=postgresql:///nosia_ruby_llm_upgrade_test \
    PARALLEL_WORKERS=1 \
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=11111111111111111111111111111111 \
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=22222222222222222222222222222222 \
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=33333333333333333333333333333333 \
    AI_API_KEY=test-only \
    AI_BASE_URL=http://127.0.0.1:9/v1 \
    LLM_MODEL=test-model \
    EMBEDDING_MODEL=test-embedding \
    EMBEDDING_DIMENSIONS=4096 \
    CHUNK_SIZE=512 \
    CHUNK_OVERLAP=128 \
    RETRIEVAL_FETCH_K=3 \
    bin/rails "$@"
}

# Already generated and checked in: do not generate duplicates.
task4_rails generate ruby_llm:upgrade --mode rename \
  chat:Chat message:Message model:Model tool_call:ToolCall

# Run only after the standalone rehearsal is green.
task4_rails db:migrate
task4_rails db:schema:dump
```

The generator exited 0 without eager loading obsolete model declarations and
produced exactly these three files; no copy, cleanup, or discard flags were used:

| Phase | Checked-in migration | Normal scratch db:migrate elapsed |
| --- | --- | ---: |
| Prepare | `20261014152719_prepare_ruby_llm_v2_upgrade.rb` | 0.4172 s |
| Backfill | `20261014152720_backfill_ruby_llm_v2_data.rb` | 0.1284 s |
| Finish | `20261014152721_finish_ruby_llm_v2_upgrade.rb` | 0.1383 s |

To execute individual phases on the **same dedicated normal scratch database**
instead of all pending migrations (these are alternatives, not replay commands):

```sh
task4_rails db:migrate:up VERSION=20261014152719
task4_rails db:migrate:up VERSION=20261014152720
task4_rails db:migrate:up VERSION=20261014152721
```

Plain `db:migrate` runs all pending phases. It exited 0 only after the standalone
rehearsal passed and automatically dumped `db/schema.rb` from
`nosia_ruby_llm_upgrade_test`. Read-only SQL confirmed the connected database,
latest version `20261014152721`, and all four journal entries completed. An
explicit `db:schema:dump` also exited 0 after migration. This
normal scratch database had **zero messages/usages**; the populated legacy
preservation evidence comes from the separate rehearsal, not that empty migrate.
No existing development/production database was migrated or reset.

### Test-first failures and narrowly adapted generator output

`bundle exec ruby test/upgrades/ruby_llm_v2.rb --seed 202604` was run before
generation: **5 runs, 5 assertions, 5 failures, 0 errors**, exit 1, explicitly
reporting the missing prepare migration. After generation, an initial harness
setup issue identified missing Neighbor schema-DSL loading; adding its existing
dependency allowed the complete unmodified legacy fixture to load.

The unmodified generated phases were then run with the same command: **5 runs,
28 assertions, 1 failure, 3 errors**, exit 1. Prepare raised PostgreSQL
`PG::InvalidTextRepresentation` for integer role comparison with `'assistant'`,
including before the missing-identity guard could produce its intended error.
All raw role predicates were audited: one in each phase. At the initial Task 4
checkpoint `d5af481`, the only generated source adaptations were those three
predicates and their explanatory comments. The preservation fixes below add
two further narrowly scoped adaptations:

```ruby
# Nosia's historical integer enum encodes assistant as 10; do not load the current Message model.
conditions << "#{message_value(:role)} = 10" if column_exists?(:messages, :role)
```

The historical encoding remains system **0**, assistant **10**, user **20**,
tool **30**. It is fixed migration history, not a lookup from today's app enum.
No migration framework was replaced, guards removed, or current app classes
ported to make these tests pass. The generated default batch size stays 10,000.

### Verified preservation and recovery boundaries

The green rehearsal seeds anonymous table classes with real FK order and
timestamps: user/account/membership, two historical provider-qualified models,
one chat, seven messages spanning all four roles, a tool call/result, an Active
Storage blob/attachment, an existing application usage row, and nonzero counters.
Assertions cover:

- Message count, IDs, integer roles, legacy token columns, chat/model/tool IDs,
  plaintext, attachment/blob attributes, and tool arguments/signature.
- Nonempty structured `content_raw` takes precedence over stale plaintext and
  is copied to `raw_content`; empty JSON preserves plaintext; absent raw remains
  absent. Tool results gain the correct internal `Message` type/result ID.
- Exactly three historical usages, including the assistant with all-null token
  buckets identified through the chat model; explicit message model wins over
  chat model. Five bucket totals are **92 / 24 / 17 / 6 / 9**, unchanged, with
  original provider/model/timestamps and **all six price fields nil**.
- Application `token_usages` attributes and account/chat counters are unchanged.
  Legacy message columns remain; no cleanup was generated or applied.
- Every original FK survives its table/column rename, except the generated,
  intentional removal of `tool_calls.message_id -> messages` when the internal
  tool-call owner becomes polymorphic. The quality-review follow-up below also
  changes only the obsolete `messages.tool_call_id` FK's delete action to
  `ON DELETE SET NULL`; unrelated application FKs are not removed or changed.
- Preparation/backfill can retry before finish. A test-only batch size of 3
  (restored in `ensure`) and a `say` callback force interruption **after commit**:
  message 103's usage and journal cursor survive; retry creates the remaining
  two usages, retains the first row byte-for-byte, and does not duplicate rows.
- Finish refuses absent/incomplete backfills with actionable errors. Prepare
  refuses unknown provider/model identity before moving any tables; it does not
  invent identity or prices. Prepare/backfill reject replay after finish.
  All three `down` methods remain irreversible and DDL transactions disabled.

The initial checkpoint's final command `bundle exec ruby test/upgrades/ruby_llm_v2.rb`
also passed: **5 runs, 89 assertions, 0 failures, 0 errors, 0 skips**, exit 0,
seed `7918`, **9.748071 s** total; populated phases **0.366 / 0.169 / 0.142 s**.
The first fully green seeded run was **5 runs, 89 assertions, 0 failures,
0 errors, 0 skips**, exit 0, seed `202604`, in **9.930930 s** including fixture
recreation per test. The measured populated happy-path phases were **0.354 s /
0.161 s / 0.141 s**. These tiny local fixtures and empty scratch migrations are
**not production downtime estimates**. A production-sized snapshot, reviewed
lock behavior, tested backup/restore, matching 1.16 application, drained AI
work, and maintenance remain release preconditions. Rename mode requires all
affected writers stopped; even concurrent indexes do not make renames/DDL online.
On failure keep AI paused and diagnose the failed phase; never skip its guards.
Recovery after cutover restores the matching database backup and application
together, not `db:rollback`. New 2.0 writes do not maintain legacy columns.

Self-review checks task-only ownership, exact database guards, documented
generator adaptations, retained FKs/columns, interruption commits, unknown prices, and
the schema diff. The harness passes RuboCop without a temporary parser override;
generated upstream formatting is retained. A read-only ERB comparison against
the installed 2.0.0 generator templates verified that initial checkpoint differed
only by the documented role line/comment. That historical comparison does not
describe the expanded adaptations below. Ruby compilation checked the three migrations
and original schema fixture successfully; `git diff --check` was clean.
There is no new application public
API requiring YARD in this task. Task 5 must still remove obsolete supporting
declarations and port runtime associations/readers; Task 7's MCP compatibility
port remains RED. The full Rails suite and autoload validation were deliberately
not represented as green or rerun here; the accepted crawler baseline is unchanged.

### Task 4 quality-review follow-up: deletion and blank-content preservation

Review of `d5af481` exposed two preservation defects; neither original Task 4
commit was amended. This follow-up still changes only Task 4 migration/test/schema
and evidence files, not application or gem source. The real database rollout
has **not** happened: use these corrected migrations for its first execution.

**Historical tool results:** the retained
`messages.tool_call_id -> ruby_llm_tool_calls.id` FK had `NO ACTION`. RubyLLM
2.0 destroys a caller's internal tool calls before the result message; unlike
1.16, its tool-call model does not nullify that old pointer first. Direct internal
call deletion, caller destruction, and chat destruction all reproduced
`PG::ForeignKeyViolation` on `fk_rails_552873cb52`.

Finish now changes only that FK to `on_delete: :nullify`, **after** verifying
backfills/usages/results and making the legacy column nullable. It locates the
exact existing source column/target, preserves its name and other options, and
does nothing if the obsolete FK is absent. Removal/recreation is atomic in a
short DDL transaction; the replacement is added unvalidated and then validated.
Retry checks the existing action and validates any interrupted replacement.
No cascading result deletion or broad FK removal is introduced. This DDL can
still take locks: keep the existing maintenance/no-writers requirement.

The harness now loads the real RubyLLM 2.0 AR macros/internal records explicitly,
using separate test-only `RuntimeChat`/`RuntimeMessage` classes on the existing
tables and historical polymorphic names. It does not boot Nosia or load its
callbacks. Tests verify direct call deletion and real 2.0 caller destruction
retain every result attribute except the nullified legacy pointer; chat
destruction completes with its dependent rows removed. FK comparison permits
**only** the documented action change, and finish retry retains the FK options
and validation. Full application callback/attachment deletion coverage remains
Task 5 integration work.

**Blank raw payloads:** generated backfill/finish validation rejected all NULL
plaintext with non-SQL-NULL `content_raw`, although the upstream renderer
deliberately keeps the original plaintext for blank raw values. Both verifiers
now use the unchanged `RubyLLM::Generators::LegacyContentSQL.render` expression
and PostgreSQL `IS DISTINCT FROM`: the raw JSON must equal `content_raw`, and
the plaintext must equal the renderer's expected result, null-safely. Finish
explicitly requires the helper so it works independently of backfill loading.
The original backfill transformation is unchanged. This strengthens rejection
of wrong non-NULL content/raw data instead of merely dropping the old check.

The fixture matrix adds both NULL and non-NULL plaintext for SQL NULL, JSON
null, `false`, `[]`, `{}`, empty strings, and whitespace strings including a
nonbreaking space. Tests exercise backfill and finish independently and compare
raw JSON null-safely. Both phases must still reject absent plaintext, absent raw
payload, corrupt nonblank plaintext, and corrupt nonblank raw JSON. Existing
nonempty JSON precedence, accounting, interruption, and guard tests remain.

Test-first evidence, all against `nosia_ruby_llm_upgrade_migration_test`:

| Stage | Result | Exit |
| --- | --- | ---: |
| Deletion regressions before FK fix, seed `202604` | 8 runs, 98 assertions, 1 failure, 3 FK errors | 1 |
| After targeted FK fix, seed `202604` | 8 runs, 111 assertions, no failures/errors | 0 |
| Blank/corrupt-content regressions before verifier fix, seed `202604` | 12 runs, 137 assertions, 2 failures, 2 errors | 1 |
| After verifier fix, seed `202604` | 12 runs, 151 assertions, no failures/errors | 0 |
| Final unfiltered harness, seed `48583` | **12 runs, 154 assertions, no failures/errors/skips**, **25.028505 s** | 0 |

Final populated happy-path phase timings were **0.407 / 0.166 / 0.151 s** for
the seven-message base fixture; the separate blank-value tests add fourteen
variants. These are local correctness timings, not production estimates.

The normal scratch database already recorded finish as applied; `db:migrate`
would not rerun this edited unreleased migration. After the harness passed,
only its targeted relaxation was applied there, with an exact database guard,
then its schema was dumped. Using the `task4_rails` function above, the exact
scratch-only repair and dump were:

```sh
task4_rails runner '
  expected = "nosia_ruby_llm_upgrade_test"
  actual = ActiveRecord::Base.connection.select_value("SELECT current_database()")
  abort "Refusing scratch FK repair in #{actual}" unless actual == expected
  require Rails.root.join("db/migrate/20261014152721_finish_ruby_llm_v2_upgrade.rb").to_s
  FinishRubyLlmV2Upgrade.new.send(:relax_legacy_message_constraints)
  key = ActiveRecord::Base.connection.foreign_keys(:messages).find { |candidate| candidate.column == "tool_call_id" && candidate.to_table == "ruby_llm_tool_calls" }
  abort "FK repair failed" unless key.on_delete == :nullify && key.validate?
  puts "#{actual}: only legacy tool-result FK relaxed and validated"
'
task4_rails db:schema:dump
```

Both exited 0. The resulting schema diff is exactly one FK declaration gaining
`on_delete: :nullify`; its version remains `20261014152721`. This private-method
repair is an explicitly authorized **scratch-only** exception, not a production
replay procedure. If any real database had applied an earlier finish, stop for
a separately reviewed forward-fix plan rather than assuming `db:migrate` applies
edits to previously recorded migrations. No development/production DB was touched.

Current generator differences are intentionally more than the three role
predicates: both content verifiers, finish's explicit renderer require, and
finish's single legacy FK relaxation are also adapted. Prepare remains otherwise
unaltered. The upstream gem/framework source remains unchanged.

Final checks, all exit 0:

```sh
bundle exec ruby test/upgrades/ruby_llm_v2.rb
bundle exec rubocop test/upgrades/ruby_llm_v2.rb
bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  --only Lint db/migrate/20261014152719_prepare_ruby_llm_v2_upgrade.rb \
  db/migrate/20261014152720_backfill_ruby_llm_v2_data.rb \
  db/migrate/20261014152721_finish_ruby_llm_v2_upgrade.rb
bundle exec ruby -r active_record \
  -r ./db/migrate/20261014152721_finish_ruby_llm_v2_upgrade.rb \
  -e 'abort "Finish did not load its own renderer" unless defined?(RubyLLM::Generators::LegacyContentSQL); puts "Finish independently loads LegacyContentSQL"'
git diff --check
```

The temporary migration-lint config is the previously documented four-line
runtime-matching Ruby 4 parser override, not a repository configuration change.
Generated upstream formatting is retained; all three migrations and the harness
also passed Ruby compilation. Self-review confirms exact FK targeting, atomic
replacement/retry, preserved blank/raw semantics, active corruption checks,
scratch-only schema adjustment, and unchanged application/gem code. Tasks 5/7
and production-sized rehearsal/recovery validation remain pending.

## Task 5: supporting associations and normalized accounting

Implemented from `ed0ee33647f170269ce3065a86ba2904bba7c15e` on 2026-10-14,
using the installed RubyLLM **2.0.0**. This is only the persistence/accounting
task, not completion of the upgrade or deployment approval. No migration,
schema, dependency, request options, instructions, catalog, token-footer view,
or MCP implementation changes are included. No development/production database
was accessed. All Rails commands used only `nosia_ruby_llm_upgrade_test` with
fake credentials and the deliberately unreachable local provider endpoint.

### Ownership and behavior

- Remove the obsolete application `Model` and `ToolCall` declarations. The gem
  now owns its supporting records. Remove the duplicate Chat model/messages
  associations and Message model/tool-call associations. The macro owns Chat's
  internal registry foreign key and deterministic **created_at, id** message
  ordering. Application chat/message associations, integer roles, attachments,
  callbacks, and other fields remain intact.
- Blank-assistant cleanup, the existing `without_tool_calls` SQL predicate,
  and the intermediate-assistant broadcast guard use `ruby_llm_tool_calls`,
  never relation methods on the public `tool_calls` hash. Model/helper searches
  found no remaining legacy tool-call persistence reads to change.
- Completion and skill accounting read `message.tokens` and string
  `message.model`. Standard input/output map unchanged to the application
  ledger; cache reads/writes map to `cached_tokens`/`cache_creation_tokens`,
  and thinking remains its own bucket. Completion still skips unreported input
  and deduplicates by source. Skills retain input-**or**-output eligibility and
  their execution source. Optional buckets default to zero; reported zero input
  is not treated as missing. No historical events or counters are replayed.
- Both embedding concerns, including the after-save pending-result guard, use
  `tokens.input`. Query recording still requires a chat; both paths retain the
  configured `EMBEDDING_MODEL` identity rather than substituting the result model.
  Vector generation/persistence and the existing pending-result lifecycle are
  unchanged.
- Existing accounting tests now create real provider attempts through
  `message.ruby_llm_usages.create!` with required chat/operation/provider/model/
  status fields, not retained message token columns. The 120/30 persisted test
  asserts the supporting record is `RubyLLM::ActiveRecord::Usage`. The original
  normalized singleton contracts and all original behavior assertions remain.
  Skill instruction stubs accept keyword arguments without porting instructions.
- The prior prerequisite token test now uses the supported 2.0 constructor
  keywords `cache_read:`/`cache_write:`; all five assertions are preserved.
  No global compatibility shim or shared helper change was introduced.

The new embedding callback regressions execute real `generate_embedding` via
`before_save`, store the vector and pending result, then execute after-save
recording. Only `RubyLLM.embed` is temporarily replaced with a local result and
restored in `ensure`; no provider call is made. Positive input records once and
clears pending state. Zero, unreported input, and absent tokens record nothing
and retain pending state, matching the previous lifecycle. Tests also cover
timestamp ties, public tool-call hashes and result links, SQL distinctness,
intermediate broadcast suppression, and chat destruction with attachments,
internal calls, and both ledgers.

### Test-first and final evidence

Every run below used seed **202605**, with no skips.

| Stage | Runs | Assertions | Failures | Errors | Exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Existing Task 2 ledger/embedding/skill and blank/history contracts, before runtime edits | 22 | 2 | 0 | 21 | 1 |
| New callback/lifecycle/filter/broadcast regressions, before runtime edits | 8 | 0 | 0 | 8 | 1 |
| Accounting contracts after association adoption, before token-reader changes | 34 | 37 | 4 | 19 | 1 |
| Focused accounting/persistence contracts after changes | 34 | 140 | 0 | 0 | 0 |
| Full focused model/accounting set (11 files) | **78** | **273** | **0** | **0** | **0** |
| Placeholder, HTML normalization, stream-buffer regressions (3 files) | **12** | **25** | **0** | **0** | **0** |
| Broader focused set after final token-constructor correction (17 files) | **105** | **316** | **1** | **11** | **1** |

Initial RED reasons were 17 setup errors from removed `acts_as_model` and four
embedding `input_tokens` errors. New callback tests independently reached that
obsolete reader in `record_embedding_usage_if_needed`; the other new tests were
initially blocked by the same supporting-model setup. After association adoption,
accounting RED exposed the intended `legacy token reader used` failures and
missing application events despite real provider usage, plus query-embedding
reader errors. Three intermediate test setup/assertion issues were corrected:
read ordering from the association rather than executing Rails' wrapped scope
without its relation context; select full messages rather than PostgreSQL-invalid
`DISTINCT id ORDER BY created_at`; attach before adding calls to avoid exercising
the deferred tool-call rendering partial in a deletion-lifecycle test.

The 80/20 normalized completion contract verifies all five buckets, exact source/
account/chat/model identity, and exactly 80 input / 20 output increments on both
account and chat; a second call changes neither events nor counters. Separate
persisted-usage tests cover output-only completion skip, zero-input creation,
unreported/nil messages, and output-only skill recording with zero defaults.

The broader run's remaining boundaries are **not** the accepted crawler baseline:

- Task 6: two token-footer setup errors (`Model` removed / Message `model:` is
  no longer an association) and one catalog setup error referencing `Model`.
  These UI tests and views were deliberately not rewritten here.
- Task 7: seven local tool-adapter errors and one local-server adapter error
  from removed `RubyLLM::Tool.params`; MCP attachment decoding still fails
  because it returns the base64 wire payload as content. Repeated adapter setup
  also emits constant-redefinition warnings.
- While arranging the lifecycle regression, attaching to an assistant that
  already has calls reproduced the deferred `messages/_tool_calls.html.erb`
  array-pair/`name` error from iterating the new hash as a relation. No view fix
  was included. The final broader command does not exercise that attachment path.

The existing stubbed streaming and stop-generation tests pass in the focused
set. They do not establish real request compatibility: `with_params` and old
instruction keywords remain for Task 6. An initial broader run also identified
the prerequisite token test's old constructor keywords (105 runs, 311 assertions,
1 failure, 12 errors); only that accounting test was corrected before the final
broader rerun above. The full suite, real providers, and accepted unstubbed-crawl
baseline were not rerun or fixed.

### Exact reproduction and review

Use `task4_rails` from the safety section above; it expands every call to the
complete approved scratch-only environment and unsets `CI`.

```sh
task5_test() { task4_rails test "$@" --seed 202605; }

contracts=(
  test/models/chat/completionable_test.rb
  test/models/chunk/vectorizable_test.rb
  test/models/chunk/searchable_test.rb
  test/models/agent_skill/executor_test.rb
  test/models/chat_test.rb
)

# Initial RED (before runtime changes).
task5_test "${contracts[@]}" \
  --include '/record_completion_usage|embedding|executor records|purge_blank|chronological/'
task5_test test/models/chat_test.rb test/models/message_test.rb \
  test/models/chunk/vectorizable_test.rb \
  --include '/timestamp_ties|destroying_a_chat|tool_calls_expose|intermediate_assistant|saving_generated_embeddings/'

# Unblocked accounting RED, then GREEN with the same command.
task5_test "${contracts[@]}" test/models/message_test.rb \
  --include '/record_completion_usage|embedding|executor records|executor skips|purge_blank|chronological|timestamp_ties|destroying_a_chat|tool_calls_expose|intermediate_assistant/'

focused=(
  test/models/chat_test.rb test/models/message_test.rb
  test/models/chat/completionable_test.rb test/models/chat/stop_generation_test.rb
  test/models/chunk/vectorizable_test.rb test/models/chunk/searchable_test.rb
  test/models/chunk_embedding_storage_test.rb test/models/agent_skill/executor_test.rb
  test/models/account_test.rb test/models/token_usage_test.rb
  test/lib/ruby_llm_tokens_test.rb
)
task5_test "${focused[@]}"
task5_test test/models/message_placeholder_test.rb \
  test/models/message_html_to_markdown_test.rb test/models/message/stream_buffer_test.rb

# Intentionally still RED at the documented Task 6/7 boundaries.
task5_test "${focused[@]}" test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/engines/tool_adapter_test.rb test/models/mcp_server_test.rb \
  test/models/mcp_server_local_test.rb test/integration/token_footer_test.rb \
  test/integration/models_consumption_column_test.rb

bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  app/models/chat.rb app/models/message.rb app/models/chunk/vectorizable.rb \
  app/models/chunk/searchable.rb app/models/agent_skill/executor.rb \
  test/models/chat_test.rb test/models/message_test.rb \
  test/models/chat/completionable_test.rb test/models/chunk/vectorizable_test.rb \
  test/models/agent_skill/executor_test.rb test/lib/ruby_llm_tokens_test.rb
git diff --check
```

A read-only Rails runner verified the exact connected scratch database and
schema version **20261014152721**, Chat's model class
`RubyLLM::ActiveRecord::Model` with foreign key `ruby_llm_model_id`, unchanged
role mapping **0/10/20/30**, and absence of the two obsolete supporting files.
No migration command was run. The runtime-matching RuboCop configuration is the
existing four-line temporary parser override documented in Task 2, not a repo
configuration change. The final lint run inspected all 11 changed Ruby files
with no offenses, and `git diff --check` was clean. Public accounting documentation
now describes normalized inputs, return values, and persistence failures.
Self-review checked the complete
owned diff, macro ordering/ownership, SQL joins, nil/zero eligibility, cache
mapping, source deduplication, pending callback lifecycle, and unchanged Task 6/7
boundaries. Task 5's focused behavior is green; the intermediate upgrade remains
unsuitable for deployment until the later tasks and release verification finish.

### Task 5 quality-review follow-up: generating-show association consumer

Review of `a018845d078bc709b2a5dc54380746a322ca5e19` found a missed consumer
outside the initial model/helper scan: `app/views/chats/show.html.erb:19`
still queried `where.missing(:tool_calls)`. With `generating: true`, both the
pre-assistant retrieval state and the blank in-progress assistant state raised
`ActionView::Template::Error: An association named :tool_calls does not exist on
the model Message`. The existing focused model tests did not render this page.

The fix changes only that query's association to `:ruby_llm_tool_calls`. Blank
content selection, ordering, and the existing placeholder-versus-thinking
animation UX remain unchanged. No tests needed rewriting. No token-footer,
catalog, request/instruction, tool-call rendering, MCP, migration, or schema
changes are included. The wider `app/`, `lib/`, and `config/` scan found no other
nondeferred relationship query using the removed association. The separately
documented `_tool_calls` hash-rendering adaptation remains deferred, not fixed.

All checks below used the same approved scratch-only environment and seed
**202605**; no provider calls or development/production database access occurred.

| Stage | Runs | Assertions | Failures | Errors | Exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Existing generating-show tests before query fix | 2 | 0 | 0 | 2 | 1 |
| Same tests after query fix | 2 | 6 | 0 | 0 | 0 |
| Task 5 focused models, message regressions, and both generating-show tests | **92** | **304** | **0** | **0** | **0** |

Exact commands, using the safe `task4_rails`, `task5_test`, and `focused` array
already defined above:

```sh
# Run before and after the one-line query change.
task5_test test/controllers/chats_controller_test.rb:77 \
  test/controllers/chats_controller_test.rb:96

# Final focused verification.
task5_test "${focused[@]}" test/models/message_placeholder_test.rb \
  test/models/message_html_to_markdown_test.rb test/models/message/stream_buffer_test.rb \
  test/controllers/chats_controller_test.rb:77 test/controllers/chats_controller_test.rb:96
git diff --check
```

Self-review confirms the follow-up owns only the one-line view fix and this
evidence. The diff check is clean. Task 6/7 compatibility gaps and the full-suite
verification boundary are unchanged; this follow-up does not claim the overall
upgrade is ready.

## Task 6: request APIs, catalog metadata, and message rendering

Implemented from `d7c2a12` on 2026-10-14 using RubyLLM **2.0.0**. This task
changes only its application request/instruction/catalog/rendering consumers,
associated tests, the streaming stub's method name, and this evidence. No
dependency, migration, schema, historical ledger field, counter implementation,
CSS, route declaration, or MCP/local-engine implementation changes are included.
The prerequisite `test/lib/ruby_llm_tokens_test.rb` already uses the supported
2.0 `cache_read:` / `cache_write:` constructor keywords at this starting commit;
it is rerun unchanged. Historical 1.x checkpoint syntax remains intact.

### Behavior and isolation

- Completion and enrichment use `with_provider_options`. Completion retains
  the exact flat `max_tokens`, `top_p`, and `top_k` names and values; temperature
  still uses its dedicated setter. A real `Chat#render` assertion verifies the
  configured OpenAI Chat Completions payload, without an HTTP request: no new
  `provider_options` nesting or `max_completion_tokens` rename is introduced.
  RubyLLM 2.0 no longer rewrites unsupported temperatures; this port preserves
  the requested value and does not silently normalize it for a provider.
- Baseline/augmented completion and guard instructions use 2.0's replacement
  default, without `replace:`. Excluded-attachment warnings and LLM skill
  instructions use `append: true`. A persisted system-message test verifies
  the skill keeps its baseline. Both Ruby skill allowlists expose only the new
  provider-options name, not a compatibility alias.
- The real 2.0 `Chat#with_model` resets `assume_model_exists` from its keyword
  default; merely setting the accessor first no longer preserves that intent.
  Completion and both guard calls now pass `assume_model_exists: true`
  explicitly, preserving the existing custom OpenAI-compatible backend behavior.
  The real model-switch regression accepts an unregistered slash/dot ID locally.
- Catalog actions use `RubyLLM.models.all`, provider-qualified `.find`, and
  `.refresh`. Entries are real `RubyLLM::Model` metadata, rendered through an
  explicit partial/collection/local, never an AR/polymorphic route. Safe row IDs
  hash the provider/ID pair. Prices use `.price(:input)` / `.price(:output)`;
  unknown buckets display `—`, while free buckets display `$0.00`. Index and
  show retain Comparia consumption by the string registry ID.
- The existing show route keeps the literal `model` segment and passes
  `model_id` plus `provider` in the query. Both identity parameters must be
  nonblank strings, and registry misses return 404. Tests round-trip overlapping
  IDs from two providers and `org/slash.model.v2`, and reject absent, blank,
  array/hash, unknown identities, and a nonliteral path ID. The route definitions
  and refresh URL are unchanged. Catalog tests scope a local `RubyLLM::Models`
  instance through a singleton accessor restored in `ensure`; they neither
  mutate the global registry cache/store nor fetch a catalog. Refresh itself
  is replaced only on that isolated instance.
- Footers and both rendering guards use normalized `message.tokens`. GreenIt
  receives the string `message.model`, and only standard input/output contribute
  to the footer estimate. Real `ruby_llm_usages` rows exercise reported zero,
  absent buckets, a nil model fallback, and done/unreported guards. Existing
  application counter-cache and per-kind totals assertions remain unchanged.
- Tool-call rendering iterates the public hash values and retains names,
  arguments, escaping, and existing markup. The regression uses real persisted
  internal calls/results and verifies public `RubyLLM::ToolCall` values; it
  does not call `dom_id` or route internal records. No legacy tool-result content
  reader was found in the runtime scan.
- New JSON/SSE integration tests run the real completion preamble and controller
  response code, replacing only retrieval and the provider-completion boundary
  on locally created chats. SSE preserves raw markdown chunks and `[DONE]`.
  Singleton replacements are restored in `ensure`; no global compatibility
  methods or actual provider requests are added to these contracts.

### Test-first evidence

All Rails invocations use only the already-migrated
`nosia_ruby_llm_upgrade_test`, fake credentials, and the port-9 endpoint below.
No development/production DB was accessed and no migration command was run.
All recorded Task 6 runs use seed **202606**, with no skips.

| Stage | Runs | Assertions | Failures | Errors | Exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| New/updated six-file contract set before production edits | 24 | 45 | 3 | 16 | 1 |
| Corrected allowlist loading plus isolated guard keyword RED | 3 | 8 | 3 | 0 | 1 |
| First same-set run after implementation | 24 | 185 | 2 | 0 | 1 |
| Contracts plus real wire-payload and JSON/SSE characterization | **27** | **216** | **0** | **0** | **0** |
| Final focused request/catalog/footer/cache/accounting/chat/streaming/job/API set (27 files) | **152** | **604** | **0** | **0** | **0** |

The initial RED reproduced removed `with_params`, obsolete `replace:`, the
custom-model reset, removed application `Model`, legacy footer readers/string
model access, and array-pair tool-call rendering. One initial test setup error
referenced `AgentSkill::RubyExecutor` before loading its enclosing executor file;
the corrected isolated run fails on the intended old allowlist and guard
instruction keywords. The first post-implementation run exposed two incorrect
test assumptions, not runtime regressions: persisted **Chat** still exposes its
internal model record (unlike **Message**'s string model), and PostgreSQL JSONB
does not preserve insertion order for argument keys. The assertions now check
the chat's `model.model_id` and argument content without ordering assumptions.
No behavior assertion was weakened to accept an old API. Real payload and API
response tests were added as supplemental characterization after the core port.

### Reproduction commands

The actual shell wrapper was `/tmp/opencode/nosia-task6-rails`, containing this
same environment and `exec ... bin/rails "$@"`. Its portable equivalent is:

```sh
task6_rails() {
  env \
    RAILS_ENV=test \
    DATABASE_URL=postgresql:///nosia_ruby_llm_upgrade_test \
    PARALLEL_WORKERS=1 \
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=11111111111111111111111111111111 \
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=22222222222222222222222222222222 \
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=33333333333333333333333333333333 \
    AI_API_KEY=test-only \
    AI_BASE_URL=http://127.0.0.1:9/v1 \
    LLM_MODEL=test-model \
    EMBEDDING_MODEL=test-embedding \
    EMBEDDING_DIMENSIONS=4096 \
    CHUNK_SIZE=512 \
    CHUNK_OVERLAP=128 \
    RETRIEVAL_FETCH_K=3 \
    bin/rails "$@"
}
task6_test() { task6_rails test "$@" --seed 202606; }

contracts=(
  test/models/chat/request_options_test.rb test/models/chunk/enrichable_test.rb
  test/models/agent_skill/executor_test.rb
  test/integration/models_consumption_column_test.rb
  test/integration/token_footer_test.rb test/integration/tool_calls_rendering_test.rb
)

# Before production edits: initial RED, then corrected isolated RED.
task6_test "${contracts[@]}"
task6_test test/models/agent_skill/executor_test.rb \
  test/models/chat/request_options_test.rb --include '/allowlists|relevance/'

# After production edits and test-setup corrections: GREEN, including extra
# real payload and JSON/SSE response characterization.
task6_test "${contracts[@]}" test/controllers/api/v1/completions_controller_test.rb

# Broader verification; results and boundaries are recorded below.
task6_test

focused=(
  test/models/chat_test.rb test/models/message_test.rb
  test/models/chat/completionable_test.rb test/models/chat/request_options_test.rb
  test/models/chat/stop_generation_test.rb test/models/chat/wait_for_attached_sources_test.rb
  test/models/chat/similarity_search_test.rb
  test/models/chunk/vectorizable_test.rb test/models/chunk/searchable_test.rb
  test/models/chunk/enrichable_test.rb test/models/chunk_embedding_storage_test.rb
  test/models/agent_skill/executor_test.rb test/models/agent_skill_test.rb
  test/models/account_test.rb test/models/token_usage_test.rb
  test/lib/ruby_llm_tokens_test.rb
  test/integration/token_footer_test.rb test/integration/models_consumption_column_test.rb
  test/integration/token_summary_cache_test.rb test/integration/tool_calls_rendering_test.rb
  test/controllers/chats_controller_test.rb test/controllers/api/v1/completions_controller_test.rb
  test/controllers/api/v1/api_authentication_test.rb test/jobs/chat_response_job_test.rb
  test/models/message_placeholder_test.rb test/models/message_html_to_markdown_test.rb
  test/models/message/stream_buffer_test.rb
)
task6_test "${focused[@]}"
```

The full non-system suite completed in **204.082031 s**: **373 runs, 1288
assertions, 1 failure, 10 errors, 0 skips**, exit 1. No Task 6 failure/error
remains in that run. Its complete non-green boundary is:

- **Task 7:** one MCP attachment-decoding assertion failure, seven adapter-test
  errors, one local-server-tools error, and one local-engine-chat integration
  error. All nine errors reach the removed `klass.params` call at
  `lib/engines/tool_adapter.rb:64`. Failed class construction also emits the
  already documented constant-redefinition warnings. Schema/call/decoding work
  remains untouched for Task 7.
- **Accepted baseline:** `Website::CrawlableTest#test_crawl_url!_still_crawls_public_hosts`
  attempts its unstubbed embedding against `127.0.0.1:9` and raises
  `Faraday::ConnectionFailed`. It is not fixed or silently skipped here.

The final focused command also includes a strengthened catalog assertion that
only the two well-formed registry misses reach `.find`; malformed requests and
nonliteral path IDs are rejected before lookup. Test tenant cleanup is explicit.
It completed in **192.600134 s**, exit 0: **152 runs, 604 assertions, 0 failures,
0 errors, 0 skips**. This rerun verifies every final Task 6 runtime/test edit,
including unchanged normalized-token characterization, usage counters/cache,
completion streaming and stop behavior, chat controllers, API authentication,
JSON/SSE completions, and chat response jobs. The full-suite result above used
the same final runtime code, before the extra catalog assertion and footer-test
tenant-cleanup refinement. System/browser tests and the standalone migration
rehearsal were not rerun in Task 6.

### Static checks and self-review

The final changed-Ruby lint command is:

```sh
bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  app/controllers/models_controller.rb app/models/chat/completionable.rb \
  app/models/chat/answer_relevance.rb app/models/chat/context_relevance.rb \
  app/models/chunk/enrichable.rb app/models/agent_skill/executor.rb \
  app/models/agent_skills/base.rb test/test_helper.rb \
  test/models/chat/request_options_test.rb test/models/chunk/enrichable_test.rb \
  test/models/agent_skill/executor_test.rb test/integration/models_consumption_column_test.rb \
  test/integration/token_footer_test.rb test/integration/tool_calls_rendering_test.rb \
  test/controllers/api/v1/completions_controller_test.rb
git diff --check
```

The temporary config is the previously documented Ruby-4 parser override, not
a repository configuration edit. An initial lint run found only two array
spacing offenses in the new request test; they were corrected with a named
local variable. The final lint inspected **15 files with no offenses**, exit 0,
and `git diff --check` also exited 0. Runtime searches in `app/`, `config/`, and
`lib/` found no remaining Task 6 `with_params`, `replace:`, `assume_exists`,
application catalog `Model` calls, or legacy message-token/content readers.
The intentionally deferred `lib/engines/tool_adapter.rb:64` `klass.params` and
vendored MCP schema/content APIs remain Task 7 work. Application `TokenUsage`
columns, accounting SQL, and historical migration fields are not API-renamed.
No new public application helper/API was introduced, so no
additional YARD surface is needed. Self-review checks exact request values,
replacement/append intent, registry isolation and provider identity, strict
parameter validation, nil-versus-zero pricing and usage, escaping, SSE raw
chunks, unchanged ledger/counters, and the Task 6-only diff. No child agents
were spawned. This evidence does not establish that the overall upgrade is
complete, that Task 7 works, or that deployment is approved.

### Task 6 quality-review follow-up: prompt-only completion lifecycle and disclosure

Review of `1f677d8e9a3bfef623445e6fcea20453bc3eee6d` found an important gap
in the original API characterization: its helper replaced `Chat#complete`, so
it did not exercise RubyLLM 2.0's conversation state machine. The original
Task 6 results above remain historical evidence, not proof that the real loop
handled every API input safely.

The controller's `prompt:` branch assigned the question only to a local variable,
unlike its `messages:` branch, which persisted messages. RubyLLM 1.16 generated
when `complete` was called, but 2.0 considers a system-only chat complete and
returns the last system message without contacting the provider. Nosia then
fetched its last persisted message and serialized the private system prompt,
including retrieved context, as an assistant JSON answer. SSE returned only
`[DONE]`, with no generation. Missing input and completed assistant-ending
histories reached the same no-pending-response state and disclosure path.

The narrowly scoped controller fix:

- Persist exactly one user message in the `prompt:` branch with `create!` before
  `complete_with_nosia`; do not add any extra user message in the `messages:` branch.
- Check the public 2.0 `@chat.complete?` state before retrieval or system-instruction
  insertion. A request with no pending response gets JSON **422** with
  `A user prompt or final user message is required`, including when streaming was
  requested. This fails closed for missing input and completed histories rather
  than pretending to generate or returning internal context. No role normalization,
  endpoint redesign, retry mechanism, or broad input-validation framework is added.

All focused API tests now leave both `Chat#complete` and the RubyLLM chat loop,
protocol request rendering, SSE parsing/accumulation, persistence callbacks,
instruction lookup, and provider-options setters **real**. A local Faraday test
adapter replaces only HTTP I/O on newly constructed transport connections; all
unmatched requests fail locally. It feeds two raw content deltas plus a final
usage/stop event through the protocol's real `on_data` handler. No provider
completion method is replaced and no network request is made by these tests.
Retrieval/MCP/guard dependencies are isolated on the newly created application
chat, and a real account prompt plus a canned retrieved chunk contain explicit
test-only system/context markers. Both constructor replacements are restored in
`ensure`; no global compatibility alias or transport configuration is retained.

Coverage includes prompt-only JSON and SSE on **both** `/v1/completions` and
`/v1/chat/completions`, the existing message-based JSON/SSE paths, and a multi-turn
user/assistant/user history. Every successful provider request must contain the
actual final user question and unchanged flat `max_tokens`, `top_p`, `top_k`, and
temperature values. Tests verify one request, one copy of each persisted user
message, persisted provider output, no system/context markers in the client
response, raw SSE markdown deltas, and `[DONE]`. Separate JSON/SSE tests require
422 and zero provider calls for absent input and completed assistant histories.

Test-first evidence, using the unchanged safe environment and seed **202606**:

| Stage | Runs | Assertions | Failures | Errors | Exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Real-loop prompt contracts before controller changes | 7 | 72 | 4 | 0 | 1 |
| Same contracts after persisting prompt user | 7 | 148 | 0 | 0 | 0 |
| Added missing-input/completed-history contracts before state guard | 11 | 162 | 4 | 0 | 1 |
| All API contracts after the state guard | **11** | **180** | **0** | **0** | **0** |
| Expanded 27-file focused set, including the previous 152-test coverage | **161** | **776** | **0** | **0** | **0** |

The first RED JSON responses visibly included **both** test markers;
both prompt-only SSE paths recorded **zero** provider requests. With the new
transport boundary, the message-based and user-ending history tests already
passed before the controller fix. The second RED independently reproduced JSON
disclosure for missing input and completed history, plus SSE **200** with only
`data: [DONE]` instead of the required rejection. These were assertion failures,
not test setup or transport errors.

The final focused run completed in **187.647139 s**, exit 0, with no skips.
The API-only final GREEN took **18.547295 s**, exit 0. Both use the same safe
scratch-only environment and seed. The full non-system suite and standalone
migration rehearsal were not rerun in this follow-up; their earlier documented
results are not presented as new verification.

Exact commands, reusing the `task6_rails`, `task6_test`, and 27-file `focused`
definitions above (the actual external wrapper remains unchanged):

```sh
# Run before and after each narrowly scoped controller edit.
sh /tmp/opencode/nosia-task6-rails test \
  test/controllers/api/v1/completions_controller_test.rb --seed 202606

# Rerun the previously green 152-test focused set with the expanded API file.
task6_test "${focused[@]}"

bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  app/controllers/api/v1/completions_controller.rb \
  test/controllers/api/v1/completions_controller_test.rb
git diff --check
```

This follow-up owns only the API controller, its request tests, and this evidence.
It touches no Task 7 code, dependency, migration, schema, root-user change, or
development/production database, and spawns no child agents. No new public helper
is introduced. The full suite's earlier Task 7/accepted crawler failures are not
fixed or represented as green by this follow-up. RuboCop inspected the two changed
Ruby files with **no offenses**, and `git diff --check` exited 0. Self-review
verified the real-loop/transport boundary, exact pending-user persistence without
duplicates, rejection before retrieval/system-prompt insertion, JSON/SSE marker
non-disclosure, unchanged request options, ensure-based stub restoration, API
authentication/account scoping, and the three-file ownership boundary.

## Task 7: narrow vendored MCP and local-tool runtime port

Implemented from `bc7caaeebb9936517664245424f4c73991ac004d` on 2026-10-14.
This task retains the published MCP **1.0.1** implementation and its existing
transports/features; it does not replace it with the official SDK. The supported
RubyLLM target remains **exactly 2.0.0**. No dependency, migration, schema,
historical accounting, request-option, AI endpoint, or transport implementation
change is included. No child agents, real provider calls in the new contracts,
development/production database access, or deployment actions were used.

### Compatibility boundaries

`vendor/gems/ruby_llm-mcp/PATCHES.md` inventories all ten imported-source edits
and their behavior against archive SHA-256
`22121bfdea1874935debdd9cee0235d02473885ce8347cf745a323f0707fd248`.
The archive hash was rechecked and a byte comparison confirmed **120 imported
files: exactly 10 documented differences and 110 pristine files**. The existing
local gemspec and exact pin are unchanged.

- MCP attachments strictly decode base64 into `StringIO`, run the real parent
  constructor with filename `mcp-attachment`, and retain the explicit MIME type.
  Tests distinguish decoded binary bytes, byte size, and re-encoded wire bytes,
  check parent source/config/type behavior, and run the actual Chat Completions
  media formatter for image/audio/PDF data without double encoding. Invalid
  base64 raises; neither it nor root tool arguments become local paths/URLs.
- `MCP::Content` is an ordinary bridge-owned value, not a global core shim.
  Its explicit `to_tool_result` and `to_message(role:)` return supported RubyLLM
  values/fields. Attachment normalization compacts nil entries and accepts a
  single real attachment or array; it never creates attachments from untrusted
  strings. Tests call these public methods and the real 2.0 `Tool.split_result`.
- Remote tools expose full nested/required `parameters_schema` and the renamed
  `to_h` key. Every success block is converted, including all text/images/audio,
  embedded resource blobs/text, and resource links. Structured JSON remains
  authoritative (with or without output schema) while retaining accompanying
  files. Schema validation and both JSON-RPC/execution error hashes remain.
  Empty content returns an empty string rather than dereferencing `content.first`.
- Prompt/resource inclusion uses actual `RubyLLM::Message` text and attachment
  fields. Standard prompt media fields and the existing legacy aliases work;
  embedded prompt resources consume their included content. Plain-chat and real
  persisted-chat tests verify text, roles, file bytes, MIME types, and Active
  Storage persistence without a provider call. Existing resource URI dispatch
  is deliberately unchanged; non-HTTP resource reads in these tests use canned
  adapter replies, not local file access or an SSRF-guard bypass.
- Both legacy callback and handler-based sampling convert system/text/image/audio
  inputs into real messages. Completion alone is canned on an otherwise real
  plain chat; coordinator responses/errors and rejection are exercised. The
  discovered native response formatter also referenced removed core Content;
  it now reads message text/files, base64-encodes wire data, and uses
  `finish_reason`. Single-block shapes remain unchanged. MCP 2025-11-25 added
  array sampling content; older negotiated versions explicitly reject multiple
  blocks with `InvalidFormatError`, never truncate or send an invalid array.
  The native client passes its existing negotiated version to that formatter.
  This boundary was checked against the official 2025-06-18 and 2025-11-25
  published JSON schemas; no protocol-negotiation algorithm was changed.
- Local tools use `Tool.parameters`; direct/local/remote invocation uses the 2.0
  keyword API. Old positional-call tests were converted, not supported by a shim.
  `McpServer#execute_tool` first makes a plain Hash and string-normalizes root
  keys. This matters because `HashWithIndifferentAccess#transform_keys` retains
  string keys even when the core tool normalizes keywords to symbols. Credentials
  remain bound in `server_context`, absent from the LLM schema.
- The real JSON endpoint regression reproduced unpermitted Parameters expansion,
  so only `arguments` is permitted as an arbitrary JSON object and converted at
  the controller boundary. Non-object JSON is rejected with 400. A real local
  MCP tool receives query/nested options with server-bound credentials; sibling
  record/auth attributes do not change the server, and cross-account execution
  remains 404. Existing result/error wrapper semantics are preserved.
- Transport characterization instantiates the original stdio/SSE/streamable/
  streamable_http classes without connecting. A second contract replaces only
  their physical constructors with canned I/O and runs the actual client,
  adapter, native protocol, capability handshake, default auto-start, list,
  keyword tool call, and stop. Command/args/env, URL/custom/auth headers, and
  capability errors are preserved. Existing stdio opt-in and public-URL tests
  remain unchanged. No local fixture bypasses the application's URL guard.

The unused OAuth generator view receives only the mechanical schema-reader
rename, not a UI rewrite. A complete vendored-runtime scan finds no remaining
removed `RubyLLM::Content`, `params_schema`, `.params`, `.param`, `with_params`,
legacy token readers, or old message-model/stop-reason reader calls. The local
variable `stop_reason` in the response formatter is not a removed API call.
New public bridge methods and changed public boundaries have YARD documentation.

### Test-first evidence

All Rails runs use only the already-migrated `nosia_ruby_llm_upgrade_test` and
the safe environment below. No database setup, migration, reset, or data-repair
command was run in this task. All seeded Task 7 runs use **202607** except the
initial existing-contract run, which used seed **21639**. No tests are skipped.

| Stage | Runs | Assertions | Failures | Errors | Exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Existing MCP decode/local schema tests before edits | 12 | 13 | 1 | 7 | 1 |
| Expanded bridge/schema/persistence contracts before runtime edits | 23 | 21 | 3 | 16 | 1 |
| Same bridge/local schema set after initial port | 23 | 121 | 0 | 0 | 0 |
| Sampling and local/remote server keyword regressions before fixes | 31 | 128 | 2 | 2 | 1 |
| After sample/server/formatter fixes, before sampling-concern fix | 32 | 145 | 1 | 0 | 1 |
| Endpoint regression plus transport/engine/bridge tests before controller fix | 56 | 282 | 2 | 0 | 1 |
| Expanded non-object endpoint and negotiated-version guard RED | 2 | 6 | 1 | 1 | 1 |
| Final complete MCP/local-engine focused set | **67** | **365** | **0** | **0** | **0** |

Initial RED reproduced encoded attachment content, removed local schema API,
remote nested-schema loss, removed core Content, and empty-content dereference.
The independent sampling-handler failure was observed after the legacy sample
path was green, not hidden behind its earlier failure. Endpoint RED first showed
unpermitted parameters, then the indifferent-Hash keyword boundary; the final
test also exposed false-valued non-object input. The negotiated-version RED
proved the native client initially omitted its legacy version when formatting
a multi-block response. All now have passing behavior assertions.

Two test harness mistakes were corrected before counting the expanded RED:
Minitest 6 does not ship `minitest/mock`, and Ruby 4 requires explicit braces
for MCP Result's positional response Hash when the constructor also has a
keyword parameter. No production compatibility shim or dependency was added
to hide those setup errors. Supplemental binary/provider serialization coverage
was added after the core attachment RED/GREEN, not represented as a new failing
implementation requirement. An existing OpenAlex integration test independently
reproduced the old positional tool call; only its call syntax was updated.

### Exact reproduction commands

```sh
task7_rails() {
  env \
    RAILS_ENV=test \
    DATABASE_URL=postgresql:///nosia_ruby_llm_upgrade_test \
    PARALLEL_WORKERS=1 \
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=11111111111111111111111111111111 \
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=22222222222222222222222222222222 \
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=33333333333333333333333333333333 \
    AI_API_KEY=test-only \
    AI_BASE_URL=http://127.0.0.1:9/v1 \
    LLM_MODEL=test-model \
    EMBEDDING_MODEL=test-embedding \
    EMBEDDING_DIMENSIONS=4096 \
    CHUNK_SIZE=512 \
    CHUNK_OVERLAP=128 \
    RETRIEVAL_FETCH_K=3 \
    bin/rails "$@"
}

# Initial existing-contract RED (before any production edit).
task7_rails test test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/engines/tool_adapter_test.rb

# Expanded RED and first GREEN, same files, after converting positional tests.
task7_rails test test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/engines/tool_adapter_test.rb --seed 202607

# Sampling/server RED and intermediate handler RED.
task7_rails test test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/models/mcp_server_test.rb test/models/mcp_server_local_test.rb --seed 202607

# Final focused set; all MCP/local-engine contracts, including engine activation.
task7_rails test test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/ruby_llm_mcp_transport_test.rb test/lib/engines \
  test/lib/mcp_catalog_registry_test.rb test/models/mcp_server_test.rb \
  test/models/mcp_server_local_test.rb test/controllers/mcp_servers_controller_test.rb \
  test/integration/local_engine_chat_test.rb test/integration/activate_engine_test.rb \
  test/integration/engines_boot_test.rb --seed 202607

# Unfiltered non-system suite, with only the accepted baseline permitted to fail.
task7_rails test --seed 202607
```

The final focused run completed in **5.719568 s**. An initial unfiltered run was
stopped by the shell's 120-second timeout and is not counted as test evidence.
The next completed full run took **248.568093 s**, with **406 runs, 1688
assertions, 0 failures, 1 error**, exit 1: only the accepted
`Website::CrawlableTest#test_crawl_url!_still_crawls_public_hosts` live embedding
request to `127.0.0.1:9`. The final unfiltered rerun additionally includes the
binary/provider and negotiated legacy-protocol contracts and expanded non-object
input coverage: **409 runs, 1715 assertions, 0 failures, 1 error, 0 skips**,
**287.336980 s**, exit 1. Its only error is that same accepted crawler baseline.
There are **no MCP or local-adapter failures/errors**. This is a completed Task 7
verification run, not a green full suite or Task 8 release approval.

### Packaging, static checks, and self-review

```sh
bundle exec ruby test/packaging/ruby_llm_path_dependency.rb --seed 202607

# Run inside vendor/gems/ruby_llm-mcp; do not leave an archive in the repository.
gem build ruby_llm-mcp.gemspec \
  --output /tmp/opencode/nosia-rubyllm2-research/ruby_llm-mcp-1.0.1-nosia-task7.gem

# Run from the worktree; this unchanged FROM-scratch fixture uses Dockerfile's
# actual pre-bundle COPY instructions, not a full application image build.
docker build \
  --file /tmp/opencode/nosia-rubyllm2-research/task3-packaging/Dockerfile.packaging \
  --output type=local,dest=/tmp/opencode/nosia-rubyllm2-research/task7-final-packaging/rootfs .
env BUNDLE_GEMFILE=/tmp/opencode/nosia-rubyllm2-research/task7-final-packaging/rootfs/rails/Gemfile bundle check

bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  app/controllers/mcp_servers_controller.rb app/models/mcp_server.rb \
  lib/engines/tool_adapter.rb test/controllers/mcp_servers_controller_test.rb \
  test/integration/local_engine_chat_test.rb test/lib/engines/tool_adapter_test.rb \
  test/lib/ruby_llm_mcp_compatibility_test.rb test/lib/ruby_llm_mcp_transport_test.rb \
  test/models/mcp_server_local_test.rb test/models/mcp_server_test.rb
bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml --only Lint \
  vendor/gems/ruby_llm-mcp/lib/ruby_llm/mcp/{attachment,content,tool,prompt,resource,sample}.rb \
  vendor/gems/ruby_llm-mcp/lib/ruby_llm/mcp/handlers/concerns/sampling_actions.rb \
  vendor/gems/ruby_llm-mcp/lib/ruby_llm/mcp/native/{client,messages/responses}.rb
bundle exec ruby -e 'files = Dir["vendor/gems/ruby_llm-mcp/lib/**/*.rb"]; files.each { |file| RubyVM::InstructionSequence.compile_file(file) }; puts "Compiled #{files.size} vendored Ruby sources"'
git diff --check
```

Packaging regression: **2 runs, 8 assertions, no failures/errors**, exit 0.
The gem builds as 1.0.1. The Docker export succeeds, all **135 files** under
the exported Gemfile/lockfile/vendor dependency layout hash-match source, and
`bundle check` succeeds there. A `bundle exec ruby -r ruby_llm/mcp` check against
that exported Gemfile verifies the exported vendor path, RubyLLM 2.0.0, decoded
attachment bytes, and real message conversion. These checks use host-installed
dependencies; **no full multistage application image or in-image bundle install
is claimed**. Dockerfile and `.dockerignore` are unchanged.

RuboCop inspects **10 application/test Ruby files** with no offenses and all
**9 edited vendored runtime Ruby files** with no Lint offenses, using the existing
external Ruby-4 parser override. Upstream layout is retained, not globally
reformatted. All **105 vendored Ruby source files** compile. The diff check is
clean. Self-review checks the full task-owned diff, exact imported-file inventory,
no core shim, real conversion/persistence/provider serialization assertions,
transport/config/security preservation, protocol-specific sampling shapes,
tenant-scoped endpoint arguments, ensure-based fake restoration, and unchanged
dependency/schema/accounting files. Live authenticated MCP interoperability,
system/browser tests, and the standalone migration rehearsal are not rerun here.
Task 8's release gate, production-sized rehearsal/recovery, and deployment
approval remain outstanding; this is not an overall-upgrade completion claim.

### Task 7 specification-review follow-up: direct HTTP resource-link results

Review of `9cbcc8cf38d0abbbc0a7984f8e893188327d87b5` found a missed URI branch.
The new all-block tool conversion reaches HTTP(S) resource links even when
other text exists. `Resource#content` expects an `MCP::Result`, but the unchanged
HTTP reader returned a raw Hash containing an `HTTPX::Response::Body` object.
Both linked-tool results and direct resource inclusion therefore raised
`NoMethodError: undefined method 'error?' for an instance of Hash`; an HTTPX
transport error instead raised a masking `ErrorResponse#body` NoMethodError.
The original `git://`-only test did not exercise this defect.

The follow-up owns only four files: the already-patched vendored `resource.rb`,
`test/lib/ruby_llm_mcp_compatibility_test.rb`, this runbook, and `PATCHES.md`.
The runtime change checks `response.raise_for_status`, then wraps the response
envelope in the actual `MCP::Result`, storing `response.body.to_s`. Existing
HTTPX status/transport exceptions propagate instead of becoming success text.
There is no rescue shim, HTTP status-to-MCP error-code invention, URI dispatch
rewrite, new transport, auth/header change, SDK replacement, or application
code change. HTTP(S) still calls `HTTPX.get`; non-HTTP still calls the adapter's
`resource_read`. No database setup/migration, development/production DB access,
deployment, or child agent is involved.

Seven public-API regressions use actual HTTPX Request/Response/Body and
ErrorResponse objects constructed locally. Only `HTTPX.get` is replaced with a
canned response and restored in `ensure`; no real HTTP request or DNS lookup is
made by these tests. Coverage includes:

- HTTP **and** HTTPS resource links with text before/after them, exact URI
  dispatch, retained registered name/URI/description/MIME metadata, cached String
  content, and reuse without refetching.
- HTTP **and** HTTPS `Resource#include` on a real plain chat, with String content
  and no accidental attachments or MCP `resource_read` calls.
- A schema-validated structured result containing an HTTP resource link,
  preserving authoritative JSON and both first-image/last-audio attachments.
- Real HTTPX 404/503 exceptions, no persisted chat message or cached successful
  resource body on failure, and the identical original transport exception.

All Rails commands reuse the exact safe `task7_rails` environment above and
seed **202607** against only `nosia_ruby_llm_upgrade_test`.

| Stage | Runs | Assertions | Failures | Errors | Exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Seven new HTTP contracts before reader fix | 7 | 2 | 2 | 5 | 1 |
| Same contracts after reader fix | **7** | **64** | **0** | **0** | **0** |
| Entire MCP/local-engine focused set after fix | **74** | **429** | **0** | **0** | **0** |
| Standalone Docker path packaging regression | **2** | **8** | **0** | **0** | **0** |
| Full non-system suite after fix | **416** | **1779** | **0** | **1** | **1** |

The focused run completed in **6.933569 s**. The complete unfiltered suite
finished in **284.395959 s**, with no skips. Its only error is the accepted
`Website::CrawlableTest#test_crawl_url!_still_crawls_public_hosts` embedding
connection failure at `127.0.0.1:9`; there are no MCP/local-adapter failures or
errors. This is exact completed-run evidence, not a green full-suite claim.

```sh
# Identical RED/GREEN command, before/after the two-line reader adaptation.
task7_rails test test/lib/ruby_llm_mcp_compatibility_test.rb \
  --include '/resource_links_retain_metadata|resource_inclusion_converts|HTTP_resource/' \
  --seed 202607

# Full MCP/local-engine set, unchanged selection from the Task 7 gate.
task7_rails test test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/ruby_llm_mcp_transport_test.rb test/lib/engines \
  test/lib/mcp_catalog_registry_test.rb test/models/mcp_server_test.rb \
  test/models/mcp_server_local_test.rb test/controllers/mcp_servers_controller_test.rb \
  test/integration/local_engine_chat_test.rb test/integration/activate_engine_test.rb \
  test/integration/engines_boot_test.rb --seed 202607
task7_rails test --seed 202607
bundle exec ruby test/packaging/ruby_llm_path_dependency.rb --seed 202607
bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  test/lib/ruby_llm_mcp_compatibility_test.rb
bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  --only Lint vendor/gems/ruby_llm-mcp/lib/ruby_llm/mcp/resource.rb
git diff --check
```

Both changed Ruby files pass their lint checks. No public method was added;
only the private HTTP-reader return/error contract changes. `PATCHES.md` now
describes that exact behavior. The complete imported-source inventory remains
ten documented differences and 110 pristine files against the same published
1.0.1 archive SHA above. This follow-up does not claim Task 8, live authenticated
MCP interoperability, or deployment readiness.

The vendored gem was rebuilt outside Git, and the unchanged Docker pre-install
COPY fixture was rerun with the final resource source/patch note:

```sh
# From vendor/gems/ruby_llm-mcp:
gem build ruby_llm-mcp.gemspec \
  --output /tmp/opencode/nosia-rubyllm2-research/ruby_llm-mcp-1.0.1-nosia-task7-resource-link.gem
# From the worktree:
docker build \
  --file /tmp/opencode/nosia-rubyllm2-research/task3-packaging/Dockerfile.packaging \
  --output type=local,dest=/tmp/opencode/nosia-rubyllm2-research/task7-resource-link-packaging/rootfs .
env BUNDLE_GEMFILE=/tmp/opencode/nosia-rubyllm2-research/task7-resource-link-packaging/rootfs/rails/Gemfile bundle check
```

All three commands exit 0. All **135** exported dependency files hash-match
source. Reading the built gem's data archive also confirms `resource.rb` matches
the final source byte-for-byte, with MCP 1.0.1 and the exact RubyLLM 2.0.0 pin.
An exported-Gemfile `bundle exec ruby -r ruby_llm/mcp` check verifies
MCP 1.0.1 resolves from that export against RubyLLM 2.0.0 and runs a real
`Resource#content` conversion with a canned HTTPX response, requiring a String
equal to the response text. No full application image or in-image dependency
installation is claimed. Review confirms the runtime diff remains exactly the
two HTTP-reader lines described above; other bridge conversions and all
transport/auth/URI dispatch code are untouched by this follow-up.

### Task 7 quality-review follow-up: outbound policy and binary-safe tool JSON

Review of `28ef68ed0261f4a0c183ab377e8dd4b13164fe6e` identified two blockers in
the newly reachable all-block conversion. A resource link beside text or
structured output could fetch a private/metadata HTTP URL without Nosia's
outbound policy. Separately, Rails tried to serialize decoded attachment/IO
state in the AJAX tool endpoint; a real binary PNG raised
`JSON::GeneratorError: "\x89" from ASCII-8BIT to UTF-8`.

This follow-up changes only eight files:

- `vendor/gems/ruby_llm-mcp/lib/ruby_llm/mcp/configuration.rb`
- `vendor/gems/ruby_llm-mcp/lib/ruby_llm/mcp/resource.rb`
- `config/initializers/ruby_llm.rb`
- `app/controllers/mcp_servers_controller.rb`
- `test/lib/ruby_llm_mcp_compatibility_test.rb`
- `test/controllers/mcp_servers_controller_test.rb`
- `vendor/gems/ruby_llm-mcp/PATCHES.md`
- This runbook.

#### Security boundary

The vendored configuration exposes one documented callback,
`resource_url_validator`, defaulting to nil on initialization/reset. Before
**every** HTTP(S) resource fetch, the resource reader requires a callable
validator with a truthy result; unset/non-callable/false/nil approval raises
`MCP::Errors::ConfigurationError` before I/O. Policy exceptions propagate.
The app initializer installs `->(url) { UrlGuard.verify!(url) }`; vendor code has
no reference to the application constant and no weaker URL-policy fallback.
HTTP(S) still uses `HTTPX.get`; non-HTTP resource dispatch, all transport
implementations, credentials, and the existing server endpoint/stdio guards
are unchanged.

Tests exercise the **actual initializer callback** with fake DNS, not only a
stubbed vendor validator. Metadata, loopback, all three RFC1918 ranges, IPv6
loopback/private/link-local, private-resolving hostnames, and mixed public/private
DNS results must raise `UrlGuard::Blocked` with **zero HTTP fetches**, both
beside plain text and beside structured output. Public HTTP/HTTPS fixtures use
the real guard with public fake DNS plus canned HTTPX I/O. Direct resource reads
are rechecked after cache reset; this is validation on a new fetch, not a claim
to solve DNS rebinding. New/reset configurations and rejection callbacks also
have explicit fail-closed contracts.

HTTPX's default resource session does not enable `follow_redirects`. The redirect
test runs the actual `HTTPX.get`/request/response pipeline and replaces only its
physical `Session#send_request`, restoring the method and visibility in `ensure`.
A public 302 pointing to `169.254.169.254` produces exactly one request, never
a metadata fetch. No redirect plugin or replacement transport was introduced.
Future redirect-following would require destination validation **before every
redirect request**.

**Remaining known limitation:** `UrlGuard.verify!` resolves DNS before HTTPX
independently connects. The existing DNS-rebinding/TOCTOU window documented in
`lib/url_guard.rb` remains open; closing it requires IP-pinned connections and
is not claimed here. This patch enforces the existing Nosia policy; it does not
claim all outbound-network/SSRF risks have been eliminated.

#### HTTP serialization boundary

Only the tool-execution controller's JSON response is converted. A real
`RubyLLM::Attachment` becomes `{type, data, mimeType, filename}`, with type as a
String and data from the attachment's base64 `encoded` API. Arrays and hashes
recurse without changing their keys/order; JSON primitives remain unchanged.
Unsupported objects raise `TypeError` rather than entering arbitrary `as_json`
or IO inspection. No global serializer, core monkey patch, or model/LLM result
conversion is added. The existing permitted tool-argument JSON object and
account-scoped lookup are unchanged; no record attributes are mass-assigned.

Endpoint tests use real remote MCP tool conversion, real
`McpServer#execute_tool`, and the authenticated controller route, replacing only
the remote client/adapter I/O. Actual non-UTF8 PNG and audio bytes must round-trip
through base64 with exact MIME/filename fields and no `StringIO` internals.
Plain text and structured JSON remain unchanged; remote error hashes retain
their wrapper semantics. A direct model call in those same tests still returns
real decoded attachments. A separate nested-IO rejection contract verifies
Rails never invokes that object's `as_json`.

#### RED/GREEN and verification

All Rails commands use the unchanged `task7_rails` safe environment above,
only `nosia_ruby_llm_upgrade_test`, and seed **202607**. No development/production
DB, migration, reset, deployment, Task 8 work, or child agent is involved.

| Stage | Runs | Assertions | Failures | Errors | Exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| New policy/initializer and binary endpoint repros before runtime changes | 27 | 31 | 24 | 2 | 1 |
| Same selection after initial fixes | **27** | **133** | **0** | **0** | **0** |
| Unsupported nested IO before primitive-only JSON fallback | 1 | 1 | 1 | 0 | 1 |
| Final complete MCP/local-engine/endpoint set | **103** | **569** | **0** | **0** | **0** |
| Packaging regression | **2** | **8** | **0** | **0** | **0** |
| Full non-system suite after both fixes | **445** | **1919** | **0** | **1** | **1** |

The initial RED independently reproduced private HTTP reads instead of
`UrlGuard::Blocked`, the missing configuration/initializer contract, missing
revalidation after cache reset, and both real PNG JSON errors. The existing
default no-redirect behavior was a passing characterization in that selection,
not claimed as a newly failing feature. The final focused set additionally
includes the false/non-callable validator case, error-hash preservation, and
unsupported-IO rejection. It completed in **7.364649 s**. The full unfiltered
suite completed after all runtime/test changes in **403.184424 s**, with no
skips. Its only error is the accepted
`Website::CrawlableTest#test_crawl_url!_still_crawls_public_hosts` embedding
connection failure at `127.0.0.1:9`. There are **no MCP, adapter, policy, or JSON
endpoint failures/errors**. This records a completed full run, not a claim that
the entire suite or release gate is green.

```sh
# RED, then initial GREEN:
task7_rails test test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/controllers/mcp_servers_controller_test.rb \
  --include '/resource_URL_policy|outbound_resource_URL|HTTP_resource_validator|blocked_hosts|remote_binary/' \
  --seed 202607
# Independent unsupported-object RED:
task7_rails test test/controllers/mcp_servers_controller_test.rb \
  --include '/unsupported_IO/' --seed 202607
# Final focused set:
task7_rails test test/lib/ruby_llm_mcp_compatibility_test.rb \
  test/lib/ruby_llm_mcp_transport_test.rb test/lib/engines \
  test/lib/mcp_catalog_registry_test.rb test/models/mcp_server_test.rb \
  test/models/mcp_server_local_test.rb test/controllers/mcp_servers_controller_test.rb \
  test/integration/local_engine_chat_test.rb test/integration/activate_engine_test.rb \
  test/integration/engines_boot_test.rb --seed 202607
task7_rails test --seed 202607
bundle exec ruby test/packaging/ruby_llm_path_dependency.rb --seed 202607
bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml \
  app/controllers/mcp_servers_controller.rb config/initializers/ruby_llm.rb \
  test/controllers/mcp_servers_controller_test.rb test/lib/ruby_llm_mcp_compatibility_test.rb
bundle exec rubocop --config /tmp/opencode/nosia-rubyllm2-task2-rubocop.yml --only Lint \
  vendor/gems/ruby_llm-mcp/lib/ruby_llm/mcp/configuration.rb \
  vendor/gems/ruby_llm-mcp/lib/ruby_llm/mcp/resource.rb
git diff --check
```

The four app/test Ruby files and two edited vendor Ruby files pass their stated
lint checks; upstream vendor style is otherwise retained. The supported target
remains exactly RubyLLM **2.0.0** / MCP **1.0.1**. `PATCHES.md` inventories the
new configuration file, making **11 modified imported files / 109 pristine
files** out of 120, against the original verified archive SHA. No gemspec,
dependency, schema, ledger, or transport source change is included. This remains
Task 7 hardening, not a Task 8/deployment or live-interoperability certification.

Packaging was also rebuilt with the final policy-hook source and patch note:

```sh
# From vendor/gems/ruby_llm-mcp:
gem build ruby_llm-mcp.gemspec \
  --output /tmp/opencode/nosia-rubyllm2-research/ruby_llm-mcp-1.0.1-nosia-task7-security-json.gem
# From the worktree:
docker build \
  --file /tmp/opencode/nosia-rubyllm2-research/task3-packaging/Dockerfile.packaging \
  --output type=local,dest=/tmp/opencode/nosia-rubyllm2-research/task7-security-json-packaging/rootfs .
env BUNDLE_GEMFILE=/tmp/opencode/nosia-rubyllm2-research/task7-security-json-packaging/rootfs/rails/Gemfile bundle check
bundle exec ruby -e 'files = Dir["vendor/gems/ruby_llm-mcp/lib/**/*.rb"]; files.each { |file| RubyVM::InstructionSequence.compile_file(file) }; puts "Compiled #{files.size} vendored Ruby sources"'
```

All commands exit 0. All **135** exported dependency files hash-match source,
and all **105** vendored Ruby sources compile. An exported-Gemfile standalone
check loads MCP 1.0.1 from that vendor path against RubyLLM 2.0.0, verifies that
an unset validator refuses a real resource read with **zero canned HTTP calls**,
then explicitly opts into its public canned fixture and verifies its String
content. That packaging-only process does not load the app initializer; the
actual app callback is independently covered by the Rails contracts above.
No full application image/in-image install or existing database was used.

## Task 8: final integration evidence

Verified on 2026-10-14 from runtime commit
**`a3ae02933dba6e53610a67c946b80ad3df8ac364`**, on `upgrade/ruby-llm-2`, Ruby **4.0.7** / Rails **8.0.5.1** /
PostgreSQL. Task 8 changes documentation and read-only audit SQL only; no runtime,
dependency, migration, schema, legacy alias, or unrelated baseline fix was needed.
The [operator runbook](ruby-llm-2-deployment.md) supersedes the historical rollout
notes above. The parent session's fresh final review is **not yet recorded**.

### Safe execution and artifact inventory

All Rails commands use the full fake-key/port-9 environment in `task7_rails`
above, with `PARALLEL_WORKERS=1`. Normal Rails checks use only
`nosia_ruby_llm_upgrade_test`. Fresh setup substitutes only
`DATABASE_URL=postgresql:///nosia_ruby_llm_upgrade_fresh_test`;
the standalone harness ignores that variable and guards its own literal
`nosia_ruby_llm_upgrade_migration_test`. No existing development/production DB
was opened. The scratch databases/worktree are retained, not cleaned up.

The local command recorder `/tmp/opencode/nosia-task8-verify.py` supplies that
environment, captures complete logs and exact argument arrays/working directory/
exit codes/timings under **`/tmp/opencode/nosia-rubyllm2-task8/`**. These are local
artifacts, not durable production evidence. Its flags `--fresh`, `--base`, and
`--vendor` select the fresh URL, read-only archived source, or gem-build directory
respectively. `targeted-ruby-files.txt` records the complete authored-Ruby selection;
`focused-suite.json` records the complete focused test argument list.

### Fresh schema-based setup (not historical replay)

The new scratch name was first checked absent in `pg_database` through a guarded
normal-test connection; `createdb nosia_ruby_llm_upgrade_fresh_test` exited 0.
A direct connection then asserted **both the exact fresh database name and zero
public tables before `db:prepare`**. No database drop or existing schema reload
was used. The fresh-only commands were:

```sh
# In the full safe test environment, substituting ONLY the fresh DATABASE_URL:
bin/rails db:prepare
bin/rails ruby_llm:load_models
bin/rails runner /tmp/opencode/nosia-task8-fresh-smoke.rb
```

All final commands exit **0**. Schema preparation took **2.195 s**. The packaged
offline model load took **3.773 s** and loaded **1672 models**; inspection confirms
the task calls `load_from_json`, never `refresh`. The guarded smoke test passed
**1 run, 36 assertions, 0 failures/errors/skips** (Minitest seed **11138**).
It checks schema version `20261014152721`, all gem support tables and retained
message columns, integer role encoding, Chat's gem-owned registry key,
provider/model and tool-call unique indexes, usage index, validated legacy result
FK with `SET NULL`, and the independent application ledger. The fresh journal is
empty because no legacy rows were migrated.

Within a rolled-back transaction it creates a real account/chat/messages and an
uploaded text attachment, reads its bytes, adds a fake **80 / 20 / 15 / 5 / 3**
provider usage, verifies normalized readers/string model, and calls application
accounting twice. Exactly one own-ledger event and **80 / 20** account/chat
increments result. A custom test-model registry row exists only inside that
transaction; no provider call is made. The local initial smoke attempted a deferred
attachment upload before transaction commit (**1 run, 29 assertions, 1 error**,
exit 1); using `Blob.create_and_upload!` fixed the verification harness, not Rails
or application behavior. Final evidence is `fresh-smoke-final.{log,json}`.

`bin/setup` was inspected, **not executed**: it already calls `db:prepare` but also
installs packages and clears logs. The unchanged historical `CreateModels`
migration calls removed `RubyLLM.models.load_from_json!` / `Model.save_to_database`.
Full migration replay from zero is **not supported/verified with 2.0**; use the
tested schema-based path. Existing 1.16 upgrades apply only pending phases. No
historical rewrite or runtime legacy alias was added.

### Migration and SQL-audit rehearsal

```sh
bundle exec ruby test/upgrades/ruby_llm_v2.rb --seed 202608
```

Exit **0**: **12 runs, 154 assertions, 0 failures/errors/skips**, **26.510185 s**
Minitest time. Seven-message populated phases: prepare **0.408 s**, backfill
**0.170 s**, finish **0.158 s**. Guards, integer roles, FK deletion semantics,
blank/raw preservation, null costs, own-ledger/counter preservation, interrupted
committed batches/retries, and finish guards all pass. These are tiny local
correctness measurements, **not production downtime estimates**.

The new `ruby-llm-2-audit-{before,after,common}.sql` files were then executed via
`psql -X` on the guarded harness fixture, first with the real 1.16 names and then
after the real three-phase upgrade. The additional fourteen NULL/blank raw JSON
variants were included. The two ordered projection sets matched **row-for-row**,
including expected converted content, tool results, five usage buckets and
provider identity, attachment/blob links, complete own ledger, and counters.
All after-only journal/index/FK/price queries also execute successfully.

The reproducible local driver is `/tmp/opencode/nosia-task8-audit-check.rb`;
`audit-before.txt`, `audit-after.txt`, and `audit-sql-final.{log,json}` retain the
result. It reuses the harness's exact-database guard before fixture loading.
Its final invocation exits **0**, followed by another **12/154** passing harness
run (seed **202608**, **26.383574 s**). This is fixture SQL validation, not an
audit of a production snapshot or a tested backup/restore.

### Final runtime gates

Using `task7_rails` with seed **202608**:

```sh
task7_rails test --seed 202608
task7_rails zeitwerk:check
bundle check
bundle exec ruby test/packaging/ruby_llm_path_dependency.rb --seed 202608
```

| Gate | Observed result | Exit |
| --- | --- | ---: |
| Full non-system Rails suite | **445 runs, 1919 assertions, 0 failures, 1 error, 0 skips**, **347.776854 s** | **1** |
| Combined high-value focused set | **264 runs, 1345 assertions, 0 failures/errors/skips**, **233.363096 s** | **0** |
| Zeitwerk | Application eager-loads: `All is good!` | 0 |
| Bundler | Dependencies satisfied | 0 |
| Standalone Docker path regression | **2 runs, 8 assertions, 0 failures/errors/skips** | 0 |

The full suite's **only** error is the explicitly authorized baseline
`Website::CrawlableTest#test_crawl_url!_still_crawls_public_hosts`, which reaches
its unstubbed embedding request to `127.0.0.1:9` and raises
`Faraday::ConnectionFailed`. It is neither hidden nor fixed, and the full suite
is **not green**. No Task 2 compatibility RED remains. New completion API tests
use real RubyLLM JSON/SSE loops with fake HTTP responses, including prompt-only
input and 422/non-disclosure for no pending user response.

The focused command combines the Task 6 `focused` array of 27 application/API/
accounting/UI/streaming/job test files with the complete final Task 7 selection:

```sh
task7_rails test "${focused[@]}" \
  test/lib/ruby_llm_mcp_compatibility_test.rb test/lib/ruby_llm_mcp_transport_test.rb \
  test/lib/engines test/lib/mcp_catalog_registry_test.rb test/models/mcp_server_test.rb \
  test/models/mcp_server_local_test.rb test/controllers/mcp_servers_controller_test.rb \
  test/integration/local_engine_chat_test.rb test/integration/activate_engine_test.rb \
  test/integration/engines_boot_test.rb --seed 202608
```

Both background test commands completed and their exit results were received
before Task 8 was committed; no background verification process was left running.

### Full lint and security: not green, baseline distinguished

```sh
bundle exec rubocop
bundle exec brakeman --no-pager \
  -o /tmp/opencode/nosia-rubyllm2-task8/brakeman-report.json
```

Full RuboCop exits **1**, **337 files / 317 offenses**. A `git archive 38faaab`
source snapshot under the artifact directory was scanned with the **same current
installed lint tools**, from its own directory using the current `BUNDLE_GEMFILE`;
the original/root worktree and its unrelated edits were never modified. That
comparable baseline is **326 files / 98 offenses**, exit **1**. The difference
is explicit, not described as an unchanged green lint gate:

- **188** array-spacing offenses in the intentionally byte-preserved legacy
  schema fixture (the original generated schema is normally excluded).
- **27** unsupported-parser errors in the three new generated migrations.
- **4** additional unsupported-parser errors in the expanded executor tests.
- The original **98** findings remain: **91** Ruby-2.7-parser errors, **6** spacing
  offenses in old migrations, and **1** trailing-empty-line offense.

The repository's `4`-only `.ruby-version` does not yield a supported target for
this RuboCop setup, which defaults to the **Ruby 2.7 parser**. No broad style
changes, baseline fixes, or repository lint exclusions were introduced.
`rubocop-ruby4.yml` outside Git inherits the root config and sets only
`AllCops: TargetRubyVersion: 4.0`. With it, **40 changed authored application/test
Ruby files have zero offenses**, exit **0**. The **14** generated/edited-vendor/
gemspec Ruby files pass **Lint-only** checks, exit **0**, retaining upstream style.
All **105** vendored Ruby sources also compile, exit **0**. The default full
invocation is still not represented as passing.

Brakeman **8.0.4** exits **3** with **3 warnings, 0 scan errors**. The archived
base scan exits **3** with the **same three fingerprints**, no new warnings:

| Finding | File | Fingerprint prefix |
| --- | --- | --- |
| RenderInline / XSS, medium | `app/views/sources/texts/edit.html.erb:9` | `09d0f4d11f58` |
| PermitAttributes / account_id mass assignment, high | `app/controllers/api_tokens_controller.rb:34` | `4fad3c218f35` |
| EOLRails, high | unchanged Rails 8.0.5.1 in `Gemfile.lock` | `d84924377155` |

These existing findings require separate triage; no ignore/suppression or Rails
upgrade was added here. Static scanning is not a live penetration test or a
complete dependency vulnerability audit. Full JSON reports and the comparable
lint reports are retained in the artifact directory.

### Packaging, source review, and limits

The MCP gem builds outside Git as
`/tmp/opencode/nosia-rubyllm2-task8/ruby_llm-mcp-1.0.1-nosia-task8.gem`, exit **0**.
Its **121** packaged files byte-match vendor source and its dependency remains
`ruby_llm (= 2.0.0)`. Provenance recheck matches archive SHA
`22121bfdea1874935debdd9cee0235d02473885ce8347cf745a323f0707fd248`:
**120 imported files / 11 documented differences / 109 pristine**, MIT license
unchanged. `PATCHES.md` retains the narrow-port inventory and upstream removal path.

```sh
# From vendor/gems/ruby_llm-mcp:
gem build ruby_llm-mcp.gemspec \
  --output /tmp/opencode/nosia-rubyllm2-task8/ruby_llm-mcp-1.0.1-nosia-task8.gem
# From the application worktree:
docker build \
  --file /tmp/opencode/nosia-rubyllm2-research/task3-packaging/Dockerfile.packaging \
  --output type=local,dest=/tmp/opencode/nosia-rubyllm2-task8/packaging/rootfs .
env BUNDLE_GEMFILE=/tmp/opencode/nosia-rubyllm2-task8/packaging/rootfs/rails/Gemfile bundle check
git diff --check
```

Each exits **0**. The Docker fixture uses the actual pre-install COPY instructions
and `.dockerignore`; **135** exported dependency files hash-match source. Original
and exported Gemfiles resolve RubyLLM **2.0.0** and MCP **1.0.1** from their respective
vendor paths. A real decoded binary attachment/message conversion also runs
against the exported path. This uses host-installed dependencies: **no full native
multistage image build, in-image bundle install, or assets:precompile was run**.
System/browser tests and live authenticated provider/MCP calls were not run.

Preliminary verification-tool invocations (missing `python`, wrong gemspec working
directory, and passing RubyGems `FileSource` instead of a filename) failed with
**127 / 1 / 1**, respectively; corrected final commands above pass. They required
no application/dependency change. An initial baseline lint scan explicitly included
generated schemas and was not comparable; the own-directory **98-offense** baseline
above is the comparison used, with both reports retained.

Removed-API searches over `app/`, `config/`, and `lib/` return no matches. The only
test matches are intentional rejection of `with_params` and the valid persisted
**Chat** model record's `model_id` check; **Message** model is a string. Legacy
schema/migration fields and application-ledger columns remain intentionally named.
YARD review confirms new public bridge conversion/config boundaries and changed
application accounting/MCP boundaries are documented; no new public runtime API
is introduced in Task 8.

Self-review covers the full branch scope, lockfile delta, tenant/input boundaries,
instruction/provider options, true completion state machine, associations/enum,
nil/zero/cache accounting, content/tool/attachment preservation, phase ordering/
retry/irreversibility, FK targeting, narrow vendor inventory/security configuration,
read-only audit SQL, and maintenance/recovery instructions. No broad baseline fixes
or runtime redesign was added. The known URL-policy DNS-rebinding/TOCTOU limitation
remains explicit. **Production-sized rehearsal, tested backup/restore, live
authenticated interoperability, and fresh final integration/data-safety review
remain unperformed gates**, not checked-off release approval. No push, merge,
deployment, cleanup migration, worktree removal, or child agent was performed.
