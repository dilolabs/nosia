# Chat Account Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users choose an account in the new-chat composer footer and consistently use that account throughout the conversation.

**Architecture:** Keep the existing `Chat#account` association as the source of truth. Authorize account/chat context in a focused controller concern, validate resource references before persistence, and use bounded tenant contexts for tools/skills. A small account-selection Stimulus controller coordinates confirmed draft resets, uploads, and Turbo history; generation and broadcasts use the saved chat account.

**Tech Stack:** Existing Ruby 4 / Rails 8.0 application, PostgreSQL/pgvector, RubyLLM 2, Turbo/Stimulus with importmap, Lexxy 0.9.23, Solid Queue, Minitest and Selenium. Do not upgrade dependencies or change the schema as part of this feature.

---

## Approved specification and execution boundary

Read `docs/superpowers/specs/2026-10-14-chat-account-selection-design.md` first. The user approved the written spec with "Go"; this plan is the next deliverable, not permission to start implementation before the execution handoff.

Preserve the existing `Procfile.dev` modification and untracked July/September planning documents. Never stage them with a broad `git add`. Implement in an isolated worktree using `using-git-worktrees`; the planning documents themselves were prepared in the current workspace. Do not run schema resets or copy production/development databases. All database preparation/testing below is explicitly test-only.

Observed repository facts override generic stack examples: `.ruby-version` is `4`, Rails is currently `8.0.5.1`, the schema has bigint IDs, and `chunks.embedding` currently has width 4096. Read the actual column width in retrieval tests, not an assumed 768-vector. Do not introduce UUID migrations, remove existing foreign keys, switch databases, add Node, or add services/policies.

## File map

| Files | Responsibility |
| --- | --- |
| `app/controllers/concerns/chat_account_scoped.rb` | Membership-scoped new-account resolution, owned-chat authorization, missing-account response. |
| `app/controllers/dashboards_controller.rb`, `app/controllers/chats_controller.rb` | Selected-account rendering and new-chat creation. |
| `app/controllers/messages_controller.rb`, `app/controllers/chat_sources_controller.rb`, `app/controllers/chat_mcp_sessions_controller.rb` | Saved-chat source/message/tool account authority. |
| `app/controllers/chunks_controller.rb` | Chat-context citation lookup with default-account compatibility. |
| `app/controllers/sources/documents_controller.rb` | Preserve filing-account checks; handle no-account upload rejection. |
| `app/models/chat/account_scoped.rb`, `app/models/chat.rb` | Account immutability and validated source/tool reference snapshots. |
| `app/models/chat/model_context_protocol.rb`, `app/jobs/chat_response_job.rb` | Bounded tenant contexts for chat tools and background generation. |
| `app/models/message.rb` | Account-scoped cited chunks. |
| `app/helpers/chats_helper.rb`, `app/helpers/agent_skills_helper.rb` | Materialized selected-account tool/skill options. |
| `app/views/chats/_account.html.erb`, `app/views/chats/_no_account.html.erb` | Footer selector/read-only label and empty state. |
| `app/views/chats/_form.html.erb`, `app/views/messages/_form.html.erb`, `app/views/chats/_mcp_selector.html.erb` | Explicit composer context and account-scoped controls. |
| `app/views/dashboards/show.html.erb`, `app/views/chats/new.html.erb`, `app/views/chats/show.html.erb` | Account-state coordination root and dashboard upload context. |
| `app/views/messages/_search_content.html.erb`, `app/views/application/_header.html.erb` | Citation context and nil-account-safe header search. |
| `app/javascript/controllers/chat_account_controller.js` | Confirmed account changes, send guard, source-state coordination, cache reset. |
| `app/javascript/controllers/composer_sources_controller.js` | URL/PDF registration lifecycle, retry/error reporting, explicit account/chat payload. |
| `app/javascript/controllers/composer_controller.js` | Keep editing/skill behavior; remove moved source-registration responsibilities. |
| `app/javascript/controllers/dropzone_controller.js` | Optional selected-account upload parameter and source-state events. |
| `test/support/chat_account_fixtures.rb`, `test/support/fixtures/chat_accounts/*.yml` | Opt-in fixtures without changing existing suite initial data. |
| `test/controllers/chat_account_*_test.rb`, `test/models/chat_account_test.rb`, `test/system/chat_account_selection_test.rb` | Focused behavioral coverage. |
| `docs/chat-account-selection.md`, `docs/README.md` | User behavior and developer account-context contract. |

New production files stay focused: account resolution, model resource checks, account-picker coordination, and composer source registration. Extracting source registration is directly needed here: the existing composer already mixes editing, skills, upload interception, and source IDs. Keep its editing/skill code otherwise unchanged.

## Task 0: Baseline and execution workspace

- [ ] Use `using-git-worktrees` when execution is selected; create an isolated feature branch from the commit containing this plan.
- [ ] Run `git status --short` and record pre-existing changes. Expected: none in the new worktree; do not overwrite user work in the original workspace.
- [ ] Run `bundle check`. Expected: dependencies satisfied; stop and report missing environment/dependencies rather than changing `Gemfile.lock`.
- [ ] Run `RAILS_ENV=test bin/rails db:prepare`. Expected: test schema prepared, never a development/production database operation.
- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/controllers/chat_sources_controller_test.rb test/models/chat_test.rb`. Record the baseline. Existing failures are not a reason to rewrite unrelated code.
- [ ] Verify headless Chrome is available before system tasks. Run `command -v chromium` or `command -v google-chrome` separately. The existing remote driver configuration in `test/application_system_test_case.rb` is incomplete (`http://:4444`); use local Chrome for this work unless the user supplies a working remote harness. Do not silently skip new system tests.

## Task 1: Opt-in fixtures and test helpers

**Files:** Create `test/support/chat_account_fixtures.rb`, the ten fixture files below, and `test/models/chat_account_fixture_test.rb`.

- [ ] Write the fixture smoke test:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountFixtureTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  test "fixture owner has two ordered accounts and a second-account chat" do
    assert_equal "picker@example.com", @user.email
    assert_equal @first, @user.first_account
    assert_equal [ @first.id, @second.id ].sort, @user.accounts.pluck(:id).sort
    assert_equal @second, chats(:picker_second_chat).account
    assert_empty users(:picker_no_account).accounts
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/chat_account_fixture_test.rb`. Expected RED: missing feature fixture support, not a syntax error.
- [ ] Create the support module. Fixtures live outside `test/fixtures` because the existing `fixtures :all` recursively loads that directory for every old test. Do not change `test/test_helper.rb`:

```ruby
require "active_job/test_helper"

module ChatAccountFixtures
  extend ActiveSupport::Concern
  include ActiveJob::TestHelper

  PASSWORD = "picker-password-123".freeze

  included do
    setup do
      @prior_tenant = ActsAsTenant.current_tenant
      @prior_adapter = ActiveJob::Base.queue_adapter
      ActsAsTenant.current_tenant = nil
      ActiveRecord::FixtureSet.reset_cache
      @picker_fixtures = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/chat_accounts").to_s,
        %w[users accounts account_users ruby_llm_models chats websites texts mcp_servers agent_skills prompts],
        { "ruby_llm_models" => "RubyLLM::ActiveRecord::Model" }).index_by(&:name)
      @user = users(:picker_owner)
      @first = accounts(:picker_first)
      @second = accounts(:picker_second)
      @foreign = accounts(:picker_foreign)
      ActiveJob::Base.queue_adapter = :test
      clear_enqueued_jobs
    end

    teardown do
      ActiveJob::Base.queue_adapter = @prior_adapter
      ActsAsTenant.current_tenant = @prior_tenant
      Current.reset
      ActiveRecord::FixtureSet.reset_cache
    end
  end

  %w[users accounts account_users ruby_llm_models chats websites texts mcp_servers agent_skills prompts].each do |table|
    define_method(table) do |name|
      @picker_fixtures.fetch(table).fixtures.fetch(name.to_s).find
    end
  end

  def sign_in_picker_user(user = @user)
    post login_url, params: { email: user.email, password: PASSWORD }
    assert_response :redirect
  end

  def with_singleton_replacement(object, name, replacement)
    own_method = object.singleton_class.instance_methods(false).include?(name)
    original = object.method(name)
    object.define_singleton_method(name, replacement)
    yield
  ensure
    if own_method
      object.define_singleton_method(name, original)
    else
      object.singleton_class.remove_method(name)
    end
  end

  def insert_picker_chunk(account, source, content, vector)
    result = Chunk.insert_all!([ { account_id: account.id, chunkable_id: source.id,
      chunkable_type: source.class.name, content: content, embedding: vector,
      metadata: {}, created_at: Time.current, updated_at: Time.current } ])
    account.chunks.find(result.rows.first.first)
  end
end
```

Load these opt-in FixtureSets in the normal test `setup`, after Rails has opened that test's transactional fixture connection. Do not declare them with class-level `fixtures :all`: Rails otherwise seeds them before the test transaction, leaving account/user rows visible to later legacy tests that expect an empty database. The base class's existing empty fixture configuration remains unchanged, each test rolls back its manually loaded FixtureSets, and the FixtureSet cache is reset between tests.

`with_singleton_replacement` avoids depending on the removed Minitest 6 mocking API. Its ensure restores method ownership; never leave global stubs installed.

Create `test/support/fixtures/chat_accounts/users.yml`:

```yaml
<% { picker_owner: "picker@example.com", picker_outsider: "outsider@example.com", picker_no_account: "no-account@example.com" }.each do |name, email| %>
<%= name %>:
  email: <%= User.type_for_attribute("email").serialize(email).to_json %>
  password_digest: <%= BCrypt::Password.create("picker-password-123", cost: BCrypt::Engine::MIN_COST).to_json %>
<% end %>
```

Create `accounts.yml` in the same directory:

```yaml
picker_first:
  name: First team
  owner: picker_owner
  created_at: 2026-01-01 00:00:00
picker_second:
  name: Research team
  owner: picker_owner
  created_at: 2026-01-02 00:00:00
picker_foreign:
  name: Private team
  owner: picker_outsider
  created_at: 2026-01-03 00:00:00
```

Create `account_users.yml`:

```yaml
picker_first_membership:
  account: picker_first
  user: picker_owner
picker_second_membership:
  account: picker_second
  user: picker_owner
picker_foreign_membership:
  account: picker_foreign
  user: picker_outsider
```

Create `ruby_llm_models.yml`:

```yaml
picker_model:
  model_id: picker-test-model
  provider: openai
  name: Picker test model
```

Create `chats.yml`:

```yaml
picker_second_chat:
  account: picker_second
  user: picker_owner
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:picker_model) %>
picker_foreign_chat:
  account: picker_foreign
  user: picker_outsider
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:picker_model) %>
```

Create `websites.yml`:

```yaml
<% %w[first second foreign].each do |name| %>
picker_<%= name %>_website:
  account: picker_<%= name %>
  url: https://<%= name %>.example/reference
  data: "# <%= name.capitalize %> source"
  index_status: 10
<% end %>
```

Create `texts.yml`:

```yaml
<% %w[first second].each do |name| %>
picker_<%= name %>_text:
  account: picker_<%= name %>
  title: <%= name.capitalize %> text
  data: <%= name.capitalize %> account evidence
<% end %>
```

Create `mcp_servers.yml`:

```yaml
<% %w[first second foreign].each do |name| %>
picker_<%= name %>_tool:
  account: picker_<%= name %>
  name: <%= name.capitalize %> tool
  transport_type: local
  enabled: true
  status: ready
<% end %>
```

Create `agent_skills.yml`:

```yaml
<% %w[first second].each do |name| %>
picker_<%= name %>_skill:
  account: picker_<%= name %>
  name: <%= name %>-skill
  description: <%= name.capitalize %> account skill
  skill_content: Account-specific test instructions
  execution_mode: llm
  trigger_mode: explicit
  enabled: true
  metadata: {}
<% end %>
```

Create `prompts.yml` in the same scoped fixture directory:

```yaml
picker_first_prompt:
  account: picker_first
  name: system_prompt
  content: First account instructions
picker_second_prompt:
  account: picker_second
  name: system_prompt
  content: Research account instructions
```

- [ ] Run the smoke test again. Expected GREEN, including decrypted email and fixture model association. Run the Task 0 baseline files again; fixture additions must not alter their initial data.
- [ ] Commit only `test/support/chat_account_fixtures.rb`, `test/support/fixtures/chat_accounts`, and `test/models/chat_account_fixture_test.rb`: `git commit -m "test: add isolated chat account fixtures"` after explicitly staging those paths.

## Task 2: Resolve and authorize chat accounts

**Files:** Create `app/controllers/concerns/chat_account_scoped.rb` and `test/controllers/chat_account_selection_test.rb`; modify `app/controllers/dashboards_controller.rb` and `app/controllers/chats_controller.rb`.

- [ ] Add the selection tests. Keep this class open for the later task's additional tests:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountSelectionTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  setup { sign_in_picker_user }

  test "new chat rejects an explicit account outside memberships" do
    get new_chat_url, params: { account_id: @foreign.id }
    assert_response :not_found
    get user_root_url, params: { account_id: @foreign.id }
    assert_response :not_found
  end

  test "create uses the second account without changing the default" do
    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { account_id: @second.id,
        prompt: "Research question", model: "picker-test-model" } }
    end
    chat = @user.chats.order(:id).last
    assert_redirected_to chat_url(chat)
    assert_equal @second.id, chat.account_id
    assert_equal @first, @user.first_account
  end

  test "missing and blank account context preserve the first account" do
    [ {}, { account_id: "" } ].each do |selection|
      post chats_url, params: { chat: selection.merge(prompt: "Default question",
        model: "picker-test-model") }
      assert_equal @first.id, @user.chats.order(:id).last.account_id
    end
  end

  test "invalid selection creates no chat message or generation job" do
    before_counts = [ Chat.count, Message.count, ChatMcpSession.count ]
    assert_no_enqueued_jobs only: ChatResponseJob do
      post chats_url, params: { chat: { account_id: @foreign.id,
        prompt: "Forbidden", model: "picker-test-model" } }
    end
    assert_response :not_found
    assert_equal before_counts, [ Chat.count, Message.count, ChatMcpSession.count ]
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/controllers/chat_account_selection_test.rb`. Expected RED: selection is ignored; unknown membership GET succeeds and creation uses the first account.
- [ ] Create the controller concern:

```ruby
module ChatAccountScoped
  extend ActiveSupport::Concern

  class MissingAccount < StandardError; end
  NO_ACCOUNT_MESSAGE = "You need access to an account to start a chat.".freeze

  included do
    rescue_from MissingAccount do
      respond_to do |format|
        format.json { render json: { error: NO_ACCOUNT_MESSAGE }, status: :unprocessable_entity }
        format.any { render plain: NO_ACCOUNT_MESSAGE, status: :unprocessable_entity }
      end
    end
  end

  private
    def selected_chat_account(account_id = nil)
      if account_id.present?
        Current.user.accounts.find(account_id)
      else
        Current.user.first_account
      end
    end

    def required_chat_account(account_id = nil)
      selected_chat_account(account_id) || raise(MissingAccount)
    end

    def authorized_chat(chat_id)
      chat = Current.user.chats.find(chat_id)
      Current.user.accounts.find(chat.account_id)
      chat
    end
end
```

Include `ChatAccountScoped` in both controllers. Replace their new-chat initialization with the following exact lines; keep the existing `@selected_model` assignment in `ChatsController#new`, and add it to `DashboardsController#show`:

```ruby
@chat = Current.user.chats.new(account: selected_chat_account(params[:account_id]))
@selected_model = params[:model]
```

In `ChatsController#create`, replace `account: Current.account` with:

```ruby
account: required_chat_account(params.dig(:chat, :account_id))
```

Replace `ChatsController#set_chat` with:

```ruby
def set_chat
  @chat = authorized_chat(params[:id])
end
```

- [ ] Run the selection tests and existing chats controller tests. Expected GREEN for account resolution, with old default behavior preserved. The later task adds resource validation before persistence.
- [ ] Explicitly stage the concern, two controllers, and selection test; commit `feat: authorize per-chat account selection`.

## Task 3: Enforce fixed account and validate resources before writes

**Files:** Create `app/models/chat/account_scoped.rb` and `test/models/chat_account_test.rb`; modify `app/models/chat.rb` and `app/controllers/chats_controller.rb`; extend `test/controllers/chat_account_selection_test.rb`.

- [ ] Add the model tests:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountTest < ActiveSupport::TestCase
  include ChatAccountFixtures

  test "persisted chats cannot be reassigned" do
    chat = chats(:picker_second_chat)
    assert_not chat.update(account: @first)
    assert_includes chat.errors[:account], "cannot be changed after creation"
    assert_equal @second.id, chat.reload.account_id
  end

  test "source attributes normalize references and reject other accounts" do
    chat = chats(:picker_second_chat)
    own = websites(:picker_second_website)
    assert_equal({ attached_website_ids: [ own.id.to_s ], attached_document_ids: [] },
      chat.source_attributes(website_ids: [ "", own.id, own.id ], document_ids: []))
    assert_raises(ActiveRecord::RecordNotFound) do
      chat.source_attributes(website_ids: [ websites(:picker_first_website).id ], document_ids: [])
    end
  end

  test "tool snapshots use the chat account even under another tenant" do
    chat = chats(:picker_second_chat)
    own_id = mcp_servers(:picker_second_tool).id
    other_id = mcp_servers(:picker_first_tool).id
    ActsAsTenant.with_tenant(@first) do
      assert_equal [ own_id ], chat.selected_mcp_servers([ own_id ]).map(&:id)
      assert_raises(ActiveRecord::RecordNotFound) do
        chat.selected_mcp_servers([ other_id ])
      end
    end
  end
end
```

Add this test inside `ChatAccountSelectionTest`:

```ruby
test "wrong-account references fail before any chat message or tool linkage" do
  invalid_options = [
    { chat: { attached_website_ids: [ websites(:picker_first_website).id ] } },
    { mcp_server_ids: [ mcp_servers(:picker_first_tool).id ] }
  ]
  invalid_options.each do |options|
    chat_params = { account_id: @second.id, prompt: "Invalid references", model: "picker-test-model" }
    chat_params.merge!(options.fetch(:chat, {}))
    counts = [ Chat.count, Message.count, ChatMcpSession.count ]
    assert_no_enqueued_jobs only: ChatResponseJob do
      post chats_url, params: options.except(:chat).merge(chat: chat_params)
    end
    assert_response :not_found
    assert_equal counts, [ Chat.count, Message.count, ChatMcpSession.count ]
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/models/chat_account_test.rb test/controllers/chat_account_selection_test.rb`. Expected RED: account reassignment succeeds, resource methods do not exist, and invalid references currently do not fail before chat persistence.
- [ ] Create the model concern and include `AccountScoped` in `Chat` alongside its other concerns:

```ruby
module Chat::AccountScoped
  extend ActiveSupport::Concern

  included do
    validate :account_is_fixed, on: :update
  end

  # @param website_ids [Array<String, Integer>]
  # @param document_ids [Array<String, Integer>]
  # @return [Hash] Normalized references owned by this chat's account
  # @raise [ActiveRecord::RecordNotFound] if any reference is unavailable
  def source_attributes(website_ids:, document_ids:)
    {
      attached_website_ids: source_ids(account.websites, website_ids),
      attached_document_ids: source_ids(account.documents, document_ids)
    }
  end

  # @param ids [Array<String, Integer>]
  # @return [Array<McpServer>] Account-owned tools, materialized in its tenant context
  # @raise [ActiveRecord::RecordNotFound] if any tool is unavailable
  def selected_mcp_servers(ids)
    requested = normalized_source_ids(ids)
    ActsAsTenant.with_tenant(account) do
      servers = account.mcp_servers.where(id: requested).to_a
      raise ActiveRecord::RecordNotFound unless servers.map { |server| server.id.to_s }.sort == requested.sort
      servers
    end
  end

  private
    def account_is_fixed
      if will_save_change_to_account_id?
        errors.add(:account, "cannot be changed after creation")
      end
    end

    def source_ids(relation, ids)
      requested = normalized_source_ids(ids)
      found = relation.where(id: requested).pluck(:id).map(&:to_s)
      raise ActiveRecord::RecordNotFound unless found.sort == requested.sort
      requested
    end

    def normalized_source_ids(ids)
      Array(ids).compact_blank.map(&:to_s).uniq
    end
end
```

Replace the body of `ChatsController#create` (not the other actions) with:

```ruby
def create
  account = required_chat_account(params.dig(:chat, :account_id))
  return unless prompt.present?

  @chat = Current.user.chats.new(account: account, model: model,
    provider: :openai, assume_model_exists: true)
  sources = @chat.source_attributes(
    website_ids: params.dig(:chat, :attached_website_ids),
    document_ids: params.dig(:chat, :attached_document_ids))
  servers = @chat.selected_mcp_servers(params[:mcp_server_ids])

  Chat.transaction do
    @chat.save!
    servers.each { |server| @chat.add_mcp_server(server) }
    @user_message = @chat.messages.create!(sources.merge(role: "user", content: prompt))
    @user_message.attach_website_sources_from_content!(@chat.account)
    @chat.start_generation!
  end

  ChatResponseJob.perform_later(@chat.id, @user_message.content, @user_message.id)
  redirect_to @chat
end
```

All submitted resource IDs are checked before `@chat.save!`. The generation job is queued only after the transaction succeeds. Do not change the website crawler's existing retry/enqueue contract in this task.

- [ ] Run the two feature files and existing chats controller tests. Expected GREEN; wrong-account references cause no partial chat/message/MCP rows and no generation job.
- [ ] Stage only the named model/controller/test files; commit `feat: keep chat resources within their selected account`.

## Task 4: Saved-chat authorization and account-aware source endpoints

**Files:** Create `test/controllers/chat_account_sources_test.rb` and `test/controllers/chat_account_access_test.rb`; modify `app/controllers/messages_controller.rb`, `app/controllers/chat_sources_controller.rb`, `app/controllers/chat_mcp_sessions_controller.rb`, and `app/controllers/sources/documents_controller.rb`.

- [ ] Create the source tests:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountSourcesTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  setup { sign_in_picker_user }

  test "new and saved chat URL registrations use explicit context" do
    [ { account_id: @second.id }, { chat_id: chats(:picker_second_chat).id } ].each_with_index do |context, index|
      url = "https://context-#{index}.example/reference"
      post chat_sources_url, params: context.merge(url: url), as: :json
      assert_response :success
      assert_equal @second.id, Website.find(response.parsed_body.fetch("id")).account_id
    end
  end

  test "conflicting saved-chat context is rejected before creating a source" do
    assert_no_difference "Website.count" do
      post chat_sources_url, params: { chat_id: chats(:picker_second_chat).id,
        account_id: @first.id, url: "https://conflict.example" }, as: :json
    end
    assert_response :not_found
  end

  test "PDF registration and dashboard upload use the second account" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n%%EOF"),
      filename: "account.pdf", content_type: "application/pdf")
    post chat_sources_url, params: { account_id: @second.id, attachable_sgid: blob.attachable_sgid }, as: :json
    assert_response :success
    assert_equal @second.id, Document.find(response.parsed_body.fetch("id")).account_id

    post sources_documents_url, params: { document: { account_id: @second.id,
      title: "Dashboard upload", file: blob.signed_id } }, as: :json
    assert_response :created
    assert_equal @second.id, Document.find(response.parsed_body.fetch("id")).account_id
  end

  test "follow-up URLs and references use the saved account and ignore overrides" do
    chat = chats(:picker_second_chat)
    own = websites(:picker_second_website)
    post chat_messages_url(chat), params: { message: { account_id: @first.id,
      content: "https://follow-up.example/reference", attached_website_ids: [ own.id ] } }
    assert_response :redirect
    assert_equal @second.id, chat.reload.account_id
    assert @second.websites.exists?(url: "https://follow-up.example/reference")
    assert_includes chat.messages.user.last.attached_website_ids, own.id.to_s

    assert_no_difference "Message.count" do
      assert_no_enqueued_jobs only: ChatResponseJob do
        post chat_messages_url(chat), params: { message: { content: "Wrong account",
          attached_website_ids: [ websites(:picker_first_website).id ] } }
      end
    end
    assert_response :not_found
  end

  test "PDF references cannot come from another account" do
    document = @first.documents.new(title: "First account PDF")
    document.file.attach(io: StringIO.new("%PDF-1.4\n%%EOF"), filename: "first.pdf", content_type: "application/pdf")
    document.save!
    counts = [ Chat.count, Message.count ]
    post chats_url, params: { chat: { account_id: @second.id, prompt: "Wrong PDF",
      model: "picker-test-model", attached_document_ids: [ document.id ] } }
    assert_response :not_found
    assert_equal counts, [ Chat.count, Message.count ]
  end

  test "malformed SGIDs retain a 400 response" do
    post chat_sources_url, params: { account_id: @second.id, attachable_sgid: "invalid" }, as: :json
    assert_response :bad_request
  end
end
```

Create the access tests:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountAccessTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  setup { sign_in_picker_user }

  test "unowned and revoked chats reject every conversation web operation" do
    own = chats(:picker_second_chat)
    @user.account_users.find_by!(account: @second).destroy!
    [ own, chats(:picker_foreign_chat) ].each do |chat|
      requests = [
        [ :get, chat_url(chat), {} ],
        [ :post, stop_chat_url(chat), {} ],
        [ :delete, chat_url(chat), {} ],
        [ :post, chat_messages_url(chat), { message: { content: "Denied" } } ],
        [ :post, chat_sources_url, { chat_id: chat.id, url: "https://denied.example" } ],
        [ :post, chat_mcp_sessions_url(chat), { mcp_server_id: mcp_servers(:picker_second_tool).id } ],
        [ :delete, chat_mcp_session_url(chat, 999999999), {} ]
      ]
      requests.each do |verb, url, values|
        counts = [ Chat.count, Message.count, Website.count, ChatMcpSession.count ]
        assert_no_enqueued_jobs only: ChatResponseJob do
          public_send(verb, url, params: values)
        end
        assert_response :not_found
        assert_equal counts, [ Chat.count, Message.count, Website.count, ChatMcpSession.count ]
      end
    end
  end

  test "no-account users cannot create chats or sources" do
    delete logout_url
    sign_in_picker_user(users(:picker_no_account))
    [ [ chats_url, { chat: { prompt: "No account", model: "picker-test-model" } } ],
      [ chat_sources_url, { url: "https://no-account.example" } ],
      [ sources_documents_url, { document: { title: "No account" } } ] ].each do |url, values|
      post url, params: values, as: :json
      assert_response :unprocessable_entity
      assert_includes response.parsed_body.fetch("error"), "access to an account"
    end
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/controllers/chat_account_sources_test.rb test/controllers/chat_account_access_test.rb`. Expected RED: source creation uses the first account and saved-chat endpoints do not reject revoked memberships.
- [ ] Include `ChatAccountScoped` in `MessagesController`, `ChatSourcesController`, `ChatMcpSessionsController`, and `Sources::DocumentsController`.

Replace `MessagesController#set_chat` and `ChatMcpSessionsController#set_chat`:

```ruby
def set_chat
  @chat = authorized_chat(params[:chat_id])
end
```

In `MessagesController#create`, after checking content and before creating a message, derive validated attributes; replace the existing attachment-ID attributes with `sources` and use the saved account for typed URLs:

```ruby
sources = @chat.source_attributes(
  website_ids: params.dig(:message, :attached_website_ids),
  document_ids: params.dig(:message, :attached_document_ids))
@user_message = @chat.messages.create!(sources.merge(role: "user", content: content))
@user_message.attach_website_sources_from_content!(@chat.account)
```

Keep generation locking, enqueue arguments, and response formats unchanged. In `ChatSourcesController#create`, assign `@source_account = source_account` before its URL/SGID branches. Replace both `Current.account` source-creation arguments with `@source_account`. Add these private methods:

```ruby
def source_account
  if params[:chat_id].present?
    account = authorized_chat(params[:chat_id]).account
    if params[:account_id].present? && params[:account_id].to_s != account.id.to_s
      raise ActiveRecord::RecordNotFound
    end
    account
  else
    required_chat_account(params[:account_id])
  end
end
```

Keep the existing invalid-SGID rescue inside `create_document_from_sgid`; account authorization happens before that method, so an unauthorized account remains a 404, not an SGID 400. Add the following rescue for invalid source data only:

```ruby
rescue_from ActiveRecord::RecordInvalid do |error|
  render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
end
```

In `Sources::DocumentsController#create`, replace the single filing/new expression with:

```ruby
account = filing_account(:document) || raise(ChatAccountScoped::MissingAccount)
@document = account.documents.new(document_params)
```

Do not alter its normal JSON/HTML source upload behavior. MCP's create action will be finalized in Task 5; it must already use the authorized chat from the new `set_chat`.

- [ ] Run both new test files and the existing source/message controller files. Expected GREEN. The invalid PDF test rejects before chat persistence, not during background indexing.
- [ ] Stage the four controllers and two new test files explicitly; commit `feat: honor saved chat accounts for sources and messages`.

## Task 5: Tenant-safe MCP, skills, and job context

**Files:** Create `app/helpers/chats_helper.rb` and `test/controllers/chat_account_tools_test.rb`; modify `app/helpers/agent_skills_helper.rb`, `app/models/chat/model_context_protocol.rb`, `app/controllers/chat_mcp_sessions_controller.rb`, and `app/jobs/chat_response_job.rb`.

- [ ] Create tool isolation tests:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountToolsTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  setup { sign_in_picker_user }

  test "saved chat accepts only its own tools" do
    chat = chats(:picker_second_chat)
    tool = mcp_servers(:picker_second_tool)
    post chat_mcp_sessions_url(chat), params: { mcp_server_id: tool.id }
    assert_response :redirect
    session = chat.chat_mcp_sessions.find_by!(mcp_server: tool)
    delete chat_mcp_session_url(chat, session)
    assert_response :redirect
    assert_not chat.chat_mcp_sessions.exists?(session.id)

    assert_no_difference "ChatMcpSession.count" do
      post chat_mcp_sessions_url(chat), params: { mcp_server_id: mcp_servers(:picker_first_tool).id }
    end
    assert_response :not_found
  end
end
```

Append to `ChatAccountTest`:

```ruby
test "model-level tool linking rejects a different account" do
  chat = chats(:picker_second_chat)
  assert_raises(ActiveRecord::RecordNotFound) { chat.add_mcp_server(mcp_servers(:picker_first_tool)) }
end

test "helper snapshots restore a pre-existing tenant" do
  helper = ApplicationController.helpers
  ActsAsTenant.with_tenant(@first) do
    assert_equal [ "Second tool" ], helper.ready_chat_mcp_servers(@second).map(&:name)
    assert_equal [ "second-skill" ], JSON.parse(helper.agent_skill_autocomplete_data(@second)).map { |skill| skill.fetch("name") }
    assert_equal @first, ActsAsTenant.current_tenant
  end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test test/controllers/chat_account_tools_test.rb test/models/chat_account_test.rb`. Expected RED: MCP create queries the first account; the helper is absent and skill snapshots conflict with the surrounding tenant.
- [ ] Create `ChatsHelper`:

```ruby
module ChatsHelper
  # @param account [Account]
  # @return [Array<McpServer>] Ready, enabled tools from this account only
  def ready_chat_mcp_servers(account)
    ActsAsTenant.with_tenant(account) do
      account.mcp_servers.enabled.ready.order(:name).to_a
    end
  end
end
```

Wrap the existing `AgentSkillsHelper#agent_skill_autocomplete_data` body in `ActsAsTenant.with_tenant(account)`, including materialization and JSON generation:

```ruby
def agent_skill_autocomplete_data(account = Current.account)
  ActsAsTenant.with_tenant(account) do
    account.agent_skills.explicitly_invocable.map do |skill|
      { name: skill.name, description: skill.description.to_s.truncate(120) }
    end.to_json
  end
end
```

Replace `Chat::ModelContextProtocol#add_mcp_server` and wrap its existing tool reader:

```ruby
def add_mcp_server(mcp_server)
  raise ActiveRecord::RecordNotFound unless mcp_server.account_id == account_id
  ActsAsTenant.with_tenant(account) do
    chat_mcp_sessions.find_or_create_by(mcp_server: mcp_server)
  end
end

def mcp_tools
  ActsAsTenant.with_tenant(account) do
    chat_mcp_sessions.enabled.includes(:mcp_server).flat_map do |session|
      next [] unless session.mcp_server&.status_ready?
      session.mcp_server.tools
    end.compact
  end
end
```

Replace the MCP controller's first tool lookup with:

```ruby
@mcp_server = @chat.selected_mcp_servers([ params[:mcp_server_id] ]).fetch(0)
```

Ensure absent IDs produce a 404, not `IndexError`: before that lookup add `raise ActiveRecord::RecordNotFound if params[:mcp_server_id].blank?`.

In `ChatMcpSessionsController#destroy`, replace its `@mcp_server` assignment with the following bounded association lookup so an unrelated surrounding tenant cannot hide the server:

```ruby
@mcp_server = ActsAsTenant.with_tenant(@chat.account) { @session.mcp_server }
raise ActiveRecord::RecordNotFound unless @mcp_server
```

- [ ] Add the following job-context test to `ChatAccountTest` before adding the job callback. This is a separate red/green cycle:

```ruby
test "background generation uses and restores the saved account tenant" do
  chat = chats(:picker_second_chat)
  observed = []
  chat.define_singleton_method(:complete_with_nosia) do |*args, **options|
    observed << ActsAsTenant.current_tenant
    nil
  end
  chat.define_singleton_method(:complete_with_agent_skills) do |*args, **options|
    observed << ActsAsTenant.current_tenant
    nil
  end
  original_find = Chat.method(:find)
  lookup = ->(*ids) { ids == [ chat.id ] ? chat : original_find.call(*ids) }
  Current.reset
  ActsAsTenant.with_tenant(@first) do
    with_singleton_replacement(Chat, :find, lookup) do
      ChatResponseJob.perform_now(chat.id, "Account context")
    end
    assert_equal @first, ActsAsTenant.current_tenant
  end
  assert_equal [ @second ], observed
end
```

Run `PARALLEL_WORKERS=1 bin/rails test test/models/chat_account_test.rb -n /background_generation/`. Expected RED: observed tenant is the first account. Add this callback inside `ChatResponseJob`, leaving its existing `perform`, retry, and ensure flow intact:

```ruby
around_perform do |job, operation|
  chat = Chat.find(job.arguments.first)
  ActsAsTenant.with_tenant(chat.account) { operation.call }
end
```

- [ ] Run the tool/model feature files plus `test/jobs/chat_response_job_test.rb`. Expected GREEN; tools, skills, query usage, and skill executions inside generation inherit the saved account, and the prior tenant is restored even when an operation fails.
- [ ] Stage only the named helper/model/controller/job/test files; commit `fix: scope chat tools and background work to their account`.

## Task 6: Footer picker, read-only label, and explicit composer context

**Files:** Create `app/views/chats/_account.html.erb`, `app/views/chats/_no_account.html.erb`; modify the five chat/dashboard/form views, `app/views/chats/_mcp_selector.html.erb`, and `app/views/application/_header.html.erb`; extend the selection/access/model tests.

- [ ] Add these methods inside `ChatAccountSelectionTest`:

```ruby
test "both new-chat entry points show membership-only selected-account controls" do
  [ user_root_url, new_chat_url ].each do |url|
    get url, params: { account_id: @second.id }
    assert_response :success
    assert_select "select[name='chat[account_id]'] option", count: 2
    assert_select "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
    assert_select "select[name='chat[account_id]'] option[value='#{@foreign.id}']", count: 0
    assert_select "#chat-form input[type=checkbox][name='mcp_server_ids[]']", count: 1
    assert_select "#chat-form input[type=checkbox][value='#{mcp_servers(:picker_second_tool).id}']"
    assert_select "#chat-form [data-composer-skills-value]" do |nodes|
      assert_equal [ "second-skill" ], JSON.parse(nodes.first["data-composer-skills-value"]).map { |skill| skill.fetch("name") }
    end
  end
end

test "saved chat shows a read-only account and its own MCP options" do
  get chat_url(chats(:picker_second_chat))
  assert_response :success
  assert_select "[data-chat-account-readonly]", text: /Research team/
  assert_select "select[name='chat[account_id]']", count: 0
  assert_select "#mcp-selector-modal", text: /Second tool/
  assert_select "#mcp-selector-modal", text: /First tool/, count: 0
end
```

Add inside `ChatAccountAccessTest`:

```ruby
test "no-account entry points render the empty state without an editor or upload zone" do
  delete logout_url
  sign_in_picker_user(users(:picker_no_account))
  [ user_root_url, new_chat_url ].each do |url|
    get url
    assert_response :success
    assert_select "[data-chat-no-account]", text: /access to an account/
    assert_select "lexxy-editor", count: 0
    assert_select "[data-controller~=dropzone]", count: 0
  end
end
```

- [ ] Run the selection/access tests. Expected RED: no footer account field/label exists, and the header search dereferences a missing default account.
- [ ] Create `_account.html.erb` (persisted branch must not read `Current`):

```erb
<div class="flex flex-wrap items-center gap-2">
  <% if chat.persisted? %>
    <span data-chat-account-readonly>Account: <%= chat.account.name %></span>
  <% else %>
    <%= form.label :account_id, "Account", class: "n-label !mb-0" %>
    <%= form.collection_select :account_id, Current.user.accounts.order(:name), :id, :name,
      { selected: chat.account_id },
      { class: "n-select !w-auto max-w-full", required: true,
        aria: { describedby: "chat-account-help" },
        data: { chat_account_target: "picker", action: "change->chat-account#change" } } %>
    <span id="chat-account-help" class="text-xs text-neutral-500">Searches and attachments use this account.</span>
  <% end %>
</div>
```

Create `_no_account.html.erb`:

```erb
<p role="status" data-chat-no-account class="text-sm text-neutral-500">
  You need access to an account to start a chat.
</p>
```

Wrap the existing contents of `chats/_form.html.erb` in `if chat.account.present?`; render `chats/no_account` in the `else` branch. Inside the account-present branch, before rendering the form, calculate:

```erb
<% skills = JSON.parse(agent_skill_autocomplete_data(chat.account)) %>
```

Make these exact new-chat form changes, preserving the rest of the editor, icons, errors, and MCP markup:

```ruby
# The form_with data option:
data: { controller: "mcp-fields-sync", chat_account_target: "form", generation_busy: false,
  action: "submit->chat-account#guard submit->mcp-fields-sync#copy" }
```

```erb
<%= form.hidden_field :model, value: @selected_model if @selected_model.present? %>
```

Replace the editor wrapper opening tag with:

```erb
<div class="relative w-full" data-controller="composer composer-sources"
     data-composer-skills-value="<%= skills.to_json %>"
     data-composer-sources-account-id-value="<%= chat.account_id %>"
     data-composer-sources-chat-id-value="<%= chat.id if chat.persisted? %>"
     data-action="chat-account:reset@window->composer-sources#reset">
```

Keep `data-composer-target="editor"` on the editor and additionally set `data-composer-sources-target="editor"`. Change the attachment hidden-input targets from `composer` to `composer-sources`, with target names `websiteIds` and `documentIds`. Add this sibling to the skill menu:

```erb
<ul hidden role="alert" class="mt-2 text-sm text-red-600" data-composer-sources-target="errors"></ul>
```

Set `aria: { label: "Send" }` and `data: { chat_account_target: "send" }` on the normal send button. Change the MCP availability expression to `ready_chat_mcp_servers(chat.account)`. Change the skill caption condition to `skills.any?`. In the footer, use `flex flex-wrap items-center justify-between gap-3` and insert:

```erb
<%= render "chats/account", chat: chat, form: form %>
```

Apply the same footer, skills snapshot, dual editor targets, source wrapper, error list, and send-button accessibility/target changes to `messages/_form.html.erb`. Move `is_generating = chat.generating` before its `form_with`; use the saved-chat form data below:

```ruby
data: { chat_account_target: "form", generation_busy: is_generating,
  action: "submit->chat-account#guard" }
```

For both form templates, replace `chat.mcp_servers.count` with `chat.chat_mcp_sessions.count` so counts do not inherit an unrelated tool tenant. In `chats/_mcp_selector.html.erb`, replace the availability expression with `ready_chat_mcp_servers(chat.account)`.

For the new-chat template, move its existing MCP-selection block (from the `MCP Server Selection` comment through the matching `unless chat.persisted?` end) into the same wrapping footer immediately after the account partial. Preserve the block's checkboxes and selected-count behavior; do not duplicate it. Give the keyboard/disclaimer span `class="basis-full"`. This keeps the account picker and collapsed MCP controls together as approved in layout B, with instructions on the next row.

Add these attributes to the outermost dashboard and new-chat page elements:

```erb
data-controller="chat-account"
data-chat-account-account-id-value="<%= @chat.account_id %>"
data-action="composer-sources:state->chat-account#sourceState dropzone:state->chat-account#sourceState turbo:submit-start->chat-account#submitStarted turbo:submit-end->chat-account#submitEnded turbo:before-cache@document->chat-account#beforeCache:capture"
```

Add the same attributes to the show page's outer element, preserving its existing controller as `data-controller="chat-reconnect chat-account"` and its reconnect generating value. The account controller therefore survives replacement of the saved-message form.

On the dashboard, wrap the entire existing document upload panel in `if @chat.account.present?`. Do not show a working uploader without an account. Add these attributes to the existing dropzone element:

```erb
data-dropzone-account-id-value="<%= @chat.account_id %>"
data-action="chat-account:reset@window->dropzone#resetChatDraft"
```

In `application/_header.html.erb`, change only the condition guarding the global search button and its `render "search"` to `if Current.user && Current.account`. Keep the user menu's separate authentication condition unchanged. This is a nil-account guard, not global search account switching.

- [ ] Add a separate broadcast regression to `ChatAccountTest`; require `turbo/broadcastable/test_helper` at the top and include `Turbo::Broadcastable::TestHelper` inside that class:

```ruby
test "background unlock renders the read-only second account without Current" do
  chat = chats(:picker_second_chat)
  Current.reset
  streams = capture_turbo_stream_broadcasts([ chat, "messages" ]) { chat.finish_generation! }
  form = streams.find { |stream| stream["target"] == "chat_#{chat.id}_message_form" }
  assert form
  assert_includes form.inner_html, "Research team"
  assert_not_includes form.inner_html, "chat[account_id]"
end
```

- [ ] Run all feature controller/model tests and existing `test/models/chat_test.rb`. Expected GREEN. Source browser behavior is completed in Tasks 7–9; do not accept the intermediate page as a finished feature.
- [ ] Stage only the named views and tests; commit `feat: show account context in chat composer footers`.

## Task 7: Account switching, confirmation, and Turbo cache reset

**Files:** Create `app/javascript/controllers/chat_account_controller.js` and `test/system/chat_account_selection_test.rb`.

- [ ] Create the system-test base and the first switching tests:

```ruby
require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class ChatAccountSelectionSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  test "empty switching refreshes account options on both entry points" do
    [ user_root_url, new_chat_url ].each do |url|
      visit url
      select "Research team", from: "Account"
      assert_selector "select option[selected][value='#{@second.id}']"
      assert_selector "#chat-form input[type=checkbox][value='#{mcp_servers(:picker_second_tool).id}']", visible: :all
      assert_equal [ "second-skill" ], browser_skills
    end
  end

  test "cancel preserves the draft and confirm resets it without moving saved sources" do
    write_draft("Keep this draft")
    dismiss_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
    assert_includes draft_html, "Keep this draft"

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
    assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
    assert_not_includes draft_html, "Keep this draft"
    assert_equal @first.id, websites(:picker_first_website).reload.account_id
  end

  private
    def write_draft(text)
      assert_selector "lexxy-editor .lexxy-editor__content"
      editor = find("lexxy-editor")
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new CustomEvent('lexxy:change', { bubbles: true }))", editor, "<p>#{text}</p>")
    end

    def draft_html
      page.evaluate_script("document.querySelector('lexxy-editor').value")
    end

    def browser_skills
      page.evaluate_script("JSON.parse(document.querySelector('[data-composer-skills-value]').dataset.composerSkillsValue).map(skill => skill.name)")
    end
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test:system TEST=test/system/chat_account_selection_test.rb`. Expected RED: changing the picker does not navigate or confirm. A browser/environment boot failure is a blocker, not the required behavioral red.
- [ ] Create the account-selection controller:

```javascript
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["picker", "form", "send"]
  static values = { accountId: String }

  initialize() {
    this.sources = new Map()
    this.submitting = false
  }

  connect() {
    this.syncControls()
  }

  formTargetConnected() {
    this.submitting = false
    this.syncControls()
  }
  sendTargetConnected() { this.syncControls() }

  submitStarted(event) {
    if (event.target !== this.formTarget) return
    this.submitting = true
    this.syncControls()
  }

  submitEnded(event) {
    if (event.target !== this.formTarget) return
    this.submitting = false
    this.syncControls()
  }

  sourceState(event) {
    this.sources.set(event.target, event.detail)
    this.syncControls()
  }

  get sourceStates() {
    for (const element of this.sources.keys()) {
      if (!this.element.contains(element)) this.sources.delete(element)
    }
    return [...this.sources.values()]
  }

  get pending() { return this.sourceStates.some(state => state.pending > 0) }
  get failed() { return this.sourceStates.some(state => state.failed) }

  syncControls() {
    if (this.hasPickerTarget) this.pickerTarget.disabled = this.pending || this.submitting
    if (this.hasSendTarget && this.hasFormTarget) {
      this.sendTarget.disabled = this.pending || this.failed || this.submitting || this.formTarget.dataset.generationBusy === "true"
    }
  }

  guard(event) {
    if (this.pending || this.failed || this.submitting || this.formTarget.dataset.generationBusy === "true") {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }

  change() {
    const next = this.pickerTarget.value
    if (this.pending || this.submitting || next === this.accountIdValue) {
      this.pickerTarget.value = this.accountIdValue
      return
    }
    if (this.dirty() && !window.confirm("Change account? This clears your unsent message, attachment references, and tool choices. Saved sources remain in the previous account.")) {
      this.pickerTarget.value = this.accountIdValue
      return
    }
    const url = new URL(window.location.href)
    url.searchParams.set("account_id", next)
    Turbo.visit(url.toString())
  }

  dirty() {
    const document = new DOMParser().parseFromString(this.element.querySelector("lexxy-editor")?.value || "", "text/html")
    return Boolean(document.body.textContent.trim() ||
      document.querySelector("action-text-attachment, a[href], img") ||
      this.element.querySelector("input[name='mcp_server_ids[]']:checked") ||
      this.sourceStates.some(state => state.dirty || state.failed))
  }

  beforeCache() {
    if (!this.hasPickerTarget) return
    window.dispatchEvent(new CustomEvent("chat-account:reset", { detail: { root: this.element } }))
    const editor = this.element.querySelector("lexxy-editor")
    if (editor) editor.value = ""
    for (const input of this.element.querySelectorAll("input")) {
      if (input.name.includes("attached_website_ids") || input.name.includes("attached_document_ids")) input.value = ""
      if (input.name === "mcp_server_ids[]" && input.type === "checkbox") input.checked = false
    }
    this.element.querySelector("#mcp-server-hidden-fields")?.replaceChildren()
    this.element.querySelector("[data-composer-target='menu']")?.replaceChildren()
    const count = this.element.querySelector("#mcp-selected-count")
    if (count) count.textContent = "0"
    this.pickerTarget.value = this.accountIdValue
    this.sources.clear()
    this.submitting = false
    this.syncControls()
  }
}
```

The account value remains the server-rendered account until navigation succeeds; cancel restores it. Sending also locks the picker immediately, so an account switch cannot race the first-message POST. A replacement form resets transient submission state while its server-rendered generation flag remains authoritative. Cached drafts are deliberately cleared only for unsaved-chat pages, not for persisted conversations. Use the `:capture` option shown above: Lexxy 0.9.23 disposes its editor in its own document-level `turbo:before-cache` listener, so the draft reset must run first. Source controllers introduced below handle the reset event and abort their own requests.

- [ ] Run the switching system tests and the controller selection tests. Expected GREEN for this task's tests. Preserve the URL's model query parameter when changing accounts.
- [ ] Explicitly stage the new controller and system test; commit `feat: confirm and reset drafts when changing chat accounts`.

## Task 8: Account-aware composer URL/PDF registration and failure handling

**Files:** Create `app/javascript/controllers/composer_sources_controller.js`; modify `app/javascript/controllers/composer_controller.js`; extend `test/system/chat_account_selection_test.rb`.

- [ ] Add these system tests inside the existing system-test class, before its `private` section:

```ruby
test "a pasted URL is registered in the selected account" do
  select "Research team", from: "Account"
  write_draft("Use the linked source")
  dispatch_link("https://browser-source.example/reference")
  assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
  assert @second.websites.exists?(url: "https://browser-source.example/reference")
  assert_not @first.websites.exists?(url: "https://browser-source.example/reference")
end

test "pending registration blocks account changes and Enter submission" do
  install_source_fetch_gate
  write_draft("Wait for this source")
  dispatch_link("https://pending-source.example/reference")
  assert_selector "select[name='chat[account_id]'][disabled]"
  assert_button "Send", disabled: true
  count = @user.chats.count
  page.execute_script("document.querySelector('#chat-form').requestSubmit()")
  assert_equal count, @user.chats.count
  page.execute_script("window.releasePickerSource()")
  assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
  assert_selector "select[name='chat[account_id]']:not([disabled])"
  assert_button "Send", disabled: false
end

test "a failed registration blocks send and can be retried" do
  page.execute_script(<<~JS)
    window.originalPickerFetch = window.fetch;
    window.fetch = (...args) => {
      const url = new URL(args[0] instanceof Request ? args[0].url : args[0], location.href);
      if (url.pathname === '/chat_sources') {
        return Promise.resolve(new Response(JSON.stringify({ error: 'Source registration failed' }),
          { status: 422, headers: { 'Content-Type': 'application/json' } }));
      }
      return window.originalPickerFetch(...args);
    };
  JS
  write_draft("Retry this source")
  dispatch_link("https://retry-source.example/reference")
  assert_text "Source registration failed"
  assert_button "Send", disabled: true
  page.execute_script("window.fetch = window.originalPickerFetch")
  click_on "Retry source"
  assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
  assert_button "Send", disabled: false
end

test "PDF upload lifecycle stays pending until its SGID is registered" do
  blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n%%EOF"),
    filename: "browser-account.pdf", content_type: "application/pdf")
  select "Research team", from: "Account"
  page.execute_script(<<~JS, blob.attachable_sgid)
    const editor = document.querySelector('lexxy-editor');
    window.pickerPDF = new File(['%PDF-1.4'], 'browser-account.pdf', { type: 'application/pdf' });
    editor.dispatchEvent(new CustomEvent('lexxy:upload-start', { detail: { file: window.pickerPDF }, bubbles: true }));
    editor.value = '<action-text-attachment sgid="' + arguments[0] + '" content-type="application/pdf" filename="browser-account.pdf"></action-text-attachment>';
  JS
  assert_button "Send", disabled: true
  page.execute_script(<<~JS)
    document.querySelector('lexxy-editor').dispatchEvent(new CustomEvent('lexxy:upload-end',
      { detail: { file: window.pickerPDF, error: null }, bubbles: true }));
  JS
  assert_selector "input[name='chat[attached_document_ids][]']", count: 2, visible: :all
  assert_equal @second.id, Document.joins(:file_attachment).where(active_storage_attachments: { blob_id: blob.id }).last.account_id
  assert_button "Send", disabled: false
end
```

Add these private helpers to the same class:

```ruby
def dispatch_link(url)
  page.execute_script("document.querySelector('lexxy-editor').dispatchEvent(new CustomEvent('lexxy:insert-link', { detail: { url: arguments[0] }, bubbles: true }))", url)
end

def install_source_fetch_gate
  page.execute_script(<<~JS)
    const original = window.fetch;
    window.fetch = (...args) => {
      const url = new URL(args[0] instanceof Request ? args[0].url : args[0], location.href);
      if (url.pathname !== '/chat_sources') return original(...args);
      return new Promise((resolve, reject) => {
        window.releasePickerSource = () => {
          window.fetch = original;
          original(...args).then(resolve, reject);
        };
      });
    };
  JS
end
```

The PDF test drives the real Lexxy event/serialized-SGID contract and real source endpoint without a live parsing/indexing worker. It is not a stub of the account decision. Keep a separate manual real-file paste check in Task 12.

- [ ] Run the system file. Expected RED: existing source registration does not send the selected account, report failures, or coordinate pending uploads.
- [ ] Extract source-only behavior into the following controller. It uses Lexxy 0.9.23's verified `lexxy:upload-start` and `lexxy:upload-end` events. An upload-end event precedes Lexxy's serialized SGID update, so retain bounded animation-frame polling:

```javascript
import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["editor", "websiteIds", "documentIds", "errors"]
  static values = { accountId: String, chatId: String }

  connect() {
    this.operations = new Map()
    this.uploads = new Set()
    this.sentSgids = new Set()
    this.dirty = false
    this.onLink = event => this.register({ url: event.detail.url }, "websiteIds", `url:${event.detail.url}`)
    this.onStart = event => {
      this.uploads.add(event.detail.file)
      this.dirty = true
      this.publishState()
    }
    this.onEnd = event => this.uploadEnded(event)
    this.editorTarget.addEventListener("lexxy:insert-link", this.onLink)
    this.editorTarget.addEventListener("lexxy:upload-start", this.onStart)
    this.editorTarget.addEventListener("lexxy:upload-end", this.onEnd)
    queueMicrotask(() => this.publishState())
  }

  disconnect() {
    this.editorTarget.removeEventListener("lexxy:insert-link", this.onLink)
    this.editorTarget.removeEventListener("lexxy:upload-start", this.onStart)
    this.editorTarget.removeEventListener("lexxy:upload-end", this.onEnd)
    for (const operation of this.operations.values()) operation.controller?.abort()
  }

  async uploadEnded(event) {
    const { file, error } = event.detail
    if (!this.uploads.has(file)) return
    try {
      if (error) throw new Error("PDF upload failed. Reset the draft and attach it again.")
      const sgid = await this.nextSgid(file)
      if (!this.uploads.has(file) || !this.element.isConnected) return
      if (!sgid) throw new Error("The PDF could not be registered. Reset the draft and attach it again.")
      this.register({ attachable_sgid: sgid }, "documentIds", `sgid:${sgid}`)
    } catch (failure) {
      if (!this.uploads.has(file) || !this.element.isConnected) return
      this.operations.set(file, { failed: true, pending: false, message: failure.message })
      this.renderErrors()
    } finally {
      this.uploads.delete(file)
      this.publishState()
    }
  }

  nextSgid(file) {
    return new Promise(resolve => {
      let attempts = 0
      const check = () => {
        if (!this.element.isConnected || !this.uploads.has(file)) return resolve(null)
        const document = new DOMParser().parseFromString(this.editorTarget.value || "", "text/html")
        for (const node of document.querySelectorAll("action-text-attachment[sgid]")) {
          const sgid = node.getAttribute("sgid")
          if (!this.sentSgids.has(sgid)) {
            this.sentSgids.add(sgid)
            return resolve(sgid)
          }
        }
        if (++attempts >= 20) return resolve(null)
        requestAnimationFrame(check)
      }
      check()
    })
  }

  register(payload, target, key) {
    if ((!payload.url && !payload.attachable_sgid) || this.operations.has(key)) return
    const context = this.chatIdValue ? { chat_id: this.chatIdValue } : { account_id: this.accountIdValue }
    const operation = { payload: { ...payload, ...context }, target, pending: false, failed: false }
    this.operations.set(key, operation)
    this.dirty = true
    this.run(operation)
  }

  async run(operation) {
    operation.pending = true
    operation.failed = false
    operation.controller = new AbortController()
    this.renderErrors()
    this.publishState()
    try {
      const response = await post("/chat_sources", {
        body: JSON.stringify(operation.payload), signal: operation.controller.signal,
        headers: { "Content-Type": "application/json", "Accept": "application/json" }
      })
      let data
      try { data = await response.json } catch { data = {} }
      if (!response.ok || !data.id) throw new Error(data.error || "Source registration failed. Retry or reset the draft.")
      if (operation.controller.signal.aborted || !this.element.isConnected) return
      this.addId(this[`${operation.target}Target`], data.id)
    } catch (failure) {
      if (failure.name !== "AbortError") {
        operation.failed = true
        operation.message = failure.message || "Source registration failed."
      }
    } finally {
      operation.pending = false
      if (this.element.isConnected) {
        this.renderErrors()
        this.publishState()
      }
    }
  }

  addId(target, id) {
    if (!target.name) throw new Error("Attachment form is unavailable. Reset the draft.")
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = target.name
    input.value = id
    target.parentNode.appendChild(input)
  }

  renderErrors() {
    this.errorsTarget.replaceChildren()
    const failures = [...this.operations.values()].filter(operation => operation.failed)
    this.errorsTarget.hidden = failures.length === 0
    for (const operation of failures) {
      const row = document.createElement("li")
      row.append(document.createTextNode(operation.message + " "))
      if (operation.payload) {
        const retry = document.createElement("button")
        retry.type = "button"
        retry.textContent = "Retry source"
        retry.addEventListener("click", () => this.run(operation))
        row.append(retry)
      }
      const reset = document.createElement("button")
      reset.type = "button"
      reset.textContent = "Reset draft"
      reset.addEventListener("click", () => {
        if (window.confirm("Reset this unsent draft? Saved sources will remain in their account.")) this.reset()
      })
      row.append(reset)
      this.errorsTarget.append(row)
    }
  }

  reset(event) {
    if (event?.detail?.root && !event.detail.root.contains(this.element)) return
    for (const operation of this.operations.values()) operation.controller?.abort()
    this.uploads.clear()
    this.operations.clear()
    this.sentSgids.clear()
    this.dirty = false
    this.editorTarget.value = ""
    for (const target of [this.websiteIdsTarget, this.documentIdsTarget]) {
      for (const input of target.parentNode.querySelectorAll("input")) {
        if (input.name === target.name) input.value = ""
      }
    }
    this.editorTarget.dispatchEvent(new CustomEvent("lexxy:change", { bubbles: true }))
    this.renderErrors()
    this.publishState()
  }

  publishState() {
    if (!this.element.isConnected) return
    const operations = [...this.operations.values()]
    this.dispatch("state", { detail: {
      pending: this.uploads.size + operations.filter(operation => operation.pending).length,
      failed: operations.some(operation => operation.failed), dirty: this.dirty
    } })
  }
}
```

In `composer_controller.js`, remove the `post` import; remove the `websiteIds`/`documentIds` targets and source-specific `sentSgids` state. Remove the `lexxy:insert-link`/`lexxy:upload-end` bindings/listeners and the complete methods `onInsertLink`, `onUploadEnd`, `nextUnsentAttachmentSgid`, `unsentSgidFromEditorValue`, and `addId`. Preserve `editor`, `menu`, `skills`, key handling, styling, submit locking, and all palette methods. These responsibilities now exist only in `composer_sources_controller.js`; no duplicate registration handlers may remain.

- [ ] Run the source system tests and existing source/message/controller tests. Expected GREEN; retry creates an account-correct reference, errors block both button and `requestSubmit`, and navigating away cannot append IDs to a different account's editor.
- [ ] Stage only the two JavaScript controllers and system test; commit `feat: register composer sources with explicit account context`.

## Task 9: Dashboard upload context, pending coordination, and retries

**Files:** Modify `app/javascript/controllers/dropzone_controller.js`; extend `test/system/chat_account_selection_test.rb`.

- [ ] Add these system tests and require `tempfile` at the top of the system-test file:

```ruby
test "dashboard uploads file into the selected account" do
  select "Research team", from: "Account"
  with_picker_pdf do |path|
    find("[data-dropzone-target='input']", visible: :all).set(path)
    assert_selector "[data-upload-status='success']"
    assert @second.documents.exists?(title: File.basename(path))
    assert_not @first.documents.exists?(title: File.basename(path))
    accept_confirm(/Saved sources remain/) { select "First team", from: "Account" }
    assert_no_selector "[data-upload-status]"
    assert @second.documents.exists?(title: File.basename(path))
  end
end

test "pending dashboard upload blocks switching and sending until complete" do
  install_dashboard_upload_gate
  with_picker_pdf do |path|
    find("[data-dropzone-target='input']", visible: :all).set(path)
    assert_selector "select[name='chat[account_id]'][disabled]"
    assert_button "Send", disabled: true
    page.execute_script("window.releasePickerUpload()")
    assert_selector "[data-upload-status='success']"
    assert_selector "select[name='chat[account_id]']:not([disabled])"
    assert_button "Send", disabled: false
  end
end

test "failed dashboard uploads can retry and then unblock sending" do
  page.execute_script(<<~JS)
    const original = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function(body) {
      XMLHttpRequest.prototype.send = original;
      queueMicrotask(() => this.onerror(new ProgressEvent('error')));
    };
  JS
  with_picker_pdf do |path|
    find("[data-dropzone-target='input']", visible: :all).set(path)
    assert_text "Upload failed. Retry or remove."
    assert_button "Send", disabled: true
    find("[data-action='dropzone#retryFile']").click
    assert_selector "[data-upload-status='success']"
    assert_button "Send", disabled: false
  end
end
```

Add these private system helpers:

```ruby
def with_picker_pdf
  Tempfile.create([ "chat-account", ".pdf" ]) do |file|
    file.write("%PDF-1.4\n% Upload-registration fixture; no parser is run.\n%%EOF\n")
    file.flush
    yield file.path
  end
end

def install_dashboard_upload_gate
  page.execute_script(<<~JS)
    const open = XMLHttpRequest.prototype.open;
    const send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
      this.pickerUploadPath = new URL(url, location.href).pathname;
      return open.call(this, method, url, ...rest);
    };
    XMLHttpRequest.prototype.send = function(body) {
      if (this.pickerUploadPath !== '/sources/documents') return send.call(this, body);
      window.releasePickerUpload = () => {
        XMLHttpRequest.prototype.open = open;
        XMLHttpRequest.prototype.send = send;
        send.call(this, body);
      };
    };
  JS
end
```

- [ ] Run the three dashboard tests with `PARALLEL_WORKERS=1 bin/rails test:system TEST=test/system/chat_account_selection_test.rb TESTOPTS='--name /dashboard/'`. Expected RED: no explicit account parameter or pending/error state exists. The default HTML redirect after upload also cannot display a second-account document through the default-account source page.
- [ ] Add an optional account value to the existing dropzone values and append its parameter only when present:

```javascript
accountId: String,
```

```javascript
if (this.hasAccountIdValue && this.accountIdValue) formData.append("document[account_id]", this.accountIdValue)
```

Before `xhr.send(formData)`, add:

```javascript
xhr.setRequestHeader("Accept", "application/json")
```

This avoids following the normal source-admin HTML redirect into a different default account. Keep FormData's browser-generated multipart content type.

In `_renderFileEntry`, immediately after creating its `li`, add `li.dataset.uploadStatus = status`. Before appending the row to the list, add this explicit error text:

```javascript
if (status === "error") {
  const message = document.createElement("span")
  message.setAttribute("role", "alert")
  message.textContent = "Upload failed. Retry or remove."
  li.appendChild(message)
}
```

Replace `_showValidationError` with a removable validation failure:

```javascript
_showValidationError(file) {
  const li = document.createElement("li")
  li.dataset.fileName = file.name
  li.dataset.uploadStatus = "error"
  li.className = "text-sm text-red-600"
  const message = document.createElement("span")
  message.setAttribute("role", "alert")
  message.textContent = `Invalid file: ${file.name}`
  const remove = document.createElement("button")
  remove.type = "button"
  remove.textContent = "Remove upload"
  remove.dataset.action = "dropzone#removeFile"
  li.append(message, remove)
  this.listTarget.appendChild(li)
  this.listTarget.classList.remove("hidden")
  this._publishChatSourceState()
}
```

Replace the existing `xhr.onload` and `xhr.onerror` handler bodies in `_uploadFile` with:

```javascript
xhr.onload = () => this._finishUpload(file, xhr.status >= 200 && xhr.status < 300 ? "success" : "error", xhr)
xhr.onerror = () => this._finishUpload(file, "error", xhr)
xhr.onabort = () => this._finishUpload(file, "error", xhr)
```

Add these methods to the controller:

```javascript
_finishUpload(file, status, xhr) {
  if (this.xhrsByFileName.get(file.name) !== xhr) return
  this.xhrsByFileName.delete(file.name)
  this.activeUploads = this.activeUploads.filter(active => active.name !== file.name)
  const entry = [...this.listTarget.querySelectorAll("[data-file-name]")].find(row => row.dataset.fileName === file.name)
  entry?.remove()
  this._renderFileEntry(file, status)
  this._dequeueNext()
  this._publishChatSourceState()
}

_publishChatSourceState() {
  if (!this.element.isConnected) return
  this.dispatch("state", { detail: {
    pending: this.activeUploads.length + this.uploadQueue.length,
    failed: Boolean(this.listTarget.querySelector("[data-upload-status='error']")),
    dirty: this.listTarget.children.length > 0
  } })
}

resetChatDraft(event) {
  if (!event.detail.root.contains(this.element)) return
  this._abortAllUploads()
  this.filesByName.clear()
  this.listTarget.replaceChildren()
  this.listTarget.classList.add("hidden")
  this.inputTarget.value = ""
  this._publishChatSourceState()
}
```

Add `queueMicrotask(() => this._publishChatSourceState())` at the end of `connect`. Publish state at the end of `_processFiles`, immediately after `activeUploads.push(file)` in `_uploadFile`, and at the end of `retryFile`. Existing failed rows are re-rendered with their existing retry and remove buttons, so the current `retryFile` method can reuse the retained File object.

Replace `removeFile` and `_abortAllUploads` to prevent abort callbacks from dequeuing more uploads during a reset:

```javascript
removeFile(event) {
  event.stopPropagation()
  const entry = event.currentTarget.closest("[data-file-name]")
  if (!entry) return
  const name = entry.dataset.fileName
  const xhr = this.xhrsByFileName.get(name)
  this.xhrsByFileName.delete(name)
  this.activeUploads = this.activeUploads.filter(file => file.name !== name)
  this.uploadQueue = this.uploadQueue.filter(file => file.name !== name)
  this.filesByName.delete(name)
  if (xhr) {
    xhr.onload = xhr.onerror = xhr.onabort = null
    xhr.abort()
  }
  entry.remove()
  if (this.listTarget.children.length === 0) this.listTarget.classList.add("hidden")
  this._dequeueNext()
  this._publishChatSourceState()
}

_abortAllUploads() {
  const requests = [...this.xhrsByFileName.values()]
  this.xhrsByFileName.clear()
  this.activeUploads = []
  this.uploadQueue = []
  for (const xhr of requests) {
    xhr.onload = xhr.onerror = xhr.onabort = null
    xhr.abort()
  }
}
```

Do not change source-admin account defaults: the account parameter is optional. No successful uploaded source is deleted when its display row is cleared.

- [ ] Run all feature system tests and `test/controllers/chat_account_sources_test.rb`. Expected GREEN, including a genuine multipart dashboard upload. Verify generic non-chat dropzones still accept uploads when no account value is provided.
- [ ] Stage the dropzone controller and system test; commit `feat: coordinate dashboard uploads with selected chat accounts`.

## Task 10: Account-scoped citations and real similarity-search regression

**Files:** Create `test/controllers/chat_account_citations_test.rb`; modify `app/controllers/chunks_controller.rb`, `app/models/message.rb`, `app/views/messages/_search_content.html.erb`; extend `test/models/chat_account_test.rb`.

- [ ] Create citation controller tests:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountCitationsTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  setup { sign_in_picker_user }

  test "citation lookup uses an owned chat account and preserves the old default" do
    width = Chunk.columns_hash.fetch("embedding").limit
    vector = [ 1.0 ] + Array.new(width - 1, 0.0)
    first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", vector)
    second = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", vector)
    chat = chats(:picker_second_chat)

    get chunk_url(second), params: { chat_id: chat.id }
    assert_response :success
    assert_includes response.body, "Research evidence"
    get chunk_url(first), params: { chat_id: chat.id }
    assert_response :not_found
    get chunk_url(second), params: { chat_id: chats(:picker_foreign_chat).id }
    assert_response :not_found
    get chunk_url(first)
    assert_response :success
    get chunk_url(second)
    assert_response :not_found

    @user.account_users.find_by!(account: @second).destroy!
    get chunk_url(second), params: { chat_id: chat.id }
    assert_response :not_found
  end
end
```

Append these model tests:

```ruby
test "cited evidence cannot include another account's chunk IDs" do
  width = Chunk.columns_hash.fetch("embedding").limit
  vector = [ 1.0 ] + Array.new(width - 1, 0.0)
  first = insert_picker_chunk(@first, texts(:picker_first_text), "First evidence", vector)
  second = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", vector)
  message = chats(:picker_second_chat).messages.create!(role: :assistant, content: "Answer",
    similar_chunk_ids: [ first.id.to_s, second.id.to_s ])
  assert_equal [ second.id ], message.similar_chunks.pluck(:id)
end

test "real nearest-neighbor retrieval excludes a closer first-account vector" do
  chat = chats(:picker_second_chat)
  width = Chunk.columns_hash.fetch("embedding").limit
  query = [ 1.0, 0.0 ] + Array.new(width - 2, 0.0)
  research = [ 0.8, 0.2 ] + Array.new(width - 2, 0.0)
  insert_picker_chunk(@first, texts(:picker_first_text), "Closer but forbidden", query)
  own = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", research)
  result = Struct.new(:vectors, :tokens).new(query, Struct.new(:input).new(3))
  original_limit = ENV["RETRIEVAL_FETCH_K"]
  ENV["RETRIEVAL_FETCH_K"] = "1"
  chat.define_singleton_method(:context_relevance) { |*args, **options| true }
  chat.define_singleton_method(:broadcast_thinking_phase) { |*args| }
  ActsAsTenant.with_tenant(@second) do
    with_singleton_replacement(RubyLLM, :embed, ->(*args, **options) { result }) do
      assert_equal [ own.id ], chat.similarity_search("Question").map(&:id)
    end
  end
  assert_equal @second.id, TokenUsage.where(chat: chat, kind: :embedding).last.account_id
ensure
  ENV["RETRIEVAL_FETCH_K"] = original_limit
end

test "saved-account prompt and completion usage do not use the first account" do
  chat = chats(:picker_second_chat)
  model_id = ruby_llm_models(:picker_model).id
  instructions = []
  chat.define_singleton_method(:with_model) { |*args, **options| }
  chat.define_singleton_method(:with_provider_options) { |**options| }
  chat.define_singleton_method(:with_temperature) { |*args| }
  chat.define_singleton_method(:mcp_tools) { [] }
  chat.define_singleton_method(:similarity_search) { |*args| [] }
  chat.define_singleton_method(:with_instructions) { |content, **options| instructions << content }
  chat.define_singleton_method(:broadcast_thinking_phase) { |*args| }
  chat.define_singleton_method(:answer_relevance) { |*args, **options| true }
  chat.define_singleton_method(:complete) do |&stream|
    messages.create!(role: :assistant, content: "Answer", model_id: model_id,
      input_tokens: 7, output_tokens: 2)
  end
  message = ActsAsTenant.with_tenant(@second) { chat.complete_with_nosia("Question") }
  assert_equal [ "Research account instructions" ], instructions
  assert_equal @second.id, TokenUsage.find_by!(source: message).account_id
end
```

- [ ] Run the new citation/model tests. Expected RED for cross-account evidence and citation HTTP lookup. The real similarity/prompt/usage tests are characterization tests and may already pass; do not change working retrieval merely to manufacture a red result.
- [ ] Include `ChatAccountScoped` in `ChunksController` and replace its `show` method:

```ruby
def show
  account = params[:chat_id].present? ? authorized_chat(params[:chat_id]).account : required_chat_account
  @chunk = account.chunks.find(params[:id])
end
```

Replace `Message#similar_chunks`:

```ruby
def similar_chunks
  chat.account.chunks.where(id: Array(similar_chunk_ids).uniq)
end
```

In `messages/_search_content.html.erb`, change only the link destination:

```erb
<%= link_to chunk_path(chunk, chat_id: message.chat_id), class: "block group", target: "_blank", rel: "noopener" do %>
```

- [ ] Add this link-rendering test inside `ChatAccountCitationsTest` after fixing the endpoint/model tests:

```ruby
test "rendered citations include the saved chat context" do
  chat = chats(:picker_second_chat)
  width = Chunk.columns_hash.fetch("embedding").limit
  own = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence",
    [ 1.0 ] + Array.new(width - 1, 0.0))
  chat.messages.create!(role: :assistant, content: "Cited answer", similar_chunk_ids: [ own.id.to_s ])
  get chat_url(chat)
  assert_select "a[href='#{chunk_path(own, chat_id: chat.id)}']", minimum: 1
end
```

- [ ] Run all new citation/model tests and existing `test/models/chat_test.rb`/`test/models/message_test.rb`. Expected GREEN; retrieval still uses the real pgvector relation and existing orphan filtering.
- [ ] Stage only the named model/controller/view/test files; commit `fix: resolve chat citations in their saved account`.

## Task 11: Full conversation, history, accessibility, and failure-reset regressions

**Files:** Extend `test/system/chat_account_selection_test.rb`. Production changes in this task should only correct a demonstrated defect in Tasks 6–9; do not add a new subsystem.

- [ ] Add the following integration-level browser tests before the system class's private helpers:

```ruby
test "sending fixes the account across reload follow-up and unlock" do
  select "Research team", from: "Account"
  write_draft("Research question")
  click_button "Send"
  assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
  assert_no_selector "select[name='chat[account_id]']"
  chat = @user.chats.order(:id).last
  assert_equal @second.id, chat.account_id
  assert chat.reload.generating

  chat.finish_generation!
  visit chat_url(chat)
  assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
  assert_button "Send", disabled: false
  write_draft("Follow-up question")
  click_button "Send"
  assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
  assert_equal @second.id, chat.reload.account_id
  assert_equal "Follow-up question", chat.messages.user.last.content.strip

  visit new_chat_url
  assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
end

test "account selection cannot change while the first-message POST is pending" do
  select "Research team", from: "Account"
  write_draft("Fixed at send time")
  page.execute_script(<<~JS)
    const original = window.fetch;
    window.fetch = (...args) => {
      const url = new URL(args[0] instanceof Request ? args[0].url : args[0], location.href);
      if (url.pathname !== '/chats') return original(...args);
      return new Promise((resolve, reject) => {
        window.releasePickerChat = () => {
          window.fetch = original;
          original(...args).then(resolve, reject);
        };
      });
    };
  JS
  click_button "Send"
  assert_selector "select[name='chat[account_id]'][disabled]"
  page.execute_script(<<~JS, @first.id.to_s)
    const picker = document.querySelector('select[name="chat[account_id]"]');
    picker.value = arguments[0];
    picker.dispatchEvent(new Event('change', { bubbles: true }));
  JS
  assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
  page.execute_script("window.releasePickerChat()")
  assert_selector "[data-chat-account-readonly]", text: "Account: Research team"
end

test "Turbo Back and Forward never restore cross-account references or tool choices" do
  write_draft("Discard this first-account draft")
  find("#chat-form details summary").click
  find("#chat-form input[type=checkbox][name='mcp_server_ids[]']").check
  dispatch_link("https://history-first.example/reference")
  assert_selector "input[name='chat[attached_website_ids][]']", count: 2, visible: :all
  accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }
  assert_equal [ "second-skill" ], browser_skills
  assert_no_selector "input[type=checkbox][name='mcp_server_ids[]']:checked", visible: :all
  assert_empty browser_website_ids

  page.go_back
  assert_selector "select option[selected][value='#{@first.id}']"
  assert_equal [ "first-skill" ], browser_skills
  assert_not_includes draft_html, "Discard this first-account draft"
  assert_no_selector "input[type=checkbox][name='mcp_server_ids[]']:checked", visible: :all
  assert_empty browser_website_ids

  page.go_forward
  assert_selector "select option[selected][value='#{@second.id}']"
  assert_equal [ "second-skill" ], browser_skills
  assert @first.websites.exists?(url: "https://history-first.example/reference")
end

test "footer selection is keyboard accessible on a narrow viewport" do
  page.current_window.resize_to(390, 844)
  picker = find("select[name='chat[account_id]']")
  picker.send_keys(:end)
  assert_selector "select option[selected][value='#{@second.id}']"
  assert_operator page.evaluate_script("document.querySelector('select[name=\"chat[account_id]\"]').getBoundingClientRect().right"), :<=,
    page.evaluate_script("window.innerWidth")
ensure
  page.current_window.resize_to(1400, 1400)
end

test "resetting a failed source clears only the unsent draft" do
  page.execute_script(<<~JS)
    const original = window.fetch;
    window.fetch = (...args) => {
      window.fetch = original;
      return Promise.reject(new TypeError('Network unavailable'));
    };
  JS
  write_draft("Unsaved draft")
  dispatch_link("https://reset-failure.example/reference")
  assert_button "Send", disabled: true
  assert_text "Network unavailable"
  accept_confirm(/Reset this unsent draft/) { click_on "Reset draft" }
  assert_button "Send", disabled: false
  assert_not_includes draft_html, "Unsaved draft"
  assert_no_selector "[data-composer-sources-target='errors']:not([hidden])"
  assert_equal @first.id, websites(:picker_first_website).reload.account_id
end
```

Add this private helper to the same class. Read actual form values rather than assuming blank hidden fields have a `value` HTML attribute:

```ruby
def browser_website_ids
  page.evaluate_script("Array.from(document.querySelectorAll('input[name=\"chat[attached_website_ids][]\"]')).map(input => input.value).filter(Boolean)")
end
```

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test:system TEST=test/system/chat_account_selection_test.rb`. Expected GREEN if earlier tasks are correct. These are cross-component verification tests; do not manufacture failures in working code. If a test fails, use `systematic-debugging` and preserve the new failing test before applying a focused correction.
- [ ] Run all new controller/model feature files in one process followed by the old baseline files. Expected GREEN with no leaked fixtures, singleton stubs, queue adapters, or tenant state.
- [ ] Stage only the additional system tests and any proven narrowly scoped correction; commit `test: verify chat account isolation across browser lifecycles`.

## Task 12: Documentation, review gates, and complete verification

**Files:** Create `docs/chat-account-selection.md`; modify `docs/README.md`; add YARD comments to changed public Ruby interfaces where missing. Do not change dependency files, schema, or deployment configuration.

- [ ] Create `docs/chat-account-selection.md` with this content:

```markdown
# Choosing an account for a chat

Choose an account in the new-chat composer's footer before sending the first message.
The first account is preselected for every new chat; the last selection is not remembered.
Only accounts you belong to are offered.

The chosen account supplies document retrieval, pasted links, PDF uploads, dashboard
uploads, MCP tools, slash-command skills, system prompts, and token usage attribution.
The dashboard upload area files documents into that account but does not automatically
attach them to a message.

Changing accounts asks before clearing an unsent draft, attachment references, uploaded
file display rows, and tool selections. Saved sources remain in their original account;
switching never moves or deletes them. Cancel keeps the draft intact.

Account changes and sending wait for uploads/source registration to finish. A failed
registration must be retried successfully or removed/reset before sending.

After the first message, the footer shows a read-only account name. To use another
account, start a new chat. Choosing a chat account does not switch the account used by
other application pages.

## Request contract

- New-chat entry points accept a membership-checked `account_id` query parameter.
- New chats submit `chat[account_id]`.
- New-chat source registration submits `account_id`; saved-chat registration submits
  `chat_id` and derives its account from that owned, membership-authorized chat.
- Dashboard uploads submit `document[account_id]` to the existing document endpoint.
- Citation links include `chat_id`; chunks are resolved through that chat's account.
- Saved-chat account overrides cannot reassign the conversation.

An omitted/blank new-chat account keeps the existing first-account fallback. Explicit
unknown/unauthorized IDs or wrong-account source/tool IDs return 404. No available
account returns 422 for creation and displays an explanatory empty state on chat pages.
Invalid attachment SGIDs retain the existing 400 response.

Generation and broadcast rendering use the persisted chat account, without requiring a
request session. Membership is checked for web actions; interrupting an already-running
generation immediately after a membership change is not part of this feature.

No schema migration, global account preference, API contract change, or retrieval
algorithm change is required.
```

Under `docs/README.md`'s Development quick links, add:

```markdown
- [Chat account selection](chat-account-selection.md) — picker behavior, account boundaries, and source request context.
```

Add these exact YARD comments above the corresponding changed public methods when they do not already have equivalent documentation:

```ruby
# Above Chat::ModelContextProtocol#add_mcp_server:
# @param mcp_server [McpServer] Server belonging to this chat's account
# @return [ChatMcpSession] Existing or newly created link
# @raise [ActiveRecord::RecordNotFound] if the server belongs to another account

# Above Chat::ModelContextProtocol#mcp_tools:
# @return [Array] Enabled, ready tool objects from this chat's account

# Above AgentSkillsHelper#agent_skill_autocomplete_data:
# @param account [Account] Explicit account for request or background rendering
# @return [String] JSON array of slash-invocable skill names and descriptions

# Above Message#similar_chunks:
# @return [ActiveRecord::Relation<Chunk>] Cited chunks belonging to the chat account
```

- [ ] Run the focused feature tests explicitly:

```bash
PARALLEL_WORKERS=1 bin/rails test test/models/chat_account_fixture_test.rb test/models/chat_account_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb
```

Expected: zero failures/errors. Then run separately:

```bash
PARALLEL_WORKERS=1 bin/rails test:system TEST=test/system/chat_account_selection_test.rb
```

Expected: all new browser tests run, zero failures/errors, no silent browser skips.

- [ ] Run `PARALLEL_WORKERS=1 bin/rails test`. Expected: no new failures. Record baseline/environment failures precisely rather than declaring an unverified full-suite pass.
- [ ] Run `bin/rubocop app/controllers app/models app/helpers app/jobs test/controllers/chat_account_selection_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb test/models/chat_account_test.rb test/models/chat_account_fixture_test.rb test/support/chat_account_fixtures.rb test/system/chat_account_selection_test.rb`. Review offenses against the changed lines; do not auto-correct unrelated files.
- [ ] Run `bin/brakeman --no-pager`. Compare warnings with the baseline; resolve new warnings introduced by this feature. There is no `bin/ci` in this repository, so do not invent a CI command.
- [ ] Run `git diff --check` and `git status --short`. Expected: only intended feature/documentation changes and no whitespace errors. Verify no migration or dependency changes were added.
- [ ] Manually paste a real PDF and a URL into each new-chat entry point with two accounts. Confirm the footer picker, saved source account, refreshed tools/skills, failure/retry feedback, citations, read-only label, and dark/narrow layout. Do not use live AI as a substitute for automated account isolation tests.
- [ ] Use `rails-code-review` and `rails-security-review` to self-review changed authorization, reference validation, tenant restoration, upload cancellation, and background rendering. Follow `requesting-code-review` for the selected execution workflow; do not create a PR or merge without the user's instruction.
- [ ] Explicitly stage `docs/chat-account-selection.md`, `docs/README.md`, and the Ruby files receiving documentation comments; commit `docs: explain chat account selection and isolation`.
- [ ] Use `verification-before-completion` before claiming implementation success. Report exact test/lint outcomes and any blockers, not just commands that were attempted.

## Plan-to-spec coverage

| Approved requirement | Tasks |
| --- | --- |
| First-account default, membership-only picker on both entry points | 2, 6, 7 |
| Footer layout B; read-only saved account and background unlock label | 6, 11 |
| Account fixed after creation; no global account switch or schema change | 2, 3, 11, 12 |
| Confirm/cancel draft resets; leave saved sources in the original account | 7, 8, 9, 11 |
| Selected-account initial/follow-up URL/PDF/dashboard uploads | 3, 4, 8, 9 |
| Pending/failed registration blocks account changes or sending as specified | 7, 8, 9, 11 |
| Selected-account MCP and skill options; bounded tenant context | 3, 5, 6, 7 |
| Membership/ownership checks and no side effects for invalid resource IDs | 2, 3, 4, 5, 10 |
| No-account empty state and 422 creation; SGID 400 and invalid ID 404 | 2, 4, 6, 8 |
| Real account-scoped similarity, prompts, query/completion token attribution | 5, 10 |
| Account-correct citation rendering and access | 10 |
| Turbo Back/Forward, generation locking, reload, keyboard/narrow access | 6, 7, 8, 11 |
| Minitest fixtures without changing legacy suite initial data | 1, 12 |
| Documentation, YARD, security/code review, test evidence | 12 |

## Execution handoff

Planning checks completed: the coverage matrix was checked against the approved spec; placeholder and whitespace scans were clean; all 45 Ruby snippets parsed (keyword fragments in their hash context), and the Ruby generated by all 10 YAML/ERB fixture templates parsed. These are documentation checks only. No application or test files were changed, and no application tests were run in this planning step.

After the plan is reviewed, offer **Subagent-Driven (recommended)** or **Inline Execution**. Load `subagent-driven-development` for the first choice or `executing-plans` for the second. Follow the red/green gates task by task; this document's implementation snippets are instructions, not evidence that application code has been written or verified.
