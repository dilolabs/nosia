# RubyLLM 2.0 upgrade: verified 1.x prerequisites

## Status

Task 1 is verified on Ruby 4.0.7, Rails 8.0.5.1, and PostgreSQL using only
the scratch database `nosia_ruby_llm_upgrade_test`. The current dependency is
exactly RubyLLM **1.16.0**, not 2.0.0. These results do not establish that the
final 2.0 upgrade is ready for deployment.

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

The dependency is intentionally left at 1.16.0. RubyLLM 2.0 dependency changes,
MCP compatibility work, the approved rename migration, and application
accounting changes are outside this completed prerequisite task.
