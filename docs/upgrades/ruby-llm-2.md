# RubyLLM 2.0 upgrade: prerequisites and compatibility contracts

## Status

Task 1 is verified on Ruby 4.0.7, Rails 8.0.5.1, and PostgreSQL using only
the scratch database `nosia_ruby_llm_upgrade_test`. Its prerequisite checkpoint
is exactly RubyLLM **1.16.0**. Task 3 now pins **2.0.0** and vendors the MCP
bridge, but its runtime compatibility port is not yet implemented. These
results do not establish that the final 2.0 upgrade is ready for deployment.
Task 4 now verifies the three rename migrations on the dedicated legacy-schema
rehearsal database and updates the schema from the normal scratch test database.
Task 5 adopts the supporting associations and normalized accounting readers;
request/instruction/catalog/usage-UI changes and the MCP runtime port remain pending.

Task 2 adds test-only 2.0 contracts on top of `a5ecca3`. They are intentionally
**RED** on the unchanged 1.16.0 dependency; see the evidence below. Production
implementation remains for subsequent tasks. Task 3's version/configuration
checks were green at that checkpoint; subsequent task evidence follows below.

Through Task 3, no migrations or schema files changed. Task 4 adds the generated
phases and schema dump, without rewriting application accounting, historical
`TokenUsage` records, or account/chat counters. No development or production
database was accessed, and no deployment was performed.

## Verified application checkpoints

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
