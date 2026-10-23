# Account Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the thin account directory with useful account cards and a balanced account overview, with safe account-specific entrypoints into existing tools and conversations.

**Architecture:** Keep the existing source, token, usage, and prompt implementations. Explicit membership-authorized route context, shared controller concerns, and account-aware path helpers carry the selected account through their existing workflows; background source rows derive account identity from their record. Model-owned summary queries and bounded history feed small ERB partials, with no global account switch, services layer, or schema change.

**Tech Stack:** Actual checkout: Ruby 4.0.7, Rails 8.0.x, PostgreSQL/pgvector, ERB, Turbo, Stimulus/importmap, Tailwind 4, Minitest/fixtures, Selenium/Chrome. Preserve installed dependencies and integer IDs; do not migrate the schema to the aspirational versions/UUID conventions in `AGENTS.md`.

---

## Approved scope and workspace

- Read `docs/superpowers/specs/2026-10-23-account-experience-design.md`. The user approved the committed spec with **“Go”**. This plan does not bypass the execution handoff.
- Branch: `feat/account-experience`.
- Worktree: `/home/cbldev/gitd/dilolabs/nosia/.worktrees/account-experience`.
- Base: `e4ec6b1`, containing only the approved design document over the existing application.
- Planning verification: `bundle check` passed. No application code, databases, or test data were changed during planning. Task 0 establishes the execution baseline.
- The original worktree has unrelated modified/untracked files. Do not stage, reset, copy, or overwrite them. Use explicit feature paths for every commit.
- This is one account-context/navigation feature over existing subsystems, not separate source ingestion, analytics, billing, or authentication projects.
- Each implementation step follows **write test → run and observe the intended failure → minimal implementation → rerun → commit**. Never treat an environment error as the required failing test.

## Contracts fixed by the design

| Concern | Contract |
| --- | --- |
| Directory | 24 accounts/page, name then ID ascending; grouped visible-page source and personal root-chat counts. |
| Hub | Sources and five recent personal conversations on the left; lifetime usage, shared-default prompt, users, personal tokens on the right. |
| History | Current user's root chats in the viewed account only; 25/page, updated time then ID descending. |
| Administration | Only the owner edits account details/shared prompts or accesses/manages membership. Members may read shared prompts and account-wide usage. |
| API tokens | Current user's tokens intersected with the viewed account, including create/revoke; plaintext shown once, never on the hub. |
| Context | `/accounts/:account_id/...` is authoritative; reject conflicting form context. Do not set `Current.account` or remember a global selection. |
| Errors | Account/record mismatches, malformed context, outsiders: 404 and no writes/jobs. Member requesting owner-only operation: 403 without redirects. Invalid forms: 422 with inputs/errors. |
| Chat entry | Existing `/chats/new?account_id=...`; preselected, not locked until first send. No composer-contract rewrite. |
| Read behavior | Hub/usage/history/prompt reads never create records, start ingestion/generation, or call providers. |
| Compatibility | Legacy non-account routes keep default context, except intentional owner-only shared-prompt protection and account-settings redirect. |

## File map and responsibilities

All paths below are relative to the worktree.

| Files | Responsibility |
| --- | --- |
| `app/controllers/concerns/account_scoped.rb` | Membership lookup, scalar-ID checks, owner predicate/403 guard; never a mutable global tenant. |
| `app/controllers/concerns/source_scoped.rb` | Resolve route account or legacy fallback; fixed filing account and shared source URL helpers. |
| `app/helpers/sources_helper.rb` | Canonical record-derived account source paths, contextual collection/form paths; safe for background rendering. |
| `app/helpers/accounts_helper.rb` | Role labels, plain conversation titles, account breadcrumbs/drawer visibility. |
| `app/models/account/overview.rb`, `app/models/account.rb` | Grouped index counts and scoped ordered personal root-chat relation. |
| `app/models/chat.rb` | Batch first-user-question lookup for a bounded set of chats. |
| `app/controllers/accounts_controller.rb` | Directory pagination, hub composition, owner-only editing, hub redirects. |
| `app/controllers/accounts/chats_controller.rb` | Private account history index only. |
| `app/controllers/sources_controller.rb` | Existing source list over an explicit source account. |
| `app/controllers/sources/documents_controller.rb`, `texts_controller.rb`, `qnas_controller.rb`, `websites_controller.rb` | Reuse existing source CRUD and indexing behavior with scoped lookups/filing/redirects. |
| `app/controllers/sources/retries_controller.rb` | Common REST create orchestration for scoped retry resources. |
| `app/controllers/sources/documents/retries_controller.rb`, `texts/retries_controller.rb`, `qnas/retries_controller.rb`, `websites/retries_controller.rb` | Four narrow source/job bindings, not new ingestion logic. |
| `app/controllers/api_tokens_controller.rb`, `app/controllers/token_usages_controller.rb` | Shared global/scoped personal token management and scoped account reporting. |
| `app/controllers/accounts/account_users_controller.rb`, `system_prompts_controller.rb`, `settings_controller.rb`, `app/controllers/system_prompts_controller.rb` | Owner guards, read-only member prompt view, legacy shared-prompt bypass closure, old settings redirect. |
| `config/routes.rb` | Show route and nested existing tools, history, and REST retry resources; preserve legacy routes. |
| `app/views/accounts/index.html.erb`, `show.html.erb`, `_account.html.erb`, `_sources.html.erb`, `_conversations.html.erb`, `_usage.html.erb`, `_configuration.html.erb`, `_pagination.html.erb`, `_breadcrumb.html.erb` | Focused directory/hub composition and summaries. |
| `app/views/accounts/chats/index.html.erb` | Full private history using the shared conversation rows. |
| `app/views/accounts/_form.html.erb`, `edit.html.erb`, `account_users/index.html.erb`, `system_prompts/show.html.erb`, `system_prompts/edit.html.erb`, `app/views/system_prompts/show.html.erb` | Hub return paths, real breadcrumbs, owner-visible management including the legacy shared-prompt view. |
| `app/views/sources/index.html.erb`, `index.turbo_stream.erb`, `_source_filters.html.erb`, `_toolbar.html.erb`, `_rows.html.erb`, `_add_menu.html.erb`, `_empty.html.erb`, `_source.html.erb`, `_account_field.html.erb` | Existing list/stream/form behavior with explicit paths and scoped context. |
| `app/views/application/_validation_errors.html.erb` | Shared visible validation errors for source, token, account, and prompt forms. |
| `app/views/sources/documents/{new,edit,show,_form}.html.erb`, `app/views/sources/texts/{new,edit,show,_form}.html.erb`, `app/views/sources/qnas/{new,edit,show,_form}.html.erb`, `app/views/sources/websites/{new,edit,show,_form}.html.erb`, `app/views/sources/documents/_document.json.jbuilder` | Existing content preserved; change paths, account selector, cancel/error semantics, and JSON location only. |
| `app/views/api_tokens/index.html.erb`, `_form.html.erb`, `app/views/token_usages/show.html.erb`, `app/views/layouts/application.html.erb` | Account-aware tool shell, drawer suppression, browser zoom. |
| `app/assets/stylesheets/nosia/accounts.css`, `app/assets/tailwind/application.css` | Account-scoped responsive styling and import, not a global redesign. |
| `config/locales/en.nosia_account_experience.yml`, `fr.nosia_account_experience.yml` | New English/French copy. |
| `test/support/account_experience_fixtures.rb`, `test/support/fixtures/account_experience/*.yml`, `test/fixtures/files/account_source.txt` | Opt-in feature fixtures, independent of existing chat fixture data. |
| `test/models/account_overview_test.rb`, `test/controllers/account_experience_test.rb`, `accounts/administration_test.rb`, `accounts/scoped_sources_test.rb`, `accounts/scoped_source_operations_test.rb`, `accounts/scoped_tokens_usage_test.rb`, `test/models/account_source_broadcast_test.rb`, `test/system/account_experience_test.rb` | Behavioral, isolation, permissions, performance, and browser coverage. |
| `docs/account-experience.md`, `docs/README.md`, `docs/DIAGRAMS.md` | User behavior, context/permission contracts, entrypoint diagram, verification evidence. |

## Task 0: Establish an isolated execution baseline

- [ ] Run `git status --short` and `bundle check` in this worktree. Expect documentation-only changes and satisfied dependencies. If dependencies are missing, resolve with the user; do not update `Gemfile.lock` for this feature.
- [ ] Prepare a **dedicated test-only** PostgreSQL database. The ignored original `.env` supplies encryption settings without being copied or displayed. Explicit process environment overrides it. Never use development/production or another active worktree's test database.

```bash
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key bundle exec dotenv -f ../../.env -- bin/rails db:prepare
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts_controller_test.rb test/controllers/sources_controller_test.rb test/controllers/api_tokens_controller_test.rb test/controllers/accounts/account_users_authorization_test.rb test/controllers/accounts/system_prompts_controller_test.rb
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test > /tmp/opencode/account-experience-baseline.log 2>&1
```

Expected: preparation succeeds and focused tests pass. Record full-suite counts and exact failures. If anything fails, stop before application changes and obtain a decision; never label a failed baseline green. Run all database-sharing test processes sequentially.

- [ ] Run `command -v chromium` and `command -v chromedriver`. Use the available local browser/driver for system verification; do not install packages. Avoid the incomplete remote URL in `test/application_system_test_case.rb`.
- [ ] For each later test command, keep the same explicit database, dummy key, dotenv prefix, and `PARALLEL_WORKERS=1` shown here. Do not run workers or real model providers.

## Task 1: Add isolated fixtures and model-owned summary queries

**Files:** Create `test/support/account_experience_fixtures.rb`, the fixture files listed below, `test/fixtures/files/account_source.txt`, `test/models/account_overview_test.rb`, and `app/models/account/overview.rb`; modify `app/models/account.rb` and `app/models/chat.rb`.

- [ ] **Step 1: Add the feature fixture dataset and loader.** These fixtures are opt-in, not additions to global fixtures or the existing `ChatAccountFixtures` dataset. Put `Account fixture text.` in `test/fixtures/files/account_source.txt`.

```ruby
# test/support/account_experience_fixtures.rb
require "active_job/test_helper"
require "active_storage/fixture_set"

module AccountExperienceFixtures
  extend ActiveSupport::Concern
  include ActiveJob::TestHelper
  PASSWORD = "account-experience-password-123".freeze
  TABLES = %w[users accounts account_users ruby_llm_models chats messages documents texts qnas websites prompts api_tokens token_usages active_storage_blobs active_storage_attachments].freeze

  included do
    setup do
      @previous_tenant = ActsAsTenant.current_tenant
      @previous_adapter = ActiveJob::Base.queue_adapter
      ActsAsTenant.current_tenant = nil
      ActiveJob::Base.queue_adapter = :test
      ActiveRecord::FixtureSet.reset_cache
      @experience_sets = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/account_experience").to_s,
        TABLES,
        { "ruby_llm_models" => "RubyLLM::ActiveRecord::Model",
          "active_storage_blobs" => "ActiveStorage::Blob",
          "active_storage_attachments" => "ActiveStorage::Attachment" }
      ).index_by(&:name)
      @user = experience(:users, :overview_owner)
      @member = experience(:users, :overview_member)
      @first = experience(:accounts, :overview_first)
      @second = experience(:accounts, :overview_second)
      @foreign = experience(:accounts, :overview_foreign)
      @empty = experience(:accounts, :overview_empty)
      clear_enqueued_jobs
    end

    teardown do
      clear_enqueued_jobs
      ActiveJob::Base.queue_adapter = @previous_adapter
      ActsAsTenant.current_tenant = @previous_tenant
      Current.reset
      ActiveRecord::FixtureSet.reset_cache
    end
  end

  def experience(table, name)
    @experience_sets.fetch(table.to_s).fixtures.fetch(name.to_s).find
  end

  def sign_in_overview(user = @user)
    delete logout_url if cookies[:session_id]
    post login_url, params: { email: user.email, password: PASSWORD }
    assert_response :redirect
  end
end
```

Write these exact files under `test/support/fixtures/account_experience/`:

```yaml
# users.yml
<% %w[owner member outsider no_account].each do |role| %>
overview_<%= role %>:
  email: <%= User.type_for_attribute("email").serialize("overview-#{role}@example.com").to_json %>
  password_digest: <%= BCrypt::Password.create("account-experience-password-123", cost: BCrypt::Engine::MIN_COST).to_json %>
<% end %>
```

```yaml
# accounts.yml
overview_first:
  name: Alpha team
  uid: alpha-team
  owner: overview_owner
  input_tokens_count: 10
  output_tokens_count: 2
  created_at: 2026-01-01 00:00:00
overview_second:
  name: Research team
  uid: research-team
  owner: overview_owner
  input_tokens_count: 900
  output_tokens_count: 100
  created_at: 2026-01-02 00:00:00
overview_foreign:
  name: Private team
  owner: overview_outsider
overview_empty:
  name: Empty team
  owner: overview_owner
```

```yaml
# account_users.yml
<% %w[first second empty].each do |account| %>
overview_owner_<%= account %>:
  account: overview_<%= account %>
  user: overview_owner
<% end %>
overview_member_second:
  account: overview_second
  user: overview_member
overview_outsider_foreign:
  account: overview_foreign
  user: overview_outsider
```

```yaml
# ruby_llm_models.yml
overview_model:
  model_id: overview-test-model
  provider: openai
  name: Overview test model
```

```yaml
# chats.yml
overview_first_chat:
  account: overview_first
  user: overview_owner
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:overview_model) %>
overview_foreign_chat:
  account: overview_foreign
  user: overview_outsider
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:overview_model) %>
overview_member_chat:
  account: overview_second
  user: overview_member
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:overview_model) %>
overview_child_chat:
  account: overview_second
  user: overview_owner
  chat: overview_second_chat_0
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:overview_model) %>
<% 28.times do |i| %>
overview_second_chat_<%= i %>:
  account: overview_second
  user: overview_owner
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:overview_model) %>
  updated_at: <%= (Time.utc(2026, 1, 4) + i.minutes).iso8601 %>
<% end %>
```

```yaml
# messages.yml
overview_first_question:
  chat: overview_first_chat
  role: 20
  content: Alpha private question
overview_member_question:
  chat: overview_member_chat
  role: 20
  content: Member private question
<% 28.times do |i| %>
overview_second_question_<%= i %>:
  chat: overview_second_chat_<%= i %>
  role: 20
  content: Research question <%= i %>
  created_at: 2026-01-01 00:00:00
<% end %>
```

```yaml
# documents.yml
<% %w[first second].each do |account| %>
overview_<%= account %>_document:
  account: overview_<%= account %>
  title: <%= account.capitalize %> document
  index_status: 10
<% end %>
```

```yaml
# active_storage_blobs.yml
overview_blob: <%= ActiveStorage::FixtureSet.blob(filename: "account_source.txt") %>
```

```yaml
# active_storage_attachments.yml
<% %w[first second].each do |account| %>
overview_<%= account %>_file:
  name: file
  record: overview_<%= account %>_document (Document)
  blob: overview_blob
<% end %>
```

```yaml
# texts.yml
overview_first_text:
  account: overview_first
  title: Alpha evidence
  data: Alpha evidence
  index_status: 10
overview_second_text:
  account: overview_second
  title: Research evidence
  data: Research evidence
  index_status: 20
```

```yaml
# qnas.yml
overview_second_qna:
  account: overview_second
  question: Research policy?
  answer: Research answer
  index_status: 10
```

```yaml
# websites.yml
overview_second_website:
  account: overview_second
  url: https://research.example/reference
  data: "# Research website"
  index_status: 0
```

```yaml
# prompts.yml
overview_second_shared:
  account: overview_second
  name: system_prompt
  content: Shared research instructions
overview_second_personal:
  account: overview_second
  user: overview_member
  name: system_prompt
  content: Personal research override
```

```yaml
# api_tokens.yml
<% { first: "owner", second: "owner", member: "member" }.each do |key, role| %>
overview_<%= key %>_token:
  account: overview_<%= key == :first ? "first" : "second" %>
  user: overview_<%= role %>
  name: <%= key %> token
  token_digest: <%= ApiToken.digest("overview-#{key}-secret") %>
<% end %>
```

```yaml
# token_usages.yml
overview_first_usage:
  account: overview_first
  kind: completion
  model_id: overview-test-model
  input_tokens: 10
  output_tokens: 2
overview_second_usage:
  account: overview_second
  kind: completion
  model_id: overview-test-model
  input_tokens: 900
  output_tokens: 100
```

- [ ] **Step 2: Write model regression tests.** Add the following complete test class.

```ruby
require "test_helper"
require_relative "../support/account_experience_fixtures"

class AccountOverviewTest < ActiveSupport::TestCase
  include AccountExperienceFixtures

  test "directory summaries count only sources and the viewer's root chats" do
    counts = Account.overview_counts_for([ @first, @second, @empty ], user: @user)
    assert_equal({ sources: 2, conversations: 1 }, counts.fetch(@first.id))
    assert_equal({ sources: 4, conversations: 28 }, counts.fetch(@second.id))
    assert_equal({ sources: 0, conversations: 0 }, counts.fetch(@empty.id))
    refute counts.key?(@foreign.id)
    assert_equal 1, Account.overview_counts_for([ @second ], user: @member).fetch(@second.id)[:conversations]
  end

  test "recent chats are ordered and restricted to this account and viewer" do
    rows = @second.conversations_for(@user).limit(5).to_a
    assert_equal 5, rows.size
    assert_equal experience(:chats, :overview_second_chat_27).id, rows.first.id
    assert rows.all? { |chat| chat.account_id == @second.id && chat.user_id == @user.id && chat.chat_id.nil? }
  end

  test "first questions are fetched in one query and preserve first-user-message semantics" do
    rows = @second.conversations_for(@user).limit(5).to_a
    statements = []
    subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }
    titles = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { Chat.first_questions_for(rows) }
    assert_equal "Research question 27", titles.fetch(rows.first.id)
    assert_equal 1, statements.grep(/SELECT/i).size
  end
end
```

- [ ] **Step 3: Run RED.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/models/account_overview_test.rb
```

Expected: fixtures load successfully; tests fail because `overview_counts_for`, `conversations_for`, and `first_questions_for` are absent. Correct fixture/environment mistakes before proceeding.

- [ ] **Step 4: Implement the model contracts.** Create this concern and add `include Overview` inside `Account`.

```ruby
# app/models/account/overview.rb
module Account::Overview
  extend ActiveSupport::Concern

  class_methods do
    # Counts visible accounts without per-card association queries.
    # @param accounts [Array<Account>] Already-authorized visible directory page
    # @param user [User] The viewer whose private chat counts may be disclosed
    # @return [Hash<Integer, Hash<Symbol, Integer>>]
    def overview_counts_for(accounts, user:)
      ids = accounts.map(&:id)
      counts = ids.index_with { { sources: 0, conversations: 0 } }
      unless ids.empty?
        [ Document, Text, Qna, Website ].each do |model|
          model.where(account_id: ids).group(:account_id).count.each do |account_id, count|
            counts.fetch(account_id)[:sources] += count
          end
        end
        user.chats.root.where(account_id: ids).group(:account_id).count.each do |account_id, count|
          counts.fetch(account_id)[:conversations] = count
        end
      end
      counts
    end
  end

  # @param user [User] The authenticated viewer
  # @return [ActiveRecord::Relation<Chat>] Private root chats, latest activity first
  def conversations_for(user)
    chats.root.where(user: user).order(updated_at: :desc, id: :desc)
  end
end
```

Add this class method to `Chat`, before its public instance methods. This is explicitly PostgreSQL, matching `config/database.yml`; do not introduce a cross-database abstraction.

```ruby
# @param chats [Array<Chat>] Already-authorized, bounded rows
# @return [Hash] First user-question markup keyed by chat ID; blank messages may map to nil
def self.first_questions_for(chats)
  return {} if chats.empty?

  Message.user.where(chat_id: chats.map(&:id))
    .select("DISTINCT ON (chat_id) messages.*")
    .reorder(:chat_id, :created_at, :id)
    .to_h { |message| [ message.chat_id, message.question ] }
end
```

- [ ] **Step 5: Run GREEN and commit.** Repeat the Step 3 command; expect all tests passing. Then:

```bash
git add app/models/account.rb app/models/account/overview.rb app/models/chat.rb test/support/account_experience_fixtures.rb test/support/fixtures/account_experience test/fixtures/files/account_source.txt test/models/account_overview_test.rb
git commit -m "feat(accounts): add bounded overview queries and fixtures"
```

## Task 2: Enforce owner-only administration on every entrypoint

**Files:** Create `app/controllers/concerns/account_scoped.rb` and `test/controllers/accounts/administration_test.rb`; modify `app/controllers/accounts_controller.rb`, `app/controllers/accounts/account_users_controller.rb`, `app/controllers/accounts/system_prompts_controller.rb`, `app/controllers/system_prompts_controller.rb`, and the existing `test/controllers/accounts/account_users_authorization_test.rb`.

- [ ] **Step 1: Write the failing request tests.**

```ruby
require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::AdministrationTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview(@member) }

  test "member cannot edit account details or manage membership" do
    get edit_account_path(@second)
    assert_response :forbidden
    assert_no_changes -> { @second.reload.name } do
      patch account_path(@second), params: { account: { name: "Changed" } }
    end
    assert_response :forbidden
    get account_account_users_path(@second)
    assert_response :forbidden
    assert_no_difference "AccountUser.count" do
      post account_account_users_path(@second), params: { account_user: { email: @user.email } }
      assert_response :forbidden
      delete account_account_user_path(@second, experience(:account_users, :overview_owner_second))
      assert_response :forbidden
    end
  end

  test "shared prompt is readable but only the owner may mutate it, including legacy routes" do
    prompt = experience(:prompts, :overview_second_shared)
    get account_system_prompt_path(@second)
    assert_response :success
    get edit_account_system_prompt_path(@second)
    assert_response :forbidden
    assert_no_changes -> { prompt.reload.content } do
      patch account_system_prompt_path(@second), params: { prompt: { content: "Hijack" } }
      assert_response :forbidden
      patch system_prompt_path(prompt), params: { prompt: { content: "Legacy hijack" } }
      assert_response :forbidden
    end
    get edit_system_prompt_path(prompt)
    assert_response :forbidden
    assert_no_difference "Prompt.count" do
      delete system_prompt_path(prompt)
      assert_response :forbidden
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "personal override editing remains unchanged" do
    prompt = experience(:prompts, :overview_second_personal)
    patch system_prompt_path(prompt), params: { prompt: { content: "My replacement override" } }
    assert_response :redirect
    assert_equal "My replacement override", prompt.reload.content
  end

  test "owner can save a shared prompt and invalid input stays editable with 422" do
    sign_in_overview
    patch account_system_prompt_path(@second), params: { prompt: { content: "Owner replacement" } }
    assert_redirected_to account_system_prompt_path(@second)
    patch account_system_prompt_path(@second), params: { prompt: { content: "" } }
    assert_response :unprocessable_entity
    assert_select "textarea[name='prompt[content]']"
  end

  test "outsider cannot reach account administration" do
    get edit_account_path(@foreign)
    assert_response :not_found
    get account_account_users_path(@foreign)
    assert_response :not_found
  end
end
```

- [ ] **Step 2: Run RED.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/administration_test.rb
```

Expected: the current member edit/update behavior and membership redirects fail the new 403 assertions; legacy shared-prompt mutation fails the protection assertions.

- [ ] **Step 3: Add the shared boundary.**

```ruby
# app/controllers/concerns/account_scoped.rb
module AccountScoped
  extend ActiveSupport::Concern

  included do
    helper_method :account_owner?
  end

  private
    # @param id [String, Numeric]
    # @return [Account] An account the current user still belongs to
    # @raise [ActiveRecord::RecordNotFound] For malformed or unauthorized IDs
    def member_account(id)
      raise ActiveRecord::RecordNotFound unless id.is_a?(String) || id.is_a?(Numeric)
      Current.user.accounts.find(id)
    end

    def account_owner?(account = @account)
      account.present? && account.owner_id == Current.user.id
    end

    def require_account_owner
      head :forbidden unless account_owner?
    end
end
```

Apply these exact callback/method changes, retaining the rest of each controller:

```ruby
# AccountsController: include, callbacks, and replacement set_account
include AccountScoped
before_action :require_account_owner, only: [ :edit, :update ]

private
  def set_account
    @account = member_account(request.path_parameters.fetch(:id))
  end
```

The existing `before_action :set_account` must stay **before** the owner guard. In `Accounts::AccountUsersController`, replace its callback block with this order, remove the old `require_owner` method, and use the same membership-aware `set_account` below:

```ruby
include AccountScoped
before_action :set_account
before_action :require_account_owner
before_action :set_user, only: :create
before_action :set_account_user, only: :destroy

private
  def set_account
    @account = member_account(request.path_parameters.fetch(:account_id))
  end
```

In `Accounts::SystemPromptsController`, include `AccountScoped`, replace callbacks with `set_account` followed by `require_account_owner, only: [ :edit, :update ]`, and remove the old `before_action :set_system_prompt`/`set_system_prompt` method. Replace the following methods:

```ruby
def update
  @system_prompt = default_or_existing_prompt
  if @system_prompt.update(system_prompt_params)
    redirect_to account_system_prompt_path(@account), notice: t("nosia.prompts.updated")
  else
    render :edit, status: :unprocessable_entity
  end
end

private
  def set_account
    @account = member_account(request.path_parameters.fetch(:account_id))
  end
```

This avoids writing a default record before validating a failed update. The existing `default_or_existing_prompt` already provides the in-memory default for GETs.

In global `SystemPromptsController`, include `AccountScoped` and register this guard **after** `set_system_prompt`:

```ruby
before_action :require_shared_prompt_owner, only: [ :edit, :update, :destroy ]

private
  def require_shared_prompt_owner
    if @system_prompt.user_id.nil?
      @account = @system_prompt.account
      require_account_owner
    end
  end
```

Do not accidentally treat a personal prompt as the shared prompt or change personal prompt selection/generation. Do not broaden personal prompt authorization in this feature.

- [ ] **Step 4: Update the two existing member-denial tests.** In `test/controllers/accounts/account_users_authorization_test.rb`, replace their `assert_redirected_to account_account_users_path(@account)` with `assert_response :forbidden`; remove the member-denial flash assertion. Keep the owner's successful add/remove and protected-owner-removal redirect expectations unchanged.
- [ ] **Step 5: Run GREEN and commit.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/administration_test.rb test/controllers/accounts/account_users_authorization_test.rb test/controllers/accounts/system_prompts_controller_test.rb
git add app/controllers/concerns/account_scoped.rb app/controllers/accounts_controller.rb app/controllers/accounts/account_users_controller.rb app/controllers/accounts/system_prompts_controller.rb app/controllers/system_prompts_controller.rb test/controllers/accounts/administration_test.rb test/controllers/accounts/account_users_authorization_test.rb
git commit -m "fix(accounts): enforce owner-only administration across routes"
```

Expected: new and existing targeted permission tests pass. Rendered owner/member controls are completed in Task 9.

## Task 3: Add explicit account tool routes and source-context path helpers

**Files:** Modify `config/routes.rb`, `app/helpers/sources_helper.rb`, `app/controllers/sources_controller.rb`, `app/views/sources/index.html.erb`, `_source_filters.html.erb`, `_toolbar.html.erb`, `_rows.html.erb`, `_add_menu.html.erb`, `_empty.html.erb`, `index.turbo_stream.erb`; create `app/controllers/concerns/source_scoped.rb` and `test/controllers/accounts/scoped_sources_test.rb`.

- [ ] **Step 1: Write scoped list/filter/stream tests.**

```ruby
require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::ScopedSourcesTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures
  setup { sign_in_overview }

  test "second-account list renders only its sources and keeps account context in every list control" do
    get "/accounts/#{@second.id}/sources"
    assert_response :success
    assert_select "[data-source-id='#{experience(:texts, :overview_second_text).id}']"
    assert_select "[data-source-id='#{experience(:texts, :overview_first_text).id}']", count: 0
    assert_select "form[action='#{account_sources_path(@second)}']", minimum: 1
    assert_select "a[href='#{account_sources_path(@second, type: 'document')}']"
    assert_select "[data-dropzone-url-value='#{account_sources_documents_path(@second)}']"
    assert_select "[data-dropzone-account-id-value='#{@second.id}']"
    assert_select "a[href='#{new_account_sources_document_path(@second)}']"
    get account_sources_path(@second, type: "text", q: "Research", sort: "title")
    assert_response :success
    assert_select "[data-source-id]", count: 1
  end

  test "all four type filters stay within the second account" do
    %w[document text qna website].each do |type|
      get "/accounts/#{@second.id}/sources", params: { type: type }
      assert_response :success
      assert_select "[data-source-id]", count: 1
    end
    get "/accounts/#{@foreign.id}/sources"
    assert_response :not_found
  end

  test "legacy list retains its first-account default" do
    get sources_path
    assert_response :success
    assert_select "[data-source-id='#{experience(:texts, :overview_first_text).id}']"
    assert_select "[data-source-id='#{experience(:texts, :overview_second_text).id}']", count: 0
  end

  test "scoped load-more responses use account paths" do
    get "/accounts/#{@second.id}/sources", params: { format: :turbo_stream, type: "text", page: 2 }
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "sources_load_more"
  end
end
```

- [ ] **Step 2: Run RED.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/scoped_sources_test.rb
```

Expected: the literal new source URL is unavailable and nested helpers are missing, not a Ruby syntax error.

- [ ] **Step 3: Add routes inside the existing authenticated `resources :accounts` block.** Add `:show` to its `only:` list. Keep its existing users/settings/system-prompt declarations and add the block below. Do not add `module: :accounts` around the reused global/source controllers.

```ruby
resources :chats, only: :index, module: :accounts
resources :sources, only: :index
resource :token_usage, only: :show, controller: "token_usages"
resources :api_tokens, only: [ :index, :create, :destroy ]
namespace :sources do
  resources :documents, except: :index do
    resource :retry, only: :create, module: :documents
  end
  resources :texts, except: :index do
    resource :retry, only: :create, module: :texts
  end
  resources :qnas, except: :index do
    resource :retry, only: :create, module: :qnas
  end
  resources :websites, except: :index do
    resource :retry, only: :create, module: :websites
  end
end
```

Expected helper families: `account_sources_path`, `account_sources_document_path`, `new_account_sources_document_path`, `account_sources_document_retry_path`, `account_chats_path`, `account_api_tokens_path`, `account_token_usage_path`. Legacy retry actions/routes remain supported; new retry resources use only `create`.

- [ ] **Step 4: Add source context and path methods.**

```ruby
# app/controllers/concerns/source_scoped.rb
module SourceScoped
  extend ActiveSupport::Concern
  include AccountScoped
  include SourcesHelper

  included do
    before_action :set_source_account
    helper_method :source_account
  end

  private
    def set_source_account
      if request.path_parameters.key?(:account_id)
        @source_account = member_account(request.path_parameters.fetch(:account_id))
        @scoped_source_account = @account = @source_account
      else
        @source_account = Current.account
      end
    end

    def source_account
      @source_account
    end

    def verify_scoped_source_account
      if @scoped_source_account && params[controller_name.singularize].is_a?(ActionController::Parameters)
        submitted = params[controller_name.singularize][:account_id]
        unless submitted.nil?
          valid_scalar = submitted.is_a?(String) || submitted.is_a?(Numeric)
          raise ActiveRecord::RecordNotFound unless valid_scalar && submitted.to_s == source_account.id.to_s
        end
      end
    end

    def source_filing_account(root)
      if @scoped_source_account
        source_account
      else
        id = params.dig(root, :account_id)
        raise ActiveRecord::RecordNotFound unless id.nil? || id.is_a?(String) || id.is_a?(Numeric)
        filing_account(root)
      end
    end
end
```

Retain `SOURCE_ICONS`/`source_status_display` in `SourcesHelper` and replace/add these URL methods. **Record** URLs are always canonical and derive account from the record, so background broadcasts do not need `Current`, controller helper methods, or a request.

```ruby
def source_show_path(record, **options)
  public_send("account_sources_#{record.model_name.element}_path", record.account_id, record, **options)
end

def source_edit_path(record)
  public_send("edit_account_sources_#{record.model_name.element}_path", record.account_id, record)
end

def source_retry_path(record)
  public_send("account_sources_#{record.model_name.element}_retry_path", record.account_id, record)
end

def source_index_path(**options)
  if @scoped_source_account
    account_sources_path(@scoped_source_account, **options)
  else
    sources_path(**options)
  end
end

def source_new_path(type)
  parts = @scoped_source_account ? [ @scoped_source_account, :sources, type.to_sym ] : [ :sources, type.to_sym ]
  new_polymorphic_path(parts)
end

def source_form_model(record)
  @scoped_source_account ? [ @scoped_source_account, :sources, record ] : [ :sources, record ]
end

def source_collection_path(type)
  parts = @scoped_source_account ? [ @scoped_source_account, :sources, type.to_s.pluralize.to_sym ] : [ :sources, type.to_s.pluralize.to_sym ]
  polymorphic_path(parts)
end
```

- [ ] **Step 5: Wire the existing list without duplicating it.** Include `SourceScoped` in `SourcesController` and replace all four `Current.account` references there with `source_account`. In the following exact view paths, replace calls to `sources_path` with `source_index_path`: `_source_filters.html.erb`, `_toolbar.html.erb`, `_rows.html.erb`, `index.turbo_stream.erb`. Keep all existing arguments, filters, sort state, page, and format.

In `app/views/sources/index.html.erb`, use `source_account` instead of `Current.account` in both stream subscriptions and replace the dropzone attributes with:

```erb
data-dropzone-url-value="<%= source_collection_path(:document) %>"
data-dropzone-account-id-value="<%= source_account.id %>"
```

Replace each add-menu target with these expressions, keeping the current translated labels/classes:

```erb
<%= link_to t("nosia.sources.upload_documents"), source_new_path(:document), class: "n-dropdown-item n-main-hover" %>
<%= link_to t("nosia.sources.add_website"), source_new_path(:website), class: "n-dropdown-item n-main-hover" %>
<%= link_to t("nosia.sources.paste_text"), source_new_path(:text), class: "n-dropdown-item n-main-hover" %>
<%= link_to t("nosia.sources.add_qna"), source_new_path(:qna), class: "n-dropdown-item n-main-hover" %>
```

In `_empty.html.erb`, replace `new_polymorphic_path([:sources, type.to_sym])` with `source_new_path(type)`. Do not redesign the existing source list or change source icons as unrelated cleanup.

- [ ] **Step 6: Run GREEN and commit.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/scoped_sources_test.rb test/controllers/sources_controller_test.rb
git add config/routes.rb app/controllers/concerns/source_scoped.rb app/controllers/sources_controller.rb app/helpers/sources_helper.rb app/views/sources/index.html.erb app/views/sources/index.turbo_stream.erb app/views/sources/_source_filters.html.erb app/views/sources/_toolbar.html.erb app/views/sources/_rows.html.erb app/views/sources/_add_menu.html.erb app/views/sources/_empty.html.erb test/controllers/accounts/scoped_sources_test.rb
git commit -m "feat(accounts): scope source navigation to explicit accounts"
```

Expected: scoped list tests and existing list tests pass; the source CRUD/retry endpoints are wired in Task 4 before this branch is shipped.

## Task 4: Carry account context through all four source write/retry workflows

**Files:** Modify all four existing `app/controllers/sources/{documents,texts,qnas,websites}_controller.rb`; create `app/controllers/sources/retries_controller.rb`, the four nested retry controllers in the file map, and `test/controllers/accounts/scoped_source_operations_test.rb`; extend `app/helpers/sources_helper.rb`.

- [ ] **Step 1: Write the source-operation matrix.** This suite exercises real controllers/models and enqueues test jobs without executing ingestion.

```ruby
require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::ScopedSourceOperationsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures
  TYPES = { document: Document, text: Text, qna: Qna, website: Website }.freeze
  setup { sign_in_overview }

  TYPES.each do |type, model|
    test "#{type} creation uses the route account and rejects conflicting or malformed filing accounts" do
      path = public_send("account_sources_#{type.to_s.pluralize}_path", @second)
      [ @first.id, @foreign.id, [], {}, [ @first.id ], { id: @first.id }, true, false, "" ].each do |bad|
        assert_no_difference -> { model.count } do
          rejected = type == :document ? { title: "Rejected" } : attributes_for_source(type)
          post path, params: { type => rejected.merge(account_id: bad) }, as: :json
          assert_response :not_found
        end
        assert_no_enqueued_jobs only: [ AddDocumentJob, AddTextJob, AddQnaJob, CrawlWebsiteUrlJob ]
      end
      assert_difference -> { model.where(account: @second).count }, 1 do
        post path, params: { type => attributes_for_source(type) }
        assert_response :redirect
      end
      assert_match %r{/accounts/#{@second.id}/sources/}, response.location
    end

    test "#{type} cannot be read, updated, deleted, or retried through a different account" do
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      path = public_send("account_sources_#{type}_path", @first, source)
      get path
      assert_response :not_found
      original = source.attributes
      patch path, params: { type => attributes_for_source(type) }
      assert_response :not_found
      assert_equal original, source.reload.attributes
      assert_no_difference -> { model.count } do
        delete path
        assert_response :not_found
      end
      post public_send("account_sources_#{type}_retry_path", @first, source)
      assert_response :not_found
    end

    test "#{type} update cannot reassign account and scoped retry enqueues only that source" do
      source = experience(type.to_s.pluralize, "overview_second_#{type}")
      path = public_send("account_sources_#{type}_path", @second, source)
      patch path, params: { type => attributes_for_source(type).merge(account_id: @first.id) }
      assert_response :not_found
      assert_equal @second.id, source.reload.account_id
      clear_enqueued_jobs
      post public_send("account_sources_#{type}_retry_path", @second, source)
      assert_redirected_to account_sources_path(@second, type: type.to_s)
      assert_equal "pending", source.reload.index_status
      job = { document: AddDocumentJob, text: AddTextJob, qna: AddQnaJob, website: CrawlWebsiteUrlJob }.fetch(type)
      assert_enqueued_with(job: job, args: [ source.id ])
    end
  end

  test "a revoked member cannot write sources" do
    @second.account_users.find_by!(user: @user).destroy!
    assert_no_difference "Text.count" do
      post account_sources_texts_path(@second), params: { text: { data: "No longer allowed" } }
      assert_response :not_found
    end
  end

  private
    def attributes_for_source(type)
      case type
      when :document
        { title: "Uploaded evidence", file: Rack::Test::UploadedFile.new(file_fixture("account_source.txt"), "text/plain") }
      when :text
        { data: "New account evidence" }
      when :qna
        { question: "New question?", answer: "New answer" }
      when :website
        { url: "https://new-research.example/reference", data: "New research page" }
      end
    end
end
```

Rejected document JSON requests deliberately contain no UploadedFile. The account guard must reject before any file validation/blob write. Successful document creation remains multipart.

- [ ] **Step 2: Run RED.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/scoped_source_operations_test.rb
```

Expected: existing source lookups fall back to the first account, writes file incorrectly, or nested retry controllers are missing. Do not perform jobs.

- [ ] **Step 3: Update existing source controllers with exact substitutions.** Include `SourceScoped` before their existing record callbacks; keep `ChatAccountScoped` in DocumentsController because its existing missing-account response/validation is still used. Apply the following replacements to the indicated controller, leaving strong parameters, upload idempotency, transaction behavior, validations, response formats, and job choice intact.

In **each of the four CRUD controllers only**, register this callback after including the concern and before the existing record callback:

```ruby
before_action :verify_scoped_source_account, only: [ :create, :update ]
```

Do not register that callback in the shared concern: the list controller has neither action and retry controllers have no update action; Rails test configuration raises for missing callback actions.

| Controller | Before | After |
| --- | --- | --- |
| `documents_controller.rb` | `Current.account.documents` | `source_account.documents` |
| `documents_controller.rb` | `filing_account(:document)` | `source_filing_account(:document)` |
| `documents_controller.rb` | `sources_document_url(@document)` | `source_response_path(@document)` |
| `documents_controller.rb` | `sources_path(type: "document")` | `source_index_path(type: "document")` |
| `documents_controller.rb` | `sources_url` | `source_index_path` |
| `texts_controller.rb` | `Current.account.texts` | `source_account.texts` |
| `texts_controller.rb` | `filing_account(:text)` | `source_filing_account(:text)` |
| `texts_controller.rb` | `sources_text_url(@text)` | `source_response_path(@text)` |
| `texts_controller.rb` | `sources_path(type: "text")` | `source_index_path(type: "text")` |
| `texts_controller.rb` | `sources_texts_url` | `source_index_path(type: "text")` |
| `qnas_controller.rb` | `Current.account.qnas` | `source_account.qnas` |
| `qnas_controller.rb` | `filing_account(:qna)` | `source_filing_account(:qna)` |
| `qnas_controller.rb` | `sources_qna_url(@qna)` | `source_response_path(@qna)` |
| `qnas_controller.rb` | `sources_path(type: "qna")` | `source_index_path(type: "qna")` |
| `qnas_controller.rb` | `sources_qnas_url` | `source_index_path(type: "qna")` |
| `websites_controller.rb` | `Current.account.websites` | `source_account.websites` |
| `websites_controller.rb` | `filing_account(:website)` | `source_filing_account(:website)` |
| `websites_controller.rb` | `sources_website_url(@website)` | `source_response_path(@website)` |
| `websites_controller.rb` | `sources_path(type: "website")` | `source_index_path(type: "website")` |
| `websites_controller.rb` | `sources_websites_url` | `source_index_path(type: "website")` |

For the Text/Website JSON create location currently written as `location: @text`/`location: @website`, use `location: source_response_path(@text)`/`location: source_response_path(@website)`. No new JSON endpoint is introduced.

Add this helper so legacy successful document-upload redirects retain their existing contract, while scoped operations stay nested:

```ruby
def source_response_path(record)
  @scoped_source_account ? source_show_path(record) : polymorphic_path([ :sources, record ])
end
```

- [ ] **Step 4: Add REST retry controllers.** The common controller calls existing model status behavior and the existing job; no new retrieval/ingestion logic or retry policy is introduced.

```ruby
# app/controllers/sources/retries_controller.rb
class Sources::RetriesController < ApplicationController
  include SourceScoped

  def create
    source = retry_source
    source.mark_pending!
    retry_job.perform_later(source.id)
    redirect_to source_index_path(type: source.source_type_key),
      notice: t("nosia.sources.#{source.model_name.collection}.retrying")
  end
end
```

```ruby
# app/controllers/sources/documents/retries_controller.rb
class Sources::Documents::RetriesController < Sources::RetriesController
  private
    def retry_source
      source_account.documents.find(params[:document_id])
    end

    def retry_job
      AddDocumentJob
    end
end
```

```ruby
# app/controllers/sources/texts/retries_controller.rb
class Sources::Texts::RetriesController < Sources::RetriesController
  private
    def retry_source
      source_account.texts.find(params[:text_id])
    end

    def retry_job
      AddTextJob
    end
end
```

```ruby
# app/controllers/sources/qnas/retries_controller.rb
class Sources::Qnas::RetriesController < Sources::RetriesController
  private
    def retry_source
      source_account.qnas.find(params[:qna_id])
    end

    def retry_job
      AddQnaJob
    end
end
```

```ruby
# app/controllers/sources/websites/retries_controller.rb
class Sources::Websites::RetriesController < Sources::RetriesController
  private
    def retry_source
      source_account.websites.find(params[:website_id])
    end

    def retry_job
      CrawlWebsiteUrlJob
    end
end
```

- [ ] **Step 5: Run GREEN with existing source/upload regressions and commit.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/scoped_source_operations_test.rb test/controllers/sources test/controllers/chat_account_sources_test.rb test/models/document_source_registration_test.rb
git add app/controllers/sources app/helpers/sources_helper.rb test/controllers/accounts/scoped_source_operations_test.rb
git commit -m "feat(accounts): preserve account context through source operations"
```

Expected: new scoped cases and existing global upload/retry tests pass, with no provider/indexing workers executed.

## Task 5: Finish source forms, links, validation, and background-row safety

**Files:** Modify the sixteen source type views listed in the file map, `app/views/sources/documents/_document.json.jbuilder`, and `_source.html.erb`; create `app/views/sources/_account_field.html.erb`, `app/views/application/_validation_errors.html.erb`, and `test/models/account_source_broadcast_test.rb`; extend `test/controllers/accounts/scoped_source_operations_test.rb`.

- [ ] **Step 1: Add form and invalid-input tests to `Accounts::ScopedSourceOperationsTest`.**

```ruby
test "all scoped forms have fixed account identity and nested form actions" do
  TYPES.each_key do |type|
    get public_send("new_account_sources_#{type}_path", @second)
    assert_response :success
    assert_select "form[action='#{public_send("account_sources_#{type.to_s.pluralize}_path", @second)}']"
    assert_select "input[type='hidden'][name='#{type}[account_id]'][value='#{@second.id}']"
    assert_select "select[name='#{type}[account_id]']", count: 0
  end
end

test "invalid document and website retain account and visible errors" do
  post account_sources_documents_path(@second), params: { document: { title: "Keep this title" } }
  assert_response :unprocessable_entity
  assert_select "[role='alert']"
  assert_select "input[name='document[title]'][value='Keep this title']"
  assert_select "form[action='#{account_sources_documents_path(@second)}']"
  post account_sources_websites_path(@second), params: { website: { url: "", data: "Keep this content" } }
  assert_response :unprocessable_entity
  assert_select "[role='alert']"
  assert_select "form[action='#{account_sources_websites_path(@second)}']"
end
```

Add a separate complete broadcast-render test. This must run without `Current.session`, including after the source-status broadcast replaces the row:

```ruby
require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/account_experience_fixtures"

class AccountSourceBroadcastTest < ActiveSupport::TestCase
  include AccountExperienceFixtures
  include Turbo::Broadcastable::TestHelper

  test "background rows retain canonical second-account show delete and retry URLs" do
    source = experience(:texts, :overview_second_text)
    Current.reset
    html = ApplicationController.render(partial: "sources/source", locals: { row: SourceRow.new(source, chunks_count: 0) })
    assert_includes html, Rails.application.routes.url_helpers.account_sources_text_path(@second, source)
    assert_includes html, Rails.application.routes.url_helpers.account_sources_text_retry_path(@second, source)
    streams = capture_turbo_stream_broadcasts([ @second, "sources", :en ]) { source.mark_indexing_failed! }
    row = streams.find { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(source, :source_row) }
    assert row
    assert_includes row.to_html, "/accounts/#{@second.id}/sources/texts/#{source.id}"
    refute_includes row.to_html, "/accounts/#{@first.id}/"
  end
end
```

- [ ] **Step 2: Run RED.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/scoped_source_operations_test.rb test/models/account_source_broadcast_test.rb
```

Expected: current forms still post globally/offer the account picker; current validation pages lack error summaries. The background test may already pass after Task 3; keep it as regression evidence rather than forcing an artificial failure.

- [ ] **Step 3: Add shared account and validation partials.**

```erb
<%# app/views/sources/_account_field.html.erb; locals: form %>
<div class="n-form-field">
  <%= form.label :account_id, t("nosia.sources.account_label"), class: "n-label" %>
  <% if @scoped_source_account %>
    <%= form.hidden_field :account_id, value: @scoped_source_account.id %>
    <p class="text-sm text-neutral-700 dark:text-neutral-200"><%= @scoped_source_account.name %></p>
  <% else %>
    <%= form.collection_select :account_id, Current.user.accounts, :id, :name,
          { prompt: true, selected: source_account&.id, required: true }, { class: "n-select" } %>
  <% end %>
</div>
```

```erb
<%# app/views/application/_validation_errors.html.erb; locals: record %>
<% if record.errors.any? %>
  <div role="alert" class="my-4 rounded-lg border border-red-700 p-3 text-red-800 dark:border-red-400 dark:text-red-200">
    <ul><% record.errors.full_messages.each do |message| %><li><%= message %></li><% end %></ul>
  </div>
<% end %>
```

For each of the four `_form.html.erb` files, replace the opening form declaration and entire existing account-selector block using the exact fragments below. Preserve every content field and Lexxy conversion/attachment setting between them.

```erb
<%# documents/_form.html.erb opening %>
<%= form_with(model: source_form_model(document)) do |form| %>
  <%= render "application/validation_errors", record: document %>
<%# documents/_form.html.erb account block %>
  <%= render "sources/account_field", form: form %>
<%# documents/_form.html.erb add beside Save %>
  <%= link_to t("nosia.actions.cancel"), document.persisted? ? source_show_path(document) : source_index_path, class: "n-btn-secondary" %>
```

```erb
<%# texts/_form.html.erb opening %>
<%= form_with(model: source_form_model(text)) do |form| %>
  <%= render "application/validation_errors", record: text %>
<%# texts/_form.html.erb account block %>
  <%= render "sources/account_field", form: form %>
<%# texts/_form.html.erb add beside Save %>
  <%= link_to t("nosia.actions.cancel"), text.persisted? ? source_show_path(text) : source_index_path, class: "n-btn-secondary" %>
```

```erb
<%# qnas/_form.html.erb opening %>
<%= form_with(model: source_form_model(qna)) do |form| %>
  <%= render "application/validation_errors", record: qna %>
<%# qnas/_form.html.erb account block %>
  <%= render "sources/account_field", form: form %>
<%# qnas/_form.html.erb add beside Save %>
  <%= link_to t("nosia.actions.cancel"), qna.persisted? ? source_show_path(qna) : source_index_path, class: "n-btn-secondary" %>
```

```erb
<%# websites/_form.html.erb opening %>
<%= form_with(model: source_form_model(website)) do |form| %>
  <%= render "application/validation_errors", record: website %>
<%# websites/_form.html.erb account block %>
  <%= render "sources/account_field", form: form %>
<%# websites/_form.html.erb add beside Save %>
  <%= link_to t("nosia.actions.cancel"), website.persisted? ? source_show_path(website) : source_index_path, class: "n-btn-secondary" %>
```

- [ ] **Step 4: Replace the remaining direct source navigation.** In the exact `new/edit/show` views for documents, texts, Q&As, and websites, use these replacements; keep the existing content, file preview, sanitization, delete confirmation, and translated accessible names:

| Before | After |
| --- | --- |
| `sources_path` or `sources_documents_path` | `source_index_path(type: "document")` in document views |
| `sources_texts_path` | `source_index_path(type: "text")` |
| `sources_qnas_path` | `source_index_path(type: "qna")` |
| `sources_websites_path` | `source_index_path(type: "website")` |
| `sources_document_path(@document)` | `source_show_path(@document)` |
| `sources_text_path(@text)` | `source_show_path(@text)` |
| `sources_qna_path(@qna)` | `source_show_path(@qna)` |
| `sources_website_path(@website)` | `source_show_path(@website)` |
| `edit_sources_document_path(@document)` | `source_edit_path(@document)` |
| `edit_sources_text_path(@text)` | `source_edit_path(@text)` |
| `edit_sources_qna_path(@qna)` | `source_edit_path(@qna)` |
| `edit_sources_website_path(@website)` | `source_edit_path(@website)` |

Apply edit-helper replacements before show-helper replacements so a text replacement cannot corrupt `edit_sources_*`. In `_document.json.jbuilder`, replace its URL line with:

```ruby
json.url source_show_path(document, format: :json)
```

In `_source.html.erb`, replace the existing show-link opening call and the complete actions container with these exact fragments. Keep the show link's existing title/body and closing `end`, and keep the existing metadata columns between the link and actions.

```erb
<%= link_to source_show_path(row.to_model), class: "block truncate font-medium n-main-focus after:absolute after:inset-0 after:content-['']" do %>
```

```erb
<div class="relative z-[1] flex gap-2 justify-end">
  <% if row.to_model.failed? %>
    <%= button_to source_retry_path(row.to_model), method: :post,
          title: t("nosia.actions.retry"), aria: { label: t("nosia.actions.retry") },
          class: "n-btn-icon n-main-hover-tertiary n-main-focus-tertiary text-orange-600 dark:text-orange-300",
          form: { data: { turbo_confirm: false } } do %>
      <span aria-hidden="true" class="text-lg leading-none">↻</span>
    <% end %>
  <% end %>
  <%= link_to source_show_path(row.to_model), title: t("nosia.actions.delete"),
        aria: { label: t("nosia.actions.delete") },
        data: { turbo_method: :delete, turbo_confirm: t("nosia.actions.confirm_delete") },
        class: "n-btn-icon n-main-hover-danger n-main-focus-danger text-red-600 dark:text-red-300" do %>
    <%= inline_svg "svg/trash-bin.svg", aria_hidden: true, class: "w-5 h-5" %>
  <% end %>
</div>
```

- [ ] **Step 5: Run GREEN, legacy source rendering, and broadcast tests; commit.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/scoped_source_operations_test.rb test/models/account_source_broadcast_test.rb test/models/sourceable_broadcast_test.rb test/controllers/sources test/integration/composer_partials_render_test.rb
git add app/views/sources app/views/application/_validation_errors.html.erb test/controllers/accounts/scoped_source_operations_test.rb test/models/account_source_broadcast_test.rb
git commit -m "feat(accounts): keep source forms and live links account-aware"
```

Expected: second-account forms/read/write/retry/broadcast cases pass, with legacy editor/upload behavior retained.

## Task 6: Scope personal API tokens and reuse account token reporting

**Files:** Modify `app/controllers/api_tokens_controller.rb`, `app/controllers/token_usages_controller.rb`, `app/views/api_tokens/index.html.erb`, `_form.html.erb`, and `app/views/token_usages/show.html.erb`; create `test/controllers/accounts/scoped_tokens_usage_test.rb`.

- [ ] **Step 1: Write private-token and account-usage tests.**

```ruby
require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::ScopedTokensUsageTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures
  setup { sign_in_overview }

  test "token list is both personal and account-specific" do
    get "/accounts/#{@second.id}/api_tokens"
    assert_response :success
    assert_select "h2", text: /second token/
    refute_includes response.body, "member token"
    refute_includes response.body, "first token"
    assert_select "form[action='#{account_api_tokens_path(@second)}']"
    assert_select "select[name='api_token[account_id]']", count: 0
  end

  test "token creation fixes the account, preserves invalid values, and reveals the secret once" do
    assert_no_difference "ApiToken.count" do
      post account_api_tokens_path(@second), params: { api_token: { name: "Rejected", account_id: @first.id } }
      assert_response :not_found
    end
    post account_api_tokens_path(@second), params: { api_token: { name: "" } }
    assert_response :unprocessable_entity
    post account_api_tokens_path(@second), params: { api_token: { name: "Research deployment" } }
    assert_redirected_to account_api_tokens_path(@second)
    follow_redirect!
    plain = response.body[%r{value="([A-Za-z0-9]{24})"}, 1]
    assert plain
    token = @user.api_tokens.find_by!(name: "Research deployment", account: @second)
    assert_equal ApiToken.digest(plain), token.token_digest
    get account_api_tokens_path(@second)
    refute_includes response.body, plain
    refute_includes response.body, token.token_digest
  end

  test "owners cannot revoke other members' tokens or tokens from another account" do
    [ experience(:api_tokens, :overview_member_token), experience(:api_tokens, :overview_first_token) ].each do |token|
      assert_no_difference "ApiToken.count" do
        delete account_api_token_path(@second, token)
        assert_response :not_found
      end
    end
    token = experience(:api_tokens, :overview_second_token)
    assert_difference "ApiToken.count", -1 do
      delete account_api_token_path(@second, token)
      assert_redirected_to account_api_tokens_path(@second)
    end
  end

  test "second-account usage is account-wide even with an unrelated ambient tenant" do
    ActsAsTenant.with_tenant(@first) do
      get "/accounts/#{@second.id}/token_usage"
      assert_response :success
      assert_includes response.body, "900"
      assert_includes response.body, "100"
      assert_equal @first, ActsAsTenant.current_tenant
    end
    sign_in_overview(@member)
    get account_token_usage_path(@second)
    assert_response :success
    get account_token_usage_path(@foreign)
    assert_response :not_found
  end
end
```

- [ ] **Step 2: Run RED.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/scoped_tokens_usage_test.rb
```

Expected: token list leaks other owned-account tokens or usage reports the first account; scoped creation/revocation contracts fail.

- [ ] **Step 3: Replace ApiTokensController with the shared scoped/global implementation.**

```ruby
class ApiTokensController < ApplicationController
  include AccountScoped
  before_action :set_token_account

  def index
    @api_tokens = token_scope.includes(:account)
    @api_token = Current.user.api_tokens.new(account: @account)
  end

  def create
    params.require(:api_token)
    account = token_filing_account(params.dig(:api_token, :account_id))
    attributes = api_token_params
    @api_token = Current.user.api_tokens.new(account: account, name: attributes[:name])
    if @api_token.save
      redirect_to token_index_path, flash: { created_api_token: @api_token.plain_token }
    elsif @account
      @api_tokens = token_scope.includes(:account)
      render :index, status: :unprocessable_entity
    else
      redirect_to api_tokens_path, alert: t("nosia.tokens.error")
    end
  end

  def destroy
    token_scope.find(params[:id]).destroy
    redirect_to token_index_path
  end

  private
    def set_token_account
      @account = member_account(request.path_parameters.fetch(:account_id)) if request.path_parameters.key?(:account_id)
    end

    def token_scope
      @account ? Current.user.api_tokens.where(account: @account) : Current.user.api_tokens
    end

    def token_filing_account(id)
      if @account
        unless id.nil?
          valid_scalar = id.is_a?(String) || id.is_a?(Numeric)
          raise ActiveRecord::RecordNotFound unless valid_scalar && id.to_s == @account.id.to_s
        end
        @account
      else
        member_account(id)
      end
    end

    def token_index_path
      @account ? account_api_tokens_path(@account) : api_tokens_path
    end

    def api_token_params
      params.require(:api_token).permit(:account_id, :name)
    end
end
```

The filing check deliberately reads the **raw** `params.dig(:api_token, :account_id)`, not `attributes[:account_id]`: arrays/hashes otherwise disappear from `permit` and look omitted. Task 10 covers these malformed JSON cases.

Replace TokenUsagesController with this reuse of its existing queries. The tenant block is narrow and restores the prior ActsAsTenant context; it does not change `Current.account` or another tab's account.

```ruby
class TokenUsagesController < ApplicationController
  include AccountScoped

  def show
    account = if request.path_parameters.key?(:account_id)
      @account = member_account(request.path_parameters.fetch(:account_id))
    else
      Current.account
    end
    ActsAsTenant.with_tenant(account) do
      @green_summary = account.green_it_summary
      @token_totals = { input: account.input_tokens_count, output: account.output_tokens_count }
      @tokens_by_kind = account.token_usages.group(:kind).sum("(input_tokens + output_tokens)")
      @tokens_by_day = account.token_usages.where("created_at > ?", 30.days.ago)
        .group("DATE(created_at)").sum("(input_tokens + output_tokens)")
    end
  end
end
```

- [ ] **Step 4: Adapt the existing token view/form, not a duplicate.** Use `@api_token` instead of `ApiToken.new` in `index.html.erb`. Replace the delete target with `@account ? account_api_token_path(@account, api_token) : api_token_path(api_token)`. Keep secret-display markup and `created_api_token` flash handling unchanged. Add error rendering before the token form using `render "application/validation_errors", record: @api_token`.

Use this opening form declaration and account block in `_form.html.erb`, keeping name/submit fields:

```erb
<%= form_with(model: api_token, url: @account ? account_api_tokens_path(@account) : api_tokens_path) do |form| %>
```

```erb
<div class="n-form-field">
  <%= form.label :account_id, t("nosia.tokens.default_account"), class: "n-label" %>
  <% if @account %>
    <%= form.hidden_field :account_id, value: @account.id %>
    <p><%= @account.name %></p>
  <% else %>
    <%= form.collection_select :account_id, Current.user.accounts, :id, :name,
          { prompt: true, required: true }, { class: "n-select" } %>
  <% end %>
</div>
```

The existing form builder retains submitted names on 422. Preserve `readonly` secret display and no persisted plaintext. Do not render token digests in any view.

- [ ] **Step 5: Run GREEN with existing token/usage tests and commit.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/api_tokens_controller_test.rb
git add app/controllers/api_tokens_controller.rb app/controllers/token_usages_controller.rb app/views/api_tokens/index.html.erb app/views/api_tokens/_form.html.erb test/controllers/accounts/scoped_tokens_usage_test.rb
git commit -m "feat(accounts): scope personal tokens and account usage"
```

Expected: scoped cases pass; existing global token create/show-once behavior still passes. The shared account breadcrumb is added in Task 9.

## Task 7: Build the bounded directory, balanced hub, and private history

**Files:** Replace `app/controllers/accounts_controller.rb` and `app/views/accounts/index.html.erb`; modify `app/views/layouts/application.html.erb`; create `app/controllers/accounts/chats_controller.rb`, `app/helpers/accounts_helper.rb`, the hub/history partials below, both new locale files, and `test/controllers/account_experience_test.rb`.

- [ ] **Step 1: Write index/hub/history tests.**

```ruby
require "test_helper"
require_relative "../support/account_experience_fixtures"

class AccountExperienceTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures
  setup { sign_in_overview }

  test "directory exposes accessible account and new-conversation links" do
    get accounts_path
    assert_response :success
    assert_select "[data-account-id]", count: 3
    assert_select "a[href='#{account_path(@second)}']"
    assert_select "a[href='#{new_chat_path(account_id: @second.id)}']"
    refute_includes response.body, @foreign.name
  end

  test "hub uses second-account summaries without exposing other members' private data" do
    get account_path(@second)
    assert_response :success
    assert_select "[data-conversation-id]", count: 5
    assert_select "[data-source-type]", count: 4
    assert_select "a[href='#{account_sources_path(@second, type: 'text')}']"
    assert_select "a[href='#{account_token_usage_path(@second)}']"
    assert_select "a[href='#{account_api_tokens_path(@second)}']"
    assert_select "a[href='#{edit_account_path(@second)}']"
    assert_includes response.body, "Shared research instructions"
    refute_includes response.body, "Personal research override"
    refute_includes response.body, "Member private question"
    refute_includes response.body, "Alpha private question"
    refute_includes response.body, experience(:api_tokens, :overview_second_token).token_digest
  end

  test "member hub hides management but retains read-only prompt, own tokens, and account usage" do
    sign_in_overview(@member)
    get account_path(@second)
    assert_response :success
    assert_select "a[href='#{edit_account_path(@second)}']", count: 0
    assert_select "a[href='#{account_account_users_path(@second)}']", count: 0
    assert_select "a[href='#{account_system_prompt_path(@second)}']"
    assert_select "[data-conversation-id]", count: 1
    refute_includes response.body, @user.email
  end

  test "history is private, account-specific, stable, and paginated" do
    get account_chats_path(@second)
    assert_response :success
    assert_select "[data-conversation-id]", count: 25
    refute_includes response.body, "Member private question"
    get account_chats_path(@second, page: 2)
    assert_response :success
    assert_select "[data-conversation-id]", count: 3
    get account_path(@foreign)
    assert_response :not_found
    get account_chats_path(@foreign)
    assert_response :not_found
  end

  test "empty hub reads do not create prompts chats sources or provider jobs" do
    before = [ Prompt.count, Chat.count, Document.count, Text.count, Qna.count, Website.count ]
    get account_path(@empty)
    assert_response :success
    assert_equal before, [ Prompt.count, Chat.count, Document.count, Text.count, Qna.count, Website.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
    assert_select "a[href='#{new_chat_path(account_id: @empty.id)}']", minimum: 1
  end
end
```

- [ ] **Step 2: Run RED.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/account_experience_test.rb
```

Expected: account show/history actions or their views are absent, and old directory cards do not have the required links/summaries.

- [ ] **Step 3: Compose the model-backed pages.** Replace AccountsController, retaining the owner boundary introduced in Task 2:

```ruby
class AccountsController < ApplicationController
  include AccountScoped
  PAGE_SIZE = 24
  before_action :set_account, only: [ :show, :edit, :update ]
  before_action :require_account_owner, only: [ :edit, :update ]

  def index
    @page = positive_page
    rows = Current.user.accounts.order(:name, :id).offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
    @has_more = rows.length > PAGE_SIZE
    @accounts = rows.first(PAGE_SIZE)
    @counts = Account.overview_counts_for(@accounts, user: Current.user)
  end

  def show
    @source_counts = SourceRow.counts_for(@account)
    @conversations = @account.conversations_for(Current.user).limit(5).to_a
    @titles = Chat.first_questions_for(@conversations)
    @users_count = @account.account_users.count
    @api_tokens_count = Current.user.api_tokens.where(account: @account).count
    @shared_prompt = @account.system_prompt
    @token_totals = { input: @account.input_tokens_count, output: @account.output_tokens_count }
  end

  def new
    @account = Current.user.accounts.new
  end

  def edit
  end

  def create
    @account = Current.user.accounts.create_with_system_prompt!(account_params.merge(owner: Current.user))
    redirect_to account_path(@account)
  rescue ActiveRecord::RecordInvalid => error
    raise unless error.record.is_a?(Account)
    @account = error.record
    render :new, status: :unprocessable_entity
  end

  def update
    if @account.update(account_params)
      redirect_to account_path(@account), notice: t("nosia.accounts.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def positive_page
      value = params[:page]
      value.is_a?(String) || value.is_a?(Numeric) ? [ value.to_i, 1 ].max : 1
    end

    def set_account
      @account = member_account(request.path_parameters.fetch(:id))
    end

    def account_params
      params.require(:account).permit(:name, :uid)
    end
end
```

```ruby
# app/controllers/accounts/chats_controller.rb
class Accounts::ChatsController < ApplicationController
  include AccountScoped
  PAGE_SIZE = 25

  def index
    @account = member_account(request.path_parameters.fetch(:account_id))
    value = params[:page]
    @page = value.is_a?(String) || value.is_a?(Numeric) ? [ value.to_i, 1 ].max : 1
    rows = @account.conversations_for(Current.user).offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
    @has_more = rows.length > PAGE_SIZE
    @conversations = rows.first(PAGE_SIZE)
    @titles = Chat.first_questions_for(@conversations)
  end
end
```

```ruby
# app/helpers/accounts_helper.rb
module AccountsHelper
  ACCOUNT_SOURCE_ICONS = { "document" => "files.svg", "text" => "file-lines.svg", "qna" => "question-circle.svg", "website" => "window.svg" }.freeze

  def account_role_label(account)
    t("nosia.account_experience.roles.#{account_owner?(account) ? 'owner' : 'member'}")
  end

  def account_conversation_title(chat, titles:)
    strip_tags(titles[chat.id].to_s).strip.presence || t("nosia.account_experience.untitled")
  end

  def account_page?
    controller_path == "accounts" || controller_path.start_with?("accounts/") || request.path_parameters.key?(:account_id)
  end
end
```

- [ ] **Step 4: Add English and French copy.** Create `config/locales/en.nosia_account_experience.yml`:

```yaml
en:
  nosia:
    account_experience:
      view_account: View account
      new_conversation: New conversation
      edit_account: Edit account
      sources: Knowledge sources
      view_sources: View all sources
      add_source: Add source
      recent: Your recent conversations
      history: Your conversations
      view_history: View history
      privacy: Only your conversations are shown.
      usage: Account usage
      usage_details: Usage details
      lifetime: Lifetime · all account members
      input: Input tokens
      output: Output tokens
      tokens: tokens
      prompt: System prompt
      default_prompt: Account default · Personal overrides may apply
      view_prompt: View system prompt
      users: Account users
      manage_users: Manage users
      api_tokens: Your API tokens
      manage_tokens: Manage your tokens
      no_sources: Add sources to give this account more knowledge. You can already start a conversation.
      no_conversations: Your private conversation history will appear here.
      no_tokens: You have no API tokens for this account.
      no_accounts: No accounts yet
      accounts_help: Accounts keep knowledge, conversations, and usage separate. Create one to get started.
      untitled: Untitled conversation
      pagination: Pagination
      previous: Previous
      next: Next
      breadcrumb: Breadcrumb
      failed:
        one: "%{count} failed source · Review"
        other: "%{count} failed sources · Review"
      processing:
        one: "%{count} processing source · View"
        other: "%{count} processing sources · View"
      sources_count:
        one: "%{count} source"
        other: "%{count} sources"
      conversations_count:
        one: "%{count} of your conversations"
        other: "%{count} of your conversations"
      roles:
        owner: Owner
        member: Member
```

Create `config/locales/fr.nosia_account_experience.yml`:

```yaml
fr:
  nosia:
    account_experience:
      view_account: Voir le compte
      new_conversation: Nouvelle conversation
      edit_account: Modifier le compte
      sources: Sources de connaissances
      view_sources: Voir toutes les sources
      add_source: Ajouter une source
      recent: Vos conversations récentes
      history: Vos conversations
      view_history: Voir l’historique
      privacy: Seules vos conversations sont affichées.
      usage: Utilisation du compte
      usage_details: Détails de l’utilisation
      lifetime: Depuis la création · tous les membres du compte
      input: Jetons d’entrée
      output: Jetons de sortie
      tokens: jetons
      prompt: Prompt système
      default_prompt: Instructions par défaut du compte · Des instructions personnelles peuvent s’appliquer
      view_prompt: Voir le prompt système
      users: Utilisateurs du compte
      manage_users: Gérer les utilisateurs
      api_tokens: Vos jetons API
      manage_tokens: Gérer vos jetons
      no_sources: Ajoutez des sources pour enrichir les connaissances de ce compte. Vous pouvez déjà démarrer une conversation.
      no_conversations: Votre historique privé de conversations apparaîtra ici.
      no_tokens: Vous n’avez aucun jeton API pour ce compte.
      no_accounts: Aucun compte pour le moment
      accounts_help: Les comptes séparent les connaissances, les conversations et l’utilisation. Créez-en un pour commencer.
      untitled: Conversation sans titre
      pagination: Pagination
      previous: Précédent
      next: Suivant
      breadcrumb: Fil d’Ariane
      failed:
        one: "%{count} source en échec · Consulter"
        other: "%{count} sources en échec · Consulter"
      processing:
        one: "%{count} source en traitement · Consulter"
        other: "%{count} sources en traitement · Consulter"
      sources_count:
        one: "%{count} source"
        other: "%{count} sources"
      conversations_count:
        one: "%{count} conversation personnelle"
        other: "%{count} conversations personnelles"
      roles:
        owner: Propriétaire
        member: Membre
```

- [ ] **Step 5: Compose small account views.** These files contain the complete account content; styling follows in Task 8. Do not use stretched whole-card links or nested anchors.

```erb
<%# app/views/accounts/index.html.erb %>
<% content_for :title, t("nosia.nav.accounts") %>
<section class="n-accounts">
  <header class="n-account-header">
    <h1 class="n-main-title"><%= t("nosia.nav.accounts") %></h1>
    <%= link_to t("nosia.accounts.add"), new_account_path, class: "n-account-primary" %>
  </header>
  <% if @accounts.empty? %>
    <div class="n-account-panel">
      <h2><%= t("nosia.account_experience.no_accounts") %></h2>
      <p class="n-account-help"><%= t("nosia.account_experience.accounts_help") %></p>
    </div>
  <% else %>
    <ul class="n-account-cards !list-none">
      <% @accounts.each do |account| %>
        <%= render "account", account: account, counts: @counts.fetch(account.id) %>
      <% end %>
    </ul>
  <% end %>
  <%= render "pagination", page: @page, has_more: @has_more, base_path: accounts_path %>
</section>
```

```erb
<%# app/views/accounts/_account.html.erb; locals: account, counts %>
<li class="n-account-panel" data-account-id="<%= account.id %>">
  <div class="n-account-header">
    <h2 class="n-account-name"><%= account.name %></h2>
    <span class="n-account-role"><%= account_role_label(account) %></span>
  </div>
  <% if account.uid.present? %><p class="n-account-help"><%= account.uid %></p><% end %>
  <p class="n-account-help"><%= t("nosia.account_experience.sources_count", count: counts[:sources]) %> · <%= t("nosia.account_experience.conversations_count", count: counts[:conversations]) %></p>
  <div class="n-account-actions">
    <%= link_to t("nosia.account_experience.view_account"), account_path(account), class: "n-account-link" %>
    <%= link_to t("nosia.account_experience.new_conversation"), new_chat_path(account_id: account.id), class: "n-account-secondary" %>
  </div>
</li>
```

```erb
<%# app/views/accounts/show.html.erb %>
<% content_for :title, @account.name %>
<section class="n-accounts" data-account-overview="<%= @account.id %>">
  <header class="n-account-header">
    <div><h1 class="n-main-title n-account-name"><%= @account.name %></h1><p class="n-account-help"><%= @account.uid %> · <%= account_role_label(@account) %></p></div>
    <div class="n-account-actions">
      <% if account_owner? %><%= link_to t("nosia.account_experience.edit_account"), edit_account_path(@account), class: "n-account-secondary" %><% end %>
      <%= link_to t("nosia.account_experience.new_conversation"), new_chat_path(account_id: @account.id), class: "n-account-primary" %>
    </div>
  </header>
  <div class="n-account-columns">
    <div class="n-account-stack"><%= render "sources" %><%= render "conversations", conversations: @conversations, titles: @titles, recent: true %></div>
    <div class="n-account-stack"><%= render "usage" %><%= render "configuration" %></div>
  </div>
</section>
```

```erb
<%# app/views/accounts/_sources.html.erb %>
<section class="n-account-panel">
  <div class="n-account-header"><h2><%= t("nosia.account_experience.sources") %></h2><%= link_to t("nosia.account_experience.view_sources"), account_sources_path(@account), class: "n-account-link" %></div>
  <div class="n-account-source-grid">
    <% SourceRow::TYPES.each do |type| %>
      <%= link_to account_sources_path(@account, type: type), class: "n-account-source", data: { source_type: type } do %>
        <%= inline_svg "svg/#{AccountsHelper::ACCOUNT_SOURCE_ICONS.fetch(type)}", aria_hidden: true, class: "h-5 w-5" %>
        <strong><%= number_with_delimiter(@source_counts[:by_type].fetch(type)) %></strong>
        <span><%= t("nosia.sources.types.#{type}", count: 2) %></span>
      <% end %>
    <% end %>
  </div>
  <% if @source_counts[:total].zero? %><p class="n-account-help"><%= t("nosia.account_experience.no_sources") %></p><%= link_to t("nosia.account_experience.add_source"), account_sources_path(@account), class: "n-account-link" %><% end %>
  <% %w[failed pending].each do |status| %>
    <% count = @source_counts[:by_status].fetch(status) %>
    <% if count.positive? %><p><%= link_to t("nosia.account_experience.#{status == 'failed' ? 'failed' : 'processing'}", count: count), account_sources_path(@account, status: status), class: "n-account-link" %></p><% end %>
  <% end %>
</section>
```

```erb
<%# app/views/accounts/_conversations.html.erb; locals: conversations, titles, recent %>
<section class="n-account-panel">
  <div class="n-account-header">
    <h2><%= t("nosia.account_experience.#{recent ? 'recent' : 'history'}") %></h2>
    <% if recent %><%= link_to t("nosia.account_experience.view_history"), account_chats_path(@account), class: "n-account-link" %><% end %>
  </div>
  <p class="n-account-help"><%= t("nosia.account_experience.privacy") %></p>
  <% if conversations.empty? %>
    <p class="n-account-help"><%= t("nosia.account_experience.no_conversations") %></p>
    <%= link_to t("nosia.account_experience.new_conversation"), new_chat_path(account_id: @account.id), class: "n-account-secondary" %>
  <% else %>
    <ul class="!list-none">
      <% conversations.each do |chat| %>
        <li class="n-account-conversation" data-conversation-id="<%= chat.id %>">
          <%= link_to account_conversation_title(chat, titles: titles), chat_path(chat), class: "n-account-link n-account-name" %>
          <time datetime="<%= chat.updated_at.iso8601 %>" class="n-account-help"><%= l(chat.updated_at, format: :short) %></time>
        </li>
      <% end %>
    </ul>
  <% end %>
</section>
```

```erb
<%# app/views/accounts/_usage.html.erb %>
<section class="n-account-panel">
  <div class="n-account-header"><h2><%= t("nosia.account_experience.usage") %></h2><%= link_to t("nosia.account_experience.usage_details"), account_token_usage_path(@account), class: "n-account-link" %></div>
  <p class="text-2xl font-semibold"><%= number_with_delimiter(@token_totals.values.sum) %> <%= t("nosia.account_experience.tokens") %></p>
  <p class="n-account-help"><%= t("nosia.account_experience.lifetime") %></p>
  <dl><% %i[input output].each do |kind| %><div class="n-account-conversation"><dt><%= t("nosia.account_experience.#{kind}") %></dt><dd><%= number_with_delimiter(@token_totals.fetch(kind)) %></dd></div><% end %></dl>
</section>
```

```erb
<%# app/views/accounts/_configuration.html.erb %>
<section class="n-account-panel">
  <h2><%= t("nosia.account_experience.prompt") %></h2>
  <p class="n-account-help"><%= t("nosia.account_experience.default_prompt") %></p>
  <p class="n-account-prompt"><%= truncate(@shared_prompt.to_s, length: 240) %></p>
  <%= link_to t("nosia.account_experience.view_prompt"), account_system_prompt_path(@account), class: "n-account-link" %>
</section>
<section class="n-account-panel">
  <div class="n-account-conversation"><h2><%= t("nosia.account_experience.users") %></h2><span><%= @users_count %></span></div>
  <% if account_owner? %><%= link_to t("nosia.account_experience.manage_users"), account_account_users_path(@account), class: "n-account-link" %><% end %>
  <div class="n-account-conversation"><h2><%= t("nosia.account_experience.api_tokens") %></h2><span><%= @api_tokens_count %></span></div>
  <% if @api_tokens_count.zero? %><p class="n-account-help"><%= t("nosia.account_experience.no_tokens") %></p><% end %>
  <%= link_to t("nosia.account_experience.manage_tokens"), account_api_tokens_path(@account), class: "n-account-link" %>
</section>
```

```erb
<%# app/views/accounts/_pagination.html.erb; locals: page, has_more, base_path %>
<nav class="n-account-actions" aria-label="<%= t('nosia.account_experience.pagination') %>">
  <% if page > 1 %><%= link_to t("nosia.account_experience.previous"), "#{base_path}?#{ { page: page - 1 }.to_query }", class: "n-account-secondary", rel: "prev" %><% end %>
  <% if has_more %><%= link_to t("nosia.account_experience.next"), "#{base_path}?#{ { page: page + 1 }.to_query }", class: "n-account-secondary", rel: "next" %><% end %>
</nav>
```

```erb
<%# app/views/accounts/chats/index.html.erb %>
<% content_for :title, t("nosia.account_experience.history") %>
<% content_for :account_tool_title, t("nosia.account_experience.history") %>
<section class="n-accounts">
  <header class="n-account-header"><h1 class="n-main-title"><%= @account.name %></h1><%= link_to t("nosia.account_experience.new_conversation"), new_chat_path(account_id: @account.id), class: "n-account-primary" %></header>
  <%= render "accounts/conversations", conversations: @conversations, titles: @titles, recent: false %>
  <%= render "accounts/pagination", page: @page, has_more: @has_more, base_path: account_chats_path(@account) %>
</section>
```

- [ ] **Step 6: Suppress duplicate cross-account history and update intentional redirect expectations.** In `app/views/layouts/application.html.erb`, replace the right-drawer guard `if Current.user` with `if Current.user && !account_page?`; this wraps both desktop/mobile copies. Keep the outer global menu/header intact. This belongs here because otherwise hub privacy assertions can see the first account's chats in global chrome.

In `test/controllers/accounts_controller_test.rb`, move the account lookup before its redirect assertion and use `assert_redirected_to account_path(account)`. In `test/integration/localized_pages_test.rb`, replace the account-update test's `assert_redirected_to accounts_url` with `assert_redirected_to account_url(@second)`; retain its localized notice assertion.
- [ ] **Step 7: Run GREEN and commit.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/account_experience_test.rb test/controllers/accounts_controller_test.rb test/controllers/accounts/administration_test.rb test/models/account_overview_test.rb
git add app/controllers/accounts_controller.rb app/controllers/accounts/chats_controller.rb app/helpers/accounts_helper.rb app/views/accounts/index.html.erb app/views/accounts/show.html.erb app/views/accounts/_account.html.erb app/views/accounts/_sources.html.erb app/views/accounts/_conversations.html.erb app/views/accounts/_usage.html.erb app/views/accounts/_configuration.html.erb app/views/accounts/_pagination.html.erb app/views/accounts/chats/index.html.erb app/views/layouts/application.html.erb config/locales/en.nosia_account_experience.yml config/locales/fr.nosia_account_experience.yml test/controllers/account_experience_test.rb test/controllers/accounts_controller_test.rb test/integration/localized_pages_test.rb
git commit -m "feat(accounts): add balanced overview and private conversation history"
```

Expected: hub/history and changed create/update navigation tests pass. Existing localized tests are rerun after the breadcrumb/control adaptations in Task 9.

## Task 8: Apply the balanced responsive styling and allow browser zoom

**Files:** Create `app/assets/stylesheets/nosia/accounts.css` and `test/system/account_experience_test.rb`; modify `app/assets/tailwind/application.css` and `app/views/layouts/application.html.erb`.

- [ ] **Step 1: Write the first browser layout regression.**

```ruby
require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class AccountExperienceSystemTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
  end

  test "balanced account layout stacks without overflow and permits browser zoom" do
    visit account_path(@second)
    assert_selector "[data-account-overview='#{@second.id}']"
    viewport = find("meta[name='viewport']", visible: :all)["content"]
    refute_match(/maximum-scale|user-scalable\s*=\s*no/, viewport)
    assert_equal "grid", page.evaluate_script("getComputedStyle(document.querySelector('.n-account-columns')).display")
    [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
      page.current_window.resize_to(width, height)
      assert_selector "a[href='#{new_chat_path(account_id: @second.id)}']", text: "New conversation"
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
    end
  end
end
```

- [ ] **Step 2: Run RED in the available local browser.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/account_experience_test.rb
```

Expected: browser runs and the current viewport restriction or unstyled block layout fails the assertion. Use the paths discovered in Task 0 if they differ; do not alter global browser configuration to accommodate one machine.

- [ ] **Step 3: Add the account-only stylesheet.**

```css
/* app/assets/stylesheets/nosia/accounts.css */
.n-accounts {
  @apply mx-auto w-full min-w-0 max-w-7xl space-y-6 pb-24 lg:pb-8;
}
.n-account-header {
  @apply flex min-w-0 flex-wrap items-start justify-between gap-4;
}
.n-account-actions {
  @apply flex min-w-0 flex-wrap items-center gap-3;
}
.n-account-cards {
  @apply grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3;
}
.n-account-columns {
  @apply grid min-w-0 grid-cols-1 items-start gap-6 xl:grid-cols-[minmax(0,1.65fr)_minmax(18rem,1fr)];
}
.n-account-stack {
  @apply grid min-w-0 gap-6;
}
.n-account-panel {
  @apply min-w-0 space-y-4 rounded-xl border border-neutral-400 bg-white p-5 text-neutral-900 dark:border-neutral-500 dark:bg-neutral-800 dark:text-neutral-100 sm:p-6;
}
.n-account-panel h2 {
  @apply text-base font-semibold;
}
.n-account-name {
  overflow-wrap: anywhere;
  @apply min-w-0;
}
.n-account-help {
  overflow-wrap: anywhere;
  @apply break-words text-sm leading-relaxed text-neutral-600 dark:text-neutral-300;
}
.n-account-role {
  @apply rounded-md bg-neutral-100 px-2 py-1 text-xs font-medium text-neutral-700 dark:bg-neutral-700 dark:text-neutral-200;
}
.n-account-primary {
  @apply inline-flex min-h-11 max-w-full items-center justify-center rounded-lg bg-green-700 px-4 py-2 text-center text-sm font-semibold text-white hover:bg-green-800 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:focus:outline-green-400;
}
.n-account-secondary {
  @apply inline-flex min-h-11 max-w-full items-center justify-center rounded-lg border border-neutral-500 bg-white px-4 py-2 text-center text-sm font-medium text-neutral-900 hover:bg-neutral-100 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:border-neutral-400 dark:bg-neutral-800 dark:text-neutral-100 dark:hover:bg-neutral-700 dark:focus:outline-green-400;
}
.n-account-link {
  @apply inline-flex min-h-11 items-center rounded-sm text-sm font-medium text-green-800 underline decoration-transparent underline-offset-4 hover:decoration-current focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:text-green-200 dark:focus:outline-green-400;
}
.n-account-source-grid {
  @apply grid grid-cols-2 gap-3 sm:grid-cols-4;
}
.n-account-source {
  @apply flex min-w-0 flex-col items-start gap-2 rounded-lg border border-neutral-500 p-3 text-sm text-neutral-800 hover:bg-green-50 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:border-neutral-400 dark:text-neutral-100 dark:hover:bg-green-950 dark:focus:outline-green-400;
}
.n-account-source strong {
  @apply text-2xl font-semibold;
}
.n-account-conversation {
  @apply flex min-w-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-b border-neutral-200 py-3 last:border-0 dark:border-neutral-600;
}
.n-account-conversation .n-account-name {
  @apply flex-1 basis-48;
}
.n-account-prompt {
  @apply break-words border-l-2 border-green-700 pl-3 text-sm leading-relaxed dark:border-green-400;
}
main:has(.n-accounts) {
  min-width: 0;
  scroll-padding-block-end: 6rem;
}
@media (prefers-reduced-motion: reduce) {
  .n-accounts a,
  .n-accounts button {
    transition: none;
  }
}
```

Add `@import "../stylesheets/nosia/accounts.css" layer(utilities);` beside the other Nosia imports. Replace the viewport meta content with `width=device-width,initial-scale=1.0`; do not impose a maximum scale or disable user scaling.

- [ ] **Step 4: Build CSS, run GREEN, and commit.**

```bash
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key bundle exec dotenv -f ../../.env -- bin/rails tailwindcss:build
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/account_experience_test.rb
git add app/assets/stylesheets/nosia/accounts.css app/assets/tailwind/application.css app/views/layouts/application.html.erb test/system/account_experience_test.rb
git commit -m "feat(accounts): style responsive overview with accessible controls"
```

Expected: Tailwind builds without Node/npm, browser layout assertions pass, and compiled build artifacts remain ignored. Verify contrast against the **composed** actual light/dark surfaces during Task 10; a class name is not proof of contrast.

## Task 9: Complete hub-centered breadcrumbs, returns, and read-only member controls

**Files:** Create `app/views/accounts/_breadcrumb.html.erb`; modify `app/views/layouts/application.html.erb`, `app/controllers/accounts/settings_controller.rb`, account edit/form/users/prompt views, global `app/views/system_prompts/show.html.erb`, token index, usage show, source index/new/edit/show views, and `test/integration/localized_pages_test.rb`; extend `test/controllers/account_experience_test.rb` and `test/controllers/accounts/administration_test.rb`.

- [ ] **Step 1: Add navigation and member-control regressions.**

```ruby
# Add to AccountExperienceTest
test "settings and account editing return to the hub with useful breadcrumbs" do
  get account_settings_path(@second)
  assert_redirected_to account_path(@second)
  get edit_account_path(@second)
  assert_response :success
  assert_select "a[href='#{account_path(@second)}']", minimum: 1
  patch account_path(@second), params: { account: { name: "Research renamed", uid: "research-renamed" } }
  assert_redirected_to account_path(@second)
  [ account_sources_path(@second), account_chats_path(@second), account_api_tokens_path(@second),
    account_token_usage_path(@second), account_system_prompt_path(@second), account_account_users_path(@second) ].each do |path|
    get path
    assert_response :success
    assert_select "nav[aria-label='Breadcrumb'] a[href='#{account_path(@second)}']"
    assert_select "#accordion-right-actions", count: 0
    assert_select "#drawer-right", count: 0
  end
end

# Add to Accounts::AdministrationTest
test "member prompt read page has neither membership navigation nor edit controls" do
  get account_system_prompt_path(@second)
  assert_response :success
  assert_select "a[href='#{edit_account_system_prompt_path(@second)}']", count: 0
  assert_select "a[href='#{account_account_users_path(@second)}']", count: 0
  shared = experience(:prompts, :overview_second_shared)
  get system_prompt_path(shared)
  assert_response :success
  assert_select "a[href='#{edit_system_prompt_path(shared)}']", count: 0
end

test "missing shared prompt edit submits PATCH and failed saving creates no default" do
  sign_in_overview
  get edit_account_system_prompt_path(@empty)
  assert_response :success
  assert_select "form[action='#{account_system_prompt_path(@empty)}'] input[name='_method'][value='patch']"
  assert_no_difference "Prompt.count" do
    patch account_system_prompt_path(@empty), params: { prompt: { content: "" } }
    assert_response :unprocessable_entity
  end
end
```

- [ ] **Step 2: Run RED.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/account_experience_test.rb test/controllers/accounts/administration_test.rb
```

Expected: old settings renders its tile page; breadcrumb account links are `#`; member prompt pages expose edit/member links; a new prompt form sends POST instead of PATCH.

- [ ] **Step 3: Implement the settings redirect and reusable breadcrumb.**

```ruby
# app/controllers/accounts/settings_controller.rb
class Accounts::SettingsController < ApplicationController
  include AccountScoped

  def show
    account = member_account(request.path_parameters.fetch(:account_id))
    redirect_to account_path(account)
  end
end
```

```erb
<%# app/views/accounts/_breadcrumb.html.erb; locals: account, title %>
<nav aria-label="<%= t('nosia.account_experience.breadcrumb') %>" class="mb-5 text-sm text-neutral-600 dark:text-neutral-300">
  <ol class="!list-none flex flex-wrap items-center gap-2">
    <li><%= link_to t("nosia.nav.accounts"), accounts_path, class: "n-account-link" %></li>
    <li aria-hidden="true">/</li>
    <% if title.present? %>
      <li><%= link_to account.name, account_path(account), class: "n-account-link n-account-name" %></li>
      <li aria-hidden="true">/</li>
      <li aria-current="page"><%= title %></li>
    <% else %>
      <li aria-current="page" class="n-account-name"><%= account.name %></li>
    <% end %>
  </ol>
</nav>
```

In the layout, replace the single `render "navbar"` call with:

```erb
<% if account_page? && @account&.persisted? %>
  <%= render "accounts/breadcrumb", account: @account, title: content_for(:account_tool_title) %>
<% else %>
  <%= render "navbar" %>
<% end %>
```

Set `content_for :account_tool_title` at the beginning of each account tool template, using these exact expressions:

| Templates | Expression |
| --- | --- |
| `app/views/accounts/edit.html.erb` | `t("nosia.account_experience.edit_account")` |
| `app/views/accounts/account_users/index.html.erb` | `t("nosia.account_experience.users")` |
| `app/views/accounts/system_prompts/show.html.erb`, `edit.html.erb` | `t("nosia.account_experience.prompt")` |
| `app/views/api_tokens/index.html.erb` | `t("nosia.account_experience.api_tokens")` when `@account` |
| `app/views/token_usages/show.html.erb` | `t("nosia.account_experience.usage")` when `@account` |
| Source `index` and each type's `new/edit/show` | `t("nosia.account_experience.sources")` when `@scoped_source_account` |

Each is an actual ERB line, for example:

```erb
<% content_for :account_tool_title, t("nosia.account_experience.sources") if @scoped_source_account %>
```

- [ ] **Step 4: Fix returns and owner-visible controls.** In account `_form.html.erb`, use this Cancel target and display the shared validation summary before fields:

```erb
<%= render "application/validation_errors", record: account %>
<%= link_to t("nosia.actions.cancel"), account.persisted? ? account_path(account) : accounts_path, class: "n-btn border n-main-border n-main-hover-tertiary n-main-focus-tertiary" %>
```

Replace the `@account.name, "#"` breadcrumb target with `@account.name, account_path(@account)` in account edit/users/prompt views, even where the new layout breadcrumb supersedes it.

Wrap the Users tab and both Edit controls in `accounts/system_prompts/show.html.erb` in `if account_owner?`. The owner edit template remains owner-only. Add explicit `method: :patch` to its `form_with` and render the validation partial immediately inside the form:

```erb
<%= form_with(model: @system_prompt, url: account_system_prompt_path(@account), method: :patch, class: "max-w-4xl mx-auto") do |form| %>
  <%= render "application/validation_errors", record: @system_prompt %>
```

Preserve its existing content field and Save/Cancel targets. In global `system_prompts/show.html.erb`, wrap both edit-control blocks with:

```erb
<% if @system_prompt.user_id.present? || account_owner?(@system_prompt.account) %>
  <%= link_to t("nosia.actions.edit"), edit_system_prompt_path(@system_prompt), class: "n-btn-primary" %>
<% end %>
```

In the French membership denial test at the end of `test/integration/localized_pages_test.rb`'s membership lifecycle scenario, replace its old owner-only **flash** expectation with `assert_response :forbidden`. Keep successful membership notices and the owner's protected-removal alert unchanged. Its account-update redirect expectation must be `assert_redirected_to account_url(@second)`.

Two existing localized settings tests intentionally need redirect-aware assertions:

```ruby
# Inside "administration decorations stay hidden from accessible names", immediately after get:
if url == account_settings_url(@second)
  assert_redirected_to account_url(@second)
  follow_redirect!(headers: { "Accept-Language" => "fr" })
end
# Keep the existing success and decorative-SVG assertions after this branch.
```

Replace the old settings-page portion of "French account headings escape authored account names" with:

```ruby
get account_settings_url(@second), headers: headers
assert_redirected_to account_url(@second)
follow_redirect!(headers: headers)
assert_response :success
assert_select "h1", text: @second.name
assert_select "h1 script", count: 0
```

Do not change other pages' heading or localization expectations just to make this feature pass.

- [ ] **Step 5: Run GREEN and localized regressions; commit.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/account_experience_test.rb test/controllers/accounts/administration_test.rb test/integration/localized_pages_test.rb test/controllers/accounts
git add app/controllers/accounts/settings_controller.rb app/views/accounts app/views/layouts/application.html.erb app/views/api_tokens/index.html.erb app/views/token_usages/show.html.erb app/views/sources app/views/system_prompts/show.html.erb test/controllers/account_experience_test.rb test/controllers/accounts/administration_test.rb test/integration/localized_pages_test.rb
git commit -m "feat(accounts): finish hub navigation and member-safe administration views"
```

Expected: scoped tools have real account breadcrumbs and owner/member controls, while global token/usage/source routes remain usable.

## Task 10: Close isolation, pagination, performance, and browser regressions

**Files:** Extend `test/controllers/account_experience_test.rb`, `test/controllers/accounts/scoped_source_operations_test.rb`, `test/controllers/accounts/scoped_tokens_usage_test.rb`, `test/models/account_overview_test.rb`, and `test/system/account_experience_test.rb`. Fix only regressions in the feature files already mapped above.

- [ ] **Step 1: Add malicious-input and no-side-effect tests.** Add to `Accounts::ScopedTokensUsageTest`:

```ruby
test "malformed token account references cannot disappear through strong parameters" do
  [ [], {}, [ @first.id ], { id: @first.id }, true, false, "" ].each do |id|
    assert_no_difference "ApiToken.count" do
      post account_api_tokens_path(@second), params: { api_token: { name: "Forged", account_id: id } }, as: :json
      assert_response :not_found
    end
  end
end

test "revoked membership blocks tokens and usage without changing data" do
  @second.account_users.find_by!(user: @user).destroy!
  [ account_api_tokens_path(@second), account_token_usage_path(@second) ].each do |path|
    get path
    assert_response :not_found
  end
  assert_no_difference "ApiToken.count" do
    post account_api_tokens_path(@second), params: { api_token: { name: "Revoked" } }
    assert_response :not_found
  end
end
```

Add to `AccountExperienceTest`:

```ruby
test "a user with no accounts gets an actionable empty directory" do
  sign_in_overview(experience(:users, :overview_no_account))
  get accounts_path
  assert_response :success
  assert_select "[data-account-id]", count: 0
  assert_select "a[href='#{new_account_path}']"
  assert_includes response.body, "No accounts yet"
end

test "directory pagination stays bounded and does not create per-card source queries" do
  25.times do |i|
    account = Account.create!(name: "Extra #{format('%02d', i)}", owner: @user)
    account.account_users.grant_to(@user)
  end
  queries = []
  subscriber = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }
  ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { get accounts_path }
  assert_response :success
  assert_select "[data-account-id]", count: 24
  assert_equal 4, queries.grep(/SELECT.*FROM "(?:documents|texts|qnas|websites)"/i).size
  get accounts_path(page: 2)
  assert_select "[data-account-id]", count: 4
end

test "French hub and empty states translate without changing the account or prompt" do
  original = experience(:prompts, :overview_second_shared).content
  get account_path(@second), headers: { "Accept-Language" => "fr" }
  assert_response :success
  assert_select "a", text: "Nouvelle conversation"
  refute_match(/translation missing/i, response.body)
  assert_equal original, experience(:prompts, :overview_second_shared).reload.content
  get account_path(@empty), headers: { "Accept-Language" => "fr" }
  refute_match(/translation missing/i, response.body)
end

test "revoked membership also blocks the hub and history" do
  @second.account_users.find_by!(user: @user).destroy!
  get account_path(@second)
  assert_response :not_found
  get account_chats_path(@second)
  assert_response :not_found
end
```

The generated pagination rows deliberately exercise new-account behavior using the fixture owner; this is not a FactoryBot setup or a replacement for the feature fixtures.

Add to `AccountOverviewTest`:

```ruby
test "untitled and same-time conversations have stable ordering and bounded title loading" do
  first = experience(:chats, :overview_second_chat_0)
  second = experience(:chats, :overview_second_chat_1)
  timestamp = Time.utc(2030, 1, 1)
  first.update_columns(updated_at: timestamp)
  second.update_columns(updated_at: timestamp)
  rows = @second.conversations_for(@user).limit(2).to_a
  assert_equal [ first.id, second.id ].sort.reverse, rows.map(&:id)
  experience(:messages, :overview_second_question_0).update_columns(content: nil)
  assert_nil Chat.first_questions_for([ first ]).fetch(first.id)
  assert_empty Chat.first_questions_for([])
end
```

- [ ] **Step 2: Run the new tests before correcting any discovered gap.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/account_experience_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/models/account_overview_test.rb
```

Expected: already-correct cases pass. Any remaining regression must fail for its intended behavior before its implementation is changed. Specifically, filtering `account_id` before validation must fail the malformed token test; the fix is the raw-reference call explicitly specified in Task 6. Do not manufacture failures in already-covered cases.

- [ ] **Step 3: Add end-to-end entry/resume/source/token flows to the browser class.**

```ruby
test "directory to hub to composer keeps the non-first account" do
  visit accounts_path
  within("[data-account-id='#{@second.id}']") { click_on "View account" }
  assert_current_path account_path(@second)
  link = find("a[href='#{new_chat_path(account_id: @second.id)}']", match: :first)
  page.execute_script("arguments[0].focus()", link)
  assert page.evaluate_script("parseFloat(getComputedStyle(document.activeElement).outlineWidth) >= 2")
  link.send_keys(:enter)
  assert_selector "select[name='chat[account_id]'] option[selected][value='#{@second.id}']", visible: :all
end

test "source-type navigation and conversation history resume stay account-specific" do
  visit account_path(@second)
  find("[data-source-type='document']").click
  assert_current_path account_sources_path(@second, type: "document")
  assert_selector "[data-source-id='#{experience(:documents, :overview_second_document).id}']"
  visit account_chats_path(@second)
  chat = experience(:chats, :overview_second_chat_27)
  find("[data-conversation-id='#{chat.id}'] a").click
  assert_current_path chat_path(chat)
end

test "owner edits return to the hub and token generation stays in this account" do
  visit edit_account_path(@second)
  fill_in "account_name", with: "Renamed research"
  click_on "Save"
  assert_current_path account_path(@second)
  visit account_api_tokens_path(@second)
  fill_in "api_token_name", with: "Browser deployment"
  click_on "Generate"
  assert_current_path account_api_tokens_path(@second)
  assert_text "Copy it now"
  assert_equal @second.id, @user.api_tokens.find_by!(name: "Browser deployment").account_id
end

test "long French content works in both themes at a narrow viewport" do
  @second.update!(name: "Un compte de recherche avec un nom très long " * 4, uid: "identifiant-sans-espace-" * 8)
  page.current_window.resize_to(375, 812)
  visit account_path(@second)
  page.execute_script("document.documentElement.classList.remove('dark')")
  light = page.evaluate_script("getComputedStyle(document.querySelector('.n-account-panel')).backgroundColor")
  page.execute_script("document.documentElement.classList.add('dark')")
  dark = page.evaluate_script("getComputedStyle(document.querySelector('.n-account-panel')).backgroundColor")
  refute_equal light, dark
  assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
  page.save_screenshot("/tmp/opencode/account-experience-narrow-dark.png")
end
```

For an actual French browser run, choose French through the existing language preference UI or set its signed preference through the supported language endpoint, rather than pretending that French account data changes the interface locale. The request-level French coverage above verifies every translated hub/empty-state string.

- [ ] **Step 4: Run browser GREEN and inspect screenshots, not just assertions.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/account_experience_test.rb
```

Also capture/read 1440px light, 375px light/dark, member view, zero-content view, and a source validation-error screenshot. Manually verify Tab/Shift-Tab order, all actions without a pointer, visible/non-obscured focus, real browser zoom at 200%, actual French labels, and reduced-motion preference. Do not describe viewport resizing, deviceScaleFactor, or CSS zoom as a verified actual browser-zoom test. If the environment cannot perform a manual check, explicitly report it as unverified.

- [ ] **Step 5: Commit the regression coverage and any test-proven corrections.**

```bash
git add test/controllers/account_experience_test.rb test/controllers/accounts/scoped_source_operations_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/models/account_overview_test.rb test/system/account_experience_test.rb
git commit -m "test(accounts): cover privacy pagination and account navigation"
```

Stage any necessary implementation corrections by their exact paths in a separate, narrowly described commit; never sweep in unrelated files with `git add .`.

## Task 11: Document, verify, review, and hand off the completed feature

**Files:** Create `docs/account-experience.md`; modify `docs/README.md` and `docs/DIAGRAMS.md`. Review the new/changed model public methods' existing YARD tags in Task 1 and document route/helper contracts without adding noise to obvious private methods.

- [ ] **Step 1: Add the user/developer guide with this content.**

```markdown
# Account experience

Open **Accounts**, then **View account**, to see an account's knowledge sources,
your recent conversations, account-wide usage, default system prompt, users,
and your API tokens. **New conversation** preselects that account in the existing
composer; you may still switch before the first message using its normal rules.

Documents, Texts, Q&As, and Websites open the existing source interface scoped to
that account. Filters, upload forms, retries, source links, and pagination preserve
its URL context. Visiting another account does not change a global preference or
the account in another browser tab.

## Visibility and administration

- Conversation previews/counts/history show only your root chats for this account.
  Account owners cannot inspect other members' chats through the account hub.
- API-token lists, generation, and revocation cover only your tokens in this
  account. A newly generated secret is displayed once; digests are never rendered.
- Usage is lifetime account-wide input/output, with detailed usage and impact on
  the linked reporting page. Hub summaries refresh on navigation/reload.
- Members may read the shared default system prompt. Only the account owner edits
  it, edits account details, or accesses/manages the membership directory.
- Personal prompt overrides may apply during generation. This feature does not
  change their selection rules or replace them with the shared-default preview.

## Request boundaries

Account tools use `/accounts/:account_id/...`. The route account is checked against
current membership before data lookup or mutation; a conflicting submitted account
is rejected. Outsiders, mismatched records, and malformed context return 404;
members attempting owner-only operations receive 403. Invalid forms return 422.
Legacy global shared-prompt edit/update/delete routes enforce the same owner rule.

Directory: 24 accounts/page. Hub: five recent conversations. History: 25/page,
ordered by activity then ID descending. Existing non-account URLs remain supported.
Account creation/editing and the old account-settings landing page lead to the hub.

Revoked membership is checked on subsequent requests. Already-running jobs/streams
are not forcibly interrupted by this feature. Merely opening read pages does not
create prompts/chats/sources or start ingestion/generation/provider requests.

## Verification

Use the dedicated test-only database and dummy provider key described in
`superpowers/plans/2026-10-23-account-experience.md`. Run processes sequentially.
Record actual focused/full-suite counts, lint/security findings, baseline failures,
and browser checks with dates; do not mark unperformed manual checks as complete.
```

Add this development link to `docs/README.md`:

```markdown
- [Account experience](account-experience.md) — overview hub, scoped tools, private history/tokens, and owner-only administration.
```

Add this bounded entrypoint diagram to `docs/DIAGRAMS.md`:

```text
Accounts index (current memberships)
  └─ Account hub (explicit authorized account)
       ├─ New conversation → existing composer with account_id
       ├─ Sources → documents / texts / Q&As / websites
       ├─ Your history → your saved chat
       ├─ Usage → account-wide reporting
       ├─ Your API tokens → your tokens ∩ this account
       ├─ Shared prompt → member read / owner edit
       └─ Details + users → owner-only administration
```

- [ ] **Step 2: Run all feature and relevant regression tests.**

```bash
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/models/account_overview_test.rb test/models/account_source_broadcast_test.rb test/controllers/account_experience_test.rb test/controllers/accounts test/controllers/accounts_controller_test.rb test/controllers/sources_controller_test.rb test/controllers/sources test/controllers/api_tokens_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_access_test.rb test/models/sourceable_broadcast_test.rb test/integration/localized_pages_test.rb
DATABASE_URL=postgresql:///nosia_account_experience_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test > /tmp/opencode/account-experience-final-suite.log 2>&1
```

Expected: feature tests pass. Compare the full-suite output against the fresh Task 0 baseline; investigate new failures and report unchanged ones separately. Never claim the full suite passed if its process exits nonzero. Run the browser command from Task 10 separately, not concurrently on the same database. Also rerun `test/system/chat_account_selection_test.rb` and `test/system/sources_dropzone_test.rb` using that launcher with their explicit filenames.

- [ ] **Step 3: Run lint/security and review the actual diff.**

```bash
git diff --check e4ec6b1
RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app test/controllers/account_experience_test.rb test/controllers/accounts test/models/account_overview_test.rb test/models/account_source_broadcast_test.rb test/system/account_experience_test.rb test/support/account_experience_fixtures.rb
bundle exec brakeman --no-pager
git diff --stat e4ec6b1
git status --short
```

Expected: no new whitespace, Ruby style, or security findings. Record existing offenses/scanner version gates instead of updating dependencies or reformatting unrelated files. Invoke the Rails code/security review skills for the final feature diff; verify account scoping, raw input validation before `permit`, legacy prompt owner enforcement, background-rendered routes, no `Current.account=` usage, no schema/package changes, and no private chats/tokens disclosed through counts or chrome.

- [ ] **Step 4: Record verification evidence and commit documentation.** Append actual command outcomes to the guide's Verification section after they run. Include screenshot paths and which manual checks were/weren't performed; do not prewrite successful counts. Then:

```bash
git add docs/account-experience.md docs/README.md docs/DIAGRAMS.md
git commit -m "docs(accounts): explain overview context and privacy guarantees"
```

- [ ] **Step 5: Offer integration choices only after verified completion.** Use `verification-before-completion` and `finishing-a-development-branch`; do not merge, push, delete worktrees, or create a PR without the user's selected integration path. Preserve all unrelated original-worktree changes.

## Plan self-review and spec coverage

| Approved requirement | Tasks |
| --- | --- |
| Balanced index/hub and each requested detail | 1, 7, 8 |
| Start conversation for the selected account | 7, 10; existing composer contract unchanged |
| All four source types and complete account-aware workflows | 3, 4, 5 |
| Background source links and stream identity | 3, 5 |
| Private conversation previews/counts/history | 1, 7, 10 |
| Owner-only account details/shared prompt/membership, including legacy routes | 2, 9, 10 |
| Personal account API tokens, fixed filing, show-once secret | 6, 10 |
| Account-wide token usage and existing detailed reporting | 6, 7 |
| Hub returns, old settings redirect, breadcrumbs, no duplicate global drawer | 7, 9 |
| Empty/default states and no writes/jobs on read/rejection | 2, 4, 7, 9, 10 |
| Grouped counts, bounded pages, batched titles, stable sorting | 1, 7, 10 |
| Themes, French, mobile, keyboard, zoom, reduced motion | 7, 8, 10 |
| Existing routes/regressions and no global account switch | 3–6, 9–11 |
| YARD, docs/diagram updates, evidence, code/security review | 1, 11 |

Execution order is sequential. Source helpers/controllers/views are shared state;
do not run Tasks 3–6 in parallel against the same files. If using fresh agents per
task, provide this plan, the approved spec, previous task commits, and the exact
test-only environment. Do not start implementation merely because the plan exists;
first obtain the execution choice at the handoff.

### Documentation-only planning verification

The author checked every approved spec section against the task map, scanned for
unfinished requirements, checked cross-task method/helper names, and parsed the
Ruby examples and both translation YAML examples. These are **plan checks**, not
application test results. Task 0 remains mandatory before implementation; no
database preparation or application/browser test execution occurred during planning.
