# Inference Provider Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure inference entirely through Nosia, with guided onboarding, encrypted provider connections, persistent chat-model choices, resource-aware Ollama provisioning, and safe embedding replacements.

**Architecture:** Keep RubyLLM's model registry as catalog metadata and add connection-qualified model bindings with isolated contexts. Immutable knowledge generations own dimension-validated chunks; source revisions and a short activation lock keep background replacements consistent. Rails models own behavior, REST resources expose administration, and shallow Solid Queue jobs perform resumable work.

**Tech Stack:** Actual repository Ruby 4, Rails 8.0, RubyLLM 2.0.0, PostgreSQL/pgvector, Hotwire, Tailwind, importmap, Solid Queue, Minitest/fixtures, Selenium. No dependency upgrade, Node, new vector database, or service/policy framework.

---

## Authority, scope, and execution boundary

Read `docs/superpowers/specs/2026-10-23-inference-provider-management-design.md`, initially committed as `3c3b14a`. The user approved the written specification with “Go”; that authorizes this plan, not automatic application implementation. Ask for the execution approach after saving/reviewing this plan.

This is one coupled feature with three sequential checkpoints:

1. **Foundation:** persistence, encrypted connections, transport policy, connection-qualified models, provisioning, and compatibility import preparation.
2. **Knowledge safety:** versioned storage, independently addressable embedders, revision-aware replacement, pinned reads, cleanup, and executable import.
3. **Product cutover:** saved chat/API routing, onboarding and administration, deployment cleanup, documentation, and full verification.

Do not release an embedding-change form before checkpoint 2. Do not remove old deployment inputs before the import is executable. Intermediate commits are testable checkpoints on the feature branch, not promises that each is independently deployable.

Planning takes place in the current checkout without touching application files. Execution must use an isolated worktree, preserving unrelated work in the original checkout. In particular, `Procfile.dev`, untracked historical planning files, and `test/packaging/embedding_dimensions.rb` are not this feature's changes. Recheck status because other work may progress concurrently. Never stage broad paths or discard unknown changes.

## Repository-specific constraints

- Existing account/source/chat/RubyLLM IDs are bigint; do not convert them. New inference/knowledge metadata IDs use base36 UUIDv7 strings of length 25. Account-owned references to existing accounts/users retain bigint types. Installation-global configuration intentionally has no account owner; account-owned sources/revisions/chunks keep explicit account scoping.
- Preserve existing foreign keys. For the new metadata migrations below, follow the repository migration rule: references are indexed without introducing database foreign-key constraints; enforce model associations and retirement/deletion checks explicitly.
- `Current.account` is derived from the signed-in user's first account and cannot be assigned. Use explicit source/chat accounts and `ActsAsTenant.with_tenant(account)` for background work; never invent `Current.account=`.
- Existing `test/test_helper.rb` loads global fixtures, and tests depend on an initially empty database. Follow `test/support/chat_account_fixtures.rb` with opt-in fixtures under `test/support/fixtures/inference/`; do not add global fixtures.
- Minitest 6 may not expose old `.stub` APIs. Reuse `with_singleton_replacement` and Faraday's test adapter, restoring replacements in `ensure`.
- RubyLLM 2 supports `Chat#with_context`, `with_max_output_tokens`, and provider-instance `list_models`. Do not globally change provider credentials or refresh every provider to update one connection.
- `chunks.embedding` is currently fixed-width, while `documents.embedding` is unrelated to active retrieval. Preserve the latter.
- This checkout has no `bin/ci`. Its real checks are `bin/rubocop`, `bin/brakeman --no-pager`, `bin/importmap audit`, Rails tests/system tests, and standalone packaging tests.
- Do not run install scripts, change the host Ollama installation, pull real multi-GB models, edit the user's `.env`, or modify a development/production database while executing automated tests.

## File ownership map

| Files | Responsibility |
| --- | --- |
| `app/models/inference.rb`, `app/models/knowledge.rb`, `app/models/concerns/uuid_identifiable.rb` | Namespace table prefixes and new metadata identifiers. |
| `app/models/inference/provider.rb`, `app/models/inference/provider/descriptor.rb` | Named connection, typed configuration, encrypted credentials, revisions, provider schema. |
| `app/models/inference/provider/endpoint.rb`, `lib/inference/http_adapter.rb`, `config/initializers/inference_transport.rb` | Approved origins/addresses, private-host consent, socket-level IP pinning, safe HTTP adapter. |
| `app/models/inference/model.rb`, `app/models/inference/model/generation_options.rb`, `app/models/inference/model/catalogable.rb` | Connection-qualified model identity, operation readiness, generation parameters, catalog import. |
| `app/models/inference/settings.rb`, `app/models/inference/selection_error.rb` | Singleton installation defaults and stable API selection/errors. |
| `app/models/inference/host_memory.rb`, `app/models/inference/recommendation.rb`, `config/inference_recommendations.yml` | Memory provenance and deterministic recommendation policy. |
| `app/models/inference/provider/ollama.rb`, `app/models/inference/download.rb`, `app/models/inference/model_preparation.rb`, `app/jobs/inference/download_job.rb`, `app/jobs/inference/model_preparation_job.rb`, `app/jobs/inference/recovery_job.rb` | Ollama HTTP catalog/pull/copy/profile operations, persisted model preparation and recovery. |
| `app/models/knowledge/generation.rb`, `app/models/knowledge/generation/embedding.rb`, `app/models/knowledge/generation/pinning.rb` | Immutable configuration, verified serving identity, embedding validation, pinned retrieval. |
| `app/models/knowledge/revision.rb`, `app/models/concerns/knowledge_journaled.rb` | Transactional source-change sequence and content identity. |
| `app/models/knowledge/rebuild.rb`, `app/models/knowledge/rebuild/source.rb`, `app/models/knowledge/rebuild/reconcilable.rb`, `app/models/knowledge/rebuild/activatable.rb` | Manifest/checkpoints, source publication, catch-up and activation. |
| `app/models/knowledge/generation/chunking.rb`, `app/models/knowledge/generation/retirable.rb` | Pure chunk production and safe historical-generation cleanup. |
| `app/jobs/knowledge/rebuild_job.rb`, `app/jobs/knowledge/rebuild_source_job.rb`, `app/jobs/knowledge/retirement_job.rb` | Shallow generation/rebuild job entry points. |
| `app/models/chunk.rb`, `app/models/chunk/vectorizable.rb`, `app/models/chunk/searchable.rb` | Generation-aware vector storage/search and usage attribution. |
| `app/models/document/chunkable.rb`, `app/models/text/chunkable.rb`, `app/models/qna/chunkable.rb`, `app/models/website/chunkable.rb` | Route ordinary source indexing through the same generation-safe writer. |
| `app/models/inference/legacy_import.rb`, `lib/tasks/inference.rake` | Explicit, idempotent legacy import and redacted operator report. |
| `app/models/chat/inference_configurable.rb`, `app/models/chat/completionable.rb`, `app/models/chat/agent_skillable.rb` | Persist/reapply chat selection and retain generation pins through citations. |
| `app/models/chat/answer_relevance.rb`, `app/models/chat/context_relevance.rb`, `app/models/chat/augmented_prompt.rb`, `app/models/chat/similarity_search.rb`, `app/models/agent_skill/detector.rb`, `app/models/chunk/enrichable.rb` | Remove remaining inference environment reads without changing unrelated algorithms. |
| `app/controllers/chats_controller.rb`, `app/controllers/dashboards_controller.rb`, `app/controllers/api/v1/models_controller.rb`, `app/controllers/api/v1/completions_controller.rb` | New-chat/API selection, canonical identifiers, validated options. |
| `app/models/inference/setup.rb`, `app/jobs/inference/preparation_job.rb`, `app/controllers/inference_setups_controller.rb`, `app/controllers/concerns/inference_ready.rb`, `app/controllers/first_runs_controller.rb` | Resumable first-run wizard and confirmed preparation. |
| `app/controllers/inference/base_controller.rb`, `app/controllers/inference/providers_controller.rb`, `app/controllers/inference/provider_tests_controller.rb`, `app/controllers/inference/catalog_refreshes_controller.rb`, `app/controllers/inference/model_preparations_controller.rb`, `app/controllers/inference/defaults_controller.rb`, `app/controllers/inference/knowledge_configurations_controller.rb`, `app/controllers/inference/rebuilds_controller.rb`, `app/controllers/inference/downloads_controller.rb`, `app/controllers/inference/retries_controller.rb` | Admin-only REST resources, optimistic concurrency, validation responses. |
| `app/controllers/models_controller.rb`, `app/helpers/models_helper.rb`, `app/views/models/`, `app/views/inference/`, `app/views/inference_setups/` | Direction-A workspace, typed forms, setup, impact review and operation status. |
| `app/views/chats/_model.html.erb`, `app/views/chats/_composer.html.erb`, `app/views/chats/_form.html.erb`, `app/views/messages/_form.html.erb` | Selected/read-only model in the existing composer. |
| `app/assets/stylesheets/nosia/inference.css`, `app/assets/tailwind/application.css`, `app/javascript/controllers/inference_errors_controller.js`, `app/javascript/controllers/inference_progress_controller.js` | Scoped responsive styling, failed-form focus and bounded server-state polling, not a parallel client-side state machine. |
| `config/locales/en.nosia_inference.yml`, `config/locales/fr.nosia_inference.yml` | Complete paired UI copy. |
| `config/routes.rb`, `config/recurring.yml`, `config/initializers/filter_parameter_logging.rb`, `config/initializers/ruby_llm.rb` | REST routing, recovery schedules, redaction and DB-only runtime configuration. |
| `docker-compose.yml`, `.env.example`, `install.sh`, `install.ps1`, `README.md`, `docs/DEPLOYMENT.md`, `docs/ARCHITECTURE.md`, `docs/DIAGRAMS.md`, `docs/README.md`, `docs/inference-providers.md`, `docs/upgrades/inference-configuration.md` | Complete packaging/onboarding/upgrade guidance. |

Migrations are enumerated in their tasks; regenerate `db/schema.rb` using test-only migration commands. Test paths are enumerated per task. Keep large domain files composed of the focused units above rather than building a single inference manager.

## Stable names and contracts

Use these names consistently across tasks:

| Contract | Meaning |
| --- | --- |
| `Inference::Settings.installation` | Unique row selected by `key: "installation"`; creation does not occur from an initializer or migration. |
| `provider.context` | Fresh isolated RubyLLM context containing only this connection's provider configuration. |
| `provider.refresh_now` | Enumerate only this connection, update local binding metadata, preserve unrelated connections. |
| `model.public_id` | `nosia/<25-character binding ID>`; never a backend tag or credential-bearing URL. |
| `model.generation_options(overrides = {})` | Strictly validate/merge only supported parameters, return string-keyed immutable snapshot. |
| `model.configure(chat, options:, serving_model_id: model_id)` | Bind context, snapshotted serving model and capability-aware generation settings to an existing RubyLLM/AR chat. |
| `Inference::Model.resolve(identifier, settings:)` | Default/canonical/unique-legacy resolution; explicit ambiguity errors. |
| `generation.embed(text, operation_key:)` | Verify serving identity, call the generation-specific embedder, validate width/finite values/norm, return RubyLLM result. |
| `generation.with_pin` | Yield under a shared PostgreSQL advisory lock on one checked-out session through citation persistence. |
| `Knowledge::Generation.with_active_pin` | Yield the active generation after acquiring its shared pin under the short settings-row lock; release row lock before invoking the block. |
| `generation.index_source_now(source, revision:)` | Snapshot, embed outside locks, revision-fence and publish chunks atomically for this generation. |
| `rebuild.reconcile_now` / `rebuild.activate` | Reconcile committed revision events, then activate only an entirely caught-up manifest. |
| `setup.confirm` / `setup.prepare_now` | Persist explicit consent, enqueue after commit; download/probe/build idempotently. |
| `Inference::LegacyImport.new(env:, confirmed_legacy_identity:).run` | Operator-only atomic import; never consult ENV during ordinary runtime. |

Technical operation states use explicit strings (`queued`, `running`, `succeeded`, `failed`, `cancelled`) and timestamps. Active knowledge state is the installation's generation reference, not an `active` boolean scattered over rows. Configuration booleans such as augmented context or peer merging are technical controls, not new business-state flags.

Every short `test` block below belongs in the named test file: model tests inherit `ActiveSupport::TestCase`, request/integration tests inherit `ActionDispatch::IntegrationTest`, and browser tests inherit `ApplicationSystemTestCase`. Include `InferenceFixtures`; use `KnowledgeFixtures` for retrieval/browser tests. Keep each test/implementation/verification action small; for a task with multiple listed behaviors, run a separate red→green loop per behavior before the task commit. Do not write the full task implementation before running its first failing behavior test.

## Task 0: Establish the execution baseline

**Files:** Read-only baseline; no application edits.

- [ ] Create an isolated feature worktree using `using-git-worktrees` after the execution mode is selected. Branch from the commit containing this plan. Record `git status --short` before and after creation; do not copy or reset the original workspace's changes.
- [ ] Run `bundle check`. Expected: dependencies satisfied. Do not edit `Gemfile.lock` to conceal missing local dependencies.
- [ ] Run `RAILS_ENV=test bin/rails db:prepare` only after confirming the connection resolves to a dedicated test database. Never use a development/production `DATABASE_URL` inherited from the shell.
- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/controllers/chats_controller_test.rb test/controllers/api/v1/completions_controller_test.rb test/models/chat_test.rb test/lib/ruby_llm_mcp_compatibility_test.rb`. Record actual baseline failures without fixing unrelated features.
- [ ] Run `command -v chromium` or `command -v google-chrome` separately. Use local headless Chrome; the existing `CAPYBARA_SERVER_PORT` remote-driver branch has an incomplete URL and is not a valid harness without additional user-provided configuration.

## Task 1: Add installation-global metadata storage and UUID identities

**Create:** `db/migrate/20261023090000_create_inference_configuration.rb`, `app/models/inference.rb`, `app/models/knowledge.rb`, `app/models/concerns/uuid_identifiable.rb`, `test/models/inference_storage_test.rb`.

- [ ] Write this red storage test first:

```ruby
require "test_helper"

class InferenceStorageTest < ActiveSupport::TestCase
  test "connection metadata is independent of existing account IDs" do
    connection = ActiveRecord::Base.connection
    assert connection.table_exists?(:inference_providers)
    assert_equal :string, connection.columns(:inference_providers).find { |c| c.name == "id" }.type
    assert_equal :bigint, connection.columns(:accounts).find { |c| c.name == "id" }.sql_type.to_sym
    refute connection.column_exists?(:inference_providers, :account_id)
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/inference_storage_test.rb`. Expected RED: missing inference table, not a malformed test.
- [ ] Add this schema and identifier concern; do not query inference settings from the migration:

```ruby
class CreateInferenceConfiguration < ActiveRecord::Migration[8.0]
  def change
    create_table :inference_providers, id: :string, limit: 25 do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.string :auth_mode, null: false, default: "api_key"
      t.string :revision_of_id, limit: 25
      t.jsonb :configuration, default: {}, null: false
      t.text :credentials
      t.jsonb :approved_addresses, default: [], null: false
      t.datetime :private_access_confirmed_at
      t.datetime :verified_at
      t.string :last_error_code
      t.integer :lock_version, default: 0, null: false
      t.timestamps
      t.index :revision_of_id
    end

    create_table :inference_models, id: :string, limit: 25 do |t|
      t.string :inference_provider_id, limit: 25, null: false
      t.bigint :ruby_llm_model_id, null: false
      t.string :model_id, null: false
      t.string :name, null: false
      t.jsonb :operations, default: [], null: false
      t.jsonb :capabilities, default: [], null: false
      t.jsonb :metadata, default: {}, null: false
      t.jsonb :options, default: {}, null: false
      t.datetime :verified_at
      t.datetime :unavailable_at
      t.integer :lock_version, default: 0, null: false
      t.timestamps
      t.index [:inference_provider_id, :model_id], unique: true, name: "index_inference_models_on_connection_and_model"
      t.index :ruby_llm_model_id
    end

    create_table :inference_settings, id: :string, limit: 25 do |t|
      t.string :key, null: false, default: "installation"
      t.string :default_model_id, limit: 25
      t.string :guard_model_id, limit: 25
      t.string :active_generation_id, limit: 25
      t.string :pending_rebuild_id, limit: 25
      t.integer :retrieval_fetch_k, default: 3, null: false
      t.boolean :augmented_context, default: true, null: false
      t.bigint :source_sequence, default: 0, null: false
      t.datetime :imported_at
      t.datetime :onboarded_at
      t.integer :lock_version, default: 0, null: false
      t.timestamps
      t.index :key, unique: true
      t.index :default_model_id
      t.index :guard_model_id
      t.index :active_generation_id
      t.index :pending_rebuild_id
    end
  end
end

module Inference
  def self.table_name_prefix = "inference_"
end

module Knowledge
  def self.table_name_prefix = "knowledge_"
end

module UuidIdentifiable
  extend ActiveSupport::Concern
  included do
    before_validation(on: :create) do
      self.id ||= SecureRandom.uuid_v7.delete("-").to_i(16).to_s(36).rjust(25, "0")
    end
  end
end
```

- [ ] Run `RAILS_ENV=test bin/rails db:migrate`, then the exact test command. Expected GREEN with existing account IDs unchanged. Add a concern test creating a metadata record and checking length 25 and UUID version nibble 7; fixtures may have deterministic synthetic IDs.
- [ ] Commit only this task's files and regenerated `db/schema.rb`: `git commit -m "feat(inference): add installation configuration storage"` after an explicit-path `git add`.

## Task 2: Encrypt connections and build opt-in inference fixtures

**Create:** `app/models/inference/provider.rb`, `app/models/inference/provider/descriptor.rb`, `app/models/inference/model.rb`, `app/models/inference/settings.rb`, `test/support/inference_fixtures.rb`, `test/support/fixtures/inference/inference_providers.yml`, `test/support/fixtures/inference/inference_models.yml`, `test/support/fixtures/inference/inference_settings.yml`, `test/models/inference/provider_test.rb`.

- [ ] Write the focused tests before the models:

```ruby
require "test_helper"
require_relative "../../support/inference_fixtures"

class Inference::ProviderTest < ActiveSupport::TestCase
  include InferenceFixtures

  test "credentials are encrypted and blank edits retain the saved secret" do
    provider = inference_providers(:first)
    provider.assign_configuration({ "openai_api_key" => "" })
    provider.save!
    assert_equal "first-secret", provider.reload.credentials.fetch("openai_api_key")
    refute_includes provider.read_attribute_before_type_cast(:credentials), "first-secret"
  end

  test "every installed native provider has a typed descriptor" do
    RubyLLM::Provider.providers.each_key do |slug|
      assert_equal slug.to_s, Inference::Provider::Descriptor.new(slug.to_s).slug
    end
    assert_raises(ArgumentError) { Inference::Provider::Descriptor.new("Kernel") }
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/inference/provider_test.rb`. Expected RED: absent inference domain/fixture support. Add fixture support before asserting production behavior; a missing YAML file is not the final accepted RED reason.
- [ ] Add the provider's credential boundary:

```ruby
class Inference::Provider < ApplicationRecord
  include UuidIdentifiable
  serialize :credentials, coder: JSON
  encrypts :credentials

  has_many :models, class_name: "Inference::Model", foreign_key: :inference_provider_id, dependent: :restrict_with_error
  validates :name, :kind, presence: true

  def descriptor = Descriptor.new(kind)

  def assign_configuration(values, clear: [])
    values = values.stringify_keys
    raise ArgumentError, "unknown provider fields" if (values.keys - descriptor.fields.keys).any?
    merged = configuration.merge(credentials || {})
    values.each { |key, value| merged[key] = descriptor.cast(key, value) unless value.blank? }
    clear.each { |key| merged.delete(key.to_s) }
    self.credentials = merged.select { |key, _| descriptor.secret?(key) }
    self.configuration = merged.reject { |key, _| descriptor.secret?(key) }
  end
end
```

Define `Descriptor#slug`, `#fields`, `#cast`, `#secret?`, `#provider_slug`, `#validate`, and `#configuration_values` in `descriptor.rb`. `fields` is the installed provider's `configuration_options`, excluding executable `bedrock_credential_provider`, plus the provider protocol where applicable. Map kinds `openai_compatible` and `docker_model_runner` to native `openai`; all other kinds must exactly match a registered slug. The type rule is Boolean for `openai_use_system_role`, parsed JSON object for `vertexai_service_account_key`, String for remaining allowed fields; JSON supplied as an arbitrary path is invalid. Treat key/token/secret/service-account fields as secret. The provider's separate `auth_mode` is one of `api_key`, `unauthenticated`, `workload_identity`, `service_account`, `key_pair`, or `bearer`, restricted by its descriptor. Support static Bedrock key pairs/session tokens, its supported bearer-key mode, or workload identity; Azure key or auth token; Vertex service-account object or workload identity. Validate native requirements plus the chosen auth mode. Custom unauthenticated local compatible endpoints use an internal nonsecret placeholder only when the provider is explicitly configured as unauthenticated, never a real key copied from another provider.

Add the minimal `Inference::Model` persistence class now so opt-in fixture loading is runnable; Task 4 extends it with selection/catalog behavior:

```ruby
class Inference::Model < ApplicationRecord
  include UuidIdentifiable
  belongs_to :inference_provider, class_name: "Inference::Provider"
  belongs_to :ruby_llm_model, class_name: "RubyLLM::ActiveRecord::Model"
end
```

Use this exact singleton method in `Inference::Settings`:

```ruby
def self.installation
  find_by(key: "installation") || create_or_find_by!(key: "installation")
end
```

Validate retrieval K `1..100`; bind default/guard references to `Inference::Model` and defer required-readiness checks until activation/onboarding so an empty installation is editable.

The opt-in fixture helper includes `ChatAccountFixtures` and loads the three inference tables plus explicitly mapped RubyLLM catalog fixtures after its setup. Preserve the existing `picker_model` row under the same fixture label/ID when reloading that catalog table, so old fixture foreign keys remain valid. Expose `inference_providers(name)`, `inference_models(name)`, `inference_settings(name)` from the returned FixtureSets and set `@settings`. Fixture data:

| Fixture | Fixed ID | Required data |
| --- | --- | --- |
| provider `first` | `0000000000000000000000001` | `kind: openai_compatible`, name First, base `https://first.example/v1`, encrypted key `first-secret`. |
| provider `second` | `0000000000000000000000002` | Same backend kind, name Second, base `https://second.example/v1`, encrypted key `second-secret`. |
| provider `ollama` | `0000000000000000000000003` | Kind ollama, auth unauthenticated, native base `http://localhost:11434/v1`, approved `127.0.0.1`, explicit private-access timestamp. |
| model `first` | `0000000000000000000000011` | First provider, `picker-test-model`, operation `chat`, capability `function_calling`, verified timestamp, options temperature .1/output 1024/top P .9. |
| model `second` | `0000000000000000000000012` | Second provider, same backend model ID and verified chat capability, same options. |
| model `embedding` | `0000000000000000000000013` | Ollama provider, dummy `fixture-embedding` registry record, operation embedding, verified supported test widths 2/3/4096. |
| settings `installation` | `0000000000000000000000021` | Key installation, default first, K 3, augmented context true. |

Serialize encrypted fixture values with `Inference::Provider.type_for_attribute("credentials").serialize({ "openai_api_key" => "first-secret" }).to_json`; do not place plaintext secrets directly in the database fixture column. These are dummy test secrets, not copied credentials.

Use explicit `inference_provider_id`/`default_model_id` string values in the YAML, not label-based associations: Rails' hashed fixture label IDs would not match the fixed string IDs in this table. Add `test/support/fixtures/inference/ruby_llm_models.yml` containing the unchanged `picker_model` plus `fixture_embedding` (`model_id: fixture-embedding`, provider ollama, output modality embeddings). Map namespaced table classes explicitly in `create_fixtures`.

- [ ] Rerun the targeted test, then add behavior tests for explicit clearing, invalid JSON/auth modes, immutable in-use endpoint identity, and `provider.revise(attributes)` returning a new revision without changing the old row. Expected GREEN; no live DNS/network calls.
- [ ] Commit with `feat(inference): encrypt typed provider connections` using only explicit paths.

## Task 3: Enforce inference-only endpoint policy and isolate contexts

**Create:** `app/models/inference/provider/endpoint.rb`, `lib/inference/http_adapter.rb`, `config/initializers/inference_transport.rb`, `test/models/inference/provider_context_test.rb`, `test/lib/inference_http_adapter_test.rb`.
**Modify:** `app/models/inference/provider.rb`, `config/initializers/filter_parameter_logging.rb`.

- [ ] Add these red context/security tests:

```ruby
test "contexts for two compatible connections never share keys or mutate globals" do
  previous = RubyLLM.config.openai_api_key
  first = inference_providers(:first).context
  second = inference_providers(:second).context
  assert_equal "first-secret", first.config.openai_api_key
  assert_equal "second-secret", second.config.openai_api_key
  assert_equal "https://first.example/v1", first.config.openai_api_base
  assert_equal previous, RubyLLM.config.openai_api_key
end

test "private inference consent does not weaken source URL protection" do
  stub_url_resolver("127.0.0.1")
  assert_raises(UrlGuard::Blocked) { UrlGuard.verify!("http://localhost:11434") }
ensure
  unstub_url_resolver
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/inference/provider_context_test.rb test/lib/inference_http_adapter_test.rb`. Expected RED: no isolated context/pinning policy.
- [ ] Implement context construction using only saved allowed values:

```ruby
def context
  RubyLLM.context do |config|
    RubyLLM::Provider.providers.values.flat_map(&:configuration_options).uniq.each do |key|
      config.public_send("#{key}=", nil)
    end
    descriptor.configuration_values(self).each do |key, value|
      config.public_send("#{key}=", value)
    end
    config.openai_protocol = :chat_completions if descriptor.provider_slug == "openai"
    config.faraday_adapter = Inference::HttpAdapter.for(endpoint_policy)
  end
end
```

`endpoint_policy` is `Inference::Provider::Endpoint` built from the descriptor's resolved effective API origin and this provider's approved IP addresses. `Endpoint#approve` accepts HTTP(S) only, rejects URL userinfo/fragments, rejects unspecified/multicast/link-local/metadata addresses (including mapped IPv6), and requires explicit admin confirmation for loopback/private targets. Store approved addresses separately from secrets. `Endpoint#address_for(uri)` rejects a different origin, any unapproved resolved address, or DNS changes until reapproved. Native provider auxiliary origins must come from the hardcoded installed-provider descriptor, not a URL returned by a model or ordinary user.

The custom Faraday adapter must subclass the installed Net::HTTP adapter and override its socket creation boundary, not just validate DNS before a separately resolving request. The concrete pin is:

```ruby
def build_connection(env)
  super.tap do |http|
    http.ipaddr = @endpoint.address_for(env.url)
  end
end
```

`Inference::HttpAdapter.for(endpoint)` returns a class closing over that immutable endpoint policy and setting `@endpoint` in `initialize`. Preserve the original hostname for Host/TLS certificate checks; reject redirects rather than forward credentials across origins. Test it with a fake Net::HTTP object and resolver changes between approval and socket construction. Verify the installed adapter signature before adding the override; if it differs, the adapter contract test must fail before changing implementation. Do not monkey-patch RubyLLM's global transport or `UrlGuard`.

The inspected `faraday-net_http` 3.4.4 implementation returns a `Net::HTTP` instance from `build_connection(env)`, so this override pins before `http.start`. Explicitly reject an inherited HTTP proxy unless it has a separately implemented approved-proxy policy; a proxy must not bypass endpoint IP pinning by resolving the target elsewhere. Add a proxy-bypass regression and retain TLS hostname verification. No proxy setting is introduced by this feature.

Extend filtered parameters with `credentials`, `configuration.vertexai_service_account_key`, auth-token fields, and service-account private-key material. Use sanitized operation error codes, never raw upstream bodies or `error.message` in UI/logs. Disable RubyLLM HTTP-body debug logging for this integration and test redaction at debug level; no credential-bearing request can be logged by changing a browser preference.

- [ ] Run both tests plus `PARALLEL_WORKERS=1 bin/rails test test/lib/url_guard_test.rb`. Add denied metadata/redirect/rebinding and approved-local tests. Expected GREEN with unchanged crawler/MCP policy.
- [ ] Commit with `feat(inference): isolate contexts and pin approved endpoints`.

## Task 4: Add qualified model selection, catalogs, and generation options

**Create:** `app/models/inference/model/catalogable.rb`, `app/models/inference/model/generation_options.rb`, `app/models/inference/selection_error.rb`, `test/models/inference/model_test.rb`, `test/models/inference/model_options_test.rb`.
**Modify:** `app/models/inference/provider.rb`, `app/models/inference/model.rb`.

- [ ] Write the selection test:

```ruby
test "ambiguous legacy identifiers never select the default implicitly" do
  error = assert_raises(Inference::SelectionError) do
    Inference::Model.resolve("picker-test-model", settings: @settings)
  end
  assert_equal "ambiguous_model", error.code
  chosen = inference_models(:second)
  assert_equal chosen, Inference::Model.resolve(chosen.public_id, settings: @settings)
  assert_equal inference_models(:first), Inference::Model.resolve(nil, settings: @settings)
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/inference/model_test.rb test/models/inference/model_options_test.rb`. Expected RED: missing qualified selection/options behavior.
- [ ] Add the resolver and binding methods:

```ruby
def public_id = "nosia/#{id}"

def self.resolve(identifier, settings: Inference::Settings.installation)
  value = identifier.to_s.strip
  if value.empty?
    settings.default_model || raise(Inference::SelectionError.new("inference_not_configured", 503))
  elsif value.start_with?("nosia/")
    ready_chat.find_by(id: value.delete_prefix("nosia/")) || raise(Inference::SelectionError.new("model_not_found", 400))
  else
    matches = ready_chat.where(model_id: value.delete_prefix("nosia:")).limit(2).to_a
    raise Inference::SelectionError.new("ambiguous_model", 400) if matches.size > 1
    matches.first || raise(Inference::SelectionError.new("model_not_found", 400))
  end
end

def configure(chat, options:, serving_model_id: model_id)
  chat.with_context(inference_provider.context)
  chat.with_model(serving_model_id, provider: inference_provider.descriptor.provider_slug.to_sym, assume_model_exists: true)
  chat.with_max_output_tokens(options.fetch("max_tokens"))
  chat.with_temperature(options["temperature"]) if options.key?("temperature")
  chat.with_provider_options(options.slice("top_p", "top_k").symbolize_keys)
  chat
end
```

`ready_chat` requires `verified_at`, no `unavailable_at`, and operations containing `chat`. Default resolution also checks readiness rather than returning an unverified default. `SelectionError` exposes `code`, `status`, and a fixed safe `message` from a code map; its error type is `invalid_request_error` for 400 and `server_error` for 503.

`GenerationOptions#call` merges saved options with a string-keyed allowlist (`temperature`, `max_tokens`, `top_p`, `top_k`, `context_tokens`); reject unknown/nonnumeric/NaN values rather than coercing `"abc"` to zero. Enforce positive integer token/context limits, max output <= context/4 and verified model max output; top P `(0,1]`, positive integer top K, and temperature within the verified provider/model range. Unsupported fields are absent in saved/returned snapshots and disabled/explained in forms. Add per-family supported-control metadata when a provider's protocol does not expose it generically; do not infer support from RubyLLM's permissive `Model.default` capabilities.

`Provider#refresh_now` instantiates `RubyLLM::Provider.resolve!(descriptor.provider_slug).new(context.config)` and calls its `list_models`. Upsert bindings by provider row/model ID, keeping readiness separate from mere catalog presence. Use RubyLLM-owned model records for shared identity metadata; store endpoint-specific dimensions/caps/pricing/context observations on the binding rather than overwrite another endpoint's observations. Missing entries become unavailable for new selection, never cascade-delete historical chats. Filter Nosia-managed serving aliases out of catalog results. Speech-only entries remain configurable but not ready chat/embedding choices.

For a native provider that does not support a live models-list endpoint, use provider-scoped bundled RubyLLM metadata or an explicitly entered model ID and mark it unverified until a consented readiness probe succeeds. Unsupported listing is not proof of invalid credentials and must not remove support for that provider. This is catalog discovery behavior, not fallback inference routing.

- [ ] Add tests for unique legacy IDs, `nosia:<raw>` aliases, explicit unknown/disabled/nonchat canonical IDs, two endpoints' differing metadata, output limits, unsupported fields, and capabilities falsely assumed by the base registry. Run both files and provider tests. Expected GREEN.
- [ ] Commit with `feat(inference): qualify models by saved connection`.

## Task 5: Implement transparent memory detection and recommendations

**Create:** `app/models/inference/host_memory.rb`, `app/models/inference/recommendation.rb`, `config/inference_recommendations.yml`, `test/models/inference/recommendation_test.rb`.

- [ ] Add a deterministic test with explicit inputs and no hardware/network dependency:

```ruby
test "a fitting installed model wins without a download" do
  result = Inference::Recommendation.new(
    ram_bytes: 32 * 1024**3, confirmed: true, embedding_bytes: 4_700_000_000,
    installed: [{ id: "qwen3:4b", bytes: 2_500_000_000, chat: true, tools: true, context: 40960 }]
  ).call
  assert_equal "qwen3:4b", result.fetch(:model_id)
  assert_equal false, result.fetch(:download_required)
  assert_equal 2048, result.fetch(:options).fetch("max_tokens")
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/inference/recommendation_test.rb`; expected RED for missing recommendation behavior.
- [ ] Store the exact reviewed fallback table and implement the budget kernel:

```yaml
models:
  qwen3:0.6b: 523000000
  qwen3:1.7b: 1400000000
  qwen3:4b: 2500000000
  qwen3:8b: 5200000000
  qwen3:14b: 9300000000
  qwen3:32b: 20000000000
embedding_bytes: 4700000000
```

```ruby
def budget
  reserve = [2 * 1024**3, (@ram_bytes * 0.25).ceil].max
  context_allowance = @ram_bytes < 16 * 1024**3 ? 1024**3 : 2 * 1024**3
  @ram_bytes - reserve - (@embedding_bytes * 1.5).ceil - context_allowance
end

def fits?(bytes)
  bytes && (bytes * 1.5).ceil <= budget
end
```

The initializer accepts `ram_bytes:`, `confirmed:`, `embedding_bytes:`, and `installed:` as shown. `call` returns `model_id`, `download_required`, `estimated_bytes`, `options`, `reason`, and `warnings`. Filter verified chat/tool entries, prefer largest fitting reviewed-family installed model, then largest fitting other installed entry with ID tie-break; only then use the largest fitting YAML fallback. Below 16 GiB use 4096/1024 context/output, otherwise 8192/2048, capped by verified model limits. No fitting/confirmed candidate returns `model_id: nil` with an explicit reason, not a hidden downgrade. Cloud embedding headroom is zero; uncertain cohosting reserves memory conservatively.

`HostMemory#detect` returns bytes plus `source` and `confirmed` provenance; native Linux/macOS/Windows adapters read memory without installation or shell interpolation. Container/remote uncertainty returns unconfirmed information. Confirmation is persisted in provider metadata/setup inputs and is editable. Do not confuse Ollama `/api/ps` loaded-model sizes with total host RAM.

- [ ] Add unknown RAM/unknown footprint, 8-GiB insufficient-budget, embedding-only catalog, largest-fitting fallback, exact threshold, smaller model context cap, and separate-cloud embedding tests. Rerun the file; expected GREEN.
- [ ] Commit with `feat(inference): recommend Ollama models from confirmed memory`.

## Task 6: Provision Ollama models with persistent progress and recovery

**Create:** `db/migrate/20261023091000_create_inference_downloads.rb`, `app/models/inference/provider/ollama.rb`, `app/models/inference/download.rb`, `app/jobs/inference/download_job.rb`, `app/jobs/inference/recovery_job.rb`, `test/models/inference/download_test.rb`, `test/models/inference/ollama_test.rb`.
**Modify:** `config/recurring.yml`.

- [ ] Write a red operation test:

```ruby
test "a duplicate confirmed request reuses one download operation" do
  provider = inference_providers(:ollama)
  first = Inference::Download.request(provider: provider, model_id: "qwen3:4b", consented: true)
  second = Inference::Download.request(provider: provider, model_id: "qwen3:4b", consented: true)
  assert_equal first.id, second.id
  assert_equal "queued", first.state
  assert_raises(ArgumentError) do
    Inference::Download.request(provider: provider, model_id: "qwen3:8b", consented: false)
  end
end
```

- [ ] Run both new test files; expected RED for missing persisted downloads.
- [ ] Migrate a UUID-string `inference_downloads` table with provider ID, model ID, unique `request_key`, string `state`, `progress` JSONB, `attempt_token`, `heartbeat_at`, `confirmed_at`, `completed_at`, `last_error_code`, lock version, and timestamps. Create a partial unique index for one live `(provider,model)` operation while state is queued/running. `request` validates consent and supported Ollama backend before insert, catches uniqueness races, and enqueues after commit.

Use this job exactly:

```ruby
class Inference::DownloadJob < ApplicationJob
  queue_as :background
  def perform(id)
    Inference::Download.find(id).run_now
  end
end
```

`Provider::Ollama` exposes `tags`, `show(model_id)`, `pull(model_id) { |event| }`, `copy(source:, destination:)`, `create_profile(source:, destination:, context_tokens:)`, and `delete_managed_alias(alias_id)`. It uses the same endpoint policy/auth as the selected provider, derives native `/api` routes independently of RubyLLM's `/v1` base, and rejects operations on a non-Ollama backend. Pull parsing must buffer fragmented NDJSON lines and process a final unterminated line; update per-digest byte totals without double counting. `create_profile` sends only known fields to `/api/create` with `from` and `parameters.num_ctx`: Ollama's OpenAI endpoint does not reliably accept a `num_ctx` request field. Prepare a managed serving profile after consent when a nondefault runtime context is needed, verify it through show, and snapshot its serving ID on the chat. Keep public model identity unchanged. Never claim a context budget was enforced merely because the UI displays it. Do not execute `ollama`, interpolate shell commands, expose arbitrary methods/paths, or delete user-owned tags.

`Download#run_now` claims an attempt token under its row lock, releases locks before HTTP, persists heartbeat/progress checkpoints, fences all progress/completion writes to that token, and marks ready only after tags/show verification. Duplicate running deliveries return without starting a second pull. A failure stores a fixed code and preserves retryable metadata; retry resumes Ollama's content-addressed pull rather than inventing byte-range handling. `Inference::RecoveryJob#perform` calls model recovery methods for abandoned heartbeats; old attempts cannot complete a replacement attempt. Schedule every minute in production.

- [ ] Exercise fake fragmented streams, unknown totals, already-installed models, 401/timeouts, worker interruption, duplicate workers and stale attempt completion. Verify no pull before consent and no network locks. Run both files and `PARALLEL_WORKERS=1 bin/rails test test/models/inference`; expected GREEN.
- [ ] Commit with `feat(inference): persist Ollama provisioning progress`.

### Task 6A: Prepare newly selected models outside first-run onboarding

**Create:** `db/migrate/20261023091100_create_inference_model_preparations.rb`, `app/models/inference/model_preparation.rb`, `app/jobs/inference/model_preparation_job.rb`, `test/models/inference/model_preparation_test.rb`.
**Modify:** `app/models/inference/model.rb`, `app/jobs/inference/recovery_job.rb`.

- [ ] Add a red test asserting that `model.request_preparation(options: model.generation_options, consented: false)` raises, a confirmed request enqueues one preparation, and repeating identical model/options reuses it without a second paid probe.
- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/inference/model_preparation_test.rb`; expected RED for the missing ongoing model-preparation path. Setup must not be the only route to ready a newly added model.
- [ ] Persist `inference_model_preparations` with UUID-string ID, model ID, requested options JSONB, unique request-key digest, serving model ID/digest, state, attempt token, heartbeat, confirmed/completed timestamps, safe error code and timestamps. `Model#request_preparation` validates explicit consent/options, deduplicates by binding + immutable identity/context profile + options digest, and enqueues after commit. `ModelPreparation#run_now` waits/resumes any required download, prepares a managed context profile if required, runs a tiny disclosed operation-specific readiness probe, validates the actual response/capabilities, then marks the binding/preparation verified. Only a succeeded record supplies `Model#prepared_serving_id`; never mark a catalog entry ready simply because it was listed. Recover abandoned attempts with the same fencing rules as downloads.

```ruby
class Inference::ModelPreparationJob < ApplicationJob
  queue_as :background
  def perform(id)
    Inference::ModelPreparation.find(id).run_now
  end
end
```

- [ ] Add failed probe/retry, unsupported controls, duplicate workers, context alias verification, no default mutation and secret-redaction tests. Run the file; expected GREEN.
- [ ] Commit with `feat(inference): prepare models before selecting them`.

### Checkpoint A

- [ ] Run foundation tests, RuboCop on touched Ruby files, and the original baseline. Review the provider auth matrix for every installed native provider, unauthenticated compatible endpoints, request-body redaction, and socket pinning. Confirm no live inference path has been switched yet and no deployment variables have been removed.

## Task 7: Add dimension-flexible generation storage without changing live defaults

**Create:** `db/migrate/20261023092000_create_knowledge_generations.rb`, `db/migrate/20261023092100_make_chunk_embeddings_generation_compatible.rb`, `app/models/knowledge/generation.rb`, `test/support/knowledge_fixtures.rb`, `test/support/fixtures/knowledge/knowledge_generations.yml`, `test/models/knowledge/generation_storage_test.rb`.
**Modify:** `db/migrate/20260821121000_align_chunks_embedding_dimensions.rb`, `app/models/chunk.rb`.

- [ ] Write a migration/storage regression test using two small vector widths:

```ruby
test "old and replacement widths coexist without changing document embeddings" do
  old = knowledge_generations(:active)
  replacement = create_pending_generation(dimensions: 3)
  first = insert_knowledge_chunk(old, [1.0, 0.0])
  second = insert_knowledge_chunk(replacement, [1.0, 0.0, 0.0])
  assert_equal 2, first.embedding.size
  assert_equal 3, second.embedding.size
  assert_equal 768, ActiveRecord::Base.connection.columns(:documents).find { |c| c.name == "embedding" }.limit
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/knowledge/generation_storage_test.rb`; expected RED for absent generation-compatible storage. Extend the opt-in support with `KnowledgeFixtures` and the two-dimensional generation before the final RED run; wrong setup is not feature evidence.
- [ ] Create the generation schema, with these exact stored attributes:

```ruby
create_table :knowledge_generations, id: :string, limit: 25 do |t|
  t.string :inference_model_id, limit: 25, null: false
  t.string :source_model_id, null: false
  t.string :serving_model_id
  t.string :serving_digest
  t.integer :dimensions, null: false
  t.integer :chunk_size, default: 512, null: false
  t.integer :chunk_overlap, default: 128, null: false
  t.boolean :merge_peers, default: false, null: false
  t.integer :chunk_max_tokens, default: 1024, null: false
  t.string :state, default: "draft", null: false
  t.datetime :verified_at
  t.datetime :retired_at
  t.integer :lock_version, default: 0, null: false
  t.timestamps
  t.index :inference_model_id
end
add_column :chunks, :knowledge_generation_id, :string, limit: 25
add_column :chunks, :source_revision_sequence, :bigint
add_column :chunks, :position, :integer
add_index :chunks, [:account_id, :knowledge_generation_id]
add_index :chunks, [:knowledge_generation_id, :chunkable_type, :chunkable_id, :position],
  unique: true, where: "knowledge_generation_id IS NOT NULL", name: "index_chunks_on_generation_source_position"
add_column :token_usages, :operation_key, :string
add_index :token_usages, :operation_key, unique: true, where: "operation_key IS NOT NULL"
```

The vector migration drops only the actual embedding HNSW index, safely/concurrently where supported, then executes `ALTER TABLE chunks ALTER COLUMN embedding TYPE vector` with bounded lock/statement timeout. Keep account/source indexes. Leave historical null generation references temporarily legal for import; new domain writes require generation identity. Do not set NOT NULL before populated legacy data is imported. Guard the down path: never cast populated mixed-width data to an arbitrary width; raise `ActiveRecord::IrreversibleMigration` with an explicit restore-from-backup instruction instead of deleting data.

Freeze the historical `AlignChunksEmbeddingDimensions` migration's schema intent at its historical 768-dimensional baseline rather than calling `Chunk.embedding_dimensions` or reading ENV. The new terminal migration removes that typmod. Existing deployments do not rerun the historical migration; fresh all-migration/schema-load paths must converge on dimension-flexible chunks with no inference inputs.

`Generation` validates integer dimensions `1..16000`, chunk/overlap rules, positive merge-token limit, and immutable configuration once verified. A generation's model belongs to its saved provider; changing the installation default does not change this reference. Add `Chunk#knowledge_generation` and prevent content/generation/source identity changes on a persisted versioned chunk; metadata-only enrichment remains allowed.

- [ ] Run test-only migrations and the storage test. Add preserved-vector-value, unchanged document-column, importer-null-compatibility, unsafe rollback, and existing-data-width assertions. Expected GREEN without an inference API call.
- [ ] Commit with `feat(knowledge): store dimension-flexible generation chunks`.

## Task 8: Pin independent embedding identities and validate every returned vector

**Create:** `app/models/knowledge/generation/embedding.rb`, `test/models/knowledge/embedding_identity_test.rb`.
**Modify:** `app/models/knowledge/generation.rb`, `app/models/inference/provider/ollama.rb`, `test/support/knowledge_fixtures.rb`.

- [ ] Write this identity test around a fake Ollama HTTP catalog:

```ruby
test "pulling the base tag never repoints the active generation" do
  active = knowledge_generations(:active)
  before = active.serving_model_id
  with_fake_ollama(base_digest: "new-weights", aliases: { before => active.serving_digest }) do
    active.verify_identity
    assert_equal before, active.reload.serving_model_id
  end
end

test "an unexpected serving digest fails closed" do
  active = knowledge_generations(:active)
  with_fake_ollama(base_digest: "new-weights", aliases: { active.serving_model_id => "wrong-weights" }) do
    assert_raises(Knowledge::Generation::IdentityChanged) { active.verify_identity }
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/knowledge/embedding_identity_test.rb`; expected RED because a stored digest alone does not enforce request identity.
- [ ] Add `prepare_identity`, `verify_identity`, and `embed(text, operation_key:)`. Use a fixed internal namespace such as `nosia-embedding-<generation-id>:managed`; only aliases belonging to a persisted generation may be deleted. HTTP-copy the source tag after confirmation, verify the alias's catalog digest, and store both source/serving identities. Before repulling a base tag, verify active aliases exist; never pull/copy into an already verified alias. The core vector validation is:

```ruby
def validate_vector(vector)
  values = Array(vector)
  valid = values.size == dimensions && values.all? { |n| n.is_a?(Numeric) && n.finite? }
  valid &&= values.any? { |n| !n.zero? }
  raise InvalidVector, "embedding shape does not match this generation" unless valid
  values
end

def embed(text, operation_key:)
  verify_identity
  result = inference_model.inference_provider.context.embed(
    text, model: serving_model_id,
    provider: inference_model.inference_provider.descriptor.provider_slug.to_sym,
    dimensions: dimensions, assume_model_exists: true
  )
  validate_vector(result.vectors)
  verify_identity
  result
end
```

Define `IdentityChanged`/`InvalidVector` on `Knowledge::Generation`. The `operation_key` is carried into the caller's unique usage write; do not log it with source text. Non-Ollama providers use explicit immutable/versioned serving IDs or new endpoint revisions; block in-place replacement if old/new identities cannot coexist. Missing/mismatched identity stops the pending build or produces knowledge-unavailable for an active generation; never substitute the source tag. Verify after embedding and before persisting a batch to catch an out-of-band model change.

`KnowledgeFixtures` includes `InferenceFixtures`, uses its verified dummy embedding binding, and loads only its generation table. `insert_knowledge_chunk(generation, vector, account: @first, source: texts(:picker_first_text), content: "fixture")` writes explicit generation/account/source/position/revision values without an inference callback. The fixture helpers are specified below. `with_fake_ollama` installs connection-scoped Faraday stubs for tags/show/copy/pull and captures requests; it must not replace `generation.embed` in identity tests.

- [ ] Test exact alias sent on actual RubyLLM embedding requests, 4096 and reduced-width output, fixed-width rejection, NaN/zero vectors, source-tag changes during an in-flight batch, alias cleanup ownership and remote mutable-ID rejection. Run the identity file; expected GREEN with zero real pulls.
- [ ] Commit with `feat(knowledge): keep independently addressable embedding identities`.

## Task 9: Journal source revisions transactionally without indexing under locks

**Create:** `db/migrate/20261023093000_create_knowledge_revisions.rb`, `app/models/knowledge/revision.rb`, `app/models/concerns/knowledge_journaled.rb`, `test/support/fixtures/knowledge/knowledge_revisions.yml`, `test/models/knowledge/revision_test.rb`.
**Modify:** `app/models/document.rb`, `app/models/text.rb`, `app/models/qna.rb`, `app/models/website.rb`, `test/support/knowledge_fixtures.rb`.

- [ ] Write transactional red tests:

```ruby
test "a rolled-back source edit does not advance the committed sequence" do
  source = texts(:picker_first_text)
  before = @settings.reload.source_sequence
  Text.transaction do
    source.update!(data: "changed")
    raise ActiveRecord::Rollback
  end
  assert_equal before, @settings.reload.source_sequence
end

test "index-status updates are not content revisions" do
  source = texts(:picker_first_text)
  before = @settings.reload.source_sequence
  source.mark_indexed!
  assert_equal before, @settings.reload.source_sequence
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/knowledge/revision_test.rb`; expected RED for missing revision tracking.
- [ ] Create `knowledge_revisions` with UUID-string ID, bigint `sequence` unique, bigint `account_id`, string `source_type`, bigint `source_id`, `action` (`upsert`/`delete`), `content_digest`, and timestamps. Index `(source_type,source_id,sequence)` and `(account_id,sequence)`. Only allow `Document`, `Text`, `Qna`, `Website`; never constantize arbitrary request input.

Wrap content-changing save/create/delete operations with this transaction order:

```ruby
def with_knowledge_revision(action: "upsert")
  settings = Inference::Settings.find_by(key: "installation")
  if settings && (action == "delete" || knowledge_content_change?)
    settings.with_lock do
      yield
      settings.update!(source_sequence: settings.source_sequence + 1)
      Knowledge::Revision.create!(account_id: account_id, sequence: settings.source_sequence,
        source_type: self.class.base_class.name, source_id: id,
        action: action, content_digest: knowledge_digest)
    end
  else
    yield
  end
end
```

Define `knowledge_content`, `knowledge_digest`, and `knowledge_content_change?` in the concern using explicit source mappings: document `content`/relevant metadata, text/website `data`, QnA question+answer. Include source/account reassignment and deletes; do not journal mere `index_status`/timestamp updates. Register around-save using action `upsert` and around-destroy explicitly using action `delete`; checking dirty attributes alone would miss deletion. Register wrappers early enough to wrap dependent chunk deletion, keep all DB changes in the same transaction, and enqueue ordinary indexing after commit. Define `Revision.latest_for(source)` as the account/type/ID-scoped row ordered by descending sequence; it never silently creates a revision. Empty extracted content remains pending/excluded until parsing commits content. Legacy sources existing before the journal receive explicit baseline revisions during import, not invented missing content. No network, parsing, or embedding call occurs inside the settings-row lock.

- [ ] Test two database sessions committing source changes, a settings lock held only for writes, deletion tombstones, rejected source-type injection, account isolation, and content edits after an embedding snapshot. Run the revision file and existing source tests; expected GREEN.
- [ ] Commit with `feat(knowledge): journal committed source revisions`.

## Task 10: Produce chunks purely and publish one generation/source revision atomically

**Create:** `app/models/knowledge/generation/chunking.rb`, `test/models/knowledge/generation_indexing_test.rb`.
**Modify:** `app/models/document/chunkable.rb`, `app/models/text/chunkable.rb`, `app/models/qna/chunkable.rb`, `app/models/website/chunkable.rb`, `app/models/chunk/vectorizable.rb`, `app/models/chunk.rb`.

- [ ] Add a red publication test:

```ruby
test "reindexing a replacement never deletes active chunks" do
  active = knowledge_generations(:active)
  original = insert_knowledge_chunk(active, [1.0, 0.0])
  replacement = create_pending_generation(dimensions: 3)
  source = original.chunkable
  revision = Knowledge::Revision.latest_for(source)
  with_fake_embeddings(replacement, vectors: [[1.0, 0.0, 0.0]]) do
    replacement.index_source_now(source, revision: revision)
  end
  assert Chunk.exists?(original.id)
  assert_equal [3], replacement.chunks.where(chunkable: source).map { |chunk| chunk.embedding.size }.uniq
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/knowledge/generation_indexing_test.rb`; expected RED because current chunkify destroys all source chunks.
- [ ] Give each source a pure `build_chunks(generation:)` interface. Use the existing separator list and Baran splitter; read size/overlap/merge/token limit from the immutable generation. Add position/source metadata consistently to non-document sources. Do not call the enrichment LLM or recrawl content to rebuild embeddings. Replace ordinary `chunkify!` with a call to the active generation's `index_source_now` at the runtime cutover, not before imported active settings exist.

The publication algorithm is explicit:

```ruby
def index_source_now(source, revision:)
  snapshot = source.build_chunks(generation: self)
  prepared = snapshot.each_with_index.map do |attributes, index|
    key = "embedding/#{id}/#{revision.sequence}/#{index + 1}"
    result = embed(attributes.fetch(:content), operation_key: key)
    attributes.merge(embedding: result.vectors, position: index + 1,
      source_revision_sequence: revision.sequence, knowledge_generation_id: id,
      account_id: source.account_id)
  end
  publish_source(source, revision: revision, attributes: prepared)
end
```

`publish_source` takes the settings lock, reloads source and latest revision, rejects deleted/superseded content and retired/cancelled targets, then replaces **only this generation/source's** chunks in a transaction. Verify serving identity before entering the lock, and fence publication to the prepared digest/revision so no network call is needed under the lock. An already-published identical revision returns its existing chunks without embedding again; check this before expensive work. Keep usage inputs alongside prepared attributes and insert `TokenUsage` records once with the deterministic unique operation key. A losing attempt may have incurred external usage, but it must not duplicate the successful ledger event.

For migration safety, implement/test the new generation writer and retrieval wrappers directly through Task 13; wire existing source/chat entry points to them only in Task 14, after executable import exists. Do not add a hidden ENV fallback to make an incomplete intermediate commit look deployable.

Remove automatic embedding of a precomputed chunk from `Chunk::Vectorizable`; the generation writer is authoritative. Keep `generate_embedding!` as an explicit generation-aware operation for existing internal consumers and reject content edits on persisted historical chunks. Do not let a precomputed-vector flag be controlled by HTTP parameters. Update previous/next lookups to include `knowledge_generation_id` and use the integer position, retaining legacy metadata positions only for import compatibility.

- [ ] Test duplicate indexing, failed embedding leaving old chunks unchanged, edits/deletes during external embedding, per-account publication, document merging, same-width new-model indexing, and metadata-only enrichment. Run the indexing file plus existing chunk/source tests; expected GREEN.
- [ ] Commit with `feat(knowledge): publish revision-fenced generation chunks`.

## Task 11: Build a resumable replacement manifest and atomic activation

**Create:** `db/migrate/20261023094000_create_knowledge_rebuilds.rb`, `app/models/knowledge/rebuild.rb`, `app/models/knowledge/rebuild/source.rb`, `app/models/knowledge/rebuild/reconcilable.rb`, `app/models/knowledge/rebuild/activatable.rb`, `app/jobs/knowledge/rebuild_job.rb`, `app/jobs/knowledge/rebuild_source_job.rb`, `test/models/knowledge/rebuild_test.rb`, `test/models/knowledge/rebuild_concurrency_test.rb`.

- [ ] Write activation tests first:

```ruby
test "failed replacement cannot switch the active generation" do
  original = @settings.active_generation
  rebuild = Knowledge::Rebuild.request(generation: create_pending_generation, confirmed: true)
  rebuild.sources.first.update!(state: "failed", error_code: "embedding_unavailable")
  assert_raises(Knowledge::Rebuild::NotReady) { rebuild.activate }
  assert_equal original, @settings.reload.active_generation
end

test "retrieval-count-only edits do not create a rebuild" do
  assert_no_difference "Knowledge::Rebuild.count" do
    @settings.update!(retrieval_fetch_k: 7)
  end
end
```

- [ ] Run both rebuild files. Expected RED for absent manifests/activation gate.
- [ ] Add two UUID-string tables. `knowledge_rebuilds`: generation ID, state, unique nullable `live_slot` (`installation` while queued/running), reconciled sequence, attempt token/heartbeat, confirmed/completed/cancelled timestamps, error code, lock version/timestamps. `knowledge_rebuild_sources`: rebuild ID, account ID bigint, source type/ID, desired revision sequence, completed revision sequence, attempt token/heartbeat, state/error code, timestamps, unique `(rebuild,source_type,source_id)`. Define `Knowledge::Rebuild::Source.table_name` explicitly as `knowledge_rebuild_sources`.

`Rebuild.request` requires confirmation and a verified pending generation, reserves the unique installation live slot, sets settings.pending_rebuild under the short lock, snapshots eligible sources/revisions and explicitly excluded preexisting unavailable sources, and enqueues after commit. A second live request returns an actionable conflict, never overwrites the pending target. A failed build may retry its failed sources; cancelling fences attempts and clears the live slot only after the cancellation record is committed.

`reconcile_now` walks revision events above its recorded sequence through a captured high-water mark, updates checkpoints to the latest source revision (including tombstones), and enqueues unfinished checkpoints. Each checkpoint job calls `generation.index_source_now`, recording completion only for its claimed attempt/revision. New failures block activation; no silent exclusion. Ordinary active indexing continues independently. Recovery resets abandoned attempt tokens and requeues only unresolved revisions.

Use this activation kernel:

```ruby
def activate
  settings = Inference::Settings.installation
  settings.with_lock do
    reload
    raise NotReady unless state == "running" && sources.where.not(state: ["succeeded", "excluded", "deleted"]).none?
    raise NotReady if sources.where(state: "succeeded").where("completed_revision_sequence IS DISTINCT FROM desired_revision_sequence").exists?
    raise NotReady unless reconciled_sequence == settings.source_sequence
    raise NotReady unless settings.pending_rebuild_id == id
    previous = settings.active_generation
    settings.update!(active_generation: generation, pending_rebuild: nil)
    generation.update!(state: "ready")
    previous&.update!(state: "retired", retired_at: Time.current)
    update!(state: "succeeded", completed_at: Time.current, live_slot: nil)
  end
end
```

The source checkpoint query also verifies completed revision equals desired revision, not state text alone. Enqueue retirement after activation commits. `RebuildJob` calls `reconcile_now`; `RebuildSourceJob` calls one checkpoint's `run_now`; both are shallow and restore explicit source account tenancy.

- [ ] Run deterministic two-session tests with barriers: edit just before activation, edit just after pointer read, delete during a build, newly uploaded source, stale checkpoint completion, cancel versus publish, and empty-knowledge activation. Assert no network under locks and no missing committed revision. Expected GREEN.
- [ ] Commit with `feat(knowledge): activate only complete replacement generations`.

## Task 12: Pin retrieval through citation persistence and retire safely

**Create:** `app/models/knowledge/generation/pinning.rb`, `app/models/knowledge/generation/retirable.rb`, `app/jobs/knowledge/retirement_job.rb`, `test/models/knowledge/generation_pinning_test.rb`, `test/models/knowledge/retirement_test.rb`.
**Modify:** `app/models/chunk/searchable.rb`, `app/models/chat/similarity_search.rb`, `app/models/chat/completionable.rb`, `app/models/chat/agent_skillable.rb`.

- [ ] Add a real PostgreSQL lock test:

```ruby
test "retirement cannot clear a generation while a response holds its pin" do
  generation = knowledge_generations(:active)
  generation.with_pin do
    result = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { generation.reload.retire_now }
    end.value
    assert_equal :busy, result
  end
end
```

- [ ] Run pinning/retirement tests with transactional fixtures disabled only for the multi-session class; load/clean that class's dedicated fixtures explicitly. Expected RED for missing cross-session pin protection; a test running on one transactional connection is insufficient.
- [ ] Use one checked-out PostgreSQL session for shared lock acquisition/release:

```ruby
def pin_key = Digest::SHA256.hexdigest(id).first(15).to_i(16)

def with_pin
  self.class.connection_pool.with_connection do |connection|
    key = Integer(pin_key)
    connection.select_value("SELECT pg_advisory_lock_shared(#{key})")
    begin
      yield self
    ensure
      connection.select_value("SELECT pg_advisory_unlock_shared(#{key})")
    end
  end
end
```

`with_active_pin` must acquire the shared advisory lock while the settings pointer is locked, then release the row transaction before yielding for query embedding/LLM work. Do not wrap the entire network call in `settings.with_lock`. Split acquisition/release into explicit internal methods to make that order possible; use the same checked-out connection until release. Session disconnection releases a crashed worker's locks. Bound pool use and document that a response pin reserves one DB connection; do not silently require a new Redis lock system.

`Chunk.search_by_similarity` receives explicit `generation:` and `chat:`, starts from an account-scoped relation with `where(knowledge_generation_id: generation.id).where.not(embedding: nil)`, then calls that generation's embedder and cosine nearest-neighbor ordering. Materialize the array while pinned. No match means empty RAG context; identity failure means an explicit knowledge-unavailable error, not fallback embedding. Record the query usage with a per-response operation key and recognizable source model identity.

Wrap the **outer** chat response path, including direct agent-skill executions, in the generation pin; preserve it until assistant `similar_chunk_ids` are written. `complete_with_nosia` and direct skills reuse the already pinned generation, not independently read a new pointer mid-response. Streaming, stop, exceptions, and API SSE all release in `ensure`. Existing chats use the current knowledge generation per response while keeping their own chat model snapshot.

`retire_now` takes the short settings lock **before** trying the generation's nonblocking exclusive advisory lock, matching reader acquisition order; return `:busy` if pinned. Recheck active/pending references, mark retirement/fence new publishers, and release the settings row before cleanup/network work while retaining the session advisory lock. Ordinary source-indexing calls also hold shared pins through publication so cleanup cannot race them. Do not acquire the locks in reverse order or a reader and cleanup can deadlock. Retain cited chunk text/metadata and required neighbor context, respecting account ownership. Delete only this retired generation's managed Ollama alias after references/pins are gone; never remove source tags. A cited historical view must still render. Explicit user source/account deletion continues its existing destruction semantics.

- [ ] Add old-query/new-pointer concurrency, exception/stop cleanup, direct skill pin, two-dimensional/three-dimensional isolation, no cross-account distance calculation, historical citation rendering, and no deletion of user-owned tags tests. Run both files plus existing citation regressions; expected GREEN.
- [ ] Commit with `feat(knowledge): pin retrieval and preserve retired citations`.

### Checkpoint B

- [ ] Run all `test/models/knowledge` tests, a fresh-schema and legacy-width migration rehearsal in a dedicated disposable test database, and existing source/citation tests. Review lock order, stale-worker fencing, post-call identity checks and historical citation retention. Do not expose UI replacement controls or remove inference environment inputs yet.

## Task 13: Import legacy settings and content identities explicitly

**Create:** `db/migrate/20261023095000_add_chat_inference_snapshots.rb`, `app/models/inference/legacy_import.rb`, `lib/tasks/inference.rake`, `test/support/legacy_inference_fixtures.rb`, `test/models/inference/legacy_import_test.rb`, `test/upgrades/inference_configuration.rb`.

- [ ] Write the idempotent import test with a literal dummy environment:

```ruby
test "import preserves separate endpoints and never relabels old vectors" do
  env = {
    "AI_BASE_URL" => "https://legacy.example/v1", "AI_API_KEY" => "legacy-secret",
    "EMBEDDING_BASE_URL" => "https://embed.example/v1",
    "LLM_MODEL" => "legacy-chat", "LLM_TEMPERATURE" => "0.1", "LLM_MAX_TOKENS" => "1024",
    "LLM_TOP_P" => "0.9", "EMBEDDING_MODEL" => "legacy-embed", "EMBEDDING_DIMENSIONS" => "2",
    "CHUNK_SIZE" => "512", "CHUNK_OVERLAP" => "128", "RETRIEVAL_FETCH_K" => "3"
  }
  importer = Inference::LegacyImport.new(env: env, confirmed_legacy_identity: true)
  importer.run
  active = Inference::Settings.installation.active_generation
  assert_equal "legacy-embed", active.source_model_id
  assert_equal 2, active.dimensions
  assert_no_difference(["Inference::Provider.count", "Knowledge::Generation.count"]) { importer.run }
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/inference/legacy_import_test.rb`; expected RED for absent import. `LegacyInferenceFixtures` includes `ChatAccountFixtures` but not `InferenceFixtures`: it inserts one two-dimensional legacy chunk for `texts(:picker_first_text)` with account/source/content/embedding/metadata/timestamps and null generation/revision/position columns. It does not create inference settings. This is deliberate legacy-state SQL setup, not an ordinary new chunk write. Use it in the importer test class so there is real old content and no preconfigured installation.
- [ ] First add nullable `chats.inference_model_id` (25-character string/index), `inference_options` JSONB default `{}`, and `inference_serving_model_id` string in the listed migration, preserving `ruby_llm_model_id`. Run the test-only migration before the import can write snapshots. Then implement a strict importer with public `validate` and `run` methods. `validate` returns field-name errors, counts, actual vector-width set, affected accounts/sources/chats and provenance warnings; it never exposes values or mutates settings. Parse numbers with `Integer`/`Float` plus finite/range validation; normalize underscore-separated legacy numeric literals deliberately. Copy only the approved legacy keys from the provided hash into private working state. Require explicit identity confirmation before associating old vectors; a dimension mismatch or mixed/unknown provenance stops the write phase rather than truncating, padding, or regenerating content secretly.

Within one DB transaction, `run` acquires the singleton row lock, checks `imported_at`, persists encrypted connections/bindings and immutable legacy generation, backfills baseline revisions/positions/generation IDs for existing chunks, snapshots historical chat model IDs/options, then marks imported. A source that already has a journal event reuses its latest committed identity; do not append a fabricated content change on every import. Do not overwrite a completed installation or today's default with a rerun. Keep historical unknown sampling settings explicitly reported as inferred from imported effective settings.

The imported chat and embedding connections remain separate if URLs differ. Default backend kind is OpenAI-compatible to preserve the old wire protocol; an explicit operator-selected native-Ollama import mode may create independent serving aliases only after confirmation. DMR remains a compatible connection, not a Docker requirement. Ordinary import does not download models or call paid generation APIs. An unavailable legacy endpoint is reported and can be corrected through configuration without discarding its data.

Expose a deliberately explicit operator task:

```ruby
namespace :inference do
  desc "Validate and import legacy inference settings without printing secrets"
  task import: :environment do
    importer = Inference::LegacyImport.new(env: ENV,
      confirmed_legacy_identity: ENV["CONFIRM_LEGACY_EMBEDDINGS"] == "yes")
    report = importer.run
    puts JSON.pretty_generate(report)
  end
end
```

`report` contains counts/status/field names only; no URL userinfo, credentials, source text, vector arrays, or raw exception messages. `CONFIRM_LEGACY_EMBEDDINGS` is an ephemeral operator acknowledgement, not a retained inference configuration variable. Use the real Ruby parser for integer strings rather than shell evaluation. Missing required values stop with a safe actionable report; preserve effective document-merge behavior and optional disabled guards rather than silently enable them.

- [ ] Add mismatched/mixed width, missing value, invalid merge setting, two chat providers with duplicate raw IDs, interrupted transaction, repeat import, and redacted report tests. Run the standalone upgrade rehearsal only against a database name ending `_inference_upgrade_test`, rejecting all other names; exercise both fresh migration and populated legacy import. Expected GREEN, no external inference calls.
- [ ] Commit with `feat(inference): import legacy settings without losing model identity`.

## Task 14: Persist chat selections and switch every inference consumer to DB configuration

**Create:** `app/models/chat/inference_configurable.rb`, `test/models/chat_inference_test.rb`, `test/models/inference/consumer_routing_test.rb`.
**Modify:** `app/models/chat.rb`, `app/models/chat/completionable.rb`, `app/models/chat/agent_skillable.rb`, `app/models/chat/answer_relevance.rb`, `app/models/chat/context_relevance.rb`, `app/models/chat/augmented_prompt.rb`, `app/models/chat/similarity_search.rb`, `app/models/agent_skill/detector.rb`, `app/models/chunk/enrichable.rb`, `app/models/document/chunkable.rb`, `app/models/text/chunkable.rb`, `app/models/qna/chunkable.rb`, `app/models/website/chunkable.rb`, `test/test_helper.rb`, `test/support/chat_account_fixtures.rb`.

- [ ] Write the central saved-selection test:

```ruby
test "a restarted conversation keeps its selected endpoint and options" do
  selected = inference_models(:second)
  chat = @user.chats.new(account: @second)
  chat.assign_inference(selected, overrides: { "temperature" => 0.4 })
  chat.save!
  @settings.update!(default_model: inference_models(:first))
  reloaded = Chat.find(chat.id)
  reloaded.configure_inference
  assert_equal selected, reloaded.inference_model
  assert_equal 0.4, reloaded.inference_options.fetch("temperature")
  assert_equal "second-secret", reloaded.context.config.openai_api_key
  assert_equal @second, reloaded.account
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/chat_inference_test.rb test/models/inference/consumer_routing_test.rb`; expected RED for absent saved connection/options snapshot.
- [ ] Use the chat snapshot columns created in Task 13; do not replace the RubyLLM-owned `ruby_llm_model_id` association. Keep nullable legacy compatibility until explicit import finishes.

Add these public methods on the concern:

```ruby
def assign_inference(selected, overrides: {})
  self.inference_model = selected
  self.inference_options = selected.generation_options(overrides)
  self.inference_serving_model_id = selected.prepared_serving_id(inference_options)
  self.context = selected.inference_provider.context
  self.model = inference_serving_model_id
  self.provider = selected.inference_provider.descriptor.provider_slug.to_sym
  self.assume_model_exists = true
  self
end

def configure_inference
  raise Inference::SelectionError.new("inference_not_configured", 503) unless inference_model
  inference_model.configure(self, options: inference_options,
    serving_model_id: inference_serving_model_id)
end

def with_inference_context
  configure_inference
  if @knowledge_generation
    yield
  else
    Knowledge::Generation.with_active_pin do |generation|
      @knowledge_generation = generation
      begin
        yield
      ensure
        @knowledge_generation = nil
      end
    end
  end
end
```

Extend `Inference::Model#configure` with optional `serving_model_id: model_id`, using that serving name only on the wire; `prepared_serving_id(options)` returns the source ID for non-Ollama/unchanged verified contexts, or the already consented/verified runtime-context profile alias from Task 6. It must not secretly create a new profile or pull a model while a normal user submits a chat. A missing prepared profile is an actionable not-ready state. Snapshot generation options once, not in a callback that invokes `with_model` recursively during saves. Always reapply context on a loaded chat before low-level `ask`/`complete`, including direct agent-skill execution.

At this point activate the generation-aware wrappers from Task 12. `complete_with_nosia` calls `with_inference_context`, enters/reuses the outer knowledge pin, and then runs its existing completion body. Direct skill entry points use the same wrapper and read-only `knowledge_generation` accessor. Preserve streaming coalescing, stop behavior, cleanup, source warnings, prompts, tool setup and usage recording. Persist retrieved chunk IDs with a saved partial assistant before a stop return so retirement cannot remove unrecorded historical citations. Attribute usage to the configured recognizable source model rather than an internal serving alias. Remove the environment-derived default model/options override. A follow-up never reads today's default chat model. Use DB settings for K/augmented context, and the pinned generation for query embeddings.

Extend the existing isolated streaming test helper to stub `with_inference_context`, `with_context`, and `with_max_output_tokens` alongside its existing preamble stubs; the coalescing-only tests must not accidentally call real providers. New routing/integration tests must run the real preamble and fake only the HTTP boundary. Update raw fixture chunk insertion to provide an explicit opted-in generation when testing the new retrieval path, without installing inference configuration globally for unrelated tests.

Guard creation explicitly calls `assign_inference(settings.guard_model, overrides: supported_zero_temperature)` on the child chat with the parent account/user; a nil guard model preserves disabled behavior. Skill detection uses that same selected guard model instead of merely checking ENV presence. Enrichment builds an isolated context chat configured from the default binding with its small per-call output cap. Do not rewrite guard scoring or skill algorithms. Replace raw upstream error logging with safe class/code messages.

Normal source `chunkify!` now resolves the active generation and current committed revision, calls `index_source_now`, and updates existing source index status only when publication succeeds. Missing inference configuration keeps the source pending and exposes setup-required rather than generating with a RubyLLM global default. Preserve source parsing/crawling behavior and tenant boundaries.

- [ ] Add first/follow-up turns, default changes between enqueue/perform, two same-provider connections, guard disabled/enabled, direct skills, enrichment, account isolation, unknown context profile and chosen-model token attribution tests. Update old API/streaming fixture helpers to supply explicit DB configuration and generation IDs; do not retain a production ENV fallback to make old tests pass. Run both new files plus original chat/skill/source/citation regressions; expected GREEN.
- [ ] Commit with `feat(chat): retain provider and generation settings per conversation`.

## Task 15: Publish unambiguous API model IDs and preserve completion contracts

**Create:** `test/controllers/api/v1/inference_models_test.rb`, `test/controllers/api/v1/inference_selection_test.rb`.
**Modify:** `app/controllers/api/v1/models_controller.rb`, `app/controllers/api/v1/completions_controller.rb`, `test/controllers/api/v1/completions_controller_test.rb`.

- [ ] Add these API regressions using the existing bearer-token helper:

```ruby
test "ambiguous legacy selection is rejected before a chat or stream exists" do
  assert_no_difference "Chat.count" do
    post "/v1/chat/completions", params: {
      model: "picker-test-model", messages: [{ role: "user", content: "hello" }], stream: true
    }, headers: auth_headers, as: :json
  end
  assert_response :bad_request
  assert_equal "ambiguous_model", response.parsed_body.dig("error", "code")
  refute_includes response.body, "first-secret"
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/controllers/api/v1/inference_models_test.rb test/controllers/api/v1/inference_selection_test.rb`; expected RED for current raw ENV catalog/routing.
- [ ] Use the binding's canonical public ID and resolve before creating any chat:

```ruby
# Api::V1::ModelsController#index
render json: { object: "list", data: Inference::Model.ready_chat.map { |model|
  { id: model.public_id, object: "model", owned_by: "nosia" }
} }

# At the beginning of completions#create, after token/account authentication:
selected = Inference::Model.resolve(completion_params[:model])
@chat = @user.chats.new(account: @account)
@chat.assign_inference(selected, overrides: completion_params.to_h.slice(
  "max_tokens", "temperature", "top_k", "top_p"))
@chat.save!
```

Keep existing prompt/messages validation and message-history staging. Do not pass the raw `model` string back into the completion method or read ENV in the SSE/nonstream response. Report `selected.public_id` in both paths, preserving `data: ...`, blank-line framing and `[DONE]` on success. Convert `SelectionError` into the spec's safe structured error before stream commitment. Once bytes have been sent, report a safe SSE error event then close; do not replay another provider or pretend the HTTP status changed. Do not retry a partially delivered completion.

If no `model` is supplied, resolve the current default once and snapshot its effective options on this chat. Unique bare IDs and `nosia:<raw>` remain accepted; ambiguous bare IDs fail. Explicit canonical unknown/unavailable/nonchat IDs fail 400 `model_not_found`; no defaults fail 503 `inference_not_configured`. Preserve API-token account/user rules, English API responses, rate limiting and unrelated 422 input validation.

- [ ] Add duplicate catalog IDs, canonical selection, unique legacy compatibility, omitted-default snapshot, unsupported option, redacted 503, SSE-after-first-chunk failure, English-locale invariance and accurate response/model attribution cases. Run all API completions/model tests; expected GREEN with one provider request per successful user prompt.
- [ ] Commit with `feat(api): route canonical configured-model identifiers`.

## Task 16: Expose admin-only REST resources with safe validation

**Create:** `app/controllers/inference/base_controller.rb`, `app/controllers/inference/providers_controller.rb`, `app/controllers/inference/provider_tests_controller.rb`, `app/controllers/inference/catalog_refreshes_controller.rb`, `app/controllers/inference/model_preparations_controller.rb`, `app/controllers/inference/defaults_controller.rb`, `app/controllers/inference/knowledge_configurations_controller.rb`, `app/controllers/inference/rebuilds_controller.rb`, `app/controllers/inference/downloads_controller.rb`, `app/controllers/inference/retries_controller.rb`, `test/controllers/inference/administration_test.rb`.
**Modify:** `config/routes.rb`, `app/controllers/models_controller.rb`.

- [ ] Write authorization and expensive-operation consent tests:

```ruby
test "an ordinary user cannot change installation defaults" do
  sign_in_picker_user
  patch "/inference/default", params: { inference_settings: { default_model_id: inference_models(:second).id } }
  assert_response :forbidden
  assert_equal inference_models(:first), @settings.reload.default_model
end

test "knowledge edits do not launch an unconfirmed rebuild" do
  @user.update!(admin: true)
  sign_in_picker_user
  assert_no_difference "Knowledge::Rebuild.count" do
    patch "/inference/knowledge_configuration", params: { knowledge: { dimensions: 1024 } }
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/controllers/inference/administration_test.rb`; expected RED because protected resources do not exist.
- [ ] Add conventional routes; replace the old custom models refresh action with a refresh resource:

```ruby
namespace :inference do
  resources :providers, except: [:show] do
    resource :test, only: :create, controller: "provider_tests"
    resource :catalog_refresh, only: :create, controller: "catalog_refreshes"
  end
  resource :default, only: :update, controller: "defaults"
  resources :model_preparations, only: [:create, :show] do
    resource :retry, only: :create, controller: "retries"
  end
  resource :knowledge_configuration, only: [:show, :update], controller: "knowledge_configurations"
  resources :rebuilds, only: [:create, :show, :destroy] do
    resource :retry, only: :create, controller: "retries"
  end
  resources :downloads, only: :show do
    resource :retry, only: :create, controller: "retries"
  end
end
resource :inference_setup, only: [:show, :update]
```

`Inference::BaseController` authenticates via the existing concern and returns 403 unless `Current.user.admin?`. Every mutation repeats the check server-side; hiding a button is not authorization. Scope resource lookups to installation-global metadata deliberately, never through another user's source account. Permit exact typed fields and optimistic `lock_version`; never mass-assign state, verification timestamps, generation IDs, credentials from another provider, or operational attempt tokens.

Provider tests/catalog refreshes are connection/auth/metadata operations, not paid chat probes. Provider endpoint edits call the revision method, preserving referenced identities; secret rotation stays on the same identity. `ModelPreparationsController#create` requires explicit download/probe consent and calls the Task 6A preparation contract; its show action renders saved status. This lets an admin ready new models at any time without repeating first signup. `DefaultsController#update` accepts only a ready configured chat model plus validated prepared options and optional ready guard selection. Knowledge `update` validates a draft and renders an impact review; only a confirmed `RebuildsController#create` starts replacement. Retrieval-K-only edits update settings directly without a rebuild. Cancellation/retry call model methods with stale-state checks. `RetriesController#create` chooses a download, model preparation or rebuild only from its explicit nested route parameter, not a client-supplied class name.

Return HTML/Turbo 422 with preserved nonsecret form inputs and linked errors, 409 for stale edits/in-progress conflict, and redirects on successful updates. Keep drafts separate from active settings. Progress endpoints are admin-only, render persisted state, and are safe to refresh/revisit; operation diagnostics never contain raw upstream bodies. Normal `/models` browsing exposes only safe names/capabilities/public identifiers and ready model selection, without endpoints, credentials or admin diagnostics.

- [ ] Add signed-out/nonadmin/admin cases for every mutation route, forged verification/credential fields, stale lock versions, referenced connection deletion, model-role mismatch, failed provider test redaction and catalog no-paid-probe cases. Rerun the file; expected GREEN.
- [ ] Commit with `feat(inference): expose protected configuration resources`.

## Task 17: Add resumable first-admin onboarding and confirmed preparation

**Create:** `db/migrate/20261023100000_create_inference_setups.rb`, `app/models/inference/setup.rb`, `app/jobs/inference/preparation_job.rb`, `app/controllers/inference_setups_controller.rb`, `app/controllers/concerns/inference_ready.rb`, `test/controllers/inference_setups_controller_test.rb`, `test/models/inference/setup_test.rb`.
**Modify:** `app/controllers/first_runs_controller.rb`, `app/controllers/chats_controller.rb`, `app/controllers/dashboards_controller.rb`, `app/controllers/messages_controller.rb`, `app/controllers/sources/documents_controller.rb`, `app/controllers/sources/texts_controller.rb`, `app/controllers/sources/qnas_controller.rb`, `app/controllers/sources/websites_controller.rb`, `app/models/inference/settings.rb`.

- [ ] Write red first-run/preparation tests:

```ruby
test "confirming setup is required before downloads or paid probes" do
  setup = Inference::Setup.create!(creator: @user, step: "models", draft: {})
  assert_no_enqueued_jobs do
    setup.update!(draft: { "embedding_model" => "qwen3-embedding:8b", "dimensions" => 4096 })
  end
  assert_nil setup.confirmed_at
end

test "failed preparation can resume without creating another account" do
  setup = Inference::Setup.create!(creator: @user, step: "review", draft: valid_setup_draft)
  setup.confirm
  assert_equal "preparing", setup.reload.step
  assert_equal @user, setup.creator
end
```

- [ ] Run setup model/controller files. Expected RED for absent persisted wizard and first-run redirect.
- [ ] Create `inference_setups` with UUID-string ID, creator bigint/index, unique installation `key`, `step`, draft JSONB, selected chat/embedding binding IDs, pending generation/rebuild IDs, confirmed/completed timestamps, safe error code, lock version/timestamps. Use steps `connect`, `models`, `review`, `preparing`, `complete`; changing a model-affecting draft invalidates its old confirmation, not a working active generation.

Use explicit after-commit preparation:

```ruby
def confirm
  with_lock do
    validate_review!
    update!(confirmed_at: Time.current, step: "preparing")
    ActiveRecord.after_all_transactions_commit { Inference::PreparationJob.perform_later(id) }
  end
end

class Inference::PreparationJob < ApplicationJob
  queue_as :background
  def perform(id)
    Inference::Setup.find(id).prepare_now
  end
end
```

`validate_review!` checks required provider/model choices, strict chunk/dimension values, RAM provenance, acknowledged memory/unknown-size warnings, and explicit confirmation payload. `prepare_now` reuses the Task 6A model-preparation operation, idempotently requests missing downloads, waits by re-enqueue/checkpoints rather than blocking a worker on another queued job, prepares verified embedding aliases, starts/reuses the pending knowledge rebuild, and completes only after both chat and knowledge are ready. Finalize default binding/options and onboarded timestamp atomically; a failed probe/build keeps setup editable/retryable and never labels an unverified model ready. Do not hold DB locks during provider calls.

First-admin signup redirects to `inference_setup_path`; subsequent sign-ins resume an unfinished setup. `InferenceReady` protects chat/runtime entry points without redirect loops: administrators can reach setup/models/provider editing, account/profile/language controls and logout; ordinary users see a safe setup-required waiting response rather than admin forms; APIs return their explicit 503 JSON contract. Do not rerun first signup or block `db:prepare`/health checks on absent inference configuration. A valid imported installation is considered configured without forced model replacement.

- [ ] Test native/Docker default endpoint suggestions, memory confirmation, three-step field retention, browser reload, confirmed downloads, preparation retry after worker restart, embedding probe failure, already-imported setups, no-admin secrets and first signup/account counts. Run setup and first-run tests; expected GREEN.
- [ ] Commit with `feat(onboarding): guide and resume inference preparation`.

## Task 18: Build the selected workspace, typed forms, progress and model picker

**Create:** `app/helpers/models_helper.rb`, `app/views/models/_navigation.html.erb`, `app/views/models/_overview.html.erb`, `app/views/models/_catalog.html.erb`, `app/views/inference/providers/index.html.erb`, `app/views/inference/providers/new.html.erb`, `app/views/inference/providers/edit.html.erb`, `app/views/inference/providers/_form.html.erb`, `app/views/inference/model_preparations/show.html.erb`, `app/views/inference/shared/_errors.html.erb`, `app/views/inference/shared/_progress.html.erb`, `app/views/inference/knowledge_configurations/show.html.erb`, `app/views/inference/rebuilds/show.html.erb`, `app/views/inference/downloads/show.html.erb`, `app/views/inference_setups/show.html.erb`, `app/views/chats/_model.html.erb`, `app/assets/stylesheets/nosia/inference.css`, `app/javascript/controllers/inference_errors_controller.js`, `app/javascript/controllers/inference_progress_controller.js`, `config/locales/en.nosia_inference.yml`, `config/locales/fr.nosia_inference.yml`, `test/integration/inference_pages_test.rb`.
**Modify:** `app/views/models/index.html.erb`, `app/views/models/_model.html.erb`, `app/views/chats/_composer.html.erb`, `app/views/chats/_form.html.erb`, `app/views/messages/_form.html.erb`, `app/controllers/chats_controller.rb`, `app/controllers/dashboards_controller.rb`, `app/assets/tailwind/application.css`.

- [ ] Add rendering assertions before changing templates:

```ruby
test "a normal user can choose a ready model without seeing connection secrets" do
  sign_in_picker_user
  get "/chats/new"
  assert_response :success
  assert_select "select[name='chat[inference_model_id]'] option[value=?]", inference_models(:second).id
  refute_includes response.body, "first-secret"
  refute_includes response.body, "https://first.example"
end

test "an embedding change review explains that current search remains active" do
  @user.update!(admin: true)
  sign_in_picker_user
  get "/inference/knowledge_configuration"
  assert_select "[data-inference-impact]"
  assert_select "input[name='confirmation']", count: 0
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/integration/inference_pages_test.rb`; expected RED for missing selected layout/typed controls.
- [ ] Implement Overview/Providers/Catalog/Advanced navigation under `/models`, matching the approved mockup, not a new brand. Add standard new/edit/index provider templates rendering the shared form; define model/knowledge settings as focused forms rather than one global save. Every new label/error/status string is in both locale files. Use the active defaults and pending operations as separate visible states. Show installed/available/download-needed/incompatible statuses with text, not color alone; retain existing useful price/context/consumption information in the catalog/detail pages.

The provider form renders descriptor fields with their correct type; saved secrets display a “configured” hint and an empty replacement field, never their plaintext value. Provide explicit secret clearing and role-specific help. Required auth mode fields are visible without exposing executable/object inputs. Put errors in this shared component:

```erb
<% if record.errors.any? %>
  <div role="alert" tabindex="-1" data-controller="inference-errors" aria-labelledby="inference-errors-title">
    <h2 id="inference-errors-title"><%= t("nosia.inference.errors.title") %></h2>
    <ul>
      <% record.errors.each do |error| %>
        <li><%= link_to error.full_message, "##{field_ids.fetch(error.attribute, form_id)}" %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

`inference_errors_controller.js` only focuses this server-rendered error region on connection. Preserve inline errors with `aria-describedby`/`aria-invalid`. Use unique summary/title IDs per form rather than duplicate global IDs if multiple forms render together.

Progress frames show stage, actual done/total counts, known/unknown download size, safe error code and retry/cancel controls. `inference_progress_controller.js` reloads its Turbo Frame on a bounded timer only while the server-rendered operation is queued/running, clears timers on disconnect, and stops after terminal state. The frame's authenticated `src` is the only fetch target; never interpolate an inference endpoint into the browser. Reconnect/reload reads persisted state. Use `aria-live="polite"` for stage changes and avoid announcing every streamed byte.

Use this composer partial pattern:

```erb
<% if chat.persisted? %>
  <span class="n-inference-chat-model"><%= chat.inference_model.name %></span>
<% else %>
  <div class="n-inference-chat-model">
    <%= form.label :inference_model_id, t("nosia.inference.chat_model") %>
    <%= form.collection_select :inference_model_id, available_models, :id, :display_name,
          { selected: selected_model_id }, { disabled: generating } %>
  </div>
<% end %>
```

Define `Model#display_name` as safe model name plus connection label. `available_models`/`selected_model_id` are explicit locals from controllers, not hidden request-only instance state in background-rendered forms. Saved-message composers render a read-only model; they must not post a replacement model. Remove the old raw-model hidden field. New-chat creation resolves the posted binding against ready chat models and calls `assign_inference`; a URL-selected canonical model goes through the same resolver. Account changes preserve the selected model when still ready and do not bypass existing draft/source reset confirmation.

Scope CSS to `.n-inference-*`, import it from the existing Tailwind entrypoint, and reuse neutral/green tokens, SVGs and fonts. At 375px forms/cards wrap with no horizontal overflow; long connection/model names cannot shrink Send/Stop controls out of view. Test light/dark text contrast, visible keyboard focus, disabled semantics, reduced motion and 200% zoom. Advanced guards, top K, peer merging and augmented context remain findable but not prominent onboarding fields.

- [ ] Rerun page rendering, localization and composer regression tests. Add both-language empty/failed/preparing/ready states, secret masking, inline/summary associations, current-default label, catalog filtering, and rendering without request-scoped `Current`. Expected GREEN.
- [ ] Commit with `feat(ui): add guided model workspace and chat picker`.

## Task 19: Prove the user journeys with offline system tests

**Create:** `test/system/inference_onboarding_test.rb`, `test/system/inference_management_test.rb`, `test/system/inference_chat_selection_test.rb`.
**Modify:** `test/support/inference_fixtures.rb`, `test/system/chat_composer_ui_test.rb`, `test/system/chat_account_selection_test.rb`, `test/system/localization_test.rb` only where their explicit inference setup is required by the new DB configuration boundary.

- [ ] Write this new-chat selection journey before polishing the UI:

```ruby
test "changing the default does not reroute an existing conversation" do
  sign_in_inference_browser
  visit "/chats/new"
  select inference_models(:second).display_name, from: I18n.t("nosia.inference.chat_model")
  fill_in_composer "Explain this document"
  click_button I18n.t("nosia.chat.send")
  assert_text inference_models(:second).name
  @settings.update!(default_model: inference_models(:first))
  visit current_path
  assert_text inference_models(:second).name
  assert_no_selector "select[name='chat[inference_model_id]']"
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/system/inference_chat_selection_test.rb`; expected RED for any missing real interaction, not a skipped/missing browser. The Rails test runner accepts an explicit system-test file and still uses `ApplicationSystemTestCase`.
- [ ] Keep fixture/provider stubs at the HTTP boundary and implement the following concrete journeys as additional tests: first signup enters setup exactly once; reload resumes selected providers/models; opening review performs no pull; confirmation starts only missing downloads; fragmented progress reaches completion; failed preparation retains fields and retries; a new embedding generation serves old search until atomic cutover; a nonadmin cannot open configuration/progress routes; provider key replacement/clear remains masked; no-inference normal-user waiting state is actionable. Define `fill_in_composer(text)` using the existing Lexxy editing helper, not a plain textarea assumption. Persist user state through real controller requests; do not stub controller/model success responses.

For browser login, use this helper rather than the integration-session POST helper (Rack-session cookies do not sign Selenium in):

```ruby
def sign_in_inference_browser
  visit root_url
  fill_in "email", with: @user.email
  fill_in "password", with: ChatAccountFixtures::PASSWORD
  find("form[action='/login'] button[type='submit']").click
end

def fill_in_composer(text)
  assert_selector "lexxy-editor[connected]"
  find("lexxy-editor .lexxy-editor__content").send_keys(text)
end
```

The responsive/accessible checks use actual browser operations:

```ruby
page.current_window.resize_to(375, 812)
assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [
  { name: "prefers-reduced-motion", value: "reduce" }
])
```

Also run a desktop viewport, long names, keyboard-only form submission/error focus, dark theme and French copy. Screenshot errors/progress/default selection for review. Keep existing PDF, account switch, MCP tools, skills and Send/Stop flows covered; a model picker must not break hidden attachment namespaces or form action selection.

- [ ] Run all three system files plus `test/system/chat_composer_ui_test.rb`, existing account-selection and localization system tests. Expected GREEN in a functioning browser harness; record real blockers instead of marking unrun tests passed.
- [ ] Commit with `test(inference): cover onboarding and safe model switching`.

## Task 20: Remove inference deployment inputs only after proving the import path

**Create:** `test/packaging/inference_configuration.rb`, `docs/inference-providers.md`, `docs/upgrades/inference-configuration.md`.
**Modify:** `docker-compose.yml`, `.env.example`, `install.sh`, `install.ps1`, `config/initializers/ruby_llm.rb`, `.github/workflows/ci.yml`, `README.md`, `docs/DEPLOYMENT.md`, `docs/ARCHITECTURE.md`, `docs/DIAGRAMS.md`, `docs/README.md`.

- [ ] Write standalone red packaging assertions:

```ruby
require "minitest/autorun"
require "yaml"

class InferenceConfigurationPackagingTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  REMOVED_KEYS = /\A(?:AI_BASE_URL|AI_API_KEY|LLM_\w+|EMBEDDING_\w+|GUARD_MODEL|CHUNK_\w+|RETRIEVAL_FETCH_K|AUGMENTED_CONTEXT)\z/

  def test_compose_has_no_required_model_runner_or_inference_environment
    compose = YAML.safe_load(File.read(File.join(ROOT, "docker-compose.yml")))
    refute compose.key?("models")
    compose.fetch("services").each_value do |service|
      refute service.key?("models")
      Array(service["environment"]).each do |assignment|
        refute_match REMOVED_KEYS, assignment.split("=", 2).first
      end
    end
    assert_includes compose.fetch("services").fetch("web").fetch("extra_hosts"), "host.docker.internal:host-gateway"
  end
end
```

- [ ] Run `bundle exec ruby test/packaging/inference_configuration.rb`; expected RED because Compose currently requires DMR/models and inference variables.
- [ ] Remove model declarations and all listed inference variables from checked-in Compose, db-migrate/web/worker environments, `.env.example`, and both installer-generated outputs. Preserve database/encryption/application configuration, Caddy trust behavior, volumes, health checks and service ordering. Add host-gateway mappings for both web and workers; do not start an Ollama container or expose unauthenticated host port 11434 publicly. Installers finish at the application onboarding URL and explain that host Ollama must be installed/running if selected; they no longer select/pull models or configure inference in `.env`.

The final RubyLLM initializer has no model/credential/environment configuration:

```ruby
RubyLLM::MCP.configure do |config|
  config.resource_url_validator = ->(url) { UrlGuard.verify!(url) }
end
```

Keep global transport-safe logging configuration from Task 3 separately; do not remove the MCP resource guard. After import is available, no normal app/model/controller/worker code may read inference ENV keys or use a global default model. Leave legacy key parsing only in the explicit importer/tests/historical documentation. Search the actual repository for all references, including startup scripts and packaging, before concluding removal.

Add the packaging test for shell and PowerShell generated Compose/environment templates, no Docker Model Runner installation/check/pull commands, native/Docker host hints, migration boot with no inference values, and preserved infrastructure secrets. Do not edit the user's preexisting untracked `test/packaging/embedding_dimensions.rb`; identify its old assertion as intentionally superseded in the feature's verification notes. In a clean execution worktree it is not part of tracked CI.

Update CI to use the pgvector PostgreSQL image needed by the actual schema and run the new standalone packaging checks in its Unix/Windows lanes. Do not invent `bin/ci` or replace unrelated existing CI checks.

Document exactly: supported provider/auth kinds; install-wide admin scope; memory-estimate limitations; model/download defaults and consent; optional guards; canonical API IDs and ambiguous legacy errors; 4096-dimensional exact-search trade-off; independent serving aliases; source changes/rebuild/cancel/retry; safe host access; and the backup → compatibility migration → confirmed import → DB-configured smoke check → legacy input removal ordering. Include rollback-by-backup, not a destructive vector cast.

- [ ] Run the standalone packaging file, `sh -n install.sh`, `docker compose config` with dummy infrastructure-only values, existing tracked packaging tests, and the native Windows parser/tests in the Windows CI lane. The documentation must explicitly forbid deleting existing `.env` inference entries until import succeeds. Any actual local `.env` cleanup happens only during the later user-selected execution/upgrade, preserves unrelated entries, and never prints their values.
- [ ] Commit with `feat(deploy): replace required model runner with UI-managed inference`.

## Task 21: Document public contracts and run the final fidelity/security gates

**Modify:** New public Ruby methods' inline documentation, `docs/inference-providers.md`, `docs/upgrades/inference-configuration.md`; only fixes belonging to the preceding tasks.

- [ ] Add YARD documentation for public connection/context, selection, setup, generation/indexing, rebuild and importer APIs. For example:

```ruby
# Resolve a public or unambiguous legacy chat-model identifier.
# @param identifier [String, nil] Canonical binding ID, legacy model ID, or nil for the default
# @param settings [Inference::Settings] Installation defaults to resolve once
# @return [Inference::Model] Ready connection-qualified chat model
# @raise [Inference::SelectionError] If absent, incompatible, or ambiguous
```

- [ ] Run `bin/rubocop`, `bin/brakeman --no-pager`, and `bin/importmap audit` separately. Expected: no newly introduced lint/security/dependency issues. Do not auto-fix unrelated files, upgrade gems or suppress warnings without reviewing the underlying issue.
- [ ] Run `PARALLEL_WORKERS=1 bin/rails test`, all new/affected system tests, and `PARALLEL_WORKERS=1 bin/rails test:system` in the established test-only database/browser harness. Run `bundle exec ruby test/upgrades/inference_configuration.rb` and all tracked packaging tests. Record exact command results; known baseline failures stay explicitly identified, never relabeled as passing.
- [ ] Manually verify concurrent same-provider requests, secret redaction under debug logging, no DNS/IP pin bypass, no mutation route reachable by a nonadmin, no destructive live dimension DDL, no stale-generation activation, and no account leakage in source manifests/citations. Use fake providers for automated tests; live local-provider smoke tests require explicit user consent and must not download models silently.
- [ ] Review the implementation against the coverage matrix below with Rails architecture/security review and request a task-level code review before integration. Confirm every production behavior was preceded by a test run that failed for the right reason, all new public APIs are documented, and the migration/import deployment order is executable. Create no PR, merge, deployment, or forced cleanup without the user's selected completion action.
- [ ] Commit only scoped final fixes with a descriptive conventional commit after rerunning their affected tests. Leave the feature branch/worktree available for user review; do not delete it or the original workspace's changes.

## Specification coverage and release checklist

| Approved requirement | Tasks | Required evidence |
| --- | --- | --- |
| Every installed RubyLLM provider plus optional DMR; multiple encrypted connections | 1–4, 16, 18 | Native-provider descriptor/auth matrix, ciphertext/redaction, context/socket isolation tests. |
| No required DMR, inference ENV, or Ollama executable inside Rails | 6, 13, 20 | Offline HTTP operations, confirmed import rehearsal, generated Unix/Windows packaging assertions. |
| First-signup setup, resumability, later `/models` management | 16–19 | Real signup/setup/reload/retry and admin/nonadmin browser flows. |
| Qwen embedding defaults, 4096 dimensions, chunk/overlap/K controls | 5, 7–10, 17–18 | Strict defaults/width probes, character units, parameter persistence and effective chunk boundaries. |
| Host-memory provenance, installed-first recommendations, disclosed automatic pulls | 5–6, 17–19 | Deterministic RAM/headroom tests, no pull before consent, restart-safe progress. |
| Supported temperature/output/top P and advanced top K | 4–6, 14, 18 | Actual request shape across supported protocols, context-profile verification, output limits. |
| Default edits affect new chats only; per-chat provider/model/options survive workers | 14–15, 18–19 | First/follow-up/restarted-job and canonical API request tests. |
| Optional guards and all existing inference consumers use DB contexts | 14, 20 | Guard/skill/enrichment/query/indexing routing tests and no normal-runtime inference ENV references. |
| Explicit embedding impact warning and background replacement | 7–12, 16, 18–19 | Same-width identity change, different dimensions, chunk changes, live old search and retry/cancel tests. |
| Independent Ollama serving identities and fail-closed drift | 6, 8, 12 | Base-tag re-pull, wrong/deleted alias, endpoint revision and safe managed-alias retirement tests. |
| Source edits/deletes, atomic activation, pinned reads, historical citations | 9–12 | Real multi-session barriers, stale-worker fences, retained citation text, explicit deletion semantics. |
| Preserve existing deployments and fresh boot without inference inputs | 7, 13, 20 | Legacy/fresh schema+import rehearsal, redacted report, no old model relabeling. |
| Existing account/MCP/PDF/skills/streaming/localization preserved | 14–15, 18–19, 21 | Original regression suites plus English/French, light/dark, keyboard, reduced-motion and narrow-layout checks. |

## Test-support implementation reference

Add the following support definitions in their owning tasks; these are opt-in test utilities, not production factories or global fixtures. The YAML fixture values are the fixed IDs/data described in Tasks 2 and 7.

`test/support/inference_fixtures.rb`:

```ruby
require_relative "chat_account_fixtures"

module InferenceFixtures
  extend ActiveSupport::Concern
  include ChatAccountFixtures

  included do
    setup do
      @inference_fixtures = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/inference").to_s,
        %w[ruby_llm_models inference_providers inference_models inference_settings],
        { "ruby_llm_models" => "RubyLLM::ActiveRecord::Model",
          "inference_providers" => "Inference::Provider", "inference_models" => "Inference::Model",
          "inference_settings" => "Inference::Settings" }
      ).index_by(&:name)
      @settings = inference_settings(:installation)
    end
  end

  %w[inference_providers inference_models inference_settings].each do |table|
    define_method(table) do |name|
      @inference_fixtures.fetch(table).fixtures.fetch(name.to_s).find
    end
  end

  def auth_headers
    @inference_api_token ||= ApiToken.create!(account: @first, user: @user, name: "Inference test")
    { "Authorization" => "Bearer #{@inference_api_token.plain_token}" }
  end

  def valid_setup_draft
    { "chat_model_id" => inference_models(:first).id,
      "embedding_model_id" => inference_models(:embedding).id,
      "dimensions" => 2, "chunk_size" => 512, "chunk_overlap" => 128,
      "retrieval_fetch_k" => 3, "ram_bytes" => 32 * 1024**3,
      "ram_confirmed" => true, "warnings_acknowledged" => true }
  end
end
```

The dummy `valid_setup_draft` intentionally uses a tiny verified test model; fresh-setup default assertions separately require Qwen/4096 and must not be weakened to this helper's values. Use request-fixture mapping, not a real provider, to probe it.

`test/support/knowledge_fixtures.rb`:

```ruby
require_relative "inference_fixtures"

module KnowledgeFixtures
  extend ActiveSupport::Concern
  include InferenceFixtures

  included do
    setup do
      @knowledge_fixtures = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/knowledge").to_s, ["knowledge_generations"],
        { "knowledge_generations" => "Knowledge::Generation" }
      ).index_by(&:name)
      @settings.update!(active_generation: knowledge_generations(:active), onboarded_at: Time.current)
      if ActiveRecord::Base.connection.table_exists?(:knowledge_revisions) && defined?(Knowledge::Revision)
        ActiveRecord::FixtureSet.create_fixtures(
          Rails.root.join("test/support/fixtures/knowledge").to_s, ["knowledge_revisions"],
          { "knowledge_revisions" => "Knowledge::Revision" }
        )
        @settings.update!(source_sequence: Knowledge::Revision.maximum(:sequence) || 0)
      end
    end
  end

  def knowledge_generations(name)
    @knowledge_fixtures.fetch("knowledge_generations").fixtures.fetch(name.to_s).find
  end

  def create_pending_generation(dimensions: 2)
    generation = knowledge_generations(:active).dup
    generation.id = nil
    generation.dimensions = dimensions
    generation.state = "draft"
    generation.verified_at = nil
    generation.serving_model_id = nil
    generation.serving_digest = nil
    generation.save!
    generation.update!(serving_model_id: "nosia-embedding-#{generation.id}:managed",
      serving_digest: "fixture-weights", verified_at: Time.current, state: "building")
    generation
  end

  def insert_knowledge_chunk(generation, vector, account: @first,
      source: texts(:picker_first_text), content: "fixture")
    result = Chunk.insert_all!([{ account_id: account.id, chunkable_type: source.class.name,
      chunkable_id: source.id, knowledge_generation_id: generation.id,
      source_revision_sequence: 1, position: 1, content: content, embedding: vector,
      metadata: { "position" => 1 }, created_at: Time.current, updated_at: Time.current }])
    account.chunks.find(result.rows.first.first)
  end

  def with_fake_embeddings(generation, vectors:)
    results = vectors.each
    replacement = lambda do |_text, operation_key:|
      Struct.new(:vectors, :tokens).new(results.next, Struct.new(:input).new(1))
    end
    with_singleton_replacement(generation, :embed, replacement) { yield }
  end
end
```

Generation fixture `active` uses ID `0000000000000000000000031`, binding `0000000000000000000000013`, source model `fixture-embedding`, serving alias `nosia-embedding-0000000000000000000000031:managed`, digest `fixture-weights`, dimensions 2, size/overlap 512/128, ready state and a verified timestamp. Add the conditional revision-fixture branch only in Task 9 when creating its YAML file; it lets the earlier storage task run before the journal exists, without creating a production fallback. Revision fixtures represent the two existing text sources with sequences 1/2, their real account/source IDs and `knowledge_digest` computed from their current stored fixture content. The raw insertion helper deliberately does not fabricate a production revision.

For identity tests, `with_fake_ollama(base_digest:, aliases:)` constructs a test client with methods `tags` (array of string-keyed name/digest hashes), `show` (verified metadata), `copy` (copy digest under a new alias), `pull` (yield deterministic events and update only the source name), and `delete_managed_alias` (record requested name). Replace only `Inference::Provider::Ollama.new` for the block, restoring it through `with_singleton_replacement`. Capture a separate real HTTP-adapter test for every method, especially fragmented NDJSON, so a fake client cannot conceal an incorrect wire format. Use actual `generation.embed` for alias-selection/digest tests; `with_fake_embeddings` is only for source publication/concurrency tests.

## Plan self-review and handoff

The written specification was approved before planning. Inline self-review checked every coverage-matrix row, incomplete-instruction markers, paths, fixture identities and cross-task method signatures. It corrected the ongoing model-preparation path, chat-column/import ordering, source deletion journaling, fixture label mismatches and advisory-lock ordering. The 47 Ruby code blocks were syntax-checked with Ripper, the YAML example parsed, and Markdown fences checked without running application code. This was an inline self-review, not a new agent dispatch. Plan code is an execution guide; no production code, migrations, application tests, live configuration, or downloads have been run/applied by writing this document.

Offer the user two execution choices only after the plan is saved and reviewed:

1. **Subagent-driven (recommended):** `subagent-driven-development`, fresh task workers and reviews between tasks, respecting dependencies and migration checkpoints.
2. **Inline execution:** `executing-plans`, execute task batches in this session with explicit checkpoint reviews.

Wait for the user's selection. Neither the specification approval nor the planning step selects an execution mode, creates a PR, or authorizes deployment.
