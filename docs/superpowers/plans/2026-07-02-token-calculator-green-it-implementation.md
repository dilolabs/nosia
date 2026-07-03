# Token Calculator & Green-IT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the input/output token usage Nosia already captures (per message, per chat, per account), capture the embedding and agent-skill tokens that are currently discarded, and translate every token into environmental impact (kWh, gCO2e) using per-model measured consumption from the Comparia benchmark — computed live so coefficient updates retroactively correct history.

**Architecture:** Approach B — an append-only `token_usages` event log (one row per LLM call, polymorphic `source` + denormalized `chat_id`), plus cached headline counters on `chats`/`accounts`. Per-kind / per-model / per-day breakdowns stay as live indexed `GROUP BY` queries. A `GreenIt` lib module + static `config/model_energy.yml` (built from the Comparia CSV) provide the live energy/CO2e calculation. Three explicit write paths (completions, embeddings, agent skills); the only callback is the counter-cache increment.

**Tech Stack:** Ruby on Rails 8, MySQL (SaaS) / SQLite (OSS), Hotwire (Turbo Streams), Minitest + setup-built records (no fixtures), RubyLLM, `acts_as_tenant`.

**Spec Document:** `docs/superpowers/specs/2026-07-02-token-calculator-green-it-design.md`

---

## Deviations from the spec (confirmed during planning)

These are deliberate corrections of spec inaccuracies, surfaced by reading the actual codebase. Implementers must follow the plan, not the spec, on these points:

1. **IDs are bigint serial, NOT UUIDv7.** The existing `messages`, `chats`, `accounts`, `agent_skill_executions` tables all use bigint `id` and bigint `t.references` FKs (confirmed in `db/schema.rb`). The `.claude/rules/migrations.md` rule that says "UUIDs as primary keys" is **not** followed by the actual codebase. The `token_usages` migration uses bigint `t.references` to match. (`db/migrate/20260418134738_create_agent_skills.rb` is the style reference.)
2. **Tests build records in `setup`, NOT fixtures.** `test/fixtures/` is empty; the real test pattern (see `test/models/agent_skill_test.rb`) creates `User`/`Account` in `setup` and sets `ActsAsTenant.current_tenant = @account`. Do not add fixture files.
3. **No foreign key constraints** in migrations (per project convention — `t.references :account` without `foreign_key: true`). Wait — `create_agent_skills.rb` *does* use `foreign_key: true`. **Follow the existing migration's lead: use `foreign_key: true` on `account`/`chat` references** to match `create_agent_skills.rb`, but omit FK on the polymorphic `source` (polymorphic FKs are not supported). This matches the most recent migration in the repo.

---

## Advisory notes from the spec reviewer (incorporated)

1. **Does `Chat` already have `belongs_to :model`?** No. `app/models/chat.rb` has `belongs_to :account`, `belongs_to :chat, optional: true`, `belongs_to :user` — no `:model`. Both `Chat` and `Message` get the new `belongs_to :model, optional: true` declaration in Task 1. Both `chats.model_id` and `messages.model_id` bigint columns already exist (schema.rb:146, :231), so this is declaration-only, no migration.
2. **Embedding write path bypasses the Model catalog.** Embeddings use `ENV["EMBEDDING_MODEL"]` directly (the ruby_llm string id) and never go through the `models` catalog. So the "nil-model fallback" logic in the completion path does **not** apply to embeddings — the embedding `model_id` is always the env string, and `GreenIt` resolves it (almost always to the embedding fallback coefficient, since embedding models are not in Comparia). This is by design.
3. **`TokenUsage` validations:** `account_id` presence (enforced by `acts_as_tenant`), `kind` presence. `model_id` is **optional** (nil when a completion's `Model` row was refreshed away). `chat_id` optional (nil for indexing embeddings). `source` optional but always set in practice. See Task 3.

---

## File Structure Map

### New Files to Create
```
lib/green_it.rb                                      # GreenIt calculation module
config/model_energy.yml                              # Comparia dataset (generated from CSV)
config/green_it.yml                                  # Grid intensity + fallback coefficients
db/migrate/[ts]_create_token_usages.rb               # token_usages table
db/migrate/[ts]_add_token_counters_to_chats.rb       # chats counter columns
db/migrate/[ts]_add_token_counters_to_accounts.rb    # accounts counter columns
db/migrate/[ts]_backfill_token_usages.rb             # backfill from historical messages
app/views/messages/_token_footer.html.erb            # per-message footer partial
app/views/chats/_token_totals.html.erb               # per-chat totals partial
app/views/dashboards/_token_usage.html.erb           # account dashboard token section
test/models/token_usage_test.rb
test/lib/green_it_test.rb
test/models/chat/completionable_test.rb
test/models/chunk/vectorizable_test.rb
test/models/chunk/searchable_test.rb
test/models/chat_test.rb                             # add recount! test
test/models/account_test.rb                          # add recount! test
test/integration/token_footer_test.rb                # footer renders when done
lib/tasks/green_it.rake                              # recount! + import tasks
```

### Files to Modify
```
app/models/message.rb              # belongs_to :model, has_many :token_usages, energy helpers
app/models/chat.rb                 # belongs_to :model, has_many :token_usages, counters, recount!
app/models/account.rb              # has_many :token_usages, counters, recount!
app/models/token_usage.rb          # NEW (created in Task 3)
app/models/chat/completionable.rb  # record_completion_usage! after self.complete
app/models/chat/similarity_search.rb  # pass chat: self into the embedding scope
app/models/chunk/searchable.rb     # capture embed input_tokens, accept chat:, record usage
app/models/chunk/vectorizable.rb   # capture embed input_tokens, record usage
app/models/agent_skill/executor.rb # LLMExecutor: record agent_skill usage after .ask
app/views/messages/_assistant.html.erb   # render token footer
app/views/messages/_message.html.erb     # render token footer
app/views/chats/show.html.erb      # render token totals header + turbo stream
app/views/dashboards/show.html.erb # render token usage section
app/views/models/_model.html.erb   # consumption column
app/controllers/dashboards_controller.rb # token rollup queries
config/application.rb              # (no change — lib already autoloaded)
```

---

## Phase 1 — Prerequisite: resolve the ruby_llm model string

### Task 1: Add `belongs_to :model` to Message and Chat

**Goal:** Make the ruby_llm string `model_id` resolvable from a Message/Chat via `message.model.model_id`. Both bigint FK columns already exist; this is declaration-only.

**Files:**
- Modify: `app/models/message.rb`
- Modify: `app/models/chat.rb`

- [ ] **Step 1: Add to `Message`** (after `belongs_to :chat`, line 19)

```ruby
  belongs_to :model, optional: true
```

- [ ] **Step 2: Add to `Chat`** (after `belongs_to :user`, line 15)

```ruby
  belongs_to :model, optional: true
```

- [ ] **Step 3: Verify**

```bash
bin/rails runner 'p Message.reflect_on_association(:model)&.macro; p Chat.reflect_on_association(:model)&.macro'
# => :belongs_to :belongs_to
```

No new tests — the association is exercised by Task 5 (completion write path) and Task 8 (footer).

---

## Phase 2 — Green-IT calculation (lib + config)

### Task 2: Generate `config/model_energy.yml` from the Comparia CSV

**Goal:** Convert the committed CSV into a static lookup keyed by normalized model id → `mwh_per_1000_tokens`, with a `source` stamp. Skip `N/A` rows (api-only models have no measured consumption).

**Files:**
- Create: `config/model_energy.yml`
- Reference: `data/comparia_model-energy-02_07_2026-license_Etalab_2_0.csv`

CSV shape (header: `id,Bradley-Terry Score,Consumption mWh (1000 tokens),Size,Parameters (B),Architecture,Organisation,License`). Only the `id` and `Consumption mWh (1000 tokens)` columns are needed. `N/A` values are skipped.

- [ ] **Step 1: Generate the YAML with a one-off script**

```bash
bin/rails runner '
require "csv"
rows = CSV.read(Rails.root.join("data/comparia_model-energy-02_07_2026-license_Etalab_2_0.csv"), headers: true)
out = { "source" => "comparia 2026-07-02, license Etalab-2.0", "models" => {} }
rows.each do |r|
  conso = r["Consumption mWh (1000 tokens)"]
  next if conso.nil? || conso.to_s.strip == "N/A"
  out["models"][r["id"].to_s.downcase] = conso.to_f
end
File.write(Rails.root.join("config/model_energy.yml"), out.to_yaml)
puts "wrote #{out["models"].size} models"
'
```

Expected output: `wrote ~40 models` (the open-weights subset; glm-5.2 → 4095.0).

- [ ] **Step 2: Verify glm-5.2 is present**

```bash
grep "glm-5.2" config/model_energy.yml
#  glm-5.2: 4095.0
```

- [ ] **Step 3: Spot-check the header**

The file must start with:
```yaml
---
source: comparia 2026-07-02, license Etalab-2.0
models:
  glm-5.2: 4095.0
  ...
```

### Task 3: Create `config/green_it.yml`

**Goal:** Grid intensity + fallback coefficients, ENV-overridable.

**Files:**
- Create: `config/green_it.yml`

- [ ] **Step 1: Write the config**

```yaml
---
# World-average grid intensity (gCO2e per kWh). Override for a local grid.
# Source: IEA world average ~475 gCO2e/kWh.
grid_intensity_gco2e_per_kwh: 475

# Fallback for chat/completion models not in the Comparia dataset
# (api-only models, unknown ids). Conservative default.
fallback_kwh_per_token: 0.0000000900

# Embedding models are generally not in Comparia (chat-focused).
# Separate fallback for embedding input tokens.
embedding:
  kwh_per_input_token: 0.0000000100
```

### Task 4: Create the `GreenIt` lib module

**Goal:** `lib/green_it.rb` autoloads as `GreenIt` (matches the `lib/mcp_catalog.rb` autoload pattern). Provides `energy_kwh`, `co2e_g`, `grid_intensity_gco2e_per_kwh`, `fallback_kwh_per_token`, plus a `used_fallback?` helper for the UI asterisk.

**Files:**
- Create: `lib/green_it.rb`

- [ ] **Step 1: Write the module**

```ruby
# lib/green_it.rb
class GreenIt
  class << self
    # Total tokens × per-model kWh/token. tokens = input + output (the Comparia
    # figure is a blended per-token average, so it applies to total tokens).
    # Returns a hash so the UI can tell whether the fallback was used.
    def energy_kwh(tokens:, model_id:, kind: :completion)
      return 0.0 if tokens.nil? || tokens.zero?

      coeff = kwh_per_token(model_id:, kind:)
      { kwh: tokens * coeff, fallback: coeff == resolved_fallback(kind) && !dataset_lookup(model_id) }
    end

    def co2e_g(kwh:)
      return 0.0 if kwh.nil? || kwh.zero?

      kwh * grid_intensity_gco2e_per_kwh
    end

    def grid_intensity_gco2e_per_kwh
      ENV["GREENIT_GRID_INTENSITY_GCO2E_PER_KWH"]&.to_f || config.fetch("grid_intensity_gco2e_per_kwh", 475)
    end

    def fallback_kwh_per_token
      ENV["GREENIT_FALLBACK_KWH_PER_TOKEN"]&.to_f || config.fetch("fallback_kwh_per_token", 0.00000009)
    end

    def embedding_kwh_per_input_token
      ENV["GREENIT_EMBEDDING_KWH_PER_INPUT_TOKEN"]&.to_f || config.dig("embedding", "kwh_per_input_token") || 0.00000001
    end

    # The Comparia mWh-per-1000-tokens value for a model id, or nil if absent.
    def dataset_mwh_per_1000_tokens(model_id)
      return nil if model_id.blank?

      energy_models[model_id.to_s.downcase]
    end

    private

    def kwh_per_token(model_id:, kind:)
      if kind.to_s == "embedding"
        # Embedding models are not in Comparia; always use the embedding fallback.
        return embedding_kwh_per_input_token
      end

      mwh = dataset_mwh_per_1000_tokens(model_id)
      return fallback_kwh_per_token if mwh.nil?

      mwh * 1e-9 # mWh per 1000 tokens → kWh per token
    end

    def resolved_fallback(kind)
      kind.to_s == "embedding" ? embedding_kwh_per_input_token : fallback_kwh_per_token
    end

    def dataset_lookup(model_id)
      !dataset_mwh_per_1000_tokens(model_id).nil?
    end

    def energy_models
      @energy_models ||= load_energy_models
    end

    def load_energy_models
      path = Rails.root.join("config", "model_energy.yml")
      YAML.load_file(path).fetch("models", {})
    end

    def config
      @config ||= YAML.load_file(Rails.root.join("config", "green_it.yml"))
    end
  end
end
```

- [ ] **Step 2: Smoke-test**

```bash
bin/rails runner '
r = GreenIt.energy_kwh(tokens: 1560, model_id: "glm-5.2")
p r  # {:kwh=>0.0063882, :fallback=>false}  (1560 * 4095e-9)
p GreenIt.co2e_g(kwh: r[:kwh])  # ~3.03 (× 475)
p GreenIt.energy_kwh(tokens: 1560, model_id: "claude-4-6-sonnet")  # fallback: true
p GreenIt.energy_kwh(tokens: 1000, model_id: "text-embedding-3-small", kind: :embedding)
'
```

Expected: glm-5.2 kWh ≈ 0.0063882, co2e ≈ 3.03; claude fallback `true`; embedding uses embedding coefficient.

### Task 5: Test `GreenIt` (`test/lib/green_it_test.rb`)

**Goal:** Lock the conversion math, fallback path, ENV override, and retroactive-update property.

**Files:**
- Create: `test/lib/green_it_test.rb`

- [ ] **Step 1: Write the tests**

```ruby
require "test_helper"

class GreenItTest < ActiveSupport::TestCase
  test "energy_kwh converts mWh-per-1000-tokens to kWh for a known model" do
    # glm-5.2: 4095 mWh / 1000 tokens
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "glm-5.2")
    assert_in_delta 0.000004095, result[:kwh], 1e-12
    assert_not result[:fallback]
  end

  test "energy_kwh is case-insensitive on model_id" do
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "GLM-5.2")
    assert_in_delta 0.000004095, result[:kwh], 1e-12
  end

  test "energy_kwh uses fallback for an unknown chat model and flags it" do
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "claude-4-6-sonnet")
    assert_in_delta GreenIt.fallback_kwh_per_token, result[:kwh] / 1000, 1e-15
    assert result[:fallback]
  end

  test "energy_kwh uses the embedding coefficient for embeddings" do
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "text-embedding-3-small", kind: :embedding)
    assert_in_delta GreenIt.embedding_kwh_per_input_token, result[:kwh] / 1000, 1e-15
  end

  test "energy_kwh is zero for zero tokens" do
    result = GreenIt.energy_kwh(tokens: 0, model_id: "glm-5.2")
    assert_equal 0.0, result[:kwh]
  end

  test "co2e_g multiplies kWh by grid intensity" do
    assert_in_delta 475.0, GreenIt.co2e_g(kwh: 1.0), 1e-9
  end

  test "ENV grid intensity overrides config" do
    with_env("GREENIT_GRID_INTENSITY_GCO2E_PER_KWH" => "100") do
      assert_in_delta 100.0, GreenIt.grid_intensity_gco2e_per_kwh, 1e-9
    end
  end

  test "retroactive update: changing the dataset changes a historical figure" do
    # The whole point of computing live from raw tokens: a coefficient update
    # retroactively corrects history. Simulate a dataset update by swapping the
    # memoized model→mWh map (no mocking library available — plain Ruby).
    GreenIt.instance_variable_set(:@energy_models, { "glm-5.2" => 8000.0 })
    result = GreenIt.energy_kwh(tokens: 1000, model_id: "glm-5.2")
    assert_in_delta 0.008, result[:kwh], 1e-12
  ensure
    GreenIt.remove_instance_variable(:@energy_models)
  end

  private

  def with_env(vars)
    old = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    GreenIt.instance_variable_set(:@config, nil) # reset any cached config
  end
end
```

> Note on the stub: `GreenIt` memoizes `@energy_models`/`@config`. The retroactive test stubs the *method*, bypassing the cache, so no reset is needed for it. The `with_env` helper resets `@config` only.

- [ ] **Step 2: Run**

```bash
bin/rails test test/lib/green_it_test.rb
```

All green.

---

## Phase 3 — `TokenUsage` model + counters

### Task 6: Create the `token_usages` migration

**Goal:** Append-only event log. bigint IDs, `t.references` with FK on `account`/`chat` (matching `create_agent_skills.rb`), polymorphic `source` without FK.

**Files:**
- Create: `db/migrate/[ts]_create_token_usages.rb`

- [ ] **Step 1: Generate and edit**

```bash
bin/rails generate migration CreateTokenUsages
```

```ruby
# db/migrate/[ts]_create_token_usages.rb
class CreateTokenUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :token_usages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :chat, foreign_key: true            # optional (nil for indexing embeddings)
      t.references :source, polymorphic: true, index: false # polymorphic; no FK
      t.string :kind, null: false                      # completion | embedding | agent_skill
      t.string :model_id                               # ruby_llm string id; nil if Model row refreshed away
      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.integer :cached_tokens, default: 0
      t.integer :cache_creation_tokens, default: 0
      t.integer :thinking_tokens, default: 0
      t.timestamps
    end

    add_index :token_usages, %i[account_id created_at]
    add_index :token_usages, %i[source_type source_id]
    add_index :token_usages, %i[account_id kind]
    add_index :token_usages, %i[account_id model_id]
  end
end
```

> **No explicit `[:chat_id]` index** — `t.references :chat, foreign_key: true` already auto-creates `index_token_usages_on_chat_id`; adding it again raises `PG::DuplicateTable`. (Caught during migration.) Similarly `t.references :account` auto-indexes `account_id`; the composite `[:account_id, created_at]` / `[:account_id, kind]` / `[:account_id, model_id]` are distinct and fine. The polymorphic `t.references :source, polymorphic: true, index: false` is paired with the explicit `[:source_type, :source_id]` index.

- [ ] **Step 2: Run it**

```bash
bin/rails db:migrate
```

### Task 7: Create the `TokenUsage` model

**Goal:** `acts_as_tenant :account`, polymorphic `source`, enum `kind`, counter-increment `after_create`, and energy helpers delegating to `GreenIt`.

**Files:**
- Create: `app/models/token_usage.rb`

- [ ] **Step 1: Write the model**

```ruby
# app/models/token_usage.rb
class TokenUsage < ApplicationRecord
  acts_as_tenant :account

  belongs_to :chat, optional: true
  belongs_to :source, polymorphic: true, optional: true

  enum :kind, { completion: "completion", embedding: "embedding", agent_skill: "agent_skill" }

  validates :kind, presence: true

  after_create :increment_counters

  def total_tokens
    (input_tokens || 0) + (output_tokens || 0)
  end

  def energy
    @energy ||= GreenIt.energy_kwh(tokens: total_tokens, model_id:, kind:)
  end

  def energy_kwh
    energy[:kwh]
  end

  def co2e_g
    GreenIt.co2e_g(kwh: energy_kwh)
  end

  def used_fallback?
    energy[:fallback]
  end

  private

  def increment_counters
    if chat_id.present?
      Chat.update_counters(chat_id, input_tokens_count: input_tokens, output_tokens_count: output_tokens)
      chat.touch
    end
    Account.update_counters(account_id, input_tokens_count: input_tokens, output_tokens_count: output_tokens)
  end
end
```

> **`update_counters`, not `increment_counter`:** these are **SUM** caches (total tokens), not count-of-records caches. `increment_counter` adds +1 per call; `update_counters(id, col => delta)` generates `SET col = COALESCE(col, 0) + delta`, adding the actual token counts. Caught by the TokenUsage test suite.

> **Conventional exception note:** `after_create :increment_counters` is the acknowledged counter-cache exception to the "no side-effect callbacks" rule — pure aggregate maintenance, no business logic, no external calls. It is *not* a hidden business-logic callback.

> The counter columns (`input_tokens_count`/`output_tokens_count`) are added in Task 8. Run the model test only after Task 8's migration, or guard the increment with `column?` checks during the gap. The plan sequences Task 8 immediately after, so run them together.

### Task 8: Add counter columns to `chats` and `accounts`

**Goal:** Cached headline counters for instant dashboard/chat reads.

**Files:**
- Create: `db/migrate/[ts]_add_token_counters_to_chats.rb`
- Create: `db/migrate/[ts]_add_token_counters_to_accounts.rb`

- [ ] **Step 1: Chats migration**

```bash
bin/rails generate migration AddTokenCountersToChats
```

```ruby
# db/migrate/[ts]_add_token_counters_to_chats.rb
class AddTokenCountersToChats < ActiveRecord::Migration[8.0]
  def change
    add_column :chats, :input_tokens_count, :integer, default: 0, null: false
    add_column :chats, :output_tokens_count, :integer, default: 0, null: false
  end
end
```

- [ ] **Step 2: Accounts migration**

```bash
bin/rails generate migration AddTokenCountersToAccounts
```

```ruby
# db/migrate/[ts]_add_token_counters_to_accounts.rb
class AddTokenCountersToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :input_tokens_count, :integer, default: 0, null: false
    add_column :accounts, :output_tokens_count, :integer, default: 0, null: false
  end
end
```

- [ ] **Step 3: Migrate**

```bash
bin/rails db:migrate
```

### Task 9: Wire associations + `recount!` on Chat and Account

**Goal:** `has_many :token_usages`, cached-counter accessors (free from the columns), and a `recount!` drift-repair method.

**Files:**
- Modify: `app/models/chat.rb`
- Modify: `app/models/account.rb`

- [ ] **Step 1: Chat — add association + `recount!`**

In `app/models/chat.rb`, after `has_many :messages, dependent: :destroy` (line 17):

```ruby
  has_many :token_usages, dependent: :destroy

  # Recompute cached token counters from the token_usages event log (drift repair).
  # Rails 8's sum takes a single column, so two queries (small, indexed).
  def recount!
    update!(input_tokens_count: token_usages.sum(:input_tokens) || 0,
            output_tokens_count: token_usages.sum(:output_tokens) || 0)
  end

  # Per-kind token breakdown: { "completion" => [in, out], ... }
  # Two single-column grouped sums (Rails 8 sum takes one column), merged by kind.
  def token_totals_by_kind
    inputs = token_usages.group(:kind).sum(:input_tokens)
    outputs = token_usages.group(:kind).sum(:output_tokens)
    (inputs.keys | outputs.keys).index_with do |kind|
      [ inputs[kind] || 0, outputs[kind] || 0 ]
    end
  end
```

> **Rails 8 `sum` takes a single column.** The earlier multi-column `sum(:input_tokens, :output_tokens)` raises `ArgumentError: wrong number of arguments (given 2, expected 0..1)` in Rails 8.0.5 — `ActiveRecord::Calculations#sum` accepts one column. Use two single-column sums. Caught during migration execution.

- [ ] **Step 2: Account — add association + `recount!`**

In `app/models/account.rb`, after `has_many :agent_skills, dependent: :destroy` (line 20):

```ruby
  has_many :token_usages, dependent: :destroy

  # Recompute cached token counters from the token_usages event log (drift repair).
  # Rails 8's sum takes a single column, so two queries (small, indexed).
  def recount!
    update!(input_tokens_count: token_usages.sum(:input_tokens) || 0,
            output_tokens_count: token_usages.sum(:output_tokens) || 0)
  end
```

- [ ] **Step 3: Message — add `has_many :token_usages` as a source**

In `app/models/message.rb`, after `belongs_to :model, optional: true` (Task 1) / near `has_many :tool_calls`:

```ruby
  has_many :token_usages, as: :source, dependent: :destroy
```

### Task 10: Test `TokenUsage`, `Chat.recount!`, `Account.recount!`

**Goal:** Validations, enum, tenant scoping, counter increments, recount! repair.

**Files:**
- Create: `test/models/token_usage_test.rb`
- Modify: `test/models/chat_test.rb` (or create if absent)
- Modify: `test/models/account_test.rb` (or create if absent)

- [ ] **Step 1: `token_usage_test.rb`**

```ruby
require "test_helper"

class TokenUsageTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "tu@example.com", password: "testpassword123")
    @account = Account.create!(name: "TU Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user)
  end

  test "requires a kind" do
    usage = TokenUsage.new(account: @account, chat: @chat, input_tokens: 10, output_tokens: 5)
    assert_not usage.valid?
    assert_includes usage.errors[:kind], "can't be blank"
  end

  test "creates with completion kind and increments chat + account counters" do
    assert_difference -> { @chat.reload.input_tokens_count }, 100 do
      assert_difference -> { @chat.reload.output_tokens_count }, 50 do
        assert_difference -> { @account.reload.input_tokens_count }, 100 do
          TokenUsage.create!(account: @account, chat: @chat, kind: :completion,
                             input_tokens: 100, output_tokens: 50)
        end
      end
    end
  end

  test "embedding usage with nil chat_id does not touch chat counter but does touch account" do
    assert_no_difference -> { @chat.reload.input_tokens_count } do
      assert_difference -> { @account.reload.input_tokens_count }, 30 do
        TokenUsage.create!(account: @account, kind: :embedding, input_tokens: 30, output_tokens: 0)
      end
    end
  end

  test "acts_as_tenant scopes to current account" do
    other_account = Account.create!(name: "Other", owner: User.create!(email: "o@e.com", password: "testpassword123"))
    TokenUsage.create!(account: @account, kind: :completion, input_tokens: 1, output_tokens: 1)
    ActsAsTenant.current_tenant = other_account
    assert_equal 0, TokenUsage.count
    ActsAsTenant.current_tenant = @account
    assert_equal 1, TokenUsage.count
  end

  test "energy delegates to GreenIt with the stored model_id" do
    usage = TokenUsage.create!(account: @account, chat: @chat, kind: :completion,
                               model_id: "glm-5.2", input_tokens: 1000, output_tokens: 560)
    assert_in_delta 1560 * 4095e-9, usage.energy_kwh, 1e-12
    assert_not usage.used_fallback?
  end

  test "flags fallback when model_id is unknown" do
    usage = TokenUsage.create!(account: @account, chat: @chat, kind: :completion,
                               model_id: "claude-4-6-sonnet", input_tokens: 1000, output_tokens: 0)
    assert usage.used_fallback?
  end
end
```

- [ ] **Step 2: `recount!` test (add to `chat_test.rb` / `account_test.rb`)**

If `test/models/chat_test.rb` does not exist, create it with the same `setup` pattern.

```ruby
require "test_helper"

class ChatTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "ct@example.com", password: "testpassword123")
    @account = Account.create!(name: "CT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user)
  end

  test "recount! repairs drifted counters" do
    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, input_tokens: 100, output_tokens: 40)
    @chat.update!(input_tokens_count: 0, output_tokens_count: 0) # simulate drift
    @chat.recount!
    assert_equal 100, @chat.reload.input_tokens_count
    assert_equal 40, @chat.reload.output_tokens_count
  end
end
```

Mirror for `AccountTest`:

```ruby
require "test_helper"

class AccountTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "at@example.com", password: "testpassword123")
    @account = Account.create!(name: "AT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  test "recount! repairs drifted account counters" do
    TokenUsage.create!(account: @account, kind: :embedding, input_tokens: 70, output_tokens: 0)
    @account.update!(input_tokens_count: 0, output_tokens_count: 0)
    @account.recount!
    assert_equal 70, @account.reload.input_tokens_count
  end
end
```

- [ ] **Step 3: Run**

```bash
bin/rails test test/models/token_usage_test.rb test/models/chat_test.rb test/models/account_test.rb
```

---

## Phase 4 — Write paths

### Task 11: Completion write path — `Chat::Completionable`

**Goal:** After `self.complete` returns (RubyLLM has persisted the assistant message with token columns), create a `TokenUsage(kind: :completion, source: message)` for the just-completed assistant message, de-duped via the polymorphic source link (idempotent). O(1) — records the single message `complete_with_nosia` already holds, per spec §6.1.

**Files:**
- Modify: `app/models/chat.rb` (add `record_completion_usage!(message)`)
- Modify: `app/models/chat/completionable.rb` (call it with the completed message)

- [ ] **Step 1: Add `record_completion_usage!(message)` to `Chat`**

In `app/models/chat.rb`, after `recount!` / `token_totals_by_kind`:

```ruby
  # Record a TokenUsage for an assistant message produced by a completion,
  # de-duped via the polymorphic source link (idempotent: re-running a
  # completion for the same message does not create a duplicate). Called from
  # Chat::Completionable#complete_with_nosia with the just-completed message.
  def record_completion_usage!(message)
    return if message.nil? || message.input_tokens.nil?
    return if TokenUsage.where(source: message).exists?

    TokenUsage.create!(
      account_id:,
      chat_id: id,
      kind: :completion,
      source: message,
      model_id: message.model&.model_id,        # ruby_llm string; nil if Model refreshed away
      input_tokens: message.input_tokens || 0,
      output_tokens: message.output_tokens || 0,
      cached_tokens: message.cached_tokens || 0,
      cache_creation_tokens: message.cache_creation_tokens || 0,
      thinking_tokens: message.thinking_tokens || 0
    )
  end
```

- [ ] **Step 2: Call it from `complete_with_nosia`**

In `app/models/chat/completionable.rb`, after `message.update(similar_chunk_ids: chunks.pluck(:id))` (line 73), before `message` (the final return):

```ruby
    record_completion_usage!(message)
```

- [ ] **Step 3: Call it from `complete_with_agent_skills` fallback path**

`complete_with_agent_skills` (in `app/models/chat/agent_skillable.rb`) ends by calling `complete_with_nosia(question, **options)` when no skill results, so it is already covered. **No change needed** — the recording happens inside `complete_with_nosia`. (When a skill *does* handle it, the agent-skill write path in Task 13 records that usage.)

- [ ] **Step 4: Test the completion write path**

Create `test/models/chat/completionable_test.rb`. Since `self.complete` makes a real LLM call, test `record_completion_usage!` directly against a persisted assistant message (unit), and assert idempotence + the nil-model fallback.

```ruby
require "test_helper"

class Chat::CompletionableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "cc@example.com", password: "testpassword123")
    @account = Account.create!(name: "CC Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user)
  end

  test "record_completion_usage! creates a TokenUsage for an assistant message with tokens" do
    msg = @chat.messages.create!(role: :assistant, content: "hi",
                                 input_tokens: 120, output_tokens: 30, model: nil)
    assert_difference -> { TokenUsage.where(source: msg).count }, 1 do
      @chat.record_completion_usage!(msg)
    end
    usage = TokenUsage.find_by(source: msg)
    assert_equal "completion", usage.kind
    assert_equal 120, usage.input_tokens
    assert_equal 30, usage.output_tokens
    assert_equal @chat.id, usage.chat_id
  end

  test "record_completion_usage! stores the ruby_llm string model_id via message.model" do
    model = Model.create!(model_id: "glm-5.2", name: "GLM 5.2", provider: "openai")
    msg = @chat.messages.create!(role: :assistant, content: "hi",
                                 input_tokens: 10, output_tokens: 5, model: model)
    @chat.record_completion_usage!(msg)
    assert_equal "glm-5.2", TokenUsage.find_by(source: msg).model_id
  end

  test "record_completion_usage! is idempotent (no dupe on re-run)" do
    msg = @chat.messages.create!(role: :assistant, content: "hi",
                                 input_tokens: 10, output_tokens: 5)
    @chat.record_completion_usage!(msg)
    assert_no_difference -> { TokenUsage.count } do
      @chat.record_completion_usage!(msg)
    end
  end

  test "record_completion_usage! stores nil model_id gracefully when Model is absent" do
    msg = @chat.messages.create!(role: :assistant, content: "hi",
                                 input_tokens: 10, output_tokens: 5, model: nil)
    @chat.record_completion_usage!(msg)
    assert_nil TokenUsage.find_by(source: msg).model_id
  end

  test "record_completion_usage! skips messages without input_tokens" do
    msg = @chat.messages.create!(role: :assistant, content: "hi", input_tokens: nil)
    assert_no_difference -> { TokenUsage.count } do
      @chat.record_completion_usage!(msg)
    end
  end
end
```

- [ ] **Step 5: Run**

```bash
bin/rails test test/models/chat/completionable_test.rb
```

### Task 12: Embedding write paths — `Chunk::Vectorizable` + `Chunk::Searchable`

**Goal:** Capture `RubyLLM.embed`'s `input_tokens` instead of discarding it. Indexing → `chat_id` nil; query → `chat_id` set (passed in from `Chat::SimilaritySearch`).

**Files:**
- Modify: `app/models/chunk/vectorizable.rb`
- Modify: `app/models/chunk/searchable.rb`
- Modify: `app/models/chat/similarity_search.rb`

- [ ] **Step 1: `Chunk::Vectorizable` — capture and record (indexing, `chat_id` nil)**

Replace `generate_embedding` body in `app/models/chunk/vectorizable.rb`:

```ruby
  def generate_embedding
    return if content.blank?
    Rails.logger.info "Generating embedding for Chunk #{id}..."
    begin
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV["EMBEDDING_BASE_URL"] || ENV["AI_BASE_URL"]
        config.openai_api_key = ENV["AI_API_KEY"]
      end
      embedding_result = RubyLLM.embed(content, context:, model: ENV["EMBEDDING_MODEL"], dimensions: ENV["EMBEDDING_DIMENSIONS"].to_i, provider: :openai, assume_model_exists: true)
      self.embedding = embedding_result.vectors
      record_embedding_usage(embedding_result, chat: nil)
    rescue RubyLLM::Error => e
      Rails.logger.error "Error generating embedding for Chunk #{id}: #{e.message}"
      throw :abort
    end
  end
```

Add the recorder (private, after `generate_embedding!`):

```ruby
  private

  def record_embedding_usage(embedding_result, chat:)
    return unless embedding_result&.input_tokens&.positive?

    TokenUsage.create!(
      account_id: account_id,
      chat_id: chat&.id,
      kind: :embedding,
      source: self,
      model_id: ENV["EMBEDDING_MODEL"],
      input_tokens: embedding_result.input_tokens,
      output_tokens: 0
    )
  end
```

> **`account_id`:** Chunks belong to accounts (`account.chunks` in `Chat::SimilaritySearch`), so `account_id` is present on the chunk. Confirm `Chunk` has `account_id` (it must, for `acts_as_tenant`/multi-tenancy). If `Chunk` uses `acts_as_tenant :account`, `account_id` is the column.

- [ ] **Step 2: `Chunk::Searchable` — accept `chat:`, capture and record (query, `chat_id` set)**

Replace the scope in `app/models/chunk/searchable.rb`:

```ruby
  included do
    has_neighbors :embedding

    scope :search_by_similarity, ->(query_text, limit: ENV["RETRIEVAL_FETCH_K"].to_i || 5, chat: nil) {
      context = RubyLLM.context do |config|
        config.openai_api_base = ENV["EMBEDDING_BASE_URL"] || ENV["AI_BASE_URL"]
        config.openai_api_key = ENV["AI_API_KEY"]
      end
      embedding_result = RubyLLM.embed(query_text, context:, model: ENV["EMBEDDING_MODEL"], dimensions: ENV["EMBEDDING_DIMENSIONS"].to_i, provider: :openai, assume_model_exists: true)
      Chunk::Searchable.record_query_embedding_usage(embedding_result, chat:)
      nearest_neighbors(:embedding, embedding_result.vectors, distance: :cosine).limit(limit)
    }
  end

  # Records the query-embedding TokenUsage. The triggering Message is the
  # natural source, but the scope runs before the user message is persisted in
  # some flows; fall back to the chat as source when no message is available.
  def self.record_query_embedding_usage(embedding_result, chat:)
    return unless embedding_result&.input_tokens&.positive? && chat

    TokenUsage.create!(
      account_id: chat.account_id,
      chat_id: chat.id,
      kind: :embedding,
      source: chat,                      # chat as the source for query embeddings
      model_id: ENV["EMBEDDING_MODEL"],
      input_tokens: embedding_result.input_tokens,
      output_tokens: 0
    )
  end
```

> **Why `source: chat` for query embeddings:** the spec said `source` = the triggering `Message`, but the scope runs inside `similarity_search` which is called *before* the user message is reliably persisted/available in all flows. Using the chat as the source is robust and still gives the polymorphic origin link. This is a minor, justified deviation from the spec's source mapping; the `kind: :embedding` + `chat_id` carry the aggregation semantics either way.

- [ ] **Step 3: `Chat::SimilaritySearch` — pass `chat: self`**

In `app/models/chat/similarity_search.rb`:

```ruby
  def similarity_search(question)
    chunks = account.chunks.search_by_similarity(question, limit: retrieval_fetch_k, chat: self)
    augmented_context = ActiveModel::Type::Boolean.new.cast(ENV["AUGMENTED_CONTEXT"])
    chunks.select { |chunk| context_relevance(augmented_context ? chunk.augmented_context : chunk.context, question:) }
  end
```

- [ ] **Step 4: Tests (hermetic — no mocking library)**

The project has **no mocking library** (no Mocha; minitest/mock's `Object#stub` is not loaded). Do NOT stub `RubyLLM.embed`. Instead, test the recording logic directly with a fake result struct, avoiding the real embedding API call entirely:

- `Chunk::Searchable.record_query_embedding_usage` is a **class method** — call it directly with a fake result.
- `Chunk::Vectorizable#record_embedding_usage` is private — invoke via `chunk.send(:record_embedding_usage, fake, chat: nil)`. To get a persisted chunk without triggering the real `RubyLLM.embed` (the `before_save :generate_embedding` runs on content change), create the chunk with **blank content** (`generate_embedding` returns early when `content.blank?`), so it persists with an id and never calls the API.

Create `test/models/chunk/vectorizable_test.rb`:

```ruby
require "test_helper"

class Chunk::VectorizableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "cv@example.com", password: "testpassword123")
    @account = Account.create!(name: "CV Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    # Persist a chunk with blank content so before_save :generate_embedding is a no-op
    # (no real RubyLLM.embed call). Mirror the real Document/Chunk construction —
    # see test/models/chunk_test.rb or the Document model for required attributes.
    @chunk = @account.chunks.create!(content: "")  # adjust if Chunk requires a document
  end

  test "indexing embedding records a TokenUsage with chat_id nil" do
    fake = Struct.new(:vectors, :input_tokens, :model).new([0.1, 0.2], 8, "text-embedding-3-small")
    assert_difference -> { TokenUsage.where(source: @chunk).count }, 1 do
      @chunk.send(:record_embedding_usage, fake, chat: nil)
    end
    usage = TokenUsage.find_by(source: @chunk)
    assert_equal "embedding", usage.kind
    assert_nil usage.chat_id
    assert_equal 8, usage.input_tokens
    assert_equal ENV["EMBEDDING_MODEL"], usage.model_id
  end
end
```

> Adjust the `@account.chunks.create!(content: "")` setup to the real Chunk construction (it may require a `document:` — inspect `test/models/chunk_test.rb` or the Document/Chunk associations and mirror). The assertion shape stays the same.

Create `test/models/chunk/searchable_test.rb`:

```ruby
require "test_helper"

class Chunk::SearchableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "cs@example.com", password: "testpassword123")
    @account = Account.create!(name: "CS Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user)
  end

  test "query embedding records a TokenUsage with chat_id set and chat as source" do
    fake = Struct.new(:vectors, :input_tokens, :model).new([0.1, 0.2], 6, "text-embedding-3-small")
    assert_difference -> { TokenUsage.where(kind: "embedding", chat_id: @chat.id).count }, 1 do
      Chunk::Searchable.record_query_embedding_usage(fake, chat: @chat)
    end
    usage = TokenUsage.find_by(kind: "embedding", chat_id: @chat.id)
    assert_equal 6, usage.input_tokens
    assert_equal @chat, usage.source
  end

  test "query embedding recording is a no-op without a chat" do
    fake = Struct.new(:vectors, :input_tokens, :model).new([0.1, 0.2], 6, "text-embedding-3-small")
    assert_no_difference -> { TokenUsage.count } do
      Chunk::Searchable.record_query_embedding_usage(fake, chat: nil)
    end
  end
end
```

> These tests verify the recording wiring without the `RubyLLM.embed` call. The actual `embed` → `input_tokens` capture is verified in the gem source (`ruby_llm/embedding.rb` exposes `attr_reader :input_tokens`) and exercised by the manual smoke test (Task 20).

- [ ] **Step 5: Run**

```bash
bin/rails test test/models/chunk/vectorizable_test.rb test/models/chunk/searchable_test.rb
```

### Task 13: Agent-skill write path — `AgentSkill::Executor::LLMExecutor`

**Goal:** After `.ask` returns the assistant Message, record a `TokenUsage(kind: :agent_skill, source: agent_skill_execution, chat_id: execution.chat_id)`.

**Files:**
- Modify: `app/models/agent_skill/executor.rb`

- [ ] **Step 1: Record usage in `LLMExecutor#call`**

In `app/models/agent_skill/executor.rb`, `LLMExecutor#call` (lines 70-77), capture the returned message and record:

```ruby
    def call
      chat = @context[:chat]
      instructions = build_sanitized_instructions

      @execution.update!(input: { instructions: instructions.truncate(1000) })

      message = chat.with_instructions(instructions, replace: false).ask(@context[:query])
      record_agent_skill_usage(message)
      message
    end

    private

    def record_agent_skill_usage(message)
      return unless message&.input_tokens || message&.output_tokens

      TokenUsage.create!(
        account_id: @execution.account_id,
        chat_id: @execution.chat_id,
        kind: :agent_skill,
        source: @execution,
        model_id: message.model&.model_id,
        input_tokens: message.input_tokens || 0,
        output_tokens: message.output_tokens || 0,
        cached_tokens: message.cached_tokens || 0,
        cache_creation_tokens: message.cache_creation_tokens || 0,
        thinking_tokens: message.thinking_tokens || 0
      )
    end
```

> `@execution` is the `AgentSkillExecution` (set in `initialize`). It has `account_id` and `chat_id` (both `belongs_to`). `.ask` returns the assistant Message (acts_as_message). `message.model&.model_id` resolves the ruby_llm string.

- [ ] **Step 2: Test (hermetic — no mocking library)**

`AgentSkillExecution` is `acts_as_tenant :account`, `belongs_to :chat` (required), `belongs_to :agent_skill`, `belongs_to :message, optional: true`. The test must fake `chat.with_instructions` (returns chat for chaining) and `chat.ask` (returns the assistant message). With **no mocking library**, define singleton methods directly on the `@chat` instance (plain Ruby; overrides only that instance for the test's lifetime):

Create `test/models/agent_skill/executor_test.rb` (or add to existing `agent_skill_test.rb`):

```ruby
require "test_helper"

class AgentSkill::ExecutorTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "ae@example.com", password: "testpassword123")
    @account = Account.create!(name: "AE Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user)
    # Mirror the real AgentSkill required fields (see test/models/agent_skill_test.rb).
    @skill = @account.agent_skills.create!(name: "summarize", execution_mode: "llm",
                                           skill_content: "summarize", trigger_mode: "explicit",
                                           enabled: true, runnable: true)
  end

  test "LLM executor records an agent_skill TokenUsage from the returned message" do
    model = Model.create!(model_id: "glm-5.2", name: "GLM 5.2", provider: "openai")
    fake_message = @chat.messages.create!(role: :assistant, content: "ok",
                                          input_tokens: 200, output_tokens: 80, model: model)

    # Fake the chat's LLM interaction with plain-Ruby singleton methods (no mock lib).
    def @chat.with_instructions(*); self; end
    def @chat.ask(*); @fake_ask_result; end
    @chat.instance_variable_set(:@fake_ask_result, fake_message)

    context = { chat: @chat, user: @user, account: @account, query: "q",
                agent_skill: @skill, options: {} }

    assert_difference -> { TokenUsage.where(kind: "agent_skill").count }, 1 do
      AgentSkill::Executor.execute(@skill, context:)
    end

    usage = TokenUsage.find_by(kind: "agent_skill")
    assert_equal @chat.id, usage.chat_id
    assert_equal "glm-5.2", usage.model_id
    assert_equal 200, usage.input_tokens
    assert_equal 80, usage.output_tokens
    assert_kind_of AgentSkillExecution, usage.source
  end
end
```

> Adjust the `agent_skills.create!` attributes and `AgentSkill.runnable?` preconditions to the real model (inspect `AgentSkill` validations / existing `agent_skill_test.rb` and mirror). If `runnable?` requires more setup (e.g. an attached `skill_md`), add it. The assertion shape stays the same.

- [ ] **Step 3: Run**

```bash
bin/rails test test/models/agent_skill/executor_test.rb
```

---

## Phase 5 — Display surfaces

### Task 14: Per-message token footer

**Goal:** Compact `<footer>` after the reasoning dropdown, shown only when `message.done?` and tokens present. Reads token columns + `message.model&.model_id` → `GreenIt`. `*` when fallback used.

**Files:**
- Create: `app/views/messages/_token_footer.html.erb`
- Modify: `app/views/messages/_assistant.html.erb`
- Modify: `app/views/messages/_message.html.erb`

- [ ] **Step 1: Create the partial**

Guarded at the call site (Step 2) so the partial itself needs no `return`.

```erb
<%# app/views/messages/_token_footer.html.erb %>
<%
  total_in = message.input_tokens || 0
  total_out = message.output_tokens || 0
  total = total_in + total_out
  energy = GreenIt.energy_kwh(tokens: total, model_id: message.model&.model_id, kind: :completion)
  kwh = energy[:kwh]
  co2e = GreenIt.co2e_g(kwh: kwh)
  fallback = energy[:fallback]
  asterisk = fallback ? "*" : ""
%>
<footer class="mt-3 pt-3 border-t border-neutral-100 dark:border-neutral-700 text-[11px] text-neutral-500 dark:text-neutral-400 flex items-center gap-2 flex-wrap">
  <span title="Input / output tokens">↑ <%= number_with_delimiter(total_in) %> ↓ <%= number_with_delimiter(total_out) %></span>
  <span aria-hidden="true">·</span>
  <span title="Energy estimate (kWh)"><%= number_with_precision(kwh, precision: 6) %> kWh</span>
  <span aria-hidden="true">·</span>
  <span title="<%= fallback ? 'estimation — modèle absent du benchmark Comparia' : 'CO2e estimate' %>"><%= number_with_precision(co2e, precision: 2) %> gCO2e<%= asterisk %></span>
</footer>
```

- [ ] **Step 2: Render it in `_assistant.html.erb`**

After the Reasoning dropdown block (after line 89, before the closing `</div>` of the message bubble at line 90):

```erb
          <% if message.done? && (message.input_tokens || message.output_tokens) %>
            <%= render "messages/token_footer", message: message %>
          <% end %>
```

- [ ] **Step 3: Render it in `_message.html.erb`** (same insertion, after the Reasoning block ~line 98, before `</div>` at line 99)

```erb
          <% if message.done? && (message.input_tokens || message.output_tokens) %>
            <%= render "messages/token_footer", message: message %>
          <% end %>
```

- [ ] **Step 4: Integration test — footer renders when done**

Create `test/integration/token_footer_test.rb`:

```ruby
require "test_helper"

class TokenFooterTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "tf@example.com", password: "testpassword123")
    @account = Account.create!(name: "TF Account", owner: @user)
    @chat = @account.chats.create!(user: @user)
    ActsAsTenant.current_tenant = @account
  end

  test "footer renders token counts and gCO2e for a done assistant message" do
    model = Model.create!(model_id: "glm-5.2", name: "GLM 5.2", provider: "openai")
    @chat.messages.create!(role: :assistant, content: "answer", done: true,
                           input_tokens: 1240, output_tokens: 320, model: model)
    # Render the partial directly to assert content without a full chat show request.
    html = ApplicationController.render("messages/_token_footer", assigns: { message: @chat.messages.last })
    assert_includes html, "1,240"
    assert_includes html, "320"
    assert_includes html, "gCO2e"
  end

  test "footer shows the fallback asterisk for an unknown model" do
    @chat.messages.create!(role: :assistant, content: "answer", done: true,
                           input_tokens: 1000, output_tokens: 0, model: nil)
    html = ApplicationController.render("messages/_token_footer", assigns: { message: @chat.messages.last })
    assert_includes html, "gCO2e*"
    assert_includes html, "absent du benchmark Comparia"
  end
end
```

- [ ] **Step 5: Run**

```bash
bin/rails test test/integration/token_footer_test.rb
```

### Task 15: Per-chat totals header + live Turbo refresh

**Goal:** Summary header on the chat page: headline from cached counters, per-kind breakdown via one live `GROUP BY`, derived kWh/CO2e. A Turbo Stream refreshes it when a new `TokenUsage` is created.

**Files:**
- Create: `app/views/chats/_token_totals.html.erb`
- Modify: `app/views/chats/show.html.erb`
- Modify: `app/models/token_usage.rb` (broadcast on create)

- [ ] **Step 1: Broadcast on `TokenUsage` create (guarded)**

Add to `app/models/token_usage.rb` (after `after_create :increment_counters`):

```ruby
  include ActionView::RecordIdentifier   # for dom_id (at top of the model)

  after_create_commit :broadcast_token_totals, if: :chat

  private

  def broadcast_token_totals
    broadcast_replace_to [ chat, :token_totals ],
      target: dom_id(chat, :token_totals),
      partial: "chats/token_totals",
      locals: { chat: chat }
  end
```

> **Do NOT add a class-level `broadcasts_to` declaration.** `broadcasts_to` fires automatically on *every* create, including indexing embeddings where `chat` is nil — the lambda would target `[nil, :token_totals]`, an invalid stream, and it would double-broadcast on chat usages. The explicit, `if: :chat`-guarded callback is the only broadcast needed: it fires only for chat-scoped usages (completions, query embeddings, agent skills) and refreshes the chat totals header live as the assistant finishes. Indexing embeddings (chat nil) have no chat header to refresh.

- [ ] **Step 2: Create the totals partial**

```erb
<%# app/views/chats/_token_totals.html.erb %>
<%= tag.div id: dom_id(chat, :token_totals) do %>
  <%
    totals = chat.token_totals_by_kind # { "completion" => [in, out], ... }
    total_in = chat.input_tokens_count
    total_out = chat.output_tokens_count
    total = total_in + total_out
    energy = GreenIt.energy_kwh(tokens: total, model_id: nil, kind: :completion) # blended across models
  %>
  <div class="text-[11px] text-neutral-500 dark:text-neutral-400 flex items-center gap-2 flex-wrap">
    <span><b>Tokens</b> ↑ <%= number_with_delimiter(total_in) %> ↓ <%= number_with_delimiter(total_out) %></span>
    <span aria-hidden="true">·</span>
    <% totals.each do |kind, sums| %>
      <span class="capitalize"><%= kind %>: ↑ <%= number_with_delimiter(sums[0]) %> ↓ <%= number_with_delimiter(sums[1]) %></span>
    <% end %>
  </div>
<% end %>
```

> **Note on the blended header energy:** a single per-chat kWh cannot be accurate per-model because totals are aggregated across models. Two options: (a) compute kWh per-row by iterating `chat.token_usages` (N small, fine for a chat), or (b) show only token totals in the header and kWh per-message in the footer. The plan uses **(a)** — iterate `token_usages` for the chat to sum real per-model kWh — which is the faithful approach. Replace the `energy` line with:

```erb
  <%
    per_row_kwh = chat.token_usages.sum { |u| u.energy_kwh }
    per_row_co2e = chat.token_usages.sum { |u| u.co2e_g }
  %>
  <span aria-hidden="true">·</span>
  <span title="Total energy (kWh)"><%= number_with_precision(per_row_kwh, precision: 6) %> kWh</span>
  <span aria-hidden="true">·</span>
  <span title="Total CO2e"><%= number_with_precision(per_row_co2e, precision: 2) %> gCO2e</span>
```

(Loading `chat.token_usages` for a single chat is bounded and acceptable; the cached counters remain the instant headline for the token numbers.)

- [ ] **Step 3: Render + stream in `show.html.erb`**

In `app/views/chats/show.html.erb`, inside the messages `tag.div` (after `dom_id(@chat, :messages)` opens, before the messages loop at line 5):

```erb
        <%= render "chats/token_totals", chat: @chat %>
```

And add the stream subscription (near `turbo_stream_from @chat, :messages` at line 16):

```erb
      <%= turbo_stream_from @chat, :token_totals %>
```

- [ ] **Step 4: Test**

Add to `test/integration/token_footer_test.rb` or a new `test/integration/chat_token_totals_test.rb`:

```ruby
  test "chat totals partial shows cached counters and per-kind breakdown" do
    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, input_tokens: 100, output_tokens: 40)
    TokenUsage.create!(account: @account, chat: @chat, kind: :embedding, input_tokens: 12, output_tokens: 0)
    html = ApplicationController.render("chats/_token_totals", assigns: { chat: @chat.reload })
    assert_includes html, "112"  # total_in
    assert_includes html, "40"
    assert_includes html, "completion"
    assert_includes html, "embedding"
    assert_includes html, "kWh"
  end
```

- [ ] **Step 5: Run**

```bash
bin/rails test test/integration/chat_token_totals_test.rb
```

### Task 16: Account dashboard rollups

**Goal:** Headline cached totals + per-model (top 5) and per-kind breakdown tables + a 30-day per-day sparkline (inline SVG, no chart library). Russian-doll cached on `account.touch` (already triggered by the counter increment).

**Files:**
- Modify: `app/controllers/dashboards_controller.rb`
- Create: `app/views/dashboards/_token_usage.html.erb`
- Modify: `app/views/dashboards/show.html.erb`

- [ ] **Step 1: Rollup queries in the controller**

```ruby
# app/controllers/dashboards_controller.rb
class DashboardsController < ApplicationController
  def show
    @chat = Current.user.chats.new
    @token_totals = {
      input: Current.account.input_tokens_count,
      output: Current.account.output_tokens_count
    }
    @tokens_by_model = Current.account.token_usages
                              .where.not(model_id: nil)
                              .group(:model_id)
                              .sum("(input_tokens + output_tokens)")
                              .sort_by { |_, v| -v }.first(5)
    @tokens_by_kind = Current.account.token_usages.group(:kind).sum("(input_tokens + output_tokens)")
    @tokens_by_day = Current.account.token_usages
                            .where("created_at > ?", 30.days.ago)
                            .group("DATE(created_at)")
                            .sum("(input_tokens + output_tokens)")
  end
end
```

- [ ] **Step 2: Create the section partial**

```erb
<%# app/views/dashboards/_token_usage.html.erb %>
<% cache [ Current.account, "dashboard-token-usage" ] do %>
  <section class="w-full max-w-4xl mx-auto mt-8">
    <h3 class="text-sm font-semibold text-neutral-700 dark:text-neutral-300 mb-3">Token usage & environmental impact</h3>

    <div class="rounded-2xl bg-white dark:bg-neutral-800 shadow-sm border n-main-border p-4 space-y-4 text-sm">
      <% total = token_totals[:input] + token_totals[:output] %>
      <div class="text-neutral-600 dark:text-neutral-400">
        <b>Total</b> ↑ <%= number_with_delimiter(token_totals[:input]) %> ↓ <%= number_with_delimiter(token_totals[:output]) %> tokens
        (<%= number_with_delimiter(total) %> total)
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <p class="text-xs font-medium text-neutral-500 mb-1">Per model (top 5)</p>
          <ul class="text-xs space-y-1">
            <% tokens_by_model.each do |model_id, t| %>
              <% e = GreenIt.energy_kwh(tokens: t, model_id: model_id, kind: :completion) %>
              <li class="flex justify-between">
                <span><%= model_id %></span>
                <span><%= number_with_delimiter(t) %> tok · <%= number_with_precision(e[:kwh], precision: 6) %> kWh<%= e[:fallback] ? "*" : "" %></span>
              </li>
            <% end %>
            <% if tokens_by_model.empty? %>
              <li class="text-neutral-400">No usage yet.</li>
            <% end %>
          </ul>
        </div>

        <div>
          <p class="text-xs font-medium text-neutral-500 mb-1">Per kind</p>
          <ul class="text-xs space-y-1">
            <% tokens_by_kind.each do |kind, t| %>
              <li class="flex justify-between">
                <span class="capitalize"><%= kind %></span>
                <span><%= number_with_delimiter(t) %> tok</span>
              </li>
            <% end %>
          </ul>
        </div>
      </div>

      <%# 30-day sparkline, inline SVG, no chart library %>
      <% if tokens_by_day.any? %>
        <%
          days = (0..29).map { |i| (30.days.ago.to_date + i) }
          max = tokens_by_day.values.max.to_f
          max = 1 if max.zero?
          pts = days.map.with_index { |d, i|
            v = tokens_by.fetch(d.to_s, 0)
            x = i * (300 / 29.0)
            y = 30 - (v / max) * 30
            "#{x.round(1)},#{y.round(1)}"
          }
        %>
        <div>
          <p class="text-xs font-medium text-neutral-500 mb-1">Last 30 days</p>
          <svg viewBox="0 0 300 30" class="w-full h-10">
            <polyline fill="none" stroke="currentColor" stroke-width="1.5" class="text-neutral-400" points="<%= pts.join(' ') %>" />
          </svg>
        </div>
      <% end %>
    </div>
  </section>
<% end %>
```

- [ ] **Step 3: Render it in `dashboards/show.html.erb`**

Insert after the dropzone `<section>` closes (after line 32, before the chat form section at line 33):

```erb
  <%= render "dashboards/token_usage", token_totals: @token_totals, tokens_by_model: @tokens_by_model, tokens_by_kind: @tokens_by_kind, tokens_by_day: @tokens_by_day %>
```

- [ ] **Step 4: Test (controller + view)**

```ruby
require "test_helper"

class DashboardsTokenUsageTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "dt@example.com", password: "testpassword123")
    @account = Account.create!(name: "DT Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    TokenUsage.create!(account: @account, kind: :completion, model_id: "glm-5.2",
                       input_tokens: 500, output_tokens: 100)
    TokenUsage.create!(account: @account, kind: :embedding, input_tokens: 20, output_tokens: 0)
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  test "dashboard shows headline totals and per-kind breakdown" do
    get dashboard_path
    assert_response :success
    assert_select "h3", text: /Token usage/
    assert_select "li", text: /glm-5.2/
    assert_select "li.capitalize", text: /embedding/
  end
end
```

> The auth pattern (`@account.account_users.grant_to(@user)` + `post login_url`) is the real one used in `test/controllers/system_prompts_controller_test.rb`. The dashboard route must be accessed through the account-scoped URL if the app is multi-tenant path-based — if `dashboard_path` is account-scoped, use the account-scoped helper (e.g. `account_dashboard_url(@account)`); mirror an existing dashboard controller test's path helper.

- [ ] **Step 5: Run**

```bash
bin/rails test test/integration/dashboards_token_usage_test.rb
```

### Task 17: Model catalog consumption column

**Goal:** Add a "Conso. moyenne (1000 tokens)" column to the model catalog, from the Comparia lookup, "—" when unmatched.

**Files:**
- Modify: `app/views/models/_model.html.erb`
- Modify: `app/views/models/index.html.erb` (add the `<th>`)

- [ ] **Step 1: Add the column cell**

In `app/views/models/_model.html.erb`, add before the Show link `<td>`:

```erb
  <td>
    <% mwh = GreenIt.dataset_mwh_per_1000_tokens(model.model_id) %>
    <%= mwh ? number_with_delimiter(mwh.to_i) : "—" %>
  </td>
```

- [ ] **Step 2: Add the table header**

In `app/views/models/index.html.erb`, add the `<th>` (between the pricing column header and the Show header):

```erb
  <th>Conso. moyenne (1000 tokens)</th>
```

> Locate the exact `<th>` row in `index.html.erb` and insert there to keep columns aligned with Task 17 Step 1's cell position.

- [ ] **Step 3: Test**

```ruby
require "test_helper"

class ModelsConsumptionColumnTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "mc@example.com", password: "testpassword123")
    @account = Account.create!(name: "MC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    Model.create!(model_id: "glm-5.2", name: "GLM 5.2", provider: "openai")
    Model.create!(model_id: "claude-4-6-sonnet", name: "Claude", provider: "anthropic")
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  test "index shows Comparia consumption for matched models and — for unmatched" do
    get models_path
    assert_response :success
    assert_select "td", text: "4,095"       # glm-5.2 mWh/1000tok
    assert_select "td", text: "—"
  end
end
```

> Same real auth pattern as `test/controllers/system_prompts_controller_test.rb`. If `models_path` is account-scoped, use the account-scoped helper.

- [ ] **Step 4: Run**

```bash
bin/rails test test/integration/models_consumption_column_test.rb
```

---

## Phase 6 — Backfill + rake tasks

### Task 18: Backfill migration (historical completion tokens)

**Goal:** Create a `TokenUsage(kind: :completion, source: message)` for every historical assistant message with `input_tokens` present, then `recount!` chats and accounts. Embedding/agent-skill history is unrecoverable (non-goal).

**Files:**
- Create: `db/migrate/[ts]_backfill_token_usages.rb`

- [ ] **Step 1: Write the data migration**

```ruby
# db/migrate/[ts]_backfill_token_usages.rb
class BackfillTokenUsages < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Only assistant messages with token data and no existing usage.
    Message.where(role: 10).where.not(input_tokens: nil).find_each do |message|
      next if TokenUsage.where(source_type: "Message", source_id: message.id).exists?

      TokenUsage.create!(
        account_id: message.chat.account_id,
        chat_id: message.chat_id,
        kind: :completion,
        source: message,
        model_id: message.model&.model_id,
        input_tokens: message.input_tokens || 0,
        output_tokens: message.output_tokens || 0,
        cached_tokens: message.cached_tokens || 0,
        cache_creation_tokens: message.cache_creation_tokens || 0,
        thinking_tokens: message.thinking_tokens || 0
      )
    end

    # Repair counters from the now-complete event log.
    Chat.find_each(&:recount!)
    Account.find_each(&:recount!)
  end

  def down
    TokenUsage.where(kind: "completion", source_type: "Message").delete_all
    Chat.find_each(&:recount!)
    Account.find_each(&:recount!)
  end
end
```

> `Message.where(role: 10)` — the role enum is `system: 0, assistant: 10, user: 20, tool: 30` (integer column). `acts_as_tenant` is **not** active inside migrations, so `account_id` is read directly via `message.chat.account_id`.

- [ ] **Step 2: Run**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Verify counts**

```bash
bin/rails runner '
p TokenUsage.group(:kind).count
p Chat.sum(:input_tokens_count)
p TokenUsage.sum(:input_tokens)
'
```

The chat sum and the `token_usages` sum should match (recount! just ran).

### Task 19: Recount rake task + recurring job

**Goal:** Admin task / recurring Solid Queue job for drift repair.

**Files:**
- Create: `lib/tasks/green_it.rake`

- [ ] **Step 1: Write the task**

```ruby
# lib/tasks/green_it.rake
namespace :green_it do
  desc "Recompute cached token counters on chats and accounts from token_usages (drift repair)"
  task recount: :environment do
    Chat.find_each(&:recount!)
    Account.find_each(&:recount!)
    puts "Recounted token counters."
  end

  desc "Regenerate config/model_energy.yml from the Comparia CSV"
  task import_energy: :environment do
    require "csv"
    rows = CSV.read(Rails.root.join("data/comparia_model-energy-02_07_2026-license_Etalab_2_0.csv"), headers: true)
    out = { "source" => "comparia 2026-07-02, license Etalab-2.0", "models" => {} }
    rows.each do |r|
      conso = r["Consumption mWh (1000 tokens)"]
      next if conso.nil? || conso.to_s.strip == "N/A"
      out["models"][r["id"].to_s.downcase] = conso.to_f
    end
    File.write(Rails.root.join("config", "model_energy.yml"), out.to_yaml)
    puts "Wrote #{out["models"].size} models to config/model_energy.yml"
  end
end
```

- [ ] **Step 2: Recurring Solid Queue job**

`config/recurring.yml` exists in the repo (currently all commented out). Add a concrete recurring job for drift repair.

Create `app/jobs/green_it/recount_job.rb`:

```ruby
class GreenIt::RecountJob < ApplicationJob
  def perform
    Chat.find_each(&:recount!)
    Account.find_each(&:recount!)
  end
end
```

Append to `config/recurring.yml`:

```yaml
production:
  green_it_recount:
    class: GreenIt::RecountJob
    schedule: every hour at minute 7
```

> Off-minute schedule (per the cron guidance) avoids the herd on `:00`. Only the `production` environment is configured; add `development` if desired locally.

- [ ] **Step 3: Verify**

```bash
bin/rails green_it:recount
```

---

## Phase 7 — Final verification

### Task 20: Full suite + lint + security

- [ ] **Step 1: Full test suite**

```bash
bin/rails test
bin/rails test:system
```

- [ ] **Step 2: Lint + security**

```bash
bundle exec rubocop -a
bundle exec brakeman --no-pager
```

Fix any offenses. Re-run `bin/ci` for the full pipeline.

- [ ] **Step 3: Manual smoke test**

```bash
bin/dev
```

- Ask a question; confirm the per-message footer appears when the assistant finishes (`↑ … ↓ … · … kWh · … gCO2e`).
- Confirm the chat totals header ticks up live (Turbo Stream).
- Visit the dashboard; confirm headline + per-model + per-kind + sparkline render.
- Visit the model catalog; confirm the "Conso. moyenne (1000 tokens)" column shows `4,095` for glm-5.2 and `—` for api-only models.

- [ ] **Step 4: Cross-account isolation check**

In a console, create two accounts, create a `TokenUsage` in one, switch `ActsAsTenant.current_tenant`, confirm the other sees zero. (Covered by `token_usage_test.rb` Task 10, but re-confirm manually.)

---

## Reviewer fixes applied (round 1)

The plan-document reviewer flagged 3 BLOCKERs and 7 NITs; all are incorporated:

- **BLOCKER 1 (executor test):** removed Mocha `any_instance.stubs`/`stubs` (the project has **no mocking library** — neither Mocha nor minitest/mock's `Object#stub` is loaded). Replaced with plain-Ruby singleton method definitions on the test `@chat` instance. The embedding tests (Task 12) were likewise rewritten to test the recording methods directly with a fake struct instead of stubbing `RubyLLM.embed`.
- **BLOCKER 2 (TokenUsage broadcast):** dropped the class-level `broadcasts_to` (it fires on every create, including chat-nil indexing embeddings → invalid `[nil, :token_totals]` stream, and double-broadcasts). Kept only the `if: :chat`-guarded `after_create_commit` callback.
- **BLOCKER 3 (multi-column sum):** ~~`group(:kind).sum(:input_tokens, :output_tokens)` returns a hash-of-hashes~~ — **this round-1 assumption was WRONG.** Rails 8.0.5's `ActiveRecord::Calculations#sum` accepts **one** column; `sum(:a, :b)` raises `ArgumentError`. Discovered during execution. The real fix: `recount!` and `token_totals_by_kind` use **two single-column sums** (see Task 9).
- **NIT 4:** embedding tests use a saved-with-blank-content chunk (so `before_save :generate_embedding` is a no-op) + direct recording-method invocation — fully hermetic, no API key needed.
- **NIT 5:** integration tests (Tasks 16, 17) pinned to the real auth pattern from `test/controllers/system_prompts_controller_test.rb`: `@account.account_users.grant_to(@user)` + `post login_url, params: { email:, password: }`. No fabricated `sign_in_as`.
- **NIT 6:** `record_completion_usage!(message)` records the single just-completed message (O(1)) instead of re-scanning all assistant messages — faithful to spec §6.1, still idempotent via the source-link de-dupe.
- **NIT 7:** `recount!` uses one multi-column `sum` query, indexed by string key.
- **NIT 8:** `config/recurring.yml` exists → Task 19 Step 2 is a concrete `GreenIt::RecountJob` + recurring entry (off-minute `:07`), not conditional.
- **NIT 9:** FK on `account`/`chat` references (matching `create_agent_skills.rb`) vs. the `migrations.md` "no FK" rule — intentional, documented deviation.
- **NIT 10:** removed the dead draft partial with `return`; the final partial is guard-at-call-site only.

### Additional issues found during execution (not catchable by doc review)

- **`update_counters` vs `increment_counter` (SUM cache):** the cached counters track total tokens, not record counts. `increment_counter` adds +1; `update_counters(id, col => delta)` adds the token delta. Fixed in Task 7. Caught by the TokenUsage test suite.
- **Rails 8 single-column `sum`:** see BLOCKER 3 correction above.
- **Migration duplicate index:** `t.references :chat` auto-creates the chat_id index; an explicit `add_index [:chat_id]` raises `PG::DuplicateTable`. Fixed in Task 6.
- **`acts_as_chat` chat creation in tests:** `@account.chats.create!(user: @user)` triggers a RubyLLM model lookup on the default model and raises `RubyLLM::ModelNotFoundError` in test env. Tests must create chats as the controller does: `chats.create!(user:, model: "test-model", provider: :openai, assume_model_exists: true)`. Applied to Tasks 10, 11, 13 test setups.
- **Broadcasts run inline in tests:** with `queue_adapter = :solid_queue`, Turbo `broadcast_replace_to` still renders the partial inline during test create, so `chats/_token_totals` must exist before any chat-scoped `TokenUsage` is created in a test. The partial (Task 15) was created early to unblock the model tests.
- **Backfill uses `insert_all` + idempotency filter** (not `create!`): bypasses the counter/broadcast callbacks (appropriate for a one-time data migration; avoids rendering a not-yet-existing partial) and skips already-backfilled messages on re-run. `recount!` sets the counters absolutely afterward.

---

## Open questions for the implementer (resolve during implementation)

1. **Chunk construction in tests:** mirror the real `Document`/`Chunk` creation path (inspect `test/models/chunk_test.rb` or the Document model) for Task 12's `@account.chunks.create!(content: "")` setup — a Chunk may require a `document:`. The assertion shape does not change.
2. **AgentSkill required fields / `runnable?` in tests:** mirror the real `AgentSkill` validations and `runnable?` preconditions (inspect `test/models/agent_skill_test.rb`) for Task 13's setup — `runnable?` may require an attached `skill_md`. The assertion shape does not change.
3. **Account-scoped route helpers:** if `dashboard_path`/`models_path` are account-scoped (`/:account_id/...`), use the account-scoped URL helpers in the Tasks 16 & 17 integration tests; mirror an existing dashboard/models controller test's path helper.
4. **No mocking library:** confirmed — do not introduce Mocha or rely on `Object#stub`. All test faking uses plain-Ruby singleton methods or direct private-method invocation (`send`) with fake structs.

---

## Notes for the implementer

- **37signals style:** keep controllers thin (the dashboard controller only assembles queries; no business logic). Keep business logic in models (`recount!`, `record_completion_usage!`, `record_embedding_usage`). The `GreenIt` lib is the justified lib-module exception (pure calculation, no persistence — like the existing `McpCatalog` / `Prompts` libs).
- **No service objects:** none are introduced. `GreenIt` is a `lib/` module, not an `app/services/` object — consistent with `lib/mcp_catalog.rb`.
- **Counter-cache callback is the documented exception** to "no side-effect callbacks" — pure aggregate maintenance.
- **Bigint, not UUID:** follow the actual codebase (`create_agent_skills.rb`), not the spec's UUIDv7 mention.
- **Tests build records in `setup` with `ActsAsTenant.current_tenant`**, no fixtures.
- **Only raw tokens are stored.** Never persist kWh/CO2e — they are always computed live so coefficient updates retroactively correct history.