# Chat Workspace UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the dashboard's focused neutral/green design to new and saved chats, with private on-demand history, reader-aware scrolling, accessible details, and preserved composer/streaming behavior.

**Architecture:** Compose a chat-only page shell from focused ERB partials. Keep the existing server-side chat/account/source/generation APIs, reuse personal membership-aware history and batched titles, and give native dialogs, reader following, disclosure restoration, and phase announcements separate small Stimulus owners. Consolidate the duplicated message renderer before changing its presentation.

**Tech Stack:** Verified Ruby 4.0.7; locked Rails 8.0.5.1, RubyLLM 2.0.0, Lexxy 0.9.23, Tailwind 4.1.16; PostgreSQL, ERB, Turbo, Stimulus, Importmap, Propshaft, Minitest/fixtures, Selenium/Chromium. Follow this checkout, not generic version claims in AGENTS.md. No Node build or dependency installation.

---

## Authority and handoff

The user reviewed [the specification](../specs/2026-10-28-chat-workspace-ui-ux-design.md)
at `7ce92e4` and answered **“Go”** to implementation planning. All Decisions in that
specification are binding. Planning does not authorize implementation, a merge,
push, PR, dependency upgrade, unrelated repair, or development-data changes.

Planning uses `/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-design`,
branch `docs/chat-workspace-design`, based on `7ce92e4`. Only documentation changes
belong here. Ruby version and `bundle check` succeeded; no runtime baseline,
database setup, assets, or application tests have been run during planning.
PostgreSQL is configured: SQLite copying does not apply. Task 0 provisions a
separate execution workspace and dedicated test database.

Read these before execution: `docs/chat-composer.md`, `docs/chat-account-selection.md`,
`docs/dashboard.md`, the approved spec, and the path-specific repository rules.
Use TDD for changes and characterize behavior before extraction. Each numbered
task ends with a review checkpoint; commit only its named files after green tests.

## File and responsibility map

| Unit | Files | Responsibility |
| --- | --- | --- |
| Baseline | External `/tmp/opencode/chat-workspace-env.sh` and evidence directory | Isolated test commands and truthful exits; no application changes |
| Fixtures | New `test/support/chat_workspace_fixtures.rb`; new `test/support/fixtures/chat_workspace/{chats,messages,token_usages}.yml` | Reuse account-picker fixtures; add deterministic transcripts, usage, peer/child chats |
| Rendering seam | `app/views/messages/{_message,_body,_user,_assistant}.html.erb`; `app/models/message.rb:118-122`; new `test/integration/chat_message_rendering_test.rb` | One wrapper and role body; update payload selects the body-only partial without changing action/target |
| Page context | `app/controllers/chats_controller.rb`; new `app/helpers/chat_workspaces_helper.rb`; `app/views/layouts/application.html.erb` | Authorized personal history/title data and chat-only shell guards |
| Shell | `app/views/chats/{new,show}.html.erb`; new `_header`, `_history`, `_transcript` partials | Introduction, title/account/actions, native history, preserved transcript/subscriptions |
| Visual scope | New `app/assets/stylesheets/nosia/chat_workspace.css`; `app/assets/tailwind/application.css` | Dashboard-consistent chat-only surfaces, layout, local overflow, reduced motion |
| Copy | New `config/locales/{en,fr}.nosia_chat_workspace.yml` | New interface labels; do not duplicate existing localization keys |
| Dialogs | New `app/javascript/controllers/chat_dialog_controller.js`; `app/views/chats/{_tools,_mcp_selector}.html.erb` | Native modal lifecycle shared only by chat History and existing saved Tools |
| Details | `app/views/chats/_token_totals.html.erb`; `app/views/messages/{_assistant,_token_footer,_search_content}.html.erb` | Separate source/reasoning/response disclosures and complete usage values |
| Following | `app/javascript/controllers/scroll_controller.js`; `app/views/messages/_form.html.erb`; chat show/transcript | Reader-follow/paused intent, Latest message, successful own submission, morph anchors |
| Live UI | New `app/javascript/controllers/chat_disclosures_controller.js`, `chat_feedback_controller.js`; message thinking partials | Restore detail openness/focus across replacement; announce phases, not token deltas |
| Tests | New `test/controllers/chat_workspace_test.rb`; new `test/system/chat_workspace_test.rb`; new `test/support/chat_workspace_browser_checks.rb` | Request privacy/structure plus real browser interactions and visual evidence |
| Documentation | New `docs/chat-workspace.md`; `docs/README.md`; `docs/chat-composer.md` | User-facing behavior, preserved contracts, verification/limitations |

Do not change `config/routes.rb`, schema, generation logic/jobs, accounting,
`chat-account`, `composer-sources`, `composer`, global history partials, or shared
modal infrastructure. Native dialog integration below replaces the saved-chat
Tools trigger only. Existing background composer rendering needs no request user.
The only planned model edit is selecting the body-only view partial for the
existing Message update broadcast, after its duplicate-ID regression test fails.

## Task 0: Isolate execution and establish baselines

**Files:** External environment/evidence files only. Never run database commands in
the main checkout or share a database with another test process.

- [ ] **Step 1: Inspect/create an execution worktree from the approved plan commit.**

```bash
git -C /home/cbldev/gitd/dilolabs/nosia status --short
git -C /home/cbldev/gitd/dilolabs/nosia worktree list
git -C /home/cbldev/gitd/dilolabs/nosia check-ignore .worktrees/chat-workspace-ui
git -C /home/cbldev/gitd/dilolabs/nosia branch --list feat/chat-workspace-ui
git -C /home/cbldev/gitd/dilolabs/nosia rev-parse docs/chat-workspace-design
git -C /home/cbldev/gitd/dilolabs/nosia worktree add .worktrees/chat-workspace-ui -b feat/chat-workspace-ui docs/chat-workspace-design
```

Record the immutable plan commit SHA. If a path or branch already exists, inspect
it rather than overwriting it. Move the session to that execution worktree. Do not
copy `.env`, development databases, user modifications, or generated assets.

- [ ] **Step 2: Create a fresh evidence directory and external shell helper.**

Inspect `/tmp/opencode/chat-workspace-env.sh` and
`/tmp/opencode/chat-workspace-evidence.path` before creating them; if either exists,
stop and establish ownership rather than overwrite it. Save the path once:

```bash
mktemp -d /tmp/opencode/chat-workspace-XXXXXX > /tmp/opencode/chat-workspace-evidence.path
git rev-parse HEAD > "$(< /tmp/opencode/chat-workspace-evidence.path)/base-sha.txt"
```

Use the patch tool to create `/tmp/opencode/chat-workspace-env.sh` with:

```bash
export NOSIA_MAIN=/home/cbldev/gitd/dilolabs/nosia
export EVIDENCE="$(< /tmp/opencode/chat-workspace-evidence.path)"
export BASE="$(< "$EVIDENCE/base-sha.txt")"
export RUBOCOP_TARGET_RUBY_VERSION=4.0
test -d "$EVIDENCE" || return 125
test_command() {
  mise exec ruby@4.0.7 -- bundle exec dotenv -f "$NOSIA_MAIN/.env" -- env \
    RAILS_ENV=test DATABASE_URL=postgresql:///nosia_chat_workspace_ui_test \
    AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 "$@"
}
rails_test() { test_command bin/rails "$@"; }
browser_test() {
  test_command bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test "$@"
}
record() {
  local label="$1" log result
  shift
  log="$(mktemp "$EVIDENCE/$label.XXXXXX.log")" || return 125
  if "$@" >"$log" 2>&1; then result=0; else result=$?; fi
  printf '%s\n' "$result" >"${log%.log}.exit" || return 125
  tail -n 30 "$log" || return 125
  printf 'Evidence: %s; exit: %s\n' "$log" "$result"
  return "$result"
}
```

The nondisplaying dotenv process may consume the main environment; never display,
read with a file tool, source, copy, or log its values. Fixed test overrides follow
dotenv. Do not start workers or live AI/MCP/crawl/indexing operations.

- [ ] **Step 3: Verify prerequisites and database identity before preparation.**

```bash
mise exec ruby@4.0.7 -- ruby --version
mise exec ruby@4.0.7 -- bundle check
command -v chromium
command -v chromedriver
df -h . /tmp/opencode
source /tmp/opencode/chat-workspace-env.sh
record config test_command bundle exec ruby -ryaml -rerb -ractive_record -ractive_record/database_configurations -e 'raw=YAML.safe_load(ERB.new(File.read("config/database.yml")).result, aliases:true); c=ActiveRecord::DatabaseConfigurations.new(raw).configs_for(env_name:"test").first; abort "wrong database" unless c.database=="nosia_chat_workspace_ui_test"; puts "Isolated test configuration verified"'
record prepare rails_test db:prepare
record identity rails_test runner 'abort "wrong environment" unless Rails.env.test?; abort "wrong database" unless ActiveRecord::Base.connection_db_config.database=="nosia_chat_workspace_ui_test"; puts "Isolated test database verified"'
```

Stop on a missing prerequisite, extension, credential, or incorrect database. Do
not install packages or reset a shared database. No application tests are safe
until both database identity checks pass.

- [ ] **Step 4: Run fresh baseline categories sequentially.** Source the helper in
each shell. Long suites may need a 900000ms tool timeout; retain real exit status.

```bash
record baseline-build rails_test tailwindcss:build
record baseline-focused rails_test test test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb test/controllers/chat_account_url_race_test.rb test/controllers/chat_sources_controller_test.rb test/models/chat_test.rb test/models/dashboard_recents_test.rb test/internationalization/catalogs_test.rb
record baseline-browser browser_test test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_waiting_ux_test.rb test/system/dashboard_test.rb
record baseline-full rails_test test
record baseline-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/models/message.rb app/controllers/chats_controller.rb test/integration/chat_composer_ui_test.rb test/system/chat_composer_ui_test.rb
record baseline-security mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

The current `chat_waiting_ux_test.rb` is largely comments and is **not evidence** of
its named end-to-end workflow. New browser tests below must actually assert it.
Historical request-options/full-suite or security problems are observations, not
accepted failures for this feature. Report actual failures, errors, skips, seeds,
counts, command exits, and timeouts. Ask for direction before implementation if
any baseline fails. Do not silently repair unrelated code or weaken assertions.

- [ ] **Step 5: Review checkpoint.** Confirm no source changes, identify the evidence
directory and immutable base, report all baselines and constraints, then obtain any
necessary user acceptance before Task 1. This task has no fabricated RED or commit.

### Task 0 execution checkpoint — accepted with limitations

The user selected subagent-driven execution, confirmed ownership of the worktree's
later `.env` and `bin/dev` server/worker, then explicitly selected **“Proceed with
exceptions”**. Leave those user-owned files/processes untouched.

Evidence: `/tmp/opencode/chat-workspace-hqSpCt/task-0-report.md`; helper:
`/tmp/opencode/chat-workspace-env.sh`; isolated database:
`nosia_chat_workspace_ui_test`. Build passed. Focused tests passed (157 runs,
12,826 assertions). Browser baseline had 79 runs and one existing setup error:
the commented waiting-UX scaffold visits the POST-only `/login` URL. Lint passed
on four existing files. Brakeman reported two existing high-confidence warnings
(API-token account mass assignment and Rails EOL); neither is suppressed/resolved.

The unrestricted full suite was **not run and remains UNVERIFIED** because an
existing crawl test can reach real robots/embedding operations. This accepted
exception does not permit live integrations, hidden test stubs, unrelated fixes,
or treating the waiting scaffold as workflow coverage. New focused/browser
regressions remain mandatory; new failures are not covered by these exceptions.

Setup spec review `ses_e7bd00f20ffeyjkKSRdIk4yE19` and quality review
`ses_e7bc7c489ffe491iOyqhmiDchC` approved proceeding to Task 1 under these limits.
The setup source remained at immutable `a6117dc23b83d383997d995b68b4f7dc38495eec`.
The helper is not a network sandbox and must be invoked from the execution
worktree, never main. No application changes were made during setup.

## Task 1: Characterize and consolidate message rendering

**Files:** New fixture/helper files in the map; new
`test/integration/chat_message_rendering_test.rb`; modify
`app/views/messages/_message.html.erb:1-108`, new `_body.html.erb`, existing role
partials' wrapper boundaries, and `app/models/message.rb:118-122`. Initial-render
characterization is GREEN before and after extraction. The update-envelope
duplicate-ID test is a separate RED before the payload correction.

- [ ] **Step 1: Add deterministic fixture files.**

`test/support/fixtures/chat_workspace/chats.yml`:

```yaml
picker_second_chat:
  account: picker_second
  user: picker_owner
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:picker_model) %>
picker_foreign_chat:
  account: picker_foreign
  user: picker_outsider
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:picker_model) %>
workspace_first_chat:
  account: picker_first
  user: picker_owner
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:picker_model) %>
workspace_peer_chat:
  account: picker_second
  user: picker_outsider
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:picker_model) %>
workspace_child_chat:
  account: picker_second
  user: picker_owner
  chat: picker_second_chat
  ruby_llm_model_id: <%= ActiveRecord::FixtureSet.identify(:picker_model) %>
```

`test/support/fixtures/chat_workspace/messages.yml`:

```yaml
workspace_question:
  chat: picker_second_chat
  role: 20
  content: "What are the key findings in this report?"
  created_at: 2026-10-20 10:00:00
workspace_answer:
  chat: picker_second_chat
  role: 10
  content: <%= ("<think>Evidence was compared carefully.</think>\n\n## Three findings\n\n" + (1..80).map { |i| "Paragraph #{i}: efficient resource use and clearer evaluation criteria." }.join("\n\n")).to_json %>
  done: true
  input_tokens: 120
  output_tokens: 24
  created_at: 2026-10-20 10:01:00
workspace_first_question:
  chat: workspace_first_chat
  role: 20
  content: "First account question"
  created_at: 2026-10-19 10:00:00
workspace_peer_question:
  chat: workspace_peer_chat
  role: 20
  content: "Private peer question"
  created_at: 2026-10-19 10:00:00
```

`test/support/fixtures/chat_workspace/token_usages.yml`:

```yaml
workspace_completion:
  account: picker_second
  chat: picker_second_chat
  kind: completion
  model_id: picker-test-model
  input_tokens: 120
  output_tokens: 24
workspace_embedding:
  account: picker_second
  chat: picker_second_chat
  kind: embedding
  input_tokens: 5
  output_tokens: 0
```

`test/support/chat_workspace_fixtures.rb`:

```ruby
require_relative "chat_account_fixtures"

module ChatWorkspaceFixtures
  extend ActiveSupport::Concern
  include ChatAccountFixtures

  included do
    setup do
      @workspace_sets = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/chat_workspace").to_s,
        %w[chats messages token_usages]
      ).index_by(&:name)
      @chat = chats(:picker_second_chat)
      @chat.update_columns(input_tokens_count: 125, output_tokens_count: 24)
    end
  end

  def workspace(table, name)
    @workspace_sets.fetch(table.to_s).fixtures.fetch(name.to_s).find
  end
end
```

Loading a second fixture set for a table replaces that table's rows. The workspace
chats file deliberately repeats the original picker chat labels/IDs so the reused
picker helper's accessors still resolve; do not omit those two rows or mix this
helper with another support loader that replaces its tables afterward.

- [ ] **Step 2: Write/run characterization tests before the extraction.** Complete
`test/integration/chat_message_rendering_test.rb`:

```ruby
require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"

class ChatMessageRenderingTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper

  test "message entry point keeps one role wrapper and streaming content target" do
    [ workspace(:messages, :workspace_question), workspace(:messages, :workspace_answer) ].each do |message|
      html = ApplicationController.render(partial: "messages/message", locals: { message: message })
      fragment = Nokogiri::HTML.fragment(html)
      assert_select fragment, "##{dom_id(message, :messages)}", count: 1
      if message.assistant?
        assert_select fragment, "##{dom_id(message, :content)}", count: 1
        assert_select fragment, "h2", text: "Three findings"
        assert_select fragment, "details", minimum: 1
      else
        assert_includes fragment.text, "What are the key findings"
      end
    end
  end

  test "saved request and streamed render use the same message identities" do
    sign_in_picker_user
    get chat_url(@chat)
    assert_response :success
    assert_select "##{dom_id(@chat, :messages)}", count: 1
    assert_select "##{dom_id(workspace(:messages, :workspace_answer), :content)}", count: 1
    assert_select "turbo-frame[id='#{dom_id(@chat)}_message_form']", count: 1
  end
end
```

```bash
record rendering-before rails_test test test/integration/chat_message_rendering_test.rb test/controllers/chats_controller_test.rb test/integration/chat_composer_ui_test.rb
```

Expected: PASS at the unmodified renderer. If it fails, investigate the fixture or
existing contract; do not call that a feature RED.

- [ ] **Step 3: Write/run the actual update-envelope regression before correcting it.**

Add this regression to the test class:

```ruby
test "actual update payload does not nest a second message wrapper" do
  message = workspace(:messages, :workspace_answer)
  current = Nokogiri::HTML.fragment(ApplicationController.render(partial: "messages/message", locals: { message: message }))
  streams = capture_turbo_stream_broadcasts([@chat, :messages, :en]) { message.broadcast_updated }
  update = streams.find { |stream| stream["action"] == "update" && stream["target"] == dom_id(message, :messages) }
  assert update
  current.at_css("##{dom_id(message, :messages)}").inner_html = update.inner_html
  assert_select current, "##{dom_id(message, :messages)}", count: 1
  assert_select current, "##{dom_id(message, :content)}", count: 1
end
```

```bash
record update-envelope-red rails_test test test/integration/chat_message_rendering_test.rb
```

Expected from code inspection: FAIL because the current `update` payload contains
the outer message wrapper again. If actual baseline behavior differs, inspect the
captured envelope and preserve the passing behavior; do not force a model edit.

- [ ] **Step 4: Give initial/append rendering one wrapper and updates body-only content.**

Complete `_message.html.erb`:

```erb
<%= tag.div id: dom_id(message, :messages), class: "message-container mb-6", data: { created_at: message.created_at.iso8601 } do %>
  <%= render "messages/body", message: message %>
<% end %>
```

Complete new `_body.html.erb`:

```erb
<%= render(message.user? ? "messages/user" : "messages/assistant", message: message) %>
```

In both role partials remove only the outer `tag.div` carrying the message ID and
its matching final `end`, plus the now-unused `container_class` declarations. Keep
the body unchanged. In `Message#broadcast_updated`, keep action, stream, target,
and locals, adding only this argument:

```ruby
broadcast_localized_to :update, chat, :messages, target: dom_id(self, :messages),
  partial: "messages/body", locals: { message: self, scroll_to: true }
```

This retains the current user-versus-assistant fallback; do not start displaying
hidden system/tool roles or add message-ordering target attributes. The existing
ordering observer re-appends marked nodes, so adding markers without changing its
algorithm can produce mutation loops and is outside this extraction.

- [ ] **Step 5: Re-run characterization and existing account/citation rendering.**

```bash
record rendering-after rails_test test test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/controllers/chats_controller_test.rb test/controllers/chat_account_citations_test.rb
```

Expected: same identities/content and green regression tests; compare before/after
HTML for the question, answer, reasoning, and blank in-progress assistant.

- [ ] **Step 6: Review and commit only fixture/rendering files.**

```bash
git add test/support/chat_workspace_fixtures.rb test/support/fixtures/chat_workspace test/integration/chat_message_rendering_test.rb app/views/messages/_message.html.erb app/views/messages/_body.html.erb app/views/messages/_user.html.erb app/views/messages/_assistant.html.erb app/models/message.rb
git commit -m "refactor(chats): Consolidate message rendering behind role partials"
```

Review gate: no duplicate DOM IDs, query/role changes, new broadcast, composer
change, or untested transcript markup loss.

## Task 2: Build the chat-only shell and private history presentation

**Files:** `app/controllers/chats_controller.rb:4-21`; new helper, shell/history/
transcript partials and paired catalogs; new `test/controllers/chat_workspace_test.rb`;
`app/views/layouts/application.html.erb:37-47`; chat stylesheet/import. Keep the
existing `create`, `destroy`, and `stop` actions unchanged.

- [ ] **Step 1: Write the failing request tests.**

```ruby
require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class ChatWorkspaceTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "new and saved pages own their shell without duplicate global history" do
    [ new_chat_url, chat_url(@chat) ].each do |url|
      get url
      assert_response :success
      assert_select ".n-chat-workspace h1", count: 1
      assert_select "main.n-chat-main", count: 1
      assert_select "button[aria-controls=chat-history]", text: "History", count: 1
      assert_select "dialog#chat-history:not([open])", count: 1
      assert_select "#accordion-right-actions, #drawer-right", count: 0
      assert_select ".n-chat-composer", count: 1
    end
  end

  test "history excludes peers children and revoked memberships" do
    get new_chat_url
    assert_select "[data-history-chat='#{@chat.id}']", count: 1
    assert_select "[data-history-chat='#{workspace(:chats, :workspace_peer_chat).id}']", count: 0
    assert_select "[data-history-chat='#{workspace(:chats, :workspace_child_chat).id}']", count: 0
    assert_select "[data-history-chat='#{chats(:picker_foreign_chat).id}']", count: 0
    @user.account_users.find_by!(account: @second).destroy!
    get new_chat_url
    assert_select "[data-history-chat='#{@chat.id}']", count: 0
    get chat_url(@chat)
    assert_response :not_found
  end

  test "title previews are plain bounded text and the full question stays in the transcript" do
    question = workspace(:messages, :workspace_question)
    question.update_columns(content: "<b>" + "A" * 240 + "</b>")
    get chat_url(@chat)
    assert_select ".n-chat-workspace h1" do |nodes|
      assert_equal 120, nodes.first.text.length
      assert_empty nodes.first.css("b")
    end
    assert_select "##{dom_id(question, :messages)}", text: /A{240}/
    assert_select "[data-history-chat='#{@chat.id}'] [aria-current=page]", count: 1
  end

  test "saved shell keeps stream targets and fixed account context" do
    get chat_url(@chat), params: { account_id: @first.id }
    assert_select "[data-chat-account-readonly]", text: /#{Regexp.escape(@second.name)}/
    assert_select "##{dom_id(@chat, :messages)}", count: 1
    assert_select "##{dom_id(@chat, :token_totals)}", count: 1
    assert_select "turbo-frame[id='#{dom_id(@chat)}_message_form']", count: 1
    assert_select "turbo-cable-stream-source", minimum: 2
  end

  test "no membership shows setup and empty history in French" do
    @user.account_users.destroy_all
    get new_chat_url, headers: { "Accept-Language" => "fr" }
    assert_response :success
    assert_select "html[lang=fr]"
    assert_select "[data-chat-no-account]", count: 1
    assert_select "a[href='#{accounts_path}']", text: "Configurer un compte"
    assert_select ".n-chat-composer", count: 0
    assert_select "#chat-history [data-history-empty]", count: 1
  end
end
```

```bash
record shell-red rails_test test test/controllers/chat_workspace_test.rb
```

Expected: FAIL for missing chat shell/header/dialog; not missing fixture methods
or sign-in problems. Fix test setup before using it as RED evidence.

- [ ] **Step 2: Add controller/helper context and localization.** Add
`before_action :set_workspace, only: [ :new, :show ]` after `set_chat` registration.
Add the following private method below `set_chat`; it performs no new authorization:

```ruby
def set_workspace
  @history = Current.user.recent_conversations.to_a
  @history_titles = Chat.first_questions_for(@history)
end
```

Use existing private-method indentation. Keep history complete as today; do not
silently limit it to dashboard's five recents or invent a new loading endpoint.
`@chat` is needed only in the templates, not by this before action on `new`.

Create `app/helpers/chat_workspaces_helper.rb`:

```ruby
# Presentation and layout identification for the dedicated chat pages.
module ChatWorkspacesHelper
  # @return [Boolean] Whether this page owns the focused chat shell
  def chat_workspace_page?
    controller_path == "chats" && %w[new show].include?(action_name)
  end

  # @param chat [Chat] An authorized personal conversation
  # @param titles [Hash] Batched first-question content keyed by chat ID
  # @return [String] Plain-text title preview including a localized fallback
  def chat_workspace_title(chat, titles:)
    truncate(account_conversation_title(chat, titles: titles), length: 120, omission: "…")
  end
end
```

Create `en.nosia_chat_workspace.yml` with this mapping, nested beneath
`en: / nosia: / chat_workspace:`:

```yaml
new_eyebrow: "New conversation"
new_title: "What would you like to explore?"
new_help: "Ask a question, attach a PDF, or use your account’s sources."
history: "History"
history_title: "Conversation history"
history_help: "Your conversations in accounts you can access."
no_history: "No conversations yet."
current: "Current conversation"
close: "Close"
new_chat: "New chat"
usage_details: "Usage details"
response_details: "Response details"
latest: "Latest message"
transcript: "Conversation messages"
reply: "Reply to this conversation"
estimates: "Environmental impact estimates"
completed: "Response complete."
setup_account: "Set up an account"
retry: "Retry"
```

Create `fr.nosia_chat_workspace.yml` with the same mapping beneath
`fr: / nosia: / chat_workspace:`:

```yaml
new_eyebrow: "Nouvelle conversation"
new_title: "Que souhaitez-vous explorer ?"
new_help: "Posez une question, joignez un PDF ou utilisez les sources de votre compte."
history: "Historique"
history_title: "Historique des conversations"
history_help: "Vos conversations dans les comptes auxquels vous avez accès."
no_history: "Aucune conversation pour le moment."
current: "Conversation en cours"
close: "Fermer"
new_chat: "Nouvelle conversation"
usage_details: "Détails de l’utilisation"
response_details: "Détails de la réponse"
latest: "Dernier message"
transcript: "Messages de la conversation"
reply: "Répondre à cette conversation"
estimates: "Estimations de l’impact environnemental"
completed: "Réponse terminée."
setup_account: "Configurer un compte"
retry: "Réessayer"
```

Do not add existing `nosia.chat.*` or `nosia.usage.*` keys a second time; catalog
tests deliberately reject duplicate leaf keys.

- [ ] **Step 3: Add focused page partials and wire their layout boundaries.**

`app/views/chats/_header.html.erb`:

```erb
<%# locals: (chat:, titles:) %>
<header class="n-chat-header">
  <div class="n-chat-toolbar">
    <%= link_to t("nosia.nav.home"), user_root_path, class: "n-workspace-link" %>
    <div class="n-workspace-actions">
      <button type="button" class="n-workspace-button" aria-controls="chat-history" aria-haspopup="dialog" data-action="chat-dialog#open" data-chat-dialog-id-param="chat-history"><%= t("nosia.chat_workspace.history") %></button>
      <% if chat.persisted? %>
        <%= link_to t("nosia.chat_workspace.new_chat"), new_chat_path, class: "n-workspace-button" %>
      <% end %>
    </div>
  </div>
  <% if chat.persisted? %>
    <h1 class="n-chat-title"><%= chat_workspace_title(chat, titles: titles) %></h1>
    <p class="n-workspace-help"><%= chat.account.name %></p>
    <details id="chat-usage-details" data-chat-detail class="n-chat-details">
      <summary id="chat-usage-summary"><%= t("nosia.chat_workspace.usage_details") %></summary>
      <%= render "chats/token_totals", chat: chat %>
    </details>
  <% end %>
</header>
```

`app/views/chats/_history.html.erb`:

```erb
<%# locals: (chat:, conversations:, titles:) %>
<dialog id="chat-history" class="n-chat-dialog n-chat-history" aria-labelledby="chat-history-title" data-action="close->chat-dialog#closed">
  <header class="n-chat-toolbar">
    <h2 id="chat-history-title"><%= t("nosia.chat_workspace.history_title") %></h2>
    <button type="button" class="n-workspace-button" autofocus data-action="chat-dialog#close"><%= t("nosia.chat_workspace.close") %></button>
  </header>
  <p class="n-workspace-help"><%= t("nosia.chat_workspace.history_help") %></p>
  <ul class="n-chat-history-list !list-none">
    <% conversations.each do |conversation| %>
      <li data-history-chat="<%= conversation.id %>" class="n-chat-history-row">
        <div>
          <%= link_to chat_workspace_title(conversation, titles: titles), chat_path(conversation), class: "n-workspace-link", aria: { current: ("page" if conversation == chat) } %>
          <p class="n-workspace-help"><%= conversation.account.name %></p>
          <time class="n-workspace-help" datetime="<%= conversation.updated_at.iso8601 %>"><%= l(conversation.updated_at, format: :short) %></time>
          <% if conversation == chat %><p class="n-workspace-help"><%= t("nosia.chat_workspace.current") %></p><% end %>
        </div>
        <%= button_to t("nosia.nav.delete_chat"), chat_path(conversation), method: :delete, class: "n-workspace-button n-workspace-danger", data: { turbo_confirm: t("nosia.actions.confirm_delete") } %>
      </li>
    <% end %>
  </ul>
  <% if conversations.empty? %><p class="n-workspace-help" data-history-empty><%= t("nosia.chat_workspace.no_history") %></p><% end %>
</dialog>
```

`app/views/chats/_transcript.html.erb`:

```erb
<%# locals: (chat:) %>
<div id="<%= dom_id(chat) %>_messages" class="n-chat-reading-column">
  <%= tag.div id: dom_id(chat, :messages), data: { controller: "message-ordering" } do %>
    <% chat.messages.for_user.where.not(id: nil).order(:created_at).each do |message| %>
      <%= render message, message: message %>
    <% end %>
    <% if chat.generating? %>
      <% in_progress = chat.messages.assistant.where(content: [nil, ""]).where.missing(:ruby_llm_tool_calls).order(:created_at).last %>
      <% if in_progress %>
        <%= render "messages/message", message: in_progress, chat: chat %>
      <% else %>
        <%= render "messages/thinking" %>
      <% end %>
    <% end %>
  <% end %>
</div>
```

Keep the reconstruction comments from `show.html.erb` beside this logic. The outer
`chat_ID_messages` and inner `messages_chat_ID` identities have different roles;
do not collapse them, duplicate the totals target, or change broadcast targets.

For `new.html.erb`, retain all existing chat-account `data-*` values/actions and
replace only its class/inner sections with this structure:

```erb
<% content_for :title, t("nosia.chat.new") %>
<div id="new-chat-workspace" class="n-chat-workspace n-chat-workspace--new"
     data-controller="chat-account"
     data-chat-account-account-id-value="<%= @chat.account_id %>"
     data-chat-account-confirm-message-value="<%= t('nosia.chat.change_account') %>"
     data-action="composer-sources:state->chat-account#sourceState dropzone:state->chat-account#sourceState turbo:submit-start->chat-account#submitStarted turbo:submit-end->chat-account#submitEnded turbo:before-cache@document->chat-account#beforeCache:capture">
  <%= render "header", chat: @chat, titles: @history_titles %>
  <section class="n-chat-start n-chat-reading-column">
    <p class="n-chat-eyebrow"><%= t("nosia.chat_workspace.new_eyebrow") %></p>
    <h1 class="n-chat-title"><%= t("nosia.chat_workspace.new_title") %></h1>
    <p class="n-workspace-help"><%= t("nosia.chat_workspace.new_help") %></p>
    <%= render "form", chat: @chat %>
    <% unless @chat.account %><%= link_to t("nosia.chat_workspace.setup_account"), accounts_path, class: "n-workspace-link" %><% end %>
  </section>
  <%= render "history", chat: @chat, conversations: @history, titles: @history_titles %>
</div>
```

For `show.html.erb`, keep its chat-account and chat-reconnect values/actions intact,
replace the hard-coded height class with `n-chat-workspace n-chat-workspace--saved`,
set `id="chat-workspace-<%= @chat.id %>"`, and use this complete inner body:

```erb
<%= render "header", chat: @chat, titles: @history_titles %>
<div class="n-chat-follow">
  <button type="button" class="n-workspace-button" hidden data-scroll-target="latest" data-action="scroll#latest"><%= t("nosia.chat_workspace.latest") %></button>
</div>
<section class="n-chat-transcript" aria-label="<%= t('nosia.chat_workspace.transcript') %>" data-scroll-target="viewport">
  <%= render "transcript", chat: @chat %>
</section>
<section class="n-chat-dock n-chat-reading-column" aria-label="<%= t('nosia.chat_workspace.reply') %>">
  <%= render "messages/form", chat: @chat %>
</section>
<%= turbo_stream_from @chat, :messages, I18n.locale %>
<%= turbo_stream_from @chat, :token_totals, I18n.locale %>
<%= render "history", chat: @chat, conversations: @history, titles: @history_titles %>
<%= render "chats/mcp_selector", chat: @chat %>
```

Also set the saved page's document title with `content_for :title,
chat_workspace_title(@chat, titles: @history_titles)`. Remove the old nested
`data-controller="scroll"` and unconditional window new-message scroll action;
Task 5 installs following on the stable page root. Task 3 adds `chat-dialog` to
both roots, so History becomes interactive in that independently tested task.

In the layout use:

```erb
<main class="<%= chat_workspace_page? ? 'n-chat-main' : 'overflow-y-auto w-full pl-6 pt-6 pr-2 lg:p-6' %>">
```

Add `|| chat_workspace_page?` to the existing navbar-suppression expression and
`&& !chat_workspace_page?` to the existing global-history condition. Do not replace
the other workspace guards or change the shared header/left menu.

- [ ] **Step 4: Add the scoped stylesheet.** Import this file **unlayered after
composer.css** so its local editor-height overrides beat Lexxy/composer rules;
all overrides must require `.n-chat-workspace`, never dashboard selectors.

```css
.n-chat-main { display:flex; min-width:0; min-height:0; width:100%; overflow:hidden; padding:1.25rem; }
.n-chat-workspace { @apply text-neutral-900 dark:text-neutral-100; display:flex; flex-direction:column; gap:1rem; min-width:0; min-height:0; width:100%; height:100%; }
.n-chat-header { flex:none; min-width:0; }
.n-chat-toolbar { display:flex; flex-wrap:wrap; align-items:center; justify-content:space-between; gap:.75rem; }
.n-chat-title { @apply text-2xl font-semibold tracking-tight; margin:.75rem 0 .4rem; overflow-wrap:anywhere; }
.n-chat-reading-column { width:100%; max-width:56rem; min-width:0; margin-inline:auto; }
.n-chat-start { display:flex; flex:1; flex-direction:column; justify-content:center; padding-block:2rem; }
.n-chat-start > :is(h1,p) { text-align:center; }
.n-chat-start > .n-workspace-help { margin:.5rem auto 1.5rem; max-width:45ch; }
.n-chat-eyebrow { @apply text-sm font-medium text-green-800 dark:text-green-200; }
.n-chat-workspace--new { overflow-y:auto; }
.n-chat-transcript { flex:1; min-height:0; overflow-y:auto; overflow-x:hidden; scroll-padding-block:1rem; overflow-anchor:none; }
.n-chat-dock { flex:none; padding-bottom:.25rem; }
.n-chat-follow { flex:none; position:sticky; top:0; z-index:10; align-self:center; }
.n-chat-workspace [hidden] { display:none !important; }
.n-chat-workspace .n-composer-editor .lexxy-editor__content { min-block-size:5rem; max-block-size:22dvh; overflow-y:auto; }
.n-chat-workspace [data-chat-no-account] { @apply text-neutral-600 dark:text-neutral-300; }
.n-chat-dialog { @apply border border-neutral-500 bg-white text-neutral-900 dark:bg-neutral-800 dark:text-neutral-100; width:min(42rem,calc(100vw - 2rem)); max-height:calc(100dvh - 2rem); overflow:auto; padding:1.25rem; border-radius:.75rem; }
.n-chat-dialog::backdrop { background:rgb(0 0 0 / .6); }
.n-chat-history { margin:0 0 0 auto; height:100dvh; max-height:100dvh; border-radius:.75rem 0 0 .75rem; }
.n-chat-history-list { margin-top:1rem; }
.n-chat-history-row { @apply border-b border-neutral-300 dark:border-neutral-600; display:flex; gap:.75rem; padding-block:1rem; }
.n-chat-history-row > div { flex:1; min-width:0; overflow-wrap:anywhere; }
.n-chat-history-row form { flex:none; }
.n-chat-history-row [aria-current=page] { font-weight:700; }
.n-chat-details { min-width:0; margin-block:.5rem; }
.n-chat-workspace .n-chat-details > summary { @apply text-sm font-medium text-green-800 dark:text-green-200; min-height:44px; cursor:pointer; padding-block:.6rem; margin:0; }
.n-chat-workspace :is(button,summary,a):focus-visible { @apply outline-2 outline-offset-2 outline-green-700 dark:outline-green-300; }
.n-chat-workspace :is(pre,.n-chat-table-scroll) { max-width:100%; overflow-x:auto; }
@media (max-width:639px), (max-height:700px) {
  .n-chat-main { overflow-y:auto; padding:1rem 1rem 6rem; scroll-padding-block:4rem 6rem; }
  .n-chat-workspace { height:auto; min-height:100%; }
  .n-chat-transcript { overflow:visible; flex:none; }
  .n-chat-header .n-workspace-actions { flex-wrap:wrap; }
  .n-chat-workspace .n-composer-editor .lexxy-editor__content { min-block-size:3rem; max-block-size:20dvh; }
  .n-chat-start { padding-block:1rem; }
  .n-chat-history-row { flex-wrap:wrap; }
  .n-chat-workspace :is(button,summary,a) { scroll-margin-block:4rem; }
}
@media (prefers-reduced-motion:reduce) {
  .n-chat-workspace *, .n-chat-workspace *::before, .n-chat-workspace *::after { animation:none !important; transition:none !important; scroll-behavior:auto !important; }
}
```

The short/narrow mode intentionally has **one page scroll surface**, not a second
transcript scroller. Task 5 selects the matching scroll surface. New-chat Tools
menus stay overflow-visible outside the editor; do not clip the composer surface.

- [ ] **Step 5: Build, run green tests, review, and commit.**

```bash
record shell-build rails_test tailwindcss:build
record shell-green rails_test test test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/controllers/chats_controller_test.rb test/controllers/dashboards_controller_test.rb test/internationalization/catalogs_test.rb
git add app/controllers/chats_controller.rb app/helpers/chat_workspaces_helper.rb app/views/chats/new.html.erb app/views/chats/show.html.erb app/views/chats/_header.html.erb app/views/chats/_history.html.erb app/views/chats/_transcript.html.erb app/views/layouts/application.html.erb app/assets/stylesheets/nosia/chat_workspace.css app/assets/tailwind/application.css config/locales/en.nosia_chat_workspace.yml config/locales/fr.nosia_chat_workspace.yml test/controllers/chat_workspace_test.rb
git commit -m "feat(chats): Add focused conversation shell and private history"
```

Expected: new shell/privacy assertions pass; old composer/background/refresh
targets still pass. Review both account membership exclusion and unchanged default
selection. History interactivity, message restyling, and reader-follow behavior are
the next tasks, not claims established by these request tests.

## Task 3: Make History and saved Tools accessible native dialogs

**Files:** New `app/javascript/controllers/chat_dialog_controller.js`; chat roots;
`app/views/chats/_tools.html.erb:2-7`, `_mcp_selector.html.erb:1-17,67-75`;
new `test/system/chat_workspace_test.rb`. No global modal/controller changes.

- [ ] **Step 1: Write the failing browser tests.** Create the system test with:

```ruby
require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"

class ChatWorkspaceSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.current_window.resize_to(*@original_size)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "history is modal keyboard-contained and preserves the exact draft editor" do
    visit new_chat_url(account_id: @second.id)
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep this unsent draft")
    page.execute_script("window.savedChatEditor = document.querySelector('lexxy-editor')")
    counts = [ Chat.count, Message.count ]
    click_button "History"
    assert_selector "#chat-history[open]"
    assert page.evaluate_script("document.querySelector('#chat-history').matches(':modal')")
    12.times do
      page.send_keys(:tab)
      assert page.evaluate_script("document.querySelector('#chat-history').contains(document.activeElement)")
    end
    page.send_keys(:escape)
    assert_no_selector "#chat-history[open]"
    assert_selector "button[aria-controls=chat-history]:focus"
    assert page.evaluate_script("window.savedChatEditor === document.querySelector('lexxy-editor')")
    assert_selector "lexxy-editor", text: "Keep this unsent draft"
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "saved Tools stays modal and reachable during generation" do
    @chat.start_generation!
    visit chat_url(@chat)
    assert_button "Stop generating", enable_aria_label: true
    find(".n-composer-tools-trigger").click
    assert_selector "dialog#mcp-selector-modal[open]"
    assert page.evaluate_script("document.querySelector('#mcp-selector-modal').matches(':modal')")
    assert_no_selector "#chat-history[open]"
    within("#mcp-selector-modal") { first("button", text: "Close").click }
    assert_selector ".n-composer-tools-trigger:focus"
    assert_button "Stop generating", enable_aria_label: true
  end

  test "history navigates and its confirmed deletion retains the existing redirect" do
    visit chat_url(@chat)
    click_button "History"
    row = "[data-history-chat='#{workspace(:chats, :workspace_first_chat).id}']"
    within(row) { click_link "First account question" }
    assert_current_path chat_path(workspace(:chats, :workspace_first_chat))
    click_button "History"
    accept_confirm { within(row) { click_button I18n.t("nosia.nav.delete_chat", locale: :en) } }
    assert_current_path user_root_path
    assert_not Chat.exists?(ActiveRecord::FixtureSet.identify(:workspace_first_chat))
  end
end
```

```bash
record dialogs-red browser_test test/system/chat_workspace_test.rb
```

Expected: History click fails to open a dialog; the old saved Tools div is not a
native dialog. This must not be a Chrome/sign-in/fixture failure.

- [ ] **Step 2: Add the page-local dialog owner.**

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.openers = new Map()
    this.caching = false
  }

  open(event) {
    event.preventDefault()
    const dialog = document.getElementById(event.params.id)
    if (!dialog || !this.element.contains(dialog)) return
    this.caching = false
    this.openers.set(dialog.id, event.currentTarget)
    this.element.querySelectorAll("dialog[open]").forEach(item => item.close())
    dialog.showModal()
  }

  close(event) {
    event.preventDefault()
    event.target.closest("dialog")?.close()
  }

  closed(event) {
    const opener = this.openers.get(event.target.id)
    if (!this.caching && !this.element.querySelector("dialog[open]") && opener?.isConnected) opener.focus()
    this.openers.delete(event.target.id)
  }

  beforeCache() {
    this.caching = true
    this.element.querySelectorAll("dialog[open]").forEach(dialog => dialog.close())
    this.openers.clear()
  }
}
```

Add `chat-dialog` to both page roots' `data-controller`, preserving existing names.
Append `turbo:before-cache@document->chat-dialog#beforeCache` to both root actions.
Native `showModal()` supplies keyboard containment, Escape dismissal, and background
inertness; do not add a competing custom trap or explicit broad `[inert]` clearing.

- [ ] **Step 3: Convert the saved Tools trigger and existing modal shell.** Replace
the saved button's old `modal-open` controller/value/action attributes with:

```erb
data-action="chat-dialog#open" data-chat-dialog-id-param="mcp-selector-modal" aria-haspopup="dialog" aria-controls="mcp-selector-modal"
```

In `_mcp_selector.html.erb`, replace the outer div and its final closing tag with:

```erb
<dialog id="mcp-selector-modal" class="n-chat-dialog" aria-labelledby="chat-tools-title" data-action="close->chat-dialog#closed">
</dialog>
```

Those tags enclose the **existing** header, available-server loop, Add/Remove forms,
empty state, and footer. Remove the old `min-h-screen` positioning wrapper and
backdrop div, and remove the inner `relative z-10 w-full max-w-2xl` card wrapper
without deleting its contents. Set `id="chat-tools-title"` on its existing h3.
Both close buttons use `data-action="chat-dialog#close"`; give the icon-only header
button `aria-label="<%= t('nosia.chat_workspace.close') %>"` and its SVG
`aria-hidden="true"`. Keep the footer Close label. Delete no controller file:
`mcp-selector` and `modal-open` can remain available for unrelated users.

Keep account-ready server selection and session Add/Remove URLs intact. Change
only the empty-state configuration link destination from `mcp_servers_path` to
`account_mcp_servers_path(chat.account)`, an existing authorized route, so setup
retains the saved conversation's account. No new route or account preference.

- [ ] **Step 4: Re-run the tests and migrate only the intentional modal selector.**

In `test/system/chat_composer_ui_test.rb:398`, change
`#mcp-selector-modal:not(.hidden)` to `dialog#mcp-selector-modal[open]`. Preserve the
asserted tool name and the actual click. No other assertion removal is authorized.

```bash
record dialogs-green browser_test test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
record dialogs-request rails_test test test/controllers/chat_workspace_test.rb test/controllers/chat_account_tools_test.rb test/integration/chat_composer_ui_test.rb
```

Also dispatch a second dialog open while one is open; verify only one `[open]`
dialog remains and focus stays in it. Cache/navigation must return to closed
history without mutating editor or account/source controller state.

- [ ] **Step 5: Review and commit.**

```bash
git add app/javascript/controllers/chat_dialog_controller.js app/views/chats/new.html.erb app/views/chats/show.html.erb app/views/chats/_tools.html.erb app/views/chats/_mcp_selector.html.erb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb
git commit -m "feat(chats): Add accessible on-demand conversation dialogs"
```

Review gate: private history, native focus/return, draft identity, existing Tools
operations during generation, Escape and Close, no stacked modal or global change.

## Task 4: Calm message surfaces and disclose complete usage metadata

**Files:** `app/views/messages/{_message,_user,_assistant,_token_footer,_search_content}.html.erb`;
`app/views/chats/_token_totals.html.erb`; chat stylesheet; rendering/request tests.
Do not change usage models, existing finalized-message guards, or citation routes.

- [ ] **Step 1: Add RED tests to `ChatMessageRenderingTest`.**

```ruby
test "assistant details retain reasoning and finalized token values without hiding recovery" do
  message = workspace(:messages, :workspace_answer)
  fragment = Nokogiri::HTML.fragment(ApplicationController.render(partial: "messages/message", locals: { message: message }))
  assert_select fragment, "[data-chat-detail] summary", text: I18n.t("nosia.chat.reasoning")
  assert_select fragment, "details[data-response-details]:not([open])", count: 1
  assert_select fragment, "[data-response-details]", text: /Input.*120.*Output.*24/m
  assert_select fragment, "[data-response-details]", text: /Environmental impact estimates/
  assert_select fragment, "[data-response-details]", text: /kWh.*gCO₂e/m
  assert_select fragment, ".n-chat-assistant-body", count: 1
end

test "pending answer has no finalized response details" do
  message = workspace(:messages, :workspace_answer)
  message.update_columns(done: false)
  fragment = Nokogiri::HTML.fragment(ApplicationController.render(partial: "messages/message", locals: { message: message.reload }))
  assert_select fragment, "[data-response-details]", count: 0
end

test "chat totals are complete and render without request scoped Current" do
  Current.reset
  fragment = Nokogiri::HTML.fragment(ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat }))
  assert_select fragment, "##{dom_id(@chat, :token_totals)}", count: 1
  assert_select fragment, "[data-chat-total-input]", text: "125"
  assert_select fragment, "[data-chat-total-output]", text: "24"
  assert_select fragment, "[data-usage-kind=completion]", text: /120.*24/m
  assert_select fragment, "[data-usage-kind=embedding]", text: /5.*0/m
  assert_select fragment, "[data-estimate-note]", text: /fallback/
end

test "eligible error retry remains outside collapsed metadata" do
  message = workspace(:messages, :workspace_answer)
  message.metadata["original_question"] = "Original question"
  with_singleton_replacement(message, :error?, -> { true }) do
    with_singleton_replacement(message, :retryable?, -> { true }) do
      fragment = Nokogiri::HTML.fragment(ApplicationController.render(partial: "messages/message", locals: { message: message }))
      assert_select fragment, "[role=alert]", count: 1
      assert_select fragment, "form[action='#{chat_messages_path(@chat)}'] button", text: "Retry"
      assert_select fragment, "details form", count: 0
      assert_select fragment, "input[value='Original question']", count: 1
    end
  end
end
```

`error?` and `retryable?` currently return false on ordinary Message records. The
last test characterizes the existing extension hook with a local test double; do
not invent a persisted error state or claim a new production retry protocol.

```bash
record details-red rails_test test test/integration/chat_message_rendering_test.rb
```

Expected: FAIL for missing detail wrappers/labeled totals/calm classes.

- [ ] **Step 2: Replace role presentation while preserving the rendering hooks.**

Change only the `_message.html.erb` wrapper's class argument to:

```erb
<%= tag.div id: dom_id(message, :messages), class: "message-container n-chat-message #{'n-chat-message--user' if message.user?}", data: { created_at: message.created_at.iso8601 } do %>
  <%= render "messages/body", message: message %>
<% end %>
```

The entry point still owns the wrapper/timestamp. Complete `_user.html.erb` as
body-only content:

```erb
<div class="n-chat-user-body"><%== sanitize message.content_without_context %></div>
```

Complete `_assistant.html.erb`:

```erb
  <p class="n-chat-assistant-name"><%= t("nosia.chat.assistant") %></p>
  <%= tag.div class: "n-chat-assistant-body", role: ("alert" if message.error?), data: { chat_error: message.error? } do %>
    <%= tag.div id: dom_id(message, :content), class: "prose prose-sm dark:prose-invert max-w-none ai-response-content", data: { controller: "table-wrapper" } do %>
      <%= render "messages/content", message: message %>
    <% end %>
    <% if message.retryable? %>
      <%= button_to t("nosia.chat_workspace.retry"), chat_messages_path(message.chat), params: { message: { content: message.metadata["original_question"] } }, method: :post, form: { data: { turbo_frame: "_top" } }, class: "n-workspace-button n-workspace-primary" %>
    <% end %>
    <% if message.similar_chunks.any? %>
      <details id="<%= dom_id(message, :sources) %>" data-chat-detail class="n-chat-details">
        <summary id="<%= dom_id(message, :sources_summary) %>"><% source_count = message.similar_chunks.count %><%= t("nosia.chat.sources", count: source_count, formatted_count: number_with_delimiter(source_count)) %></summary>
        <%= tag.div id: dom_id(message, :search_content) do %><%= render "messages/search_content", message: message %><% end %>
      </details>
    <% end %>
    <% if message.reasoning_content.present? %>
      <details id="<%= dom_id(message, :reasoning_details) %>" data-chat-detail class="n-chat-details">
        <summary id="<%= dom_id(message, :reasoning_summary) %>"><%= t("nosia.chat.reasoning") %></summary>
        <%= tag.div id: dom_id(message, :reasoning_content) do %><%= render "messages/reasoning_content", message: message %><% end %>
      </details>
    <% end %>
    <% if message.done? && (message.tokens.input || message.tokens.output) %>
      <%= render "messages/token_footer", message: message %>
    <% end %>
  <% end %>
```

Keep `_streaming_content.html.erb` unchanged: it replaces the same content target
with the same markdown/table wrapper. Retain existing source-account filtering and
safe content rendering. Do not move Retry into a disclosure.

Complete `_token_footer.html.erb`:

```erb
<% total_in = message.tokens.input || 0 %>
<% total_out = message.tokens.output || 0 %>
<% energy = GreenIt.energy_kwh(tokens: total_in + total_out, model_id: message.model, kind: :completion) %>
<details id="<%= dom_id(message, :response_details) %>" data-chat-detail data-response-details class="n-chat-details">
  <summary id="<%= dom_id(message, :response_summary) %>"><%= t("nosia.chat_workspace.response_details") %></summary>
  <dl class="n-chat-values">
    <div><dt><%= t("nosia.usage.input") %></dt><dd><%= number_with_delimiter(total_in) %></dd></div>
    <div><dt><%= t("nosia.usage.output") %></dt><dd><%= number_with_delimiter(total_out) %></dd></div>
  </dl>
  <p class="n-workspace-help"><%= t("nosia.chat_workspace.estimates") %>: <%= number_with_precision(energy[:kwh], precision: 6) %> kWh · <%= number_with_precision(GreenIt.co2e_g(kwh: energy[:kwh]), precision: 2) %> gCO₂e</p>
  <% if energy[:fallback] %><p class="n-workspace-help" data-estimate-note><%= t("nosia.usage.fallback_note") %></p><% end %>
</details>
```

Complete `_token_totals.html.erb`:

```erb
<% totals = chat.token_totals_by_kind %>
<% usages = chat.token_usages.to_a %>
<%= tag.div id: dom_id(chat, :token_totals) do %>
  <dl class="n-chat-values">
    <div><dt><%= t("nosia.usage.input") %></dt><dd data-chat-total-input><%= number_with_delimiter(chat.input_tokens_count) %></dd></div>
    <div><dt><%= t("nosia.usage.output") %></dt><dd data-chat-total-output><%= number_with_delimiter(chat.output_tokens_count) %></dd></div>
  </dl>
  <div class="n-chat-table-scroll">
    <table class="n-chat-usage-table">
      <caption><%= t("nosia.usage.per_kind") %></caption>
      <thead><tr><th scope="col"><%= t("nosia.usage.per_kind") %></th><th scope="col"><%= t("nosia.usage.input") %></th><th scope="col"><%= t("nosia.usage.output") %></th></tr></thead>
      <tbody>
        <% totals.each do |kind, sums| %>
          <tr data-usage-kind="<%= kind %>"><th scope="row"><%= t("nosia.usage.kinds.#{kind}") %></th><td><%= number_with_delimiter(sums[0]) %></td><td><%= number_with_delimiter(sums[1]) %></td></tr>
        <% end %>
      </tbody>
    </table>
  </div>
  <p class="n-workspace-help"><%= t("nosia.chat_workspace.estimates") %>: <%= number_with_precision(usages.sum(&:energy_kwh), precision: 6) %> kWh · <%= number_with_precision(usages.sum(&:co2e_g), precision: 2) %> gCO₂e</p>
  <p class="n-workspace-help" data-estimate-note><%= t(usages.any?(&:used_fallback?) ? "nosia.usage.total_fallback_tooltip" : "nosia.usage.total_tooltip") %></p>
<% end %>
```

The totals partial remains renderable in background broadcasts without `Current`.
Its replace target is **inside**, not around, the header's stable `<details>`.

- [ ] **Step 3: Add local surface styles and preserve source links.**

```css
.n-chat-workspace .n-chat-message { margin-block:0 1.5rem; min-width:0; }
.n-chat-workspace .n-chat-message--user { display:flex; justify-content:flex-end; }
.n-chat-workspace .n-chat-user-body { @apply border border-green-700 bg-green-50 text-green-950 dark:border-green-400 dark:bg-green-950 dark:text-green-100; max-width:85%; padding:.9rem 1.1rem; border-radius:.75rem; overflow-wrap:anywhere; font-size:1rem; line-height:1.65; }
.n-chat-workspace .n-chat-assistant-name { @apply text-sm font-medium text-green-800 dark:text-green-200; margin-bottom:.5rem; }
.n-chat-workspace .n-chat-assistant-body { @apply border border-neutral-400 bg-white dark:border-neutral-500 dark:bg-neutral-800; padding:1.25rem; border-radius:.75rem; min-width:0; }
.n-chat-workspace .n-chat-assistant-body[data-chat-error=true] { @apply border-red-700 bg-red-50 text-red-900 dark:border-red-300 dark:bg-red-950 dark:text-red-100; }
.n-chat-workspace .ai-response-content { font-size:1rem; line-height:1.7; overflow-wrap:anywhere; }
.n-chat-workspace .n-chat-values { display:flex; flex-wrap:wrap; gap:1rem 2rem; margin-block:.75rem; font-size:.875rem; }
.n-chat-workspace .n-chat-values dd { font-variant-numeric:tabular-nums; font-weight:600; }
.n-chat-workspace .n-chat-usage-table { width:100%; font-size:.875rem; text-align:left; font-variant-numeric:tabular-nums; }
.n-chat-workspace .n-chat-usage-table :is(th,td) { @apply border-b border-neutral-300 dark:border-neutral-600; padding:.5rem; }
.n-chat-workspace .n-chat-source { @apply block rounded-lg border border-neutral-400 bg-neutral-50 p-3 text-neutral-900 dark:border-neutral-500 dark:bg-neutral-900 dark:text-neutral-100; margin-block:.5rem; overflow-wrap:anywhere; }
.n-chat-workspace .n-chat-source:hover { @apply border-green-700 dark:border-green-300; }
```

Complete `_search_content.html.erb` without changing the evidence destination or
source-account lookup:

```erb
<% if message.similar_chunks.any? %>
  <div class="space-y-2">
    <% message.similar_chunks.each_with_index do |chunk, index| %>
      <%= link_to chunk_path(chunk, chat_id: message.chat_id), class: "n-chat-source", target: "_blank", rel: "noopener" do %>
        <div class="flex min-w-0 items-start gap-3">
          <span aria-hidden="true"><%= index + 1 %></span>
          <div class="min-w-0">
            <p class="font-medium"><%= chunk.title %></p>
            <% if chunk.respond_to?(:document) && chunk.document.present? %>
              <p class="n-workspace-help"><%= chunk.document.name rescue t("nosia.chat.document") %></p>
            <% end %>
          </div>
        </div>
      <% end %>
    <% end %>
  </div>
<% end %>
```

Retain the existing source preview pages unchanged; document citation regression
tests still prove their PDF preview and account isolation.

- [ ] **Step 4: Run green/render/broadcast/citation regressions.**

```bash
record details-build rails_test tailwindcss:build
record details-green rails_test test test/integration/chat_message_rendering_test.rb test/controllers/chat_workspace_test.rb test/controllers/chat_account_citations_test.rb test/integration/chat_composer_ui_test.rb
```

Add a real citation browser/request sample with `insert_picker_chunk`, as used in
`test/controllers/chat_account_citations_test.rb:25-52`, and compare totals and
estimated values to their pre-change Ruby calculations. Do not assert invented
energy constants or consider a fixture-only partial test proof of live delivery.
Task 6 explicitly verifies replacement of these targets.

- [ ] **Step 5: Review and commit.**

```bash
git add app/views/messages/_message.html.erb app/views/messages/_user.html.erb app/views/messages/_assistant.html.erb app/views/messages/_token_footer.html.erb app/views/messages/_search_content.html.erb app/views/chats/_token_totals.html.erb app/assets/stylesheets/nosia/chat_workspace.css test/integration/chat_message_rendering_test.rb
git commit -m "feat(chats): Add readable messages and disclosed usage details"
```

Review gate: exact original usage sources/precision, readable estimate caveats,
initially collapsed independent disclosures, no hidden Retry, no citation leak,
one content/reasoning/search/totals identity per intended target.

## Task 5: Follow the reader, not every mutation

**Files:** Replace `app/javascript/controllers/scroll_controller.js`; modify saved
chat root actions and `app/views/messages/_form.html.erb:5-7`; extend system tests.
No new timers, provider calls, or server persistence for reader intent.

- [ ] **Step 1: Add failing browser tests and a deterministic stream helper.** Add
these methods/tests inside `ChatWorkspaceSystemTest`:

```ruby
def stream_answer(text)
  message = workspace(:messages, :workspace_answer)
  html = ApplicationController.render(partial: "messages/streaming_content", locals: { message: message, content_html: Message.render_markdown_content(text) })
  stream = %(<turbo-stream action="replace" target="#{dom_id(message, :content)}"><template>#{html}</template></turbo-stream>)
  page.execute_script("Turbo.renderStreamMessage(arguments[0])", stream)
  assert_selector "##{dom_id(message, :content)}", text: text.lines.last.strip
end

def reader_surface
  page.evaluate_script("matchMedia('(max-width:639px), (max-height:700px)').matches ? 'main.n-chat-main' : '.n-chat-transcript'")
end

[[1400,1000], [375,812], [812,375]].each do |width, height|
test "streaming pauses and resumes at #{width}x#{height}" do
  page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
  visit chat_url(@chat)
  assert_selector "[data-reader-following=true]"
  surface = reader_surface
  page.execute_script("const e=document.querySelector(arguments[0]); e.scrollTop=120; e.dispatchEvent(new Event('scroll'))", surface)
  assert_selector "[data-reader-following=false]"
  before = page.evaluate_script("document.querySelector(arguments[0]).scrollTop", surface)
  stream_answer("## Answer\n\n" + (1..100).map { |i| "Reading paragraph #{i}." }.join("\n\n"))
  assert_button "Latest message"
  assert_in_delta before, page.evaluate_script("document.querySelector(arguments[0]).scrollTop", surface), 3
  click_button "Latest message"
  assert_selector "[data-reader-following=true]"
  assert_no_button "Latest message"
  gap = page.evaluate_script("((e)=>e.scrollHeight-e.clientHeight-e.scrollTop)(document.querySelector(arguments[0]))", surface)
  assert_operator gap, :<=, 80
end

test "own successful follow-up alone resumes following at #{width}x#{height}" do
  page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
  visit chat_url(@chat)
  surface = reader_surface
  page.execute_script("const e=document.querySelector(arguments[0]); e.scrollTop=80; e.dispatchEvent(new Event('scroll'))", surface)
  assert_selector "[data-reader-following=false]"
  page.execute_script(<<~JS)
    const form=document.querySelector('form[data-chat-followup]');
    form.dispatchEvent(new CustomEvent('turbo:submit-start',{bubbles:true}));
    form.dispatchEvent(new CustomEvent('turbo:submit-end',{bubbles:true,detail:{success:false}}));
  JS
  assert_selector "[data-reader-following=false]"
  visit chat_url(@chat)
  find("lexxy-editor .lexxy-editor__content").send_keys("A real follow-up")
  page.execute_script("const e=document.querySelector(arguments[0]); e.scrollTop=80; e.dispatchEvent(new Event('scroll'))", surface)
  assert_selector "[data-reader-following=false]"
  assert_enqueued_jobs 1, only: ChatResponseJob do
    click_button "Send", enable_aria_label: true
    assert_selector "[data-generation-busy=true]"
  end
  assert_selector "[data-reader-following=true]"
  assert_equal "A real follow-up", @chat.messages.user.order(:id).last.content.strip
end

test "morph and incoming content preserve the paused reader at #{width}x#{height}" do
  page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
  visit chat_url(@chat)
  surface = reader_surface
  find("button[aria-controls=chat-history]").send_keys(:tab)
  page.execute_script("const e=document.querySelector(arguments[0]); e.scrollTop=100; e.dispatchEvent(new Event('scroll')); window.readerFocus=document.activeElement", surface)
  assert_selector "[data-reader-following=false]"
  before = page.evaluate_script("document.querySelector(arguments[0]).scrollTop", surface)
  page.execute_script("Turbo.visit(window.location.href,{action:'replace'})")
  assert_selector "[data-reader-following=false]"
  assert_in_delta before, page.evaluate_script("document.querySelector(arguments[0]).scrollTop", surface), 3
  page.execute_script("window.readerFocus=document.activeElement")
  stream_answer("## More evidence\n\n" + (1..100).map { |i| "Evidence paragraph #{i}." }.join("\n\n"))
  assert page.evaluate_script("document.activeElement===window.readerFocus")
end
end
```

```bash
record following-red browser_test test/system/chat_workspace_test.rb
```

Expected: missing following state or position jumps under streamed content.

- [ ] **Step 2: Install the reader-aware controller.**

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport", "latest"]

  connect() {
    this.state = this.element.chatReaderState ||= { paused: false, anchor: null, pending: false }
    this.onScroll = this.scrolled.bind(this)
    this.main = this.element.closest("main")
    this.main.addEventListener("scroll", this.onScroll)
    this.viewportTarget.addEventListener("scroll", this.onScroll)
    this.observer = new MutationObserver(() => this.schedule(true))
    this.observer.observe(this.viewportTarget, { childList: true, subtree: true, characterData: true })
    this.resizeObserver = new ResizeObserver(() => this.schedule(false))
    this.resizeObserver.observe(this.main)
    this.resizeObserver.observe(this.viewportTarget.firstElementChild)
    this.schedule(false)
  }

  disconnect() {
    this.main.removeEventListener("scroll", this.onScroll)
    this.viewportTarget.removeEventListener("scroll", this.onScroll)
    this.observer.disconnect()
    this.resizeObserver.disconnect()
    cancelAnimationFrame(this.frame)
  }

  get surface() {
    return matchMedia("(max-width:639px), (max-height:700px)").matches ? this.main : this.viewportTarget
  }

  scrolled(event) {
    if (event.target !== this.surface) return
    this.state.paused = this.surface.scrollHeight - this.surface.clientHeight - this.surface.scrollTop > 80
    if (!this.state.paused) this.state.pending = false
    this.capture()
    this.reflect()
  }

  capture() {
    if (!this.state.paused) return
    const top = this.surface.getBoundingClientRect().top
    const anchor = [...this.viewportTarget.querySelectorAll(".message-container[id]")].find(node => node.getBoundingClientRect().bottom > top)
    this.state.anchor = anchor ? { id: anchor.id, offset: anchor.getBoundingClientRect().top - top } : null
  }

  beforeStream(event) {
    const target = document.getElementById(event.target.getAttribute("target"))
    if (target && this.viewportTarget.contains(target)) this.capture()
  }

  schedule(changed = false) {
    this.changed ||= changed
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => this.reconcile())
  }

  reconcile() {
    if (!this.element.isConnected) return
    if (this.state.paused) {
      const anchor = this.state.anchor && document.getElementById(this.state.anchor.id)
      if (anchor) this.surface.scrollTop += anchor.getBoundingClientRect().top - this.surface.getBoundingClientRect().top - this.state.anchor.offset
      if (this.changed && this.surface.scrollHeight - this.surface.clientHeight - this.surface.scrollTop > 80) this.state.pending = true
    } else {
      this.surface.scrollTop = this.surface.scrollHeight
    }
    this.changed = false
    this.reflect()
  }

  reflect() {
    this.element.dataset.readerFollowing = String(!this.state.paused)
    this.latestTarget.hidden = !(this.state.paused && this.state.pending)
  }

  latest() {
    this.state.paused = false
    this.state.pending = false
    this.state.anchor = null
    this.schedule(false)
  }

  submissionStarted(event) {
    if (!event.target.matches("form[data-chat-followup]")) return
    event.target.addEventListener("turbo:submit-end", result => {
      if (result.detail.success && this.element.isConnected) this.latest()
    }, { once: true })
  }

  afterRender() {
    this.schedule(false)
  }
}
```

This deliberately stores only ephemeral UI state on the stable chat DOM node;
there is no localStorage, business state, poll, or persistent account preference.
The 80px classification is captured before mutation rather than recomputed after
content growth. The listener on the submitted form survives its replacement long
enough to receive submit-end; Stop and MCP forms have no follow-up marker.

- [ ] **Step 3: Wire actions without replacing existing action owners.** Add `scroll`
to the saved root controllers and append these actions to its current `data-action`:

```text
turbo:before-stream-render@document->scroll#beforeStream
turbo:before-render@document->scroll#capture
turbo:render@document->scroll#afterRender
turbo:submit-start->scroll#submissionStarted
```

In the messages form's existing data hash add `chat_followup: true`, retaining
`chat_account_target`, `generation_busy`, and the account submit guard. Do not add
it to Stop's separate hidden form or a new-chat form.

Remove `data-action="animationend->scroll#scrollToBottom"` from
`messages/_thinking.html.erb`; it bypasses paused intent. No other code calls the
old methods after the Task 2 show-page action removal. Search to verify that fact.

- [ ] **Step 4: Verify desktop, flow mode, reconnect, and reduced motion.**

```bash
record following-green browser_test test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
record following-contracts rails_test test test/controllers/chats_controller_test.rb test/integration/chat_composer_ui_test.rb test/controllers/chat_account_url_race_test.rb
```

The three reader tests above run in desktop, 375×812, and 812×375 modes with the
actual matching scroll surface. Reflow from desktop to narrow while paused; the same visible message must
remain the anchor. Under reduced motion, inspect scroll position over successive
animation frames: there must be no repeated smooth scroll animation. Confirm a
background incoming user message does not count as the current tab's submission.

- [ ] **Step 5: Review and commit.**

```bash
git add app/javascript/controllers/scroll_controller.js app/views/chats/show.html.erb app/views/messages/_form.html.erb app/views/messages/_thinking.html.erb test/system/chat_workspace_test.rb
git commit -m "feat(chats): Preserve reader position during streamed responses"
```

Review gate: observer/listener cleanup, successful-submit discrimination, unchanged
message ordering/targets, morph retention, no incoming focus theft, and one scroll
surface in each responsive mode.

## Task 6: Preserve disclosures and announce meaningful generation changes

**Files:** New `chat_disclosures_controller.js`, `chat_feedback_controller.js`;
saved root/status element; `_thinking.html.erb`, `_thinking_animation.html.erb`;
paired chat-workspace catalogs; system/rendering tests. Do not alter phase broadcasts
or attach a live region to the streamed answer body.

### Task 6 approved review amendment — Keep Turbo

The user explicitly selected **“Keep Turbo (Recommended)”** after the focus-race
investigation. Keep the standard dependency and delivery path; no vendored fork,
dependency change, custom stream receiver, or global focus monkeypatch is authorized.
This amendment qualifies Task 6's focus guarantees and review gate only; it does not
rewrite other tasks or waive their checks.

- Accept only Turbo's outer ID-preservation race: a live replacement can reclaim
  an ID-bearing summary when a deliberate focus move happens in the same frame,
  even if the newly focused control is removed. Characterize that native caller;
  do not present strict race cases as application guarantees or skipped failures.
- Preserve independent open/closed choices and normal lost-summary restoration
  across replacement/morph. The application restorer must not override connected
  intentional focus or another modal, or restore deleted answers, closed dialogs,
  or focus in a different conversation. Keep the ID-less source-link guard tests,
  normal ID-summary retention, async renderer result/rejection/once-only behavior,
  and cleanup/lifecycle coverage.
- Remove `nativeFocusPasses`, revision/frame settling, native-focus suppression,
  intent correction, and all extra RAF/timing gates. Hidden-tab delivery must not
  wait for a frame, including a visible-to-hidden transition; the actual-controller
  frozen-RAF contract remains required. A small ungated wrapper may observe normal
  focus intent and await the original renderer once, without fighting Turbo.
- Retain investigation evidence under `/tmp/opencode/chat-workspace-hqSpCt/`:
  `task6-focus-red.aVSlDD.log` records the original Send/removed-control race;
  `task6-return-red.fkX6Nt.log` records the workaround's stale away-and-back intent;
  `task6-hidden-red.XpyceA.log` records the unaccepted application RAF stall.
  The reproducible hidden contract is `/tmp/opencode/chat-disclosures-hidden-contract.mjs`.
- SPEC must re-evaluate this amended contract before QUALITY. No Task 7/8 work or
  unrestricted/full-suite permission is implied.

- [ ] **Step 1: Add actual browser assertions for replacement and phase updates.**

```ruby
test "live totals replacement and whole-answer update keep details open and focused" do
  visit chat_url(@chat)
  find("#chat-usage-summary").click
  response_summary = "##{dom_id(workspace(:messages, :workspace_answer), :response_summary)}"
  find(response_summary).click
  find(response_summary).send_keys(:tab, [:shift, :tab])
  html = ApplicationController.render(partial: "chats/token_totals", locals: { chat: @chat })
  stream = %(<turbo-stream action="replace" target="#{dom_id(@chat, :token_totals)}"><template>#{html}</template></turbo-stream>)
  page.execute_script("Turbo.renderStreamMessage(arguments[0])", stream)
  assert_selector "#chat-usage-details[open]"
  message = workspace(:messages, :workspace_answer)
  html = ApplicationController.render(partial: "messages/body", locals: { message: message })
  stream = %(<turbo-stream action="update" target="#{dom_id(message, :messages)}"><template>#{html}</template></turbo-stream>)
  page.execute_script("Turbo.renderStreamMessage(arguments[0])", stream)
  assert_selector "##{dom_id(message, :response_details)}[open]"
  assert_selector "#{response_summary}:focus"
  page.execute_script("Turbo.visit(window.location.href,{action:'replace'})")
  assert_selector "#chat-usage-details[open]"
  assert_selector "##{dom_id(message, :response_details)}[open]"
end

test "real preparing phase updates and completion are distinct from streamed tokens" do
  @chat.messages.assistant.delete_all
  @chat.start_generation!
  visit chat_url(@chat)
  assert_selector "#thinking_animation #thinking_animation_content", count: 1
  phase = ApplicationController.render(partial: "messages/thinking_animation", locals: { phase: "searching" })
  stream = %(<turbo-stream action="update" target="thinking_animation_content"><template>#{phase}</template></turbo-stream>)
  page.execute_script("Turbo.renderStreamMessage(arguments[0])", stream)
  assert_selector "[data-chat-feedback-target=status]", text: "Searching", visible: :all
  assert_no_selector ".ai-response-content[aria-live]"
  assert_selector "[role=status][aria-live=polite]", count: 1, visible: :all
  page.execute_script("document.querySelector('[data-generation-busy]').setAttribute('data-generation-busy','false')")
  assert_selector "[data-chat-feedback-target=status]", text: "Response complete.", visible: :all
end
```

```bash
record live-ui-red browser_test test/system/chat_workspace_test.rb
```

Expected: whole-answer replacement closes response details or loses summary focus;
no single stable announcement region exists. Rendering failure is not a valid RED.

- [ ] **Step 2: Add the disclosure owner.**

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.states = this.element.chatDetailStates ||= new Map()
    this.observer = new MutationObserver(() => this.restore())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.restore()
  }

  disconnect() {
    this.observer.disconnect()
  }

  remember(event) {
    if (event.target.matches("details[data-chat-detail][id]")) this.states.set(event.target.id, event.target.open)
  }

  preserveAttribute(event) {
    if (!this.element.contains(event.target)) return
    if (event.detail.attributeName !== "open") return
    if (event.target.matches("details[data-chat-detail][id]") && this.states.has(event.target.id)) event.preventDefault()
    if (event.target.matches("dialog.n-chat-dialog[open]")) event.preventDefault()
  }

  captureFocus(event) {
    const active = document.activeElement
    if (!this.element.contains(active)) return
    const target = event?.type === "turbo:before-stream-render" ? document.getElementById(event.target.getAttribute("target")) : this.element
    if (!target?.contains(active)) return
    const detail = active.closest("details[data-chat-detail]")
    if (detail) this.focusId = active.id || detail.querySelector("summary[id]")?.id
  }

  restore() {
    this.element.querySelectorAll("details[data-chat-detail][id]").forEach(detail => {
      if (this.states.has(detail.id)) detail.open = this.states.get(detail.id)
      else this.states.set(detail.id, detail.open)
    })
    if (this.focusId && (!document.activeElement || document.activeElement === document.body)) document.getElementById(this.focusId)?.focus({ preventScroll: true })
    this.focusId = null
  }
}
```

Attach `chat-disclosures` to the saved root. Append these actions, using capture
for the non-bubbling details toggle event:

```text
toggle->chat-disclosures#remember:capture
turbo:before-morph-attribute@document->chat-disclosures#preserveAttribute
turbo:before-stream-render@document->chat-disclosures#captureFocus
turbo:before-render@document->chat-disclosures#captureFocus
turbo:render@document->chat-disclosures#restore
```

Disclosure state lives on this chat's DOM node, not in browser storage. Native
dialog `open` remains stable on a same-page morph but closes before navigation
caching through the separate dialog owner. Changes must not preserve a deleted
conversation or restore focus into a dialog that is no longer open.

- [ ] **Step 3: Add a restrained phase fragment and stable announcement owner.**

Complete `_thinking_animation.html.erb`:

```erb
<% phase = "thinking" unless %w[preparing indexing searching retrieving generating using_tool thinking].include?(phase) %>
<div class="n-chat-phase" data-phase="<%= phase %>">
  <span class="n-chat-phase-indicator" aria-hidden="true"></span>
  <div>
    <p class="n-chat-phase-title"><%= t("nosia.chat.phases.#{phase}.title") %></p>
    <p class="n-workspace-help"><%= t("nosia.chat.phases.#{phase}.subtitle") %></p>
  </div>
</div>
```

Complete `_thinking.html.erb`:

```erb
<div id="thinking_animation" class="n-chat-message">
  <p class="n-chat-assistant-name"><%= t("nosia.chat.assistant") %></p>
  <div id="thinking_animation_content" class="n-chat-assistant-body">
    <%= render "messages/thinking_animation", phase: "preparing" %>
  </div>
</div>
```

Add these scoped styles:

```css
.n-chat-workspace .n-chat-phase { display:flex; align-items:flex-start; gap:.75rem; }
.n-chat-workspace .n-chat-phase-title { font-size:.875rem; font-weight:600; }
.n-chat-workspace .n-chat-phase-indicator { @apply bg-green-700 dark:bg-green-300; width:.5rem; height:.5rem; border-radius:50%; margin-top:.5rem; flex:none; }
.n-chat-workspace #thinking_animation { animation:none; transition:none; }
```

Do not rename `thinking_animation` or `thinking_animation_content`: existing
created/phase/finish broadcasts target them. The dot is decorative; text alone
communicates state. No synthetic percentage, elapsed timer, or typewriter delay.

Create `chat_feedback_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { completed: String, stopped: String }

  connect() {
    this.generating = this.busy
    this.observer = new MutationObserver(() => this.update())
    this.observer.observe(this.element, { childList: true, subtree: true, attributes: true, attributeFilter: ["data-generation-busy", "data-chat-generation-stopped"] })
    this.update()
  }

  disconnect() {
    this.observer.disconnect()
  }

  get busy() {
    return Boolean(this.element.querySelector('[data-generation-busy="true"]'))
  }

  update() {
    const busy = this.busy
    if (this.generating && !busy) {
      this.statusTarget.textContent = this.element.dataset.chatGenerationStopped === "true" ? this.stoppedValue : this.completedValue
      this.phase = null
    } else if (busy) {
      const phase = [...this.element.querySelectorAll(".n-chat-phase[data-phase]")].at(-1)
      if (phase && phase.dataset.phase !== this.phase) {
        this.phase = phase.dataset.phase
        this.statusTarget.textContent = phase.querySelector(".n-chat-phase-title").textContent
      }
    }
    this.generating = busy
  }
}
```

Add `chat-feedback` to the saved root, plus
`data-chat-feedback-completed-value="<%= t('nosia.chat_workspace.completed') %>"`,
`data-chat-feedback-stopped-value="<%= t('nosia.chat_workspace.stopped') %>"`, and
`data-chat-generation-stopped="<%= @chat.generation_stopped? %>"`. Add this stable
child outside the changing message target:

```erb
<p class="sr-only" role="status" aria-live="polite" aria-atomic="true" data-chat-feedback-target="status"></p>
```

Add `stopped: "Generation stopped."` to the English workspace catalog and
`stopped: "Génération arrêtée."` to French. Do not assert that a partial answer
exists in this announcement. Stop's existing transcript makes any retained
partial answer visible without a new state flag.

- [ ] **Step 4: Verify real stream envelopes and end-to-end recovery.**

```bash
record live-ui-green browser_test test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb
record live-contracts rails_test test test/controllers/chats_controller_test.rb test/integration/chat_composer_ui_test.rb test/integration/chat_message_rendering_test.rb test/controllers/chat_account_citations_test.rb test/internationalization/catalogs_test.rb
```

Additionally capture localized broadcasts using `Turbo::Broadcastable::TestHelper`
as in `ChatComposerUiTest:82-96`: actual token-total replacement must land inside
the stable usage disclosure; background unlock must leave Send enabled. Do not
replace a real broadcast assertion with a manual `visit` and call it delivery.

- [ ] **Step 5: Review and commit.**

```bash
git add app/javascript/controllers/chat_disclosures_controller.js app/javascript/controllers/chat_feedback_controller.js app/views/chats/show.html.erb app/views/messages/_thinking.html.erb app/views/messages/_thinking_animation.html.erb app/assets/stylesheets/nosia/chat_workspace.css config/locales/en.nosia_chat_workspace.yml config/locales/fr.nosia_chat_workspace.yml test/system/chat_workspace_test.rb
git commit -m "feat(chats): Preserve live detail state and accessible phase feedback"
```

Review gate: no character-by-character live region, no observer recursion,
cross-page morph interception, focus theft, or changed broadcast/backend contract.

## Task 7: Complete responsive, citation, and real-broadcast evidence

**Files:** New `test/support/chat_workspace_browser_checks.rb`; extend request,
rendering, and system tests; only browser-proven corrections to the chat-scoped
styles/controllers/partials already named. Do not claim the old waiting scaffold
as completed coverage and do not rewrite unrelated test infrastructure.

- [ ] **Step 1: Add concrete citation and actual broadcast assertions.** Add to
`ChatMessageRenderingTest`, retaining Task 1's
`require "turbo/broadcastable/test_helper"` and
`include Turbo::Broadcastable::TestHelper`, then these tests:

```ruby
test "sources retain account scoped evidence links beside separate reasoning" do
  width = Chunk.columns_hash.fetch("embedding").limit
  vector = [1.0] + Array.new(width - 1, 0.0)
  local = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", vector)
  foreign = insert_picker_chunk(@first, texts(:picker_first_text), "Foreign evidence", vector)
  message = workspace(:messages, :workspace_answer)
  message.update_columns(similar_chunk_ids: [local.id.to_s, foreign.id.to_s])
  fragment = Nokogiri::HTML.fragment(ApplicationController.render(partial: "messages/message", locals: { message: message.reload }))
  assert_select fragment, "details[data-chat-detail] a[href='#{chunk_path(local, chat_id: @chat.id)}']", count: 1
  assert_select fragment, "a[href='#{chunk_path(foreign, chat_id: @chat.id)}']", count: 0
  assert_select fragment, "##{dom_id(message, :reasoning_details)}", count: 1
  assert_select fragment, "##{dom_id(message, :sources)}", count: 1
end

test "actual usage broadcasts preserve a single complete replace target" do
  streams = capture_turbo_stream_broadcasts([@chat, :token_totals, :en]) do
    TokenUsage.create!(account_id: @second.id, chat_id: @chat.id, kind: :completion,
      model_id: "picker-test-model", input_tokens: 2, output_tokens: 3)
  end
  replacement = streams.find { |stream| stream["target"] == dom_id(@chat, :token_totals) }
  assert replacement
  assert_equal "replace", replacement["action"]
  fragment = Nokogiri::HTML.fragment(replacement.inner_html)
  assert_select fragment, "##{dom_id(@chat, :token_totals)}", count: 1
  assert_select fragment, "[data-chat-total-input]", text: "127"
  assert_select fragment, "[data-chat-total-output]", text: "27"
  assert_select fragment, "details", count: 0
end
```

These preserve existing citation/privacy and broadcast expectations, so run them
at their relevant earlier task before implementation as well. A failure exposing
an existing accounting or callback problem is a blocker to discuss, not permission
to repair the usage subsystem as a presentation change.

- [ ] **Step 2: Add explicit browser measurement helpers.** Complete
`test/support/chat_workspace_browser_checks.rb`:

```ruby
module ChatWorkspaceBrowserChecks
  def chat_viewport(width, height)
    page.current_window.resize_to(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
    assert_equal [width, height], page.evaluate_script("[innerWidth,innerHeight]")
  end

  def chat_theme(dark)
    current = page.evaluate_script("document.documentElement.classList.contains('dark')")
    find("#theme-toggle").click if current != dark
    assert_equal dark, page.evaluate_script("document.documentElement.classList.contains('dark')")
  end

  def assert_chat_bounds
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth"), "Page-wide horizontal overflow"
    [".n-composer-surface", ".n-composer-account", ".n-composer-send"].each do |selector|
      next unless page.has_selector?(selector)
      box = find(selector).native.rect
      assert_operator box.x, :>=, 0
      assert_operator box.x + box.width, :<=, page.evaluate_script("innerWidth") + 1
    end
  end

  def chat_contrast(selector, minimum: 4.5, outline: false)
    node = find(selector, match: :first)
    node.scroll_to(:center)
    result = page.evaluate_script(<<~JS, node, outline)
      ((e,outline)=>{
        const canvas=document.createElement('canvas');canvas.width=canvas.height=1;
        const c=canvas.getContext('2d',{willReadFrequently:true});
        const rgba=color=>{c.clearRect(0,0,1,1);c.fillStyle=color;c.fillRect(0,0,1,1);const p=Array.from(c.getImageData(0,0,1,1).data);p[3]/=255;return p;};
        const blend=(a,b)=>a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));
        const parents=[];for(let a=outline?e.parentElement:e;a;a=a.parentElement)parents.unshift(a);
        const bg=parents.reduce((b,a)=>{const s=getComputedStyle(a);if(s.opacity!=='1'||s.backgroundImage!=='none')throw new Error('Unmeasured opacity/gradient');return blend(rgba(s.backgroundColor),b);},[255,255,255]);
        const style=getComputedStyle(e),fg=blend(rgba(outline?style.outlineColor:style.color),bg);
        const luminance=rgb=>rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((s,v,i)=>s+v*[.2126,.7152,.0722][i],0);
        const a=luminance(fg),b=luminance(bg),r=e.getBoundingClientRect();
        const x=Math.max(0,Math.min(innerWidth-1,r.left+r.width/2)),y=Math.max(0,Math.min(innerHeight-1,r.top+r.height/2));
        const hit=document.elementFromPoint(x,y);
        return {ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05),visible:!!hit&&(hit===e||e.contains(hit)),outline:parseFloat(style.outlineWidth)};
      })(arguments[0],arguments[1])
    JS
    assert result.fetch("visible"), "Contrast sample is covered: #{selector}"
    assert_operator result.fetch("ratio"), :>=, minimum, selector
    assert_operator result.fetch("outline"), :>=, 2 if outline
    dir = ENV.fetch("EVIDENCE")
    File.open(File.join(dir, "chat-contrast.jsonl"), "a") { |file| file.puts({ selector: selector, minimum: minimum, result: result }.to_json) }
  end
end
```

The helper uses Selenium's native element rectangle and deliberately
rejects gradients/opacity it cannot measure correctly. Native dialog backdrop
composition needs a separate sample or manual check, not a falsely passing ratio.

- [ ] **Step 3: Add a real visual/keyboard matrix test.** Require/include that helper
in the existing system test and append:

```ruby
test "localized chat surfaces reflow in both themes with measured visible controls" do
  @second.update_columns(name: "CompteDeRecherche" * 12)
  message = workspace(:messages, :workspace_answer)
  message.update_columns(content: message.content + "\n\n```ruby\n" + "long_code_identifier_" * 30 + "\n```\n")
  ["EN", "FR"].each do |language|
    visit new_chat_url(account_id: @second.id)
    select language, from: "language_preference_locale"
    assert_selector "html[lang='#{language.downcase}']"
    [[375,812], [768,1024], [1400,1000], [812,375]].each do |width, height|
      chat_viewport(width, height)
      [false, true].each do |dark|
        [new_chat_url(account_id: @second.id), chat_url(@chat)].each_with_index do |url, index|
          visit url
          assert_selector "lexxy-editor[connected]"
          chat_theme(dark)
          assert_chat_bounds
          chat_contrast(".n-chat-title")
          find("button[aria-controls=chat-history]").send_keys(:tab, [:shift, :tab])
          chat_contrast("button[aria-controls=chat-history]:focus", minimum: 3, outline: true)
          find("button[aria-controls=chat-history]").click
          assert_selector "#chat-history[open]"
          within("#chat-history") { first("button", text: I18n.t("nosia.chat_workspace.close", locale: language.downcase)).click }
          find(".n-composer-send").send_keys(:tab, [:shift, :tab])
          assert_selector ".n-composer-send:focus"
          assert_chat_bounds
          page.save_screenshot(File.join(ENV.fetch("EVIDENCE"), "chat-#{language}-#{width}x#{height}-#{dark ? 'dark' : 'light'}-#{index}.png"))
        end
      end
    end
  end
end
```

Add this stateful test for visible message/detail/help samples and keyboard
reachability. It supplements, rather than replaces, the matrix above:

```ruby
test "wide evidence details errors and reduced-motion controls remain readable" do
  width = Chunk.columns_hash.fetch("embedding").limit
  chunk = insert_picker_chunk(@second, texts(:picker_second_text), "Research evidence", [1.0] + Array.new(width - 1, 0.0))
  message = workspace(:messages, :workspace_answer)
  columns = (1..24).map { |index| "Metric #{index}" }
  table = "\n\n| " + columns.join(" | ") + " |\n| " + Array.new(24, "---").join(" | ") + " |\n| " + Array.new(24, "42").join(" | ") + " |\n"
  message.update_columns(similar_chunk_ids: [chunk.id.to_s], content: message.content + table)
  chat_viewport(375, 812)
  page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [{name: "prefers-reduced-motion", value: "reduce"}])
  [false, true].each do |dark|
    visit chat_url(@chat)
    chat_theme(dark)
    chat_contrast(".n-chat-user-body")
    chat_contrast(".n-chat-assistant-name")
    chat_contrast(".ai-response-content h2")
    find("##{dom_id(message, :sources_summary)}").click
    chat_contrast(".n-chat-source")
    find("##{dom_id(message, :response_summary)}").click
    chat_contrast("[data-response-details] .n-workspace-help")
    find("#chat-usage-summary").click
    chat_contrast("[data-chat-total-input]")
    chat_contrast(".n-composer-meta")
    find(".n-composer-send").send_keys(:tab, [:shift, :tab])
    assert page.evaluate_script(<<~JS)
      (()=>{const e=document.activeElement,r=e.getBoundingClientRect();const hit=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);return e.matches('.n-composer-send')&&r.top>=0&&r.bottom<=innerHeight&&!!hit&&(hit===e||e.contains(hit));})()
    JS
    assert_chat_bounds
    assert_selector ".table-wrapper"
    page.execute_script("document.querySelector('.table-wrapper').scrollLeft=1000")
    assert page.evaluate_script("document.querySelector('.table-wrapper').scrollLeft>0")
    page.save_screenshot(File.join(ENV.fetch("EVIDENCE"), "chat-details-#{dark ? 'dark' : 'light'}.png"))
  end
  message.metadata["original_question"] = "Retry this question"
  html = with_singleton_replacement(message, :error?, -> { true }) do
    with_singleton_replacement(message, :retryable?, -> { true }) do
      ApplicationController.render(partial: "messages/body", locals: { message: message })
    end
  end
  stream = %(<turbo-stream action="update" target="#{dom_id(message, :messages)}"><template>#{html}</template></turbo-stream>)
  page.execute_script("Turbo.renderStreamMessage(arguments[0])", stream)
  assert_selector "[role=alert] button", text: "Retry"
  [false, true].each do |dark|
    chat_theme(dark)
    chat_contrast("[role=alert] .ai-response-content h2")
    page.save_screenshot(File.join(ENV.fetch("EVIDENCE"), "chat-error-#{dark ? 'dark' : 'light'}.png"))
  end
  assert_enqueued_jobs 1, only: ChatResponseJob do
    click_button "Retry"
    assert_selector "[data-generation-busy=true]"
  end
end
```

Use the same known error extension hook as the rendering test; do not claim a new
provider error protocol. Measure meaningful control borders against adjacent
surfaces as an additional manual/DevTools sample. Do not label screenshots or
geometry checks as native zoom or screen-reader testing.

- [ ] **Step 4: Run the visual tests before any corrective CSS.**

```bash
record responsive-red browser_test test/system/chat_workspace_test.rb
```

This may already pass if earlier styling is correct. In that case record PASS,
inspect screenshots, and make no fabricated visual fix. If a planned layout
requirement fails, preserve the failing test/log, change only its scoped styles,
and rerun to green. Include `.table-wrapper` in the existing local overflow rule:

```css
.n-chat-workspace :is(pre,.table-wrapper,.n-chat-table-scroll) { max-width:100%; overflow-x:auto; }
```

Add a wide markdown table sample and physically scroll its wrapper horizontally;
the page itself must retain its width. Inspect History, Tools, long account names,
source error lists and Retry in both themes at short/narrow viewports. Verify
keyboard focus with viewport bounds and hit testing, not outline color alone.

- [ ] **Step 5: Exercise actual lifecycle seams without a live provider.**

```bash
record final-build rails_test tailwindcss:build
record final-focused rails_test test test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb test/controllers/chat_account_url_race_test.rb test/controllers/chat_sources_controller_test.rb test/models/chat_test.rb test/models/dashboard_recents_test.rb test/internationalization/catalogs_test.rb
record final-chat-browser browser_test test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
record final-workspace-browser browser_test test/system/dashboard_test.rb test/system/accounts_settings_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb
# Full suite remains UNVERIFIED under the explicitly accepted Task 0 exception;
# do not invoke the network-capable unrestricted suite for this UI task.
git diff --name-only --diff-filter=ACMR "$BASE" -- '*.rb' > "$EVIDENCE/changed-ruby-files.txt"
record final-lint mise exec ruby@4.0.7 -- bundle exec ruby -e 'files=File.readlines(ARGV.fetch(0), chomp:true); abort "No Ruby changes found" if files.empty?; exec "bundle", "exec", "rubocop", *files' "$EVIDENCE/changed-ruby-files.txt"
record final-security mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

For changed Ruby files, pass the exact changed file list to RuboCop (never run its
auto-fix on unrelated files). Compare scanner fingerprints and full-suite failures
to Task 0's actual base. A timeout is unverified, not a pass. Run database-sharing
commands one at a time; no concurrent browser/test processes.

Required explicit checks: preparing → phase update → blank assistant target →
formatted streamed markdown → final update → composer unlock; Stop retains existing
partial content; native PDF chooser/file bytes; account-switch confirmation/source
reset; pending/failed sources block Send; `/skill` and Enter/Shift+Enter; Tools
Add/Remove; history privacy/delete; paused reader across updates and refresh;
disclosure focus/open state; no duplicate DOM targets or message creation.

These checks use deterministic fixtures and existing stream/job test doubles.
Do not enable live workers to fill a coverage gap. Mark any missing assertion as
unverified until a real test or documented manual check establishes it.

- [ ] **Step 6: Review and commit the verified test/visual corrections.**

```bash
git diff --check
git add test/support/chat_workspace_browser_checks.rb test/system/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb app/assets/stylesheets/nosia/chat_workspace.css
git commit -m "test(chats): Verify responsive private and live conversation flows"
```

Review gate: inspect the actual screenshots/contrast rows and logs. Do not accept a
green scaffold, skipped workflow, manually reloaded screenshot, or source-only
assertion as proof of keyboard/streaming behavior.

## Task 8: Document behavior, review fidelity, and hand off verification

**Files:** New `docs/chat-workspace.md`; update `docs/README.md` and
`docs/chat-composer.md`; plan execution checkboxes/evidence records. No app changes
unless a new failing test has first established a scoped defect.

- [ ] **Step 1: Add the user-facing guide with these contents.**

```markdown
# Chat workspace

`/chats/new` opens a focused starting page. `/chats/:id` opens a saved conversation
with its existing account, transcript, and shared composer. The dashboard's own
composer and workspace navigation keep their existing behavior.

## History and accounts

History opens on demand on desktop and mobile. It shows only your root
conversations in accounts you can currently access, with account and activity
context. Escape or Close dismisses it and restores focus. Conversation deletion
still asks for confirmation and uses the existing redirect.

New-chat account selection remains membership-only and follows the existing
default/explicit-account behavior. Saved conversations cannot change accounts.
No new persistent account preference or conversation naming feature is added.

## Reading and details

Responses follow while you stay within 80 CSS pixels of the bottom. Scroll up to
pause following. New content then exposes Latest message; activate it or return
to the bottom to resume. A successful follow-up also resumes following; incoming
responses do not take keyboard focus. A same-page Turbo recovery keeps reading
intent, while a full browser reload may start at the latest message.

Sources and Reasoning remain independent disclosures. Response details contains
the existing finalized response usage. Usage details contains the conversation's
existing input/output totals, usage-kind breakdown, and environmental estimates.
Labels and caveats changed, not calculations or authorization.

## Composer and generation

The existing PDF, formatting, account, sources, skills, Tools, Enter/Shift+Enter,
Send, and Stop behavior remains in the shared composer. Upload/source errors stay
visible and block sending where required. History and details do not replace or
reset your editor. Saved Tools uses an accessible modal with the same operations.

Generation remains incremental and shows named preparation/search/tool phases.
Assistive announcements identify phase changes and completion, not every token.
Stop preserves any existing partial answer; eligible Retry remains visible outside
collapsed metadata. There is no new provider, cancellation, retry, or polling API.

## Verification

Use the dedicated test environment and commands in
`superpowers/plans/2026-10-28-chat-workspace-ui-ux.md`. Run suites sequentially,
without live providers or workers. Record actual command exits, screenshots,
contrast samples, baseline differences, and unavailable manual checks.

Narrow and short layouts use the page as their sole scroll surface; desktop uses
the transcript. Code/tables can scroll locally. Both themes and English/French
must be checked. Native 200% browser zoom and screen-reader behavior require
separate checks; viewport/device scaling is not proof of either.
```

- [ ] **Step 2: Link the guide and explain the styling boundary.** Add this docs-index
entry adjacent to the existing composer guide:

```markdown
- [Chat workspace](chat-workspace.md) — focused new/saved conversations, private history, reader-aware following, and live details.
```

Append to `docs/chat-composer.md`:

```markdown
## Dedicated chat-page shell

New and saved chat pages use the [focused chat workspace](chat-workspace.md).
Its unlayered `nosia/chat_workspace.css` import is scoped to chat-page classes;
the dashboard's shared composer keeps its existing sizing and safeguards.
The saved Tools trigger delegates to the page-local native dialog owner; its
server operations and background-renderable composer locals are unchanged.
```

- [ ] **Step 3: Self-review spec fidelity and YARD.** Check every Decisions entry and
the coverage table below against the final diff. The only new public application
Ruby interface is `ChatWorkspacesHelper`; its methods have YARD return/parameter
tags in Task 2. Document any additional public Ruby method if implementation adds
one. Reject unrelated services, queries, policies, schemas, routes, dependencies,
or generation/accounting changes.

- [ ] **Step 4: Verify documentation and report exact evidence.**

```bash
git diff --check
git diff --stat "$BASE"
git status --short
```

In the execution handoff, list actual helper/evidence locations, each command and
exit/counts, screenshot states inspected, contrast results, baseline failures,
and manual native-zoom/screen-reader limitations. Do not replace the guide with a
claim that all tests passed if any suite failed, timed out, skipped its workflow,
or was not run. No invented counts or prefilled success records belong here.

- [ ] **Step 5: Commit only the guide/index/composer documentation.**

```bash
git add docs/chat-workspace.md docs/README.md docs/chat-composer.md
git commit -m "docs(chats): Explain focused conversation behavior and verification"
```

Final review: requirements/privacy, Rails/Hotwire quality, security of rendered
content/params, accessibility evidence, and protected dashboard/composer regressions.
Only then offer branch integration choices; no automatic merge, push, PR, cleanup,
or deletion of another worktree.

## Spec-to-task coverage and plan review

| Approved requirement | Implementing/verifying tasks |
| --- | --- |
| Focused A direction; dashboard-neutral/green; no new capabilities | 2, 4, 7, 8 |
| Centered new chat; saved title/account; existing default behavior | 2, 7 |
| Private on-demand history; current-membership exclusion; existing deletion | 2, 3, 7 |
| Stable editor, fixed saved account, PDF/sources/skills/Tools safeguards | 2, 3, 5, 7 |
| Reader-aware following, 80px boundary, successful own submission, Latest message | 5, 7 |
| Paused position and focus across streaming/reconnect/morph | 5, 6, 7 |
| Independent citations/reasoning/response/usage disclosures; unchanged estimates | 4, 6, 7 |
| Preserved message IDs, ordering container, blank reconstruction, localized streams | 1, 2, 4, 6, 7 |
| Phase feedback, reduced motion, visible Stop/Retry/errors and no-account setup | 2, 3, 4, 6, 7 |
| Modal keyboard containment, Escape, return focus, no stacked dialogs | 3, 6, 7 |
| Both themes, EN/FR, long content, narrow/short layouts, contrast/focus | 2, 4, 7 |
| Isolated test-first execution, fresh baselines, truthful verification and docs | 0, all task RED/GREEN steps, 7, 8 |

Before execution, self-review the plan's interfaces: every `data-action` resolves
to its named controller method, targets occur once, catalog keys are paired,
fixtures resolve across fixture sets, and scroll CSS breakpoints exactly match
the controller's surface selection. Run a placeholder scan and correct any gap
inline. This plan is proposed implementation detail, not executed test evidence.

## Planning validation record

- Checked the plan against every approved design section and Decisions entry;
  the coverage table maps each requirement to an execution/verification task.
- Verified standalone Ruby and JavaScript documentation examples parse, and
  compiled Rails ERB examples without executing them. This checks documentation
  syntax only, not application correctness or browser behavior.
- Reviewed fixture replacement semantics, stream action/target/payload boundaries,
  paired localization, controller/action/target names, and matching scroll/layout
  breakpoints. Removed ambiguous recovery copy and incomplete template blocks.
- No application implementation, database provisioning, asset build, or runtime
  test suite has run during planning. Task 0 remains an explicit prerequisite.
