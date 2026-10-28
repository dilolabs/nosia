# MCP Workspace UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved account-explicit MCP management rows, catalog, server details and safe configuration workflows without adding execution capabilities.

**Architecture:** Reuse workspace partials and Rails/Hotwire. One account-scoping concern supplies an explicitly authorized account; small resource controllers retain legacy connection/tool URLs. Model concerns own credential updates and capability outcomes; catalog recovery stays in the existing catalog model/controller. Focused helpers/partials and MCP-only Stimulus controllers handle presentation and progressive enhancement.

**Tech Stack:** Observed Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL, RubyLLM 2.0.0, vendored ruby_llm-mcp 1.0.1, Tailwind 4.1.16, ERB, Turbo/Stimulus, Importmap, Minitest/fixtures and Selenium/Chromium. Do not change dependencies to match generic stack descriptions.

---

## Authority and execution boundaries

The user reviewed specification commit `31d4d2d88fb2e4a06b96b5a581f8f21b4f95965c`
and answered **“Go”** to implementation planning. The authority is
[MCP workspace UI/UX design](../specs/2026-10-27-mcp-workspace-ui-ux-design.md),
especially its Decisions section. This is a plan, not implementation evidence.
Select an execution approach after this plan is committed; do not begin application
changes during planning. No merge, push, PR, dependency installation, shared DB
reset or unrelated repair is authorized.

The documentation worktree is `.worktrees/mcp-workspace-design`, branch
`docs/mcp-workspace-design`, based on `ea09e57291c767e913ac1d2a3d4fca8e138733dd`.
Use a separate execution worktree. Preserve main's unrelated files and the completed
Accounts/Settings branch. Earlier baseline exceptions are **not MCP acceptance**.

## File and responsibility map

| Task | Files and responsibility |
| --- | --- |
| 0 | External environment/recorder under `/tmp/opencode`; isolated baseline, no tracked source changes |
| 1 | `app/controllers/concerns/mcp_scoped.rb`; `app/helpers/mcp_workspace_helper.rb`; existing server/catalog controllers; `app/controllers/mcp_servers/{connections,connection_tests,tool_executions}_controller.rb`; `config/routes.rb`: explicit account context and compatible endpoints |
| 1 tests | `test/support/mcp_workspace_fixtures.rb`; `test/controllers/mcp_workspace_scoping_test.rb`: deterministic local integration and isolation |
| 2 | `app/models/mcp_server/configuration.rb`; `app/models/mcp_server.rb`; server controller; `lib/mcp_catalog.rb`; catalog controller; parameter filter; paired `*.nosia_mcp_workspace.yml`: safe updates and recoverable activation |
| 2 tests | `test/models/mcp_server_configuration_test.rb`; `test/controllers/mcp_workspace_configuration_test.rb`: credential round trips and 422 recovery |
| 3 | `app/models/mcp_server/capability_snapshot.rb`; server model/controller; `test/models/mcp_server_capability_snapshot_test.rb`: truthful discovery without changing execution APIs |
| 4 | `app/views/mcp_workspace/{_header,_feedback,setup}.html.erb`; server list/row/status; layout guards; one MCP shortcut in `accounts/_configuration`; MCP helper; busy controller; MCP stylesheet/import: shared shell and management rows |
| 4 tests | `test/controllers/mcp_workspace_shell_test.rb`; `test/system/mcp_workspace_test.rb`: shell/list regression and browser-first styling |
| 5 | catalog index/show; catalog entry/fields and shared errors partials; `app/helpers/mcp_forms_helper.rb`; `mcp_secrets_controller.js`: discovery and metadata-driven setup |
| 6 | server detail; `app/views/mcp_servers/{_connection_controls,_capabilities,_connection_test_result}.html.erb`; `app/javascript/controllers/mcp_server_controller.js`; MCP helper: state-aware controls and accessible sections |
| 7 | server new/edit/form; shared `app/views/mcp_workspace/_field.html.erb`; `app/javascript/controllers/mcp_form_controller.js`: transport-aware forms using the existing safe field/error and busy/secret components |
| 5–7 tests | `test/controllers/mcp_workspace_{catalog,detail,forms}_test.rb`; system workflows below; intentional MCP legacy HTML assertions, including `test/integration/localized_pages_test.rb` |
| 8 | `test/support/mcp_browser_checks.rb`; completed MCP system test; focused `docs/mcp-workspace.md`, docs index; public YARD checks, final evidence record |

No migrations, new transport clients, service/form/policy directories, new runner,
raw environment editor or unrelated shared-style refactor. The small controller
split is necessary for conventional new scoped resources while retaining old URLs.
Do not move business logic into those controllers.

## Task 0: Isolate execution and establish fresh baselines

**Files:** external `/tmp/opencode/mcp-workspace-env.sh`; unique evidence directory;
no tracked changes. All database-sharing commands run sequentially.

- [ ] **Step 1: Verify/create the execution worktree.** From the main repository:

```bash
git status --short
git worktree list
git check-ignore .worktrees/mcp-workspace-ui
git branch --list feat/mcp-workspace-ui
BASE=$(git rev-parse docs/mcp-workspace-design)
git show -1 --oneline "$BASE"
git worktree add .worktrees/mcp-workspace-ui -b feat/mcp-workspace-ui "$BASE"
```

If a branch/path already exists, inspect it instead of overwriting it. Confirm
`BASE` is the approved plan commit at handoff and record the full immutable SHA.
Move the session to `/home/cbldev/gitd/dilolabs/nosia/.worktrees/mcp-workspace-ui`.
Do not copy development DBs, `.env`, user modifications or generated CSS.

- [ ] **Step 2: Inspect then create an external helper.** If the helper exists,
investigate it; do not overwrite another session's file. Create one fresh directory
with the command below, saving its actual absolute path once. Check both named
files for existing work before running it; if either exists, stop and investigate.
Use the patch tool to write the helper, which reuses the saved path across shells.

```bash
mktemp -d /tmp/opencode/mcp-workspace-XXXXXX > /tmp/opencode/mcp-workspace-evidence.path
git rev-parse HEAD > "$(< /tmp/opencode/mcp-workspace-evidence.path)/base-sha.txt"
```

```bash
export NOSIA_MAIN=/home/cbldev/gitd/dilolabs/nosia
export RUBOCOP_TARGET_RUBY_VERSION=4.0
export EVIDENCE="$(< /tmp/opencode/mcp-workspace-evidence.path)"
test -d "$EVIDENCE" || return 125
export BASE="$(< "$EVIDENCE/base-sha.txt")"
test -n "$BASE" || return 125
test_command() {
  mise exec ruby@4.0.7 -- bundle exec dotenv -f "$NOSIA_MAIN/.env" -- env \
    RAILS_ENV=test DATABASE_URL=postgresql:///nosia_mcp_workspace_ui_test \
    AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 "$@"
}
rails_test() { test_command bin/rails "$@"; }
browser_test() {
  test_command bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test "$@"
}
record() {
  local label="$1" log result fd recorder_result=0
  shift
  log="$(mktemp "$EVIDENCE/$label.XXXXXX.log")" || return 125
  exec {fd}>"$log" || return 125
  if "$@" >&"$fd" 2>&1; then result=0; else result=$?; fi
  printf '%s\n' "$result" >"${log%.log}.exit" || recorder_result=125
  exec {fd}>&- || recorder_result=125
  if test "$recorder_result" -ne 0; then
    printf 'Recorder failed; command exit was %s\n' "$result" >&2
    return 125
  fi
  tail -n 25 "$log" || return 125
  printf 'Evidence: %s (command exit %s)\n' "$log" "$result" || return 125
  return "$result"
}
```

Never display/source/read/copy `.env`; nondisplaying dotenv is its only consumer.
Fixed test variables follow dotenv and must win. Never run ingestion/provider/
queue workers. Keep each failed log and its real exit; no `tee` exit masking.

- [ ] **Step 3: Check prerequisites and configuration before database preparation.**

```bash
mise exec ruby@4.0.7 -- ruby --version
mise exec ruby@4.0.7 -- bundle check
command -v chromium
command -v chromedriver
df -h . /tmp/opencode
source /tmp/opencode/mcp-workspace-env.sh
record preflight test_command bundle exec ruby -ryaml -rerb -ractive_record -ractive_record/database_configurations -e 'raw=YAML.safe_load(ERB.new(File.read("config/database.yml")).result, aliases:true); c=ActiveRecord::DatabaseConfigurations.new(raw).configs_for(env_name:"test").first; abort "wrong database" unless c.database=="nosia_mcp_workspace_ui_test"; puts "Isolated database configuration verified"'
record prepare rails_test db:prepare
record environment rails_test runner 'abort "wrong environment" unless Rails.env.test?; abort "wrong database" unless ActiveRecord::Base.connection_db_config.database=="nosia_mcp_workspace_ui_test"; puts "Verified isolated test database"'
```

Stop for missing prerequisites/extensions/credentials or configuration mismatch;
do not install packages, edit dependencies or prepare another DB to work around it.

- [ ] **Step 4: Run all fresh baseline categories, one at a time.** Source the helper
in every shell, use this feature worktree, and allow up to 900000ms for suites.

```bash
record baseline-build rails_test tailwindcss:build
record baseline-focused rails_test test test/controllers/mcp_servers_controller_test.rb test/controllers/mcp_connection_tests_test.rb test/models/mcp_server_test.rb test/models/mcp_server_local_test.rb test/lib/mcp_catalog_registry_test.rb test/helpers/mcp_catalog_helper_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record baseline-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/controllers/mcp_servers_controller.rb app/controllers/mcp_catalog_controller.rb app/models/mcp_server.rb app/helpers/mcp_catalog_helper.rb lib/mcp_catalog.rb test/controllers/mcp_servers_controller_test.rb test/controllers/mcp_connection_tests_test.rb test/models/mcp_server_test.rb test/models/mcp_server_local_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/integration/localized_pages_test.rb
record baseline-full rails_test test
record baseline-mcp-browser browser_test test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb
record baseline-protected-browser browser_test test/system/accounts_settings_workspace_test.rb test/system/account_experience_test.rb test/system/agent_skills_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/profile_management_test.rb
record baseline-security mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
git status --short
```

Run later categories after test failures unless infrastructure/safety prevents it.
Known *source observations*, not reproduced/accepted results: old MCP browser setup
expects the pre-dashboard composer after login; Profile has an obsolete language
submit selector; prior work found a request-options test double and security/JSON
warnings. Record actual names, messages, lines, seeds, counts and true exits.
Obtain explicit direction before application changes. A planned MCP selector
migration is not permission to conceal its original baseline failures.

- [ ] **Step 5: Checkpoint.** Prove tracked source equals `BASE`; report all outcomes,
disk headroom, actual helper/evidence paths and unresolved issues. Independent
specification/quality review of the setup precedes any needed user acceptance.
No fabricated RED or source commit is needed for this no-code task.

## Task 1: Account context, conventional operation controllers and compatibility

**Files:** the Task 1 rows in the map above. This task adds scoped endpoints;
the following UI tasks advertise them. Existing unscoped workflows must still work.

- [ ] **Step 1: Create the shared fixture helper.** This is test setup, not a new
factory system. Use these complete contents in `test/support/mcp_workspace_fixtures.rb`:

```ruby
require_relative "chat_account_fixtures"

module McpWorkspaceFixtures
  extend ActiveSupport::Concern
  include ChatAccountFixtures

  class EchoTool < MCP::Tool
    tool_name "workspace_echo"
    description "Echo a query without external services"
    input_schema(properties: { query: { type: "string" } }, required: [ "query" ])
    def self.call(query:, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: query } ])
    end
  end

  included do
    setup do
      @saved_engines = Engines::Registry.all
      @saved_catalog = McpCatalog.instance_variable_get(:@catalog)
      @saved_categories = McpCatalog.instance_variable_get(:@categories)
      @health_check = ->(auth) { raise "credential-echo-#{auth[:api_key]}" if auth[:api_key] == "bad" }
      Engines::Registry.register(Engines::Registration.new(id: "workspace-demo",
        name: "Workspace demo", icon: "test", description: "Local fixture integration",
        required_config: [ { name: "api_key", label: "Demo key", type: "secret", required: true },
          { name: "team", label: "Team", type: "string", required: true } ],
        tool_classes: [ EchoTool ], capabilities: [ "tools" ], health_check: ->(auth) { @health_check.call(auth) }))
      McpCatalog.instance_variable_set(:@catalog, nil)
      McpCatalog.instance_variable_set(:@categories, nil)
      @first_server = mcp_servers(:picker_first_tool)
      @second_server = mcp_servers(:picker_second_tool)
      [ [ @first, @first_server ], [ @second, @second_server ] ].each do |account, server|
        ActsAsTenant.with_tenant(account) do
          server.update!(status: "disconnected", metadata: { engine: "workspace-demo", catalog_id: "workspace-demo" },
            auth_config: { api_key: "saved-secret", team: "Research" })
        end
      end
      stub_url_resolver([ "93.184.216.34" ])
    end

    teardown do
      unstub_url_resolver
      Engines::Registry.clear
      @saved_engines.each { |entry| Engines::Registry.register(entry) }
      McpCatalog.instance_variable_set(:@catalog, @saved_catalog)
      McpCatalog.instance_variable_set(:@categories, @saved_categories)
    end
  end
end
```

- [ ] **Step 2: Write `test/controllers/mcp_workspace_scoping_test.rb` before routes/controllers.**

```ruby
require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceScopingTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures
  setup { sign_in_picker_user }

  test "scoped reads use the path account and never change the default" do
    get account_mcp_servers_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_includes response.body, @second_server.name
    refute_includes response.body, @first_server.name
    get account_mcp_server_path(@second, @first_server)
    assert_response :not_found
    get account_mcp_servers_path(@foreign)
    assert_response :not_found
    get "/accounts/#{@second.id}junk/mcp_servers"
    assert_response :not_found
    assert_equal @first, @user.reload.first_account
  end

  test "scoped creation update and deletion retain context" do
    assert_difference -> { @second.mcp_servers.count }, 1 do
      post account_mcp_servers_path(@second), params: { mcp_server: {
        name: "Scoped HTTP", transport_type: "streamable", endpoint: "https://mcp.example.org/mcp" }, account_id: @foreign.id }
    end
    server = @second.mcp_servers.find_by!(name: "Scoped HTTP")
    assert_redirected_to account_mcp_server_path(@second, server)
    patch account_mcp_server_path(@second, server), params: { mcp_server: { name: "Renamed" } }
    assert_redirected_to account_mcp_server_path(@second, server)
    assert_equal "Renamed", server.reload.name
    assert_difference -> { @second.mcp_servers.count }, -1 do
      delete account_mcp_server_path(@second, server)
    end
    assert_redirected_to account_mcp_servers_path(@second)
  end

  test "catalog activation and connection operations preserve URL context" do
    get account_mcp_catalog_index_path(@second)
    assert_response :success
    post account_mcp_catalog_index_path(@second), params: { id: "open_alex", config: {}, account_id: @foreign.id }
    assert_redirected_to account_mcp_server_path(@second, @second.mcp_servers.find_by!(name: "OpenAlex"))
    post account_mcp_server_connection_path(@second, @second_server)
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    assert @second_server.reload.status_ready?
    delete account_mcp_server_connection_path(@second, @second_server)
    assert @second_server.reload.status_disconnected?
    post account_mcp_server_connection_test_path(@second, @second_server), as: :json
    assert_response :success
    assert_equal true, response.parsed_body.fetch("success")
    post account_mcp_server_tool_execution_path(@second, @second_server), as: :json,
      params: { tool_name: "workspace_echo", arguments: { query: "fixture" } }
    assert_equal({ "success" => true, "result" => "fixture" }, response.parsed_body)
  end

  test "foreign and revoked mutations fail without writes" do
    before = @second_server.attributes
    account_users(:picker_second_membership).destroy!
    [ [ :post, account_mcp_server_connection_test_path(@second, @second_server) ],
      [ :post, account_mcp_server_connection_path(@second, @second_server) ],
      [ :delete, account_mcp_server_connection_path(@second, @second_server) ],
      [ :post, account_mcp_server_tool_execution_path(@second, @second_server) ],
      [ :patch, account_mcp_server_path(@second, @second_server) ],
      [ :delete, account_mcp_server_path(@second, @second_server) ],
      [ :post, account_mcp_catalog_index_path(@second) ] ].each do |verb, path|
      public_send(verb, path, params: { id: "open_alex", account_id: @first.id, mcp_server: { name: "Forged" } })
      assert_response :not_found
    end
    assert_equal before, @second_server.reload.attributes
  end

  test "legacy routes and ordinary member permissions remain" do
    post test_connection_mcp_server_path(@first_server), as: :json
    assert_response :success
    assert_equal %w[latency message status success], response.parsed_body.keys.sort
    post disconnect_mcp_server_path(@first_server)
    assert_redirected_to mcp_server_path(@first_server)
    @second.account_users.grant_to(users(:picker_outsider))
    sign_in_picker_user(users(:picker_outsider))
    patch account_mcp_server_path(@second, @second_server), params: { mcp_server: { notes: "Member edit" } }
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    assert_equal "Member edit", @second_server.reload.notes
  end
end
```

- [ ] **Step 3: RED.**

```bash
record scope-red rails_test test test/controllers/mcp_workspace_scoping_test.rb
```

Expected genuine missing scoped route/helpers, not fixture or DNS errors. Preserve
the failure. All new public methods below have their contracts documented in place.

- [ ] **Step 4: Add `app/controllers/concerns/mcp_scoped.rb`.**

```ruby
module McpScoped
  extend ActiveSupport::Concern
  include AccountScoped
  include McpWorkspaceHelper
  included { around_action :with_mcp_account }

  private
    def with_mcp_account
      @mcp_scoped = request.path_parameters.key?(:account_id)
      @account = @mcp_scoped ? member_account(mcp_path_id(:account_id)) : Current.account
      if @account
        ActsAsTenant.with_tenant(@account) { yield }
      elsif request.get? && (controller_path == "mcp_catalog" || (controller_path == "mcp_servers" && %w[index new].include?(action_name)))
        render "mcp_workspace/setup", formats: [ :html ]
      else
        head :not_found
      end
    end

    def mcp_path_id(key)
      value = request.path_parameters[key]
      raise ActiveRecord::RecordNotFound unless value.is_a?(String) && value.match?(/\A[0-9]+\z/)
      value
    end

    def set_mcp_server
      key = request.path_parameters.key?(:mcp_server_id) ? :mcp_server_id : :id
      @mcp_server = @account.mcp_servers.find(mcp_path_id(key))
    end
end
```

The numeric validation matches the actual checkout, not the generic UUID notes.
Do not assign `Current.account`: it is computed from `Current.user.first_account`.

- [ ] **Step 5: Add `app/helpers/mcp_workspace_helper.rb`.**

```ruby
module McpWorkspaceHelper
  # @return [Boolean] Whether the controller owns an MCP workspace shell
  def mcp_workspace_page?
    %w[mcp_servers mcp_catalog].include?(controller_path) || controller_path.start_with?("mcp_servers/")
  end

  # @return [Boolean] Whether context came from an authorized account URL
  def mcp_scoped? = @mcp_scoped == true
  # @return [String] Context-preserving server list
  def mcp_index_path = mcp_scoped? ? account_mcp_servers_path(@account) : mcp_servers_path
  # @return [String] Context-preserving creation form
  def mcp_new_path = mcp_scoped? ? new_account_mcp_server_path(@account) : new_mcp_server_path
  # @return [String] Context-preserving catalog list
  def mcp_catalog_list_path = mcp_scoped? ? account_mcp_catalog_index_path(@account) : mcp_catalog_index_path
  # @param id [String] Trusted catalog ID
  # @return [String] Context-preserving template URL
  def mcp_template_path(id) = mcp_scoped? ? account_mcp_catalog_path(@account, id) : mcp_catalog_path(id)
  # @param server [McpServer] Authorized record
  # @return [String] Context-preserving details URL
  def mcp_record_path(server) = mcp_scoped? ? account_mcp_server_path(@account, server) : mcp_server_path(server)
  # @param server [McpServer] Authorized record
  # @return [String] Context-preserving edit URL
  def mcp_edit_path(server) = mcp_scoped? ? edit_account_mcp_server_path(@account, server) : edit_mcp_server_path(server)
  # @param server [McpServer] New or authorized existing record
  # @return [McpServer, Array] Rails form model argument
  def mcp_form_model(server) = mcp_scoped? ? [ @account, server ] : server
  # @param server [McpServer] Authorized record
  # @return [String] Existing test operation URL
  def mcp_test_path(server) = mcp_scoped? ? account_mcp_server_connection_test_path(@account, server) : test_connection_mcp_server_path(server)
  # @param server [McpServer] Authorized record
  # @return [String] Existing connect operation URL
  def mcp_connect_path(server) = mcp_scoped? ? account_mcp_server_connection_path(@account, server) : connect_mcp_server_path(server)
  # @param server [McpServer] Authorized record
  # @return [String] Existing disconnect operation URL
  def mcp_disconnect_path(server) = mcp_scoped? ? account_mcp_server_connection_path(@account, server) : disconnect_mcp_server_path(server)
  # @return [Symbol] HTTP verb preserving the legacy disconnect URL
  def mcp_disconnect_method = mcp_scoped? ? :delete : :post
  # @return [String] Existing composer with explicit URL account when applicable
  def mcp_new_chat_path = mcp_scoped? ? new_chat_path(account_id: @account.id) : new_chat_path

  # @param current [String, nil] Detail/form current label
  # @param catalog [Boolean] Whether to include the catalog ancestor
  # @param server [McpServer, nil] Authorized edit ancestor
  # @return [Array<Hash>] Explicit complete breadcrumb
  def mcp_trail(current: nil, catalog: false, server: nil)
    trail = [ { label: t("nosia.nav.home"), path: user_root_path } ]
    if mcp_scoped?
      trail += [ { label: t("nosia.nav.accounts"), path: accounts_path }, { label: @account.name, path: account_path(@account) } ]
    else
      trail << { label: t("nosia.nav.settings"), path: settings_path }
    end
    trail << { label: t("nosia.mcp.title"), path: (current || catalog || server) ? mcp_index_path : nil }
    trail << { label: t("nosia.mcp.catalog"), path: current ? mcp_catalog_list_path : nil } if catalog
    trail << { label: server.name, path: mcp_record_path(server) } if server
    trail << { label: current, path: nil } if current
    trail
  end
end
```

- [ ] **Step 6: Route through small resource controllers.** Insert this complete
block inside existing `resources :accounts`; retain all existing sibling routes:

```ruby
resources :mcp_catalog, only: [ :index, :show, :create ]
resources :mcp_servers do
  scope module: :mcp_servers do
    resource :connection, only: [ :create, :destroy ]
    resource :connection_test, only: :create
    resource :tool_execution, only: :create
  end
end
```

Replace only the existing unscoped MCP server member block with:

```ruby
resources :mcp_servers do
  member do
    post :test_connection, to: "mcp_servers/connection_tests#create"
    post :connect, to: "mcp_servers/connections#create"
    post :disconnect, to: "mcp_servers/connections#destroy"
    post :execute_tool, to: "mcp_servers/tool_executions#create"
  end
end
```

In `McpServersController`, include `McpScoped`, change its callback to
`before_action :set_mcp_server, only: [ :show, :edit, :update, :destroy ]`, remove
its old `set_mcp_server`, connection/tool actions and `tool_result_for_json`
definitions (they are moved below), and use these CRUD bodies:

```ruby
def index
  @mcp_servers = @account.mcp_servers.order(created_at: :desc)
  filters = { "status" => McpServer.statuses.keys, "transport_type" => %w[stdio streamable sse local], "enabled" => %w[true false 1 0] }
  filters.each do |key, allowed|
    @mcp_servers = @mcp_servers.where(key => params[key]) if allowed.include?(params[key])
  end
end

def show
  @tools, @prompts, @resources = @mcp_server.tools, @mcp_server.prompts, @mcp_server.resources
end

def new
  @mcp_server = @account.mcp_servers.build
end

def create
  @mcp_server = @account.mcp_servers.build(mcp_server_params)
  if @mcp_server.save
    redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.created")
  else
    render :new, status: :unprocessable_entity
  end
end

def edit
end

def update
  if @mcp_server.update(mcp_server_params)
    redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.updated")
  else
    render :edit, status: :unprocessable_entity
  end
end

def destroy
  @mcp_server.destroy
  redirect_to mcp_index_path, notice: t("nosia.mcp.deleted")
end
```

Keep its existing strong-parameter method until Task 2. In the catalog controller,
include `McpScoped`, replace every `Current.account` query/activation argument with
`@account`, and use `mcp_catalog_list_path`/`mcp_record_path(@mcp_server)` for its
existing redirects. These are the only intermediate catalog changes.

Create the following complete files:

`app/controllers/mcp_servers/connections_controller.rb`:

```ruby
class McpServers::ConnectionsController < ApplicationController
  include McpScoped
  before_action :set_mcp_server

  def create
    if @mcp_server.test_connection!
      redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.connected")
    else
      redirect_to mcp_record_path(@mcp_server), alert: t("nosia.mcp.connection_failed")
    end
  end

  def destroy
    @mcp_server.disconnect!
    redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.disconnected")
  end
end
```

`app/controllers/mcp_servers/connection_tests_controller.rb`:

```ruby
class McpServers::ConnectionTestsController < ApplicationController
  include McpScoped
  before_action :set_mcp_server

  def create
    success = @mcp_server.test_connection!
    respond_to do |format|
      format.html { redirect_to mcp_record_path(@mcp_server), status: :see_other, flash: { connection_test: success ? "success" : "error" } }
      format.json do
        if success
          render json: { success: true, status: @mcp_server.status, latency: @mcp_server.latency_ms, message: t("nosia.mcp.connection_established") }
        else
          render json: { success: false, status: @mcp_server.status, error: @mcp_server.last_error, message: t("nosia.mcp.connection_failed") }, status: :unprocessable_entity
        end
      end
    end
  end
end
```

`app/controllers/mcp_servers/tool_executions_controller.rb`:

```ruby
class McpServers::ToolExecutionsController < ApplicationController
  include McpScoped
  before_action :set_mcp_server

  def create
    if !params[:arguments].nil? && !params[:arguments].is_a?(ActionController::Parameters)
      render json: { error: t("nosia.mcp.arguments_invalid") }, status: :bad_request
    else
      arguments = params.permit(arguments: {}).fetch(:arguments, {}).to_h
      render json: tool_result_for_json(@mcp_server.execute_tool(params[:tool_name], arguments))
    end
  end

  private
    def tool_result_for_json(value)
      case value
      when RubyLLM::Attachment
        { type: value.type.to_s, data: value.encoded, mimeType: value.mime_type, filename: value.filename }
      when Array
        value.map { |item| tool_result_for_json(item) }
      when Hash
        value.transform_values { |item| tool_result_for_json(item) }
      when String, Numeric, TrueClass, FalseClass, NilClass
        value
      else
        raise TypeError, "Unsupported tool result JSON value"
      end
    end
end
```

Add the setup view now so missing-account requests are safe before styling:

```erb
<%# app/views/mcp_workspace/setup.html.erb %>
<div class="n-workspace n-mcp-workspace" data-mcp-workspace data-mcp-screen="setup">
  <%= render "workspaces/header", title: t("nosia.mcp.title"), trail: [ { label: t("nosia.nav.home"), path: user_root_path }, { label: t("nosia.nav.settings"), path: settings_path }, { label: t("nosia.mcp.title"), path: nil } ] %>
  <section class="n-workspace-panel">
    <h2 class="n-workspace-section-title"><%= t("nosia.account_experience.no_accounts") %></h2>
    <%= link_to t("nosia.accounts.add"), new_account_path, class: "n-workspace-button n-workspace-primary" %>
    <%= link_to t("nosia.nav.accounts"), accounts_path, class: "n-workspace-link" %>
  </section>
</div>
```

- [ ] **Step 7: GREEN and preserved JSON behavior.**

```bash
record scope-green rails_test test test/controllers/mcp_workspace_scoping_test.rb test/controllers/mcp_servers_controller_test.rb test/controllers/mcp_connection_tests_test.rb test/lib/ruby_llm_mcp_compatibility_test.rb
git diff --check
git add app/controllers/concerns/mcp_scoped.rb app/helpers/mcp_workspace_helper.rb app/controllers/mcp_servers_controller.rb app/controllers/mcp_catalog_controller.rb app/controllers/mcp_servers app/views/mcp_workspace/setup.html.erb config/routes.rb test/support/mcp_workspace_fixtures.rb test/controllers/mcp_workspace_scoping_test.rb
git commit -m "feat: Preserve MCP account context and operation compatibility"
```

No legacy binary serialization/keyword/error assertions may be dropped. Inspect
only Task 1 paths before committing; record the actual tested tree and review.

## Task 2: Safe credential updates and recoverable catalog activation

**Files:** configuration concern/model, CRUD/catalog controllers, catalog library,
parameter filter, paired workspace locales, model/request tests below.

- [ ] **Step 1: Write `test/models/mcp_server_configuration_test.rb`.**

```ruby
require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpServerConfigurationTest < ActiveSupport::TestCase
  include McpWorkspaceFixtures

  test "blank keeps saved secrets and replacement preserves other configuration" do
    @second_server.update!(connection_config: { env: { "UNEDITED" => "keep" } })
    assert @second_server.save_workspace({ notes: "Updated" }, values: { "api_key" => "", "team" => "New team" })
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
    assert_equal "New team", @second_server.auth_config.fetch("team")
    assert @second_server.save_workspace({}, values: { "api_key" => "replacement" })
    assert_equal "replacement", @second_server.reload.auth_config.fetch("api_key")
    assert_equal({ "UNEDITED" => "keep" }, @second_server.connection_config.fetch("env"))
  end

  test "required removal and contradictory instructions fail without database writes" do
    before = @second_server.attributes
    refute @second_server.save_workspace({}, values: {}, removals: [ "api_key" ])
    assert @second_server.errors.include?(:"configuration.api_key")
    assert_equal before, @second_server.reload.attributes
    refute @second_server.save_workspace({}, values: { "api_key" => "new" }, removals: [ "api_key" ])
    assert @second_server.errors.include?(:"configuration.api_key")
    assert_equal before, @second_server.reload.attributes
  end

  test "optional removal is explicit and a failed edit retains only public values" do
    @second_server.update!(metadata: { engine: "open_alex" }, auth_config: { api_key: "optional-secret" })
    assert @second_server.save_workspace({}, values: {}, removals: [ "api_key" ])
    refute @second_server.reload.auth_config.key?("api_key")
    @second_server.update!(metadata: { engine: "workspace-demo" }, auth_config: { api_key: "saved-secret", team: "Research" })
    refute @second_server.save_workspace({ name: "" }, values: { "api_key" => "not-for-html", "team" => "Retained" })
    assert_equal({ "team" => "Retained" }, @second_server.workspace_public_values)
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
  end

  test "local transport cannot be coerced and unknown registrations preserve data" do
    refute @second_server.save_workspace({ transport_type: "streamable" }, values: {})
    assert_equal "local", @second_server.reload.transport_type
    @second_server.update!(metadata: { engine: "missing" })
    assert @second_server.save_workspace({ notes: "Safe edit" }, values: { api_key: "ignored" })
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
    assert_equal [], @second_server.workspace_configuration_fields
  end

  test "unchanged argument arrays round trip instead of becoming strings" do
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
      connection_config: { args: [ "one value", "", "last" ], headers: { "X-Custom" => "keep" } })
    assert @second_server.save_workspace({ args: "one value\n\nlast" }, values: {})
    assert_equal [ "one value", "", "last" ], @second_server.reload.args
    assert_equal({ "X-Custom" => "keep" }, @second_server.headers)
  end

  test "disabled stdio cannot construct a client or test a persisted command" do
    previous = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    @second_server.update!(transport_type: "stdio", endpoint: nil, command: "must-not-run", args: [])
    ENV["MCP_STDIO_ENABLED"] = "false"
    before = @second_server.attributes
    with_singleton_replacement(RubyLLM::MCP, :client, ->(**_) { flunk "stdio process construction attempted" }) do
      assert_nil @second_server.client
      refute @second_server.test_connection!
    end
    assert_equal before, @second_server.reload.attributes
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous
  end
end
```

Create `test/controllers/mcp_workspace_configuration_test.rb`:

```ruby
require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceConfigurationTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures
  setup { sign_in_picker_user }

  test "scoped edits use whitelisted credential values and preserve blank secrets" do
    patch account_mcp_server_path(@second, @second_server), params: { mcp_server: {
      name: "Changed", configuration_values: { api_key: "", team: "Public team", ignored: "no" } } }
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
    assert_equal "Public team", @second_server.auth_config.fetch("team")
    refute @second_server.auth_config.key?("ignored")
  end

  test "activation failure remains on setup without writing or echoing secret values" do
    before = @second.mcp_servers.count
    post account_mcp_catalog_index_path(@second), params: { id: "workspace-demo", config: { api_key: "never-echo-this", team: "" } }
    assert_response :unprocessable_entity
    assert_equal before, @second.mcp_servers.count
    refute_includes response.body, "never-echo-this"
    refute flash.to_hash.values.join.include?("never-echo-this")
  end

  test "missing YAML requirements are validated without enabling blocked stdio" do
    assert_no_difference -> { @first.mcp_servers.count } do
      post mcp_catalog_index_path, params: { id: "kchat", config: {} }
    end
    assert_response :unprocessable_entity
    refute @first.mcp_servers.exists?(name: "Infomaniak kChat")
    assert_equal @first, @user.reload.first_account
  end
end
```

- [ ] **Step 2: RED.**

```bash
record configuration-red rails_test test test/models/mcp_server_configuration_test.rb test/controllers/mcp_workspace_configuration_test.rb
```

Expected missing safe-update API and redirect-vs-422 failures. A missing translation
or invalid fixture is not the intended RED; correct test setup before source work.

- [ ] **Step 3: Create `app/models/mcp_server/configuration.rb`, and add
`include Configuration` near the top of `McpServer`.**

```ruby
module McpServer::Configuration
  extend ActiveSupport::Concern
  included { validate :validate_workspace_configuration }

  # @return [Array<Hash>] Declared fields; never inferred from encrypted keys
  def workspace_configuration_fields
    if local?
      Array(Engines::Registry[metadata["engine"]]&.required_config).map(&:deep_symbolize_keys)
    else
      [ { name: "token", label: I18n.t("nosia.mcp.bearer_token"), type: "secret" },
        { name: "api_key", label: I18n.t("nosia.mcp.api_key"), type: "secret" } ]
    end
  end

  # @return [Hash] Only public values suitable for form repopulation
  def workspace_public_values
    source = @workspace_public_values || auth_config || {}
    source.slice(*workspace_configuration_fields.reject { |field| secret_configuration_field?(field) }.map { |field| field[:name].to_s })
  end

  # @param field [Hash] Trusted declaration
  # @return [Boolean] Whether the value must never be repopulated
  def secret_configuration_field?(field) = %w[secret password].include?(field[:type].to_s)

  # @param attributes [Hash] Whitelisted ordinary model attributes
  # @param values [Hash] Whitelisted declared configuration inputs
  # @param removals [Array<String>] Explicit saved-secret removals
  # @return [Boolean] Whether this complete edit was valid and saved
  def save_workspace(attributes, values:, removals: [])
    attrs = attributes.to_h.stringify_keys
    @workspace_configuration_errors = []
    if persisted? && local? && attrs.key?("transport_type") && attrs["transport_type"] != "local"
      @workspace_configuration_errors << [ :transport_type, I18n.t("nosia.mcp_workspace.local_transport_fixed") ]
      attrs.delete("transport_type")
    end
    if attrs["args"].is_a?(String)
      attrs["args"] = attrs["args"] == Array(args).join("\n") ? args : (attrs["args"].empty? ? [] : attrs["args"].lines(chomp: true))
    end
    assign_attributes(attrs)
    config = (auth_config || {}).deep_dup
    incoming = values.stringify_keys
    @workspace_public_values = {}
    workspace_configuration_fields.each do |field|
      key = field[:name].to_s
      secret = secret_configuration_field?(field)
      remove = secret && removals.map(&:to_s).include?(key)
      if remove && incoming[key].present?
        @workspace_configuration_errors << [ :"configuration.#{key}", I18n.t("nosia.mcp_workspace.credential_conflict") ]
      elsif remove
        config.delete(key)
      elsif incoming.key?(key) && (!secret || incoming[key].present?)
        config[key] = incoming[key].to_s
      end
      @workspace_public_values[key] = config[key] unless secret
      @workspace_configuration_errors << [ :"configuration.#{key}", :blank ] if field[:required] && config[key].blank?
    end
    self.auth_config = config
    save
  ensure
    @workspace_configuration_errors = nil
  end

  private
    def validate_workspace_configuration
      Array(@workspace_configuration_errors).each { |attribute, message| errors.add(attribute, message) }
    end
end
```

Fields not exposed by the form are never reconstructed from hidden inputs. Existing
HTTP bearer/API precedence remains in `build_client_config`. Do not alter it.
In the existing `client` method replace its initial local guard with
`return nil if local? || (transport_type == "stdio" && !self.class.stdio_enabled?)`.
At the start of `test_connection!`, before any status write, add
`return false if transport_type == "stdio" && !self.class.stdio_enabled?`.
This enforces the deployment restriction for already-persisted configurations too;
it does not construct a process, change the JSON result shape or weaken validation.

- [ ] **Step 4: Update the server controller's create/new/update and parameter boundary.**
Replace the Task 1 definitions with:

```ruby
def new
  @mcp_server = @account.mcp_servers.build(transport_type: "streamable")
end

def create
  @mcp_server = @account.mcp_servers.build(transport_type: mcp_server_params[:transport_type])
  if @mcp_server.save_workspace(mcp_server_params, values: configuration_values, removals: configuration_removals)
    redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.created")
  else
    render :new, status: :unprocessable_entity
  end
end

def update
  if @mcp_server.save_workspace(mcp_server_params, values: configuration_values, removals: configuration_removals)
    redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.updated")
  else
    render :edit, status: :unprocessable_entity
  end
end

private
  def mcp_server_params
    params.require(:mcp_server).permit(:name, :transport_type, :endpoint, :enabled, :notes, :tags, :command, :args)
  end

  def configuration_values
    root = params.require(:mcp_server)
    allowed = @mcp_server.workspace_configuration_fields.map { |field| field[:name].to_s }
    legacy = root.permit(:token, :api_key).to_h.slice(*allowed)
    legacy.merge(root.fetch(:configuration_values, ActionController::Parameters.new).permit(*allowed).to_h)
  end

  def configuration_removals
    params.require(:mcp_server).permit(remove_credentials: []).fetch(:remove_credentials, [])
  end
```

Only one `private` section belongs in the class. This replaces—not duplicates—the
old broad `connection_config`/`auth_config` browser assignment. The legacy connection
and tool JSON endpoints do not use these CRUD parameters and retain their contracts.

- [ ] **Step 5: Recover catalog errors without a form/service object.** In the
existing public `McpCatalog.activate_for_account`, directly after finding/validating
the template and before choosing registry/YAML activation, add:

```ruby
config_values = config_values.stringify_keys
validate_required(template, config_values)
```

Retain the existing method signature, interpolation, registry/YAML builders and
`RecordInvalid` behavior. Add this public method before `private`:

```ruby
# @param template [Hash] Trusted catalog entry
# @param values [Hash] Submitted values, never stored in session/flash
# @return [Hash] Only declared non-secret fields suitable for HTML
def public_configuration_values(template, values)
  keys = Array(template[:requires_config]).reject { |field| %w[secret password].include?(field[:type].to_s) }.map { |field| field[:name].to_s }
  values.stringify_keys.slice(*keys)
end
```

Replace `McpCatalogController` with:

```ruby
class McpCatalogController < ApplicationController
  include McpScoped

  def index
    @categories = McpCatalog.categories
    @servers_by_category = McpCatalog.all.group_by { |entry| entry[:category] }
    @added_servers = @account.mcp_servers.to_a.group_by { |server| server.metadata["catalog_id"] }
    @activated_ids = @added_servers.keys.compact
  end

  def show
    @template = McpCatalog.find(request.path_parameters[:id])
    if @template
      @mcp_server = @account.mcp_servers.build
      @configuration_values = {}
      @added_servers = @account.mcp_servers.to_a.group_by { |server| server.metadata["catalog_id"] }
    else
      redirect_to mcp_catalog_list_path, alert: t("nosia.mcp.server_not_found")
    end
  end

  def create
    @template = McpCatalog.find(params[:id] || params[:server_id])
    if @template
      values = params.fetch(:config, ActionController::Parameters.new).permit(*Array(@template[:requires_config]).map { |field| field[:name].to_s }).to_h
      begin
        @mcp_server = McpCatalog.activate_for_account(@account, @template[:id], values)
        redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.activated_named", name: @template[:name])
      rescue ActiveRecord::RecordInvalid => error
        @mcp_server = error.record
        render_configuration_error(values)
      rescue StandardError
        @mcp_server = @account.mcp_servers.build
        @mcp_server.errors.add(:base, I18n.t("nosia.mcp.connection_failed"))
        render_configuration_error(values)
      end
    else
      redirect_to mcp_catalog_list_path, alert: t("nosia.mcp.server_not_found")
    end
  end

  private
    def render_configuration_error(values)
      @configuration_values = McpCatalog.public_configuration_values(@template, values)
      @added_servers = @account.mcp_servers.to_a.group_by { |server| server.metadata["catalog_id"] }
      render :show, status: :unprocessable_entity
    end
end
```

Do not change interpolation to rebuild existing server configuration on edits.
Catalog error messages remain escaped; generic exceptions are not echoed in HTML.
Append `:config, :mcp_server` to `Rails.application.config.filter_parameters` in
`config/initializers/filter_parameter_logging.rb`, filtering complete MCP submissions
including extension-secret names that the generic token/key regex would miss.

- [ ] **Step 6: Add both full locale files now; subsequent presentation tasks reuse them.**

`config/locales/en.nosia_mcp_workspace.yml`:

```yaml
en:
  nosia:
    mcp_workspace:
      description: Manage the tools and resources available to your assistants.
      custom_add: Add custom server
      empty: No MCP servers yet
      empty_help: Choose an integration from the catalog or add a custom server.
      filtered_empty: No servers match these filters.
      reset: Reset filters
      browse_catalog: Browse catalog
      connection_status: Connection status
      apply_filters: Apply filters
      all: All
      availability: Availability
      enabled: Enabled for conversations
      disabled: Disabled for conversations
      open: Open
      manage: Manage server
      manage_many: Manage servers
      added: Added to this account
      add: Add to account
      adding: Adding…
      configure: Configure and add
      saving: Saving…
      connection: Connection
      historical: Recorded status, not continuous health monitoring.
      latest_latency: "Last measured response: %{latency}"
      not_loaded: Connect to discover the available capabilities.
      unavailable: Capabilities could not be loaded. Check the connection and try again.
      count_unavailable: unavailable
      no_items: This server reported no items in this section.
      schema: View parameter schema
      required: Required
      delete_title: Remove this server
      delete_help: Remove this account’s configuration, not the external service.
      delete_confirm: "Remove %{name} from %{account}? This does not delete the external service."
      organization: Organization (optional)
      keep_secret: Leave blank to keep the saved credential.
      saved: Credential saved
      remove_secret: Remove saved credential on Save
      secret_reentry: Secret fields are not restored after an unsuccessful save. Re-enter a replacement if needed.
      saved_test: Test saved configuration
      saved_test_help: This does not save or test these edits. It returns to server details, leaving unsaved edits behind.
      local_transport_fixed: Built-in integrations keep their registered local transport.
      missing_registration: This integration’s configuration definition is unavailable. Existing settings are preserved.
      stdio_unavailable: Local process connections are disabled on this deployment.
      credential_conflict: Choose either a replacement or removal, not both.
      optional: Optional
```

`config/locales/fr.nosia_mcp_workspace.yml`:

```yaml
fr:
  nosia:
    mcp_workspace:
      description: Gérez les outils et les ressources disponibles pour vos assistants.
      custom_add: Ajouter un serveur personnalisé
      empty: Aucun serveur MCP pour le moment
      empty_help: Choisissez une intégration du catalogue ou ajoutez un serveur personnalisé.
      filtered_empty: Aucun serveur ne correspond à ces filtres.
      reset: Réinitialiser les filtres
      browse_catalog: Parcourir le catalogue
      connection_status: État de la connexion
      apply_filters: Appliquer les filtres
      all: Tous
      availability: Disponibilité
      enabled: Activé pour les conversations
      disabled: Désactivé pour les conversations
      open: Ouvrir
      manage: Gérer le serveur
      manage_many: Gérer les serveurs
      added: Ajouté à ce compte
      add: Ajouter au compte
      adding: Ajout…
      configure: Configurer et ajouter
      saving: Enregistrement…
      connection: Connexion
      historical: État enregistré, sans surveillance continue de la connexion.
      latest_latency: "Dernier temps de réponse mesuré : %{latency}"
      not_loaded: Connectez le serveur pour découvrir ses fonctionnalités.
      unavailable: Impossible de charger les fonctionnalités. Vérifiez la connexion et réessayez.
      count_unavailable: indisponible
      no_items: Ce serveur n’a signalé aucun élément dans cette section.
      schema: Voir le schéma des paramètres
      required: Obligatoire
      delete_title: Retirer ce serveur
      delete_help: Retirez la configuration de ce compte, sans supprimer le service externe.
      delete_confirm: "Retirer %{name} de %{account} ? Le service externe ne sera pas supprimé."
      organization: Organisation (facultatif)
      keep_secret: Laissez vide pour conserver l’identifiant enregistré.
      saved: Identifiant enregistré
      remove_secret: Supprimer l’identifiant enregistré lors de l’enregistrement
      secret_reentry: Les champs secrets ne sont pas restaurés après un échec. Saisissez à nouveau le remplacement si nécessaire.
      saved_test: Tester la configuration enregistrée
      saved_test_help: Les modifications ne sont ni enregistrées ni testées. Vous reviendrez aux détails du serveur et perdrez les modifications non enregistrées.
      local_transport_fixed: Les intégrations natives conservent leur transport local enregistré.
      missing_registration: La définition de cette intégration est indisponible. Les paramètres existants sont conservés.
      stdio_unavailable: Les connexions par processus local sont désactivées sur ce déploiement.
      credential_conflict: Choisissez un remplacement ou une suppression, pas les deux.
      optional: Facultatif
```

- [ ] **Step 7: GREEN, lint, review and commit exact Task 2 paths.**

```bash
record configuration-green rails_test test test/models/mcp_server_configuration_test.rb test/controllers/mcp_workspace_configuration_test.rb test/controllers/mcp_workspace_scoping_test.rb test/lib/mcp_catalog_registry_test.rb test/helpers/mcp_catalog_helper_test.rb test/internationalization/catalogs_test.rb
record configuration-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/models/mcp_server/configuration.rb app/controllers/mcp_servers_controller.rb app/controllers/mcp_catalog_controller.rb lib/mcp_catalog.rb test/models/mcp_server_configuration_test.rb test/controllers/mcp_workspace_configuration_test.rb
git diff --check
git add app/models/mcp_server.rb app/models/mcp_server/configuration.rb app/controllers/mcp_servers_controller.rb app/controllers/mcp_catalog_controller.rb lib/mcp_catalog.rb config/initializers/filter_parameter_logging.rb config/locales/en.nosia_mcp_workspace.yml config/locales/fr.nosia_mcp_workspace.yml test/models/mcp_server_configuration_test.rb test/controllers/mcp_workspace_configuration_test.rb
git commit -m "feat: Preserve MCP credentials and recover configuration errors"
```

## Task 3: Truthful capability outcomes without changing tool execution

**Files:** `app/models/mcp_server/capability_snapshot.rb`, model include, server
`show`, `test/models/mcp_server_capability_snapshot_test.rb`.

- [ ] **Step 1: Write the complete model test.**

```ruby
require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpServerCapabilitySnapshotTest < ActiveSupport::TestCase
  include McpWorkspaceFixtures

  test "not-ready and unknown engines are not reported as empty successful lists" do
    assert_equal [ :not_loaded ], @second_server.capability_snapshot.values.map(&:state).uniq
    @second_server.update!(status: "ready", metadata: { engine: "missing" })
    assert_equal [ :unavailable ], @second_server.capability_snapshot.values.map(&:state).uniq
  end

  test "local capabilities load without invoking a tool or health check" do
    @health_check = ->(_) { flunk "browsing must not run a connection test" }
    @second_server.update!(status: "ready")
    snapshot = @second_server.capability_snapshot
    assert_equal :loaded, snapshot.fetch(:tools).state
    assert_equal [ "workspace_echo" ], snapshot.fetch(:tools).items.map(&:name)
    assert_equal :loaded, snapshot.fetch(:prompts).state
    assert_empty snapshot.fetch(:prompts).items
    assert @second_server.tools.first.parameters_schema
  end

  test "remote discovery runs once per kind and keeps independent failures distinct" do
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp", status: "ready")
    calls = Hash.new(0)
    client = Object.new
    client.define_singleton_method(:tools) { calls[:tools] += 1; [] }
    client.define_singleton_method(:prompts) { calls[:prompts] += 1; raise "private diagnostic" }
    client.define_singleton_method(:resources) { calls[:resources] += 1; [] }
    @second_server.define_singleton_method(:client) { client }
    snapshot = @second_server.capability_snapshot
    assert_same snapshot, @second_server.capability_snapshot
    assert_equal :loaded, snapshot.fetch(:tools).state
    assert_empty snapshot.fetch(:tools).items
    assert_equal :unavailable, snapshot.fetch(:prompts).state
    assert_equal :loaded, snapshot.fetch(:resources).state
    assert_equal({ tools: 1, prompts: 1, resources: 1 }, calls)
    refute snapshot.fetch(:prompts).to_h.values.join.include?("private diagnostic")
  end
end
```

- [ ] **Step 2: RED.**

```bash
record capabilities-red rails_test test test/models/mcp_server_capability_snapshot_test.rb
```

Expected missing snapshot API. Correct fixture/SDK setup mistakes before counting
the failure as the feature gate.

- [ ] **Step 3: Add the complete concern; include `CapabilitySnapshot` in the model.**

```ruby
module McpServer::CapabilitySnapshot
  extend ActiveSupport::Concern
  Result = Data.define(:state, :items)

  # @return [Hash<Symbol, Result>] Request-local discovery; never executes content
  def capability_snapshot
    signature = [ status, transport_type, metadata["engine"] ]
    if @capability_snapshot_signature != signature
      @capability_snapshot_signature = signature
      @capability_snapshot = %i[tools prompts resources].to_h { |kind| [ kind, discover_capability(kind) ] }
    end
    @capability_snapshot
  end

  private
    def discover_capability(kind)
      return Result.new(:not_loaded, []) unless status_ready?

      if local?
        if Engines::Registry[metadata["engine"]]
          Result.new(:loaded, kind == :tools ? local_tools : [])
        else
          Result.new(:unavailable, [])
        end
      elsif (mcp_client = client)
        items = mcp_client.public_send(kind)
        items.nil? ? Result.new(:unavailable, []) : Result.new(:loaded, Array(items))
      else
        Result.new(:unavailable, [])
      end
    rescue StandardError
      Result.new(:unavailable, [])
    end
end
```

Replace only the `show` body in `McpServersController` with:

```ruby
def show
  @capabilities = @mcp_server.capability_snapshot
  @tools = @capabilities.fetch(:tools).items
  @prompts = @capabilities.fetch(:prompts).items
  @resources = @capabilities.fetch(:resources).items
end
```

The old view can still render until Task 6. Do not change `tools`, `prompts`,
`resources`, `execute_tool`, client construction, transport clients or engine
registration. The snapshot holds no raw failure diagnostic or persisted state.

- [ ] **Step 4: GREEN, lint and commit.**

```bash
record capabilities-green rails_test test test/models/mcp_server_capability_snapshot_test.rb test/models/mcp_server_configuration_test.rb test/models/mcp_server_test.rb test/models/mcp_server_local_test.rb test/controllers/mcp_servers_controller_test.rb test/lib/ruby_llm_mcp_compatibility_test.rb
record capabilities-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/models/mcp_server/capability_snapshot.rb test/models/mcp_server_capability_snapshot_test.rb
git diff --check
git add app/models/mcp_server.rb app/models/mcp_server/capability_snapshot.rb app/controllers/mcp_servers_controller.rb test/models/mcp_server_capability_snapshot_test.rb
git commit -m "feat: Distinguish MCP capability loading outcomes"
```

## Task 4: Shared workspace shell, management rows and browser-first styles

**Files:** header/feedback partials, server list/row/status, layout guards, MCP
helper, MCP stylesheet/import, shell request test and initial system test.

- [ ] **Step 1: Add `test/controllers/mcp_workspace_shell_test.rb`.**

```ruby
require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceShellTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures
  setup { sign_in_picker_user }

  test "list owns its bilingual shell and catalog-first scoped actions" do
    %i[en fr].each do |locale|
      get account_mcp_servers_path(@second), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "head title", text: I18n.t("nosia.mcp.title", locale: locale), count: 1
      assert_select "main h1", text: I18n.t("nosia.mcp.title", locale: locale), count: 1
      assert_select "main .n-workspace-header nav", count: 1
      assert_select "main nav [aria-current=page]", count: 1
      assert_select "[data-workspace-scope]", text: /#{Regexp.escape(@second.name)}/
      assert_select ".n-workspace-primary[href=?]", account_mcp_catalog_index_path(@second)
      assert_select "a[href=?]", new_account_mcp_server_path(@second)
      assert_select ".n-workspace-header a[href=?]", new_chat_path(account_id: @second.id)
      assert_select "[data-mcp-row]", count: 1
      assert_select "[data-mcp-row] a[href=?]", account_mcp_server_path(@second, @second_server)
      assert_select "#drawer-right, #accordion-right-actions", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "account overview exposes the explicit MCP route without changing its default" do
    get account_path(@second)
    assert_response :success
    assert_select "a[href=?]", account_mcp_servers_path(@second), text: I18n.t("nosia.mcp_workspace.manage_many")
    assert_equal @first, @user.reload.first_account
  end

  test "filters distinguish empty results and preserve disabled values" do
    @second_server.update!(enabled: false)
    get account_mcp_servers_path(@second), params: { enabled: "false" }
    assert_select "[data-mcp-row]", count: 1
    get account_mcp_servers_path(@second), params: { status: "ready" }
    assert_select "[data-mcp-filtered-empty]"
    assert_select "a[href=?]", account_mcp_servers_path(@second), text: I18n.t("nosia.mcp_workspace.reset")
    get account_mcp_servers_path(@second), params: { status: "unsupported" }
    assert_select "[data-mcp-row]", count: 1
  end

  test "no-account entry points offer setup and mutations fail closed" do
    sign_in_picker_user(users(:picker_no_account))
    [ mcp_servers_path, new_mcp_server_path, mcp_catalog_index_path, mcp_catalog_path("kchat") ].each do |path|
      get path
      assert_response :success
      assert_select "a[href=?]", new_account_path
      assert_select "[data-mcp-workspace] form", count: 0
    end
    post mcp_servers_path, params: { mcp_server: { name: "Not created" } }
    assert_response :not_found
    get mcp_server_path(@first_server)
    assert_response :not_found
  end

  test "non-MCP drawers remain while secrets and long identifiers are escaped" do
    get api_tokens_path
    assert_select "#drawer-right, #accordion-right-actions", count: 2
    @first_server.update!(name: "<script>#{'LongName' * 30}</script>", notes: "saved-secret")
    get mcp_servers_path
    assert_select "main script", count: 0
    refute_includes response.body, "saved-secret"
    assert_select "[data-mcp-row]", text: /LongName/
  end

  test "legacy credential-bearing endpoints are redacted in list summaries" do
    @first_server.update_columns(transport_type: "streamable", status: "disconnected",
      endpoint: "https://user:embedded-fixture@mcp.example.org/mcp?token=query-fixture")
    get mcp_servers_path
    assert_response :success
    refute_includes response.body, "embedded-fixture"
    refute_includes response.body, "query-fixture"
    assert_includes response.body, "mcp.example.org/mcp"
  end
end
```

Create `test/system/mcp_workspace_test.rb` with this initial focused browser test;
Task 8 extends the same class instead of defining duplicate matrix classes:

```ruby
require "application_system_test_case"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceSystemTest < ApplicationSystemTestCase
  include McpWorkspaceFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  test "management rows reflow and catalog-first action works by keyboard" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: false)
    @second_server.update!(name: "CompteDeRecherche" * 16)
    visit account_mcp_servers_path(@second)
    assert_selector "[data-mcp-workspace] h1", count: 1
    assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
    target = ".n-workspace-primary[href='#{account_mcp_catalog_index_path(@second)}']"
    120.times do
      page.send_keys(:tab)
      break if page.evaluate_script("document.activeElement.matches(arguments[0])", target)
    end
    assert page.evaluate_script("document.activeElement.matches(arguments[0])", target)
    assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.activeElement).outlineWidth)"), :>=, 2
    page.send_keys(:enter)
    assert_current_path account_mcp_catalog_index_path(@second)
    assert_equal @first, @user.reload.first_account
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
```

- [ ] **Step 2: Run request RED and browser RED before adding MCP CSS.**

```bash
record shell-red rails_test test test/controllers/mcp_workspace_shell_test.rb
record shell-browser-red browser_test test/system/mcp_workspace_test.rb
```

Expected missing workspace/list markers and header action/outline. Do not count a
login setup failure as UI RED. The six-page matrix is added after all six views
exist; request tests gate the intermediate presentation tasks.

- [ ] **Step 3: Extend the MCP helper with these display-only methods.**

```ruby
# @return [String, nil] Localized explicit scope; never changes the default
def mcp_scope_label
  t(mcp_scoped? ? "nosia.workspace.account" : "nosia.workspace.default_account", name: @account.name) if @account
end

# @param server [McpServer] Authorized record
# @return [String] Credential-free endpoint/command label
def mcp_endpoint_label(server)
  if server.endpoint.present?
    uri = URI.parse(server.endpoint.match?(%r{\Ahttps?://}i) ? server.endpoint : "https://#{server.endpoint}")
    "#{uri.host}#{uri.path}"
  elsif server.command.present?
    File.basename(server.command.to_s.split.first.to_s)
  else
    t("nosia.mcp.transport.#{server.transport_type}_short")
  end
rescue URI::InvalidURIError
  t("nosia.mcp.transport.#{server.transport_type}_short")
end

# @param server [McpServer] Authorized record
# @return [String] Plain contextual confirmation
def mcp_delete_confirmation(server)
  t("nosia.mcp_workspace.delete_confirm", name: server.name, account: @account.name)
end

# @param id [String] Trusted catalog ID/category
# @return [String] Local-only icon path
def mcp_icon(id)
  { "kchat" => "svg/chats.svg", "kdrive" => "svg/folders.svg", "open_alex" => "svg/file-search.svg",
    "communication" => "svg/chats.svg", "productivity" => "svg/folders.svg" }.fetch(id.to_s, "svg/server.svg")
end
```

These assets were checked in the planning checkout, including `file-search.svg`
and the Settings-provided `server.svg`. Do not add guessed vendor or remote assets.

Create `app/views/mcp_workspace/_header.html.erb`:

```erb
<%# locals: (title:, current: nil, description: nil, catalog: false, server: nil, actions: nil) %>
<% buttons = capture do %>
  <div class="hidden lg:block"><%= link_to t("nosia.nav.new_chat"), mcp_new_chat_path, class: "n-workspace-link" %></div>
  <%= actions %>
<% end %>
<%= render "workspaces/header", title: title, description: description, scope_label: mcp_scope_label, trail: mcp_trail(current: current, catalog: catalog, server: server), actions: buttons %>
```

Create `app/views/mcp_workspace/_feedback.html.erb`:

```erb
<% [ :notice, :alert ].each do |kind| %>
  <% if flash[kind].present? %>
    <div class="n-mcp-message" role="<%= kind == :alert ? 'alert' : 'status' %>"><%= flash[kind] %></div>
  <% end %>
<% end %>
```

In the layout append `|| mcp_workspace_page?` to the existing flash suppression
and legacy-breadcrumb suppression expressions, and `&& !mcp_workspace_page?` to
the existing drawer guard. Preserve every Skills/Accounts/Settings predicate:

```diff
-<%= render "flash" unless agent_skills_workspace_page? %>
+<%= render "flash" unless agent_skills_workspace_page? || mcp_workspace_page? %>
-<% unless agent_skills_workspace_page? || account_workspace_header? %>
+<% unless agent_skills_workspace_page? || account_workspace_header? || mcp_workspace_page? %>
-<% if Current.user && !account_page? && !dashboard_page? && !sources_workspace_page? && !token_usage_workspace_page? && !agent_skills_workspace_page? && !settings_workspace_page? %>
+<% if Current.user && !account_page? && !dashboard_page? && !sources_workspace_page? && !token_usage_workspace_page? && !agent_skills_workspace_page? && !settings_workspace_page? && !mcp_workspace_page? %>
```

These replace the corresponding opening lines, not their nested bodies/closing
tags. Render MCP feedback on every owned screen in Tasks 4–7, including setup.
Add `<%= render "mcp_workspace/feedback" %>` below setup's header.

Make scoped management discoverable with one static shortcut appended to
`app/views/accounts/_configuration.html.erb`, following its existing Skills panel.
Do not change existing panels, counts, permissions or queries:

```erb
<section class="n-account-panel">
  <h2><%= t("nosia.mcp.title") %></h2>
  <%= link_to t("nosia.mcp_workspace.manage_many"), account_mcp_servers_path(@account), class: "n-account-link" %>
</section>
```

Replace `app/views/mcp_servers/index.html.erb` completely:

```erb
<div class="n-workspace n-mcp-workspace" data-mcp-workspace data-mcp-screen="servers" data-controller="mcp-busy" data-action="turbo:submit-start->mcp-busy#start turbo:submit-end->mcp-busy#finish">
  <%= render "mcp_workspace/header", title: t("nosia.mcp.title"), description: t("nosia.mcp_workspace.description"), actions: capture {
    concat link_to(t("nosia.mcp_workspace.custom_add"), mcp_new_path, class: "n-workspace-button")
    concat link_to(t("nosia.mcp_workspace.browse_catalog"), mcp_catalog_list_path, class: "n-workspace-button n-workspace-primary")
  } %>
  <%= render "mcp_workspace/feedback" %>
  <%= form_with url: mcp_index_path, method: :get, class: "n-mcp-filters" do %>
    <% { status: McpServer.statuses.keys, enabled: %w[true false], transport_type: %w[streamable sse stdio local] }.each do |key, values| %>
      <div><%= label_tag key, t(key == :enabled ? "nosia.mcp_workspace.availability" : (key == :status ? "nosia.mcp_workspace.connection_status" : "nosia.mcp.transport_type")), class: "n-mcp-label" %>
      <%= select_tag key, options_for_select([[t("nosia.mcp_workspace.all"), ""]] + values.map { |value|
        label = key == :enabled ? t(value == "true" ? "nosia.mcp_workspace.enabled" : "nosia.mcp_workspace.disabled") : t("nosia.mcp.#{key == :status ? 'status' : 'transport'}.#{value}#{key == :transport_type ? '_short' : ''}")
        [label, value]
      }, params[key]), class: "n-mcp-input" %></div>
    <% end %>
    <%= submit_tag t("nosia.mcp_workspace.apply_filters"), class: "n-workspace-button" %>
    <%= link_to t("nosia.mcp_workspace.reset"), mcp_index_path, class: "n-workspace-link" %>
  <% end %>
  <% if @mcp_servers.any? %>
    <ul class="n-mcp-rows !list-none" role="list"><%= render partial: "mcp_server", collection: @mcp_servers, as: :server %></ul>
  <% elsif @account.mcp_servers.exists? %>
    <section class="n-workspace-panel" data-mcp-filtered-empty><h2 class="n-workspace-section-title"><%= t("nosia.mcp_workspace.filtered_empty") %></h2><%= link_to t("nosia.mcp_workspace.reset"), mcp_index_path, class: "n-workspace-link" %></section>
  <% else %>
    <section class="n-workspace-panel"><h2 class="n-workspace-section-title"><%= t("nosia.mcp_workspace.empty") %></h2><p class="n-workspace-help"><%= t("nosia.mcp_workspace.empty_help") %></p><%= link_to t("nosia.mcp_workspace.browse_catalog"), mcp_catalog_list_path, class: "n-workspace-button n-workspace-primary" %><%= link_to t("nosia.mcp_workspace.custom_add"), mcp_new_path, class: "n-workspace-link" %></section>
  <% end %>
</div>
```

Replace `app/views/mcp_servers/_mcp_server.html.erb` completely:

```erb
<%# locals: (server:) %>
<li class="n-mcp-row" id="<%= dom_id(server) %>" data-mcp-row data-mcp-busy-group>
  <div class="min-w-0"><h2 class="n-workspace-section-title"><%= link_to server.name, mcp_record_path(server), class: "n-workspace-link" %></h2>
    <p class="n-workspace-help"><%= t("nosia.mcp.transport.#{server.transport_type}_short") %> · <%= mcp_endpoint_label(server) %></p>
    <p class="n-workspace-help"><%= t(server.enabled? ? "nosia.mcp_workspace.enabled" : "nosia.mcp_workspace.disabled") %></p>
    <% if server.tags.present? %><p class="n-workspace-help"><%= server.tags %></p><% end %>
    <% if server.latency_ms %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.latest_latency", latency: t("nosia.mcp.latency", milliseconds: number_with_delimiter(server.latency_ms))) %></p><% end %>
  </div>
  <%= render "status", server: server %>
  <div class="n-workspace-actions"><%= link_to t("nosia.mcp_workspace.open"), mcp_record_path(server), class: "n-workspace-link" %><%= link_to t("nosia.actions.edit"), mcp_edit_path(server), class: "n-workspace-link" %>
    <% if server.transport_type == "stdio" && !McpServer.stdio_enabled? %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.stdio_unavailable") %></p>
    <% elsif server.status_ready? %><%= button_to t("nosia.mcp.disconnect"), mcp_disconnect_path(server), method: mcp_disconnect_method, class: "n-workspace-button n-mcp-operation-button", data: { turbo_submits_with: t("nosia.mcp_workspace.saving") }, form: { data: { mcp_operation: true } } %>
    <% else %><%= button_to t("nosia.mcp.connect"), mcp_connect_path(server), method: :post, class: "n-workspace-button n-mcp-operation-button", data: { turbo_submits_with: t("nosia.mcp.testing_connection") }, form: { data: { mcp_operation: true } } %><% end %>
  </div>
</li>
```

Replace `_status.html.erb` with a non-animated, text-labeled status:

```erb
<%# locals: (server:) %>
<span class="n-mcp-status" data-state="<%= server.status %>"><%= t("nosia.mcp.status.#{server.status}") %></span>
```

- [ ] **Step 4: Add the local busy controller, MCP-only styles and one import.**
Create `app/javascript/controllers/mcp_busy_controller.js` before using its markup:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() { this.pending = new Map() }

  start(event) {
    const form = event.target
    if (!form.matches("[data-mcp-operation]")) return
    const group = form.closest("[data-mcp-busy-group]")
    if (!group) return
    const submitter = event.detail.formSubmission.submitter
    const states = Array.from(group.querySelectorAll("button,input[type=submit]"))
      .filter(button => button !== submitter).map(button => [button, button.disabled])
    this.pending.set(form, { group, states })
    states.forEach(([button]) => button.disabled = true)
    group.setAttribute("aria-busy", "true")
  }

  finish(event) { this.restore(event.target) }

  disconnect() {
    this.pending?.forEach((_, form) => this.restore(form))
  }

  restore(form) {
    const entry = this.pending.get(form)
    if (!entry) return
    entry.states.forEach(([button, disabled]) => button.disabled = disabled)
    entry.group.removeAttribute("aria-busy")
    this.pending.delete(form)
  }
}
```

Turbo retains ownership of the submitted button and its busy text. This controller
only disables/restores sibling connection buttons; it never disables inputs before
serialization or starts an operation.

```css
/* app/assets/stylesheets/nosia/mcp_workspace.css */
.n-mcp-workspace { overflow-wrap: anywhere; }
.n-mcp-workspace [hidden] { display: none !important; }
.n-mcp-workspace .n-workspace-link { min-inline-size: 2.75rem; }
.n-mcp-workspace .n-workspace-button:not(.n-workspace-primary):hover { @apply bg-neutral-50 dark:bg-neutral-900; }
.n-mcp-workspace .n-workspace-button:disabled { opacity: 1; }
.n-mcp-workspace form { max-inline-size: 100%; }
.n-mcp-workspace [data-mcp-operation] { inline-size: min(100%, 16rem); }
.n-mcp-operation-button { inline-size: 100%; }
.n-mcp-test-note { max-inline-size: 28rem; }
.n-mcp-rows { @apply grid min-w-0 gap-4; }
.n-mcp-row { @apply grid min-w-0 items-center gap-4 rounded-xl border border-neutral-500 bg-white p-5 dark:bg-neutral-800 lg:grid-cols-[minmax(0,1fr)_auto_auto]; }
.n-mcp-status { @apply inline-flex w-fit items-center rounded-full border border-neutral-500 px-3 py-1 text-sm font-medium; }
.n-mcp-status[data-state=ready] { @apply bg-green-50 text-green-900 dark:bg-green-950 dark:text-green-200; }
.n-mcp-status[data-state=error] { @apply bg-red-50 text-red-900 dark:bg-red-950 dark:text-red-200; }
.n-mcp-filters { @apply flex min-w-0 flex-wrap items-end gap-3; }
.n-mcp-label { @apply mb-2 block text-sm font-medium; }
.n-mcp-input { @apply block min-h-11 w-full min-w-0 rounded-md border border-neutral-500 bg-white px-3 py-2 text-sm text-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:bg-neutral-800 dark:text-neutral-100 dark:focus:outline-green-300; }
.n-mcp-input[aria-invalid=true] { @apply border-red-700 dark:border-red-300; }
.n-mcp-message { @apply min-w-0 rounded-lg border border-neutral-500 bg-white p-4 text-sm dark:bg-neutral-800; }
.n-mcp-grid { @apply grid min-w-0 gap-4 md:grid-cols-2 xl:grid-cols-3; }
.n-mcp-card { @apply flex min-w-0 flex-col gap-3 rounded-xl border border-neutral-500 bg-white p-5 dark:bg-neutral-800; }
.n-mcp-card .n-workspace-actions { @apply mt-auto pt-3; }
.n-mcp-icon { @apply inline-flex h-10 w-10 items-center justify-center rounded-lg bg-green-50 text-green-800 dark:bg-green-950 dark:text-green-200; }
.n-mcp-form-layout { @apply grid min-w-0 items-start gap-5 xl:grid-cols-[minmax(0,2fr)_minmax(16rem,1fr)]; }
.n-mcp-form-sections { @apply grid min-w-0 gap-5; }
.n-mcp-field { @apply min-w-0 space-y-2; }
.n-mcp-errors { @apply min-w-0 rounded-lg border border-red-700 bg-red-50 p-4 text-red-900 focus:outline-2 focus:outline-offset-2 focus:outline-red-700 dark:border-red-300 dark:bg-red-950 dark:text-red-200 dark:focus:outline-red-300; }
.n-mcp-error { @apply text-sm text-red-800 dark:text-red-200; }
.n-mcp-check { @apply flex min-h-11 items-center gap-3 rounded-md focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-green-700 dark:focus-within:outline-green-300; }
.n-mcp-check input { @apply h-5 w-5 shrink-0; }
.n-mcp-workspace summary { @apply min-h-11 cursor-pointer py-3 text-sm font-medium focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:focus:outline-green-300; }
.n-mcp-tabs { @apply flex min-w-0 flex-wrap gap-2 border-b border-neutral-500; }
.n-mcp-tabs [aria-selected=true] { @apply border-b-2 border-green-700 text-green-900 dark:border-green-300 dark:text-green-200; }
.n-mcp-panel { @apply min-w-0 space-y-4 rounded-md; }
.n-mcp-panel:focus { @apply outline-2 outline-offset-2 outline-green-700 dark:outline-green-300; }
.n-mcp-workspace pre { white-space: pre-wrap; overflow-wrap: anywhere; @apply min-w-0 rounded-md bg-neutral-50 p-3 text-xs text-neutral-900 dark:bg-neutral-900 dark:text-neutral-100; }
.n-mcp-danger { @apply flex flex-wrap items-center justify-between gap-4 border-t border-neutral-500 pt-6; }
main:has([data-mcp-workspace]) { min-width: 0; scroll-padding-block-end: 6rem; }
```

```css
@import "../stylesheets/nosia/mcp_workspace.css" layer(utilities);
```

Do not restyle `.n-workspace-*` outside `.n-mcp-workspace`; existing other tools
must keep their output. Check filter translation keys against the existing MCP
locale before GREEN; add any missing paired keys rather than English literals.

- [ ] **Step 5: GREEN and commit.** The temporary catalog still has its old layout;
the keyboard test only checks the preserved destination, not future catalog cards.

```bash
record shell-build rails_test tailwindcss:build
record shell-green rails_test test test/controllers/mcp_workspace_shell_test.rb test/controllers/mcp_workspace_scoping_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/internationalization/catalogs_test.rb
record shell-browser-green browser_test test/system/mcp_workspace_test.rb
git diff --check
git add app/helpers/mcp_workspace_helper.rb app/views/mcp_workspace app/views/mcp_servers/index.html.erb app/views/mcp_servers/_mcp_server.html.erb app/views/mcp_servers/_status.html.erb app/views/accounts/_configuration.html.erb app/views/layouts/application.html.erb app/assets/stylesheets/nosia/mcp_workspace.css app/assets/tailwind/application.css app/javascript/controllers/mcp_busy_controller.js test/controllers/mcp_workspace_shell_test.rb test/system/mcp_workspace_test.rb
git commit -m "feat: Align MCP server management with workspace navigation"
```

The old index-delete assertion must be intentionally migrated when the detail
danger area lands in Task 6: deletion is not removed. Do not silently skip it to
claim all legacy MCP tests pass at this intermediate task.

## Task 5: Catalog cards and metadata-driven configuration recovery

**Files:** catalog views, `app/helpers/mcp_forms_helper.rb`, shared errors partial,
`app/javascript/controllers/mcp_secrets_controller.js`, catalog request test.

- [ ] **Step 1: Write `test/controllers/mcp_workspace_catalog_test.rb`.**

```ruby
require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceCatalogTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures
  setup { sign_in_picker_user }

  test "catalog uses scoped cards and added means manage not connected" do
    %i[en fr].each do |locale|
      get account_mcp_catalog_index_path(@second), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "[data-mcp-screen=catalog] h1", count: 1
      assert_select "[data-mcp-entry='workspace-demo']" do
        assert_select "a[href=?]", account_mcp_server_path(@second, @second_server)
        assert_select "button[disabled]", count: 0
        assert_select "svg[aria-hidden=true]", minimum: 1
      end
      assert_select "#drawer-right, #accordion-right-actions", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "failed setup retains public fields with linked errors and empty secrets" do
    @second_server.update!(metadata: { engine: "workspace-demo" })
    post account_mcp_catalog_index_path(@second), params: { id: "workspace-demo", config: { api_key: "", team: "Retained public value" } }
    assert_response :unprocessable_entity
    assert_select "[data-form-errors-target=summary][tabindex='-1'][role=alert]"
    assert_select "a[data-error-field=config_api_key][href='#config_api_key']"
    assert_select "input#config_team[value='Retained public value']"
    assert_select "input#config_api_key[type=password][value='']"
    assert_select "input#config_api_key[aria-invalid=true]"
    assert_select "form[action=?]", account_mcp_catalog_index_path(@second)
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    refute_includes response.body, "saved-secret"
  end

  test "public metadata stays public and declared secrets stay secret" do
    assert_equal [ "drive_id" ], McpCatalog.public_configuration_values(McpCatalog.find("kdrive"), { token: "hide", drive_id: "123" }).keys
    assert_empty McpCatalog.public_configuration_values(McpCatalog.find("kchat"), { kchat_token: "hide", kchat_team_name: "hide-team" })
    get mcp_catalog_path("kchat")
    if McpServer.stdio_enabled?
      assert_select "input#config_kchat_team_name[type=password]"
    else
      assert_select "[data-mcp-transport-unavailable]"
      assert_select "form[action=?]", mcp_catalog_index_path, count: 0
    end
  end
end
```

- [ ] **Step 2: RED.**

```bash
record catalog-red rails_test test test/controllers/mcp_workspace_catalog_test.rb
```

Expected missing owned-shell, cards, form preservation and error associations.

- [ ] **Step 3: Add the complete form helper.**

```ruby
module McpFormsHelper
  # @param name [String, Symbol] Model attribute or configuration.name
  # @param catalog [Boolean] Whether the input belongs to catalog configuration
  # @return [String] Stable input ID
  def mcp_field_id(name, catalog: false)
    key = name.to_s
    if key.start_with?("configuration.")
      "#{catalog ? 'config' : 'mcp_server_configuration_values'}_#{key.delete_prefix('configuration.')}"
    else
      "mcp_server_#{key}"
    end
  end

  # @param field [Hash] Trusted field metadata
  # @param template [Hash, nil] Catalog entry for existing localization support
  # @return [String] Escaped by the caller, never HTML-safe
  def mcp_configuration_label(field, template: nil)
    template ? catalog_field_text(template, field, :label) : field[:label].presence || field[:name].to_s.humanize
  end

  # @param record [McpServer] Possibly invalid model
  # @param catalog [Boolean] Whether field IDs belong to catalog setup
  # @return [Array<Hash>] Messages and optional valid field targets; no values
  def mcp_error_items(record, catalog: false)
    record.errors.flat_map do |error|
      if catalog && error.type == :missing_required_config
        error.options.fetch(:fields).split(", ").map do |key|
          field = Array(@template[:requires_config]).find { |item| item[:name].to_s == key }
          { message: "#{mcp_configuration_label(field, template: @template)} #{I18n.t('errors.messages.blank')}", target: mcp_field_id("configuration.#{key}", catalog: true) } if field
        end.compact
      else
        attribute = error.attribute.to_s
        editable = attribute.start_with?("configuration.") || %w[name transport_type endpoint command args tags notes enabled].include?(attribute)
        { message: error.full_message, target: editable && !catalog ? mcp_field_id(attribute) : nil }
      end
    end
  end

  # @param record [McpServer] Possibly invalid model
  # @param name [String, Symbol] Model or configuration attribute
  # @param catalog [Boolean] Whether field IDs belong to catalog setup
  # @return [Hash] Connected hint/error attributes
  def mcp_field_options(record, name, catalog: false)
    id = mcp_field_id(name, catalog: catalog)
    invalid = mcp_error_items(record, catalog: catalog).any? { |item| item[:target] == id }
    { id: id, aria: { invalid: invalid ? "true" : nil, describedby: "#{id}_help#{invalid ? " #{id}_error" : ''}" } }
  end
end
```

Create `app/views/mcp_workspace/_errors.html.erb`:

```erb
<%# locals: (record:, catalog: false) %>
<% if record.errors.any? %>
  <section class="n-mcp-errors" data-form-errors-target="summary" role="alert" tabindex="-1" aria-labelledby="mcp-errors-title">
    <h2 id="mcp-errors-title" class="n-workspace-section-title"><%= t("nosia.mcp.errors", count: record.errors.count) %></h2>
    <ul class="!list-none" role="list"><% mcp_error_items(record, catalog: catalog).each do |item| %><li>
      <% if item[:target] %><%= link_to item[:message], "##{item[:target]}", class: "n-workspace-link", data: { error_field: item[:target] } %><% else %><%= item[:message] %><% end %>
    </li><% end %></ul>
  </section>
<% end %>
```

Create `app/views/mcp_catalog/_fields.html.erb` (shared by local server edits):

```erb
<%# locals: (fields:, values:, record:, catalog: true, template: nil) %>
<% fields.each do |field| %>
  <% key = field[:name].to_s; attribute = "configuration.#{key}"; secret = %w[secret password].include?(field[:type].to_s) %>
  <% id = mcp_field_id(attribute, catalog: catalog); input_name = catalog ? "config[#{key}]" : "mcp_server[configuration_values][#{key}]" %>
  <% saved = !catalog && record.persisted? && secret && (record.attribute_in_database("auth_config") || {})[key].present? %>
  <% options = mcp_field_options(record, attribute, catalog: catalog).merge(class: "n-mcp-input", required: field[:required] && !saved) %>
  <div class="n-mcp-field">
    <%= label_tag id, class: "n-mcp-label" do %><%= mcp_configuration_label(field, template: template) %> · <%= t(field[:required] ? "nosia.mcp_workspace.required" : "nosia.mcp_workspace.optional") %><% end %>
    <% if saved %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.saved") %></p><% end %>
    <% if secret %><%= password_field_tag input_name, "", options.merge(autocomplete: "off", data: { mcp_secret: true }) %>
    <% elsif field[:type].to_s == "select" %><%= select_tag input_name, options_for_select(field[:options] || [], values[key]), options %>
    <% elsif field[:type].to_s == "textarea" %><%= text_area_tag input_name, values[key], options.merge(rows: 3) %>
    <% else %><%= text_field_tag input_name, values[key], options %>
    <% end %>
    <p id="<%= id %>_help" class="n-workspace-help"><%= template ? catalog_field_text(template, field, :description) : field[:description] %> <%= t(saved ? "nosia.mcp_workspace.keep_secret" : "nosia.mcp_workspace.secret_reentry") if secret %></p>
    <% errors = mcp_error_items(record, catalog: catalog).select { |item| item[:target] == id } %>
    <% if errors.any? %><p id="<%= id %>_error" class="n-mcp-error"><%= errors.map { |item| item[:message] }.join(" ") %></p><% end %>
    <% if saved %><label class="n-mcp-check"><%= check_box_tag "mcp_server[remove_credentials][]", key, false %><span><%= t("nosia.mcp_workspace.remove_secret") %></span></label><% end %>
  </div>
<% end %>
```

Create `app/javascript/controllers/mcp_secrets_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  clear() {
    this.element.querySelectorAll("[data-mcp-secret]").forEach(input => {
      input.value = ""
      input.defaultValue = ""
    })
  }
}
```

- [ ] **Step 4: Replace the catalog views and add the entry partial.**

`app/views/mcp_catalog/index.html.erb`:

```erb
<div class="n-workspace n-mcp-workspace" data-mcp-workspace data-mcp-screen="catalog">
  <%= render "mcp_workspace/header", title: t("nosia.mcp.catalog_title"), catalog: true, description: t("nosia.mcp.catalog_help"), actions: link_to(t("nosia.mcp.my_servers"), mcp_index_path, class: "n-workspace-link") %>
  <%= render "mcp_workspace/feedback" %>
  <% if @servers_by_category.any? %>
    <% @categories.each do |category| %><% entries = @servers_by_category[category[:id].to_s]; next if entries.blank? %>
      <section class="space-y-4"><h2 class="n-workspace-section-title"><%= catalog_category_name(category) %></h2>
        <% if category[:description] %><p class="n-workspace-help"><%= catalog_category_description(category) %></p><% end %>
        <ul class="n-mcp-grid !list-none" role="list"><%= render partial: "entry", collection: entries, as: :entry %></ul>
      </section>
    <% end %>
  <% else %><section class="n-workspace-panel"><h2><%= t("nosia.mcp.catalog_empty") %></h2></section><% end %>
</div>
```

`app/views/mcp_catalog/_entry.html.erb`:

```erb
<%# locals: (entry:) %>
<% added = @added_servers.fetch(entry[:id], []); blocked = entry[:transport_type] == "stdio" && !McpServer.stdio_enabled? %>
<li class="n-mcp-card" data-mcp-entry="<%= entry[:id] %>">
  <span class="n-mcp-icon"><%= inline_svg mcp_icon(entry[:id]), aria_hidden: true, class: "h-6 w-6" %></span>
  <h3 class="n-workspace-section-title"><%= link_to entry[:name], mcp_template_path(entry[:id]), class: "n-workspace-link" %></h3>
  <p class="n-workspace-help"><%= catalog_entry_description(entry) %></p>
  <p class="n-workspace-help"><%= Array(entry[:capabilities]).map { |value| catalog_capability_label(value) }.join(" · ") %></p>
  <% if added.any? %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.added") %></p><% end %>
  <div class="n-workspace-actions">
    <% if added.any? %><%= link_to t(added.one? ? "nosia.mcp_workspace.manage" : "nosia.mcp_workspace.manage_many"), added.one? ? mcp_record_path(added.first) : mcp_index_path, class: "n-workspace-button" %>
    <% elsif blocked %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.stdio_unavailable") %></p>
    <% elsif Array(entry[:requires_config]).any? %><%= link_to t("nosia.mcp_workspace.configure"), mcp_template_path(entry[:id]), class: "n-workspace-button n-workspace-primary" %>
    <% else %><%= button_to t("nosia.mcp_workspace.add"), mcp_catalog_list_path, params: { id: entry[:id] }, class: "n-workspace-button n-workspace-primary", data: { turbo_submits_with: t("nosia.mcp_workspace.adding") } %><% end %>
  </div>
</li>
```

`app/views/mcp_catalog/show.html.erb`:

```erb
<% content_for :head, tag.meta(name: "turbo-cache-control", content: "no-cache") %>
<div class="n-workspace n-mcp-workspace" data-mcp-workspace data-mcp-screen="catalog-setup">
  <%= render "mcp_workspace/header", title: @template[:name], current: @template[:name], catalog: true, description: catalog_entry_description(@template) %>
  <%= render "mcp_workspace/feedback" %>
  <% added = @added_servers.fetch(@template[:id], []) %>
  <% blocked = @template[:transport_type] == "stdio" && !McpServer.stdio_enabled? %>
  <% if added.any? && @mcp_server.errors.empty? %>
    <section class="n-workspace-panel"><h2 class="n-workspace-section-title"><%= t("nosia.mcp_workspace.added") %></h2><%= link_to t(added.one? ? "nosia.mcp_workspace.manage" : "nosia.mcp_workspace.manage_many"), added.one? ? mcp_record_path(added.first) : mcp_index_path, class: "n-workspace-button" %></section>
  <% elsif blocked %>
    <section class="n-workspace-panel" data-mcp-transport-unavailable data-controller="form-errors"><%= tag.div role: (@mcp_server.errors.any? ? 'alert' : 'status'), tabindex: -1, data: (@mcp_server.errors.any? ? { form_errors_target: 'summary' } : {}) do %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.stdio_unavailable") %></p><% end %><%= link_to t("nosia.actions.cancel"), mcp_catalog_list_path, class: "n-workspace-link" %></section>
  <% else %>
    <%= form_with url: mcp_catalog_list_path, method: :post, class: "n-mcp-form-sections", data: { controller: "form-errors html-form mcp-secrets", action: "click->form-errors#focusField invalid->form-errors#revealInvalid:capture turbo:before-fetch-request->html-form#requestHTML turbo:before-cache@document->mcp-secrets#clear" } do %>
      <%= hidden_field_tag :id, @template[:id] %>
      <%= render "mcp_workspace/errors", record: @mcp_server, catalog: true %>
      <section class="n-workspace-panel space-y-4"><h2 class="n-workspace-section-title"><%= t("nosia.mcp.configuration") %></h2>
        <% if Array(@template[:requires_config]).any? %><%= render "fields", fields: @template[:requires_config], values: @configuration_values, record: @mcp_server, catalog: true, template: @template %>
        <% else %><p class="n-workspace-help"><%= t("nosia.mcp.no_config") %></p><% end %>
      </section>
      <section class="n-workspace-panel"><h2 class="n-workspace-section-title"><%= t("nosia.mcp.capabilities") %></h2><p class="n-workspace-help"><%= Array(@template[:capabilities]).map { |value| catalog_capability_label(value) }.join(" · ") %></p></section>
      <div class="n-workspace-actions"><%= submit_tag t("nosia.mcp_workspace.add"), class: "n-workspace-button n-workspace-primary", data: { turbo_submits_with: t("nosia.mcp_workspace.adding") } %><%= link_to t("nosia.actions.cancel"), mcp_catalog_list_path, class: "n-workspace-link" %></div>
    <% end %>
  <% end %>
</div>
```

422 states deliberately re-expose the recoverable form even if a direct POST was
made for an already-added template. Ordinary GETs show management; backend duplicate
validation is not replaced or relaxed. Never put secret values into hidden inputs.
Blocked stdio gets an explanatory focused alert on a failed POST and catalog
recovery, not a linked summary pointing to credential fields that are not rendered.

- [ ] **Step 5: GREEN, build and commit.**

```bash
record catalog-build rails_test tailwindcss:build
record catalog-green rails_test test test/controllers/mcp_workspace_catalog_test.rb test/controllers/mcp_workspace_configuration_test.rb test/controllers/mcp_workspace_scoping_test.rb test/helpers/mcp_catalog_helper_test.rb test/lib/mcp_catalog_registry_test.rb test/internationalization/catalogs_test.rb
git diff --check
git add app/helpers/mcp_forms_helper.rb app/views/mcp_catalog app/views/mcp_workspace/_errors.html.erb app/javascript/controllers/mcp_secrets_controller.js test/controllers/mcp_workspace_catalog_test.rb
git commit -m "feat: Present account-scoped MCP catalog and safe setup recovery"
```

## Task 6: Server details, safe connection feedback and progressive tabs

**Files:** detail/connection/capability partials, MCP helper, existing tab controller,
`test/controllers/mcp_workspace_detail_test.rb`, intentional legacy MCP assertions.

- [ ] **Step 1: Write the detail request test.**

```ruby
require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceDetailTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures
  setup { sign_in_picker_user }

  test "not-loaded counts are unknown and existing operations remain scoped" do
    get account_mcp_server_path(@second, @second_server)
    assert_response :success
    assert_select "[data-mcp-screen=detail] h1", text: @second_server.name
    assert_select "[data-tab-key=tools]", text: /—/
    assert_select "[data-mcp-capability=tools]", text: /#{Regexp.escape(I18n.t('nosia.mcp_workspace.not_loaded'))}/
    assert_select "form[action=?]", account_mcp_server_connection_path(@second, @second_server)
    assert_select "[data-mcp-danger] form[action=?]", account_mcp_server_path(@second, @second_server)
    assert_select "button", text: I18n.t("nosia.mcp.test"), count: 0
  end

  test "ready local schemas use the real SDK method and do not execute tools" do
    @second_server.update!(status: "ready")
    get account_mcp_server_path(@second, @second_server)
    assert_select "[data-tab-key=tools]", text: /1/
    assert_select "[data-mcp-capability=tools] details pre", text: /query/
    assert_select "[data-mcp-capability=prompts]", text: /#{Regexp.escape(I18n.t('nosia.mcp_workspace.no_items'))}/
    assert_select "form[action=?] input[name=_method][value=delete]", account_mcp_server_connection_path(@second, @second_server)
    assert_select "main script", count: 0
  end

  test "connection failure shows safe recovery while legacy JSON stays unchanged" do
    @second_server.update!(api_key: "bad")
    post account_mcp_server_connection_test_path(@second, @second_server)
    assert_response :see_other
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    follow_redirect!
    assert_select "#connection-test-result[role=alert]"
    assert_select "a[href=?]", edit_account_mcp_server_path(@second, @second_server)
    refute_includes response.body, "credential-echo-bad"
    post test_connection_mcp_server_path(@first_server), as: :json
    assert_response :success
    assert_equal %w[latency message status success], response.parsed_body.keys.sort
  end

  test "real prompt argument objects render metadata without fetching messages" do
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp", status: "ready")
    prompt = RubyLLM::MCP::Prompt.new(Object.new, { "name" => "summary", "description" => "Read-only metadata",
      "arguments" => [{ "name" => "topic", "description" => "Research topic", "required" => true }] })
    prompt.define_singleton_method(:fetch) { |*| flunk "prompt was executed" }
    resource = Struct.new(:uri, :description, :mime_type).new("mcp://example/record", "Resource metadata", "text/plain")
    client = Struct.new(:tools, :prompts, :resources).new([], [prompt], [resource])
    with_singleton_replacement(RubyLLM::MCP, :client, ->(**_) { client }) do
      get account_mcp_server_path(@second, @second_server)
      assert_response :success
      assert_select "[data-mcp-capability=prompts] dt", text: /topic.*Required/
      assert_select "[data-mcp-capability=resources] h3", text: "mcp://example/record"
    end
  end

  test "details never echo credential-bearing endpoint query or userinfo" do
    @first_server.update_columns(transport_type: "streamable", status: "disconnected",
      endpoint: "https://user:embedded-fixture@mcp.example.org/mcp?token=query-fixture")
    get mcp_server_path(@first_server)
    assert_response :success
    refute_includes response.body, "embedded-fixture"
    refute_includes response.body, "query-fixture"
    assert_includes response.body, "mcp.example.org/mcp"
  end
end
```

- [ ] **Step 2: RED.**

```bash
record detail-red rails_test test test/controllers/mcp_workspace_detail_test.rb
```

Expected missing truthful markers, schema disclosure, scoped operations and danger
area—not an exception from invoking an SDK object as a Hash.

- [ ] **Step 3: Add display helpers and replace all detail markup.**
Append these public methods to `McpWorkspaceHelper`:

```ruby
# @param result [McpServer::CapabilitySnapshot::Result]
# @return [String, Integer] Truthful count, not a zero for unavailable content
def mcp_capability_count(result)
  result.state == :loaded ? result.items.size : (result.state == :not_loaded ? "—" : t("nosia.mcp_workspace.count_unavailable"))
end

# @param tool [RubyLLM::Tool] Existing SDK object
# @return [Hash, nil] Available schema without executing the tool
def mcp_tool_schema(tool)
  schema = tool.parameters_schema if tool.respond_to?(:parameters_schema)
  schema if schema.is_a?(Hash)
end

# @param prompt [RubyLLM::MCP::Prompt]
# @return [Array<Hash>] Local argument metadata, not prompt messages
def mcp_prompt_arguments(prompt)
  Array(prompt.arguments).filter_map do |argument|
    value = argument.to_h if argument.respond_to?(:to_h)
    value.deep_symbolize_keys if value.is_a?(Hash)
  end
end
```

`app/views/mcp_servers/_connection_controls.html.erb`:

```erb
<%# locals: (server:) %>
<div class="n-workspace-actions" data-mcp-busy-group>
  <%= link_to t("nosia.actions.edit"), mcp_edit_path(server), class: "n-workspace-button" %>
  <% if server.transport_type == "stdio" && !McpServer.stdio_enabled? %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.stdio_unavailable") %></p>
  <% else %>
    <% unless server.status_ready? %><%= button_to t("nosia.mcp.connect"), mcp_connect_path(server), method: :post, class: "n-workspace-button n-workspace-primary n-mcp-operation-button", data: { turbo_submits_with: t("nosia.mcp.testing_connection") }, form: { data: { mcp_operation: true } } %><% end %>
    <%= button_to t("nosia.mcp.test_connection_short"), mcp_test_path(server), method: :post, class: "n-workspace-button n-mcp-operation-button #{'n-workspace-primary' if server.status_ready?}", data: { turbo_submits_with: t("nosia.mcp.testing_connection") }, form: { data: { mcp_operation: true } } %>
    <% if server.status_ready? %><%= button_to t("nosia.mcp.disconnect"), mcp_disconnect_path(server), method: mcp_disconnect_method, class: "n-workspace-button n-mcp-operation-button", data: { turbo_submits_with: t("nosia.mcp_workspace.saving") }, form: { data: { mcp_operation: true } } %><% end %>
  <% end %>
</div>
```

Replace `app/views/mcp_servers/_connection_test_result.html.erb`:

```erb
<%# locals: (server:, success:) %>
<section id="connection-test-result" class="n-mcp-message" role="<%= success ? 'status' : 'alert' %>" aria-labelledby="connection-test-heading">
  <h2 id="connection-test-heading" class="n-workspace-section-title"><%= t(success ? "nosia.mcp.connection_established" : "nosia.mcp.connection_failed") %></h2>
  <p class="n-workspace-help"><%= t(success ? "nosia.mcp.connection_test_success_help" : "nosia.mcp.connection_test_failure_help") %></p>
  <% if success && server.latency_ms %><p class="n-workspace-help"><%= t("nosia.mcp.connection_test_latency", latency: t("nosia.mcp.latency", milliseconds: number_with_delimiter(server.latency_ms))) %></p><% end %>
  <% unless success %><%= link_to t("nosia.actions.edit"), mcp_edit_path(server), class: "n-workspace-link" %><% end %>
</section>
```

`app/views/mcp_servers/_capabilities.html.erb`:

```erb
<%# locals: (kind:, result:) %>
<section id="<%= kind %>" class="n-mcp-panel" data-mcp-server-target="panel" data-tab-key="<%= kind %>" data-mcp-capability="<%= kind %>">
  <h2 class="n-workspace-section-title"><%= t("nosia.mcp.#{kind}") %></h2>
  <% if result.state != :loaded %><p class="n-workspace-help"><%= t(result.state == :not_loaded ? "nosia.mcp_workspace.not_loaded" : "nosia.mcp_workspace.unavailable") %></p>
  <% elsif result.items.empty? %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.no_items") %></p>
  <% else %>
    <ul class="n-mcp-rows !list-none" role="list"><% result.items.each do |item| %><li class="n-workspace-panel">
      <% if kind == :resources %>
        <h3 class="n-workspace-section-title"><%= item.uri %></h3><p class="n-workspace-help"><%= item.description %></p>
        <% if item.respond_to?(:mime_type) %><p class="n-workspace-help"><%= t("nosia.mcp.mime_type", type: item.mime_type) %></p><% end %>
      <% else %>
        <h3 class="n-workspace-section-title"><%= item.name %></h3><p class="n-workspace-help"><%= item.description %></p>
        <% if kind == :tools && (schema = mcp_tool_schema(item)) %><details><summary><%= t("nosia.mcp_workspace.schema") %></summary><pre><%= JSON.pretty_generate(schema) %></pre></details><% end %>
        <% if kind == :prompts %><dl><% mcp_prompt_arguments(item).each do |argument| %><dt class="n-mcp-label"><%= argument[:name] %> <%= t("nosia.mcp_workspace.required") if argument[:required] %></dt><dd class="n-workspace-help"><%= argument[:description] %></dd><% end %></dl><% end %>
      <% end %>
    </li><% end %></ul>
  <% end %>
</section>
```

Replace `app/views/mcp_servers/show.html.erb`:

```erb
<div class="n-workspace n-mcp-workspace" data-mcp-workspace data-mcp-screen="detail" data-controller="mcp-server mcp-busy" data-action="turbo:submit-start->mcp-busy#start turbo:submit-end->mcp-busy#finish hashchange@window->mcp-server#restore popstate@window->mcp-server#restore turbo:render@document->mcp-server#connect">
  <%= render "mcp_workspace/header", title: @mcp_server.name, current: @mcp_server.name, actions: render("connection_controls", server: @mcp_server) %>
  <%= render "mcp_workspace/feedback" %>
  <div class="n-workspace-actions"><%= render "status", server: @mcp_server %><p class="n-workspace-help"><%= t(@mcp_server.enabled? ? "nosia.mcp_workspace.enabled" : "nosia.mcp_workspace.disabled") %></p></div>
  <% if flash[:connection_test].present? %><%= render "connection_test_result", server: @mcp_server, success: flash[:connection_test] == "success" %>
  <% elsif @mcp_server.last_error.present? && flash[:alert].blank? %><%= render "connection_test_result", server: @mcp_server, success: false %><% end %>
  <nav class="n-mcp-tabs" aria-label="<%= t('nosia.mcp.capabilities') %>" data-mcp-server-target="list" data-action="focusout->mcp-server#resetRoving">
    <% %i[overview tools prompts resources].each do |kind| %><%= link_to "##{kind}", id: "mcp-tab-#{kind}", class: "n-workspace-link", data: { mcp_server_target: "tab", tab_key: kind, action: "click->mcp-server#select keydown->mcp-server#key" } do %><%= t("nosia.mcp.#{kind}") %><% unless kind == :overview %> · <%= mcp_capability_count(@capabilities.fetch(kind)) %><% end %><% end %><% end %>
  </nav>
  <section id="overview" class="n-mcp-panel" data-mcp-server-target="panel" data-tab-key="overview">
    <h2 class="n-workspace-section-title"><%= t("nosia.mcp.overview") %></h2>
    <div class="n-mcp-grid"><section class="n-workspace-panel"><h3 class="n-workspace-section-title"><%= t("nosia.mcp.configuration") %></h3><dl>
      <dt class="n-mcp-label"><%= t("nosia.mcp.transport_type") %></dt><dd><%= t("nosia.mcp.transport.#{@mcp_server.transport_type}_short") %></dd>
      <dt class="n-mcp-label"><%= t("nosia.mcp.endpoint") %></dt><dd><%= mcp_endpoint_label(@mcp_server) %></dd>
      <% if @mcp_server.tags.present? %><dt class="n-mcp-label"><%= t("nosia.mcp.tags") %></dt><dd><%= @mcp_server.tags %></dd><% end %>
    </dl></section>
    <section class="n-workspace-panel"><h3 class="n-workspace-section-title"><%= t("nosia.mcp_workspace.connection") %></h3><p class="n-workspace-help"><%= t("nosia.mcp_workspace.historical") %></p>
      <% if @mcp_server.last_connected_at %><p class="n-workspace-help"><%= t("nosia.mcp.last_connected") %>: <%= l(@mcp_server.last_connected_at, format: :short) %></p><% end %>
      <% if @mcp_server.latency_ms %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.latest_latency", latency: t("nosia.mcp.latency", milliseconds: number_with_delimiter(@mcp_server.latency_ms))) %></p><% end %>
    </section></div>
    <% if @mcp_server.notes.present? %><section class="n-workspace-panel"><h3 class="n-workspace-section-title"><%= t("nosia.mcp.notes") %></h3><p class="n-workspace-help whitespace-pre-wrap"><%= @mcp_server.notes %></p></section><% end %>
  </section>
  <% %i[tools prompts resources].each do |kind| %><%= render "capabilities", kind: kind, result: @capabilities.fetch(kind) %><% end %>
  <section class="n-mcp-danger" data-mcp-danger><div><h2 class="n-workspace-section-title"><%= t("nosia.mcp_workspace.delete_title") %></h2><p class="n-workspace-help"><%= t("nosia.mcp_workspace.delete_help") %></p></div><%= button_to t("nosia.actions.delete"), mcp_record_path(@mcp_server), method: :delete, class: "n-workspace-button n-workspace-danger", data: { turbo_confirm: mcp_delete_confirmation(@mcp_server) } %></section>
</div>
```

- [ ] **Step 4: Replace the tab controller completely.** It reads local preloaded
panels only; it does not request or execute provider content.

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "tab", "panel"]

  connect() {
    this.listTarget.setAttribute("role", "tablist")
    this.tabTargets.forEach(tab => {
      tab.setAttribute("role", "tab")
      tab.setAttribute("aria-controls", tab.dataset.tabKey)
    })
    this.panelTargets.forEach(panel => {
      panel.setAttribute("role", "tabpanel")
      panel.setAttribute("aria-labelledby", `mcp-tab-${panel.dataset.tabKey}`)
      panel.tabIndex = 0
    })
    this.restore()
  }

  disconnect() {
    this.listTarget.removeAttribute("role")
    this.tabTargets.forEach(tab => ["role", "aria-controls", "aria-selected", "tabindex"].forEach(name => tab.removeAttribute(name)))
    this.panelTargets.forEach(panel => {
      panel.hidden = false
      ;["role", "aria-labelledby", "tabindex"].forEach(name => panel.removeAttribute(name))
    })
  }

  restore() {
    const candidate = location.hash.slice(1)
    this.activate(this.tabTargets.some(tab => tab.dataset.tabKey === candidate) ? candidate : "overview")
  }

  select(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    const key = event.currentTarget.dataset.tabKey
    this.activate(key)
    history.pushState(null, "", `#${key}`)
  }

  key(event) {
    const index = this.tabTargets.indexOf(event.currentTarget)
    let next
    if (event.key === "ArrowLeft") next = (index - 1 + this.tabTargets.length) % this.tabTargets.length
    if (event.key === "ArrowRight") next = (index + 1) % this.tabTargets.length
    if (event.key === "Home") next = 0
    if (event.key === "End") next = this.tabTargets.length - 1
    if (next !== undefined) {
      event.preventDefault()
      this.tabTargets.forEach((tab, i) => tab.tabIndex = i === next ? 0 : -1)
      this.tabTargets[next].focus()
    } else if (event.key === " " || event.key === "Enter") {
      event.preventDefault()
      const key = event.currentTarget.dataset.tabKey
      this.activate(key)
      history.pushState(null, "", `#${key}`)
    }
  }

  resetRoving() {
    queueMicrotask(() => {
      if (this.hasListTarget && !this.listTarget.contains(document.activeElement)) {
        this.tabTargets.forEach(tab => tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1)
      }
    })
  }

  activate(key) {
    this.tabTargets.forEach(tab => {
      const selected = tab.dataset.tabKey === key
      tab.setAttribute("aria-selected", String(selected))
      tab.tabIndex = selected ? 0 : -1
    })
    this.panelTargets.forEach(panel => panel.hidden = panel.dataset.tabKey !== key)
  }
}
```

Task 4's scoped `[hidden]` rule remains authoritative even when utility classes set
panel display. The render event reinitializes semantics after a Turbo morph without
performing discovery or requests; hashes continue to select the visible panel.

- [ ] **Step 5: Migrate legacy assertions deliberately—not by removing coverage.**
In `test/controllers/mcp_servers_controller_test.rb`, replace only the old list
delete-button test with:

```ruby
test "index exposes details instead of a competing destructive row action" do
  server = make_server
  get mcp_servers_url
  assert_response :success
  assert_select "[data-mcp-row] a[href=?]", mcp_server_path(server)
  assert_select "[data-mcp-row] form input[name=_method][value=delete]", count: 0
end
```

Change its detail deletion assertion to the actual form contract:

```ruby
assert_select "[data-mcp-danger] form[action=?]", mcp_server_path(server) do
  assert_select "input[name=_method][value=delete]"
  assert_select "button", text: /Delete/
end
```

In `test/controllers/mcp_connection_tests_test.rb`, replace result heading `h3`
selectors with `h2`; replace its HTML raw-error assertion with
`refute_includes response.body, "Invalid credentials <script>"` and retain its
recovery guidance, escaping, status, Edit link and JSON assertions unchanged.
Its ready-tag selector becomes `assert_select "[data-state=ready]", text: /Ready/`.
In `test/system/mcp_connection_tests_test.rb`, migrate only login's obsolete
composer assertion to `assert_selector "[data-dashboard]"` **after Task 0 direction**;
replace the failure's `assert_text "Invalid credentials"` with the localized
`connection_test_failure_help` assertion and `assert_no_text "Invalid credentials"`.
Keep busy state/width, language/theme, latency, saved-configuration and safety checks.
Its contrast helper must measure the actual button surface, not the body behind
a newly primary-filled button. Replace only its background measurement with:

```javascript
const button = document.querySelector('button[data-turbo-submits-with]');
const background = luminance(getComputedStyle(button).backgroundColor);
```

Keep the 4.5 threshold and real theme checks. This strengthens surface correctness;
it is not permission to lower contrast thresholds or skip the test.

- [ ] **Step 6: GREEN, lint/build and commit.**

```bash
record detail-build rails_test tailwindcss:build
record detail-green rails_test test test/controllers/mcp_workspace_detail_test.rb test/controllers/mcp_servers_controller_test.rb test/controllers/mcp_connection_tests_test.rb test/controllers/mcp_workspace_scoping_test.rb test/models/mcp_server_capability_snapshot_test.rb
record detail-browser browser_test test/system/mcp_workspace_test.rb test/system/mcp_connection_tests_test.rb
git diff --check
git add app/helpers/mcp_workspace_helper.rb app/views/mcp_servers/show.html.erb app/views/mcp_servers/_connection_controls.html.erb app/views/mcp_servers/_capabilities.html.erb app/views/mcp_servers/_connection_test_result.html.erb app/javascript/controllers/mcp_server_controller.js app/assets/stylesheets/nosia/mcp_workspace.css test/controllers/mcp_workspace_detail_test.rb test/controllers/mcp_servers_controller_test.rb test/controllers/mcp_connection_tests_test.rb test/system/mcp_connection_tests_test.rb
git commit -m "feat: Clarify MCP connections and accessible capability browsing"
```

## Task 7: Transport-aware Add/Edit forms and saved-configuration testing

**Files:** new/edit/form, shared ordinary field partial, transport controller,
form request test and precise legacy MCP browser selector migrations.

- [ ] **Step 1: Write `test/controllers/mcp_workspace_forms_test.rb`.**

```ruby
require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceFormsTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures
  setup { sign_in_picker_user }

  test "new and edit have one title heading trail and contextual cancellation" do
    %i[en fr].each do |locale|
      [ [ new_account_mcp_server_path(@second), account_mcp_servers_path(@second) ],
        [ edit_account_mcp_server_path(@second, @second_server), account_mcp_server_path(@second, @second_server) ] ].each do |path, cancel|
        get path, headers: { "Accept-Language" => locale.to_s }
        assert_response :success
        assert_select "head title", count: 1
        assert_select "main h1", count: 1
        assert_equal css_select("main h1").first.text, css_select("head title").first.text
        assert_select "main .n-workspace-header nav", count: 1
        assert_select "[data-mcp-form] a[href=?]", cancel, text: I18n.t("nosia.actions.cancel", locale: locale)
        assert_select "meta[name=turbo-cache-control][content=no-cache]"
        assert_select "#drawer-right, #accordion-right-actions", count: 0
        refute_match(/translation missing|missing translation/i, response.body)
      end
    end
  end

  test "built-in fields retain their transport and never contain saved secret values" do
    get edit_account_mcp_server_path(@second, @second_server)
    assert_select "input[name='mcp_server[transport_type]'][value=local]"
    assert_select "select[name='mcp_server[transport_type]']", count: 0
    assert_select "input[name='mcp_server[configuration_values][api_key]'][value='']"
    assert_select "input[name='mcp_server[configuration_values][team]'][value=Research]"
    refute_includes response.body, "saved-secret"
  end

  test "422 keeps non-secret values and connects errors without echoing replacement" do
    patch account_mcp_server_path(@second, @second_server), params: { mcp_server: {
      name: "", notes: "Retained note", configuration_values: { api_key: "never-render", team: "" } } }
    assert_response :unprocessable_entity
    assert_select "textarea#mcp_server_notes", text: "Retained note"
    assert_select "a[data-error-field=mcp_server_name]"
    assert_select "input#mcp_server_name[aria-invalid=true]"
    assert_select "a[data-error-field=mcp_server_configuration_values_team]"
    assert_select "input#mcp_server_configuration_values_team[aria-invalid=true]"
    refute_includes response.body, "never-render"
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
  end

  test "test saved configuration is a separate scoped form" do
    get edit_account_mcp_server_path(@second, @second_server)
    assert_select "form[action=?]", account_mcp_server_connection_test_path(@second, @second_server) do |forms|
      assert_empty forms.first.ancestors("form")
      assert_select "input[name^='mcp_server']", count: 0
    end
    assert_select "[data-mcp-form] button[data-turbo-submits-with]", count: 0
    assert_select "[data-mcp-form] input[type=submit][data-turbo-submits-with]"
  end
end
```

- [ ] **Step 2: RED.**

```bash
record forms-red rails_test test test/controllers/mcp_workspace_forms_test.rb
```

- [ ] **Step 3: Create the ordinary field partial and replace the form/pages.**

`app/views/mcp_workspace/_field.html.erb`:

```erb
<%# locals: (form:, attribute:, label:, type: :text, required: false, conditional_required: false, choices: [], value: nil) %>
<div class="n-mcp-field">
  <%= form.label attribute, label, class: "n-mcp-label" %>
  <% opts = mcp_field_options(form.object, attribute).merge(class: "n-mcp-input", required: required, data: { mcp_required: required || conditional_required }) %>
  <% if type == :select %><%= form.select attribute, choices, {}, opts %>
  <% elsif type == :textarea %><%= form.text_area attribute, opts.merge(rows: 4, value: value.nil? ? form.object.public_send(attribute) : value) %>
  <% else %><%= form.text_field attribute, opts %><% end %>
  <p id="<%= mcp_field_id(attribute) %>_help" class="n-workspace-help"><%= t("nosia.mcp_workspace.required") if required %></p>
  <% errors = mcp_error_items(form.object).select { |item| item[:target] == mcp_field_id(attribute) } %>
  <% if errors.any? %><p id="<%= mcp_field_id(attribute) %>_error" class="n-mcp-error"><%= errors.map { |item| item[:message] }.join(" ") %></p><% end %>
</div>
```

`app/views/mcp_servers/_form.html.erb`:

```erb
<%# locals: (mcp_server:) %>
<%= form_with model: mcp_form_model(mcp_server), class: "n-mcp-form-sections", data: { mcp_form: true, controller: "mcp-form form-errors html-form mcp-secrets", action: "click->form-errors#focusField invalid->form-errors#revealInvalid:capture turbo:before-fetch-request->html-form#requestHTML turbo:before-cache@document->mcp-secrets#clear" } do |f| %>
  <%= render "mcp_workspace/errors", record: mcp_server %>
  <section class="n-workspace-panel space-y-4"><h2 class="n-workspace-section-title"><%= t("nosia.mcp.configuration") %></h2>
    <%= render "mcp_workspace/field", form: f, attribute: :name, label: t("nosia.mcp.name"), required: true %>
    <% if mcp_server.local? %><%= f.hidden_field :transport_type, value: "local" %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.local_transport_fixed") %></p>
    <% else %>
      <% choices = %w[streamable sse stdio].map { |value| [ t("nosia.mcp.transport.#{value}"), value, { disabled: value == 'stdio' && !McpServer.stdio_enabled? && mcp_server.transport_type != 'stdio' } ] } %>
      <%= render "mcp_workspace/field", form: f, attribute: :transport_type, label: t("nosia.mcp.connection_type"), type: :select, choices: choices, required: true %>
      <% unless McpServer.stdio_enabled? %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.stdio_unavailable") %></p><% end %>
      <div data-mcp-form-target="httpFields"><%= render "mcp_workspace/field", form: f, attribute: :endpoint, label: t("nosia.mcp.url"), conditional_required: true %></div>
      <div class="space-y-4" data-mcp-form-target="stdioFields"><%= render "mcp_workspace/field", form: f, attribute: :command, label: t("nosia.mcp.command") %><%= render "mcp_workspace/field", form: f, attribute: :args, label: t("nosia.mcp.arguments"), type: :textarea, value: Array(mcp_server.args).join("\n") %></div>
    <% end %>
  </section>
  <% fields = mcp_server.workspace_configuration_fields %>
  <% if fields.any? %>
    <%= tag.section class: "n-workspace-panel space-y-4", data: (mcp_server.local? ? {} : { mcp_form_target: "httpFields" }) do %>
      <h2 class="n-workspace-section-title"><%= t("nosia.mcp.authentication") %></h2>
      <%= render "mcp_catalog/fields", fields: fields, values: mcp_server.workspace_public_values, record: mcp_server, catalog: false, template: (McpCatalog.find(mcp_server.metadata["engine"]) if mcp_server.local?) %>
    <% end %>
  <% elsif mcp_server.local? && !Engines::Registry[mcp_server.metadata["engine"]] %><section class="n-workspace-panel"><p class="n-workspace-help"><%= t("nosia.mcp_workspace.missing_registration") %></p></section><% end %>
  <section class="n-workspace-panel"><h2 class="n-workspace-section-title"><%= t("nosia.mcp_workspace.availability") %></h2><label class="n-mcp-check"><%= f.check_box :enabled %><span><%= t("nosia.mcp_workspace.enabled") %></span></label></section>
  <%= tag.details class: "n-workspace-panel", open: mcp_server.errors.include?(:tags) || mcp_server.errors.include?(:notes) do %><summary><%= t("nosia.mcp_workspace.organization") %></summary><div class="space-y-4">
    <%= render "mcp_workspace/field", form: f, attribute: :tags, label: t("nosia.mcp.tags_input") %>
    <%= render "mcp_workspace/field", form: f, attribute: :notes, label: t("nosia.mcp.notes"), type: :textarea %>
  </div><% end %>
  <div class="n-workspace-actions"><%= f.submit t("nosia.actions.save"), class: "n-workspace-button n-workspace-primary", data: { turbo_submits_with: t("nosia.mcp_workspace.saving") } %><%= link_to t("nosia.actions.cancel"), mcp_server.persisted? ? mcp_record_path(mcp_server) : mcp_index_path, class: "n-workspace-link" %></div>
<% end %>
```

`app/views/mcp_servers/new.html.erb`:

```erb
<% content_for :head, tag.meta(name: "turbo-cache-control", content: "no-cache") %>
<div class="n-workspace n-mcp-workspace" data-mcp-workspace data-mcp-screen="new">
  <%= render "mcp_workspace/header", title: t("nosia.mcp.new"), current: t("nosia.mcp.new"), description: t("nosia.mcp.new_help") %>
  <%= render "mcp_workspace/feedback" %>
  <div class="n-mcp-form-layout">
    <%= render "form", mcp_server: @mcp_server %>
    <aside class="n-workspace-panel"><h2 class="n-workspace-section-title"><%= t("nosia.mcp.catalog") %></h2><p class="n-workspace-help"><%= t("nosia.mcp.catalog_help") %></p><%= link_to t("nosia.mcp_workspace.browse_catalog"), mcp_catalog_list_path, class: "n-workspace-link" %></aside>
  </div>
</div>
```

`app/views/mcp_servers/edit.html.erb`:

```erb
<% content_for :head, tag.meta(name: "turbo-cache-control", content: "no-cache") %>
<div class="n-workspace n-mcp-workspace" data-mcp-workspace data-mcp-screen="edit" data-controller="mcp-busy" data-action="turbo:submit-start->mcp-busy#start turbo:submit-end->mcp-busy#finish">
  <%= render "mcp_workspace/header", title: t("nosia.actions.edit_named", name: @mcp_server.name), current: t("nosia.actions.edit"), server: @mcp_server, description: t("nosia.mcp.edit_help") %>
  <%= render "mcp_workspace/feedback" %>
  <div class="n-mcp-form-layout">
    <%= render "form", mcp_server: @mcp_server %>
    <aside class="n-workspace-panel space-y-3" data-mcp-busy-group>
      <h2 class="n-workspace-section-title"><%= t("nosia.mcp_workspace.saved_test") %></h2>
      <p class="n-workspace-help"><%= t("nosia.mcp_workspace.saved_test_help") %></p>
      <% if @mcp_server.transport_type == "stdio" && !McpServer.stdio_enabled? %><p class="n-workspace-help"><%= t("nosia.mcp_workspace.stdio_unavailable") %></p>
      <% else %><%= button_to t("nosia.mcp_workspace.saved_test"), mcp_test_path(@mcp_server), method: :post, class: "n-workspace-button n-mcp-operation-button", data: { turbo_submits_with: t("nosia.mcp.testing_connection") }, form: { data: { mcp_operation: true } } %><% end %>
    </aside>
  </div>
</div>
```

These pages do not add another `content_for :title`; the shared header owns it.
The short help rail stacks after the form on narrow screens and keeps its test
form outside the configuration form. The HTTP auth group remains in non-local
form markup so switching from stdio to HTTP can reveal it without losing values.

- [ ] **Step 4: Replace `mcp_form_controller.js` with transport-only enhancement.**

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["httpFields", "stdioFields"]

  connect() {
    this.toggleTransportFields()
    this.transport = this.element.querySelector('[name="mcp_server[transport_type]"]')
    this.change = () => this.toggleTransportFields()
    this.transport?.addEventListener("change", this.change)
  }

  disconnect() {
    this.transport?.removeEventListener("change", this.change)
  }

  toggleTransportFields() {
    const type = this.element.querySelector('[name="mcp_server[transport_type]"]')?.value
    for (const [targets, visible] of [[this.httpFieldsTargets, ["streamable", "sse"].includes(type)], [this.stdioFieldsTargets, type === "stdio"]]) {
      targets.forEach(group => {
        group.hidden = !visible
        group.querySelectorAll("input, textarea, select").forEach(input => {
          input.disabled = !visible
          input.required = visible && input.dataset.mcpRequired === "true"
        })
      })
    }
  }
}
```

Visible local credential fields are not HTTP targets and are not disabled. Without
JS both remote transport groups remain readable; conditional endpoint validation
falls back to the server rather than incorrectly blocking a stdio submission.
With JS the visible endpoint gets native required validation from its data flag.

- [ ] **Step 5: Preserve existing catalog/connection browser coverage.** After
Task 0's explicit direction for reproduced selector problems, update only these
contracts in the existing files (no skipped tests):

```ruby
# test/system/mcp_connection_tests_test.rb: edit's intentionally clearer label
click_button "Test saved configuration"

# test/system/mcp_catalog_test.rb: setup additions and current signed-in landing
@previous_stdio_enabled = ENV["MCP_STDIO_ENABLED"]
ENV["MCP_STDIO_ENABLED"] = "true"
assert_selector "[data-dashboard]"

# Same file teardown, alongside the existing metrics cleanup:
ENV["MCP_STDIO_ENABLED"] = @previous_stdio_enabled
```

The catalog suite only renders/edits fields; it does not start an external stdio
process. Replace its old `.n-card` measurement root with the whole selected setup
form, preserving all old width/copy/edge checks and adding the scoped markers:

```javascript
const card = document.querySelector('[data-mcp-screen="catalog-setup"] form');
```

Its mobile focus selectors become:

```ruby
assert_selector "[data-mcp-screen=catalog-setup] form a:focus", text: "Cancel"
assert_selector '[data-mcp-screen=catalog-setup] input[type="submit"]:focus'
```

And its button geometry selector is:

```javascript
const button = document.querySelector('[data-mcp-screen="catalog-setup"] input[type=submit]');
```

Keep EN/FR, three widths, both themes, exact activation focus order and full button
edge hit-testing. Setting the flag is only an isolated test prerequisite with
restoration, not a deployment change or permission to execute a remote process.

- [ ] **Step 6: Migrate only the affected French MCP presentation contracts.**
First run the existing integration file against the new presentation, retaining
the failure output before changing its expectations:

```bash
record localized-presentation-red rails_test test test/integration/localized_pages_test.rb
```

In `test/integration/localized_pages_test.rb`, make these exact replacements;
retain all other assertions, particularly JSON keys, statuses, raw API diagnostics,
execution results and escaping. The last hunk uses a configuration-free local
template for the generic activation exception so disabled stdio does not mask it:

```diff
-    assert_select "h3", text: "1 erreur :"
+    assert_select "#mcp-errors-title", text: "1 erreur :"
@@
-      assert_equal "Échec de la connexion : Original provider failure.", flash[:alert]
+      assert_equal "Échec de la connexion", flash[:alert]
+      refute_includes flash[:alert], "Original provider failure"
@@
-    tool = Struct.new(:name, :description, :input_schema).new("runtime_tool", "<script>Original tool description</script>", { "query" => "Original schema" })
+    tool = Struct.new(:name, :description, :parameters_schema).new("runtime_tool", "<script>Original tool description</script>", { "query" => "Original schema" })
@@
-      assert_select "p", text: "Paramètres :"
-      assert_select "p", text: "Variables :"
+      assert_select "[data-mcp-capability=tools] details summary", text: I18n.t("nosia.mcp_workspace.schema", locale: :fr)
+      assert_select "[data-mcp-capability=prompts] dt", text: /query.*#{Regexp.escape(I18n.t("nosia.mcp_workspace.required", locale: :fr))}/
@@
-      assert_select "span", text: "- Original variable"
+      assert_select "[data-mcp-capability=prompts] dd", text: "Original variable"
@@
       with_singleton_replacement(McpCatalog, :activate_for_account, ->(*) { raise "Original provider diagnostic" }) do
-        post mcp_catalog_index_url, params: { id: "kchat" }, headers: headers
+        post mcp_catalog_index_url, params: { id: "open_alex" }, headers: headers
       end
-      assert_redirected_to mcp_catalog_index_url
-      assert_equal "Erreur d’activation : Original provider diagnostic.", flash[:alert]
+      assert_response :unprocessable_entity
+      assert_select "[data-mcp-screen=catalog-setup] [role=alert]", text: /Échec de la connexion/
+      assert_select "form input[name=id][value=open_alex]"
+      refute_includes response.body, "Original provider diagnostic"
+      assert_nil flash[:alert]
```

- [ ] **Step 7: GREEN, build, browser checks and commit.**

```bash
record forms-build rails_test tailwindcss:build
record forms-green rails_test test test/controllers/mcp_workspace_forms_test.rb test/controllers/mcp_workspace_configuration_test.rb test/controllers/mcp_workspace_catalog_test.rb test/controllers/mcp_connection_tests_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record forms-browser browser_test test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb
git diff --check
git add app/views/mcp_workspace/_field.html.erb app/views/mcp_servers/new.html.erb app/views/mcp_servers/edit.html.erb app/views/mcp_servers/_form.html.erb app/javascript/controllers/mcp_form_controller.js test/controllers/mcp_workspace_forms_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/integration/localized_pages_test.rb
git commit -m "feat: Improve MCP forms and explicit saved-configuration testing"
```

## Task 8: Full browser matrix, behavioral proof, docs and final gates

**Files:** extend `test/system/mcp_workspace_test.rb`; create
`test/support/mcp_browser_checks.rb`, `docs/mcp-workspace.md`; update docs index;
final documentation-only execution record in this plan after reviews.

- [ ] **Step 1: Add the dedicated browser helper before final UI adjustments.**
Use these complete contents in `test/support/mcp_browser_checks.rb`:

```ruby
require "tmpdir"
require "fileutils"

module McpBrowserChecks
  extend ActiveSupport::Concern
  DRIVER = :mcp_workspace_desktop_input
  INPUT_FLAG = "--blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4".freeze

  included do
    setup do
      FileUtils.mkdir_p("/tmp/opencode")
      @mcp_evidence = Dir.mktmpdir("mcp-browser-", "/tmp/opencode")
      @old_driver, @old_session = Capybara.current_driver, Capybara.session_name
      @old_registration = Capybara.drivers[@old_driver]
      options = { name: DRIVER }
      options.merge!(browser: :remote, url: "http://:4444") if ENV["CAPYBARA_SERVER_PORT"]
      ActionDispatch::SystemTesting::Driver.new(:selenium, using: :headless_chrome,
        screen_size: [ 1400, 1400 ], options: options) { |settings| settings.add_argument(INPUT_FLAG) }.use
      Capybara.session_name = "mcp_workspace_#{object_id}"
      @mcp_session = Capybara.current_session
    end

    teardown do
      begin
        if @mcp_session
          page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
          page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
          page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
        end
      ensure
        begin
          @mcp_session&.quit
        ensure
          Capybara.current_driver = @old_driver
          Capybara.session_name = @old_session
        end
      end
      assert_same @old_registration, Capybara.drivers[@old_driver]
      assert_equal @old_driver, Capybara.current_driver
      assert_equal @old_session, Capybara.session_name
      File.write(File.join(@mcp_evidence, "cleanup.json"), { driver_restored: true, session_restored: true,
        original_registration_unchanged: true, input_capability_emulation: INPUT_FLAG, physical_hardware_proof: false }.to_json)
    end
  end

  def mcp_size(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
    assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
  end

  def mcp_wait
    page.driver.browser.execute_async_script("const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));")
  end

  def mcp_theme(theme)
    find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != (theme == "dark")
    assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
    page.driver.browser.execute_async_script("const done=arguments[0];Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());")
  end

  def mcp_tab_to(selector)
    160.times do
      page.send_keys(:tab)
      if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
        mcp_wait
        return
      end
    end
    flunk "Keyboard could not reach #{selector}"
  end

  def mcp_assert_focus
    sample = page.evaluate_script(<<~JS)
      (()=>{const active=document.activeElement,e=active.matches('input[type=checkbox]')?active.closest('label'):active;
        const r=e.getBoundingClientRect(),s=getComputedStyle(e),m=document.querySelector('main').getBoundingClientRect();
        const points=[[r.x+r.width/2,r.top+1],[r.x+r.width/2,r.bottom-1],[r.left+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
        return {tag:active.tagName,text:e.textContent.trim(),width:r.width,height:r.height,outline:parseFloat(s.outlineWidth),
          visible:r.top>=Math.max(0,m.top)&&r.bottom<=Math.min(innerHeight,m.bottom)&&points.every(([x,y])=>{const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));})};})()
    JS
    assert_operator sample.fetch("height"), :>=, 44, sample.to_json
    assert_operator sample.fetch("width"), :>=, 44, sample.to_json
    assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
    assert sample.fetch("visible"), sample.to_json
  end

  def mcp_keyboard_walk
    count = page.evaluate_script(<<~JS)
      Array.from(document.querySelector('[data-mcp-workspace]').querySelectorAll('a,button,input,select,textarea,summary,[role=tabpanel]'))
        .filter(e=>e.getClientRects().length&&getComputedStyle(e).visibility==='visible'&&!e.disabled&&e.tabIndex>=0)
        .map((e,index)=>{e.dataset.mcpWalk=String(index);return e;}).length
    JS
    assert_operator count, :>, 1
    mcp_tab_to("[data-mcp-walk='0']")
    count.times do |index|
      if index.positive?
        page.send_keys(:tab)
        mcp_wait
      end
      assert page.evaluate_script("document.activeElement.dataset.mcpWalk===arguments[0]", index.to_s), "Visible DOM/keyboard order diverged at #{index}"
      if page.evaluate_script("document.activeElement.getAttribute('role')==='tabpanel'")
        # Read-only panels can be taller than the viewport: they need a visible
        # focus indicator/intersection, not an impossible 44px control rectangle.
        assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.activeElement).outlineWidth)"), :>=, 2
        assert page.evaluate_script("(()=>{const r=document.activeElement.getBoundingClientRect(),m=document.querySelector('main').getBoundingClientRect();return r.bottom>m.top&&r.top<m.bottom})()")
      else
        mcp_assert_focus
      end
    end
    page.send_keys([:shift, :tab])
    mcp_wait
    assert page.evaluate_script("document.activeElement.dataset.mcpWalk===arguments[0]", (count - 2).to_s)
  end

  def mcp_layout
    assert page.evaluate_script("document.documentElement.scrollWidth<=document.documentElement.clientWidth+1&&document.querySelector('main').scrollWidth<=document.querySelector('main').clientWidth+1")
    rows = page.evaluate_script(<<~JS)
      Array.from(document.querySelector('[data-mcp-workspace]').querySelectorAll('h1,h2,h3,p,dt,dd,label,summary,pre')).filter(e=>e.getClientRects().length).map(e=>{
        const r=e.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(e);
        return {text:e.textContent.slice(0,80),ellipsis:getComputedStyle(e).textOverflow==='ellipsis',fits:e.scrollWidth<=e.clientWidth+1&&Array.from(range.getClientRects()).every(t=>t.left>=r.left-1&&t.right<=r.right+1)};
      })
    JS
    assert_not_empty rows
    rows.each { |row| refute row.fetch("ellipsis"), row.to_json; assert row.fetch("fits"), row.to_json }
  end

  def mcp_contrast(phase)
    rows = page.evaluate_script(<<~JS)
      (()=>{const root=document.querySelector('[data-mcp-workspace]'),c=document.createElement('canvas');c.width=c.height=1;
        const ctx=c.getContext('2d',{willReadFrequently:true});
        function rgba(v){ctx.clearRect(0,0,1,1);ctx.fillStyle=v;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
        function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
        function bg(e){const a=[];for(;e;e=e.parentElement)a.unshift(e);return a.reduce((b,e)=>{const s=getComputedStyle(e);if(s.opacity!=='1'||s.backgroundImage!=='none')throw Error('Unmeasured surface');return blend(rgba(s.backgroundColor),b);},[255,255,255]);}
        function lum(a){return a.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4}).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0);}
        function row(e,property,minimum,outside=false){const b=bg(outside?e.parentElement:e),f=blend(rgba(getComputedStyle(e)[property]),b),x=lum(f),y=lum(b);return {text:e.textContent.trim().slice(0,70),property,minimum,outside,background:b,foreground:f,ratio:(Math.max(x,y)+.05)/(Math.min(x,y)+.05)};}
        const visible=e=>e.getClientRects().length&&getComputedStyle(e).visibility==='visible'&&!e.disabled;
        const rows=Array.from(root.querySelectorAll('h1,h2,h3,p,dt,dd,label,summary,pre,a,button,input,select,textarea,svg')).filter(visible).map(e=>row(e,'color',e.tagName.toLowerCase()==='svg'?3:4.5));
        root.querySelectorAll('.n-workspace-button,.n-mcp-input').forEach(e=>{if(!visible(e))return;if(e.classList.contains('n-workspace-primary'))rows.push(row(e,'backgroundColor',3,true));else{rows.push(row(e,'borderTopColor',3));rows.push(row(e,'borderTopColor',3,true));}});
        const active=document.activeElement;if(root.contains(active)){const e=active.matches('input[type=checkbox]')?active.closest('label'):active;rows.push(row(e,'outlineColor',3,true));}return rows;})()
    JS
    rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.to_json }
    File.open(File.join(@mcp_evidence, "contrast.jsonl"), "a") { |file| file.puts({ path: URI(page.current_url).path, phase: phase, locale: find("html", visible: :all)["lang"], viewport: page.evaluate_script("[innerWidth,innerHeight]"), samples: rows }.to_json) }
  end

  def mcp_hover
    target = first("[data-mcp-workspace] .n-workspace-primary")
    page.execute_script("arguments[0].scrollIntoView({block:'center',behavior:'instant'})", target)
    mcp_wait
    find("#theme-toggle").hover
    before = mcp_hover_sample(target)
    refute before.fetch("hovered")
    assert_equal before.fetch("expected"), before.fetch("background")
    mcp_contrast("unhovered")
    target.hover
    mcp_wait
    after = mcp_hover_sample(target)
    assert before.fetch("capable") && after.fetch("capable"), after.to_json
    assert after.fetch("hovered")
    assert_equal before.fetch("bounds"), after.fetch("bounds")
    refute_equal before.fetch("background"), after.fetch("background")
    assert_equal after.fetch("expected"), after.fetch("background")
    mcp_contrast("hovered")
    File.open(File.join(@mcp_evidence, "hover.jsonl"), "a") { |file| file.puts({ before: before, after: after, input_capability_emulation: INPUT_FLAG }.to_json) }
  end

  def mcp_hover_sample(element)
    page.evaluate_script(<<~JS, element)
      (()=>{const e=arguments[0],r=e.getBoundingClientRect(),dark=document.documentElement.classList.contains('dark'),hovered=e.matches(':hover');
        const token=dark?(hovered?'--color-green-200':'--color-green-300'):(hovered?'--color-green-800':'--color-green-700');
        const c=document.createElement('canvas');c.width=c.height=1;const x=c.getContext('2d');function rgba(v){x.clearRect(0,0,1,1);x.fillStyle=v;x.fillRect(0,0,1,1);return Array.from(x.getImageData(0,0,1,1).data)};
        return {hovered,capable:matchMedia('(hover:hover)').matches&&matchMedia('(pointer:fine)').matches,bounds:[r.x,r.y,r.width,r.height],background:rgba(getComputedStyle(e).backgroundColor),expected:rgba(getComputedStyle(document.documentElement).getPropertyValue(token)),token};})()
    JS
  end
end
```

This is declared desktop-input capability emulation, not hardware or zoom evidence.
No production stylesheet or pseudo-state is forced. Use a dedicated named driver;
do not overwrite `ApplicationSystemTestCase` or the protected driver's registration.

- [ ] **Step 2: Extend the existing MCP system class.** Require/include
`../support/mcp_browser_checks` after `McpWorkspaceFixtures`. Retain its original
keyboard creation test and login setup. Add these complete tests:

```ruby
test "all six pages meet the 96-state base layout matrix" do
  @second_server.update!(status: "ready", name: "CompteDeRecherche" * 12)
  states = []
  %w[en fr].each do |locale|
    select locale.upcase, from: "language_preference_locale"
    assert_selector "html[lang='#{locale}']", visible: :all
    pages = { servers: account_mcp_servers_path(@second), catalog: account_mcp_catalog_index_path(@second),
      setup: account_mcp_catalog_path(@second, "kdrive"), detail: account_mcp_server_path(@second, @second_server),
      new: new_account_mcp_server_path(@second), edit: edit_account_mcp_server_path(@second, @second_server) }
    pages.each do |name, path|
      [[375,812],[768,1024],[1440,1000],[812,375]].each do |width, height|
        mcp_size(width, height)
        %w[light dark].each do |theme|
          visit path
          mcp_theme(theme)
          assert_selector "[data-mcp-workspace] h1", count: 1
          assert_selector ".n-workspace-header nav", count: 1
          assert_no_selector "#drawer-right, #accordion-right-actions", visible: :all
          assert_no_text(/translation missing|missing translation/i)
          refute_includes page.html, "saved-secret"
          mcp_layout
          mcp_keyboard_walk
          mcp_contrast("keyboard")
          mcp_hover
          page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
          page.save_screenshot(File.join(@mcp_evidence, "#{name}-#{locale}-#{width}-#{height}-#{theme}.png")) if [375,1440].include?(width)
          states << { screen: name, locale: locale, viewport: [width,height], theme: theme }
          File.write(File.join(@mcp_evidence, "matrix.json"), { states: states, native_200_percent_zoom: "UNVERIFIED", input_capability_emulation: McpBrowserChecks::INPUT_FLAG }.to_json)
        end
      end
    end
  end
  assert_equal 96, states.size
  assert_equal 96, states.uniq.size
  page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [{name:"prefers-reduced-motion",value:"reduce"}])
  visit account_mcp_server_path(@second, @second_server)
  assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
  assert page.evaluate_script("Array.from(document.querySelectorAll('[data-mcp-workspace] a,[data-mcp-workspace] button')).every(e=>getComputedStyle(e).transitionDuration==='0s')")
  assert_equal @first, @user.reload.first_account
  puts "MCP matrix evidence: #{@mcp_evidence}"
end

test "manual tabs work by keyboard and hash without executing content" do
  @second_server.update!(status: "ready")
  before = [ Chat.count, Prompt.count ]
  assert_no_enqueued_jobs do
    visit account_mcp_server_path(@second, @second_server)
    mcp_tab_to("#mcp-tab-overview")
    page.send_keys(:arrow_right)
    assert_selector "#mcp-tab-tools:focus[aria-selected=false]"
    page.send_keys(:enter)
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    assert_selector "#tools[role=tabpanel]"
    assert_equal "#tools", URI(page.current_url).fragment.then { |value| "##{value}" }
    page.refresh
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    mcp_tab_to("#mcp-tab-tools")
    page.send_keys(:end)
    assert_selector "#mcp-tab-resources:focus"
    page.send_keys(:space)
    assert_selector "#resources[role=tabpanel]"
    page.send_keys(:home)
    page.send_keys(:enter)
    assert_selector "#overview[role=tabpanel]"
    page.send_keys(:tab)
    assert_selector "#overview:focus"
    page.send_keys([:shift,:tab])
    assert_selector "#mcp-tab-overview:focus"
    page.go_back
    assert_selector "#mcp-tab-resources[aria-selected=true]"
    page.go_forward
    assert_selector "#mcp-tab-overview[aria-selected=true]"
    visit "#{account_mcp_server_path(@second, @second_server)}#unknown-section"
    assert_selector "#mcp-tab-overview[aria-selected=true]"
  end
  assert_equal before, [ Chat.count, Prompt.count ]
end

test "invalid edits focus a linked summary and do not retain replacement secrets" do
  visit edit_account_mcp_server_path(@second, @second_server)
  fill_in "mcp_server_name", with: ""
  fill_in "mcp_server_configuration_values_api_key", with: "never-echo-replacement"
  # Deliberately exercise server validation; native required validation is tested separately below.
  page.execute_script("document.querySelector('[data-mcp-form]').noValidate=true")
  click_on "Save"
  assert_selector "[data-form-errors-target=summary]:focus"
  assert_no_text "never-echo-replacement"
  refute_includes page.html, "never-echo-replacement"
  assert_equal "", find("#mcp_server_configuration_values_api_key").value
  mcp_tab_to("a[data-error-field=mcp_server_name]")
  page.send_keys(:enter)
  assert_selector "#mcp_server_name:focus"
  mcp_assert_focus
  assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
  visit new_account_mcp_server_path(@second)
  click_on "Save"
  assert_selector "#mcp_server_name:invalid"
end

test "saved-config testing never submits edits and busy actions remain stable" do
  release = Queue.new
  @health_check = ->(_) { release.pop }
  visit edit_account_mcp_server_path(@second, @second_server)
  fill_in "mcp_server_name", with: ""
  width = find_button("Test saved configuration").native.rect.width
  click_button "Test saved configuration"
  assert_selector "button[disabled]", text: "Testing connection…"
  assert_equal width, find_button("Testing connection…", disabled: true).native.rect.width
  release << true
  assert_selector "#connection-test-result[role=status]"
  assert_current_path account_mcp_server_path(@second, @second_server)
  assert_equal "Second tool", @second_server.reload.name
ensure
  release << true if release
end

test "sections remain readable with page JavaScript disabled" do
  @second_server.update!(status: "ready")
  page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
  visit account_mcp_server_path(@second, @second_server)
  %w[overview tools prompts resources].each { |id| assert_selector "##{id}", visible: true }
  assert_no_selector "[role=tablist]", visible: :all
ensure
  page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
end
```

- [ ] **Step 3: Add focused keyboard form/catalog workflows.** Append these tests
to the same system class, using local fake configuration only:

```ruby
test "scoped custom creation editing deletion and catalog setup stay in their account" do
  before = [ Chat.count, Prompt.count ]
  visit new_account_mcp_server_path(@second)
  fill_in "mcp_server_name", with: "Browser custom"
  fill_in "mcp_server_endpoint", with: "https://mcp.example.org/mcp"
  mcp_tab_to("[data-mcp-form] input[type=submit]")
  mcp_assert_focus
  page.send_keys(:enter)
  server = @second.mcp_servers.find_by!(name: "Browser custom")
  assert_current_path account_mcp_server_path(@second, server)
  assert server.status_disconnected?
  visit edit_account_mcp_server_path(@second, server)
  find("[data-mcp-form] summary").click
  fill_in "mcp_server_notes", with: "Public note"
  click_on "Save"
  assert_equal "Public note", server.reload.notes
  mcp_tab_to("[data-mcp-danger] button")
  mcp_assert_focus
  accept_confirm { page.send_keys(:enter) }
  assert_current_path account_mcp_servers_path(@second)
  refute @second.mcp_servers.exists?(server.id)
  visit account_mcp_catalog_path(@second, "open_alex")
  mcp_tab_to("[data-mcp-screen=catalog-setup] input[type=submit]")
  mcp_assert_focus
  page.send_keys(:enter)
  added = @second.mcp_servers.find_by!(name: "OpenAlex")
  assert_current_path account_mcp_server_path(@second, added)
  assert added.status_disconnected?
  assert_equal @first, @user.reload.first_account
  assert_equal before, [ Chat.count, Prompt.count ]
end

test "catalog errors retain only public input and secret snapshots clear" do
  @second_server.update!(metadata: { engine: "workspace-demo" })
  visit account_mcp_catalog_path(@second, "workspace-demo")
  fill_in "config_team", with: "Retained team"
  page.execute_script("document.querySelector('[data-mcp-screen=catalog-setup] form').noValidate=true")
  click_on "Add to account"
  assert_selector "[data-form-errors-target=summary]:focus"
  assert_equal "Retained team", find("#config_team").value
  assert_equal "", find("#config_api_key").value
  mcp_tab_to("a[data-error-field=config_api_key]")
  page.send_keys(:enter)
  assert_selector "#config_api_key:focus"
  mcp_assert_focus
  fill_in "config_api_key", with: "snapshot-only-fixture-secret"
  page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
  assert_equal "", find("#config_api_key").value
  refute_includes page.html, "snapshot-only-fixture-secret"
  fill_in "config_api_key", with: "history-only-fixture-secret"
  click_on "Cancel"
  assert_current_path account_mcp_catalog_index_path(@second)
  page.go_back
  assert_current_path account_mcp_catalog_path(@second, "workspace-demo")
  assert_equal "", find("#config_api_key").value
  refute_includes page.html, "history-only-fixture-secret"
  assert_selector "meta[name=turbo-cache-control][content=no-cache]", visible: :all
end

test "empty filters and an empty account offer distinct scoped recovery" do
  before = @second.mcp_servers.count
  visit account_mcp_servers_path(@second)
  select "Ready", from: "status"
  click_on "Apply filters"
  assert_selector "[data-mcp-filtered-empty]"
  assert_no_selector "[data-mcp-row]"
  find("[data-mcp-filtered-empty] a").click
  assert_current_path account_mcp_servers_path(@second)
  assert_selector "[data-mcp-row]", count: before
  assert_equal before, @second.mcp_servers.count
  ActsAsTenant.with_tenant(@second) { @second_server.destroy! }
  visit account_mcp_servers_path(@second)
  assert_text "No MCP servers yet"
  assert_no_selector "[data-mcp-filtered-empty]"
  assert_selector "a[href='#{account_mcp_catalog_index_path(@second)}']", text: "Browse catalog"
  assert_selector "a[href='#{new_account_mcp_server_path(@second)}']", text: "Add custom server"
end

test "scoped New chat uses the existing preselected composer without creating a chat" do
  before = Chat.count
  mcp_size(1440, 1000)
  visit account_mcp_servers_path(@second)
  target = ".n-workspace-header a[href='#{new_chat_path(account_id: @second.id)}']"
  mcp_tab_to(target)
  mcp_assert_focus
  page.send_keys(:enter)
  assert_current_path new_chat_path(account_id: @second.id)
  assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
  assert_equal before, Chat.count
  assert_equal @first, @user.reload.first_account
end

test "catalog title links are keyboard reachable without adding anything" do
  before = [ McpServer.count, Chat.count, Prompt.count ]
  assert_no_enqueued_jobs do
    McpCatalog.all.each do |entry|
      visit account_mcp_catalog_index_path(@second)
      mcp_tab_to("[data-mcp-entry='#{entry[:id]}'] h3 a")
      mcp_assert_focus
      page.send_keys(:enter)
      assert_current_path account_mcp_catalog_path(@second, entry[:id])
    end
  end
  assert_equal before, [ McpServer.count, Chat.count, Prompt.count ]
end

test "transport selection reveals only relevant inputs without executing a command" do
  previous = ENV["MCP_STDIO_ENABLED"]
  ENV["MCP_STDIO_ENABLED"] = "true"
  visit new_account_mcp_server_path(@second)
  find("#mcp_server_transport_type option[value=stdio]").select_option
  assert_selector "#mcp_server_command"
  assert_no_selector "#mcp_server_endpoint"
  assert find("#mcp_server_endpoint", visible: :all).disabled?
  fill_in "mcp_server_command", with: "must-not-execute"
  fill_in "mcp_server_args", with: "one argument\nsecond"
  find("#mcp_server_transport_type option[value=sse]").select_option
  assert_selector "#mcp_server_endpoint"
  assert_no_selector "#mcp_server_command"
  assert find("#mcp_server_command", visible: :all).disabled?
  assert_equal "must-not-execute", find("#mcp_server_command", visible: :all).value
ensure
  ENV["MCP_STDIO_ENABLED"] = previous
end

test "empty and unavailable capability results do not become the same message" do
  Engines::Registry.register(Engines::Registration.new(id: "workspace-empty", name: "Empty", icon: "test",
    description: "No tools", required_config: [], tool_classes: [], health_check: ->(_) {}))
  @second_server.update!(status: "ready", metadata: { engine: "workspace-empty" })
  visit "#{account_mcp_server_path(@second, @second_server)}#tools"
  assert_selector "#mcp-tab-tools", text: /0/
  assert_selector "#tools", text: I18n.t("nosia.mcp_workspace.no_items")
  @second_server.update!(metadata: { engine: "unknown" })
  visit "#{account_mcp_server_path(@second, @second_server)}#tools"
  assert_selector "#mcp-tab-tools", text: /unavailable/
  assert_selector "#tools", text: I18n.t("nosia.mcp_workspace.unavailable")
end

test "connection checks disable only conflicting controls until completion" do
  release = Queue.new
  @health_check = ->(_) { release.pop }
  @second_server.update!(status: "ready")
  visit account_mcp_server_path(@second, @second_server)
  click_button "Test connection"
  assert_selector "[data-mcp-busy-group][aria-busy=true]"
  assert_button "Disconnect", disabled: true
  release << true
  assert_selector "#connection-test-result[role=status]"
  assert_button "Disconnect", disabled: false
  assert_selector "[role=tablist]"
ensure
  release << true if release
end
```

For errors/confirmation, use the real keyboard and Turbo response, not forced
focus. The dispatched cache event verifies the existing lifecycle handler; the
following navigation/back checks prove secrets are not restored in the browser.
Neither is native browser zoom proof.

- [ ] **Step 4: Run the expanded browser checks and diagnose honestly.**

```bash
record matrix-build rails_test tailwindcss:build
record matrix-browser browser_test test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb
```

Any uncovered in-scope defect gets a focused failing assertion before its minimal
fix. Preserve intermediate failed attempts; do not weaken focus/contrast/width/
state coverage. Open representative screenshots for all six screens, both themes
and locales at phone/desktop; inspect recorded JSON and actual hover phases as
well. Post-reset screenshots are layout evidence, not proof of focused visibility.
The base matrix is 96 unique states; extra errors/transport/busy checks are not
silently counted as those matrix states. Actual native 200% zoom is separate and
remains explicitly UNVERIFIED without headed/manual proof.

- [ ] **Step 5: Add `docs/mcp-workspace.md` with these complete contents, plus the
one docs-index link immediately after the existing Accounts/Settings guide link.**

```markdown
# MCP workspace

MCP servers are managed within one account. Unscoped pages use and name your
existing default account; `/accounts/:account_id/mcp_servers` and the corresponding
catalog URLs retain their explicit account. Visits do not change the default.
Existing member permissions apply; another account’s records are not accessible.

Browse catalog is the main addition path; Add custom server remains available.
Server rows separate availability for conversations from the last recorded
connection state. Filters do not change records. Catalog “Added” does not mean
connected, and Save/Add do not automatically test or connect a server.

Details include Overview, Tools, Prompts and Resources. Capability browsing is
read-only; schemas can be expanded. Tabs support keyboard navigation and hash
links, and the sections remain readable without JavaScript. There are no new
tool/prompt test runners. Unavailable counts are not reported as zero.

Blank credential edits keep saved values; entering a replacement replaces only
that field; explicit removal clears it on Save subject to required-field rules.
Saved secrets are not shown or restored after failed submissions. Public fields
remain on invalid forms with linked and inline errors. Built-in and stdio
deployment restrictions are preserved; no raw configuration editor is provided.

Test saved configuration is separate from Save. It uses saved values, ignores
unsaved edits, and returns to server details. Connection actions show busy/result
feedback without continuous polling. Delete removes this account’s configuration,
not the external service, and still requires confirmation.

The workspace supports English/French and light/dark themes, narrow layouts,
keyboard navigation and mobile navigation clearance. Native 200% zoom and any
unexercised browser/platform require separate verification; viewport emulation is
not proof and sampled checks are not an exhaustive accessibility audit.

See the [approved design](superpowers/specs/2026-10-27-mcp-workspace-ui-ux-design.md)
for scope, decisions and acceptance requirements.
```

```markdown
- [MCP workspace](mcp-workspace.md) — account context, catalog, safe configuration, connection feedback and capability browsing.
```

- [ ] **Step 6: Fresh final verification, sequentially.**
Stage only the Task 8 test/docs patch first and record the exact tree being tested.
If any source/test changes after verification, restage and rerun the affected and
final gates; do not reuse the old tree or evidence for a changed patch.

```bash
git add test/support/mcp_browser_checks.rb test/system/mcp_workspace_test.rb docs/mcp-workspace.md docs/README.md
git diff --cached --check
git diff --exit-code
git rev-parse HEAD > "$EVIDENCE/final-tested-parent.txt"
git write-tree > "$EVIDENCE/final-tested-tree.txt"
record final-build rails_test tailwindcss:build
record final-focused rails_test test test/controllers/mcp_workspace_scoping_test.rb test/controllers/mcp_workspace_configuration_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/mcp_workspace_catalog_test.rb test/controllers/mcp_workspace_detail_test.rb test/controllers/mcp_workspace_forms_test.rb test/controllers/mcp_servers_controller_test.rb test/controllers/mcp_connection_tests_test.rb test/models/mcp_server_configuration_test.rb test/models/mcp_server_capability_snapshot_test.rb test/models/mcp_server_test.rb test/models/mcp_server_local_test.rb test/lib/mcp_catalog_registry_test.rb test/helpers/mcp_catalog_helper_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/dashboards_controller_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record final-full rails_test test
record final-browser browser_test test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/system/accounts_settings_workspace_test.rb test/system/account_experience_test.rb test/system/agent_skills_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/profile_management_test.rb
record final-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/controllers/concerns/mcp_scoped.rb app/controllers/mcp_servers_controller.rb app/controllers/mcp_catalog_controller.rb app/controllers/mcp_servers app/models/mcp_server.rb app/models/mcp_server app/helpers/mcp_workspace_helper.rb app/helpers/mcp_forms_helper.rb lib/mcp_catalog.rb test/support/mcp_workspace_fixtures.rb test/support/mcp_browser_checks.rb test/controllers/mcp_workspace_scoping_test.rb test/controllers/mcp_workspace_configuration_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/mcp_workspace_catalog_test.rb test/controllers/mcp_workspace_detail_test.rb test/controllers/mcp_workspace_forms_test.rb test/models/mcp_server_configuration_test.rb test/models/mcp_server_capability_snapshot_test.rb test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/integration/localized_pages_test.rb
record final-security mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
git diff --check
git diff --stat "$BASE"..HEAD
git status --short
```

Record actual counts/seeds/exits, compare exact baseline error identities and
messages—not only totals—and stop for any new issue. No new provider/process/
dependency/transport behavior may be smuggled into test cleanup. Review changed
public Ruby YARD against the actual interfaces and validate documentation links.

- [ ] **Step 7: Commit only Task 8 test/docs changes, then whole-feature review.**

```bash
git add test/support/mcp_browser_checks.rb test/system/mcp_workspace_test.rb docs/mcp-workspace.md docs/README.md
git commit -m "test: Verify MCP workspace workflows and responsive states"
test "$(git rev-parse HEAD^{tree})" = "$(< "$EVIDENCE/final-tested-tree.txt")"
git rev-parse HEAD > "$EVIDENCE/final-tested-sha.txt"
```

Use independent specification and quality reviews after each task and fresh
whole-feature reviews here when executing subagent-driven. Resolve findings with
focused RED/GREEN evidence; do not treat implementation reports as proof. Keep
the last actually tested revision/tree explicit if a commit follows unchanged
source. Do not claim a test rerun merely because documentation was committed.

- [ ] **Step 8: Record and hand off, with source identity proof.** After reviews,
append an execution record to this plan only. Include immutable `BASE`, task/fix
commits, actual commands/log/exit paths, exact baseline direction, final results,
96-state/hover/cleanup evidence, representative image paths, review outcomes,
native zoom/remote/assistive-tech limits and disk headroom. Label any accepted
nonzero gates honestly. Prove every non-plan tracked path remains byte/mode
identical to the freshly tested revision before a docs-only record commit:

```bash
git diff --name-only HEAD
git diff --check
git add docs/superpowers/plans/2026-10-27-mcp-workspace-ui-ux.md
git diff --cached --name-only
git commit -m "docs: Record MCP workspace verification"
git status --short
```

Then prove non-plan identity using the actual tested commit/tree saved above:

```bash
TESTED_SHA="$(< "$EVIDENCE/final-tested-sha.txt")"
git diff --exit-code "$TESTED_SHA"..HEAD -- . ':(exclude)docs/superpowers/plans/2026-10-27-mcp-workspace-ui-ux.md'
```

The record must distinguish the tested patch/commit from the later prose commit.
Do not merge, push, open a PR or remove worktrees without a separate user choice.

## Plan self-review and coverage ledger

| Specification requirement | Owning tasks |
| --- | --- |
| All Decisions, existing routes, no runners and no dependency/schema changes | Authority/non-goals; Tasks 1, 3, 6, 8 |
| Explicit account routes, path priority, membership/defaults/no-account behavior | Tasks 1, 4 and scoped workflow tests |
| Shell, titles/trails/New chat, MCP-only drawer isolation | Task 4; six-page shell/keyboard matrix in 8 |
| Catalog-first rows, filters, safe summaries and distinct empties | Task 4 |
| Categories/cards/icons/added-vs-connected/contextual activation | Tasks 2 and 5 |
| Unknown/empty/failure outcomes; real tool/prompt/resource interfaces | Tasks 3 and 6 |
| State-aware controls, local busy states, safe HTML and unchanged JSON | Tasks 1, 4, 6 and 8 |
| Grouped transport-aware forms, credential operations, inline/summary errors | Tasks 2, 5, 7 and 8 |
| Saved-configuration-only tests, no auto-connect, no secret cache echoes | Tasks 5, 7 and 8 |
| Actual EN/FR/theme/viewports, keyboard, contrast, real hover, reduced motion | Task 8 plus earlier browser RED |
| Fresh baseline, protected regressions, lint/security, docs/YARD, honest evidence | Tasks 0 and 8; per-task gates |

Planning self-review completed against all specification sections and Decisions.
The file map, task order, staged paths and existing SDK interfaces were reconciled.
Static checks on the final planned snippets passed:

- 35 Ruby and 20 ERB blocks compiled; 7 JavaScript blocks, 5 embedded JavaScript
  snippets and 25 Bash blocks passed syntax checks. Shell checks used `bash -n`,
  not execution of the future commands.
- 121 literal/enumerated locale references resolved in English and French;
  the proposed locale files contain the same 45 keys.
- 13 planned route names, scoped connection verbs and the detail path were
  checked using standalone Rails routing, without application boot.
- All six localized-integration replacement hunks matched the existing file;
  the resulting in-memory Ruby source compiled.
- Referenced existing/planned test paths, four local icon assets, document links,
  balanced fences, placeholder scan and whitespace checks passed.

These are planning checks, not runtime or application-test results. No application
boot, database preparation, MCP baseline, browser run or application implementation
occurred during planning. All execution checkboxes remain unchecked. Execution
choice and fresh baseline reporting/acceptance are still gates.

## Execution record — 2026-10-27

The planning statements and unchecked example steps above are historical. Tasks
0–8 have now been implemented and independently reviewed. This record is a later
documentation-only addition; it does not claim another application test run.

### Source and delivery identity

- Branch: `feat/mcp-workspace-ui`; execution worktree:
  `/home/cbldev/gitd/dilolabs/nosia/.worktrees/mcp-workspace-ui`.
- Immutable execution base: `5750fb0246efd3556a6e5e256f0146af58a41ec1`.
- Last tested and reviewed source commit:
  `798a85328a865412c9c9b52d81124dd2c5b2f621`.
- Its full tree: `f9108aa2cc995eafcd0edb580b76001f038cba55`.
- The later commit containing this record changes only this plan. Non-plan
  byte/mode identity is checked against that tested commit, not against an
  assumed parent. Documentation commits do not constitute fresh test evidence.
- No merge, push, PR, worktree removal or unrelated-main-worktree change was
  performed. The branch and worktree are retained for a separate user decision.

### Task and fix commits

Task 0 established the isolated baseline without a source commit. Each following
task passed independent specification and quality reviews after its fixes:

| Task | Implementation and follow-up commits, in order |
| --- | --- |
| 1 — authorized account context and operation compatibility | `6a4610bfd725898c791c48b6a3fa297144d333de` |
| 2 — safe credentials and recoverable configuration | `ab6118e9dd53964c877558d52095c3302ace8b49`, `f9a837afe27ddc1aecdb2c0a38c19c240865ce69`, `5bdc3813b789895174e140eb3b5a08e9bafc1d8d`, `5bb2f9274787802d397e5c8a7259c1cfc559af98` |
| 3 — truthful, independent capability outcomes | `03a5929867d2dd6704b9042564eada381a7768b8`, `9826c8696e46cc2938bd2cdec534b776e6a93cdb` |
| 4 — management shell, rows and mobile account context | `d62733e8b1ed53228c862c42626a9f6fa34aaf0b`, `1adef5e6b8069fbbd17398da338d664253c2f605`, `139cb56bada8e6a0ceac0c38f0033def307e199c` |
| 5 — catalog and setup recovery | `188666c7e6a692cc244e6d8553943f75bc1b8234`, `dd9df4986c3073ebe1f0cf79caa97cba9c4f634e` |
| 6 — details, safe connection feedback and progressive tabs | `d279c7043f17fdd7809e5176e3e48a54f4dd7c6f`, `fe0ad1f5f378f35324cce2f58e43f1deea64cc04`, `b8ab724b2edd28a9a389e77a2d0c71825b8ab06b` |
| 7 — transport-aware forms and saved-only testing | `c1503d229e3bc6378df7065c60ccaeafbd014a01`, `e02a0721528a89a2ff77dd24f8613f62e8cdd896`, `f0b3628cebfc32583541e9d645e1b9cc9d6fe50b` |
| 8 — browser matrix, workflow proof, documentation and test safety | `40b11524775fc18c3073627c4838da3c1d776fd8`, `d3134058f9cbc5022155f5c20983dabb549c823e`, `798a85328a865412c9c9b52d81124dd2c5b2f621` |

Review fixes include derived credential-header cleanup on replacement/removal and
transport changes, controlled malformed-container rejection, nullable metadata,
mobile New chat account context, template capabilities in every setup state,
Connect-failure recovery, Turbo-compatible tab history, persisted-transport saved
test availability, declared-field errors, correct error counts and secret re-entry
guidance. No client/protocol/schema/dependency or engine-definition change was
introduced. Test-only stdio prerequisites were explicitly approved, restore their
previous environment value, and do not relax production restrictions.

Precise legacy MCP presentation assertions were migrated without dropping JSON,
escaping, metadata, account, activation or disconnected-state checks. The final
full suite exposed an overlooked OpenAlex heading/submit-label assertion; only
those presentation expectations were updated, with focused RED/GREEN evidence
observed before the restart. It was not accepted as another baseline failure.

### Baseline direction and remaining nonzero gates

The user accepted MCP-only continuation with the exact fresh baseline findings
left unchanged, stopping for new regressions. No unrelated repair, suppression,
test exclusion or additional waiver was authorized or made.

- Original full baseline: seed `3095`, 1,160 tests / 22,941 assertions, exit **1**;
  only `Chat::RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults`,
  missing `augmented_context` at `app/models/chat/completionable.rb:39`, declared
  at `test/models/chat/request_options_test.rb:29`.
- Original protected browser baseline: seed `36642`, 64 tests / 26,512 assertions,
  exit **1**; six Profile language-selector errors at
  `test/system/profile_management_test.rb:272`, unable to find
  `button[type=submit]` inside the language-preference form.
- Brakeman baseline: exit **3**; high-confidence `PermitAttributes` at
  `app/controllers/api_tokens_controller.rb:62` and `EOLRails` at
  `Gemfile.lock:318`. Their messages remain respectively “Potentially dangerous
  key allowed for mass assignment” and “Support for Rails 8.0.5.1 ended on
  2026-10-07”.
- Existing duplicate `tools_cache` / `last_test_at` JSON warnings remain visible.

The six browser identities comprise the four
`test_native_Tab_keeps_every_{en,fr}_{light,dark}_mobile_profile_control_fully_above_the_bottom_navigation`
variants, `test_signed_language_preferences_keep_mobile_profile_controls_contained_and_keyboard_accessible_in_both_themes`,
and `test_long_email_and_French_validation_errors_stay_contained_in_the_mobile_scrolling_region`.
Current raw output and the recorded-identity audit retain their exact names and
messages. Full/browser/security gates are **nonzero, not green**.

### Restart boundary and evidence provenance

A server restart emptied `/tmp/opencode`, destroying the original baseline raw
files, per-task RED/GREEN logs, earlier final logs and browser artifacts. The
commits, staged queue-safety patch and isolated database survived. The user asked
to continue without repeating completed work. Lost raw files were not recreated,
and completed build/focused/full checks were not rerun merely to replace logs.

Completed results for the final source tree before the interruption are recovered
**session observations**, not currently inspectable raw output:

| Completed before restart | Seed | Observed result | Exit |
| --- | --- | --- | --- |
| Saved-configuration browser case | 23986 | 1 test / 14 assertions, passed | 0 |
| Empty Queue nonblocking probe | n/a | Immediate `ThreadError`, no indefinite wait | 0 |
| Tailwind build | n/a | Passed | 0 |
| Final focused suite, including activation | 63583 | 210 tests / 14,270 assertions, passed | 0 |
| Final full suite | 10156 | 1,243 tests / 24,640 assertions; only accepted `augmented_context` error | **1** |

Historical lost log names were `task8-conclusive-saved-busy.7k6JQX.log`,
`task8-conclusive-queue-probe.ycjXbH.log`,
`task8-conclusive-final-build.SZHRhW.log`,
`task8-conclusive-final-focused.J7NTzH.log` and
`task8-conclusive-final-full.faUblJ.log`. These names are provenance, not links to
surviving files. Pre-restart source correspondence rests on the session and the
surviving staged tree; old raw identity files are also lost.

The interrupted browser command had no observed completion and remained pending.
It and the pending lint/security/syntax/audits were completed after restart. New
raw logs, matching `.exit` files and copied browser artifacts are preserved in
the ignored, persistent worktree directory
`.superpowers/mcp-evidence-recovery/` (called `E` below). The exact recorder is
`.superpowers/mcp-verification-env.sh`. It retains the original nondisplaying
dotenv invocation and isolated `nosia_mcp_workspace_ui_test` database. `.env` was
never read, displayed, sourced or copied. Database-sharing commands ran
sequentially; no workers or real provider/stdio processes were launched.

| Pending gate completed after restart | Seed | Actual result | Raw log under `E` | Exit |
| --- | --- | --- | --- | --- |
| Expanded MCP and complete protected browser suite | 3 | 94 tests / 79,112 assertions; zero failures, six recorded Profile errors, zero skips | `resumed-final-browser.MbJ8WX.log` | **1** |
| RuboCop | n/a | 27 files, no offenses | `resumed-final-lint.HN107k.log` | 0 |
| Brakeman | n/a | Zero scanner errors, two recorded findings | `resumed-final-security.odLiV3.log` | **3** |
| Recorded-identity comparison | n/a | Only the accepted browser/security identities and messages | `resumed-recorded-identities.BdIKxs.log` | 0 |
| Changed syntax | n/a | 4 JavaScript / 22 Rails ERB files compile | `resumed-final-syntax.fzGxDG.log` | 0 |
| Current artifact/docs/YARD audit | n/a | Matrix, interaction evidence, documentation links and public helper contracts checked | `resumed-final-artifact-audit.2ebf4x.log` | 0 |

The resumed comparison uses the **recorded accepted identities**, not a fabricated
diff against lost baseline files. This record does not claim all final gates were
rerun after restart. `E/restart.md`, `E/resume-completion.md` and
`E/resumed-source-identity.json` explicitly describe this limitation.

Actual test commands used the wrappers defined above; the focused invocation
included the approved final request/model/helper/localization/protected-request
list and the additional activation regression:

```bash
rails_test tailwindcss:build
rails_test test test/controllers/mcp_workspace_scoping_test.rb test/controllers/mcp_workspace_configuration_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/mcp_workspace_catalog_test.rb test/controllers/mcp_workspace_detail_test.rb test/controllers/mcp_workspace_forms_test.rb test/controllers/mcp_servers_controller_test.rb test/controllers/mcp_connection_tests_test.rb test/models/mcp_server_configuration_test.rb test/models/mcp_server_capability_snapshot_test.rb test/models/mcp_server_test.rb test/models/mcp_server_local_test.rb test/lib/mcp_catalog_registry_test.rb test/helpers/mcp_catalog_helper_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/dashboards_controller_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb test/integration/activate_engine_test.rb
rails_test test
browser_test test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/system/accounts_settings_workspace_test.rb test/system/account_experience_test.rb test/system/agent_skills_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/profile_management_test.rb
mise exec ruby@4.0.7 -- bundle exec rubocop app/controllers/concerns/mcp_scoped.rb app/controllers/mcp_servers_controller.rb app/controllers/mcp_catalog_controller.rb app/controllers/mcp_servers app/models/mcp_server.rb app/models/mcp_server app/helpers/mcp_workspace_helper.rb app/helpers/mcp_forms_helper.rb lib/mcp_catalog.rb test/support/mcp_workspace_fixtures.rb test/support/mcp_browser_checks.rb test/controllers/mcp_workspace_scoping_test.rb test/controllers/mcp_workspace_configuration_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/mcp_workspace_catalog_test.rb test/controllers/mcp_workspace_detail_test.rb test/controllers/mcp_workspace_forms_test.rb test/models/mcp_server_configuration_test.rb test/models/mcp_server_capability_snapshot_test.rb test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/integration/localized_pages_test.rb test/integration/activate_engine_test.rb
mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

### Current browser and documentation evidence

Durable matrix root: `E/browser/mcp-browser-20261027-2132-dxxyqx/`.
Only newly generated browser fixture artifacts were copied there after the
resumed gate; these are not reconstructions of the old evidence.

- `matrix.json`: **96 unique** six-screen × EN/FR × light/dark × four-viewport
  states. Extra workflow tests are not counted as base states.
- `keyboard.jsonl` and `focus.jsonl`: **1,208 forward and 1,208 reverse** native
  Tab stops with matching order and focus samples, ≥44×44 controls, ≥2px outlines
  and unobscured geometry. Tall read-only panels use the documented intersection
  exception. No forced focus or test scrolling simulates focused visibility.
- `layout.jsonl`: all 96 states, including 552 action-label samples, 1,392
  breadcrumb samples and 64 computed submit-label measurements; no clipping or
  ellipsis. Ordinary editable values may scroll inside their input.
- `contrast.jsonl`: **11,352** composed-color samples in 288 keyboard/unhovered/
  hovered phase records. Minimum text ratio **4.945**; minimum meaningful nontext
  **3.191**. Actual Ready/Prêt status text and selected-tab indicators are covered
  against their real adjacent surfaces.
- `hover.jsonl`: **96 actual surface changes**, with real `:hover`, declared
  fine-pointer/hover capability emulation, stable bounds and exact token matches.
  No forced stylesheet or pseudo-state is used.
- All **20** dedicated session cleanup records prove restored driver/session and
  unchanged original driver registration; media/metrics/scripts are reset and
  dedicated sessions quit.
- **48 PNGs** and six `contact-{servers,catalog,setup,detail,new,edit}.jpg` sheets
  cover phone/desktop, both locales and themes. The parent opened all six sheets.
  Representative originals include `detail-fr-1440-1000-dark.png`,
  `setup-en-375-812-light.png` and `new-fr-375-812-light.png`. Reset-scroll images
  are layout evidence, not separate proof of focused visibility.
- Workflow coverage preserves scoped CRUD/activation, saved-only testing, real
  busy requests and unrelated-control availability, native/server validation,
  secret lifecycle plus actual Back navigation, empty/filter recovery, mobile and
  desktop composer context, transport switching, no-JS sections, reduced motion,
  capability outcomes and Turbo URL **and DOM** history restoration.
- Current audits and all samples are indexed by `E/resumed-browser-audit.json`.
  The English [MCP guide](../../mcp-workspace.md), docs-index link and changed
  public Ruby YARD were checked against actual interfaces.

The stronger reverse traversal exposed a focused link 0.25px above the main
viewport at 812×375. A retained regression preceded the MCP-only 8px top scroll
inset; native scrolling then kept the same control clear of the header without
lowering thresholds. The final small test follow-up prevents a missing health
hook from hanging on an unbounded Queue read.

### Independent reviews and final handoff limits

- Task 8 final specification: `ses_e81e74536ffeiUjZ4a4rjh84tr`, approved at
  `798a8532`; final quality: `ses_e81b05750ffeOcJ0ISSuzZM33t`, approved with no
  unresolved findings after the Queue fix.
- Fresh whole-feature specification: `ses_e80be8413ffeM1FksWIRLl45o1`,
  **SPEC COMPLIANT**. Fresh whole-feature quality/security/architecture/UI:
  `ses_e80ba5c53ffe55FkTCgSKnFbRV`, **APPROVED**, no Critical/Important/Minor
  findings. These were read-only reviews, not additional test runs.
- Native **200% browser zoom remains UNVERIFIED**. Capability/viewport emulation
  is not physical hardware or native zoom proof. Remote browser/platform and
  assistive-technology behavior not exercised here remains unverified; sampled
  checks are not an exhaustive accessibility audit.
- Restart-related loss of historical raw evidence remains a delivery limitation.
  Accepted nonzero full/browser/security results remain nonzero.
- Final observed disk headroom: **7.2 GiB** on the persistent filesystem and
  **7.8 GiB** in `/tmp`; no cleanup was performed.
- `E/resumed-tested-{sha,tree,parent}.txt` and `E/resumed-commit-proof.json` identify
  the actual tested source. The following documentation-only record commit is
  checked with:

```bash
git diff --exit-code 798a85328a865412c9c9b52d81124dd2c5b2f621..HEAD -- . ':(exclude)docs/superpowers/plans/2026-10-27-mcp-workspace-ui-ux.md'
```

The worktree is retained; integration or cleanup still requires separate user
authorization.
