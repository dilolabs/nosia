# RubyLLM 2.0 Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Upgrade Nosia from RubyLLM 1.14 through 1.15/1.16 to 2.0.0, preserving conversations, MCP integrations, streaming, and application accounting.

**Architecture:** Keep Nosia's chat/message models and its own usage ledger. Adopt RubyLLM-owned supporting records through the generated rename-mode migrations, adapted for Nosia's integer roles. Vendor the locked MCP bridge and port its RubyLLM integration without replacing its transports.

**Tech Stack:** Actual repository: Ruby 4, Rails 8.0, PostgreSQL/pgvector, Minitest, Hotwire, RubyLLM 2.0.0, ruby_llm-mcp 1.0.1. Do not upgrade Rails or the interpreter as part of this work.

---

## Approved Specification and Workspace

- Specification: `docs/superpowers/specs/2026-10-14-ruby-llm-2-upgrade-design.md`, approved by the user after commit `91f5dab`.
- Branch: `upgrade/ruby-llm-2`.
- Worktree: `/home/cbldev/gitd/dilolabs/nosia/.worktrees/ruby-llm-2-upgrade`.
- Root worktree contains unrelated changes. Do not stage, modify, or discard them.
- Worktree ignore was committed independently as `38faaab` before creation.
- No production deployment, existing development database migration, or cleanup migration.

## Baseline and Safe Test Environment

Dependencies are installed. A separate `nosia_ruby_llm_upgrade_test` database was created from the original schema. With the configuration below, the unchanged baseline is **328 runs, 1030 assertions, 0 failures, 1 error**. The sole error is `Website::CrawlableTest#test_crawl_url!_still_crawls_public_hosts`: the existing test reaches an unstubbed real embedding call. The user explicitly authorized proceeding with this recorded baseline rather than expanding scope to fix crawl-test isolation.

Use these environment variables for test commands, either as command prefixes or exports in a dedicated test shell. These are deliberately fake keys, not deployment credentials:

```bash
export RAILS_ENV=test
export DATABASE_URL=postgresql:///nosia_ruby_llm_upgrade_test
export PARALLEL_WORKERS=1
export ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=11111111111111111111111111111111
export ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=22222222222222222222222222222222
export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=33333333333333333333333333333333
export AI_API_KEY=test-only
export AI_BASE_URL=http://127.0.0.1:9/v1
export LLM_MODEL=test-model
export EMBEDDING_MODEL=test-embedding
export EMBEDDING_DIMENSIONS=4096
export CHUNK_SIZE=512
export CHUNK_OVERLAP=128
export RETRIEVAL_FETCH_K=3
```

Port 9 prevents accidental paid provider traffic. The checked-in schema uses 4096-dimensional chunks, so use 4096 rather than the example environment's 768. Never source production environment files. The test database is disposable; existing development and production databases are not.

## File and Responsibility Map

| Files | Responsibility |
| --- | --- |
| `Gemfile`, `Gemfile.lock` | Staged prerequisite upgrades and final exact 2.0.0 dependency |
| `vendor/gems/ruby_llm-mcp/` | Published MCP runtime, license, provenance, narrowly documented 2.0 patch |
| `config/initializers/ruby_llm.rb` | Supported configuration and explicit Chat Completions |
| `app/models/chat.rb`, `app/models/message.rb` | RubyLLM-owned associations, enum-safe scopes, application accounting |
| Three `db/migrate/*ruby_llm_v2*.rb` files | Prepare, backfill, finish; no cleanup |
| `test/upgrades/ruby_llm_v2.rb`, `test/fixtures/files/ruby_llm_1_16_schema.rb` | Standalone migration rehearsal, separate from normal Rails fixture tests |
| `app/models/chat/{completionable,answer_relevance,context_relevance}.rb` | Provider options and instruction semantics |
| `app/models/chunk/{enrichable,vectorizable,searchable}.rb` | Completion options and embedding token readers |
| `app/models/agent_skill/executor.rb`, `app/models/agent_skills/base.rb` | Agent instruction semantics, allowed methods, usage recording |
| `lib/engines/tool_adapter.rb`, `app/models/mcp_server.rb` | 2.0 tool schemas and keyword calls |
| `app/controllers/models_controller.rb`, `app/views/models/` | Public registry-based catalog and provider-qualified links |
| `app/views/messages/{_assistant,_message,_token_footer}.html.erb` | New token/model readers and tool-call rendering |
| Existing focused tests and new `test/lib/ruby_llm_mcp_compatibility_test.rb` | Behavioral regression coverage |
| `docs/upgrades/ruby-llm-2.md`, `README.md` | Deployment, recovery, patch maintenance, and verification evidence |

## Task 1: Verify the 1.x Prerequisites

Completed and reviewed in Tasks 1–7; checkbox status below records the historical
execution, not a claim that production operations occurred. Exact RED/GREEN
evidence and review follow-ups are in `docs/upgrades/ruby-llm-2.md`. The example
token constructor below was adapted to 1.16's supported `cached:`/
`cache_creation:` keywords at that checkpoint; 2.0 uses `cache_read:`/`cache_write:`.

**Files:** `Gemfile`, `Gemfile.lock`, existing focused tests, `docs/upgrades/ruby-llm-2.md`.

- [x] Run the baseline with the safe environment and record its known exception. Run the focused set separately; all focused tests must pass:

```bash
bin/rails test test/models/chat_test.rb test/models/chat/completionable_test.rb test/models/chat/stop_generation_test.rb test/models/chunk/vectorizable_test.rb test/models/chunk/searchable_test.rb test/models/agent_skill/executor_test.rb test/lib/engines/tool_adapter_test.rb test/models/mcp_server_test.rb test/models/mcp_server_local_test.rb test/integration/token_footer_test.rb test/integration/models_consumption_column_test.rb
```

- [x] Change only the RubyLLM declaration to `gem "ruby_llm", "1.15.0"`, run `bundle update ruby_llm --conservative`, and rerun the focused set. Then repeat with `gem "ruby_llm", "1.16.0"`. Preserve separate commits for both verified intermediate versions, so a matching 1.16 application build actually exists for rename-mode recovery.
- [x] Check `db/migrate/20260402102301_add_ruby_llm_v1_14_columns.rb` and confirm `tool_calls.thought_signature` is text. Do not generate duplicate 1.x migrations.
- [x] Write a token semantics regression before changing accounting. Under 1.15/1.16, demonstrate normalized cache buckets explicitly:

```ruby
test "token buckets keep standard input separate from cache reads and writes" do
  tokens = RubyLLM::Tokens.new(input: 80, output: 20, cached: 15, cache_creation: 5)
  assert_equal 80, tokens.input
  assert_equal 100, tokens.input + tokens.cache_read + tokens.cache_write
  assert_equal 20, tokens.output
end
```

- [x] Record exact prerequisite commit IDs and focused results in the upgrade runbook. Do not rewrite historical `TokenUsage` records or cached counters to reinterpret old token semantics.

## Task 2: Add Failing 2.0 Contracts Before Changing Dependencies

**Create:** `test/lib/ruby_llm_mcp_compatibility_test.rb`.
**Modify tests:** `test/lib/engines/tool_adapter_test.rb`, `test/models/chat/completionable_test.rb`, `test/models/chunk/vectorizable_test.rb`, `test/models/chunk/searchable_test.rb`, `test/models/agent_skill/executor_test.rb`, `test/integration/token_footer_test.rb`.

- [x] Add a dependency/contract test that fails on 1.16 for the missing upgrade, not an unrelated boot failure:

```ruby
require "test_helper"

class RubyLLMMcpCompatibilityTest < ActiveSupport::TestCase
  test "the application runs the intended RubyLLM version" do
    assert_equal Gem::Version.new("2.0.0"), Gem.loaded_specs.fetch("ruby_llm").version
  end

  test "inline MCP attachments expose decoded bytes and encoded wire content" do
    bytes = "binary payload".b
    attachment = RubyLLM::MCP::Attachment.new(Base64.strict_encode64(bytes), "application/pdf")
    assert_equal bytes, attachment.content
    assert_equal Base64.strict_encode64(bytes), attachment.encoded
    assert_equal bytes.bytesize, attachment.byte_size
    assert_equal "application/pdf", attachment.mime_type
  end
end
```

- [x] Add and run a new local-tool test using `adapted.call(query: "einstein")` and asserting `adapted.parameters_schema` preserves required/nested properties and does not expose credentials. Keep existing positional-call tests until the dependency switch; then convert them to the supported keyword API rather than adding an application compatibility shim.
- [x] Add this test to `Chat::CompletionableTest`; it supplies the new readers on a real persisted source while explicitly rejecting the old one. Run it and observe `legacy token reader used` before implementing Task 5:

```ruby
test "completion accounting reads normalized tokens and a string model" do
  message = @chat.messages.create!(role: :assistant, content: "answer")
  tokens = RubyLLM::Tokens.new(input: 80, output: 20, cache_read: 15, cache_write: 5, thinking: 3)
  message.define_singleton_method(:tokens) { tokens }
  message.define_singleton_method(:model) { "glm-5.2" }
  message.define_singleton_method(:input_tokens) { raise "legacy token reader used" }

  assert_difference -> { TokenUsage.where(source: message).count }, 1 do
    @chat.record_completion_usage!(message)
  end
  usage = TokenUsage.find_by!(source: message)
  assert_equal [ 80, 20, 15, 5, 3 ], usage.attributes.values_at(
    "input_tokens", "output_tokens", "cached_tokens", "cache_creation_tokens", "thinking_tokens"
  )
  assert_equal "glm-5.2", usage.model_id
  assert_equal 80, @chat.reload.input_tokens_count
  assert_equal 20, @account.reload.output_tokens_count
  assert_no_difference -> { TokenUsage.count } do
    @chat.record_completion_usage!(message)
  end
end
```
- [x] Change embedding fakes to `Struct.new(:vectors, :tokens, :model)` with a 1.16-compatible normalized token object. Run each focused file and confirm its new test fails on the old reader. Do not implement any reader changes until this failure is observed. The footer contract was deferred to Task 6 and is now green.
- [x] For existing tests, preserve behavioral assertions rather than deleting tests that reference removed classes. Their setup will change to supported registry/usage records in Task 5.

## Task 3: Vendor the Published MCP Bridge and Resolve RubyLLM 2.0

**Files:** `vendor/gems/ruby_llm-mcp/`, `Gemfile`, `Gemfile.lock`, `config/initializers/ruby_llm.rb`.

- [x] Fetch and unpack the published release outside the repository, then copy its runtime and license into the vendor directory. This is importing the selected third-party dependency, not hand-writing a transport implementation:

```bash
gem fetch ruby_llm-mcp --version 1.0.1
gem unpack ruby_llm-mcp-1.0.1.gem
```

Run those commands under `/tmp/opencode/nosia-rubyllm2-research`, not the application root. Copy the published `lib/`, gemspec, README, and license. Verify the archive SHA-256 against RubyGems metadata. Keep upstream license notices. Do not commit caches, downloaded archives, installed gems, or unrelated development files.

- [x] Change the vendored gemspec RubyLLM requirement to `= 2.0.0`, its verified compatibility target. Retain existing version 1.0.1 and identify the local patch in `PATCHES.md`. Set the root declarations:

```ruby
gem "ruby_llm", "2.0.0"
gem "ruby_llm-mcp", path: "vendor/gems/ruby_llm-mcp"
```

- [x] Use `bundle update ruby_llm ruby_llm-mcp --conservative`. Expected changes include `schematist` replacing `ruby_llm-schema` and required RubyLLM HTTP dependencies; preserve the existing `json < 3` constraint. Inspect the complete lockfile diff.
- [x] Update the initializer by removing `config.use_new_acts_as` and adding:

```ruby
config.openai_protocol = :chat_completions
```

Retain endpoint, key, model, embedding model, and system-role settings that the 2.0 configuration actually supports. Do not globally remove temperature or change endpoint behavior.
- [x] Run the version assertion separately. It must now pass. The rest of the application may require Tasks 4–6 before the full Rails suite is green; record this intermediate state honestly.

## Task 4: Rehearse and Adapt the Three Rename Migrations

**Create:** `test/upgrades/ruby_llm_v2.rb`, `test/fixtures/files/ruby_llm_1_16_schema.rb`.
**Generate:** `db/migrate/*_prepare_ruby_llm_v2_upgrade.rb`, `*_backfill_ruby_llm_v2_data.rb`, `*_finish_ruby_llm_v2_upgrade.rb`.

- [x] Save the original legacy schema as a committed test fixture before updating `db/schema.rb`. Build the rehearsal as a standalone Minitest executable, not a normal `*_test.rb` file using `test_helper`: normal Rails fixture/pending-schema setup must not run against a deliberately legacy database.
- [x] Require `bundler/setup`, `minitest/autorun`, `active_record`, and `ruby_llm`. Connect only to a newly created `nosia_ruby_llm_upgrade_migration_test` database. Fail closed before destructive fixture setup:

```ruby
expected = "nosia_ruby_llm_upgrade_migration_test"
ActiveRecord::Base.establish_connection(adapter: "postgresql", database: expected)
unless ActiveRecord::Base.connection.select_value("SELECT current_database()") == expected
  raise "Refusing migration rehearsal outside the dedicated disposable database"
end
```

- [x] Seed legacy data without current app callbacks, using anonymous Active Record table classes and `insert_all!`: a model; user/account/chat; user and assistant messages; an assistant tool call plus linked tool-result message; structured `content_raw`; an assistant with null token counts but identifiable chat model; Active Storage blob/attachment links; an existing application `token_usages` row and nonzero counters. Use the original schema's required columns, timestamps, and existing FK order. Keep the assistant role **10**, user **20**, system **0**, tool **30**.
- [x] Before generation, add tests asserting the three migration files exist and the post-upgrade data contract. Run and confirm the missing migration failure. Generate without cleanup:

```bash
bin/rails generate ruby_llm:upgrade --mode rename chat:Chat message:Message model:Model tool_call:ToolCall
```

The generator resolves names/tables without needing to instantiate the removed supporting models. Do not eager-load obsolete declarations during generation. Preserve generator output; do not hand-reimplement the migration framework.

- [x] Run the rehearsal against unmodified generated files. Expected initial failure: PostgreSQL rejects comparing integer `role` with `'assistant'`. This must be reproduced before adapting the SQL.
- [x] In all three generated migrations, change their role candidate condition from the string literal to the legacy integer:

```ruby
conditions << "#{message_value(:role)} = 10" if column_exists?(:messages, :role)
```

Document this as Nosia's fixed historical enum encoding. Do not reference the current `Message` class from irreversible migration SQL. Check every occurrence; changing backfill alone leaves prepare/finish broken.

- [x] Rehearse with the real existing FKs. Preserve application-owned IDs and references; let the generated migration manage supporting tables and its own references. Do not remove unrelated FK constraints. The reviewed legacy-result SET NULL and blank-content verifier adaptations are documented in the runbook.
- [x] Add executable assertions after migration:

```ruby
assert_equal before_message_ids, table(:messages).order(:id).pluck(:id)
assert_equal before_roles, table(:messages).order(:id).pluck(:role)
assert_equal before_attachments, table(:active_storage_attachments).order(:id).pluck(:id, :record_type, :record_id, :blob_id)
assert_equal before_application_usage, table(:token_usages).order(:id).pluck(:id, :input_tokens, :output_tokens)
assert_equal before_account_counters, table(:accounts).order(:id).pluck(:id, :input_tokens_count, :output_tokens_count)
assert_equal "Message", migrated_tool_call.fetch("result_type")
assert_equal legacy_tool_result_id, migrated_tool_call.fetch("result_id")
assert_equal({ "answer" => "preserved" }, JSON.parse(migrated_structured_content))
assert_equal historical_input_total, table(:ruby_llm_usages).sum(:input_tokens)
assert_nil table(:ruby_llm_usages).where(message_id: assistant_without_prices_id).pick(:total_cost)
```

Define `table(name)` locally as an anonymous `ActiveRecord::Base` subclass with its table name and disabled STI. Capture the `before_*` snapshots and seeded IDs in test setup. Avoid active app model callbacks while comparing historical data.

- [x] Exercise interruption and retry: inject an exception after a committed backfill batch by wrapping the migration's progress callback, rerun the same migration, and assert each historical message has exactly one usage row. Rehearse prepare/backfill retries before finish; finished migrations intentionally reject replay. Test finish-before-backfill failure and a missing usage model identity failure; preserve their actionable errors.
- [x] Run `bundle exec ruby test/upgrades/ruby_llm_v2.rb`. Record timings from the disposable rehearsal, explicitly not production downtime estimates. Only after success, run `RAILS_ENV=test bin/rails db:migrate` against `nosia_ruby_llm_upgrade_test` and update `db/schema.rb`. Never run an unqualified development migration command.

## Task 5: Adopt Supporting Associations and Token Readers

**Files:** `app/models/chat.rb`, `app/models/message.rb`, `app/models/model.rb`, `app/models/tool_call.rb`, embedding concerns, agent executors, associated tests and `test/test_helper.rb`.

- [x] Before implementation, run the new token-contract tests and existing blank-message/tool-call preservation tests against 2.0 to capture the concrete failures.
- [x] Remove the application's `Model` and `ToolCall` classes only from the 2.0 build. Remove the explicit `belongs_to :model` declarations in Chat/Message: Chat's macro already owns its correctly keyed internal model association, while Message's `model` is now a string from usage. Remove Message's `has_many :tool_calls` declaration so it cannot shadow RubyLLM's public tool-call hash.
- [x] Use the internal association for database existence checks and joins:

```ruby
# Chat#purge_blank_assistant_messages!
messages.assistant.where(content: [ nil, "" ]).where.missing(:ruby_llm_tool_calls).destroy_all

# Message.without_tool_calls
left_joins(:ruby_llm_tool_calls)
  .where("messages.role != 30 OR ruby_llm_tool_calls.id IS NULL")
  .distinct

# Message#broadcast_created, intermediate-assistant guard
if assistant? && ruby_llm_tool_calls.exists?
```

Preserve the existing integer `role` enum, `has_many_attached`, callbacks, and chronological ordering. Prefer the macro's `created_at, id` ordering when removing duplicate association declarations; verify existing chronological-history tests.

- [x] Implement completion ledger translation without changing its schema:

```ruby
def record_completion_usage!(message)
  return if message.nil? || message.tokens.input.nil?
  return if TokenUsage.where(source: message).exists?

  tokens = message.tokens
  TokenUsage.create!(
    account_id:, chat_id: id, kind: :completion, source: message,
    model_id: message.model,
    input_tokens: tokens.input || 0, output_tokens: tokens.output || 0,
    cached_tokens: tokens.cache_read || 0, cache_creation_tokens: tokens.cache_write || 0,
    thinking_tokens: tokens.thinking || 0
  )
end
```

- [x] In `AgentSkill::LLMExecutor#record_agent_skill_usage`, take `tokens = message.tokens`, retain the existing input-or-output eligibility, use `message.model`, and map the same five buckets. Preserve execution source and `:agent_skill` kind. Do not create completion records for historical migration events.
- [x] In both embedding concerns, replace every result `input_tokens` read, including `record_embedding_usage_if_needed`, with `tokens.input`:

```ruby
return unless embedding_result&.tokens&.input&.positive?
# Within the unchanged TokenUsage attribute hash:
input_tokens: embedding_result.tokens.input
```

For query recording retain `chat &&` in the eligibility condition. Keep existing configured model identity and vector persistence behavior.

- [x] Adapt fixture setup that creates `Model` to use `RubyLLM::ActiveRecord::Model` only when an actual internal record is needed. Persist usage test data through `message.ruby_llm_usages.create!(chat:, operation: "chat", provider: "openai", model: "glm-5.2", status: "succeeded", input_tokens: 120, output_tokens: 30)` rather than retained legacy message token columns. Internal record setup is test data, not the application's catalog API.
- [x] Run completion, embedding, skill, chat, message, placeholder, and stop-generation tests. Require all targeted tests green before moving on.

## Task 6: Migrate Request Options, Instructions, Catalog, and Usage UI

**Files:** completion/relevance/enrichment concerns, agent skill allowlists, model controller/views, token footer/call sites, associated tests.

- [x] Add tests capturing configured provider options and system-message behavior before implementation. Use singleton fake chat methods that record calls instead of sending requests. Verify base instructions are replaced, attachment warnings append, and LLM-skill instructions retain their previous appending intent.
- [x] Replace runtime `with_params` with `with_provider_options`, retaining the existing provider's field names/nesting. Remove `replace: true`; replace `replace: false` with `append: true` where the old 1.x semantics append. Change both agent skill allowlists and streaming-test stubs to the new method name. Preserve existing request values and temperature behavior; document that 2.0 no longer rewrites unsupported temperatures.

```ruby
self.with_provider_options(max_tokens: options[:max_tokens], top_p: options[:top_p], top_k: options[:top_k])
self.with_instructions(augmented_system_prompt)
self.with_instructions(note, append: true)

# AgentSkill::LLMExecutor
message = chat.with_instructions(instructions, append: true).ask(@context[:query])
```

- [x] Add catalog request tests for overlapping model IDs from two providers and IDs containing `/` or `.`. Keep the existing show route with the fixed segment `model` and explicit query parameters, avoiding model IDs as Rails primary keys. Use `model_path("model", model_id: model.id, provider: model.provider)` in the row partial. Show resolves `params[:model_id]` and `params[:provider]`; reject absent/non-string values or any other `:id` with 404 before registry lookup. Test round trips before changing views. Slashes remain escaped query values, not Rails route segments.
- [x] Set index data to `RubyLLM.models.all`, use `RubyLLM.models.find(model_id, provider:)` for show, refresh with `RubyLLM.models.refresh`, and translate registry misses to 404. Render explicitly with the existing partial, because metadata values are not Active Record records:

```erb
<%= render partial: "models/model", collection: @models, as: :model %>
```

Use `model.id`, `model.price(:input)`, `model.price(:output)`, and an explicit safe HTML ID. Remove `dom_id(model)` and implicit polymorphic links for registry values. Retain the Comparia column and pass `model.id` to GreenIt.

- [x] Update token footer code and both guards:

```ruby
total_in = message.tokens.input || 0
total_out = message.tokens.output || 0
energy = GreenIt.energy_kwh(tokens: total_in + total_out, model_id: message.model, kind: :completion)
```

```erb
<% if message.done? && (message.tokens.input || message.tokens.output) %>
```

- [x] Check all tool-call views and controllers for relation assumptions. Iterate the public hash with `.each_value` when rendering call values, and use explicit HTML IDs for internal records. Preserve existing content visibility rather than regenerating the UI.
- [x] Run catalog/footer/cache tests, completion/agent tests, chat controller tests, streaming/stop tests, and job tests. Inspect external API controllers for indirectly renamed calls, but do not change unrelated API behavior. The reviewed prompt-only real-loop JSON/SSE and 422/non-disclosure regressions are included.

## Task 7: Port MCP Tools and Multimodal Integration

**Files:** vendored `lib/ruby_llm/mcp/{content,attachment,tool,prompt,resource,sample}.rb`, `handlers/concerns/sampling_actions.rb`, Nosia's `lib/engines/tool_adapter.rb`, `app/models/mcp_server.rb`, compatibility tests.

- [x] Run the inline-attachment failure from Task 2. Add fake-adapter tests for text/structured tool results, mixed attachments, error results, prompt/resource inclusion, and sampling message conversion. Use canned MCP protocol hashes and a fake adapter's `execute_tool`/`execute_prompt`/`resource_read`; no external credentials or services.
- [x] Port `MCP::Attachment` using a decoded IO source and the real RubyLLM parent initializer so `source`, `filename`, `config`, and byte size remain valid:

```ruby
require "base64"
require "stringio"

def initialize(content, mime_type)
  super(StringIO.new(Base64.strict_decode64(content)), filename: "mcp-attachment")
  @mime_type = mime_type
end
```

Do not override `content` to return encoded data; inherit `content` and `encoded` from RubyLLM. Test actual bytes and wire Base64 independently.

- [x] Make `RubyLLM::MCP::Content` an ordinary bridge-owned value, not a subclass or global reintroduction of removed `RubyLLM::Content`. Preserve its bridge-local readers, and provide explicit conversion points:

```ruby
def to_tool_result
  attachments.empty? ? text.to_s : [ text, *attachments ].compact
end

def to_message(role:)
  RubyLLM::Message.new(role:, content: text, attachments:)
end
```

Initialize with `@text = text` and `@attachments = Array(attachments)`. Validate/normalize callers at the bridge boundary; tool results may contain only text and actual RubyLLM attachments, not arbitrary bridge value objects.

- [x] Rename the remote Tool reader `params_schema` to `parameters_schema`, update its `to_h` key, and convert every successful result from bridge Content to `to_tool_result` before returning from `execute`. Preserve structured JSON output, error hashes, resource links, and all supported attachment blocks. Test multiple blocks so later results are not silently discarded by `content.first`.
- [x] In Prompt, Resource, Sample, and SamplingActions, convert bridge content with `to_message(role:)`, passing text and attachments separately. Remove positional hash constructors and Content-valued message content. Test normal and persisted-chat inclusion. Preserve tool/resource lookup and capability errors; do not add approval/sampling features unused by Nosia.
- [x] Change the local engine adapter to `klass.parameters(schema.deep_transform_keys(&:to_s)) if schema`, and all actual tool invocations to the keyword API. The final server boundary uses a plain string-keyed Hash to preserve indifferent-access semantics, rather than a compatibility shim.
- [x] Add transport contract tests confirming `stdio`, `sse`, and `streamable` select the unchanged transport classes, pass the same URL/headers/command, and retain clean shutdown behavior. Use fake transports or local fixture servers; URL validation and stdio deployment opt-in must still apply. Do not replace transports or bypass security checks to make tests pass.
- [x] Run all MCP/local-engine tests and `test/lib/ruby_llm_mcp_compatibility_test.rb`. Record upstream provenance, modified files, supported RubyLLM version, and the removal path when upstream ships compatibility in `vendor/gems/ruby_llm-mcp/PATCHES.md`. Reviewed HTTP-resource policy and binary-JSON follow-ups are included; DNS TOCTOU remains documented.

## Task 8: Fresh Setup, Deployment Documentation, and Final Verification

**Files:** `docs/upgrades/ruby-llm-2.md`, `docs/upgrades/ruby-llm-2-deployment.md`, three read-only audit SQL files, `README.md`, and this plan. No schema or historical migration edit was necessary: fresh setup uses the checked-in schema.

- [x] Test fresh schema loading into another explicitly named disposable test database. Check the early `CreateModels` migration's removed calls separately: prefer normal schema-based fresh setup; if full historical replay must remain supported, make its data-loading operation migration-local and version-independent rather than adding runtime legacy shims. Fresh `db:prepare`, offline registry loading, and a guarded 1-test/36-assertion smoke pass; full historical replay is explicitly not supported/verified with 2.0.
- [x] Write the runbook with these commands and clear production preconditions:

```bash
# After verified backup, prepared 1.16 build, drained AI work, and maintenance:
bin/rails db:migrate
bin/rails ruby_llm:load_models
```

Explain that plain `db:migrate` runs every pending phase. Include each generated migration's actual timestamp in its `db:migrate:up` command, in prepare/backfill/finish order, for execution outside deployment timeouts. Include audit SQL for message IDs/counts, enum distributions, attachment links, tool results, usage totals, and application counters; expected values are captured from the pre-upgrade snapshot, not guessed. Keep historical unknown prices unknown.

- [x] Document that rename has no `down`; recovery restores the tested backup and matching prerequisite application together. New 2.0 writes do not maintain old columns. Keep AI paused after any phase failure. Record that cleanup is a later deployment, requires re-review of app references/FKs, and is not included here.
- [x] Document the one authorized baseline crawl error distinctly from upgrade failures. Record intermediate version commits, migration rehearsal timing, commands, exit codes, and focused results.
- [x] Run the migration rehearsal, focused suite, full suite, and autoload validation with the safe environment:

```bash
bundle exec ruby test/upgrades/ruby_llm_v2.rb
bin/rails test
bin/rails zeitwerk:check
bundle exec rubocop
bundle exec brakeman --no-pager
git diff --check
```

Expected: migration rehearsal and upgrade-focused tests pass; full suite has no newly introduced failures, with the explicitly accepted live-embedding crawl error reported if still present. Lint/security must not add new issues; distinguish pre-existing findings accurately.

Observed Task 8: migration **12/154 pass**; combined focused **264/1345 pass**;
full **445/1919, 0 failures, 1 accepted crawl error** (exit 1); Zeitwerk passes.
Default RuboCop is **not green** (317 offenses versus the comparable baseline's
98); the added findings are preserved-schema layout and unsupported-parser
errors, not silently ignored. With an external Ruby-4 parser config, all 40
changed authored Ruby files pass; 14 generated/vendor/gemspec files pass Lint-only.
Brakeman exits 3 with the same three warning fingerprints as archived `38faaab`;
no new warning. Packaging regression **2/8**, gem build, Docker path export,
binary conversion, and source/hash checks pass. No full image build or assets
precompile was run. Detailed commands/artifacts are in the Task 8 evidence.

- [x] Search application runtime and test setup for removed APIs:

```bash
rg 'acts_as_model|acts_as_tool_call|use_new_acts_as|with_params|replace:|params_schema|model&?\.model_id|message\.(input_tokens|output_tokens|cached_tokens|cache_creation_tokens|thinking_tokens)' app config lib test
```

Allow legitimate application-ledger database columns and the intentional legacy schema fixture; do not blindly replace accounting SQL or quoted historical migration fields.

- [x] Confirm YARD documentation for new public bridge/helper methods; preserve upstream style within vendored sources and repository conventions in application files. Self-review with Rails code-review and migration-safety guidance. Task 8 adds no public runtime API.
- [x] Parent session: fresh final integration/data-safety review approved at `88a2a18` after the MCP explicit-generation follow-up. Parent verification confirmed 466 tests / 2106 assertions, zero failures and the accepted pre-existing crawl error; migration rehearsal 12 / 154 and packaging 2 / 8 passed. This does not approve production rollout or merging with a non-green baseline.
- [x] Commit only task-owned files after tests/checks. Leave the worktree on its upgrade branch for review; do not merge, push, deploy, or delete the worktree without user direction.

### Operator release gates (not performed by this implementation)

- [ ] Production-sized isolated snapshot rehearsal with measured locks/downtime.
- [ ] Tested consistent backup/restore and matching 1.16 build/storage recovery.
- [ ] Live authenticated MCP/provider interoperability on the intended deployment.
- [ ] Separate production maintenance/deployment approval. No initial cleanup.

## Plan Self-Review

- Approved rename mode, MCP patch, protocol preservation, prerequisite builds, own ledger, integer roles, data audit, attachments, streaming/stop behavior, unknown historical prices, and deferred cleanup each have explicit tasks.
- All production operations are documented only; executable rehearsals target dedicated disposable databases.
- Known baseline error is recorded and authorized, not silently weakened or counted as passing.
- Import unchanged upstream source from the pinned published gem; test and document every compatibility adaptation.
- Tasks 1–4 establish prerequisite and schema confidence; Tasks 5–7 migrate the coupled runtime surface; Task 8 is the integration/release gate.
