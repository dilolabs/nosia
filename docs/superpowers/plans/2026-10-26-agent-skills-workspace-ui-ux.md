# Agent Skills Workspace UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the management-first Skills workspace on legacy and explicit account routes while preserving authored content, parser/runtime behavior, permissions and API compatibility.

**Architecture:** Keep thin Rails CRUD controllers and share authorized request-local account scoping. Add explicit RESTful enablement actions plus the legacy toggle adapter; render structured rows, full details and a native textarea form using small partials and scoped styles. Use Turbo for submissions and small generic Stimulus controllers for HTML form responses and linked-error focus, not client-side state or a new editor.

**Tech Stack:** Actual checkout: Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL/pgvector, Minitest/fixtures, Turbo 8, Stimulus 3.2, Importmap, Propshaft and Tailwind 4.1. Do not upgrade dependencies or substitute the generic AGENTS.md runtime description.

---

## Authority and execution boundary

- [Approved Skills specification](../specs/2026-10-26-agent-skills-workspace-ui-ux-design.md), reviewed at `ea1564da5a22ba83126abc481efa353d3d6aa807`; user answered **“Go”** to written-spec review. The [shared foundation](../specs/2026-10-24-workspace-tools-ui-ux-design.md) applies.
- Only Skills is planned. MCP retains its independent design/spec/plan cycle. No parser changes, execution tests in the UI, new search/filter/bulk/pagination/history features, tables, jobs, providers, dependencies or account preferences.
- This plan was prepared on `docs/agent-skills-workspace-design`, based on application revision `6cd1dd03b78a6723a8c31e947f381bda9bf5af1d`. No application execution has started. The execution method has not been selected.
- At planning time, committed main had no diff from that base in Skills controller/model/parser/views, routes or application layout. Main advanced independently; do not merge/reset/rebase it or other worktrees. Recheck contracts against the chosen execution base in Task 0. No push, PR, merge into main or worktree removal is authorized.
- Run database-sharing commands sequentially, never parallel implementers against this worktree/database. Preserve real exits and failed attempts. Earlier Token usage test/security acceptances are not Skills waivers.

## File responsibilities before task decomposition

| Unit | Files | Responsibility |
| --- | --- | --- |
| Account authority | `app/controllers/concerns/agent_skill_scoped.rb` | Path/default account resolution, bounded tenant context, association-scoped record lookup |
| Browser CRUD | `app/controllers/agent_skills_controller.rb` | Existing CRUD, contextual redirects, retained failed-form input |
| State HTTP resources | `app/controllers/agent_skills/enablements_controller.rb`, `app/controllers/agent_skills/toggles_controller.rb`; `config/routes.rb` | Explicit enable/disable; compatibility PATCH toggle |
| Paths/presentation | `app/helpers/agent_skills_workspace_helper.rb` | Route-family helpers, trail/scope, input/error mapping; no parsing or queries |
| Workspace views | `app/views/agent_skills/{index,show,new,edit,setup}.html.erb`; `_header`, `_feedback`, `_row`, `_state_action`, `_settings`, `_form`, `_form_errors`, `_field_error` partials | Explicit-local presentation and complete native form |
| Scoped shared integration | `app/views/layouts/application.html.erb`, `app/views/application/_menu.html.erb`, `app/views/accounts/_configuration.html.erb` | Skills-only drawer/flash/breadcrumb changes and account entry; retain other pages |
| Styles/catalogs | `app/assets/stylesheets/nosia/skills_workspace.css`, `app/assets/tailwind/application.css`, `config/locales/{en,fr}.nosia_skills_workspace.yml` | Responsive theme-safe presentation and complete EN/FR wrappers |
| Generic enhancement | `app/javascript/controllers/html_form_controller.js`, `form_errors_controller.js` | Declare HTML response negotiation on owned forms; reveal/focus linked errors |
| Fixtures/contract tests | `test/support/agent_skills_workspace_fixtures.rb`, `test/support/fixtures/agent_skills_workspace/{agent_skills,agent_skill_executions}.yml`, `test/models/agent_skill_presentation_contract_test.rb` | Reusable existing account fixtures plus parser/runtime characterization |
| Request tests | `test/controllers/agent_skills_workspace_{scoping,states,shell,content,forms}_test.rb`, `test/integration/agent_skills_api_compatibility_test.rb`, existing `test/integration/localized_pages_test.rb` | All HTTP/context/content/form/legacy contracts |
| Browser checks | `test/system/agent_skills_workspace_test.rb` | Real user flows, keyboard/error behavior, themes/locales/reflow and evidence |
| Documentation | `docs/agent-skills-workspace.md`, `docs/README.md`, `docs/DIAGRAMS.md` | Delivered behavior, parser limits and verification status |

The `_skill_card.html.erb` partial has one caller in the current Skills index.
Replace it with `_row.html.erb` only after confirming that caller inventory; do not
delete unrelated/unfamiliar files. Existing model/parser/API implementation files
are protected: add characterization/regression tests, not behavioral rewrites.

## Task 0: Isolated execution checkout and fresh baseline

**Files:** no tracked application changes. External runner:
`/tmp/opencode/agent-skills-workspace-check.py`. Execution worktree:
`/home/cbldev/gitd/dilolabs/nosia/.worktrees/agent-skills-workspace-ui`.

- [ ] **Step 1: Confirm execution consent, isolate the implementation branch, and record its immutable base.** Use using-git-worktrees. Verify the existing `.worktrees` directory is ignored and the destination/branch are unused before creation. Start from the committed plan, not an independently moving main. Do not reuse a dirty worktree.

```bash
git status --short --branch
git -C /home/cbldev/gitd/dilolabs/nosia check-ignore .worktrees/agent-skills-workspace-ui
git branch --list feat/agent-skills-workspace-ui
git worktree add -b feat/agent-skills-workspace-ui /home/cbldev/gitd/dilolabs/nosia/.worktrees/agent-skills-workspace-ui HEAD
git -C /home/cbldev/gitd/dilolabs/nosia/.worktrees/agent-skills-workspace-ui rev-parse HEAD
```

The `-C` ignore check only reads the main directory; create the new worktree from
the documentation checkout's committed plan HEAD, not main's HEAD. Run subsequent commands from the new worktree; move the session
there if it becomes primary. Record the SHA and current protected refs in external
execution notes. Inspect `git diff --name-only` against the approved application
base for the protected Skills contracts; stop if they differ materially.

- [ ] **Step 2: Check prerequisites without installing or changing them.**

```bash
mise exec ruby@4.0.7 -- ruby --version
mise exec ruby@4.0.7 -- bundle check
chromium --version
chromedriver --version
pg_isready -h /var/run/postgresql
df -h . /tmp/opencode
```

Expected: installed Ruby 4.0.7, satisfied bundle, compatible local Chromium /
ChromeDriver and the local PostgreSQL socket. If a prerequisite, local socket or disk headroom is missing, stop and ask; do not
install packages or clean other worktrees. Configuration may be loaded nondisplaying
from the existing main checkout `.env`; never read/copy/log its contents. The
sentinel environment below must override actual provider credentials for tests.

- [ ] **Step 3: Create this external append-only-per-run recorder with the patch tool.** It is execution support, not application code. It refuses existing log paths and records actual child exits. Each command gets a fresh filename; an interrupted run without a trailer has UNKNOWN exit.

```python
import json
import os
from pathlib import Path
import subprocess
import sys

log_path = Path(sys.argv[1])
mode, *args = sys.argv[2:]
root = Path.cwd()
branch = subprocess.check_output(["git", "branch", "--show-current"], text=True).strip()
if branch != "feat/agent-skills-workspace-ui":
    sys.exit("Refusing a non-feature checkout")
env = os.environ.copy()
env.update(RAILS_ENV="test", DATABASE_URL="postgresql:///nosia_agent_skills_workspace_test",
           DB_HOST="/var/run/postgresql", PGHOST="/var/run/postgresql",
           AI_API_KEY="nosia-test-key", PARALLEL_WORKERS="1")
prefix = ["mise", "exec", "ruby@4.0.7", "--", "bundle", "exec", "dotenv", "-f",
          str(root.parents[1] / ".env"), "--"]
commands = {
    "rails": ["bin/rails"],
    "ruby": ["bundle", "exec", "ruby"],
    "lint": ["bin/rubocop"],
    "scan": ["bin/brakeman"],
    "browser": ["bundle", "exec", "ruby", "-rselenium-webdriver", "-e",
        'ENV.delete("CAPYBARA_SERVER_PORT"); '
        'Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; '
        'Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"',
        "--", "test"]
}
command = prefix + commands[mode] + args
code = None
try:
    with log_path.open("x") as log:
        log.write(json.dumps({"cwd": str(root), "command": command,
            "base": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()}) + "\n")
        log.flush()
        code = subprocess.run(command, cwd=root, env=env, stdout=log,
                              stderr=subprocess.STDOUT).returncode
        log.write("\nCOMMAND_EXIT=" + str(code) + "\n")
        log.flush()
except FileExistsError:
    sys.exit(2)
except Exception as error:
    print(f"Recorder failure; child exit={code!r}; {error}", file=sys.stderr)
    sys.exit(125)
print(f"{log_path}: child exit {code}")
sys.exit(code)
```

- [ ] **Step 4: Validate the dedicated test environment, then prepare only its database.** Run each command separately, sequentially. Do not execute `db:reset`, load development fixtures or start workers/providers. A preparation failure blocks baseline work.

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-env.log ruby -e 'abort "Unsafe test environment" unless ENV.values_at("RAILS_ENV", "DATABASE_URL", "DB_HOST", "PGHOST", "AI_API_KEY", "PARALLEL_WORKERS") == ["test", "postgresql:///nosia_agent_skills_workspace_test", "/var/run/postgresql", "/var/run/postgresql", "nosia-test-key", "1"]; puts "Dedicated local test environment verified"'
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-db-create.log rails db:create
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-db-guard.log rails runner 'abort "Wrong database" unless Rails.env.test? && ActiveRecord::Base.connection.select_value("SELECT current_database()") == "nosia_agent_skills_workspace_test" && ActiveRecord::Base.connection.select_value("SELECT inet_server_addr()").nil?; puts "Dedicated local-socket test database verified"'
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-db-prepare.log rails db:test:prepare
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-build.log rails tailwindcss:build
```

- [ ] **Step 5: Run fresh focused, full, browser and scanner baselines sequentially.** Use shell timeout 0 for long foreground suites, or genuine background tool execution with completion notifications; never let the harness default timeout manufacture a result. Read complete logs after completion, not just the runner's path/exit announcement.

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-focused.log rails test test/models/agent_skill_test.rb test/integration/localized_pages_test.rb test/controllers/account_experience_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/internationalization/catalogs_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-full.log rails test
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-browser.log browser test/system
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-baseline-security.log scan --no-pager
```

Expected: successful focused/browser/build runs; inspect full/security results
without assuming historical failures remain. Stop before application edits for
explicit user acceptance of any exact existing failures/warnings. No suppression,
skipping tests or unrelated baseline fixes. Record counts/assertions/seeds/exits,
immutable base, prerequisite facts and any acceptance. Task 0 requires no tracked
source commit. If Subagent-Driven was chosen, obtain its required task reviews.

## Task 1: Fixture-backed parser and runtime characterization

**Create:** `test/support/agent_skills_workspace_fixtures.rb`,
`test/support/fixtures/agent_skills_workspace/agent_skills.yml`,
`test/support/fixtures/agent_skills_workspace/agent_skill_executions.yml`,
`test/models/agent_skill_presentation_contract_test.rb`.

- [ ] **Step 1: Add the fixture helper and YAML below.** Existing account-experience fixtures already provide owner, member, outsider, no-account user and four accounts. Do not add factories or duplicate those users.

```ruby
# test/support/agent_skills_workspace_fixtures.rb
require_relative "account_experience_fixtures"

module AgentSkillsWorkspaceFixtures
  extend ActiveSupport::Concern
  include AccountExperienceFixtures

  included do
    setup do
      ActiveRecord::FixtureSet.reset_cache
      @skill_sets = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/agent_skills_workspace").to_s,
        %w[agent_skills agent_skill_executions]
      ).index_by(&:name)
    end
  end

  def workspace_skill(name)
    @skill_sets.fetch("agent_skills").fixtures.fetch(name.to_s).find
  end

  def workspace_execution(name)
    @skill_sets.fetch("agent_skill_executions").fixtures.fetch(name.to_s).find
  end

  def workspace_source(name = "new-skill")
    "---\nname: #{name}\ndescription: Keep this description\n---\n\n# Instructions\nKeep **this** source."
  end

  def workspace_records
    ActsAsTenant.without_tenant do
      [AgentSkill, AgentSkillExecution, TokenUsage].to_h do |model|
        [model.name, model.order(:id).map(&:attributes)]
      end
    end
  end
end
```

```yaml
# test/support/fixtures/agent_skills_workspace/agent_skills.yml
<% { first: ["first", 5, true, "llm", "explicit", "2026-01-01"],
     second: ["second", 80, true, "llm", "explicit", "2026-01-01"],
     second_later: ["second", 80, true, "llm", "combined", "2026-01-02"],
     second_ruby: ["second", 20, false, "ruby", "explicit", "2026-01-03"],
     foreign: ["foreign", 100, true, "llm", "auto", "2026-01-01"] }.each do |key, (account, priority, enabled, execution, trigger, created)| %>
skills_<%= key %>:
  account: overview_<%= account %>
  name: workspace-<%= key.to_s.tr("_", "-") %>
  description: Original <%= key %> description
  execution_mode: <%= execution %>
  trigger_mode: <%= trigger %>
  enabled: <%= enabled %>
  priority: <%= priority %>
  requires_rag_context: false
  metadata: { tags: [original, English] }
  skill_content: |
    ---
    name: workspace-<%= key.to_s.tr("_", "-") %>
    description: Original <%= key %> description
    ---

    Keep **original <%= key %>** instructions.
  created_at: <%= created %> 00:00:00
  updated_at: <%= created %> 00:00:00
<% end %>
```

```yaml
# test/support/fixtures/agent_skills_workspace/agent_skill_executions.yml
skills_second_execution:
  account: overview_second
  agent_skill: skills_second
  chat: overview_second_chat_0
  execution_mode: llm
  status: completed
  input: {}
  output: {}
skills_first_execution:
  account: overview_first
  agent_skill: skills_first
  chat: overview_first_chat
  execution_mode: llm
  status: completed
  input: {}
  output: {}
```

- [ ] **Step 2: Write these behavior characterizations before controller/view changes.** These are expected to PASS on the baseline, not invented feature REDs. If any fail, investigate a stale assumption before proceeding; do not alter the parser to satisfy the plan.

```ruby
# test/models/agent_skill_presentation_contract_test.rb
require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillPresentationContractTest < ActiveSupport::TestCase
  include AgentSkillsWorkspaceFixtures

  test "new-record defaults and create-only content presence stay intact" do
    skill = @second.agent_skills.new(name: "defaults")
    assert_equal ["llm", "explicit", true, 0, false],
      [skill.execution_mode, skill.trigger_mode, skill.enabled, skill.priority, skill.requires_rag_context]
    assert_not skill.valid?
    assert skill.errors.include?(:skill_content)
    stored = workspace_skill(:skills_second)
    assert stored.update(skill_content: "")
    assert_equal "", stored.reload.skill_content
  end

  test "frontmatter merges metadata but does not synchronize stored identity and modes" do
    skill = workspace_skill(:skills_second)
    original = skill.attributes.slice("name", "description", "execution_mode", "trigger_mode")
    source = "---\nname: other-name\ndescription: Other description\nexecution_mode: ruby\ntrigger_mode: auto\ntags: [updated]\n---\nKeep source."
    assert_no_enqueued_jobs { assert skill.update(skill_content: source) }
    assert_equal original, skill.reload.attributes.slice(*original.keys)
    assert_equal source, skill.skill_content
    assert_equal "other-name", skill.metadata.fetch("name")
    assert_equal ["updated"], skill.metadata.fetch("tags")
  end

  test "RAG keeps the existing frontmatter fallback and boolean conversion" do
    [[true, false, true], [false, true, true], ["false", true, false], [nil, true, true]].each do |metadata_value, checked, expected|
      source = "---\n" + { "name" => "rag-probe", "requires_rag_context" => metadata_value }.to_yaml.delete_prefix("---\n") + "---\nBody"
      skill = @second.agent_skills.new(name: "rag-probe", skill_content: source, requires_rag_context: checked)
      assert skill.valid?, skill.errors.full_messages.to_sentence
      assert_equal expected, skill.requires_rag_context
      assert_equal source, skill.skill_content
    end
  end

  test "enabled Ruby without an implementation is not runnable" do
    skill = workspace_skill(:skills_second_ruby)
    assert skill.update(enabled: true)
    assert skill.enabled?
    assert_not skill.runnable?
    assert_includes @second.agent_skills.runnable, skill
  end

  test "validation never rewrites submitted source or persists invalid priority" do
    skill = workspace_skill(:skills_second)
    original = skill.attributes
    source = workspace_source("different-name")
    skill.assign_attributes(skill_content: source, priority: 101)
    assert_not skill.save
    assert_equal source, skill.skill_content
    assert_equal original, skill.reload.attributes
  end
end
```

- [ ] **Step 3: Run the characterization and original model/localization tests.**

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task1-characterization.log rails test test/models/agent_skill_presentation_contract_test.rb test/models/agent_skill_test.rb test/integration/localized_pages_test.rb
```

Expected: PASS. No model/parser/API implementation changes.

- [ ] **Step 4: Commit only fixtures/tests.**

```bash
git add test/support/agent_skills_workspace_fixtures.rb test/support/fixtures/agent_skills_workspace test/models/agent_skill_presentation_contract_test.rb
git commit -m "test(skills): Characterize workspace content and parser contracts"
```

## Task 2: Authorized scoped CRUD and route-family helpers

**Create:** `app/controllers/concerns/agent_skill_scoped.rb`,
`app/helpers/agent_skills_workspace_helper.rb`, `app/views/agent_skills/setup.html.erb`,
`config/locales/en.nosia_skills_workspace.yml`, `config/locales/fr.nosia_skills_workspace.yml`,
`test/controllers/agent_skills_workspace_scoping_test.rb`.
**Modify:** `config/routes.rb` (accounts block near existing Sources/Token usage routes),
`app/controllers/agent_skills_controller.rb`.

- [ ] **Step 1: Write the integration tests below.**

```ruby
require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsWorkspaceScopingTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures
  setup { sign_in_overview }

  test "legacy account input cannot retarget the default and scoped reads use the URL account" do
    first = workspace_skill(:skills_first)
    second = workspace_skill(:skills_second)
    before = workspace_records
    get agent_skills_path, params: { account_id: @second.id }
    assert_response :success
    assert_includes response.body, first.name
    refute_includes response.body, second.name
    get account_agent_skills_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_includes response.body, second.name
    refute_includes response.body, first.name
    [new_account_agent_skill_path(@second), account_agent_skill_path(@second, second),
      edit_account_agent_skill_path(@second, second)].each do |path|
      assert_no_enqueued_jobs { get path }
      assert_response :success
    end
    assert_equal before, workspace_records
    assert_equal @first, @user.reload.first_account
  end

  test "create update and delete stay in each route family without transferring accounts" do
    [[agent_skills_path, @first], [account_agent_skills_path(@second), @second]].each do |collection, account|
      name = "created-#{account.id}"
      before_other = workspace_skill(:skills_foreign).attributes
      assert_no_enqueued_jobs do
        assert_difference -> { account.agent_skills.count }, 1 do
          post collection, params: { agent_skill: { skill_content: workspace_source(name), account_id: @foreign.id } }
        end
      end
      assert_redirected_to collection
      record = account.agent_skills.find_by!(name: name)
      path = account == @first ? agent_skill_path(record) : account_agent_skill_path(account, record)
      patch path, params: { agent_skill: { priority: 64, account_id: @foreign.id } }
      assert_redirected_to collection
      assert_equal 64, record.reload.priority
      assert_equal account.id, record.account_id
      delete path
      assert_redirected_to collection
      assert_not account.agent_skills.exists?(record.id)
      assert_equal before_other, workspace_skill(:skills_foreign).reload.attributes
    end
  end

  test "foreign malformed revoked and cross-account records fail closed" do
    before = workspace_records
    foreign = workspace_skill(:skills_foreign)
    first = workspace_skill(:skills_first)
    [account_agent_skills_path(@foreign), "/accounts/not-an-account/agent_skills",
      account_agent_skill_path(@second, foreign), account_agent_skill_path(@second, first),
      edit_account_agent_skill_path(@second, first)].each do |path|
      get path, params: { account_id: @second.id }
      assert_response :not_found
    end
    post account_agent_skills_path(@foreign), params: { agent_skill: { skill_content: workspace_source } }
    assert_response :not_found
    patch account_agent_skill_path(@second, first), params: { agent_skill: { priority: 99 } }
    assert_response :not_found
    delete account_agent_skill_path(@second, first)
    assert_response :not_found
    experience(:account_users, :overview_owner_second).destroy!
    get account_agent_skills_path(@second), params: { account_id: @first.id }
    assert_response :not_found
    assert_equal before, workspace_records
  end

  test "non-owner members keep existing management rights" do
    sign_in_overview(@member)
    get account_agent_skills_path(@second)
    assert_response :success
    second = workspace_skill(:skills_second)
    patch account_agent_skill_path(@second, second), params: { agent_skill: { priority: 63 } }
    assert_redirected_to account_agent_skills_path(@second)
    assert_equal 63, second.reload.priority
  end

  test "no default account has setup guidance and no mutation route can file elsewhere" do
    sign_in_overview(experience(:users, :overview_no_account))
    before = workspace_records
    [agent_skills_path, new_agent_skill_path].each do |path|
      get path
      assert_response :success
      assert_select "[data-skills-setup] a[href='#{accounts_path}']"
      assert_select "textarea", count: 0
    end
    post agent_skills_path, params: { agent_skill: { skill_content: workspace_source, account_id: @first.id } }
    assert_response :not_found
    get agent_skill_path(workspace_skill(:skills_first))
    assert_response :not_found
    assert_equal before, workspace_records
  end

  test "tenant context is bounded on successful and failing lookups" do
    second = workspace_skill(:skills_second)
    first = workspace_skill(:skills_first)
    ActsAsTenant.with_tenant(@foreign) do
      get account_agent_skill_path(@second, second)
      assert_response :success
      assert_equal @foreign, ActsAsTenant.current_tenant
      get account_agent_skill_path(@second, first)
      assert_response :not_found
      assert_equal @foreign, ActsAsTenant.current_tenant
    end
  end
end
```

- [ ] **Step 2: Run RED.**

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task2-red.log rails test test/controllers/agent_skills_workspace_scoping_test.rb
```

Expected: missing scoped routes/helpers and no-account setup failures. Fix syntax,
fixture or environment mistakes before treating a failure as feature evidence.

- [ ] **Step 3: Add scoped CRUD routes and the complete concern/path helper below.** Inside the existing `resources :accounts` block add `resources :agent_skills`. Leave legacy routes/toggle unchanged until Task 3. Do not add a global tenant setter.

```ruby
# Inside resources :accounts in config/routes.rb
resources :agent_skills
```

```ruby
# app/controllers/concerns/agent_skill_scoped.rb
module AgentSkillScoped
  extend ActiveSupport::Concern
  include AccountScoped
  include AgentSkillsWorkspaceHelper

  included do
    around_action :with_agent_skill_account
  end

  private
    def with_agent_skill_account
      @scoped_skill_account = request.path_parameters.key?(:account_id)
      @account = if @scoped_skill_account
        member_account(request.path_parameters.fetch(:account_id))
      else
        Current.account
      end

      if @account
        ActsAsTenant.with_tenant(@account) { yield }
      elsif controller_path == "agent_skills" && %w[index new].include?(action_name)
        render "agent_skills/setup", formats: [:html]
      else
        head :not_found
      end
    end

    def set_scoped_agent_skill
      id = request.path_parameters[:agent_skill_id] || request.path_parameters[:id]
      @agent_skill = @account.agent_skills.find(id)
    end
end
```

```ruby
# app/helpers/agent_skills_workspace_helper.rb
module AgentSkillsWorkspaceHelper
  # @return [Boolean] Whether this controller renders the Skills browser workspace
  def agent_skills_workspace_page?
    controller_path == "agent_skills" || controller_path.start_with?("agent_skills/")
  end

  # @return [Boolean] Whether the account came from the authorized URL path
  def skills_workspace_scoped?
    @scoped_skill_account == true
  end

  # @return [String] The originating list URL
  def skill_workspace_index_path
    skills_workspace_scoped? ? account_agent_skills_path(@account) : agent_skills_path
  end

  # @return [String] The originating creation URL
  def skill_workspace_new_path
    skills_workspace_scoped? ? new_account_agent_skill_path(@account) : new_agent_skill_path
  end

  # @param skill [AgentSkill] An authorized existing skill
  # @return [String] Context-preserving details URL
  def skill_workspace_path(skill)
    skills_workspace_scoped? ? account_agent_skill_path(@account, skill) : agent_skill_path(skill)
  end

  # @param skill [AgentSkill] An authorized existing skill
  # @return [String] Context-preserving edit URL
  def skill_workspace_edit_path(skill)
    skills_workspace_scoped? ? edit_account_agent_skill_path(@account, skill) : edit_agent_skill_path(skill)
  end

  # @param skill [AgentSkill] An authorized new or existing skill
  # @return [AgentSkill, Array] Model argument for form_with
  def skill_workspace_form_model(skill)
    skills_workspace_scoped? ? [@account, skill] : skill
  end
end
```

- [ ] **Step 4: Replace the CRUD controller with this scoped version and add setup/catalogs.** The temporary legacy toggle method is preserved verbatim in behavior and removed by Task 3's adapter. Raw submitted values are only retained for failed form presentation; they do not bypass model callbacks.

```ruby
# app/controllers/agent_skills_controller.rb
class AgentSkillsController < ApplicationController
  include AgentSkillScoped
  before_action :set_scoped_agent_skill, only: [:show, :edit, :update, :destroy, :toggle]

  def index
    @agent_skills = @account.agent_skills.order(priority: :desc, created_at: :asc)
  end

  def new
    @agent_skill = @account.agent_skills.new
  end

  def create
    @agent_skill = @account.agent_skills.new(agent_skill_params)
    if @agent_skill.save
      redirect_to skill_workspace_index_path, notice: t("nosia.skills.created"), status: :see_other
    else
      @submitted_skill_values = agent_skill_params.to_h
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
  end

  def update
    if @agent_skill.update(agent_skill_params)
      redirect_to skill_workspace_index_path, notice: t("nosia.skills.updated"), status: :see_other
    else
      @submitted_skill_values = agent_skill_params.to_h
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @agent_skill.destroy
      redirect_to skill_workspace_index_path, notice: t("nosia.skills.deleted"), status: :see_other
    else
      redirect_to skill_workspace_index_path, alert: @agent_skill.errors.full_messages.to_sentence.presence || t("nosia.skills_workspace.action_failed"), status: :see_other
    end
  end

  def toggle
    @agent_skill.update!(enabled: !@agent_skill.enabled)
    redirect_to skill_workspace_index_path, notice: t(@agent_skill.enabled? ? "nosia.skills.now_enabled" : "nosia.skills.now_disabled")
  end

  private
    def agent_skill_params
      params.require(:agent_skill).permit(:name, :description, :execution_mode,
        :trigger_mode, :requires_rag_context, :enabled, :priority, :skill_content)
    end
end
```

```erb
<%# app/views/agent_skills/setup.html.erb %>
<div class="n-workspace n-skills-workspace" data-skills-workspace data-skills-setup>
  <%= render "workspaces/header", title: t("nosia.skills.title"), trail: [{ label: t("nosia.nav.home"), path: user_root_path }], show_new_chat: true %>
  <section class="n-workspace-panel" aria-labelledby="skills-setup-title">
    <h2 id="skills-setup-title" class="n-workspace-section-title"><%= t("nosia.skills_workspace.setup_title") %></h2>
    <p class="n-workspace-help"><%= t("nosia.skills_workspace.setup_help") %></p>
    <%= link_to t("nosia.skills_workspace.setup_action"), accounts_path, class: "n-workspace-button n-workspace-primary" %>
  </section>
</div>
```

```yaml
# config/locales/en.nosia_skills_workspace.yml
en:
  nosia:
    skills_workspace:
      setup_title: "Choose or create an account first"
      setup_help: "An account is needed before you can manage agent skills."
      setup_action: "View accounts"
      action_failed: "The skill could not be changed. Please try again."
```

```yaml
# config/locales/fr.nosia_skills_workspace.yml
fr:
  nosia:
    skills_workspace:
      setup_title: "Choisissez ou créez d’abord un compte"
      setup_help: "Un compte est nécessaire pour gérer les compétences d’agent."
      setup_action: "Voir les comptes"
      action_failed: "La compétence n’a pas pu être modifiée. Veuillez réessayer."
```

- [ ] **Step 5: Run GREEN and original regressions, then commit.** Scoping is now testable; subsequent tasks replace all contextual browser controls before feature delivery. No interim branch is deployed.

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task2-green.log rails test test/controllers/agent_skills_workspace_scoping_test.rb test/models/agent_skill_presentation_contract_test.rb test/integration/localized_pages_test.rb
git add config/routes.rb app/controllers/agent_skills_controller.rb app/controllers/concerns/agent_skill_scoped.rb app/helpers/agent_skills_workspace_helper.rb app/views/agent_skills/setup.html.erb config/locales/en.nosia_skills_workspace.yml config/locales/fr.nosia_skills_workspace.yml test/controllers/agent_skills_workspace_scoping_test.rb
git commit -m "feat(skills): Add authorized account-scoped browser CRUD"
```

## Task 3: Explicit enablement resources and legacy toggle compatibility

**Create:** `app/controllers/agent_skills/enablements_controller.rb`,
`app/controllers/agent_skills/toggles_controller.rb`,
`test/controllers/agent_skills_workspace_states_test.rb`.
**Modify:** `config/routes.rb`, `app/controllers/agent_skills_controller.rb`,
`app/helpers/agent_skills_workspace_helper.rb`.

- [ ] **Step 1: Write state integration tests.**

```ruby
require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsWorkspaceStatesTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures
  setup { sign_in_overview }

  test "explicit state actions preserve account and desired state without execution" do
    [[workspace_skill(:skills_first), nil], [workspace_skill(:skills_second), @second]].each do |skill, account|
      path = account ? account_agent_skill_enablement_path(account, skill) : agent_skill_enablement_path(skill)
      index = account ? account_agent_skills_path(account) : agent_skills_path
      work_before = [AgentSkillExecution.count, TokenUsage.count]
      assert_no_enqueued_jobs do
        2.times do
          delete path
          assert_redirected_to index
          assert_not skill.reload.enabled?
          post path
          assert_redirected_to index
          assert skill.reload.enabled?
        end
        post path
        assert skill.reload.enabled?
      end
      assert_equal work_before, [AgentSkillExecution.count, TokenUsage.count]
    end
  end

  test "legacy PATCH toggle still flips twice and returns the legacy list" do
    skill = workspace_skill(:skills_first)
    [false, true].each do |expected|
      patch toggle_agent_skill_path(skill), params: { account_id: @second.id }
      assert_response :found
      assert_redirected_to agent_skills_path
      assert_equal expected, skill.reload.enabled?
    end
  end

  test "cross-account enablements and legacy foreign toggle cannot mutate" do
    before = workspace_records
    first = workspace_skill(:skills_first)
    post account_agent_skill_enablement_path(@second, first)
    assert_response :not_found
    delete account_agent_skill_enablement_path(@foreign, workspace_skill(:skills_foreign))
    assert_response :not_found
    patch toggle_agent_skill_path(workspace_skill(:skills_second))
    assert_response :not_found
    assert_equal before, workspace_records
  end

  test "known validation failure reports an error without claiming a state change" do
    skill = workspace_skill(:skills_second)
    skill.update_columns(priority: 101)
    before = skill.reload.attributes
    delete account_agent_skill_enablement_path(@second, skill)
    assert_redirected_to account_agent_skills_path(@second)
    assert flash[:alert].present?
    assert_nil flash[:notice]
    assert_equal before, skill.reload.attributes
  end

  test "deletion removes only the authorized skill and its recorded executions" do
    second = workspace_skill(:skills_second)
    other = workspace_skill(:skills_first).attributes
    other_execution = workspace_execution(:skills_first_execution).attributes
    assert_no_enqueued_jobs do
      assert_difference -> { AgentSkillExecution.count }, -1 do
        delete account_agent_skill_path(@second, second)
      end
    end
    assert_redirected_to account_agent_skills_path(@second)
    assert_not AgentSkill.exists?(second.id)
    assert_equal other, workspace_skill(:skills_first).reload.attributes
    assert_equal other_execution, workspace_execution(:skills_first_execution).reload.attributes
  end
end
```

- [ ] **Step 2: Run RED for missing enablement routes/controllers.**

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task3-red.log rails test test/controllers/agent_skills_workspace_states_test.rb
```

- [ ] **Step 3: Add the resource block inside BOTH legacy and account-scoped `resources :agent_skills`.** Replace the existing legacy member-toggle route with the explicit compatibility route outside the legacy resource. Use only REST controller actions.

```ruby
resources :agent_skills do
  scope module: :agent_skills do
    resource :enablement, only: [:create, :destroy]
  end
end
```

```ruby
patch "agent_skills/:id/toggle", to: "agent_skills/toggles#update", as: :toggle_agent_skill
```

Remove `:toggle` from the CRUD `before_action` list and remove that controller's
entire `def toggle` method. Do not change the API namespace routes.

```ruby
# app/controllers/agent_skills/enablements_controller.rb
class AgentSkills::EnablementsController < ApplicationController
  include AgentSkillScoped
  before_action :set_scoped_agent_skill

  def create
    update_enablement(true)
  end

  def destroy
    update_enablement(false)
  end

  private
    def update_enablement(enabled)
      if @agent_skill.update(enabled: enabled)
        redirect_to skill_workspace_index_path, notice: t(enabled ? "nosia.skills.now_enabled" : "nosia.skills.now_disabled"), status: :see_other
      else
        redirect_to skill_workspace_index_path, alert: @agent_skill.errors.full_messages.to_sentence.presence || t("nosia.skills_workspace.action_failed"), status: :see_other
      end
    end
end
```

```ruby
# app/controllers/agent_skills/toggles_controller.rb
class AgentSkills::TogglesController < ApplicationController
  include AgentSkillScoped
  before_action :set_scoped_agent_skill

  def update
    if @agent_skill.update(enabled: !@agent_skill.enabled?)
      redirect_to skill_workspace_index_path, notice: t(@agent_skill.enabled? ? "nosia.skills.now_enabled" : "nosia.skills.now_disabled")
    else
      redirect_to skill_workspace_index_path, alert: @agent_skill.errors.full_messages.to_sentence.presence || t("nosia.skills_workspace.action_failed")
    end
  end
end
```

Append this public method to `AgentSkillsWorkspaceHelper`:

```ruby
  # @param skill [AgentSkill] An authorized existing skill
  # @return [String] Explicit enable/disable resource URL
  def skill_workspace_enablement_path(skill)
    skills_workspace_scoped? ? account_agent_skill_enablement_path(@account, skill) : agent_skill_enablement_path(skill)
  end
```

- [ ] **Step 4: Run GREEN, including legacy/localization behavior, then commit.**

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task3-green.log rails test test/controllers/agent_skills_workspace_scoping_test.rb test/controllers/agent_skills_workspace_states_test.rb test/models/agent_skill_presentation_contract_test.rb test/integration/localized_pages_test.rb
git add config/routes.rb app/controllers/agent_skills_controller.rb app/controllers/agent_skills app/helpers/agent_skills_workspace_helper.rb test/controllers/agent_skills_workspace_states_test.rb
git commit -m "feat(skills): Add explicit enablement actions with toggle compatibility"
```

## Task 4: Workspace shell, structured rows and complete details

**Create:** `app/views/agent_skills/_header.html.erb`, `_feedback.html.erb`,
`_row.html.erb`, `_state_action.html.erb`, `_settings.html.erb`;
`app/javascript/controllers/html_form_controller.js`;
`app/assets/stylesheets/nosia/skills_workspace.css`;
`test/controllers/agent_skills_workspace_shell_test.rb`,
`test/controllers/agent_skills_workspace_content_test.rb`,
`test/system/agent_skills_workspace_test.rb`.
**Modify:** `app/views/agent_skills/{index,show,setup}.html.erb`, helper/catalogs,
`app/views/layouts/application.html.erb`, `app/views/application/_menu.html.erb`,
`app/views/accounts/_configuration.html.erb`, `app/assets/tailwind/application.css`,
`test/integration/localized_pages_test.rb`.
**Retire after caller check:** `app/views/agent_skills/_skill_card.html.erb`.

- [ ] **Step 1: Write request tests for the shell/content contract.**

```ruby
# test/controllers/agent_skills_workspace_shell_test.rb
require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsWorkspaceShellTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures
  setup { sign_in_overview }

  test "list and details have one heading breadcrumb scope and no conversation drawer" do
    [[agent_skills_path, "Default account: #{@first.name}"],
      [account_agent_skills_path(@second), "Account: #{@second.name}"],
      [account_agent_skill_path(@second, workspace_skill(:skills_second)), "Account: #{@second.name}"]].each do |path, scope|
      assert_no_enqueued_jobs { get path }
      assert_response :success
      assert_select "[data-skills-workspace] h1", count: 1
      assert_select "main h1", count: 1
      assert_select "[data-workspace-scope]", text: scope
      assert_select ".n-workspace-header nav", count: 1
      assert_select "#accordion-right-actions, #drawer-right, [data-drawer-target]", count: 0
    end
    assert_select ".n-workspace-trail a[href='#{account_agent_skills_path(@second)}']"
    assert_select ".n-workspace-header a[href='#{new_chat_path(account_id: @second.id)}']"
    get settings_path
    assert_select "#accordion-right-actions", count: 1
    get account_path(@second)
    assert_select "a[href='#{account_agent_skills_path(@second)}']"
    assert_equal @first, @user.reload.first_account
  end

  test "Skills feedback is in flow and global toasts are not duplicated" do
    post account_agent_skill_enablement_path(@second, workspace_skill(:skills_second))
    follow_redirect!
    assert_select "[data-skills-feedback][role='status']", text: I18n.t("nosia.skills.now_enabled")
    assert_select "#toast-success, #toast-danger", count: 0
  end
end
```

```ruby
# test/controllers/agent_skills_workspace_content_test.rb
require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsWorkspaceContentTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures
  setup { sign_in_overview }

  test "structured rows preserve order settings tags counts and contextual actions" do
    get account_agent_skills_path(@second)
    assert_response :success
    expected = [:skills_second, :skills_second_later, :skills_second_ruby].map { |name| workspace_skill(name).id.to_s }
    assert_equal expected, css_select("[data-skill-id]").map { |row| row["data-skill-id"] }
    assert_select "[data-skills-count][data-total='3'][data-enabled='2']"
    expected.each do |id|
      assert_select "[data-skill-id='#{id}']" do
        assert_select "a[href='#{account_agent_skill_path(@second, id)}']"
        assert_select "a[href='#{edit_account_agent_skill_path(@second, id)}']"
        assert_select "form[action='#{account_agent_skill_enablement_path(@second, id)}']"
        assert_select "[data-skill-execution], [data-skill-trigger], [data-skill-priority], [data-skill-rag]", count: 4
        assert_select "form[data-skill-delete]", count: 0
      end
    end
    assert_includes response.body, "original, English"
  end

  test "details keep complete authored content escaped and deletion separate" do
    skill = workspace_skill(:skills_second)
    source = "---\nname: raw-example\n---\n</pre><script>alert('unsafe')</script>\nKeep **literal** instructions."
    skill.update_columns(skill_content: source, description: "Full <strong>description</strong>", metadata: { "tags" => ["<unsafe>", "English"] })
    before = workspace_records
    get account_agent_skill_path(@second, skill)
    assert_select "pre[data-skill-source]", text: source
    assert_select "[data-skills-workspace] script", count: 0
    assert_select "[data-skill-description] strong", text: "description"
    assert_select "[data-skill-delete-section] form[action='#{account_agent_skill_path(@second, skill)}'][data-turbo-confirm]"
    confirm = css_select("[data-skill-delete-section] form").first["data-turbo-confirm"]
    assert_includes confirm, skill.name
    assert_includes confirm, @second.name
    assert_includes confirm, "recorded executions"
    assert_equal before, workspace_records
  end

  test "empty account and locale reads are honest and preserve authored values" do
    before = workspace_records
    %w[en fr].each do |locale|
      headers = { "Accept-Language" => locale }
      get account_agent_skills_path(@empty), headers: headers
      assert_select "[data-skills-empty] a[href='#{new_account_agent_skill_path(@empty)}']"
      get account_agent_skills_path(@second), headers: headers
      assert_includes response.body, workspace_skill(:skills_second).description
      refute_match(/translation missing|missing translation/i, response.body)
      get account_agent_skill_path(@second, workspace_skill(:skills_second)), headers: headers
      assert_select "pre", text: workspace_skill(:skills_second).skill_content
    end
    assert_equal before, workspace_records
  end
end
```

- [ ] **Step 2: Add the first browser layout test before CSS/view implementation.** This file is extended in Tasks 5–6; keep the helper methods below available to those additions.

```ruby
require "application_system_test_case"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsWorkspaceSystemTest < ApplicationSystemTestCase
  include AgentSkillsWorkspaceFixtures

  setup do
    @original_window_size = page.current_window.size
    @evidence_dir = "/tmp/opencode/agent-skills-workspace-#{Process.pid}"
    FileUtils.mkdir_p(@evidence_dir)
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    page.current_window.resize_to(*@original_window_size)
    Capybara.reset_sessions!
  end

  test "structured rows reflow and expose keyboard reachable text actions" do
    [375, 1440].each do |width|
      resize_skills_viewport(width, 900)
      %w[light dark].each do |theme|
        visit account_agent_skills_path(@second)
        set_skills_theme(theme)
        assert_selector "[data-skill-id]", count: 3
        assert_skills_layout
        focus_skill_by_tab("[data-skill-id] [data-skill-state-action]")
        assert_skills_focus
        page.save_screenshot("#{@evidence_dir}/rows-#{width}-#{theme}.png")
      end
    end
  end

  private
    def resize_skills_viewport(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth, innerHeight]") != [width, height]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
    end

    def set_skills_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
    end

    def assert_skills_layout
      assert_selector "main h1", count: 1
      assert_no_text(/translation missing|missing translation/i)
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1")
      assert_no_selector "#drawer-right, #accordion-right-actions, [data-drawer-target]", visible: :all
    end

    def focus_skill_by_tab(selector)
      200.times do
        page.send_keys(:tab)
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          page.driver.browser.execute_async_script("const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));")
          return
        end
      end
      flunk "Keyboard could not reach #{selector}"
    end

    def assert_skills_focus
      result = page.evaluate_script(<<~JS)
        (()=>{const e=document.activeElement,r=e.getBoundingClientRect(),s=getComputedStyle(e),m=document.querySelector('main').getBoundingClientRect();
        const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
        return {height:r.height,outline:parseFloat(s.outlineWidth),visible:r.top>=Math.max(0,m.top)&&r.bottom<=Math.min(innerHeight,m.bottom)&&points.every(([x,y])=>{const h=document.elementFromPoint(x,y);return h&&(h===e||e.contains(h));})};})()
      JS
      assert_operator result.fetch("height"), :>=, 44
      assert_operator result.fetch("outline"), :>=, 2
      assert result.fetch("visible"), result.to_json
    end
end
```

- [ ] **Step 3: Run request/browser REDs.**

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task4-red-http.log rails test test/controllers/agent_skills_workspace_shell_test.rb test/controllers/agent_skills_workspace_content_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task4-red-browser.log browser test/system/agent_skills_workspace_test.rb
```

Expected: missing workspace semantics, structured rows, contextual actions and
44px/focus/reflow behavior. Do not accept missing fixture helpers as a valid RED.

- [ ] **Step 4: Extend the helper with the following presentation methods and create the HTML-form enhancement.** No editor parsing or readiness lookup belongs here.

```ruby
  # @return [String, nil] Localized account scope, escaped by normal ERB
  def skill_workspace_scope
    if @account
      t(skills_workspace_scoped? ? "nosia.workspace.account" : "nosia.workspace.default_account", name: @account.name)
    end
  end

  # @param title [String, nil] Current detail/form title
  # @return [Array<Hash>] Complete breadcrumb for this route family
  def skill_workspace_trail(title: nil)
    trail = if skills_workspace_scoped?
      [{ label: t("nosia.nav.accounts"), path: accounts_path }, { label: @account.name, path: account_path(@account) }]
    else
      [{ label: t("nosia.nav.home"), path: user_root_path }]
    end
    trail << { label: t("nosia.skills.title"), path: title ? skill_workspace_index_path : nil }
    trail << { label: title, path: nil } if title
    trail
  end

  # @return [String] Existing composer URL, contextual when a URL account exists
  def skill_workspace_new_chat_path
    skills_workspace_scoped? ? new_chat_path(account_id: @account.id) : new_chat_path
  end

  # @param skill [AgentSkill] Authorized deletion target
  # @return [String] Plain confirmation, never marked HTML-safe
  def skill_workspace_delete_confirmation(skill)
    t("nosia.skills_workspace.delete_confirm", name: skill.name, account: @account.name)
  end
```

```javascript
// app/javascript/controllers/html_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  requestHTML(event) {
    if (event.target !== this.element) return
    const headers = event.detail.fetchOptions.headers
    if (headers instanceof Headers) headers.set("Accept", "text/html, application/xhtml+xml")
    else headers.Accept = "text/html, application/xhtml+xml"
  }
}
```

- [ ] **Step 5: Create the complete partials/list/details below.** All mutation forms opt into HTML negotiation locally; no Turbo Stream or global header rewrite is introduced.

```erb
<%# app/views/agent_skills/_header.html.erb %>
<%# locals: (title:, current: nil, description: nil, back_path: nil, primary: nil) %>
<% actions = capture do %>
  <div class="hidden lg:block"><%= link_to t("nosia.nav.new_chat"), skill_workspace_new_chat_path, class: "n-workspace-link" %></div>
  <%= primary %>
<% end %>
<%= render "workspaces/header", title: title, description: description, scope_label: skill_workspace_scope, trail: skill_workspace_trail(title: current), back_path: back_path, actions: actions %>
```

```erb
<%# app/views/agent_skills/_feedback.html.erb %>
<% %i[notice alert].each do |kind| %>
  <% if flash[kind].present? %>
    <div data-skills-feedback class="n-skills-feedback <%= kind == :alert ? 'n-skills-feedback-error' : '' %>" role="<%= kind == :alert ? 'alert' : 'status' %>"><%= flash[kind] %></div>
  <% end %>
<% end %>
```

```erb
<%# app/views/agent_skills/_state_action.html.erb %>
<%# locals: (skill:) %>
<%= button_to t(skill.enabled? ? "nosia.skills.disable" : "nosia.skills.enable"), skill_workspace_enablement_path(skill),
      method: skill.enabled? ? :delete : :post, class: "n-workspace-button",
      aria: { label: "#{t(skill.enabled? ? 'nosia.skills.disable' : 'nosia.skills.enable')}: #{skill.name}" },
      data: { skill_state_action: true, turbo_submits_with: t(skill.enabled? ? "nosia.skills_workspace.disabling" : "nosia.skills_workspace.enabling") },
      form: { data: { controller: "html-form", action: "turbo:before-fetch-request->html-form#requestHTML" } } %>
```

```erb
<%# app/views/agent_skills/_settings.html.erb %>
<%# locals: (skill:) %>
<dl class="n-skills-settings">
  <div><dt><%= t("nosia.skills.execution_mode") %></dt><dd data-skill-execution><span class="n-tag"><%= t("nosia.skills.execution.#{skill.execution_mode}") %></span></dd></div>
  <div><dt><%= t("nosia.skills.trigger_mode") %></dt><dd data-skill-trigger><span class="n-tag"><%= t("nosia.skills.trigger.#{skill.trigger_mode}") %></span></dd></div>
  <div><dt><%= t("nosia.skills.priority") %></dt><dd data-skill-priority><%= skill.priority %></dd></div>
  <div><dt><%= t("nosia.skills.rag_context") %></dt><dd data-skill-rag><%= t(skill.requires_rag_context ? "nosia.skills.yes" : "nosia.skills.no") %></dd></div>
</dl>
```

```erb
<%# app/views/agent_skills/_row.html.erb %>
<%# locals: (skill:) %>
<li id="<%= dom_id(skill) %>" class="n-skills-row" data-skill-id="<%= skill.id %>">
  <div class="n-skills-identity">
    <h2><%= link_to skill.name, skill_workspace_path(skill), class: "n-workspace-link" %></h2>
    <p class="n-workspace-help"><%= truncate(skill.description.to_s, length: 140) %></p>
    <% if skill.tags_list.present? %><p class="n-workspace-help"><span><%= t("nosia.skills.tags") %></span> <%= skill.tags_list %></p><% end %>
  </div>
  <%= render "agent_skills/settings", skill: skill %>
  <div><span class="n-skills-badge" data-skill-enabled="<%= skill.enabled? %>"><%= t(skill.enabled? ? "nosia.skills.enabled" : "nosia.skills.disabled") %></span></div>
  <div class="n-skills-actions">
    <%= link_to t("nosia.skills_workspace.view"), skill_workspace_path(skill), class: "n-workspace-link", aria: { label: "#{t('nosia.skills_workspace.view')}: #{skill.name}" } %>
    <%= link_to t("nosia.skills.edit"), skill_workspace_edit_path(skill), class: "n-workspace-link", aria: { label: "#{t('nosia.skills.edit')}: #{skill.name}" } %>
    <%= render "agent_skills/state_action", skill: skill %>
  </div>
</li>
```

```erb
<%# app/views/agent_skills/index.html.erb %>
<div class="n-workspace n-skills-workspace" data-skills-workspace>
  <%= render "agent_skills/header", title: t("nosia.skills.title"), description: t("nosia.skills_workspace.description"), primary: (@agent_skills.any? ? link_to(t("nosia.skills.create"), skill_workspace_new_path, class: "n-workspace-button n-workspace-primary") : nil) %>
  <%= render "agent_skills/feedback" %>
  <% total = @agent_skills.size; enabled = @agent_skills.count(&:enabled?) %>
  <p class="n-workspace-help" data-skills-count data-total="<%= total %>" data-enabled="<%= enabled %>"><%= t("nosia.skills_workspace.counts", count: total, total: number_with_delimiter(total), enabled: number_with_delimiter(enabled)) %></p>
  <% if @agent_skills.any? %>
    <ul class="n-skills-rows !list-none"><%= render partial: "agent_skills/row", collection: @agent_skills, as: :skill %></ul>
    <p class="n-workspace-help"><%= t("nosia.skills_workspace.availability_note") %></p>
  <% else %>
    <section class="n-workspace-panel" data-skills-empty>
      <p class="n-workspace-section-title"><%= t("nosia.skills.none") %></p>
      <p class="n-workspace-help"><%= t("nosia.skills.none_help") %></p>
      <%= link_to t("nosia.skills.create"), skill_workspace_new_path, class: "n-workspace-button n-workspace-primary" %>
    </section>
  <% end %>
</div>
```

```erb
<%# app/views/agent_skills/show.html.erb %>
<div class="n-workspace n-skills-workspace" data-skills-workspace data-skill-detail>
  <%= render "agent_skills/header", title: @agent_skill.name, current: @agent_skill.name, back_path: skill_workspace_index_path, primary: link_to(t("nosia.skills.edit"), skill_workspace_edit_path(@agent_skill), class: "n-workspace-button n-workspace-primary") %>
  <%= render "agent_skills/feedback" %>
  <section class="n-workspace-panel n-skills-detail">
    <div class="n-skills-actions">
      <span class="n-skills-badge" data-skill-enabled="<%= @agent_skill.enabled? %>"><%= t(@agent_skill.enabled? ? "nosia.skills.enabled" : "nosia.skills.disabled") %></span>
      <%= render "agent_skills/state_action", skill: @agent_skill %>
    </div>
    <h2 class="n-workspace-section-title"><%= t("nosia.skills.description") %></h2>
    <div data-skill-description><%= simple_format(@agent_skill.description) %></div>
    <% if @agent_skill.tags_list.present? %><p class="n-workspace-help"><span><%= t("nosia.skills.tags") %></span> <%= @agent_skill.tags_list %></p><% end %>
    <%= render "agent_skills/settings", skill: @agent_skill %>
    <p class="n-workspace-help"><%= t("nosia.skills_workspace.availability_note") %></p>
  </section>
  <section class="n-workspace-panel" aria-labelledby="skill-source-title">
    <h2 id="skill-source-title" class="n-workspace-section-title"><%= t("nosia.skills.content") %></h2>
    <pre data-skill-source class="n-skills-source"><%= @agent_skill.skill_content_text %></pre>
  </section>
  <section class="n-workspace-panel n-skills-danger" data-skill-delete-section aria-labelledby="skill-delete-title">
    <h2 id="skill-delete-title" class="n-workspace-section-title"><%= t("nosia.skills.delete") %></h2>
    <p class="n-workspace-help"><%= t("nosia.skills_workspace.delete_help") %></p>
    <%= button_to t("nosia.skills.delete"), skill_workspace_path(@agent_skill), method: :delete, class: "n-workspace-button n-workspace-danger", data: { skill_delete: true, turbo_submits_with: t("nosia.skills_workspace.deleting") }, form: { data: { skill_delete: true, turbo_confirm: skill_workspace_delete_confirmation(@agent_skill), controller: "html-form", action: "turbo:before-fetch-request->html-form#requestHTML" } } %>
  </section>
</div>
```

In `setup.html.erb`, replace its first `render "workspaces/header"` expression with:

```erb
<%= render "agent_skills/header", title: t("nosia.skills.title") %>
<%= render "agent_skills/feedback" %>
```

- [ ] **Step 6: Make only these shared integration changes.** In application layout, replace the global flash call and surround the existing breadcrumb/navbar conditional with an outer Skills exclusion. Append the Skills exclusion to the existing drawer condition; retain all its existing predicates.

```erb
<%= render "flash" unless agent_skills_workspace_page? %>
```

```erb
<% unless agent_skills_workspace_page? %>
  <% if account_page? && @account %>
    <%= render "accounts/breadcrumb", account: @account, title: content_for(:account_tool_title) %>
  <% else %>
    <%= render "navbar" %>
  <% end %>
<% end %>
```

```erb
<% if Current.user && !account_page? && !dashboard_page? && !sources_workspace_page? && !token_usage_workspace_page? && !agent_skills_workspace_page? %>
```

Change ONLY the mobile New chat link destination in `application/_menu.html.erb`
from `new_chat_path` to the following expression, leaving its label/classes/icon
and every other link intact:

```ruby
agent_skills_workspace_page? ? skill_workspace_new_chat_path : new_chat_path
```

Append this small section to `accounts/_configuration.html.erb`:

```erb
<section class="n-account-panel">
  <h2><%= t("nosia.skills.title") %></h2>
  <%= link_to t("nosia.skills.manage"), account_agent_skills_path(@account), class: "n-account-link" %>
</section>
```

- [ ] **Step 7: Replace both workspace catalogs with complete values below.** Existing `nosia.skills` and ActiveRecord translations stay authoritative; do not duplicate those namespace keys.

```yaml
en:
  nosia:
    skills_workspace:
      description: "Manage the instructions and behaviors available to your assistant."
      view: "View"
      counts:
        one: "%{total} skill · %{enabled} enabled"
        other: "%{total} skills · %{enabled} enabled"
      setup_title: "Choose or create an account first"
      setup_help: "An account is needed before you can manage agent skills."
      setup_action: "View accounts"
      action_failed: "The skill could not be changed. Please try again."
      availability_note: "Enabled describes configuration, not verified execution. Ruby skills also require their implementation class."
      delete_help: "Deleting this skill also removes its recorded executions. You will be asked to confirm the skill and account."
      delete_confirm: "Delete %{name} from %{account}? Its recorded executions will also be deleted."
      definition: "Skill definition"
      behavior: "Behavior"
      advanced: "Advanced settings"
      saved_identity: "Saved identity"
      identity_note: "Editing frontmatter does not automatically change the saved name or description."
      source_help: "Use YAML frontmatter followed by instructions. The source remains plain text."
      name_help: "The name must be unique in this account, start with a letter, and use only letters, numbers, underscores or hyphens."
      execution_help: "LLM uses instructions. Ruby requires its implementation class. Saving does not verify execution."
      trigger_help: "Choose how this skill can be triggered."
      rag_help: "Keep this consistent with requires_rag_context in frontmatter. A requirement set there must also be cleared there to turn it off."
      saving: "Saving…"
      updating: "Updating…"
      enabling: "Enabling…"
      disabling: "Disabling…"
      deleting: "Deleting…"
```

```yaml
fr:
  nosia:
    skills_workspace:
      description: "Gérez les instructions et les comportements disponibles pour votre assistant."
      view: "Voir"
      counts:
        one: "%{total} compétence · %{enabled} activée(s)"
        other: "%{total} compétences · %{enabled} activée(s)"
      setup_title: "Choisissez ou créez d’abord un compte"
      setup_help: "Un compte est nécessaire pour gérer les compétences d’agent."
      setup_action: "Voir les comptes"
      action_failed: "La compétence n’a pas pu être modifiée. Veuillez réessayer."
      availability_note: "L’activation décrit la configuration, pas une exécution vérifiée. Les compétences Ruby nécessitent aussi leur classe d’implémentation."
      delete_help: "La suppression de cette compétence supprime aussi ses exécutions enregistrées. Vous devrez confirmer la compétence et le compte."
      delete_confirm: "Supprimer %{name} du compte %{account} ? Ses exécutions enregistrées seront aussi supprimées."
      definition: "Définition de la compétence"
      behavior: "Comportement"
      advanced: "Paramètres avancés"
      saved_identity: "Identité enregistrée"
      identity_note: "Modifier l’en-tête YAML ne change pas automatiquement le nom ou la description enregistrés."
      source_help: "Utilisez un en-tête YAML suivi des instructions. Le contenu reste du texte brut."
      name_help: "Le nom doit être unique dans ce compte, commencer par une lettre et ne contenir que des lettres, chiffres, traits de soulignement ou traits d’union."
      execution_help: "LLM utilise des instructions. Ruby nécessite sa classe d’implémentation. L’enregistrement ne vérifie pas l’exécution."
      trigger_help: "Choisissez comment cette compétence peut être déclenchée."
      rag_help: "Gardez ce choix cohérent avec requires_rag_context dans l’en-tête YAML. Une exigence définie dans cet en-tête doit aussi y être retirée pour la désactiver."
      saving: "Enregistrement…"
      updating: "Mise à jour…"
      enabling: "Activation…"
      disabling: "Désactivation…"
      deleting: "Suppression…"
```

- [ ] **Step 8: Add scoped row/detail styles and import them immediately after `workspace.css` in Tailwind's entrypoint.** Do not alter global typography, old tool classes or dependencies.

```css
@import "../stylesheets/nosia/skills_workspace.css" layer(utilities);
```

```css
/* app/assets/stylesheets/nosia/skills_workspace.css */
main:has([data-skills-workspace]) { min-width: 0; scroll-padding-block-end: 7rem; }
.n-skills-workspace .n-skills-rows { @apply min-w-0 divide-y divide-neutral-400 rounded-xl border border-neutral-400 bg-white dark:divide-neutral-500 dark:border-neutral-500 dark:bg-neutral-800; }
.n-skills-workspace .n-skills-row { @apply grid min-w-0 grid-cols-1 items-start gap-4 p-5; }
.n-skills-workspace .n-skills-identity,
.n-skills-workspace .n-skills-identity h2 { overflow-wrap: anywhere; @apply min-w-0; }
.n-skills-workspace .n-skills-identity h2 .n-workspace-link { @apply text-base font-semibold; }
.n-skills-workspace .n-skills-settings { @apply grid min-w-0 grid-cols-2 gap-3 text-sm; }
.n-skills-workspace .n-skills-settings div,
.n-skills-workspace .n-skills-settings dd { overflow-wrap: anywhere; @apply min-w-0; }
.n-skills-workspace .n-skills-settings dt { @apply text-xs text-neutral-600 dark:text-neutral-300; }
.n-skills-workspace .n-skills-settings dd { @apply mt-1 font-medium; }
.n-skills-workspace .n-skills-actions { @apply flex min-w-0 flex-wrap items-center gap-3; }
.n-skills-workspace .n-skills-actions form { @apply min-w-0 max-w-full; }
.n-skills-workspace .n-workspace-button { overflow-wrap: anywhere; white-space: normal; }
.n-skills-workspace .n-workspace-button:disabled { opacity: 1; }
.n-skills-workspace .n-skills-badge { @apply inline-block max-w-full rounded-full border border-neutral-500 bg-neutral-100 px-3 py-1 text-sm font-medium text-neutral-800 dark:bg-neutral-700 dark:text-neutral-100; }
.n-skills-workspace .n-skills-badge[data-skill-enabled="true"] { @apply border-green-700 bg-green-100 text-green-900 dark:border-green-300 dark:bg-green-900 dark:text-green-100; }
.n-skills-workspace .n-skills-detail { @apply space-y-4; }
.n-skills-workspace .n-skills-detail [data-skill-description] { overflow-wrap: anywhere; @apply min-w-0 space-y-3; }
.n-skills-workspace .n-skills-source { overflow-wrap: anywhere; white-space: pre-wrap; @apply max-w-full bg-neutral-100 text-sm leading-relaxed text-neutral-900 dark:bg-neutral-900 dark:text-neutral-100; }
.n-skills-workspace .n-skills-danger { @apply space-y-3; }
.n-skills-workspace .n-skills-danger h2 { @apply text-red-800 dark:text-red-200; }
.n-skills-workspace .n-skills-feedback { overflow-wrap: anywhere; @apply rounded-lg border border-green-700 bg-green-50 p-4 text-sm text-green-950 dark:border-green-300 dark:bg-green-950 dark:text-green-100; }
.n-skills-workspace .n-skills-feedback-error { @apply border-red-700 bg-red-50 text-red-900 dark:border-red-300 dark:bg-red-950 dark:text-red-100; }
@media (min-width: 768px) {
  .n-skills-workspace .n-skills-row { grid-template-columns: minmax(0, 1fr) auto; }
  .n-skills-workspace .n-skills-identity,
  .n-skills-workspace .n-skills-actions { grid-column: 1 / -1; }
}
@media (min-width: 1280px) {
  .n-skills-workspace .n-skills-row { grid-template-columns: minmax(0, 2fr) minmax(0, 1.4fr) auto minmax(0, 1.2fr); }
  .n-skills-workspace .n-skills-identity,
  .n-skills-workspace .n-skills-actions { grid-column: auto; }
}
@media (prefers-reduced-motion: reduce) {
  .n-skills-workspace a, .n-skills-workspace button, .n-skills-workspace summary { transition: none; animation: none; }
}
```

- [ ] **Step 9: Update only the localization assertions whose markup intentionally changed.** In `test/integration/localized_pages_test.rb`, Skills list/detail title assertions become `h1`; the hidden Disable-label assertion becomes a visible button assertion. Keep enum, tags, exact authored source, description, empty-state and mutation assertions unchanged. New/edit/error heading assertions are updated with the form in Task 5.

```ruby
assert_select "h1", text: "Compétences d’agent"
assert_select "button", text: "Désactiver la compétence"
assert_select "h1", text: skill.name
```

- [ ] **Step 10: Build, run GREEN and inspect actual screenshots before committing.** Remove the old `_skill_card` only after `grep` confirms the index was its only caller and now renders `_row`. Never weaken hit-testing/overflow assertions to obtain a pass; fix scoped layout issues instead.

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task4-build.log rails tailwindcss:build
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task4-green-http.log rails test test/controllers/agent_skills_workspace_scoping_test.rb test/controllers/agent_skills_workspace_states_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/agent_skills_workspace_content_test.rb test/integration/localized_pages_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task4-green-browser.log browser test/system/agent_skills_workspace_test.rb
git add app/helpers/agent_skills_workspace_helper.rb app/views/agent_skills app/views/layouts/application.html.erb app/views/application/_menu.html.erb app/views/accounts/_configuration.html.erb app/javascript/controllers/html_form_controller.js app/assets/stylesheets/nosia/skills_workspace.css app/assets/tailwind/application.css config/locales/en.nosia_skills_workspace.yml config/locales/fr.nosia_skills_workspace.yml test/controllers/agent_skills_workspace_shell_test.rb test/controllers/agent_skills_workspace_content_test.rb test/system/agent_skills_workspace_test.rb test/integration/localized_pages_test.rb
git commit -m "feat(skills): Add structured workspace rows and full details"
```

## Task 5: Grouped forms, retained input and linked validation recovery

**Create:** `app/views/agent_skills/_form_errors.html.erb`, `_field_error.html.erb`,
`app/javascript/controllers/form_errors_controller.js`,
`test/controllers/agent_skills_workspace_forms_test.rb`.
**Modify:** `_form.html.erb`, `new.html.erb`, `edit.html.erb`, workspace helper/CSS,
`test/system/agent_skills_workspace_test.rb`, `test/integration/localized_pages_test.rb`.
No model/parser or Source-form changes.

- [ ] **Step 1: Add request tests for both form families, derived errors and retained values.**

```ruby
require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsWorkspaceFormsTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures
  setup { sign_in_overview }

  test "new and edit forms have contextual actions and native labeled grouped controls" do
    first = workspace_skill(:skills_first)
    second = workspace_skill(:skills_second)
    [[new_agent_skill_path, agent_skills_path, false],
      [edit_agent_skill_path(first), agent_skill_path(first), true],
      [new_account_agent_skill_path(@second), account_agent_skills_path(@second), false],
      [edit_account_agent_skill_path(@second, second), account_agent_skill_path(@second, second), true]].each do |path, action, editing|
      before = workspace_records
      get path
      assert_response :success
      assert_select "main h1", count: 1
      assert_select "form[data-skill-form][action='#{action}'][data-controller~='form-errors'][data-controller~='html-form']"
      assert_select "textarea#agent_skill_skill_content[rows='20']"
      assert_select "textarea[required]", count: editing ? 0 : 1
      assert_select "[data-skill-saved-identity]", count: editing ? 1 : 0
      assert_select "input[name='agent_skill[name]'], textarea[name='agent_skill[description]'], select[name='agent_skill[account_id]']", count: 0
      assert_select "details[data-skill-advanced]:not([open]) input#agent_skill_priority"
      assert_select "input#agent_skill_enabled, select#agent_skill_execution_mode, select#agent_skill_trigger_mode", count: 3
      assert_select "[data-form-errors-target='summary']", count: 0
      assert_select "#drawer-right, #accordion-right-actions", count: 0
      assert_equal before, workspace_records
    end
  end

  test "invalid create retains source and controls despite parser RAG precedence" do
    source = "---\nname: 1bad\nrequires_rag_context: true\n---\n</textarea><script>unsafe()</script>\nKeep **this**."
    [agent_skills_path, account_agent_skills_path(@second)].each do |path|
      before = workspace_records
      post path, params: { agent_skill: { skill_content: source, priority: 101,
        execution_mode: "ruby", trigger_mode: "combined", enabled: "0", requires_rag_context: "0" } }
      assert_response :unprocessable_entity
      assert_select "textarea#agent_skill_skill_content", text: source
      assert_select "[data-skills-workspace] script", count: 0
      assert_select "form[data-skill-form][action='#{path}']"
      assert_select "details[data-skill-advanced][open]"
      assert_select "input#agent_skill_priority[value='101'][aria-invalid='true'][aria-describedby='agent_skill_priority_help agent_skill_priority_error']"
      assert_select "input#agent_skill_requires_rag_context[checked], input#agent_skill_enabled[checked]", count: 0
      assert_select "select#agent_skill_execution_mode option[value='ruby'][selected]"
      assert_select "select#agent_skill_trigger_mode option[value='combined'][selected]"
      assert_select "[data-form-errors-target='summary'][role='alert'][tabindex='-1'] a[href='#agent_skill_skill_content']"
      assert_select "[data-form-errors-target='summary'] a[href='#agent_skill_priority']"
      assert_select "#agent_skill_skill_content_error", text: /Name/
      assert_equal before, workspace_records
    end
  end

  test "failed edit preserves submitted source and saved identity without writes" do
    skill = workspace_skill(:skills_second)
    before = workspace_records
    source = workspace_source("changed-frontmatter")
    patch account_agent_skill_path(@second, skill), params: { agent_skill: { skill_content: source, priority: 101 } }
    assert_response :unprocessable_entity
    assert_select "textarea", text: source
    assert_select "[data-skill-saved-identity]", text: /#{Regexp.escape(skill.name)}/
    assert_select "form[action='#{account_agent_skill_path(@second, skill)}']"
    assert_equal before, workspace_records
    patch account_agent_skill_path(@second, skill), params: { agent_skill: { skill_content: "", priority: 12 } }
    assert_redirected_to account_agent_skills_path(@second)
    assert_equal "", skill.reload.skill_content
  end
end
```

- [ ] **Step 2: Add these browser workflows to the system class above its `private` section.** The server-priority test disables native validation only on the test form to exercise 422/focus recovery. The separate native-validation test keeps production constraints enabled and verifies that closed Advanced content is revealed before native focus.

```ruby
  test "create and edit stay in both route families without changing stored identity" do
    [[@first, agent_skills_path, new_agent_skill_path],
      [@second, account_agent_skills_path(@second), new_account_agent_skill_path(@second)]].each do |account, index, new_path|
      name = "browser-#{account.id}"
      source = workspace_source(name)
      visit new_path
      fill_in "agent_skill_skill_content", with: source
      focus_skill_by_tab("[data-skill-advanced] summary")
      page.send_keys(:enter)
      assert_selector "[data-skill-advanced][open]"
      fill_in "agent_skill_priority", with: 42
      find("[data-skill-save]").click
      assert_current_path index
      record = account.agent_skills.find_by!(name: name)
      assert_equal source, record.skill_content
      assert_equal 42, record.priority
      row = "[data-skill-id='#{record.id}']"
      within(row) { find("a[href$='/edit']").click }
      assert_field "agent_skill_skill_content", with: source
      assert_selector "[data-skill-saved-identity]", text: name
      fill_in "agent_skill_skill_content", with: workspace_source("new-frontmatter-name")
      find("[data-skill-save]").click
      assert_current_path index
      assert_equal name, record.reload.name
      assert_equal "Keep this description", record.description
      assert_equal workspace_source("new-frontmatter-name"), record.skill_content
    end
    assert_equal @first, @user.reload.first_account
    assert_no_enqueued_jobs
  end

  test "server errors focus the summary retain input and reopen a manually closed advanced field" do
    record = workspace_skill(:skills_second)
    before = record.attributes
    source = "---\nname: new-frontmatter-name\nrequires_rag_context: true\n---\nKeep the edited source."
    visit edit_account_agent_skill_path(@second, record)
    fill_in "agent_skill_skill_content", with: source
    find("[data-skill-advanced] summary").click
    fill_in "agent_skill_priority", with: 101
    uncheck "agent_skill_requires_rag_context"
    page.execute_script("document.querySelector('form[data-skill-form]').noValidate=true")
    find("[data-skill-save]").click
    assert_selector "[data-form-errors-target='summary']"
    assert_selector "[data-form-errors-target='summary']:focus"
    assert_field "agent_skill_skill_content", with: source
    assert_field "agent_skill_priority", with: "101"
    assert_unchecked_field "agent_skill_requires_rag_context"
    assert_selector "[data-skill-advanced][open]"
    find("[data-skill-advanced] summary").click
    assert_no_selector "[data-skill-advanced][open]"
    focus_skill_by_tab("[data-form-errors-target='summary'] a[href='#agent_skill_priority']")
    page.send_keys(:enter)
    assert_selector "[data-skill-advanced][open]"
    assert_selector "#agent_skill_priority:focus"
    assert_skills_focus
    page.save_screenshot("#{@evidence_dir}/advanced-validation.png")
    assert_equal before, record.reload.attributes
  end

  test "native validation reveals a closed invalid advanced field before focusing it" do
    before = workspace_records
    visit new_account_agent_skill_path(@second)
    fill_in "agent_skill_skill_content", with: workspace_source("native-validation")
    find("[data-skill-advanced] summary").click
    fill_in "agent_skill_priority", with: 101
    find("[data-skill-advanced] summary").click
    page.execute_script("window.skillsNativeRequests=[];document.addEventListener('turbo:before-fetch-request',e=>{if(e.target.matches('form[data-skill-form]'))window.skillsNativeRequests.push(e.detail.url.toString());})")
    find("[data-skill-save]").click
    assert_selector "[data-skill-advanced][open]"
    assert_selector "#agent_skill_priority:focus"
    assert_empty page.evaluate_script("window.skillsNativeRequests")
    assert_no_selector "[data-form-errors-target='summary']"
    assert_equal before, workspace_records
  end
```

- [ ] **Step 3: Run HTTP/browser REDs.**

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task5-red-http.log rails test test/controllers/agent_skills_workspace_forms_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task5-red-browser.log browser test/system/agent_skills_workspace_test.rb
```

Expected: old forms lack grouped native disclosure, contextual action, retained
RAG input and linked focus behavior. Do not change parser precedence to fix input
presentation. Fix any source-line-ending assumption only after characterizing the
existing native submission behavior; never silently normalize stored instructions.

- [ ] **Step 4: Add complete input/error presentation helpers.** The submitted-values snapshot was defined in Task 2; these methods read it only after a failed save, never write it back to the model.

```ruby
  # @param skill [AgentSkill] Form object, possibly invalid
  # @param attribute [Symbol] An existing permitted field
  # @return [Object] Submitted value on 422, otherwise model value
  def skill_workspace_value(skill, attribute)
    if @submitted_skill_values&.key?(attribute.to_s)
      @submitted_skill_values.fetch(attribute.to_s)
    else
      skill.public_send(attribute)
    end
  end

  # @param attribute [Symbol] Model error attribute
  # @return [Symbol, nil] Editable field, mapping frontmatter identity to content
  def skill_workspace_error_attribute(attribute)
    if [:name, :description].include?(attribute.to_sym)
      :skill_content
    elsif [:skill_content, :execution_mode, :trigger_mode, :priority, :requires_rag_context, :enabled].include?(attribute.to_sym)
      attribute.to_sym
    end
  end

  # @param skill [AgentSkill] Form object
  # @param attribute [Symbol] Editable field
  # @return [Array<String>] Connected model error messages
  def skill_workspace_field_errors(skill, attribute)
    skill.errors.select { |error| skill_workspace_error_attribute(error.attribute) == attribute }.map(&:full_message)
  end

  # @param form [ActionView::Helpers::FormBuilder] Current form
  # @param attribute [Symbol] Editable field
  # @return [Hash] Accessible hint/error attributes
  def skill_workspace_field_options(form, attribute)
    invalid = skill_workspace_field_errors(form.object, attribute).any?
    ids = [form.field_id(attribute, :help)]
    ids << form.field_id(attribute, :error) if invalid
    { aria: { invalid: invalid ? "true" : nil, describedby: ids.join(" ") } }
  end

  # @param skill [AgentSkill] Form object
  # @return [Boolean] Whether advanced content must be exposed
  def skill_workspace_advanced_invalid?(skill)
    [:priority, :requires_rag_context].any? { |attribute| skill.errors.include?(attribute) }
  end
```

- [ ] **Step 5: Create the generic error-focus controller and partials.** It reveals native-invalid fields as well as linked server errors, with no global listeners, source parsing, fetch calls or client data state. Stimulus owns declarative action cleanup.

```javascript
// app/javascript/controllers/form_errors_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["summary"]

  summaryTargetConnected(summary) {
    summary.focus()
  }

  revealInvalid(event) {
    for (let disclosure = event.target.closest("details"); disclosure; disclosure = disclosure.parentElement?.closest("details")) disclosure.open = true
  }

  focusField(event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const link = event.target.closest("a[data-error-field]")
    if (!link || !this.hasSummaryTarget || !this.summaryTarget.contains(link)) return
    const field = document.getElementById(link.dataset.errorField)
    if (field && this.element.contains(field)) {
      event.preventDefault()
      this.revealInvalid({ target: field })
      field.focus()
    }
  }
}
```

```erb
<%# app/views/agent_skills/_form_errors.html.erb %>
<%# locals: (form:) %>
<% if form.object.errors.any? %>
  <div id="<%= form.field_id(:errors) %>" class="n-skills-errors" data-form-errors-target="summary" role="alert" tabindex="-1" aria-labelledby="<%= form.field_id(:errors, :title) %>">
    <h2 id="<%= form.field_id(:errors, :title) %>"><%= t("nosia.skills.errors", count: form.object.errors.count) %></h2>
    <ul class="!list-none">
      <% form.object.errors.each do |error| %>
        <li>
          <% attribute = skill_workspace_error_attribute(error.attribute) %>
          <% if attribute %>
            <%= link_to error.full_message, "##{form.field_id(attribute)}", class: "n-workspace-link", data: { error_field: form.field_id(attribute) } %>
          <% else %>
            <%= error.full_message %>
          <% end %>
        </li>
      <% end %>
    </ul>
  </div>
<% end %>
```

```erb
<%# app/views/agent_skills/_field_error.html.erb %>
<%# locals: (form:, attribute:) %>
<% errors = skill_workspace_field_errors(form.object, attribute) %>
<% if errors.any? %><p id="<%= form.field_id(attribute, :error) %>" class="n-skills-field-error"><%= errors.to_sentence %></p><% end %>
```

- [ ] **Step 6: Replace the shared form and new/edit templates.** All real fields retain their names and enum values; Advanced visibility never disables them. Checkbox casting is presentation only. The new-record `required` marker does not impose an edit validation.

```erb
<%# app/views/agent_skills/_form.html.erb %>
<%# locals: (agent_skill:) %>
<%= form_with model: skill_workspace_form_model(agent_skill), class: "n-skills-form", data: { skill_form: true, controller: "form-errors html-form", action: "click->form-errors#focusField invalid->form-errors#revealInvalid:capture turbo:before-fetch-request->html-form#requestHTML" } do |f| %>
  <%= render "agent_skills/form_errors", form: f %>
  <% if agent_skill.persisted? %>
    <section class="n-workspace-panel" data-skill-saved-identity>
      <h2 class="n-workspace-section-title"><%= t("nosia.skills_workspace.saved_identity") %></h2>
      <p><strong><%= AgentSkill.human_attribute_name(:name) %>:</strong> <%= agent_skill.attribute_in_database(:name) %></p>
      <p><strong><%= t("nosia.skills.description") %>:</strong> <%= agent_skill.attribute_in_database(:description) %></p>
      <p class="n-workspace-help"><%= t("nosia.skills_workspace.identity_note") %></p>
    </section>
  <% end %>
  <div class="n-skills-form-layout">
    <section class="n-workspace-panel">
      <h2 class="n-workspace-section-title"><%= t("nosia.skills_workspace.definition") %></h2>
      <%= f.label :skill_content, t(agent_skill.new_record? ? "nosia.skills.required_content" : "nosia.skills.content"), class: "n-skills-label" %>
      <%= f.text_area :skill_content, **skill_workspace_field_options(f, :skill_content), value: skill_workspace_value(agent_skill, :skill_content), rows: 20, required: agent_skill.new_record?, class: "n-skills-input n-skills-editor", placeholder: t("nosia.skills.content_placeholder") %>
      <p id="<%= f.field_id(:skill_content, :help) %>" class="n-workspace-help"><%= t("nosia.skills_workspace.source_help") %> <%= t("nosia.skills_workspace.name_help") %></p>
      <%= render "agent_skills/field_error", form: f, attribute: :skill_content %>
    </section>
    <fieldset class="n-workspace-panel n-skills-behavior">
      <legend class="n-workspace-section-title"><%= t("nosia.skills_workspace.behavior") %></legend>
      <div>
        <%= f.label :execution_mode, t("nosia.skills.execution_mode"), class: "n-skills-label" %>
        <%= f.select :execution_mode, options_for_select(AgentSkill.execution_modes.keys.map { |value| [t("nosia.skills.execution.#{value}"), value] }, skill_workspace_value(agent_skill, :execution_mode)), {}, skill_workspace_field_options(f, :execution_mode).merge(class: "n-skills-input") %>
        <p id="<%= f.field_id(:execution_mode, :help) %>" class="n-workspace-help"><%= t("nosia.skills_workspace.execution_help") %></p>
        <%= render "agent_skills/field_error", form: f, attribute: :execution_mode %>
      </div>
      <div>
        <%= f.label :trigger_mode, t("nosia.skills.trigger_mode"), class: "n-skills-label" %>
        <%= f.select :trigger_mode, options_for_select(AgentSkill.trigger_modes.keys.map { |value| [t("nosia.skills.trigger.#{value}"), value] }, skill_workspace_value(agent_skill, :trigger_mode)), {}, skill_workspace_field_options(f, :trigger_mode).merge(class: "n-skills-input") %>
        <p id="<%= f.field_id(:trigger_mode, :help) %>" class="n-workspace-help"><%= t("nosia.skills_workspace.trigger_help") %></p>
        <%= render "agent_skills/field_error", form: f, attribute: :trigger_mode %>
      </div>
      <div>
        <label for="<%= f.field_id(:enabled) %>" class="n-skills-check"><%= f.check_box :enabled, **skill_workspace_field_options(f, :enabled), checked: ActiveModel::Type::Boolean.new.cast(skill_workspace_value(agent_skill, :enabled)) %><span><%= t("nosia.skills.enabled") %></span></label>
        <p id="<%= f.field_id(:enabled, :help) %>" class="n-workspace-help"><%= t("nosia.skills_workspace.availability_note") %></p>
        <%= render "agent_skills/field_error", form: f, attribute: :enabled %>
      </div>
      <%= tag.details class: "n-skills-advanced", open: skill_workspace_advanced_invalid?(agent_skill), data: { skill_advanced: true } do %>
        <summary><%= t("nosia.skills_workspace.advanced") %></summary>
        <div>
          <%= f.label :priority, t("nosia.skills.priority"), class: "n-skills-label" %>
          <%= f.number_field :priority, **skill_workspace_field_options(f, :priority), value: skill_workspace_value(agent_skill, :priority), in: 0..100, step: 1, class: "n-skills-input" %>
          <p id="<%= f.field_id(:priority, :help) %>" class="n-workspace-help"><%= t("nosia.skills.priority_help") %></p>
          <%= render "agent_skills/field_error", form: f, attribute: :priority %>
        </div>
        <div>
          <label for="<%= f.field_id(:requires_rag_context) %>" class="n-skills-check"><%= f.check_box :requires_rag_context, **skill_workspace_field_options(f, :requires_rag_context), checked: ActiveModel::Type::Boolean.new.cast(skill_workspace_value(agent_skill, :requires_rag_context)) %><span><%= t("nosia.skills.requires_rag") %></span></label>
          <p id="<%= f.field_id(:requires_rag_context, :help) %>" class="n-workspace-help"><%= t("nosia.skills_workspace.rag_help") %></p>
          <%= render "agent_skills/field_error", form: f, attribute: :requires_rag_context %>
        </div>
      <% end %>
    </fieldset>
  </div>
  <div class="n-skills-actions">
    <%= f.submit t(agent_skill.persisted? ? "nosia.skills.update" : "nosia.skills.create"), class: "n-workspace-button n-workspace-primary", data: { skill_save: true, turbo_submits_with: t(agent_skill.persisted? ? "nosia.skills_workspace.updating" : "nosia.skills_workspace.saving") } %>
    <%= link_to t("nosia.actions.cancel"), skill_workspace_index_path, class: "n-workspace-link" %>
  </div>
<% end %>
```

```erb
<%# app/views/agent_skills/new.html.erb %>
<div class="n-workspace n-skills-workspace" data-skills-workspace>
  <%= render "agent_skills/header", title: t("nosia.skills.new"), current: t("nosia.skills.new"), back_path: skill_workspace_index_path %>
  <%= render "agent_skills/feedback" %>
  <%= render "agent_skills/form", agent_skill: @agent_skill %>
</div>
```

```erb
<%# app/views/agent_skills/edit.html.erb %>
<div class="n-workspace n-skills-workspace" data-skills-workspace>
  <%= render "agent_skills/header", title: t("nosia.skills.edit_title"), current: t("nosia.skills.edit_title"), back_path: skill_workspace_index_path %>
  <%= render "agent_skills/feedback" %>
  <%= render "agent_skills/form", agent_skill: @agent_skill %>
</div>
```

- [ ] **Step 7: Append form-only styles, preserving existing Sources/Profile behavior.** Invalid borders must beat neutral field styles in both themes.

```css
.n-skills-workspace .n-skills-form { @apply space-y-6; }
.n-skills-workspace .n-skills-form-layout { @apply grid min-w-0 grid-cols-1 items-start gap-6; }
.n-skills-workspace .n-skills-form .n-workspace-panel { @apply min-w-0 space-y-3; }
.n-skills-workspace .n-skills-form [data-skill-saved-identity] p { overflow-wrap: anywhere; }
.n-skills-workspace .n-skills-label { @apply block text-sm font-medium; }
.n-skills-workspace .n-skills-input { @apply block min-h-11 w-full min-w-0 rounded-md border border-neutral-500 bg-white px-3 py-2 text-sm text-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:border-neutral-400 dark:bg-neutral-900 dark:text-neutral-100 dark:focus:outline-green-300; }
.n-skills-workspace .n-skills-editor { @apply resize-y font-mono leading-relaxed; }
.n-skills-workspace .n-skills-editor::placeholder { @apply text-neutral-600 opacity-100 dark:text-neutral-300; }
.n-skills-workspace .n-skills-input[aria-invalid="true"] { @apply border-red-700 dark:border-red-300; }
.n-skills-workspace .n-skills-check { @apply flex min-h-11 cursor-pointer items-center gap-3 text-sm font-medium; }
.n-skills-workspace .n-skills-check input { @apply h-5 w-5 shrink-0 accent-green-700 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:focus:outline-green-300; }
.n-skills-workspace .n-skills-advanced { @apply space-y-4 border-t border-neutral-500 pt-4 dark:border-neutral-400; }
.n-skills-workspace .n-skills-advanced summary { overflow-wrap: anywhere; @apply min-h-11 cursor-pointer rounded-md px-2 py-3 text-sm font-semibold focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:focus:outline-green-300; }
.n-skills-workspace .n-skills-errors { overflow-wrap: anywhere; @apply rounded-lg border border-red-700 bg-red-50 p-4 text-red-900 focus:outline-2 focus:outline-offset-2 focus:outline-red-700 dark:border-red-300 dark:bg-red-950 dark:text-red-100 dark:focus:outline-red-300; }
.n-skills-workspace .n-skills-errors h2 { @apply font-semibold; }
.n-skills-workspace .n-skills-field-error { overflow-wrap: anywhere; @apply text-sm text-red-800 dark:text-red-200; }
@media (min-width: 1280px) {
  .n-skills-workspace .n-skills-form-layout { grid-template-columns: minmax(0, 2fr) minmax(18rem, 1fr); }
}
```

- [ ] **Step 8: Update the intentional form-heading assertions in localized_pages_test.** Preserve existing French labels, machine options, placeholder, source equality and input submit value checks. The old error heading now belongs to the linked summary.

```ruby
assert_select "h1", text: "Créer une compétence d’agent"
assert_select "h1", text: "Modifier la compétence d’agent"
assert_select "[data-form-errors-target='summary'] h2", text: heading
```

- [ ] **Step 9: Build, run GREEN and inspect the validation screenshot, then commit.** Test both body preservation and actual persisted RAG behavior; the projection must not become a parser override.

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task5-build.log rails tailwindcss:build
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task5-green-http.log rails test test/controllers/agent_skills_workspace_forms_test.rb test/controllers/agent_skills_workspace_scoping_test.rb test/controllers/agent_skills_workspace_states_test.rb test/controllers/agent_skills_workspace_content_test.rb test/models/agent_skill_presentation_contract_test.rb test/integration/localized_pages_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task5-green-browser.log browser test/system/agent_skills_workspace_test.rb
git add app/helpers/agent_skills_workspace_helper.rb app/views/agent_skills app/javascript/controllers/form_errors_controller.js app/assets/stylesheets/nosia/skills_workspace.css test/controllers/agent_skills_workspace_forms_test.rb test/system/agent_skills_workspace_test.rb test/integration/localized_pages_test.rb
git commit -m "feat(skills): Group forms and preserve accessible validation recovery"
```

## Task 6: API compatibility, adverse paths and full browser evidence

**Create:** `test/integration/agent_skills_api_compatibility_test.rb`.
**Modify:** `test/controllers/agent_skills_workspace_states_test.rb`,
`test/controllers/agent_skills_workspace_forms_test.rb`,
`test/system/agent_skills_workspace_test.rb`.

This is coverage hardening over the completed implementation, not a reason to
manufacture REDs by temporarily damaging working code. Record first-PASS checks
honestly. A real failure blocks the task: use systematic-debugging, add a focused
regression, and review a narrow correction; do not change parser/API behavior or
weaken assertions to make the matrix pass.

- [ ] **Step 1: Add exact API compatibility tests without editing API controllers.** Reset only the API's dedicated in-memory test rate store; use existing public fixture token values, not real credentials.

```ruby
require "test_helper"
require_relative "../support/agent_skills_workspace_fixtures"

class AgentSkillsApiCompatibilityTest < ActionDispatch::IntegrationTest
  include AgentSkillsWorkspaceFixtures

  setup do
    Api::V1::ApplicationController::RATE_LIMIT_STORE.clear
    @headers = { "Authorization" => "Bearer overview-second-secret", "Accept-Language" => "fr" }
  end

  teardown { Api::V1::ApplicationController::RATE_LIMIT_STORE.clear }

  test "API retains JSON account scope stored source and English machine fields" do
    get api_v1_agent_skills_path, headers: @headers, as: :json
    assert_response :success
    assert_equal @second.agent_skills.order(priority: :desc, created_at: :asc).pluck(:id), response.parsed_body.map { |row| row.fetch("id") }
    skill = workspace_skill(:skills_second)
    get api_v1_agent_skill_path(skill), headers: @headers, as: :json
    assert_response :success
    assert_equal skill.skill_content, response.parsed_body.fetch("skill_content")
    assert_equal "llm", response.parsed_body.fetch("execution_mode")
    assert_equal @second.id, response.parsed_body.fetch("account_id")
    get api_v1_agent_skill_path(workspace_skill(:skills_first)), headers: @headers, as: :json
    assert_response :not_found
  end

  test "API CRUD keeps accepted fields response statuses and parser precedence" do
    source = workspace_source("api-workspace")
    work_before = [AgentSkillExecution.count, TokenUsage.count]
    assert_no_enqueued_jobs do
      post api_v1_agent_skills_path, params: { agent_skill: { skill_content: source, priority: 15, account_id: @foreign.id } }, headers: @headers, as: :json
      assert_response :created
      id = response.parsed_body.fetch("id")
      skill = @second.agent_skills.find(id)
      assert_equal source, skill.skill_content
      patch api_v1_agent_skill_path(skill), params: { agent_skill: { name: "api-renamed", description: "Explicit accepted description", execution_mode: "ruby", trigger_mode: "combined", enabled: false, requires_rag_context: true, priority: 16 } }, headers: @headers, as: :json
      assert_response :success
      assert_equal ["api-renamed", "Explicit accepted description", "ruby", "combined", false, true, 16],
        skill.reload.attributes.values_at("name", "description", "execution_mode", "trigger_mode", "enabled", "requires_rag_context", "priority")
      assert_equal source, skill.skill_content
      delete api_v1_agent_skill_path(skill), headers: @headers, as: :json
      assert_response :no_content
      assert_not @second.agent_skills.exists?(id)
    end
    assert_equal work_before, [AgentSkillExecution.count, TokenUsage.count]
  end

  test "invalid API credentials still return unauthorized" do
    get api_v1_agent_skills_path, headers: { "Authorization" => "Bearer not-a-token" }, as: :json
    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
  end
end
```

- [ ] **Step 2: Add adverse-state and error-escaping tests to the existing request classes.** Insert the first two tests in `AgentSkillsWorkspaceStatesTest` and the third in `AgentSkillsWorkspaceFormsTest`.

```ruby
  test "aborted destruction reports failure and rolls back dependent deletion" do
    before = workspace_records
    blocker = ->(record) { record.errors.add(:base, "Deletion blocked"); throw :abort }
    AgentSkill.set_callback(:destroy, :before, blocker)
    begin
      delete account_agent_skill_path(@second, workspace_skill(:skills_second))
      assert_redirected_to account_agent_skills_path(@second)
      assert_equal "Deletion blocked", flash[:alert]
      assert_nil flash[:notice]
      assert_equal before, workspace_records
    ensure
      AgentSkill.skip_callback(:destroy, :before, blocker)
    end
  end

  test "unexpected query failure stays observable and tenant context is restored" do
    failure = ->(*event) do
      sql = event.last.fetch(:sql)
      raise ActiveRecord::StatementInvalid, "Skills failure probe" if sql.match?(/\ASELECT/i) && sql.include?('"agent_skills"')
    end
    ActsAsTenant.with_tenant(@foreign) do
      error = assert_raises(ActiveRecord::StatementInvalid, ActionView::Template::Error) do
        ActiveSupport::Notifications.subscribed(failure, "sql.active_record") { get account_agent_skills_path(@second) }
      end
      assert_includes error.message, "Skills failure probe"
      assert_equal @foreign, ActsAsTenant.current_tenant
    end
  end
```

```ruby
  test "base errors remain escaped summary text and do not invent an input target" do
    skill = workspace_skill(:skills_second)
    skill.errors.add(:base, "<script>unsafe()</script>")
    form = ActionView::Helpers::FormBuilder.new(:agent_skill, skill, controller.view_context, {})
    html = ApplicationController.render(partial: "agent_skills/form_errors", locals: { form: form })
    fragment = Nokogiri::HTML.fragment(html)
    assert_select fragment, "[role='alert'] li", text: "<script>unsafe()</script>"
    assert_select fragment, "script, li a", count: 0
    get "/accounts/#{@second.id}/agent_skills/not-a-skill"
    assert_response :not_found
  end
```

- [ ] **Step 3: Add state/deletion and pending-response browser checks above `private`.** The held fetch response is a test-only observation point, restored immediately; it does not replace the real server request or any model result.

```ruby
  test "state actions and cancelled or confirmed deletion preserve both route families" do
    [[workspace_skill(:skills_first), @first, agent_skills_path],
      [workspace_skill(:skills_second), @second, account_agent_skills_path(@second)]].each do |skill, account, index|
      detail = account == @first ? agent_skill_path(skill) : account_agent_skill_path(account, skill)
      source = skill.skill_content
      visit index
      within("[data-skill-id='#{skill.id}']") { find("[data-skill-state-action]").click }
      assert_current_path index
      assert_selector "[data-skill-id='#{skill.id}'] [data-skill-enabled='false']"
      visit detail
      find("[data-skill-state-action]").click
      assert_current_path index
      assert skill.reload.enabled?
      assert_equal source, skill.skill_content
      visit detail
      page.execute_script(<<~JS)
        window.skillsDeleteRequests=[];
        document.addEventListener('turbo:before-fetch-request',event=>{
          if(event.target.matches('form[data-skill-delete]'))window.skillsDeleteRequests.push(event.detail.url.toString());
        });
      JS
      confirmation = /#{Regexp.escape(skill.name)}.*#{Regexp.escape(account.name)}/
      before = skill.attributes
      dismiss_confirm(confirmation) { find("button[data-skill-delete]").click }
      assert_equal before, skill.reload.attributes
      assert_empty page.evaluate_script("window.skillsDeleteRequests")
      accept_confirm(confirmation) { find("button[data-skill-delete]").click }
      assert_current_path index
      assert_equal 1, page.evaluate_script("window.skillsDeleteRequests.length")
      assert_not AgentSkill.exists?(skill.id)
    end
    assert_equal @first, @user.reload.first_account
    assert_no_enqueued_jobs
  end

  test "pending form submission has one disabled progress control until response confirmation" do
    skill = workspace_skill(:skills_second)
    visit edit_account_agent_skill_path(@second, skill)
    page.execute_script(<<~JS)
      const original=window.fetch;
      window.fetch=async(...args)=>{
        window.fetch=original;
        const response=await original(...args);
        await new Promise(resolve=>{window.skillsRelease=resolve;document.documentElement.dataset.skillsHeld='true';});
        return response;
      };
    JS
    find("[data-skill-save]").click
    assert_selector "[data-skill-save][disabled][value='Updating…']"
    assert_selector "html[data-skills-held='true']", visible: :all
    assert_selector "form[data-skill-form]", count: 1
    page.execute_script("window.skillsRelease()")
    assert_current_path account_agent_skills_path(@second)
    assert_selector "[data-skills-feedback][role='status']"
  ensure
    page.execute_script("window.skillsRelease?.()") if page.current_url.start_with?("http")
  end
```

The deletion form and its button are both marked; the click selector above
intentionally selects the button, not an ambiguous form/control match.

- [ ] **Step 4: Add the complete locale/theme/page/viewport matrix test and contrast helper.** It covers 96 normal states: two route families × four page kinds × two locales × two themes × three viewport sizes. Save a screenshot and contrast measurements for every state. Long fixture text is test data, not a production mutation.

```ruby
  test "all Skills page kinds fit locales themes long content and responsive viewports" do
    first = workspace_skill(:skills_first)
    second = workspace_skill(:skills_second)
    [first, second].each do |skill|
      name = "SkillIdentifier" * 12
      skill.update_columns(name: name, description: "Detailed authored description. " * 40,
        metadata: { "tags" => ["LongAuthoredTag" * 30, "English"] },
        skill_content: workspace_source(name) + "\n" + "unbrokensourcetext" * 80)
    end
    @second.update_columns(name: "CompteDeRecherche" * 12)
    before = workspace_records
    states = []
    paths = {
      legacy_list: agent_skills_path, legacy_new: new_agent_skill_path,
      legacy_detail: agent_skill_path(first), legacy_edit: edit_agent_skill_path(first),
      scoped_list: account_agent_skills_path(@second), scoped_new: new_account_agent_skill_path(@second),
      scoped_detail: account_agent_skill_path(@second, second), scoped_edit: edit_account_agent_skill_path(@second, second)
    }
    assert_no_enqueued_jobs do
      %w[en fr].each do |locale|
        select locale.upcase, from: "language_preference_locale"
        paths.each do |kind, path|
          [[375, 812], [768, 1024], [1440, 1000]].each do |width, height|
            resize_skills_viewport(width, height)
            %w[light dark].each do |theme|
              visit path
              set_skills_theme(theme)
              assert_selector "html[lang='#{locale}']", visible: :all
              assert_skills_layout
              selector = if page.has_selector?("[data-skill-advanced] summary", wait: 0)
                "[data-skill-advanced] summary"
              else
                "[data-skills-workspace] a.n-workspace-link"
              end
              focus_skill_by_tab(selector)
              if selector.include?("summary")
                page.send_keys(:enter)
                assert_selector "[data-skill-advanced][open]"
              end
              assert_skills_focus
              measure_skills_contrast
              name = "#{kind}-#{locale}-#{width}-#{theme}"
              page.save_screenshot("#{@evidence_dir}/#{name}.png")
              states << { page: kind, locale: locale, theme: theme, viewport: [width, height], screenshot: "#{name}.png" }
              File.write("#{@evidence_dir}/matrix.json", { states: states, native_200_percent_zoom: "UNVERIFIED" }.to_json)
            end
          end
        end
      end
      assert_equal 96, states.length
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [{ name: "prefers-reduced-motion", value: "reduce" }])
      assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
      transitions = page.evaluate_script("Array.from(document.querySelectorAll('[data-skills-workspace] a,[data-skills-workspace] button,[data-skills-workspace] summary')).map(e=>getComputedStyle(e).transitionDuration)")
      assert transitions.all? { |duration| duration == "0s" }
    end
    assert_equal before, workspace_records
    assert_equal @first, @user.reload.first_account
  end
```

Add this private method to the system class. Canvas resolves modern CSS color
syntax and alpha composition. Unsupported opacity/gradient composition fails
explicitly instead of pretending it was measured.

```ruby
    def measure_skills_contrast
      samples = page.evaluate_script(<<~JS)
        (()=>{
          const root=document.querySelector('[data-skills-workspace]'),canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const chain=[];for(let a=e;a;a=a.parentElement)chain.unshift(a);return chain.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured gradient/opacity');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          function visible(e){return e.getClientRects().length>0&&getComputedStyle(e).visibility==='visible';}
          function measure(e,property,minimum,parent=false,pseudo=null){const s=getComputedStyle(e,pseudo),bg=background(parent?e.parentElement:e),fg=blend(rgba(s[property]),bg),a=luminance(fg),b=luminance(bg);return {tag:e.tagName,id:e.id,property,pseudo,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};}
          const text=Array.from(root.querySelectorAll('h1,h2,p,dt,dd,label,summary,a,button,input:not([type=hidden]):not([type=checkbox]),textarea,select,.n-skills-badge')).filter(visible);
          if(!text.length)throw new Error('No visible text samples');
          const rows=text.map(e=>measure(e,'color',4.5));
          root.querySelectorAll('textarea[placeholder]').forEach(e=>{if(visible(e)&&!e.value)rows.push(measure(e,'color',4.5,false,'::placeholder'));});
          root.querySelectorAll('.n-workspace-button,.n-skills-input').forEach(e=>{if(visible(e))rows.push(measure(e,'borderTopColor',3,true));});
          if(!root.contains(document.activeElement))throw new Error('Missing focused workspace action');
          rows.push(measure(document.activeElement,'outlineColor',3,true));
          return rows;
        })()
      JS
      samples.each { |sample| assert_operator sample.fetch("ratio"), :>=, sample.fetch("minimum"), sample.to_json }
      File.open("#{@evidence_dir}/contrast.jsonl", "a") do |file|
        file.puts({ viewport: page.evaluate_script("[innerWidth,innerHeight]"),
          locale: find("html", visible: :all)["lang"],
          dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: samples }.to_json)
      end
    end
```

- [ ] **Step 5: Check empty/setup and invalid forms in both locales/themes too.** Add this system test; it logs in the existing no-account fixture only after the valid-account checks. Do not create users via factories or persist a locale/account preference.

```ruby
  test "empty setup and validation feedback stay readable in both locales and themes" do
    resize_skills_viewport(375, 812)
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      %w[light dark].each do |theme|
        visit account_agent_skills_path(@empty)
        set_skills_theme(theme)
        assert_selector "[data-skills-empty]"
        assert_skills_layout
        focus_skill_by_tab("[data-skills-empty] a")
        assert_skills_focus
        measure_skills_contrast
        visit edit_account_agent_skill_path(@second, workspace_skill(:skills_second))
        find("[data-skill-advanced] summary").click
        fill_in "agent_skill_priority", with: 101
        page.execute_script("document.querySelector('form[data-skill-form]').noValidate=true")
        find("[data-skill-save]").click
        assert_selector "[data-form-errors-target='summary']"
        assert_skills_layout
        assert_selector "[data-form-errors-target='summary']:focus"
        measure_skills_contrast
        page.save_screenshot("#{@evidence_dir}/errors-#{locale}-#{theme}.png")
      end
    end
    Capybara.reset_sessions!
    visit root_url
    fill_in "email", with: experience(:users, :overview_no_account).email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      %w[light dark].each do |theme|
        visit agent_skills_path
        set_skills_theme(theme)
        assert_selector "[data-skills-setup]"
        assert_skills_layout
        focus_skill_by_tab("[data-skills-setup] a[href='#{accounts_path}']")
        assert_skills_focus
        measure_skills_contrast
        page.save_screenshot("#{@evidence_dir}/setup-#{locale}-#{theme}.png")
      end
    end
  end
```

- [ ] **Step 6: Run compatibility/adverse/browser coverage and inspect artifacts.** Expected PASS without API/model/parser edits. Open screenshots from every page kind in both themes, normal/error/empty/setup states and narrow layouts; record which files were actually inspected. Do not call generated-but-unopened screenshots a visual review.

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task6-http.log rails test test/integration/agent_skills_api_compatibility_test.rb test/controllers/agent_skills_workspace_states_test.rb test/controllers/agent_skills_workspace_forms_test.rb test/models/agent_skill_presentation_contract_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-task6-browser.log browser test/system/agent_skills_workspace_test.rb
```

- [ ] **Step 7: Verify native 200% browser zoom separately.** Use a browser/tool that can set actual browser zoom and shows its 200% state. Check legacy/scoped list, details, new/edit, advanced validation recovery and bottom-navigation clearance with EN/FR and both themes. Record route, locale/theme, browser zoom evidence, viewport/screenshot and observed result. CSS `zoom`, transform, CDP page scaling and viewport resizing are not substitutes. If native zoom cannot be exercised, record **UNVERIFIED**, leave this check incomplete and disclose it for review/user decision; never count the 96-state matrix as native zoom evidence.

- [ ] **Step 8: Commit tests only after coverage results are inspected.**

```bash
git add test/integration/agent_skills_api_compatibility_test.rb test/controllers/agent_skills_workspace_states_test.rb test/controllers/agent_skills_workspace_forms_test.rb test/system/agent_skills_workspace_test.rb
git commit -m "test(skills): Cover API compatibility and browser workspace flows"
```

## Task 7: Document the delivered workspace and compatibility limits

**Create:** `docs/agent-skills-workspace.md`.
**Modify:** `docs/README.md`, `docs/DIAGRAMS.md`.

- [ ] **Step 1: Add the complete guide below.** This is documentation-only: no artificial RED, source rewrite or application test claim. Reference actual execution evidence rather than inventing passing counts.

````markdown
# Agent skills workspace

## Account context

`/agent_skills` manages the current default account and names it explicitly.
`/accounts/:account_id/agent_skills` manages the account in that URL after a
membership check on every request. Settings opens the default-account tool;
the account overview's Agent skills link opens the scoped tool.

Creating, editing, viewing, enabling, disabling and deleting retain that route
family and account. Back and Cancel return to its list. Navigation never sets a
persistent account preference; submitted account IDs cannot move a skill.
Foreign, revoked or invalid account/record URLs return 404. A missing legacy
default account instead gets setup guidance on list/new.

## Managing skills

Rows show a description excerpt, tags, execution/trigger settings, priority,
RAG requirement and Enabled/Disabled. Ordering remains priority descending,
creation ascending. Counts refer only to the displayed account.

Use View for the full description/settings and complete raw SKILL.md. Edit opens
the native source form. Enable/Disable saves explicit intent and reports the
confirmed result; it does not execute or verify the skill. Ruby still requires
its configured implementation class.

Deletion lives on details. Its confirmation names the skill/account and explains
that recorded executions are deleted too. Cancelling does nothing. The existing
PATCH `/agent_skills/:id/toggle` remains available for compatibility; new browser
controls use POST/DELETE enablement resources instead.

## Writing and editing

The definition remains plain SKILL.md text with YAML frontmatter. Examples are
placeholders, not inserted content. Execution mode, trigger mode and Enabled are
visible; priority and RAG sit in Advanced settings. Collapsing Advanced does not
remove its submitted fields.

New defaults remain LLM, Explicit, Enabled, priority 0 and RAG off. Content is
required on creation; existing edit validation has not been tightened. Failed
validation retains submitted source/settings, exposes advanced errors, focuses
a linked summary and leaves the saved record unchanged.

The existing parser merges metadata but fills name, description and mode fields
only when nil. Editing frontmatter does not automatically rename or re-describe
an existing skill; the saved identity is shown read-only. There is no synchronized
preview or automatic source reformatting. RAG retains its existing metadata /
checkbox precedence: keep both consistent and clear any frontmatter requirement
as well when turning it off. Unexpected parser exceptions have not been redesigned.

Interface labels/help/messages support English/French and light/dark. Authored
names, descriptions, tags, instructions and machine enum values are not translated.
The API, runtime invocation and model validation behavior remain unchanged.

## Verification

The [specification](superpowers/specs/2026-10-26-agent-skills-workspace-ui-ux-design.md)
defines the account/content/accessibility contract. The
[implementation plan](superpowers/plans/2026-10-26-agent-skills-workspace-ui-ux.md)
records the actual execution revision, commands, exits, review results and any
limitations when implementation completes. Mockups are not browser-test evidence;
native 200% browser zoom is a separate check from viewport resizing.
````

- [ ] **Step 2: Add one development link after Token usage in `docs/README.md`, without changing unrelated text.**

```markdown
- [Agent skills workspace](agent-skills-workspace.md) — default/scoped management, structured rows, raw source editing, parser limits and accessible feedback.
```

- [ ] **Step 3: Add this standalone diagram section to `docs/DIAGRAMS.md` near the other workspace entry-point sections.**

````markdown
## Agent Skills Workspace Entry Points

```text
Settings -> /agent_skills (default account)
Account hub -> /accounts/:account_id/agent_skills (authorized URL account)
                              |
                     Structured rows + counts
                       |       |        |
                    Create   View     Enable/Disable
                       |       |        |
                       |   Full details + saved raw SKILL.md
                       |       |                     |
                       +---- Edit                Confirm Delete
                              |                     |
                  Source + Behavior + Advanced     Existing execution cleanup
                              |                     |
                   Save -> same-context list <-----+
                   422 -> retained form + linked errors
```

URL account context is not a global preference. Enabled is not verified execution;
source parsing, runtime behavior and API contracts remain unchanged. See
[Agent skills workspace](agent-skills-workspace.md) for compatibility limits.
````

- [ ] **Step 4: Verify local links, whitespace and documentation-only task scope, then commit.** Read the guide against actual delivered routes/controls before committing. Do not substitute a future capability for existing parser behavior.

```bash
git diff --check
git diff --name-only
git add docs/agent-skills-workspace.md docs/README.md docs/DIAGRAMS.md
git commit -m "docs(skills): Explain account context and source editing limits"
```

## Task 8: Whole-feature verification, review and truthful completion evidence

**Modify after verification only:** this implementation plan's execution record.
**Evidence outside Git:** fresh `/tmp/opencode/skills-final-*.log` files and browser
artifact directory printed by the system test. No merges/pushes/PRs/cleanup.

- [ ] **Step 1: Confirm a clean feature tree and protect unchanged subsystems.** The application base below is immutable; the actual execution base (committed spec/plan) must also be recorded. Readiness means reviewed evidence, not merely a clean Git status.

```bash
git status --short --branch
git diff --check 6cd1dd03b78a6723a8c31e947f381bda9bf5af1d HEAD
git diff --exit-code 6cd1dd03b78a6723a8c31e947f381bda9bf5af1d HEAD -- app/models app/jobs app/controllers/api app/controllers/mcp_servers_controller.rb app/controllers/token_usages_controller.rb app/controllers/sources_controller.rb app/controllers/concerns/source_scoped.rb app/controllers/concerns/account_scoped.rb app/helpers/sources_workspace_helper.rb app/views/sources app/views/token_usages app/assets/stylesheets/nosia/sources.css app/assets/stylesheets/nosia/usage_workspace.css db Gemfile Gemfile.lock config/importmap.rb
```

Expected: no protected changes. Read the entire changed-file inventory and shared
layout/menu/catalog diffs; ensure conditional changes affect only Skills pages.
Never reset or discard unexpected user work to satisfy this boundary check.

- [ ] **Step 2: Run all final checks sequentially with fresh exclusive log paths.** Use timeout 0 for long suites, inspect completed log trailers and retain failed attempts. A retry uses a new filename. Do not filter tests or suppress warnings to match the baseline.

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-focused.log rails test test/models/agent_skill_test.rb test/models/agent_skill_presentation_contract_test.rb test/controllers/agent_skills_workspace_scoping_test.rb test/controllers/agent_skills_workspace_states_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/agent_skills_workspace_content_test.rb test/controllers/agent_skills_workspace_forms_test.rb test/integration/agent_skills_api_compatibility_test.rb test/integration/localized_pages_test.rb test/controllers/account_experience_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/internationalization/catalogs_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-full.log rails test
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-build.log rails tailwindcss:build
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-browser.log browser test/system
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-lint.log lint app/controllers/agent_skills_controller.rb app/controllers/concerns/agent_skill_scoped.rb app/controllers/agent_skills/enablements_controller.rb app/controllers/agent_skills/toggles_controller.rb app/helpers/agent_skills_workspace_helper.rb test/support/agent_skills_workspace_fixtures.rb test/models/agent_skill_presentation_contract_test.rb test/controllers/agent_skills_workspace_scoping_test.rb test/controllers/agent_skills_workspace_states_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/agent_skills_workspace_content_test.rb test/controllers/agent_skills_workspace_forms_test.rb test/integration/agent_skills_api_compatibility_test.rb test/integration/localized_pages_test.rb test/system/agent_skills_workspace_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-security.log scan --no-pager
```

Expected: focused/browser/build/lint pass; inspect full/scanner exits against
the explicitly accepted fresh Task 0 baseline. Reproduced accepted nonzero exits
are still not green. Unexpected differences block completion. If native zoom
remains unverified, disclose it as such and obtain the review/user decision;
do not silently check off Task 6 Step 7.

- [ ] **Step 3: Perform final specification, architecture and security/code-quality review.** Use the required review skills under the chosen execution method. For Subagent-Driven execution, obtain independent whole-feature specification and quality reviews after per-task reviews. Provide the immutable base/final revision, approved spec/plan, full diff, raw baseline/final logs, exact user baseline acceptance, actual inspected screenshots, theme contrast minima and native-zoom status. Inline execution follows its applicable review instructions; do not invent authorization to dispatch other agents. Real findings require focused RED/GREEN corrections and rerunning affected checks.

- [ ] **Step 4: Write the actual execution record, then commit documentation only.** Include immutable execution base, final tested application SHA, task commits and review outcomes, counts/assertions/seeds/true exits, exact baseline acceptance, logs and screenshots actually inspected, contrast results, native-zoom status and unresolved limitations. Do not write a self-referential future commit SHA or copy Token usage's acceptance. Mark only steps actually completed. Keep raw logs/screenshots/credentials out of Git.

```bash
git diff --check
git add docs/superpowers/plans/2026-10-26-agent-skills-workspace-ui-ux.md
git commit -m "docs(skills): Record workspace verification and review evidence"
```

- [ ] **Step 5: Verify post-commit scope and report the outcome without merging.** Confirm the evidence commit changes only this plan and all application bytes equal the tested revision. Report the branch/revision, honest results and limitations. No push, merge into main, PR or worktree deletion without a new explicit request. Do not start the independent MCP cycle implicitly as part of finishing this branch.

## Plan self-review and specification coverage

This is the planning checklist, not evidence that application execution happened.

| Approved requirement | Planned delivery/check |
| --- | --- |
| Default/scoped authority, second authorized account, membership/forgery/tenant isolation | Tasks 0/2/3/6; account association lookups, bounded tenant, no permitted account transfer |
| Contextual navigation, account entry, shared layout/drawers/New chat | Tasks 2/4/5; predicate-scoped integration and explicit path helpers |
| Management-first rows, order/counts/tags/settings/actions, full raw details and confirmed deletion | Tasks 3/4/6; request and actual browser action tests |
| Grouped native editor, read-only identity, exact source/enum/default/parser compatibility | Tasks 1/5/6; unchanged model/API files and submitted-value projection only |
| Retained 422 input, linked/inline errors, disclosure/focus/pending feedback | Tasks 4/5/6; generic declared-form HTML and error-focus controllers |
| EN/FR, light/dark, responsive long content, keyboard, contrast/reduced motion and native zoom | Tasks 4/5/6/8; 96-state matrix plus adverse states and separate native-zoom evidence |
| Fresh baseline, no inherited waivers/providers/jobs/schema/dependencies, independent reviews and docs | Tasks 0/1/6/7/8; protected diff, real exits, execution-method gate and accurate evidence |

Inline planning self-review completed against the specification: each requirement
maps to the tasks above; custom helper signatures/paths/selectors are consistent;
code fences/prose links and unresolved-marker checks passed. Ruby and Python
snippets, catalog YAML, fixture ERB and 17 complete Rails ERB fragments passed
static syntax checks without loading the application. The single opening-only
layout predicate is intentionally a replacement line in an existing conditional.
These are not application, browser, build or security-test results. No planning
review agents were dispatched. Execution steps remain unchecked.

Follow exact RED → minimal implementation → GREEN ordering in feature tasks;
characterization and documentation checks are explicitly not artificial REDs.

## Execution handoff

This plan does not execute itself. After it is saved/committed and self-reviewed,
offer the user **1 — Subagent-Driven (recommended)** or **2 — Inline Execution**.
Wait for the selection, invoke the chosen execution skill, and begin with Task 0.
No prior feature's execution-method choice or baseline acceptance carries over.

---

## Actual execution record — 2026-10-26

**Outcome: reviewed with accepted concerns, not all green.** The user approved
the written specification with **“Go”**, then chose **1 — Subagent-Driven**
execution. Independent SPEC review preceded QUALITY review at each task and at
whole-feature delivery. MCP remains a separate, unstarted design/implementation
cycle; no merge, push, PR or worktree cleanup is authorized by this record.

This appendix records actual execution without rewriting the approved instructions
or code examples above. Their original unchecked planning boxes are preserved;
the execution-status checklist below distinguishes completed work from this
document's pending publication/post-commit checks.

### Fixed revision, environment and provenance

- **Final application/test/configuration revision tested and reviewed:**
  `bb041d7395bed1c67c4df4895c2f2dd776116873`.
- **Tested tree:** `b9c0e5703beca5d4435c69a7e46c14902f0a7191`.
- Immutable application exploration base:
  `6cd1dd03b78a6723a8c31e947f381bda9bf5af1d`.
- Committed specification/plan execution base:
  `df3d02c13e58622d020786e6cda60a63df6c0a26`.
- Branch/worktree: `feat/agent-skills-workspace-ui` in
  `/home/cbldev/gitd/dilolabs/nosia/.worktrees/agent-skills-workspace-ui`.
- Actual runtime: Ruby **4.0.7**, Rails **8.0.5.1**, PostgreSQL/pgvector,
  Tailwind **4.1.16**, Chromium/ChromeDriver **156.0.8078.47**, Minitest/fixtures,
  Turbo/Stimulus/Importmap. Generic AGENTS.md stack descriptions were not used to
  authorize a dependency, database or ID-schema upgrade.
- All application checks ran sequentially through the unchanged external
  `/tmp/opencode/agent-skills-workspace-check.py`, SHA-256
  `6d4264e38b24ccd6c817422ed906395b5b36cad8bc52c39d1cba8adea2872dba`,
  foreground timeout **0**, `RAILS_ENV=test`, local-socket dedicated
  `postgresql:///nosia_agent_skills_workspace_test`, one worker and test-only AI
  sentinel. No provider credentials were disclosed; configuration loading was
  nondisplaying, not an environment-file read/dump. No real provider, worker or
  ingestion operation was started.

**Evidence limitation:** restart removed original Tasks 0–5 raw logs, screenshots,
reports and the original external checklist. Their conclusions/reviews below are
historical conversation provenance, reconstructed in
`/tmp/opencode/2026-10-26-agent-skills-execution-checklist.md`, **not recovered
on-disk outputs**. The user requested continuation without repeating completed
work. The recorder was restored byte-identically; the existing local test DB
passed the read-only recovery guard (`skills-resume-db-guard.log`), without another
DB creation/preparation. Task 6 onward has current explicit artifacts and report
manifests under `/tmp/opencode/`; these are host-local evidence, not committed
logs or a promise of permanent availability.

Existing externally introduced merge `d97eabe8050bb3b934b1fab050e01567d21e221d`
has the same tree `8d38afee2b984d9c0b333c86783e802caca57813` as reviewed Task 5
`a6ef6bfc4c034aab1d105e970210c50491c855b5`; the assistant did not merge/push it.
Upstream also advanced externally to the tested SHA during final reviews; no
assistant push/fetch/merge occurred. A **new phase-2 snapshot** of all 194 current
refs is `/tmp/opencode/skills-phase2-refs-before.log`, SHA-256
`0de352363b3dd67cfd440fddad6ffc840c1d3f4893d07c567b9a6a0862663a05`.
Earlier unchanged-ref claims apply only to their actual intervals, not to later
outside changes (including the unrelated inference-providers branch).

### Task commits and ordered review outcomes

Rows 0–5 use the historical provenance limit above. Rows 6–8 also have retained
post-restart logs/reports. Review identifiers are controller-reported session
references, not newly queried or newly dispatched agents in this documentation
step. Commit IDs below were checked against actual Git history.

| Task | Commits / scope | SPEC first, then QUALITY | Outcome |
|---|---|---|---|
| 0 | No source commit; isolated checkout, dedicated DB and fresh baseline | `ses_e87bdaaddffenKgeU9vHjtIe4U` → `ses_e87b9a436ffeilisXtGM3XzAgu` | Approved safety/truthful reporting; exact baseline concerns accepted, not green |
| 1 | `9844a13`, `f3ff3c9`; fixtures and parser/runtime characterization | `ses_e873d7514ffeOgUg4bGZ4OAPah` → `ses_e873b695bffei8vKgYxc2wrCMp` | Re-approved after deep-snapshot/metadata-retention hardening |
| 2 | `bbefdb2`; authorized scoped CRUD, helper and setup | `ses_e8727007cffejfl8LneyceagED` → `ses_e8725341dffenI6ccH2Aq4L4w7` | Approved; request-bound tenant restoration observation corrected |
| 3 | `1876eac`, `43a86d6`; enablement and legacy toggle | `ses_e871cd0a9ffeZQF3jjtqK57hMS` → `ses_e871b6714ffeQZ3gygLrbDCEAf` | Re-approved with consecutive DELETE idempotence and exact 303 coverage |
| 4 | `a07875c`, `c09f9b9`; shell, rows and details | `ses_e8708e275ffeBHRHK2jb3CH5FR` → `ses_e8706f02affeFCuSK6DfxJKFw7` | Re-approved after header qualification and markerless-list semantics |
| 5 | `a6ef6bf`; exactly 11 form paths | `ses_e86f593a8ffeLFm9FjBm5lBWgJ` → `ses_e86f33801ffeJC66OzvK2hlIkV` | Approved; QUALITY inspection resumed after restart on the identical tree |
| 6 | `66661c4`; four test paths plus explicitly approved placeholder-CSS exception | `ses_e86cb2832ffeOQmjzzFAsfkl6F` → `ses_e86c6562effeJLn3n2rrlIjPEA` | Approved complete API/adverse/normal-matrix/native-zoom evidence |
| 7 | `f1f67f2`; guide, docs index and diagram only | `ses_e86beb243ffeIfBKI16KACBTPN` → `ses_e86bd3205ffeG5AypwwWWG7g0F` | Approved; 31 local links checked, optional diagram clarification only |
| 8 | `679dd8a` catalog contract; `bb041d7` strict path IDs and exact browser source | Final whole SPEC `ses_e8699038bffe2rKLMhNxenpjiV` → fresh whole QUALITY/architecture/security/UI `ses_e866ff885ffe3R0HfcIPKM0oCB` | Final fresh-evidence recheck and QUALITY approved the same tested SHA with accepted concerns; no Critical/Important or new actionable Minor findings |

The controller read the actual final fixes/RED–GREEN evidence and all seven latest
raw outputs. Whole-feature SPEC initially withheld approval for the two gaps
described below, approved their corrections, then approved the fresh broad
evidence at the fixed tested SHA. Only after that did fresh whole-feature QUALITY
approve; the automated scanner is not a substitute for that independent review.

### Actual adaptations and genuine regressions

- Task 1's supplied shallow attributes snapshot aliased mutable state; the test
  used `deep_dup` and added unrelated-metadata retention coverage. This corrected
  the characterization, not production persistence.
- Task 2's supplied tenant-restoration assertion observed outside Rails' request
  executor, where CurrentAttributes reset. A bounded prepend-around callback
  observed restoration inside the executor, captured ensure-path observations and
  restored the exact callback chain. Task 6's query-error probe used the same
  boundary; unexpected faults remained observable.
- Task 4 qualified `application/header` to avoid the new Skills `_header` partial
  colliding with the shared layout's relative render. `role="list"` was added by
  regression coverage for markerless list semantics, also retained for the form
  error list. No Safari/assistive-technology execution was claimed.
- Task 5's **10 → 11** file count was a clerical correction before commit, not an
  expanded scope. Native form source assertions stayed intact; no normalization
  or parser rewrite was needed.
- Task 6 exposed a real **2.294:1 dark placeholder contrast failure**, not a
  fabricated RED: the emitted pseudo/dark selector did not match. The controller
  authorized only the explicit dark-ancestor placeholder selector and a permanent
  focused regression. RED **1/137, seed 61358, exit 1** preceded CSS/build; GREEN
  **1/305, seed 242, exit 0** measured about **7.814 light / 12.095 dark**. Narrow
  SPEC `ses_e86da6835ffeL83HH6baAksRd3` then QUALITY
  `ses_e86d8c53effeQrUZ5RY4bi1U3I` approved before complete coverage resumed.
- Task 8's first final focused run genuinely failed the new Skills plural
  inventory: **130/11710, seed 37235, 1 failure, exit 1**. Authorized test-only
  `679dd8a` registered `nosia.skills_workspace.counts` and supplied actual
  `total`/`enabled` values to both expected formatting and real I18n translation,
  retaining exact inventory equality, all keys/locales/counts and all assertions.
  Targeted **4/10815, seed 34260, exit 0** and lint passed; narrow SPEC
  `ses_e86b03072ffegB7RGJa93hrHaH` then QUALITY
  `ses_e86af165fffeBuSX7dl3BKnetN` approved.
- Whole SPEC then found integer lookups accepting numeric-prefix malformed IDs
  and HTML `<pre>` consuming one authored leading LF. Exactly four files in
  `bb041d7` addressed these: whole-string ASCII-decimal validation of Skills path
  IDs before membership/association lookup, and one escaped presentation LF
  before raw source. No shared AccountScoped/auth/Current/model/parser/API/schema
  change. Real HTTP RED **3/12, seed 680, 3 failures, exit 1** and browser RED
  **1/15, seed 176, 1 failure, exit 1** preceded production edits. Full scoping
  GREEN **9/318, seed 3295** and Skills browser GREEN **10/9077, seed 32050**, plus
  three-file lint, all exited 0 with no failures/errors/skips. The 44 malformed
  read/mutation cases and eight exact JavaScript `pre.textContent` cases preserve
  account/record/no-job invariants, escaped hostile text, leading LFs, trailing
  whitespace and empty content. Previous tests/thresholds were not weakened.

Available failed attempts, corrective runs and prior-revision final gates are
retained separately in `/tmp/opencode/agent-skills-task8-report.md` and
`agent-skills-task6-report.md`, with actual commands/hashes/revisions. In
particular, `skills-final-focused.log`, `skills-task6-placeholder-red.log`,
`skills-final-strict-ids-red.log` and `skills-final-source-whitespace-red.log` were
not overwritten by GREEN. A transient harness-managed initial diff capture later
expired; explicit current diff snapshots replaced it as **fresh captures**, not
pretended recovered evidence.

### Limited baseline acceptance — not clean gates

The user's explicit **“Yes”** permitted proceeding with Skills despite only the
disclosed unchanged errors/warnings below. This summarizes the accepted scope,
not a reconstructed verbatim question or recovered baseline log. It did not
authorize new failures/errors/skips/warnings, unrelated fixes, skips, suppression
or upgrades. Direct installed-scanner comparisons were separately authorized
without changing warning exits; the version gate must still be reported apart.

| Historical baseline (raw evidence lost in restart) | Exactly accepted concern |
|---|---|
| Focused **100/12056**, seed **2600**, exit **0** | Passing baseline, feature tests subsequently increase counts |
| Full **1119/21433**, seed **5673**, F/E/S **0/1/0**, exit **1** | Undefined `augmented_context`, `app/models/chat/completionable.rb:39` → `test/models/chat/request_options_test.rb:32` |
| Browser **158/16441**, seed **54721**, F/E/S **0/7/0**, exit **1** | Six ProfileManagement language-submit-selector errors and one ChatWaitingUx login/Email setup error |
| JSON warnings | Existing duplicate `tools_cache` / `last_test_at` keys and JSON 3.0 advisory only |
| Original Brakeman wrapper | Installed **8.0.4** versus latest **8.1.0**, ensure-latest exit **5** |
| Authorized installed Brakeman | **79 checks, 0 scan errors**, same two **High-confidence** warnings, exit **3**: PermitAttributes at `app/controllers/api_tokens_controller.rb:62`; EOLRails at `Gemfile.lock:318` |

### Latest complete final commands at the tested SHA

These seven commands actually ran sequentially at **bb041d7**. Each exclusive raw
log was opened in full, including `COMMAND_EXIT`; no filters, warning-suppression
flags, auto-correct or upgrades were used. Earlier final gates at **679dd8a** are
not substitutes for these corrected-candidate runs. These application checks
were **not rerun** for the documentation-only record.

```bash
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-after-review-focused.log rails test test/models/agent_skill_test.rb test/models/agent_skill_presentation_contract_test.rb test/controllers/agent_skills_workspace_scoping_test.rb test/controllers/agent_skills_workspace_states_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/agent_skills_workspace_content_test.rb test/controllers/agent_skills_workspace_forms_test.rb test/integration/agent_skills_api_compatibility_test.rb test/integration/localized_pages_test.rb test/controllers/account_experience_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/internationalization/catalogs_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-after-review-full.log rails test
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-after-review-build.log rails tailwindcss:build
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-after-review-browser.log browser test/system
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-after-review-lint.log lint app/controllers/agent_skills_controller.rb app/controllers/concerns/agent_skill_scoped.rb app/controllers/agent_skills/enablements_controller.rb app/controllers/agent_skills/toggles_controller.rb app/helpers/agent_skills_workspace_helper.rb test/support/agent_skills_workspace_fixtures.rb test/models/agent_skill_presentation_contract_test.rb test/controllers/agent_skills_workspace_scoping_test.rb test/controllers/agent_skills_workspace_states_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/agent_skills_workspace_content_test.rb test/controllers/agent_skills_workspace_forms_test.rb test/integration/agent_skills_api_compatibility_test.rb test/integration/localized_pages_test.rb test/system/agent_skills_workspace_test.rb test/internationalization/catalogs_test.rb
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-after-review-security.log scan --no-pager
python3 /tmp/opencode/agent-skills-workspace-check.py /tmp/opencode/skills-final-after-review-security-installed.log ruby -e 'load Gem.bin_path("brakeman", "brakeman")' -- --no-pager
```

| Final log suffix after `skills-final-after-review-` | Seed | Tests / assertions or result | F/E/S | True exit |
|---|---|---|---|---|
| `focused.log` | **14497** | **133 / 13189** | **0/0/0** | **0** |
| `full.log` | **11244** | **1152 / 22566** | **0/1/0** | **1** |
| `build.log` | n/a | Tailwind **4.1.16**, successful build | n/a | **0** |
| `browser.log` | **35112** | **168 / 25527** | **0/7/0** | **1** |
| `lint.log` | n/a | **16 Ruby files, no offenses**, including catalog test | n/a | **0** |
| `security.log` | n/a | ensure-latest wrapper: **8.0.4 vs 8.1.0** | not a completed scan | **5** |
| `security-installed.log` | n/a | **79 checks / 0 scan errors / 2 warnings** | n/a | **3** |

Fresh full-suite error:
`Chat::RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults`,
`NoMethodError: undefined method 'augmented_context'`, at
`app/models/chat/completionable.rb:39` (map/with_index at 35) →
`test/models/chat/request_options_test.rb:32` (test defined at 29).

Fresh browser errors are exactly these six `ProfileManagementTest` methods plus
the one `ChatWaitingUxTest` method; the complete name sets matched the preceding
raw run, not merely its error count:

```text
ProfileManagementTest#test_native_Tab_keeps_every_en_dark_mobile_profile_control_fully_above_the_bottom_navigation
ProfileManagementTest#test_native_Tab_keeps_every_en_light_mobile_profile_control_fully_above_the_bottom_navigation
ProfileManagementTest#test_native_Tab_keeps_every_fr_dark_mobile_profile_control_fully_above_the_bottom_navigation
ProfileManagementTest#test_native_Tab_keeps_every_fr_light_mobile_profile_control_fully_above_the_bottom_navigation
ProfileManagementTest#test_long_email_and_French_validation_errors_stay_contained_in_the_mobile_scrolling_region
ProfileManagementTest#test_signed_language_preferences_keep_mobile_profile_controls_contained_and_keyboard_accessible_in_both_themes
ChatWaitingUxTest#test_the_composer_locks,_phases_show,_the_placeholder_appears,_then_content,_then_unlock
```

The six profile errors are `Capybara::ElementNotFound` for
`button[type=submit]`, `test/system/profile_management_test.rb:272`, via
`switch_language:270` (callers 149/173/129–130). ChatWaitingUx cannot find enabled
**Email** in setup at `test/system/chat_waiting_ux_test.rb:15` after login_url
(test defined at 22). No new failure/error/skip or Skills browser error occurred.

Installed Brakeman **8.0.4** completed **79 checks**, **0 scan errors**, with the
same warning-details section as its prior run: **High confidence** (not severity),
Mass Assignment / **PermitAttributes**, `app/controllers/api_tokens_controller.rb:62`,
`params.require(:api_token).permit(:account_id, :name)`; and **High confidence**,
Unmaintained Dependency / **EOLRails**, `Gemfile.lock:318`, support for Rails
**8.0.5.1** ended **2026-10-07** per that scanner. The original wrapper's exit 5
and completed installed scan's warning exit 3 remain distinct and **non-green**.
No claim that a newer scanner passed or that security is clean. Accepted duplicate
JSON-key warnings remain unchanged and unsuppressed.

Latest raw-log SHA-256 manifest, all under `/tmp/opencode/`:

```text
0cec2edb3c288a0dea63c5a11373385ac40c18ba2eef6cb05587bec5fc338875  skills-final-after-review-focused.log
b0878ceca8ba189d3a789eab4ee90107c4d1f1588d51c870dd8940b127ff62b8  skills-final-after-review-full.log
5519a8f07eb9e6be11ae25ec19974c5bf80389d5096919fe4c2934b264dd2128  skills-final-after-review-build.log
5ba49bd95cad7c423bfa65599498f2317c2ce0fdce2ce2faf899ee707173b1d8  skills-final-after-review-browser.log
fd56565744ce2e91250d230cd4474f2f86a1de126cff9326e3e120fefed51222  skills-final-after-review-lint.log
f0ac5efa31c44476eb68e88d62655d967a65f70891c1b9badecf891b3c67d033  skills-final-after-review-security.log
ecfe21ef58da6cb471035415b3cb2303f2076aed3c92c7ebf1c704462d6448a3  skills-final-after-review-security-installed.log
```

### Browser, contrast and native-zoom evidence

Fresh bb041d7 evidence: `/tmp/opencode/agent-skills-workspace-70358/`.
The **96/96** normal matrix covers two route families × four page kinds × EN/FR ×
light/dark × three viewports (375×812, 768×1024, 1440×1000), plus empty/setup/error
states, permanent placeholder coverage, reduced-motion and strong keyboard-focus/
whole-control hit-testing checks. There are **112 contrast records / 3754 samples**,
1877 samples per theme; **117 PNGs generated is not 117 visually reviewed**.

| Fresh selected-sample minimum | Light | Dark |
|---|---:|---:|
| Text | 4.945457412311979 | 8.228034925049096 |
| Placeholder | 7.81388303728913 | 12.09488625090816 |
| Control border | 4.536155586951846 | 3.1916051526448737 |
| Focus outline | 4.536155586951846 | 9.341138249313333 |

The normal matrix correctly retains native zoom **UNVERIFIED**. Separate Task 6
native evidence is `/tmp/opencode/skills-task6-native-200-18744/` and
`skills-task6-native-200.log`: **48/48 states, 1 test / 5597 assertions, seed
23022, F/E/S 0/0/0, exit 0**. Actual Chromium Settings selected **200%**, independent
native API returned **2**; outer size stayed 1400×1400, CSS viewport changed from
1400×1257 to 700×628, DPR 1→2, visual scale 1. Temporary Selenium profile/settings
were restored to native 100%; CSS zoom/transform/CDP scaling or viewport proxies
were not substituted. The 32 ordinary and 16 server-validation states cover both
families/locales/themes with bottom-navigation clearance (minimum recorded 24 CSS
px); native contrast has **64 records / 2288 samples**.

**Native attribution limit:** this native proof belongs to the actual Task 6
candidate (raw header d97eabe, subsequently committed as **66661c4**), not a new
bb041d7 native run. The current details view and strict-ID concern differ from
that candidate. The controller explicitly retained the earlier native proof
without repeating the one-off because CSS/layout/zoom mechanism did not change;
the source-LF correction has exact real-browser `textContent` proof and the fresh
complete normal matrix. Stored artifact hashes being retained does not assert
that current application bytes still equal Task 6's candidate.

**Actual image inspection by role:** this Task 8 implementer opened **no images**.
The Task 6 implementer opened 26 final normal and 27 native images; its complete
opened-file manifests are in `/tmp/opencode/agent-skills-task6-report.md`, separate
from generated totals. Representative actually opened normal paths under
`/tmp/opencode/agent-skills-workspace-13497/` include
`legacy_list-fr-375-light.png`, `scoped_detail-fr-375-dark.png`,
`legacy_new-fr-375-dark.png`, `errors-fr-dark.png`, `setup-fr-dark.png`; native
examples include `browser-settings-200.png`, `legacy-list-fr-light.png` and
`scoped-edit-fr-dark-validation-priority.png` under the native directory above.
The parent reports inspecting earlier normal images in 13497, native
`browser-settings-200.png` and two native state images, and reading all seven
latest raw outputs. The two parent state filenames are not named in the
reconstructed checklist/handoff and are not invented here.

The **fresh whole QUALITY reviewer**, not this implementer, actually opened these
11 normal images under `/tmp/opencode/agent-skills-workspace-70358/`:

```text
rows-1440-light.png
rows-375-dark.png
scoped_list-fr-1440-dark.png
scoped_detail-fr-375-light.png
legacy_edit-fr-375-dark.png
placeholder-scoped-dark.png
errors-fr-dark.png
setup-fr-light.png
empty-en-dark.png
legacy_new-en-1440-light.png
scoped_edit-fr-768-light.png
```

It also actually opened these seven retained native images under
`/tmp/opencode/skills-task6-native-200-18744/`:

```text
browser-settings-200.png
legacy-list-fr-light.png
scoped-detail-en-dark-top.png
scoped-detail-fr-dark.png
scoped-new-fr-light.png
legacy-edit-fr-dark-validation-summary.png
scoped-edit-fr-dark-validation-priority.png
```

Standard framework screenshots for accepted browser errors reuse filenames and
were automatically overwritten by later runs; no separate old image copies are
claimed. Unique Task 6 artifacts and explicit raw logs remain distinct.
Optional nonblocking observations remain **not fixed and not requirements
defects**: contrast query does not directly select `pre`/`legend` (current UI
reviewed readable); native viewport halving is recorded/proven but lacks a
separate explicit halving assertion; diagram nodes/arrows could be clearer; the
679dd8a commit body has cosmetic literal newline separators. No new actionable
whole-QUALITY finding or baseline waiver resulted.

### Execution status and documentation-only publication boundary

- [x] Tasks 0–5 executed and reviewed; historical-only original artifacts lost in restart, as disclosed.
- [x] Task 6 coverage/native evidence and ordered reviews completed; retained evidence attributed to its actual candidate.
- [x] Task 7 documentation and ordered reviews completed.
- [x] Task 8 Step 1: clean feature/protected-subsystem/complete-diff checks completed.
- [x] Task 8 Step 2: all seven final checks completed at the fixed tested SHA, preserving true nonzero results.
- [x] Task 8 Step 3: final SPEC evidence approval followed by fresh QUALITY/architecture/security/UI approval.
- [ ] Task 8 Step 4 publication: this record is prepared before its docs-only commit; commit identity and actual documentation checks are reported externally after creation.
- [ ] Task 8 Step 5: post-commit single-path manifest, all-other-tracked-byte equality, clean tree/ref verification and final controller/user report occur externally after that commit.

These last boxes intentionally do not claim future events at record-writing
time; the controller may close the external execution checklist after post-commit
verification. No future self-referential documentation-commit SHA is embedded.
Publication is limited to this plan. All other tracked bytes must equal the fixed
tested SHA; only the feature branch ref may advance from the new phase-2 snapshot.
Only local documentation links/fences/whitespace/scope are checked for this record,
not a repetition of completed application suites. Full-suite/browser/security
concerns remain disclosed and non-green; reviewed delivery is not merge authority.

See the [approved specification](../specs/2026-10-26-agent-skills-workspace-ui-ux-design.md)
and [delivered workspace guide](../../agent-skills-workspace.md) for product scope.
