# RubyLLM 2.0 upgrade: prerequisites and compatibility contracts

## Status

Task 1 is verified on Ruby 4.0.7, Rails 8.0.5.1, and PostgreSQL using only
the scratch database `nosia_ruby_llm_upgrade_test`. Its prerequisite checkpoint
is exactly RubyLLM **1.16.0**. Task 3 now pins **2.0.0** and vendors the MCP
bridge, but its runtime compatibility port is not yet implemented. These
results do not establish that the final 2.0 upgrade is ready for deployment.

Task 2 adds test-only 2.0 contracts on top of `a5ecca3`. They are intentionally
**RED** on the unchanged 1.16.0 dependency; see the evidence below. Production
implementation remains for subsequent tasks. Task 3's version/configuration
checks are green; the other contracts remain RED, with evidence below.

No application accounting, historical `TokenUsage` records, account/chat
counters, migrations, or schema files were changed. No development or
production database was accessed, and no deployment was performed.

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
