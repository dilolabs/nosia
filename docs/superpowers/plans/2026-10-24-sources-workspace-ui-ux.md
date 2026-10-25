# Sources Workspace UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved balanced Sources workspace across default-account and explicitly scoped lists, new/edit forms, and detail pages while preserving source processing, account boundaries, and the dashboard's existing workflows.

**Architecture:** Reuse SourceScoped, existing CRUD/retry routes, SourceRow, Sourceable broadcasts, the uploader, and Lexxy. Add a small shared workspace header/style foundation plus Sources-only presentation, composed GET filters, and focused form/upload enhancements; do not introduce a new service layer, global account preference, schema, dependency, or ingestion workflow. Later Token usage, Agent skills, and MCP redesigns are separate subprojects.

**Tech Stack:** Actual checkout: Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL, Minitest/fixtures, Turbo/Stimulus, Importmap, Propshaft, Tailwind 4.1, and Lexxy 0.9.23. Do not upgrade or replace these while executing this plan.

---

## Authority and scope

- Approved specifications: [shared foundation](../specs/2026-10-24-workspace-tools-ui-ux-design.md) and [Sources design](../specs/2026-10-24-sources-workspace-ui-ux-design.md), committed in `0a58bbe`. The user reviewed them and answered **“Go”** to writing this plan.
- Only Sources application work is in scope. Do not implement Token usage, Agent skills, MCP, new account routes for those tools, or an app-wide visual migration here.
- Unscoped `/sources` remains the default-account list. Legacy new forms retain their membership filing picker; scoped forms remain fixed to the URL account; editing never transfers accounts.
- Keep the current 50-row page size, existing status enum, hundreds-scale listing strategy, source content/Markdown conversion, MIME/size behavior, JSON contracts, jobs, and broadcast stream/target identities.
- No application changes or Rails/database/browser regression runs were performed while writing this plan. Static plan validation is not implementation verification.

## File boundaries

| Unit | Create / modify | Responsibility |
| --- | --- | --- |
| Shared workspace foundation | Create `app/views/workspaces/_header.html.erb`, `app/assets/stylesheets/nosia/workspace.css`, paired `config/locales/{en,fr}.nosia_workspace.yml` | Heading, account/scope text, secondary navigation, shared buttons/panels; initially used only by Sources. |
| Sources shell and safe empty account | Create `app/helpers/sources_workspace_helper.rb`, `app/views/sources/setup.html.erb`; modify `app/controllers/concerns/source_scoped.rb`, `app/views/layouts/application.html.erb`, Sources index and Tailwind imports | Sources-only layout predicate, no-account GET guidance, preserved desktop New chat link, no duplicate history drawer. |
| List state and presentation | Modify `app/helpers/sources_helper.rb`, `app/views/sources/_source_filters.html.erb`, `_toolbar.html.erb`, `_rows.html.erb`, `_empty.html.erb`, `_add_menu.html.erb`, `_drop_hint.html.erb`, and `index.turbo_stream.erb`; keep `_counts.html.erb` unchanged; create Sources CSS and paired Sources-workspace catalogs | Composed URL filters, stable count IDs, responsive row metadata, clear empty states and actions. |
| Reusable row / uploader | Modify `app/views/sources/_source.html.erb`, `_status.html.erb`, `app/models/concerns/sourceable.rb`; create `app/javascript/controllers/source_upload_controller.js` | Safe background-renderable row actions, account-aware confirmation text, explicit browse into the existing dropzone. No uploader transport rewrite. |
| Forms | Create `app/helpers/source_forms_helper.rb`, `_form_page`, `_form_help`, `_form_errors`, `_field_error`, `_form_actions`, `app/javascript/controllers/source_form_controller.js`; modify four forms, `_account_field`, and eight new/edit templates | Existing fields/editors with truthful account identity, linked errors, retained values and focus. |
| Details | Create `app/views/sources/_detail.html.erb` and Sources-only document `_preview.html.erb`; modify four show templates; retain the shared document partial unchanged | Meaningful titles, status/metadata, clear authorized actions, unchanged safe content/preview behavior, including chat citations. |
| Verification | Create five focused request test files and two system files listed by task; update obsolete scoped request presentation assertions plus the specifically reviewed French heading and two Stimulus token selectors recorded below | New behavior first, retain existing permission/upload/JSON/broadcast/composer assertions. |
| Documentation | Create `docs/sources-workspace.md`; modify `docs/README.md`, `docs/DIAGRAMS.md` | Explain current scope, filters, forms, statuses, and honest verification limits. |

`SourceRow`, source models' validations, source controllers' write actions, jobs, routes, shared composer JavaScript, the global validation partial, global fixtures, and the old browser suites remain unchanged unless an actual regression requires a separately reviewed correction.

## Safe commands and evidence

Execution should use a sibling feature worktree, **not** modify the finished dashboard checkout. All command working directories after Task 0 are that new worktree. Its relative `../../.env` points to the original repository environment; never copy, display, edit, or commit any `.env` file.

These are exact shell functions for the execution shell, not repository files. If the harness starts a new shell for each call, redefine them in that call or inline their exact prefixes. Do not rely on environment/function persistence between tool calls.

```bash
rails_test() {
  mise exec ruby@4.0.7 -- env RAILS_ENV=test DATABASE_URL=postgresql:///nosia_sources_workspace_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails "$@"
}

browser_test() {
  mise exec ruby@4.0.7 -- env RAILS_ENV=test DATABASE_URL=postgresql:///nosia_sources_workspace_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test "$@"
}

record_check() {
  local output="$1"
  shift
  if [[ -e "$output" ]]; then
    print -u2 -- "Preserve existing evidence: choose a new log filename"
    return 2
  fi
  "$@" > "$output" 2>&1
  local exit_code=$?
  python3 -c 'import sys; from pathlib import Path; p=Path(sys.argv[1]); p.write_text(p.read_text()+"\nTRUE_EXIT_STATUS: "+sys.argv[2]+"\n"); print(str(p)+": exit "+sys.argv[2])' "$output" "$exit_code"
  return "$exit_code"
}
```

Do not enable shell `errexit` around expected RED commands. Read each saved log with the file-reading tool and record its actual tests/assertions/seed/exit. Preserve failed attempts under new filenames instead of overwriting them. Keep all database-sharing commands sequential, with no workers or live providers. Use `/tmp/opencode/` for execution artifacts, not source-controlled screenshots or logs.

Historical dashboard verification at `3040dc1`: focused 257 tests passed; full server suite 1,068 runs / 18,989 assertions / zero failures / one existing `Chat::RequestOptionsTest` missing-`augmented_context` error, exit 1. Its locations were `app/models/chat/completionable.rb:39` and `test/models/chat/request_options_test.rb:32` (test starts at 29). Brakeman exited 3 with existing API-token `PermitAttributes` and Rails EOL warnings. These are historical evidence, **not a fresh Sources baseline or a new failure waiver**. Do not fix, skip, or suppress unrelated issues; stop for user acceptance if the fresh baseline fails.

## Execution record and verified corrections — 2026-10-25

The user selected **Subagent-Driven execution**, then explicitly accepted the
fresh Task 0 baseline with **“Yes”** before Task 1. Acceptance covers only the
reproduced RequestOptions error, two scanner warnings, and duplicate-key JSON
warnings. It does not waive new feature failures or permit weakened assertions.

- Worktree: `/home/cbldev/gitd/dilolabs/nosia/.worktrees/sources-workspace-ui`;
  branch: `feat/sources-workspace-ui`; immutable execution base:
  `8c3328ef5ad028f0c8a02d0c7eb1d3b27459fa6e`.
- Restarted shells selected Ruby 3.4.11 unless explicitly overridden. Execution
  uses installed Ruby 4.0.7 via `mise exec ruby@4.0.7 --` for **every** Ruby/Bundler
  invocation, including standalone lint and scanner examples below. No upgrade.
- `/tmp/opencode/nosia-sources-test-helpers.zsh` supplies the launchers above and
  a non-overwriting logger with commit, safe command, timestamps, and true exit.
  Source it in each new execution shell; do not inspect or copy `.env`.
- `/tmp/opencode/nosia-sources-workspace-execution.md` retains detailed task,
  implementer/reviewer, RED/GREEN, failure-investigation, and evidence notes.
  External artifacts are session evidence, not required files in a fresh clone.

### Authoritative adaptations to the original stage snippets

The task snippets below retain their original step-by-step context, not a second
copy of the final application. These reviewed corrections supersede literal
examples where they differ; use the committed code for the final implementation.

1. **Shell callbacks:** shared `only:` action lists failed Rails' missing-action
   check. Equivalent action-name predicates preserve behavior without weakening
   framework configuration.
2. **Rows and uploads:** Turbo injects model-named render locals, so `_source`
   accepts `**_broadcast_locals` while still requiring `row`. A 375px browser RED
   exposed a clipped chooser; Sources-only action alignment keeps it in view.
   Upload failure copy is **“Upload not confirmed. Check sources or retry.”** /
   **“Importation non confirmée. Consultez les sources ou réessayez.”** because
   response loss can follow a committed document. The real retry test checks the
   persisted document and single job before Retry, not merely after it.
3. **Forms:** the invalid-editor border rule follows editor styles so a neutral
   shorthand cannot override it. The focused light/dark browser probe was added
   early in Task 4 and preserved when Task 6 extended that system file. Only one
   obsolete French Q&A heading assertion changed to the action-oriented shared
   `h1`; all rich-editor/textarea/submit assertions remain.
4. **Details:** a custom/truncated Q&A title is not the full question. Details
   retain the full escaped question when it differs, rather than discarding
   content. Exact EN/FR status/count/ISO assertions were strengthened. An opt-in,
   provider-free chunk fixture covers nonzero failed/pending counts; global
   fixture tables remain unchanged. Missing-file tests preserve shared blobs.
5. **Browser lifecycle:** 422 morphs preserve the form controller, so summary
   focus follows the existing `turbo:render` listener/cleanup pattern. Ordinary
   error links focus an existing same-form field without a GET/hash/cache visit
   that would clear drafts; modified clicks retain their normal intent.
   Website HTML drafts render through the existing normalization on a temporary
   duplicate, leaving the source and stored content unchanged. Markdown,
   frontmatter, sanitizer, model validation, and write contracts are unchanged.
6. **Action negotiation and CSRF:** redirects inherited Turbo Stream Accept and
   received the append-only Load more response. The Sources navigation controller
   requests HTML only for current-workspace marked Retry POST forms and generated
   hidden DELETE forms exactly matching a current workspace Delete link. Both
   actions retain Turbo's CSRF handling. **The initial native Retry workaround in
   `0cad9b2` is superseded by `407ae6e`:** a CSRF-enabled live-broadcast regression
   proved tokenless background forms need Turbo's session header. Protection
   settings are restored in `ensure`. Server redirects/formats, load-more
   negotiation, permissions, and uploader transport remain unchanged.
7. **Protected selectors:** only two exact `data-controller='dropzone'` selectors
   in `chat_account_selection_test.rb` changed to whitespace-token matching,
   because `dropzone source-upload` composes controllers. Every upload/account
   assertion remains. The other five protected browser files are unchanged.
8. **Final full-suite boundaries:** the legacy account-experience drawer test now
   expects zero drawers on its existing Sources paths but still requires two on
   unrelated tools. No path or assertion was removed. The document partial was
   also used by chat citations; it is restored byte-for-byte to the execution
   base. Sources details explicitly render a new Sources-only document preview,
   preserving the citation heading, markup, and sizing. Citation tests remain
   unchanged; an added workspace test protects the separation.
9. **Separately authorized test isolation:** the initial full run also exposed
   a pre-existing order-dependent RubyLLM registry leak. Unchanged committed-base
   tests reproduced exactly three failures/nineteen errors: URL-race fixtures
   initialized a fixture-only singleton, then MCP generation could not resolve
   `gpt-4o-mini`. The user explicitly chose **“Fix test isolation (Recommended)”**,
   not an expanded baseline waiver. Separate commit `62ba58e` snapshots and
   restores prior registry definedness/object in test teardown, with a permanent
   post-teardown guard. Race, job, provider, and production MCP behavior are
   unchanged; no registry preload, network refresh, dependency or fixture change.

Each adaptation followed an observed failure or a characterization coverage
gap, with independent specification then quality review. Original failed logs
were retained; no failure was skipped or suppressed. Task 6's final authorized
scope is eleven paths, including the Sources-only helper/controllers/templates
and new tests above; it is not limited to the original CSS-only assumption.

### Completed task evidence

All counts below are actual runs/assertions; seeds and exits are retained.
Application tasks and documentation each passed independent specification and
quality review. Native **200% browser zoom remains UNVERIFIED**; exact viewport
emulation and measured contrast are not native-zoom evidence.

| Gate/task | Commits / evidence | Result |
| --- | --- | --- |
| Fresh Task 0 focused | `sources-workspace-baseline-focused.log` | 223 / 12,835; seed 7240; exit 0 |
| Fresh Task 0 full | `sources-workspace-baseline-full.log` | 1,068 / 18,989; seed 47125; 0 failures, 1 accepted RequestOptions error; **exit 1** |
| Fresh Task 0 protected browsers | `sources-workspace-baseline-browser.log` | 100 / 4,721; seed 33735; exit 0 |
| Fresh Task 0 Brakeman | `sources-workspace-baseline-brakeman.log` | 2 accepted warnings: API-token `PermitAttributes`, Rails EOL; **exit 3** |
| Task 1 | `dc1249b`; `sources-workspace-task1-green-20261025T075227-775955.log` | 125 / 11,973; seed 21666; exit 0 |
| Task 2 | `f762963`, `427eb13`; `sources-workspace-task2-copy-correction-green.log` | 27 / 10,112; seed 18562; exit 0 |
| Task 3 | `bf83d1d`, `4d51c63`, `9a169c9`; `sources-workspace-task3-upload-uncertainty-*.log` | Requests 116 / 11,609, seed 14890; browsers 3 / 40, seed 33964; exits 0 |
| Task 4 | `a2562e2`, `1eea370`; `sources-workspace-task4-editor-style-*.log` | Requests 162 / 12,928, seed 16360; style probe 1 / 11, seed 26662; exits 0 |
| Task 5 | `4f4e207`, `c60b260`, `bd9944a`; `sources-workspace-task5-characterization-green.log` | 164 / 13,343; seed 60348; exit 0 |
| Task 6 | `0cad9b2`, `407ae6e`; `sources-workspace-task6-csrf-*.log` | New browsers 19 / 1,809, seed 24130; protected 100 / 4,721, seed 5760; requests 240 / 14,405, seed 5916; exits 0 |
| Task 7 | `ce86c98`; `sources-workspace-task7-*.log` | Three documentation paths; local links, scope/diff checks exit 0; no new application-test claim |

Log filenames in this table are under `/tmp/opencode/`. Task 6's current evidence
is `/tmp/opencode/sources-workspace-852967/`; earlier complete representative
reviews are retained in `839871/` and `827079/`. The implementer and spec reviewer
opened the sixteen specified list/form/detail/setup/422 images; the parent also
opened representative lists, all four detail types, editors, both setup themes,
and the retained bold draft after error-link focus. The follow-up additionally
reviewed the live-CSRF Retry screenshot. Contrast samples per theme: 139; minima:

| Theme | Normal text | Control border | Focus outline |
| --- | ---: | ---: | ---: |
| Light | 4.945457 | 4.349232 | 4.945457 |
| Dark | 7.129980 | 3.780915 | 10.802270 |

Task 8 final whole-feature verification/reviews are recorded separately below.
No merge, push, PR, worktree removal, or later-tool implementation
has been authorized by completing these tasks.

## Task 0: Establish an isolated, reproducible baseline

**No application edits.** Create only an isolated worktree and dedicated test database, build the existing ignored CSS, and retain logs.

- [x] **Step 1: Verify clean planning checkout and create the feature worktree.** Run from the current dashboard worktree. If the branch/path already exists or the checkout is modified, inspect and ask rather than overwriting user work.

```bash
git status --short
git worktree list
git -C /home/cbldev/gitd/dilolabs/nosia check-ignore .worktrees/sources-workspace-ui
git worktree add ../sources-workspace-ui -b feat/sources-workspace-ui HEAD
```

Expected: a clean checkout, ignored `.worktrees` destination, and new branch/worktree at `/home/cbldev/gitd/dilolabs/nosia/.worktrees/sources-workspace-ui`. Move the harness session there with `tools.opencode.session_move` if using it as the primary worktree, or set every tool's working directory explicitly. Do not delete or move the dashboard worktree.

- [x] **Step 2: Check installed tooling and free space in the new worktree.**

```bash
mise exec ruby@4.0.7 -- ruby --version
mise exec ruby@4.0.7 -- bundle check
python3 --version
/usr/bin/chromium --version
/usr/bin/chromedriver --version
df -h . /tmp/opencode
record_check /tmp/opencode/sources-workspace-execution-base.log git rev-parse HEAD
```

Expected: installed dependencies and matching local Chromium/driver. If missing, ask; do not install packages. If disk space is insufficient, ask before any cleanup. The old worktree had limited root-disk headroom; do not delete caches or other databases on your own.

- [x] **Step 3: Prepare only the dedicated test database and existing CSS.** Verify the explicit process environment without printing environment contents.

```bash
mise exec ruby@4.0.7 -- env RAILS_ENV=test DATABASE_URL=postgresql:///nosia_sources_workspace_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -e 'abort "Unsafe test environment" unless ENV["RAILS_ENV"] == "test" && ENV["DATABASE_URL"] == "postgresql:///nosia_sources_workspace_test" && ENV["AI_API_KEY"] == "nosia-test-key" && ENV["PARALLEL_WORKERS"] == "1"; puts "Dedicated test environment verified"'
rails_test db:prepare
rails_test runner 'abort "Wrong database" unless Rails.env.test? && ActiveRecord::Base.connection.select_value("SELECT current_database()") == "nosia_sources_workspace_test"; puts "Dedicated test database verified"'
rails_test tailwindcss:build
```

Never run `db:reset`, drop shared databases, start queue/provider workers, change dependencies, or copy environment files. Keep generated Tailwind output ignored.

- [x] **Step 4: Run focused/server/browser baselines and the scanner sequentially.**

```bash
record_check /tmp/opencode/sources-workspace-baseline-focused.log rails_test test test/controllers/sources_controller_test.rb test/controllers/sources/documents_controller_test.rb test/controllers/sources/texts_controller_test.rb test/controllers/sources/qnas_controller_test.rb test/controllers/sources/websites_controller_test.rb test/controllers/accounts/scoped_sources_test.rb test/controllers/accounts/scoped_source_operations_test.rb test/models/source_row_test.rb test/models/sourceable_test.rb test/models/sourceable_broadcast_test.rb test/models/account_source_broadcast_test.rb test/models/document_source_registration_test.rb test/integration/localized_pages_test.rb test/integration/localized_broadcasts_test.rb test/internationalization/catalogs_test.rb
record_check /tmp/opencode/sources-workspace-baseline-full.log rails_test test
record_check /tmp/opencode/sources-workspace-baseline-browser.log browser_test test/system/sources_dropzone_test.rb test/system/account_experience_test.rb test/system/localization_test.rb test/system/dashboard_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
record_check /tmp/opencode/sources-workspace-baseline-brakeman.log mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

Read the logs. Expected: focused checks pass; full results and scanner warnings/exits must be freshly compared with the historical evidence above. Stop before Task 1 on any failure/error or scanner warning unless the user explicitly accepts that exact fresh baseline. No broad waiver is implied by approving this plan. Record the user's decision and actual counts in execution notes; never describe an exiting-1 full suite as green.

- [x] **Step 5: Retain the baseline and review readiness.** Run `git status --short` to confirm no tracked application changes. With subagent-driven execution, obtain independent spec and verification-quality reviews before Task 1. No source commit is required for environment-only work.

## Task 1: Add the workspace shell and no-account GET guidance

**Create:** `test/controllers/sources_workspace_shell_test.rb`, `app/helpers/sources_workspace_helper.rb`, `app/views/workspaces/_header.html.erb`, `app/views/sources/setup.html.erb`, `app/assets/stylesheets/nosia/workspace.css`, `config/locales/en.nosia_workspace.yml`, `config/locales/fr.nosia_workspace.yml`, `config/locales/en.nosia_sources_workspace.yml`, `config/locales/fr.nosia_sources_workspace.yml`.
**Modify:** `app/controllers/concerns/source_scoped.rb`, `app/views/layouts/application.html.erb`, `app/views/sources/index.html.erb`, `app/views/sources/_toolbar.html.erb`, `app/assets/tailwind/application.css`.

- [x] **Step 1: Write the request tests before application edits.**

```ruby
# test/controllers/sources_workspace_shell_test.rb
require "test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceShellTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "legacy and scoped lists identify their real account without GET writes" do
    counts = [ Document.count, Text.count, Qna.count, Website.count, TokenUsage.count ]
    assert_no_enqueued_jobs do
      get sources_path, params: { account_id: @second.id }
    end
    assert_response :success
    assert_select "[data-source-workspace] h1", text: I18n.t("nosia.sources.title")
    assert_select "[data-workspace-scope]", text: "Default account: #{@first.name}"
    assert_select "#accordion-right-actions, #drawer-right", count: 0
    assert_select "[data-source-workspace] a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
    assert_equal counts, [ Document.count, Text.count, Qna.count, Website.count, TokenUsage.count ]

    get account_sources_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_select "[data-workspace-scope]", text: "Account: #{@second.name}"
    assert_select "[data-source-workspace] a[href='#{new_chat_path}']", count: 0
    assert_equal @first, @user.first_account
  end

  test "no-membership list and legacy new forms show setup rather than controls" do
    sign_in_overview(experience(:users, :overview_no_account))
    paths = [ sources_path ] + SourceRow::TYPES.map { |type| public_send("new_sources_#{type}_path") }
    paths.each do |path|
      assert_no_enqueued_jobs { get path }
      assert_response :success
      assert_select "[data-source-setup]", count: 1
      assert_select "[data-source-workspace] a[href='#{accounts_path}']"
      assert_select "[data-source-workspace] form, [data-source-workspace] [data-controller~='dropzone']", count: 0
    end
    get account_sources_path(@first)
    assert_response :not_found
    get sources_text_path(experience(:texts, :overview_first_text))
    assert_response :not_found
    get edit_sources_text_path(experience(:texts, :overview_first_text))
    assert_response :not_found
  end

  test "shell is localized and drawer suppression does not affect chat pages" do
    get sources_path, headers: { "Accept-Language" => "fr" }
    assert_select "[data-workspace-scope]", text: "Compte par défaut : #{@first.name}"
    refute_match(/translation missing|missing translation/i, response.body)
    get new_chat_path
    assert_response :success
    assert_select "#accordion-right-actions, #drawer-right", count: 2
  end
end
```

- [x] **Step 2: Run RED and inspect the actual failure.**

```bash
record_check /tmp/opencode/sources-workspace-task1-red.log rails_test test test/controllers/sources_workspace_shell_test.rb
```

Expected RED: missing workspace markup and existing nil-account rendering errors. These directly exercise the feature, not a missing database/asset/fixture. Do not add implementation until those causes are observed.

- [x] **Step 3: Add the helper, shared header, and setup page.**

```ruby
# app/helpers/sources_workspace_helper.rb
module SourcesWorkspaceHelper
  # @return [Boolean] Whether the current page belongs to the Sources workspace
  def sources_workspace_page?
    controller_path == "sources" || controller_path.start_with?("sources/")
  end

  # @param account [Account, nil] The displayed, authorized account
  # @param default [Boolean] Whether this is the legacy default-account list
  # @return [String, nil] Escaped by the caller's ordinary ERB rendering
  def source_workspace_scope(account, default: false)
    if account
      key = default ? "default_account" : "account"
      t("nosia.workspace.#{key}", name: account.name)
    end
  end

  # @param title [String, nil] Current form/detail title, absent on the list
  # @return [Array<Hash>] Legacy breadcrumb; scoped pages use the account breadcrumb
  def source_workspace_trail(title: nil)
    if @scoped_source_account
      []
    else
      trail = [ { label: t("nosia.nav.home"), path: user_root_path } ]
      trail << { label: t("nosia.sources.title"), path: title ? source_index_path : nil }
      trail << { label: title, path: nil } if title
      trail
    end
  end
end
```

```erb
<%# app/views/workspaces/_header.html.erb %>
<%# locals: (title:, description: nil, scope_label: nil, trail: [], back_path: nil, show_new_chat: false, actions: nil) %>
<% content_for :title, title %>
<header class="n-workspace-header">
  <% if trail.any? %>
    <nav aria-label="<%= t('nosia.workspace.breadcrumb') %>" class="n-workspace-help">
      <ol class="n-workspace-trail !list-none">
        <% trail.each_with_index do |item, index| %>
          <% if index.positive? %><li aria-hidden="true">/</li><% end %>
          <%= tag.li aria: { current: item[:path] ? nil : "page" } do %>
            <% if item[:path] %>
              <%= link_to item.fetch(:label), item.fetch(:path), class: "n-workspace-link" %>
            <% else %>
              <%= item.fetch(:label) %>
            <% end %>
          <% end %>
        <% end %>
      </ol>
    </nav>
  <% end %>
  <div class="n-workspace-heading-row">
    <div class="min-w-0">
      <h1 class="n-workspace-title"><%= title %></h1>
      <% if description %><p class="n-workspace-help"><%= description %></p><% end %>
      <% if scope_label %><p class="n-workspace-scope" data-workspace-scope><%= scope_label %></p><% end %>
    </div>
    <div class="n-workspace-actions">
      <% if back_path %><%= link_to t("nosia.actions.back"), back_path, class: "n-workspace-link", data: { workspace_back: true } %><% end %>
      <% if show_new_chat %>
        <div class="hidden lg:block"><%= link_to t("nosia.nav.new_chat"), new_chat_path, class: "n-workspace-link" %></div>
      <% end %>
      <%= actions %>
    </div>
  </div>
</header>
```

```erb
<%# app/views/sources/setup.html.erb %>
<div class="n-workspace n-source-workspace" data-source-workspace data-source-setup>
  <%= render "workspaces/header", title: t("nosia.sources.title"), trail: source_workspace_trail,
        show_new_chat: true %>
  <section class="n-workspace-panel" aria-labelledby="sources-setup-title">
    <h2 id="sources-setup-title" class="n-workspace-section-title"><%= t("nosia.sources_workspace.setup_title") %></h2>
    <p class="n-workspace-help"><%= t("nosia.sources_workspace.setup_help") %></p>
    <%= link_to t("nosia.sources_workspace.setup_action"), accounts_path, class: "n-workspace-button n-workspace-primary" %>
  </section>
</div>
```

Append these callbacks after `before_action :set_source_account` and these private methods immediately after `source_account` in `SourceScoped`. Existing write actions/format checks remain untouched.

```ruby
before_action :render_source_workspace_setup, only: %i[ index new ]
before_action :require_source_read_account, only: %i[ show edit ]

def render_source_workspace_setup
  if source_account.nil? && (controller_path == "sources" || action_name == "new")
    render "sources/setup", formats: [ :html ]
  end
end

def require_source_read_account
  raise ActiveRecord::RecordNotFound unless source_account
end
```

In `app/views/layouts/application.html.erb`, change only the right-drawer condition from `Current.user && !account_page? && !dashboard_page?` to `Current.user && !account_page? && !dashboard_page? && !sources_workspace_page?`.

Replace the index's existing title block with the shared header and wrap its entire existing stream/list content in `<div class="n-workspace n-source-workspace" data-source-workspace>…</div>`. Keep both stream subscriptions and all existing dropzone attributes/targets/URLs intact. The complete index for this task is:

```erb
<%# app/views/sources/index.html.erb %>
<% content_for :account_tool_title, t("nosia.account_experience.sources") if @scoped_source_account %>
<div class="n-workspace n-source-workspace" data-source-workspace>
  <%= turbo_stream_from source_account, "sources", I18n.locale %>
  <% unless @query %>
    <%= turbo_stream_from source_account, "sources", "list:#{@type}:#{@status}", I18n.locale %>
  <% end %>
  <%= render "workspaces/header", title: t("nosia.sources.title"),
        description: t("nosia.sources_workspace.description"),
        scope_label: source_workspace_scope(source_account, default: !@scoped_source_account),
        trail: source_workspace_trail, show_new_chat: !@scoped_source_account,
        actions: capture { render "sources/add_menu" } %>
  <div class="flex flex-col gap-4 md:flex-row">
    <%= render "sources/source_filters", type: @type, status: @status, counts: @counts %>
    <div class="min-w-0 flex-1" data-controller="dropzone"
         data-dropzone-messages-value="<%= t('nosia.sources.upload_messages').to_json %>"
         data-dropzone-url-value="<%= source_collection_path(:document) %>"
         <% if @scoped_source_account %>data-dropzone-account-id-value="<%= @scoped_source_account.id %>"<% end %>
         data-dropzone-max-file-size-value="50" data-dropzone-click-to-browse-value="false"
         data-dropzone-accepted-files-value="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/plain,image/png,image/jpeg">
      <%= render "sources/toolbar", type: @type, status: @status, sort: @sort, query: @query %>
      <div data-dropzone-target="container" class="relative rounded-lg border-2 border-dashed n-main-border transition data-[active=true]:border-blue-500">
        <input type="file" multiple class="hidden" data-dropzone-target="input"
               accept="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/plain,image/png,image/jpeg">
        <div id="sources_list">
          <%= render "sources/rows", rows: @rows, has_more: @has_more, page: @page,
                type: @type, status: @status, sort: @sort, query: @query %>
        </div>
      </div>
      <ul class="mt-3 hidden space-y-1" data-dropzone-target="list"></ul>
    </div>
  </div>
</div>
```

Remove the single `<%= render "sources/add_menu" %>` line from the old toolbar; the chooser now appears once in the header. The toolbar itself is replaced in Task 2.

- [x] **Step 4: Add paired copy and shared styles.** No new plural branches are introduced.

```yaml
# config/locales/en.nosia_workspace.yml
en:
  nosia:
    workspace:
      breadcrumb: "Workspace navigation"
      account: "Account: %{name}"
      default_account: "Default account: %{name}"
```

```yaml
# config/locales/fr.nosia_workspace.yml
fr:
  nosia:
    workspace:
      breadcrumb: "Navigation de l’espace de travail"
      account: "Compte : %{name}"
      default_account: "Compte par défaut : %{name}"
```

```yaml
# config/locales/en.nosia_sources_workspace.yml
en:
  nosia:
    sources_workspace:
      description: "Manage the knowledge available to conversations in this account."
      setup_title: "Set up an account to manage sources"
      setup_help: "Create or join an account before adding documents, websites, text, or Q&As."
      setup_action: "Your accounts"
```

```yaml
# config/locales/fr.nosia_sources_workspace.yml
fr:
  nosia:
    sources_workspace:
      description: "Gérez les connaissances disponibles pour les conversations de ce compte."
      setup_title: "Configurez un compte pour gérer les sources"
      setup_help: "Créez ou rejoignez un compte avant d’ajouter des documents, des sites web, des textes ou des questions-réponses."
      setup_action: "Vos comptes"
```

```css
/* app/assets/stylesheets/nosia/workspace.css */
.n-workspace { @apply mx-auto w-full min-w-0 max-w-7xl space-y-6 pb-24 text-neutral-900 dark:text-neutral-100 lg:pb-8; }
.n-workspace-header { @apply min-w-0 space-y-3; }
.n-workspace-heading-row { @apply flex min-w-0 flex-wrap items-start justify-between gap-4; }
.n-workspace-title { overflow-wrap: anywhere; @apply text-3xl font-semibold tracking-tight; }
.n-workspace-help { overflow-wrap: anywhere; @apply text-sm leading-relaxed text-neutral-600 dark:text-neutral-300; }
.n-workspace-scope { overflow-wrap: anywhere; @apply mt-2 inline-block max-w-full rounded-md border border-neutral-500 bg-white px-3 py-1 text-sm dark:bg-neutral-800; }
.n-workspace-actions { @apply flex flex-wrap items-center gap-3; }
.n-workspace-trail { @apply flex min-w-0 flex-wrap items-center gap-2; }
.n-workspace-trail li { overflow-wrap: anywhere; @apply min-w-0; }
.n-workspace-panel { @apply min-w-0 rounded-xl border border-neutral-400 bg-white p-5 dark:border-neutral-500 dark:bg-neutral-800 sm:p-6; }
.n-workspace-section-title { @apply text-base font-semibold; }
.n-workspace-link { overflow-wrap: anywhere; @apply inline-flex min-h-11 max-w-full items-center rounded-sm text-sm font-medium text-green-800 underline underline-offset-4 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:text-green-200 dark:focus:outline-green-300; }
.n-workspace-button { @apply inline-flex min-h-11 min-w-11 max-w-full items-center justify-center gap-2 rounded-md border border-neutral-500 bg-white px-3 py-2 text-sm font-medium text-neutral-900 hover:bg-neutral-100 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 disabled:cursor-wait disabled:opacity-60 dark:bg-neutral-800 dark:text-neutral-100 dark:hover:bg-neutral-700 dark:focus:outline-green-300; }
.n-workspace-primary { @apply border-green-700 bg-green-700 text-white hover:bg-green-800 dark:border-green-300 dark:bg-green-300 dark:text-green-950 dark:hover:bg-green-200; }
.n-workspace-danger { @apply text-red-800 focus:outline-red-700 dark:text-red-200 dark:focus:outline-red-300; }
main:has([data-source-workspace]) { min-width: 0; scroll-padding-block-end: 6rem; }
@media (prefers-reduced-motion: reduce) { .n-workspace a, .n-workspace button { transition: none; } }
```

Import this file after `dashboard.css` in `app/assets/tailwind/application.css`:

```css
@import "../stylesheets/nosia/workspace.css" layer(utilities);
```

- [x] **Step 5: Build and run GREEN plus scope/layout regressions.**

```bash
rails_test tailwindcss:build
record_check /tmp/opencode/sources-workspace-task1-green.log rails_test test test/controllers/sources_workspace_shell_test.rb test/controllers/accounts/scoped_sources_test.rb test/controllers/accounts/scoped_source_operations_test.rb test/controllers/dashboards_controller_test.rb test/integration/header_navigation_test.rb test/internationalization/catalogs_test.rb
mise exec ruby@4.0.7 -- env RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app/helpers/sources_workspace_helper.rb app/controllers/concerns/source_scoped.rb test/controllers/sources_workspace_shell_test.rb
git diff --check
```

Expected: all focused checks pass; no existing drawer behavior changes outside Sources. Preserve only a fresh, explicitly accepted historical baseline exception, never new feature failures.

- [x] **Step 6: Commit explicit Task 1 paths.**

```bash
git add app/helpers/sources_workspace_helper.rb app/controllers/concerns/source_scoped.rb app/views/workspaces/_header.html.erb app/views/sources/setup.html.erb app/views/sources/index.html.erb app/views/sources/_toolbar.html.erb app/views/layouts/application.html.erb app/assets/stylesheets/nosia/workspace.css app/assets/tailwind/application.css config/locales/en.nosia_workspace.yml config/locales/fr.nosia_workspace.yml config/locales/en.nosia_sources_workspace.yml config/locales/fr.nosia_sources_workspace.yml test/controllers/sources_workspace_shell_test.rb
git commit -m "feat(sources): Add workspace shell and account setup guidance"
```

## Task 2: Compose filters in the URL and keep count targets stable

**Create:** `test/controllers/sources_workspace_filters_test.rb`, `app/assets/stylesheets/nosia/sources.css`.
**Modify:** `app/helpers/sources_helper.rb`, `app/views/sources/_source_filters.html.erb`, `_toolbar.html.erb`, index layout class, both Sources-workspace catalogs, both existing Sources catalogs, `test/controllers/accounts/scoped_sources_test.rb`, and the Tailwind import file.

- [x] **Step 1: Add behavior tests and replace the obsolete two-form/resetting-link contract.**

```ruby
# test/controllers/sources_workspace_filters_test.rb
require "test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceFiltersTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "type and status links preserve other selections but reset pagination" do
    get account_sources_path(@second), params: { type: "text", status: "failed", q: "Research", sort: "title", page: 3 }
    assert_response :success
    assert_select "form[data-source-toolbar][action='#{account_sources_path(@second)}'][method='get']", count: 1
    assert_select "input[name='page']", count: 0
    assert_select "input[name='type'][value='text']", count: 1
    assert_select "input[name='q'][value='Research']", count: 1
    assert_select "select[name='status'] option[selected][value='failed']"
    assert_select "select[name='sort'] option[selected][value='title']"
    assert_link_state "[data-source-filter-type='document']", { "type" => "document", "status" => "failed", "sort" => "title", "q" => "Research" }
    assert_link_state "[data-source-filter-type='all']", { "status" => "failed", "sort" => "title", "q" => "Research" }
    assert_link_state "[data-source-filter-status='pending']", { "type" => "text", "status" => "pending", "sort" => "title", "q" => "Research" }
    assert_select "[data-source-reset][href='#{account_sources_path(@second)}']"
  end

  test "legacy controls remain default-account controls with all seven zero-capable count IDs" do
    get sources_path, params: { type: "document", status: "indexed", q: "First", sort: "chunks" }
    assert_select "form[data-source-toolbar][action='#{sources_path}']"
    assert_select "select[name='status'] option[value='indexed'][selected]"
    assert_select "[data-source-filter-status='failed'] #source_count_status-failed", text: "0"
    assert_select "[data-source-filter-status='pending'] #source_count_status-pending", text: "0"
    keys = %w[all type-document type-text type-qna type-website status-failed status-pending]
    keys.each { |key| assert_select "#source_count_#{key}", count: 1 }
    assert_select "#source_count_all", text: SourceRow.counts_for(@first).fetch(:total).to_s
    assert_link_state "[data-source-filter-type='website']", { "type" => "website", "status" => "indexed", "sort" => "chunks", "q" => "First" }, path: sources_path
  end

  private
    def assert_link_state(selector, expected, path: account_sources_path(@second))
      elements = css_select(selector)
      assert_equal 1, elements.length
      uri = URI.parse(elements.first["href"])
      assert_equal path, uri.path
      assert_equal expected, Rack::Utils.parse_nested_query(uri.query.to_s)
    end
end
```

Replace only the method named `"filters toolbar add menu and empty states retain scoped or legacy paths"` in `test/controllers/accounts/scoped_sources_test.rb` with:

```ruby
test "filters toolbar add menu and empty states retain scoped or legacy paths" do
  options = { type: "text", status: "failed", sort: "title", q: "Research" }
  get account_sources_path(@second), params: options
  assert_response :success
  assert_select "form[data-source-toolbar][action='#{account_sources_path(@second)}'][method='get']", count: 1
  assert_select "input[name='type'][value='text']", count: 1
  assert_select "select[name='status'] option[selected][value='failed']"
  assert_select "input[name='q'][value='Research']", count: 1
  assert_select "select[name='sort'] option[selected][value='title']"
  %w[failed pending].each do |status|
    assert_select "a[href='#{account_sources_path(@second, **options.merge(status: status))}']"
  end
  SourceRow::TYPES.each do |type|
    assert_select "a[href='#{account_sources_path(@second, **options.merge(type: type))}']"
    new_path = public_send("new_account_sources_#{type}_path", @second)
    assert_select "a[href='#{new_path}']"
  end
  SourceRow::TYPES.each do |type|
    get account_sources_path(@empty), params: { type: type }
    assert_response :success
    new_path = public_send("new_account_sources_#{type}_path", @empty)
    assert_select ".sources-empty a[href='#{new_path}']"
  end
  get sources_path
  assert_response :success
  assert_select "form[data-source-toolbar][action='#{sources_path}'][method='get']", count: 1
  assert_select "[data-dropzone-url-value='#{sources_documents_path}']"
  assert_select "[data-dropzone-account-id-value]", count: 0
  SourceRow::TYPES.each do |type|
    new_path = public_send("new_sources_#{type}_path")
    assert_select "a[href='#{new_path}']"
  end
end
```

All other scoped authorization, helper, load-more, stream, and account-default tests stay intact.

- [x] **Step 2: Observe RED before adding the filter helper/templates.**

```bash
record_check /tmp/opencode/sources-workspace-task2-red.log rails_test test test/controllers/sources_workspace_filters_test.rb test/controllers/accounts/scoped_sources_test.rb
```

Expected: missing toolbar markers/status selection and links that still discard selections; not fixture failures.

- [x] **Step 3: Add composed navigation and one GET toolbar.** Add this public method before `source_new_path` in `SourcesHelper`; do not change `source_index_path` itself.

```ruby
# @param changes [Hash] Selected type/status changes; pagination is never carried
# @return [String] Scoped or legacy list URL preserving the other current filters
def source_filter_path(**changes)
  options = { type: @type, status: @status, sort: @sort, q: @query }.merge(changes).compact
  options.delete(:type) if options[:type] == "all"
  options.delete(:status) if options[:status] == "all"
  options.delete(:sort) if options[:sort] == "recent"
  source_index_path(**options)
end
```

```erb
<%# app/views/sources/_source_filters.html.erb %>
<%# locals: (type:, status:, counts:) %>
<nav class="n-source-filters" aria-label="<%= t('nosia.sources.filters') %>">
  <p class="n-workspace-help"><%= t("nosia.sources_workspace.counts_scope") %></p>
  <div class="n-source-filter-types">
    <%= link_to source_filter_path(type: "all"), class: "n-source-filter", aria: { current: type == "all" ? "true" : nil }, data: { source_filter_type: "all" } do %>
      <span><%= t("nosia.sources.all") %></span><%= render "sources/counts", key: "all", value: counts[:total] %>
    <% end %>
    <% SourceRow::TYPES.each do |key| %>
      <%= link_to source_filter_path(type: key), class: "n-source-filter", aria: { current: type == key ? "true" : nil }, data: { source_filter_type: key } do %>
        <span><%= source_type_icon(key) %><%= t("nosia.sources.types.#{key}", count: 2) %></span>
        <%= render "sources/counts", key: "type-#{key}", value: counts[:by_type].fetch(key, 0) %>
      <% end %>
    <% end %>
  </div>
  <div class="n-source-filter-attention">
    <p class="n-workspace-help"><%= t("nosia.sources.needs_attention") %></p>
    <% { "failed" => :error, "pending" => :pending }.each do |key, variant| %>
      <%= link_to source_filter_path(status: key), class: "n-source-filter", aria: { current: status == key ? "true" : nil }, data: { source_filter_status: key } do %>
        <span><%= t("nosia.sources.#{key}_filter") %></span>
        <%= render "sources/counts", key: "status-#{key}", value: counts[:by_status].fetch(key, 0), variant: variant %>
      <% end %>
    <% end %>
  </div>
</nav>
```

```erb
<%# app/views/sources/_toolbar.html.erb %>
<%# locals: (type:, status:, sort:, query:) %>
<%= form_with url: source_index_path, method: :get, class: "n-source-toolbar", role: "search", data: { controller: "auto-submit", source_toolbar: true } do |form| %>
  <%= form.hidden_field :type, value: type %>
  <div class="n-source-search">
    <%= label_tag "source-q", t("nosia.sources_workspace.search_label"), class: "n-label" %>
    <%= form.search_field :q, id: "source-q", value: query, placeholder: t("nosia.sources.search"), class: "n-field" %>
  </div>
  <div class="n-source-toolbar-field">
    <%= form.label :status, t("nosia.sources_workspace.status_label"), class: "n-label" %>
    <% statuses = [ [ t("nosia.sources_workspace.all_statuses"), "all" ] ] + SourceRow::STATUSES.map { |key| [ t("nosia.sources.status.#{key == 'pending' ? 'processing' : key}"), key ] } %>
    <%= form.select :status, options_for_select(statuses, status), {}, class: "n-select", data: { action: "change->auto-submit#submit" } %>
  </div>
  <div class="n-source-toolbar-field">
    <%= form.label :sort, t("nosia.sources_workspace.sort_label"), class: "n-label" %>
    <%= form.select :sort, options_for_select(SourceRow::SORTS.map { |key| [ t("nosia.sources.sort.#{key}"), key ] }, sort), {}, class: "n-select", data: { action: "change->auto-submit#submit" } %>
  </div>
  <%= form.submit t("nosia.actions.filter"), class: "n-workspace-button" %>
  <%= link_to t("nosia.actions.reset"), source_index_path, class: "n-workspace-link", data: { source_reset: true } %>
<% end %>
```

In the index replace `<div class="flex flex-col gap-4 md:flex-row">` with `<div class="n-source-layout">`. Keep `_counts.html.erb` unchanged: one responsive navigation renders each existing count ID exactly once.

- [x] **Step 4: Add list layout, paired labels, and emoji-free existing chooser/filter strings.**

```css
/* app/assets/stylesheets/nosia/sources.css — unlayered, strictly Sources-scoped */
.n-source-layout { @apply grid min-w-0 grid-cols-1 items-start gap-5 lg:grid-cols-[11rem_minmax(0,1fr)]; }
.n-source-filters { @apply min-w-0 space-y-3; }
.n-source-filter-types, .n-source-filter-attention { @apply flex min-w-0 flex-wrap gap-2 lg:flex-col; }
.n-source-filter-attention > p { @apply w-full; }
.n-source-filter { @apply inline-flex min-h-11 min-w-0 items-center justify-between gap-4 rounded-md border border-neutral-500 bg-white px-3 py-2 text-sm text-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:bg-neutral-800 dark:text-neutral-100 dark:focus:outline-green-300; }
.n-source-filter > span:first-child { @apply inline-flex min-w-0 items-center gap-2; overflow-wrap: anywhere; }
.n-source-filter[aria-current="true"] { @apply bg-green-50 font-semibold text-green-900 dark:bg-green-950 dark:text-green-200; }
.n-source-workspace .n-count { @apply bg-transparent text-neutral-600 dark:text-neutral-300; }
.n-source-toolbar { @apply mb-4 flex min-w-0 flex-wrap items-end gap-3; }
.n-source-search { flex: 1 1 14rem; min-width: 0; }
.n-source-toolbar-field { flex: 1 1 9rem; min-width: 0; }
.n-source-workspace .n-label { @apply mb-1 block text-sm font-medium; }
.n-source-workspace .n-field, .n-source-workspace .n-select { @apply min-h-11 border-neutral-500 bg-white text-neutral-900 focus:outline-green-700 dark:bg-neutral-800 dark:text-neutral-100 dark:focus:outline-green-300; }
.n-source-workspace details[open] > summary { margin-bottom: 0; }
```

Import `sources.css` after `workspace.css`, **without** a layer, following the existing composer stylesheet's approach. Its selectors are explicitly scoped; later editor rules must outrank the unlayered Lexxy CSS. Do not put global element selectors in this file.

```css
@import "../stylesheets/nosia/sources.css";
```

Append these keys under the existing `nosia.sources_workspace` mapping in each paired catalog:

```yaml
# English additions
search_label: "Search sources"
counts_scope: "Account-wide counts"
status_label: "Status"
all_statuses: "All statuses"
sort_label: "Sort by"
```

```yaml
# French additions
search_label: "Rechercher des sources"
counts_scope: "Totaux du compte"
status_label: "État"
all_statuses: "Tous les états"
sort_label: "Trier par"
```

In `config/locales/en.nosia_sources.yml`, replace these existing leaf values without changing keys or plural branches:

```yaml
upload_documents: "Upload documents"
add_website: "Add website"
paste_text: "Paste text"
add_qna: "Add Q&A"
failed_filter: "Failed"
pending_filter: "Processing"
empty_failed: "Nothing failed — all good."
```

In `config/locales/fr.nosia_sources.yml` replace the same leaves:

```yaml
upload_documents: "Importer des documents"
add_website: "Ajouter un site web"
paste_text: "Coller du texte"
add_qna: "Ajouter une question-réponse"
failed_filter: "En échec"
pending_filter: "En cours de traitement"
empty_failed: "Aucun échec — tout va bien."
```

- [x] **Step 5: Run GREEN, preserve scope/pagination/stream regressions, and commit.**

```bash
rails_test tailwindcss:build
record_check /tmp/opencode/sources-workspace-task2-green.log rails_test test test/controllers/sources_workspace_filters_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/accounts/scoped_sources_test.rb test/controllers/sources_controller_test.rb test/internationalization/catalogs_test.rb
mise exec ruby@4.0.7 -- env RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app/helpers/sources_helper.rb test/controllers/sources_workspace_filters_test.rb test/controllers/accounts/scoped_sources_test.rb
git diff --check
git add app/helpers/sources_helper.rb app/views/sources/_source_filters.html.erb app/views/sources/_toolbar.html.erb app/views/sources/index.html.erb app/assets/stylesheets/nosia/sources.css app/assets/tailwind/application.css config/locales/en.nosia_sources_workspace.yml config/locales/fr.nosia_sources_workspace.yml config/locales/en.nosia_sources.yml config/locales/fr.nosia_sources.yml test/controllers/sources_workspace_filters_test.rb test/controllers/accounts/scoped_sources_test.rb
git commit -m "feat(sources): Preserve composed filters and stable live counts"
```

Expected: all targeted tests pass. Do not change pagination/stream tests merely because the toolbar became one form; those contracts remain unchanged.

## Task 3: Make rows, empty states, and upload feedback usable at every width

**Create:** `test/controllers/sources_workspace_rows_test.rb`, `test/system/sources_workspace_upload_test.rb`, `app/javascript/controllers/source_upload_controller.js`.
**Modify:** Sources row/status/rows/empty/drop-hint/add-menu/index/Turbo templates, `SourcesHelper`'s icon mapping, `SourcesWorkspaceHelper`, `Sourceable`'s row locals, Sources CSS, and paired Sources-workspace catalogs.

- [x] **Step 1: Write the row/background and real browse/retry tests.**

```ruby
# test/controllers/sources_workspace_rows_test.rb
require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceRowsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures
  include Turbo::Broadcastable::TestHelper

  setup { sign_in_overview }

  test "rows show type status metadata and independent actions with named account confirmation" do
    source = experience(:texts, :overview_second_text)
    source.update_columns(title: "<script>Source title</script>")
    get account_sources_path(@second)
    row = "##{ActionView::RecordIdentifier.dom_id(source, :source_row)}"
    assert_select "#{row} [data-source-type-label]", text: "Text"
    assert_select "#{row} [data-source-index-status='failed']", text: "Failed"
    assert_select "#{row} [data-source-chunks]"
    assert_select "#{row} time[datetime]"
    assert_select "#{row} [data-source-type-icon] svg[aria-hidden='true']"
    assert_select "#{row} a[data-source-edit][href='#{edit_account_sources_text_path(@second, source)}']"
    assert_select "#{row} form[action='#{account_sources_text_retry_path(@second, source)}'][data-turbo-confirm]", count: 0
    assert_select "#{row} a a, #{row} a button, [data-source-workspace] script", count: 0
    confirmation = css_select("#{row} a[data-turbo-method='delete']").first["data-turbo-confirm"]
    assert_includes confirmation, source.display_title
    assert_includes confirmation, @second.name
    assert_select "[data-source-upload] button[data-action='source-upload#browse']"
    assert_select "[data-source-upload] [data-dropzone-variant-value='dashboard']", count: 0
    assert_select "[data-source-upload][data-dropzone-variant-value='dashboard']"
  end

  test "standalone and live rows do not require request context or per-row account queries" do
    source = experience(:texts, :overview_second_text)
    source.association(:account).reset
    source.strict_loading!
    Current.reset
    html = ApplicationController.render(partial: "sources/source", locals: { row: SourceRow.new(source, chunks_count: 7) })
    fragment = Nokogiri::HTML.fragment(html)
    assert_select fragment, "[data-source-chunks][data-value='7']"
    assert_select fragment, "a[data-source-edit][href='#{edit_account_sources_text_path(@second, source)}']"
    assert_not source.association(:account).loaded?

    source = Text.find(source.id)
    streams = capture_turbo_stream_broadcasts([ @second, "sources", :en ]) { source.mark_indexing_failed! }
    row = streams.find { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(source, :source_row) }
    assert row
    assert_includes row.to_html, @second.name
    refute_includes row.to_html, "/accounts/#{@first.id}/"
  end

  test "permitted empty text keeps an accessible title without a new validation rule" do
    source = experience(:texts, :overview_second_text)
    source.update_columns(title: nil, data: "")
    get account_sources_path(@second)
    assert_select "[data-source-id='#{source.id}'] .n-source-title", text: "Untitled Text"
    confirmation = css_select("[data-source-id='#{source.id}'] a[data-turbo-method='delete']").first["data-turbo-confirm"]
    assert_includes confirmation, "Untitled Text"
    assert_empty source.reload.data
    assert source.valid?
  end

  test "empty searches are escaped and all type-empty states retain their add destination" do
    get account_sources_path(@second), params: { q: "<script>missing</script>" }
    assert_select ".sources-empty script", count: 0
    assert_select ".sources-empty [data-source-reset][href='#{account_sources_path(@second)}']"
    get account_sources_path(@empty), params: { status: "indexed" }
    assert_select ".sources-empty h3", text: I18n.t("nosia.sources_workspace.empty_filtered")
    assert_select ".sources-empty [data-source-reset][href='#{account_sources_path(@empty)}']"
    SourceRow::TYPES.each do |type|
      get account_sources_path(@empty), params: { type: type }
      path = public_send("new_account_sources_#{type}_path", @empty)
      assert_select ".sources-empty h3", text: I18n.t("nosia.sources.empty.#{type}")
      assert_select ".sources-empty a[href='#{path}']"
    end
  end
end
```

The first row test intentionally distinguishes the uploader root's variant attribute from a nested element; do not accidentally move the variant onto a button or input.

```ruby
# test/system/sources_workspace_upload_test.rb
require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceUploadTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    select "EN", from: "language_preference_locale"
    visit account_sources_path(@second)
    assert_selector "[data-source-upload]"
  end

  test "browse activates the existing input and a real upload stays in the URL account" do
    page.execute_script(<<~JS)
      const input=document.getElementById('source-upload-files');
      window.sourceBrowseCalls=0; window.sourceOriginalClick=input.click;
      input.click=()=>{ window.sourceBrowseCalls+=1; };
    JS
    click_on "Choose files"
    assert_equal 1, page.evaluate_script("window.sourceBrowseCalls")
    page.execute_script("const input=document.getElementById('source-upload-files'); input.click=window.sourceOriginalClick;")
    previous = @second.documents.count
    clear_enqueued_jobs
    find("#source-upload-files", visible: :all).set(file_fixture("account_source.txt"))
    assert_selector "[data-upload-status='success'] [data-source-upload-label]", text: "Uploaded. Check source status for indexing."
    assert_equal previous + 1, @second.documents.count
    assert_not @first.documents.exists?(title: "account_source.txt")
    assert_enqueued_jobs 1, only: AddDocumentJob
  end

  test "retry after a committed response is lost reuses its upload intent and index job" do
    path = account_sources_documents_path(@second)
    page.execute_script(<<~JS, path)
      const target=arguments[0],open=XMLHttpRequest.prototype.open,send=XMLHttpRequest.prototype.send;
      window.sourceUploadedIds=[];
      XMLHttpRequest.prototype.open=function(method,url,...args){this.sourcePath=new URL(url,location.href).pathname;return open.call(this,method,url,...args);};
      XMLHttpRequest.prototype.send=function(body){
        if(this.sourcePath===target){
          const loaded=this.onload;
          this.onload=event=>{
            if(this.status>=200&&this.status<300){
              window.sourceUploadedIds.push(JSON.parse(this.responseText).id);
              if(window.sourceUploadedIds.length===1)return this.onerror(new ProgressEvent('error'));
            }
            loaded.call(this,event);
          };
        }
        return send.call(this,body);
      };
    JS
    previous = @second.documents.count
    clear_enqueued_jobs
    find("#source-upload-files", visible: :all).set(file_fixture("account_source.txt"))
    assert_selector "[data-upload-status='error']"
    within("[data-dropzone-target='list']") { click_on "Retry" }
    assert_selector "[data-upload-status='success'] [data-source-upload-label]", text: "Uploaded. Check source status for indexing."
    ids = page.evaluate_script("window.sourceUploadedIds")
    assert_equal 2, ids.length
    assert_equal 1, ids.uniq.length
    assert_equal previous + 1, @second.documents.count
    assert_enqueued_jobs 1, only: AddDocumentJob
  end
end
```

- [x] **Step 2: Observe RED in both request and browser tests.**

```bash
record_check /tmp/opencode/sources-workspace-task3-request-red.log rails_test test test/controllers/sources_workspace_rows_test.rb
record_check /tmp/opencode/sources-workspace-task3-browser-red.log browser_test test/system/sources_workspace_upload_test.rb
```

Expected: missing semantic row metadata/edit control, missing browse/upload marker or labels. Existing real upload behavior must not be replaced with fake responses; the second test deliberately drops only the first *successful response* after the real server commit.

- [x] **Step 3: Add safe row metadata and actions that also work in background renders.** Replace the existing icon constant/method in `SourcesHelper` with:

```ruby
SOURCE_ICONS = { "document" => "files.svg", "text" => "file-lines.svg", "qna" => "question-circle.svg", "website" => "window.svg" }.freeze

# @param key [String] Existing source type; unknown keys use the document icon
# @return [ActiveSupport::SafeBuffer] Decorative SVG from the fixed local asset map
def source_type_icon(key)
  inline_svg "svg/#{SOURCE_ICONS.fetch(key, 'files.svg')}", aria_hidden: true, class: "n-source-type-icon"
end
```

Add these two public methods to `SourcesWorkspaceHelper`:

```ruby
# @param record [Document, Text, Qna, Website] Existing source; content may be empty
# @return [String] Presentation fallback only, without mutating stored content
def source_workspace_title(record)
  record.display_title.presence || t("nosia.sources_workspace.untitled_source", type: record.source_type_label)
end

# @param record [Document, Text, Qna, Website] Source being deleted
# @param account_name [String, nil] Supplied by request/broadcast, never lazily loaded
# @return [String] Plain confirmation text; standalone rendering falls back to account ID
def source_delete_confirmation(record, account_name: nil)
  t("nosia.sources_workspace.delete_confirm", title: source_workspace_title(record), account: account_name.presence || record.account_id.to_s)
end
```

```erb
<%# app/views/sources/_source.html.erb %>
<%# locals: (row:, account_name: nil) %>
<% record = row.to_model %>
<div id="<%= dom_id(record, :source_row) %>" class="n-source-row" data-source-id="<%= row.id %>" data-source-type="<%= row.source_type_key %>">
  <div class="n-source-identity">
    <span data-source-type-icon><%= source_type_icon(row.source_type_key) %></span>
    <div class="min-w-0">
      <%= link_to source_workspace_title(record), source_show_path(record), class: "n-source-title n-main-focus" %>
      <p class="n-source-subtitle"><%= row.source_subtitle %></p>
      <% if record.failed? %><p class="n-source-subtitle"><%= record.failure_reason.presence || t("nosia.sources_workspace.failed_help") %></p><% end %>
    </div>
  </div>
  <div class="n-source-metadata">
    <span data-source-type-label><%= row.source_type_label %></span>
    <%= render "sources/status", row: row %>
    <% value = record.pending? && row.chunks_count.zero? ? "—" : number_with_delimiter(row.chunks_count) %>
    <span data-source-chunks data-value="<%= row.chunks_count %>"><%= t("nosia.sources_workspace.chunk_value", value: value) %></span>
    <time datetime="<%= row.created_at.iso8601 %>"><%= t("nosia.sources_workspace.added", time: t("nosia.time.ago", duration: time_ago_in_words(row.created_at))) %></time>
  </div>
  <div class="n-source-row-actions">
    <%= link_to t("nosia.actions.edit"), source_edit_path(record), class: "n-workspace-button", data: { source_edit: true } %>
    <% if record.failed? %>
      <%= button_to source_retry_path(record), method: :post, aria: { label: t("nosia.actions.retry") }, class: "n-workspace-button n-main-focus-tertiary" do %>
        <span aria-hidden="true"><svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M20 7v5h-5M4 17v-5h5M6 7a7 7 0 0 1 12-1l2 3M4 15l2 3a7 7 0 0 0 12-1"/></svg></span>
        <%= t("nosia.actions.retry") %>
      <% end %>
    <% end %>
    <%= link_to source_show_path(record), aria: { label: t("nosia.actions.delete") }, class: "n-workspace-button n-workspace-danger n-main-focus-danger", data: { turbo_method: :delete, turbo_confirm: source_delete_confirmation(record, account_name: account_name) } do %>
      <%= inline_svg "svg/trash-bin.svg", aria_hidden: true, class: "h-4 w-4" %><%= t("nosia.actions.delete") %>
    <% end %>
  </div>
</div>
```

```erb
<%# app/views/sources/_status.html.erb %>
<%# locals: (row:) %>
<% classes, label = source_status_display(row.to_model) %>
<span class="n-source-status <%= classes %>" data-source-index-status="<%= row.index_status %>">
  <span aria-hidden="true" class="h-1.5 w-1.5 rounded-full bg-current"></span><%= label %>
</span>
```

In both `_rows.html.erb` and `index.turbo_stream.erb`, replace the row render with this exact line. Keep all surrounding empty/load-more/Turbo actions intact:

```erb
<%= render "sources/source", row: row, account_name: source_account.name %>
```

In **both** row-local hashes in `Sourceable#broadcast_source_created` and `#broadcast_source_status_change`, replace the existing `locals:` line with:

```ruby
locals: { row: SourceRow.new(self, chunks_count: chunks.count), account_name: account.name }
```

This passes view metadata through the existing broadcast. It does not change stream names, targets, lifecycle callbacks, query strategy, or number of broadcasts. The row never calls `record.account`; standalone callers without the optional local still render safely.

The new retry form omits the old `data-turbo-confirm="false"` attribute: that is
a literal prompt string, not Turbo's boolean opt-out. Retry uses its existing
authorized POST directly; only Delete requires the named destructive confirmation.

- [x] **Step 4: Reuse the existing uploader, adding only browse and truthful per-file labels.**

```javascript
// app/javascript/controllers/source_upload_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { labels: Object }

  browse() {
    if (this.element.isConnected && !this.element.closest("[inert]")) this.inputTarget.click()
  }

  labelUploads() {
    this.element.querySelectorAll("[data-upload-status]").forEach(entry => {
      let label = entry.querySelector("[data-source-upload-label]")
      if (!label) {
        label = document.createElement("span")
        label.dataset.sourceUploadLabel = ""
        entry.append(label)
      }
      label.textContent = this.labelsValue[entry.dataset.uploadStatus] || ""
    })
  }
}
```

Stimulus auto-registers this controller through the existing importmap loader; do not edit `controllers/index.js` or add packages.

In the index's existing uploader root change `data-controller="dropzone"` to the following attributes, leaving its URL/account/MIME/size/click-to-browse values intact:

```erb
data-controller="dropzone source-upload" data-source-upload
data-dropzone-variant-value="dashboard"
data-source-upload-labels-value="<%= t('nosia.sources_workspace.upload_labels').to_json %>"
data-action="dropzone:state->source-upload#labelUploads"
```

Replace the existing file input with:

```erb
<input id="source-upload-files" type="file" multiple class="hidden"
       data-dropzone-target="input" data-source-upload-target="input"
       accept="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/plain,image/png,image/jpeg">
```

Replace the list container's old border class with `class="n-source-dropzone"`. Immediately above it add the filtered-result snapshot (not a fabricated live result count):

```erb
<p class="n-workspace-help" data-source-results data-total="<%= @total %>"><%= t("nosia.sources_workspace.results", total: number_with_delimiter(@total)) %></p>
```

After the list container, replace the old upload `<ul>` with:

```erb
<div class="n-source-upload-strip">
  <div><p class="font-medium"><%= t("nosia.sources_workspace.upload_title") %></p><p class="n-workspace-help"><%= t("nosia.sources_workspace.upload_help") %></p></div>
  <button type="button" class="n-workspace-button" data-action="source-upload#browse"><%= t("nosia.sources_workspace.choose_files") %></button>
</div>
<ul class="n-source-upload-list hidden !list-none" data-dropzone-target="list" aria-live="polite" aria-relevant="additions text"></ul>
```

The existing `dashboard` variant exposes its already-implemented retry/remove controls. The new controller reads the existing `data-upload-status` truth and labels it; it owns no upload state, requests, retry IDs, or server writes. Do not edit `dropzone_controller.js`.

- [x] **Step 5: Replace the chooser, drop hint, and empty-state markup.**

```erb
<%# app/views/sources/_add_menu.html.erb %>
<details class="n-source-add-menu">
  <summary class="n-workspace-button n-workspace-primary"><%= t("nosia.sources.add") %></summary>
  <ul class="n-source-add-options !list-none">
    <% { document: "upload_documents", website: "add_website", text: "paste_text", qna: "add_qna" }.each do |type, key| %>
      <li><%= link_to source_new_path(type), class: "n-source-add-option" do %>
        <%= source_type_icon(type.to_s) %><%= t("nosia.sources.#{key}") %>
      <% end %></li>
    <% end %>
  </ul>
</details>
```

```erb
<%# app/views/sources/_drop_hint.html.erb %>
<p class="n-source-drop-hint"><%= inline_svg "svg/download.svg", aria_hidden: true, class: "h-4 w-4" %><%= t("nosia.sources.drop_hint") %></p>
```

```erb
<%# app/views/sources/_empty.html.erb %>
<%# locals: (type:, status:, query:) %>
<div class="sources-empty n-source-empty">
  <%= render "sources/drop_hint" %>
  <% if query.present? %>
    <h3 class="n-workspace-section-title"><%= t("nosia.sources.empty_query", query: query) %></h3>
    <%= link_to t("nosia.actions.reset"), source_index_path, class: "n-workspace-link", data: { source_reset: true } %>
  <% elsif status == "failed" || status == "pending" %>
    <h3 class="n-workspace-section-title"><%= t("nosia.sources.empty_#{status}") %></h3>
    <%= link_to t("nosia.actions.reset"), source_index_path, class: "n-workspace-link", data: { source_reset: true } %>
  <% elsif status != "all" %>
    <h3 class="n-workspace-section-title"><%= t("nosia.sources_workspace.empty_filtered") %></h3>
    <%= link_to t("nosia.actions.reset"), source_index_path, class: "n-workspace-link", data: { source_reset: true } %>
  <% elsif type == "all" %>
    <h3 class="n-workspace-section-title"><%= t("nosia.sources.first") %></h3>
    <p class="n-workspace-help"><%= t("nosia.sources.first_help") %></p>
    <%= link_to t("nosia.sources.add_type.document"), source_new_path(:document), class: "n-workspace-button" %>
  <% else %>
    <h3 class="n-workspace-section-title"><%= t("nosia.sources.empty.#{type}") %></h3>
    <%= link_to t("nosia.sources.add_type.#{type}"), source_new_path(type), class: "n-workspace-button n-workspace-primary" %>
  <% end %>
</div>
```

Keep the existing main stylesheet's `#sources_list:has([data-source-id]) .sources-empty` hiding rule. Do not give `.n-source-empty` an unlayered `display` value that would defeat it.

- [x] **Step 6: Append Sources-only styles and paired copy.**

```css
/* Append to app/assets/stylesheets/nosia/sources.css */
.n-source-type-icon { @apply h-4 w-4 shrink-0; }
.n-source-row { @apply grid min-w-0 grid-cols-1 items-center gap-3 border-b border-neutral-300 bg-white p-4 last:border-0 dark:border-neutral-600 dark:bg-neutral-800 xl:grid-cols-[minmax(0,1fr)_minmax(10rem,0.8fr)_auto]; }
.n-source-identity { @apply flex min-w-0 items-start gap-3; }
.n-source-title { overflow-wrap: anywhere; @apply block rounded-sm font-semibold text-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:text-neutral-100 dark:focus:outline-green-300; }
.n-source-subtitle { overflow-wrap: anywhere; @apply mt-1 text-sm leading-relaxed text-neutral-600 dark:text-neutral-300; }
.n-source-metadata { @apply flex min-w-0 flex-wrap items-center gap-x-3 gap-y-2 text-sm text-neutral-600 dark:text-neutral-300; }
.n-source-row-actions { @apply flex min-w-0 flex-wrap items-center gap-2; }
.n-source-row-actions form { margin: 0; }
.n-source-row-actions .n-workspace-button { @apply focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:focus:outline-green-300; }
.n-source-row-actions .n-workspace-danger { @apply focus:outline-red-700 dark:focus:outline-red-300; }
.n-source-status { @apply inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs font-medium; }
.n-source-dropzone { @apply relative overflow-visible rounded-xl border border-neutral-500 bg-white dark:bg-neutral-800; }
.n-source-dropzone[data-active="true"] { @apply outline-2 outline-offset-2 outline-green-700 dark:outline-green-300; }
.n-source-drop-hint { @apply flex flex-wrap items-center justify-center gap-2 border-b border-dashed border-neutral-400 p-3 text-sm text-neutral-600 dark:border-neutral-500 dark:text-neutral-300; }
.n-source-empty { @apply space-y-3 p-5 text-center; }
.n-source-upload-strip { @apply mt-4 flex min-w-0 flex-wrap items-center justify-between gap-3 rounded-lg border border-dashed border-neutral-500 p-4 text-sm; }
.n-source-upload-list { @apply mt-3 space-y-2; }
.n-source-upload-list > li { flex-wrap: wrap; }
.n-source-upload-list .file-name { white-space: normal; overflow: visible; overflow-wrap: anywhere; min-width: 0; }
.n-source-upload-list [data-source-upload-label] { flex-basis: 100%; @apply text-sm text-neutral-700 dark:text-neutral-200; }
.n-source-upload-list button { @apply min-h-11 min-w-11 rounded-md px-2 text-sm text-neutral-800 focus:outline-2 focus:outline-green-700 dark:text-neutral-100 dark:focus:outline-green-300; }
.n-source-add-menu { @apply relative; }
.n-source-add-menu summary { @apply list-none cursor-pointer; }
.n-source-add-options { @apply absolute right-0 top-full z-20 mt-2 min-w-56 max-w-[calc(100vw-3rem)] rounded-lg border border-neutral-500 bg-white p-1 shadow-sm dark:bg-neutral-800; }
.n-source-add-option { @apply flex min-h-11 min-w-0 items-center gap-2 rounded-md px-3 py-2 text-sm hover:bg-green-50 focus:outline-2 focus:outline-green-700 dark:hover:bg-green-950 dark:focus:outline-green-300; overflow-wrap: anywhere; }
@media (prefers-reduced-motion: reduce) { .n-source-workspace .animate-pulse { animation: none; } }
```

Append under `nosia.sources_workspace`:

```yaml
# English additions
untitled_source: "Untitled %{type}"
delete_confirm: 'Delete “%{title}” from account “%{account}”? This cannot be undone.'
failed_help: "Processing failed. Retry or review the source."
empty_filtered: "No sources match these filters."
chunk_value: "Chunks: %{value}"
added: "Added %{time}"
results: "Matches on this load: %{total}"
upload_title: "Drop documents onto the list, or choose files"
upload_help: "Uploads use this account. Check each source’s status for indexing; reload to reapply filters and sorting."
choose_files: "Choose files"
upload_labels:
  pending: "Waiting to upload"
  uploading: "Uploading"
  success: "Uploaded. Check source status for indexing."
  error: "Not uploaded"
```

```yaml
# French additions
untitled_source: "%{type} sans titre"
delete_confirm: 'Supprimer « %{title} » du compte « %{account} » ? Cette action est irréversible.'
failed_help: "Le traitement a échoué. Réessayez ou consultez la source."
empty_filtered: "Aucune source ne correspond à ces filtres."
chunk_value: "Extraits : %{value}"
added: "Ajoutée %{time}"
results: "Résultats à ce chargement : %{total}"
upload_title: "Déposez des documents sur la liste ou choisissez des fichiers"
upload_help: "Les fichiers sont enregistrés dans ce compte. Consultez l’état des sources pour l’indexation ; rechargez pour réappliquer les filtres et le tri."
choose_files: "Choisir des fichiers"
upload_labels:
  pending: "En attente d’importation"
  uploading: "Importation en cours"
  success: "Fichier importé. Consultez l’état de la source pour l’indexation."
  error: "Non importé"
```

- [x] **Step 7: Run GREEN, existing broadcasts/uploads, and commit.**

```bash
rails_test tailwindcss:build
record_check /tmp/opencode/sources-workspace-task3-request-green.log rails_test test test/controllers/sources_workspace_rows_test.rb test/controllers/sources_workspace_filters_test.rb test/controllers/accounts/scoped_sources_test.rb test/models/sourceable_test.rb test/models/sourceable_broadcast_test.rb test/models/account_source_broadcast_test.rb test/models/document_source_registration_test.rb test/integration/localized_pages_test.rb test/integration/localized_broadcasts_test.rb test/internationalization/catalogs_test.rb
record_check /tmp/opencode/sources-workspace-task3-browser-green.log browser_test test/system/sources_workspace_upload_test.rb
mise exec ruby@4.0.7 -- env RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app/helpers/sources_helper.rb app/helpers/sources_workspace_helper.rb app/models/concerns/sourceable.rb test/controllers/sources_workspace_rows_test.rb test/system/sources_workspace_upload_test.rb
git diff --check
git add app/helpers/sources_helper.rb app/helpers/sources_workspace_helper.rb app/models/concerns/sourceable.rb app/javascript/controllers/source_upload_controller.js app/views/sources/_source.html.erb app/views/sources/_status.html.erb app/views/sources/_rows.html.erb app/views/sources/_empty.html.erb app/views/sources/_drop_hint.html.erb app/views/sources/_add_menu.html.erb app/views/sources/index.html.erb app/views/sources/index.turbo_stream.erb app/assets/stylesheets/nosia/sources.css config/locales/en.nosia_sources_workspace.yml config/locales/fr.nosia_sources_workspace.yml test/controllers/sources_workspace_rows_test.rb test/system/sources_workspace_upload_test.rb
git commit -m "feat(sources): Improve rows and truthful upload feedback"
```

Expected: all targeted checks pass, including unchanged `AccountSourceBroadcastTest`'s accessible-name/icon assertions and strict-loading standalone render. No ingestion job is performed by browser verification.

## Task 4: Unify all new/edit forms without changing fields or filing rules

**Create:** `test/controllers/sources_workspace_forms_test.rb`, `app/helpers/source_forms_helper.rb`, `app/javascript/controllers/source_form_controller.js`, `app/views/sources/_form_page.html.erb`, `_form_help.html.erb`, `_form_errors.html.erb`, `_field_error.html.erb`, `_form_actions.html.erb`.
**Modify:** four source `_form` partials, `_account_field`, eight new/edit templates, Sources CSS/catalogs, and only the two obsolete new/edit Back selectors in the existing scoped operations test.

- [x] **Step 1: Add request tests for fixed edit identity, preserved failed filing, connected errors, and safe summaries.**

```ruby
# test/controllers/sources_workspace_forms_test.rb
require "test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceFormsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "all scoped forms share the layout and keep existing nested fields and fixed account" do
    SourceRow::TYPES.each do |type|
      source = experience(type.pluralize, "overview_second_#{type}")
      paths = [ public_send("new_account_sources_#{type}_path", @second),
        public_send("edit_account_sources_#{type}_path", @second, source) ]
      paths.each do |path|
        assert_no_enqueued_jobs { get path }
        assert_response :success
        assert_select "[data-source-workspace] h1", count: 1
        assert_select ".n-source-form-layout form[data-controller='source-form']", count: 1
        assert_select "form input[type='hidden'][name='#{type}[account_id]'][value='#{@second.id}']"
        assert_select "form select[name='#{type}[account_id]']", count: 0
        assert_select "form input[type='submit'][data-turbo-submits-with]"
        assert_select "[data-source-form-help]"
        assert_select "#accordion-right-actions, #drawer-right", count: 0
      end
    end
  end

  test "legacy editing is read-only for account identity and document replacement is explicit" do
    sign_in_overview(@member)
    SourceRow::TYPES.each do |type|
      source = experience(type.pluralize, "overview_second_#{type}")
      get public_send("edit_sources_#{type}_path", source)
      assert_response :success
      assert_select "form select[name='#{type}[account_id]']", count: 0
      assert_select "form [data-source-fixed-account]", text: @second.name
      if type == "document"
        assert_select "[data-source-current-file]", text: /#{Regexp.escape(source.file.filename.to_s)}/
        assert_select "input[type='file'][name='document[file]']"
      end
    end
  end

  test "failed legacy document creation retains its chosen filing account and connected error" do
    assert_no_enqueued_jobs do
      post sources_documents_path, params: { document: { title: "Keep this title", account_id: @second.id } }
    end
    assert_response :unprocessable_entity
    assert_select "[data-source-form-target='errors'][tabindex='-1'][role='alert'] a[href='#document_file']", text: "File can't be blank"
    assert_select "input[name='document[title]'][value='Keep this title']"
    assert_select "select[name='document[account_id]'] option[value='#{@second.id}'][selected]"
    assert_select "input#document_file[aria-invalid='true'][aria-describedby='document_file_help document_file_error']"
    assert_select "#document_file_error", text: "File can't be blank"
    assert_equal @first, @user.first_account
  end

  test "website 422 errors retain editor content without changing existing validation" do
    post account_sources_websites_path(@second), params: { website: { url: "", data: "Keep **this** content" } }
    assert_response :unprocessable_entity
    assert_select "[role='alert'] a[href='#website_url']", text: "Url can't be blank"
    assert_select "input#website_url[aria-invalid='true']"
    assert_select "lexxy-editor[name='website[data]'][attachments='false']" do |editors|
      assert_equal Commonmarker.to_html("Keep **this** content"), editors.first["value"]
    end
  end

  test "source-specific error summary escapes base messages and omits an empty summary" do
    source = experience(:texts, :overview_second_text)
    source.errors.add(:base, "<script>unsafe</script>")
    form = ActionView::Helpers::FormBuilder.new(:text, source, controller.view_context, {})
    html = ApplicationController.render(partial: "sources/form_errors", locals: { form: form, fields: [ :data ] })
    fragment = Nokogiri::HTML.fragment(html)
    assert_select fragment, "[role='alert'] li", text: "<script>unsafe</script>"
    assert_select fragment, "script, li a", count: 0
    source.errors.clear
    assert_empty ApplicationController.render(partial: "sources/form_errors", locals: { form: form, fields: [ :data ] }).strip
  end
end
```

In `Accounts::ScopedSourceOperationsTest`, within `"new edit and show links retain the route account"`, change only the Back assertions immediately after the **new** and **edit** GETs. The show assertions remain unchanged until Task 5:

```ruby
get public_send("new_account_sources_#{type}_path", @second)
assert_response :success
assert_select "a[data-workspace-back][href='#{index_path}']", text: I18n.t("nosia.actions.back")
assert_select "form a[href='#{account_sources_path(@second)}']", text: I18n.t("nosia.actions.cancel")

get edit_path
assert_response :success
assert_select "a[data-workspace-back][href='#{path}']", text: I18n.t("nosia.actions.back")
assert_select "form a[href='#{path}']", text: I18n.t("nosia.actions.cancel")
```

This replaces sr-only-label assumptions with equally strict visible-label/path assertions; do not remove or weaken account, format, content, or write/job assertions.

- [x] **Step 2: Run RED before the form implementation.**

```bash
record_check /tmp/opencode/sources-workspace-task4-red.log rails_test test test/controllers/sources_workspace_forms_test.rb test/controllers/accounts/scoped_source_operations_test.rb
```

Expected: missing shared form markup/partial, editable legacy edit account selector, missing linked errors, and lost legacy selection. Do not invent new model validations to make tests fail.

- [x] **Step 3: Add the field options, error partials, and error-focus enhancement.**

```ruby
# app/helpers/source_forms_helper.rb
module SourceFormsHelper
  # @param form [ActionView::Helpers::FormBuilder] Existing source builder
  # @param attribute [Symbol] Existing field
  # @param help [String, nil] Optional help element ID
  # @param options [Hash] Ordinary field options such as class or attachments
  # @return [Hash] Stable field ID and connected validation attributes
  def source_field_options(form, attribute, help: nil, **options)
    invalid = form.object.errors.include?(attribute)
    described_by = [ help, invalid ? form.field_id(attribute, :error) : nil ].compact
    options.merge(id: form.field_id(attribute), aria: { invalid: invalid, describedby: described_by.presence&.join(" ") })
  end
end
```

```javascript
// app/javascript/controllers/source_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["errors"]

  connect() {
    if (this.hasErrorsTarget) this.errorsTarget.focus()
  }
}
```

```erb
<%# app/views/sources/_form_errors.html.erb %>
<%# locals: (form:, fields:) %>
<% if form.object.errors.any? %>
  <div id="<%= form.field_id(:errors) %>" class="n-source-errors" role="alert" tabindex="-1"
       aria-labelledby="<%= form.field_id(:errors, :title) %>" data-source-form-target="errors">
    <h2 id="<%= form.field_id(:errors, :title) %>" class="font-semibold"><%= t("nosia.sources_workspace.check_form") %></h2>
    <ul class="!list-none">
      <% form.object.errors.each do |error| %>
        <li><% if fields.include?(error.attribute) %>
          <%= link_to error.full_message, "##{form.field_id(error.attribute)}", class: "n-source-error-link" %>
        <% else %><%= error.full_message %><% end %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

```erb
<%# app/views/sources/_field_error.html.erb %>
<%# locals: (form:, attribute:) %>
<% if form.object.errors.include?(attribute) %>
  <p id="<%= form.field_id(attribute, :error) %>" class="n-source-field-error"><%= form.object.errors.full_messages_for(attribute).to_sentence %></p>
<% end %>
```

```erb
<%# app/views/sources/_form_actions.html.erb %>
<%# locals: (form:) %>
<div class="n-source-form-actions">
  <%= form.submit t("nosia.actions.save"), class: "n-workspace-button n-workspace-primary", data: { turbo_submits_with: t("nosia.sources_workspace.saving") } %>
  <%= link_to t("nosia.actions.cancel"), form.object.persisted? ? source_show_path(form.object) : source_index_path, class: "n-workspace-link" %>
</div>
```

Replace `_account_field.html.erb` completely:

```erb
<%# locals: (form:) %>
<div class="n-source-field">
  <% if @scoped_source_account || form.object.persisted? %>
    <% account = @scoped_source_account || form.object.account %>
    <p class="n-label"><%= t("nosia.sources.account_label") %></p>
    <%= form.hidden_field :account_id, value: account.id %>
    <p class="n-source-fixed-account" data-source-fixed-account><%= account.name %></p>
  <% else %>
    <%= form.label :account_id, t("nosia.sources.account_label"), class: "n-label" %>
    <%= form.collection_select :account_id, Current.user.accounts, :id, :name,
          { prompt: true, selected: form.object.account_id.presence || source_account&.id }, { class: "n-select" } %>
  <% end %>
</div>
```

No new account assignment is permitted. The hidden value retains the existing scoped contract and is ignored by unchanged legacy update strong parameters; never add `:account_id` to those update parameter lists.

- [x] **Step 4: Add the shared form page/help and replace all eight wrappers.**

```erb
<%# app/views/sources/_form_page.html.erb %>
<%# locals: (record:) %>
<% content_for :account_tool_title, t("nosia.account_experience.sources") if @scoped_source_account %>
<% type = record.model_name.element %>
<% title = record.persisted? ? t("nosia.sources.#{type.pluralize}.edit_action") : t("nosia.sources.add_type.#{type}") %>
<% account = @scoped_source_account || (record.account if record.persisted?) %>
<div class="n-workspace n-source-workspace" data-source-workspace>
  <%= render "workspaces/header", title: title, description: t("nosia.sources_workspace.form_description"),
        scope_label: source_workspace_scope(account), trail: source_workspace_trail(title: title),
        back_path: record.persisted? ? source_show_path(record) : source_index_path(type: type),
        show_new_chat: !@scoped_source_account %>
  <div class="n-source-form-layout">
    <section class="n-workspace-panel">
      <%= render partial: "sources/#{type.pluralize}/form", locals: { type.to_sym => record } %>
    </section>
    <%= render "sources/form_help", record: record %>
  </div>
</div>
```

```erb
<%# app/views/sources/_form_help.html.erb %>
<%# locals: (record:) %>
<aside class="n-workspace-panel" data-source-form-help aria-labelledby="source-form-help-title">
  <h2 id="source-form-help-title" class="n-workspace-section-title"><%= t("nosia.sources_workspace.form_help_title") %></h2>
  <p class="n-workspace-help"><%= t("nosia.sources_workspace.form_help.#{record.model_name.element}") %></p>
  <p class="n-workspace-help"><%= t("nosia.sources_workspace.processing_help") %></p>
</aside>
```

Use each following complete line in the named file, replacing its old wrapper. The typed form partials are defined in Step 5.

```erb
<%# app/views/sources/documents/new.html.erb %>
<%= render "sources/form_page", record: @document %>
```

```erb
<%# app/views/sources/documents/edit.html.erb %>
<%= render "sources/form_page", record: @document %>
```

```erb
<%# app/views/sources/texts/new.html.erb %>
<%= render "sources/form_page", record: @text %>
```

```erb
<%# app/views/sources/texts/edit.html.erb %>
<%= render "sources/form_page", record: @text %>
```

```erb
<%# app/views/sources/qnas/new.html.erb %>
<%= render "sources/form_page", record: @qna %>
```

```erb
<%# app/views/sources/qnas/edit.html.erb %>
<%= render "sources/form_page", record: @qna %>
```

```erb
<%# app/views/sources/websites/new.html.erb %>
<%= render "sources/form_page", record: @website %>
```

```erb
<%# app/views/sources/websites/edit.html.erb %>
<%= render "sources/form_page", record: @website %>
```

- [x] **Step 5: Replace the four typed forms, retaining every current field and conversion.** Do not add a title field to Text, new required attributes to Text/Q&A, a crawl configuration, or a file MIME restriction to the document form.

```erb
<%# app/views/sources/documents/_form.html.erb %>
<%= form_with model: source_form_model(document), class: "n-source-form", data: { controller: "source-form" } do |form| %>
  <%= render "sources/form_errors", form: form, fields: [ :title, :file ] %>
  <div class="n-source-field">
    <%= form.label :title, t("nosia.sources.title_label"), class: "n-label" %>
    <%= form.text_field :title, **source_field_options(form, :title, help: form.field_id(:title, :help), class: "n-field") %>
    <p id="<%= form.field_id(:title, :help) %>" class="n-workspace-help"><%= t("nosia.sources_workspace.optional_title") %></p>
    <%= render "sources/field_error", form: form, attribute: :title %>
  </div>
  <div class="n-source-field">
    <% if document.persisted? && document.file.attached? %>
      <p class="n-workspace-help" data-source-current-file><%= t("nosia.sources_workspace.current_file", name: document.file.filename.to_s) %></p>
    <% end %>
    <%= form.label :file, document.persisted? ? t("nosia.sources_workspace.replacement_file") : t("nosia.sources.file_label"), class: "n-label" %>
    <%= form.file_field :file, **source_field_options(form, :file, help: form.field_id(:file, :help), class: "n-field") %>
    <p id="<%= form.field_id(:file, :help) %>" class="n-workspace-help"><%= t(document.persisted? ? "nosia.sources_workspace.keep_file" : "nosia.sources_workspace.select_file") %></p>
    <% if document.errors.any? %><p class="n-workspace-help"><%= t("nosia.sources_workspace.reselect_file") %></p><% end %>
    <%= render "sources/field_error", form: form, attribute: :file %>
  </div>
  <%= render "sources/account_field", form: form %>
  <%= render "sources/form_actions", form: form %>
<% end %>
```

```erb
<%# app/views/sources/texts/_form.html.erb %>
<%= form_with model: source_form_model(text), class: "n-source-form", data: { controller: "source-form" } do |form| %>
  <%= render "sources/form_errors", form: form, fields: [ :data ] %>
  <div class="n-source-field">
    <%= form.label :data, t("nosia.sources.text_label"), class: "n-label" %>
    <%= form.lexxy_rich_text_area :data, **source_field_options(form, :data,
          value: Commonmarker.to_html(text.data.to_s.encode("UTF-8")), class: "n-textarea n-source-editor", attachments: "false") %>
    <%= render "sources/field_error", form: form, attribute: :data %>
  </div>
  <%= render "sources/account_field", form: form %>
  <%= render "sources/form_actions", form: form %>
<% end %>
```

```erb
<%# app/views/sources/qnas/_form.html.erb %>
<%= form_with model: source_form_model(qna), class: "n-source-form", data: { controller: "source-form" } do |form| %>
  <%= render "sources/form_errors", form: form, fields: [ :question, :answer ] %>
  <div class="n-source-field">
    <%= form.label :question, t("nosia.sources.question_label"), class: "n-label" %>
    <%= form.text_field :question, **source_field_options(form, :question, class: "n-field") %>
    <%= render "sources/field_error", form: form, attribute: :question %>
  </div>
  <div class="n-source-field">
    <%= form.label :answer, t("nosia.sources.answer_label"), class: "n-label" %>
    <%= form.lexxy_rich_text_area :answer, **source_field_options(form, :answer,
          value: Commonmarker.to_html(qna.answer.to_s.encode("UTF-8")), class: "n-textarea n-source-editor", attachments: "false") %>
    <%= render "sources/field_error", form: form, attribute: :answer %>
  </div>
  <%= render "sources/account_field", form: form %>
  <%= render "sources/form_actions", form: form %>
<% end %>
```

```erb
<%# app/views/sources/websites/_form.html.erb %>
<%= form_with model: source_form_model(website), class: "n-source-form", data: { controller: "source-form" } do |form| %>
  <%= render "sources/form_errors", form: form, fields: [ :url, :data ] %>
  <div class="n-source-field">
    <%= form.label :url, t("nosia.sources.url_label"), class: "n-label" %>
    <%= form.url_field :url, **source_field_options(form, :url, class: "n-field") %>
    <%= render "sources/field_error", form: form, attribute: :url %>
  </div>
  <div class="n-source-field">
    <%= form.label :data, t("nosia.sources.data_label"), class: "n-label" %>
    <%# Preserve body-only website editing: to_html strips crawl frontmatter.
        Selecting a different rendering/conversion here would change saved content. %>
    <%= form.lexxy_rich_text_area :data, **source_field_options(form, :data,
          value: website.to_html, class: "n-textarea n-source-editor", attachments: "false") %>
    <%= render "sources/field_error", form: form, attribute: :data %>
  </div>
  <%= render "sources/account_field", form: form %>
  <%= render "sources/form_actions", form: form %>
<% end %>
```

- [x] **Step 6: Add bounded form/editor styling and paired help.** Append to `app/assets/stylesheets/nosia/sources.css`:

```css
.n-source-form-layout { @apply grid min-w-0 grid-cols-1 items-start gap-5 xl:grid-cols-[minmax(0,48rem)_minmax(14rem,1fr)]; }
.n-source-form { @apply min-w-0 space-y-5; }
.n-source-field { @apply min-w-0 space-y-2; }
.n-source-field .n-field, .n-source-field .n-select { width: 100%; min-width: 0; max-width: 100%; }
.n-source-fixed-account { overflow-wrap: anywhere; @apply rounded-md border border-neutral-500 bg-neutral-50 p-3 text-sm dark:bg-neutral-900; }
.n-source-form-actions { @apply flex flex-wrap items-center gap-4 border-t border-neutral-400 pt-5 dark:border-neutral-500; }
.n-source-errors { @apply space-y-2 rounded-md border border-red-700 bg-red-50 p-4 text-sm text-red-900 focus:outline-2 focus:outline-offset-2 focus:outline-red-700 dark:border-red-300 dark:bg-red-950 dark:text-red-100 dark:focus:outline-red-300; }
.n-source-error-link { @apply inline-flex min-h-11 items-center rounded-sm underline underline-offset-4 focus:outline-2 focus:outline-offset-2 focus:outline-red-700 dark:focus:outline-red-300; overflow-wrap: anywhere; }
.n-source-field-error { @apply text-sm text-red-800 dark:text-red-200; }
.n-source-workspace .field_with_errors { display: contents; }
.n-source-workspace [aria-invalid="true"] { @apply border-red-700 dark:border-red-300; }
.n-source-workspace .n-source-editor {
  width: 100%; min-width: 0; max-width: 100%; padding: 0;
  border: 1px solid var(--color-neutral-500); border-radius: .5rem;
  background: var(--color-white); color: var(--color-neutral-900);
  --lexxy-editor-rows: 14lh;
  --lexxy-focus-ring-color: var(--color-green-700);
}
.dark .n-source-workspace .n-source-editor {
  background: var(--color-neutral-800); color: var(--color-neutral-100);
  --lexxy-focus-ring-color: var(--color-green-300);
}
.n-source-workspace .n-source-editor .lexxy-editor__content { min-block-size: 16rem; padding: 1rem; overflow-wrap: anywhere; }
.n-source-workspace .n-source-editor lexxy-toolbar { flex-wrap: wrap; max-width: 100%; }
.n-source-workspace .n-source-editor lexxy-toolbar button { min-width: 2.75rem; min-height: 2.75rem; }
.n-source-workspace [data-source-form-help] { @apply space-y-3; }
```

The editor CSS remains unlayered and qualified by the Sources workspace, so Lexxy's engine styles do not win simply by being unlayered and the chat composer remains untouched. Do not hide the native editor toolbar or add a second formatting toolbar.

Append under `nosia.sources_workspace` in each paired catalog:

```yaml
# English additions
form_description: "Save knowledge for conversations without changing the account’s default settings."
check_form: "Check the fields below"
saving: "Saving…"
optional_title: "Optional. Without a title, the file name is used."
current_file: "Current file: %{name}"
replacement_file: "Replacement file (optional)"
keep_file: "Leave this empty to keep the current file, or choose a replacement."
select_file: "Choose the document to add."
reselect_file: "Browsers do not retain file selections after a failed save. Select the file again if adding or replacing one."
form_help_title: "About this source"
processing_help: "Saving queues the existing background processing. Check the source list for its actual indexing status."
form_help:
  document: "Add a document with its current file control. Editing keeps its file unless you select a replacement."
  text: "Paste or write knowledge using the existing editor. Attachments are disabled here."
  qna: "Pair a clear question with its answer. The answer uses the existing text-only editor."
  website: "The URL uses the existing crawl and indexing workflow. You can edit the available content; there are no additional crawl settings here."
```

```yaml
# French additions
form_description: "Enregistrez des connaissances pour les conversations sans modifier le compte par défaut."
check_form: "Vérifiez les champs ci-dessous"
saving: "Enregistrement…"
optional_title: "Facultatif. Sans titre, le nom du fichier est utilisé."
current_file: "Fichier actuel : %{name}"
replacement_file: "Fichier de remplacement (facultatif)"
keep_file: "Laissez ce champ vide pour conserver le fichier actuel ou choisissez un remplacement."
select_file: "Choisissez le document à ajouter."
reselect_file: "Les navigateurs ne conservent pas le fichier sélectionné après un échec. Sélectionnez-le à nouveau pour l’ajouter ou le remplacer."
form_help_title: "À propos de cette source"
processing_help: "L’enregistrement lance le traitement en arrière-plan existant. Consultez la liste des sources pour connaître l’état réel de l’indexation."
form_help:
  document: "Ajoutez un document avec le champ de fichier existant. La modification conserve le fichier sauf si vous choisissez un remplacement."
  text: "Collez ou rédigez des connaissances avec l’éditeur existant. Les pièces jointes sont désactivées ici."
  qna: "Associez une question claire à sa réponse. La réponse utilise l’éditeur de texte existant sans pièces jointes."
  website: "L’URL utilise le processus existant d’exploration et d’indexation. Vous pouvez modifier le contenu disponible ; aucun réglage d’exploration supplémentaire n’est proposé ici."
```

- [x] **Step 7: Run GREEN and every existing scoped/legacy write and conversion contract.**

```bash
rails_test tailwindcss:build
record_check /tmp/opencode/sources-workspace-task4-green.log rails_test test test/controllers/sources_workspace_forms_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/accounts/scoped_source_operations_test.rb test/controllers/sources/documents_controller_test.rb test/controllers/sources/texts_controller_test.rb test/controllers/sources/qnas_controller_test.rb test/controllers/sources/websites_controller_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
mise exec ruby@4.0.7 -- env RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app/helpers/source_forms_helper.rb test/controllers/sources_workspace_forms_test.rb test/controllers/accounts/scoped_source_operations_test.rb
git diff --check
```

Expected: all focused tests pass, including unchanged filing rejection, legacy JSON versus scoped HTML negotiation, editor Markdown/frontmatter behavior, member permissions, and queued job assertions. A new field requirement, content rewrite, weakened assertion, or new update account parameter is not a presentation fix.

- [x] **Step 8: Commit only Task 4 paths.**

```bash
git add app/helpers/source_forms_helper.rb app/javascript/controllers/source_form_controller.js app/views/sources/_form_page.html.erb app/views/sources/_form_help.html.erb app/views/sources/_form_errors.html.erb app/views/sources/_field_error.html.erb app/views/sources/_form_actions.html.erb app/views/sources/_account_field.html.erb app/views/sources/documents/_form.html.erb app/views/sources/texts/_form.html.erb app/views/sources/qnas/_form.html.erb app/views/sources/websites/_form.html.erb app/views/sources/documents/new.html.erb app/views/sources/documents/edit.html.erb app/views/sources/texts/new.html.erb app/views/sources/texts/edit.html.erb app/views/sources/qnas/new.html.erb app/views/sources/qnas/edit.html.erb app/views/sources/websites/new.html.erb app/views/sources/websites/edit.html.erb app/assets/stylesheets/nosia/sources.css config/locales/en.nosia_sources_workspace.yml config/locales/fr.nosia_sources_workspace.yml test/controllers/sources_workspace_forms_test.rb test/controllers/accounts/scoped_source_operations_test.rb
git commit -m "feat(sources): Unify forms and connected validation feedback"
```

Browser verification of focus, linked errors, submitting state, mobile editors, and successful saves follows in Task 6; do not claim those from request tests alone.

## Task 5: Make source details coherent without changing content rendering

**Create:** `test/controllers/sources_workspace_details_test.rb`, `app/views/sources/_detail.html.erb`.
**Modify:** four show templates, `app/views/sources/documents/_document.html.erb`, Sources CSS/catalogs, and the remaining show presentation assertions in `test/controllers/accounts/scoped_source_operations_test.rb`.

- [x] **Step 1: Write read-only, navigation, safe-content, and file-preview tests.**

```ruby
# test/controllers/sources_workspace_details_test.rb
require "test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceDetailsTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview(@member) }

  test "each legacy and scoped detail names the source and account with separate actions" do
    SourceRow::TYPES.each do |type|
      source = experience(type.pluralize, "overview_second_#{type}")
      scoped = public_send("account_sources_#{type}_path", @second, source)
      legacy = public_send("sources_#{type}_path", source)
      edit_path = public_send("edit_account_sources_#{type}_path", @second, source)
      [ legacy, scoped ].each do |path|
        before = source.reload.attributes
        assert_no_enqueued_jobs { get path }
        assert_response :success
        assert_select "[data-source-detail] h1", text: source.display_title
        assert_select "[data-workspace-scope]", text: "Account: #{@second.name}"
        assert_select "[data-source-detail] [data-source-type-label]", text: source.source_type_label
        assert_select "[data-source-detail] [data-source-chunks]"
        assert_select "[data-source-detail] time[datetime]"
        assert_select "[data-source-detail] a[data-source-edit][href='#{edit_path}']", text: I18n.t("nosia.sources.#{type.pluralize}.edit_action")
        assert_select "[data-source-detail] a[data-turbo-method='delete'][href='#{scoped}']" do |links|
          assert_includes links.first["data-turbo-confirm"], source.display_title
          assert_includes links.first["data-turbo-confirm"], @second.name
        end
        assert_select "#accordion-right-actions, #drawer-right", count: 0
        assert_equal before, source.reload.attributes
        retry_path = public_send("account_sources_#{type}_retry_path", @second, source)
        assert_select "[data-source-detail] form[action='#{retry_path}']", count: source.failed? ? 1 : 0
      end
    end
  end

  test "text and Q&A stay escaped while website HTML keeps its existing sanitizer" do
    text = experience(:texts, :overview_second_text)
    qna = experience(:qnas, :overview_second_qna)
    website = experience(:websites, :overview_second_website)
    text.update_columns(data: "<script>alert('text')</script>")
    qna.update_columns(question: "<img src=x onerror=alert(1)>", answer: "<script>alert('answer')</script>")
    website.update_columns(data: "# Safe heading\n\n**Safe bold**\n\n<script>alert('website')</script>\n\n<img src=x onerror=alert(1)>")
    [ text, qna, website ].each do |source|
      type = source.model_name.element
      get public_send("account_sources_#{type}_path", @second, source)
      assert_response :success
      assert_select "[data-source-detail] script, [data-source-detail] [onerror]", count: 0
      assert_equal source.data, source.reload.data if source.respond_to?(:data)
    end
    get account_sources_text_path(@second, text)
    assert_select "[data-source-detail-content]", text: "<script>alert('text')</script>"
    get account_sources_qna_path(@second, qna)
    assert_select "[data-source-detail-content]", text: "<script>alert('answer')</script>"
    get account_sources_website_path(@second, website)
    assert_select "[data-source-detail-content] strong", text: "Safe bold"
  end

  test "empty permitted content has a presentation title but remains unchanged" do
    source = experience(:texts, :overview_second_text)
    source.update_columns(title: nil, data: "")
    get account_sources_text_path(@second, source)
    assert_response :success
    assert_select "[data-source-detail] .n-workspace-header h1", text: "Untitled Text"
    assert_empty source.reload.data
  end

  test "document details keep the original file link and MIME-specific preview" do
    source = experience(:documents, :overview_second_document)
    get account_sources_document_path(@second, source)
    assert_response :success
    assert_select "[data-source-file-link][target='_blank'][rel='noopener']", text: source.file.filename.to_s
    assert_select "[data-source-file-link][href*='/rails/active_storage/']"
    assert_select "[data-source-document-preview] iframe, [data-source-document-preview] img", count: 0

    source.file.blob.update_columns(content_type: "application/pdf")
    get account_sources_document_path(@second, source)
    assert_select "[data-source-document-preview] iframe[title='#{source.display_title}']"
    source.file.blob.update_columns(content_type: "image/png")
    get account_sources_document_path(@second, source)
    assert_select "[data-source-document-preview] img[alt='#{source.display_title}']"
  end
end
```

The MIME test changes only transactional fixture metadata to exercise existing branches; it does not parse a fake PDF/image or run a job.

Within the existing typed test `"#{type} new edit and show links retain the route account"`, replace only its show block's old sr-only presentation assertions with:

```ruby
get path
assert_response :success
assert_select "a[data-workspace-back][href='#{index_path}']", text: I18n.t("nosia.actions.back")
assert_select "a[data-source-edit][href='#{edit_path}']", text: I18n.t("nosia.sources.#{type.to_s.pluralize}.edit_action")
assert_select "a[href='#{path}'][data-turbo-method='delete'][data-turbo-confirm]",
  text: I18n.t("nosia.sources.#{type.to_s.pluralize}.delete_action")
```

- [x] **Step 2: Observe RED, then add the shared detail wrapper.**

```bash
record_check /tmp/opencode/sources-workspace-task5-red.log rails_test test test/controllers/sources_workspace_details_test.rb test/controllers/accounts/scoped_source_operations_test.rb
```

Expected: missing meaningful detail heading, metadata, wrapper markers, and labeled file destination. Escaping and sanitizer assertions should already pass; keep them passing.

```erb
<%# app/views/sources/_detail.html.erb %>
<%# locals: (record:, content:) %>
<% content_for :account_tool_title, t("nosia.account_experience.sources") if @scoped_source_account %>
<% type = record.model_name.element %>
<% row = SourceRow.new(record, chunks_count: record.chunks.count) %>
<% account = @scoped_source_account || record.account %>
<% title = source_workspace_title(record) %>
<% actions = capture do %>
  <%= link_to t("nosia.sources.#{type.pluralize}.edit_action"), source_edit_path(record), class: "n-workspace-button n-workspace-primary", data: { source_edit: true } %>
  <% if record.failed? %>
    <%= button_to t("nosia.actions.retry"), source_retry_path(record), method: :post, class: "n-workspace-button" %>
  <% end %>
  <%= link_to t("nosia.sources.#{type.pluralize}.delete_action"), source_show_path(record),
        class: "n-workspace-button n-workspace-danger",
        data: { turbo_method: :delete, turbo_confirm: source_delete_confirmation(record, account_name: account.name) } %>
<% end %>
<div class="n-workspace n-source-workspace" data-source-workspace data-source-detail>
  <%= render "workspaces/header", title: title,
        scope_label: source_workspace_scope(account), trail: source_workspace_trail(title: title),
        back_path: source_index_path(type: type), show_new_chat: !@scoped_source_account, actions: actions %>
  <section class="n-workspace-panel n-source-detail-panel">
    <div class="n-source-metadata">
      <span data-source-type-label><%= record.source_type_label %></span>
      <%= render "sources/status", row: row %>
      <% value = record.pending? && row.chunks_count.zero? ? "—" : number_with_delimiter(row.chunks_count) %>
      <span data-source-chunks><%= t("nosia.sources_workspace.chunk_value", value: value) %></span>
      <time datetime="<%= record.created_at.iso8601 %>"><%= t("nosia.sources_workspace.added", time: t("nosia.time.ago", duration: time_ago_in_words(record.created_at))) %></time>
    </div>
    <% if record.failed? %><p class="n-workspace-help"><%= record.failure_reason.presence || t("nosia.sources_workspace.failed_help") %></p><% end %>
    <div class="n-source-detail-content" data-source-detail-content><%= content %></div>
  </section>
</div>
```

- [x] **Step 3: Replace each complete show template, preserving its content policy.**

```erb
<%# app/views/sources/documents/show.html.erb %>
<%= render "sources/detail", record: @document, content: capture { render @document } %>
```

```erb
<%# app/views/sources/texts/show.html.erb %>
<% content = capture do %>
  <div class="n-source-plain-content"><%= @text.data %></div>
<% end %>
<%= render "sources/detail", record: @text, content: content %>
```

```erb
<%# app/views/sources/qnas/show.html.erb %>
<% content = capture do %>
  <div class="n-source-plain-content"><%= @qna.answer %></div>
<% end %>
<%= render "sources/detail", record: @qna, content: content %>
```

The Q&A question is already the meaningful page heading via `Qna#display_title`; do not duplicate it as a second ID-based heading.

```erb
<%# app/views/sources/websites/show.html.erb %>
<% content = capture do %>
  <p class="n-workspace-help"><%= @website.url %></p>
  <% if @website.data.present? %>
    <div class="n-source-markdown"><%= sanitize @website.to_html,
          tags: ApplicationHelper::SANITIZED_MARKDOWN_TAGS,
          attributes: ApplicationHelper::SANITIZED_MARKDOWN_ATTRIBUTES %></div>
  <% else %>
    <p class="n-workspace-help"><%= t("nosia.sources.no_content") %></p>
  <% end %>
<% end %>
<%= render "sources/detail", record: @website, content: content %>
```

```erb
<%# app/views/sources/documents/_document.html.erb %>
<div id="<%= dom_id document %>" data-source-document-preview>
  <% if document.file.attached? %>
    <%= link_to document.file.filename.to_s, url_for(document.file), target: "_blank", rel: "noopener", class: "n-workspace-link", data: { source_file_link: true } %>
    <% case document.file.blob.content_type %>
    <% when "application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document" %>
      <iframe class="n-source-file-frame" src="<%= url_for(document.file) %>" title="<%= document.display_title %>"></iframe>
    <% when "image/png", "image/jpeg" %>
      <img class="n-source-file-image" src="<%= url_for(document.file) %>" alt="<%= document.display_title %>">
    <% end %>
  <% else %>
    <p class="n-workspace-help"><%= t("nosia.sources_workspace.no_file") %></p>
  <% end %>
</div>
```

This retains PDF/DOCX iframe, PNG/JPEG image, and other-file link behavior. It does not claim DOCX has new browser-native support, change file authorization, or introduce a document converter. Text and Q&A remain escaped plain text; Website retains the exact existing allowlist. No `raw` or `html_safe` is added.

- [x] **Step 4: Add bounded content/preview styling and paired fallback copy.**

```css
/* Append to app/assets/stylesheets/nosia/sources.css */
.n-source-detail-panel { @apply space-y-5; }
.n-source-detail-content { min-width: 0; overflow-wrap: anywhere; }
.n-source-plain-content { white-space: pre-wrap; @apply text-base leading-relaxed; }
.n-source-markdown { @apply space-y-3 text-base leading-relaxed; }
.n-source-markdown a { @apply text-green-800 underline dark:text-green-200; }
.n-source-markdown pre, .n-source-markdown table { display: block; max-width: 100%; overflow-x: auto; }
.n-source-file-frame { width: 100%; height: 60vh; min-height: 16rem; margin-top: 1rem; border: 1px solid var(--color-neutral-500); border-radius: .5rem; }
.n-source-file-image { display: block; width: auto; max-width: 100%; max-height: 70vh; margin: 1rem auto 0; object-fit: contain; }
```

```yaml
# English addition under nosia.sources_workspace
no_file: "No file is available for this document."
```

```yaml
# French addition under nosia.sources_workspace
no_file: "Aucun fichier n’est disponible pour ce document."
```

- [x] **Step 5: Run GREEN and commit.**

```bash
rails_test tailwindcss:build
record_check /tmp/opencode/sources-workspace-task5-green.log rails_test test test/controllers/sources_workspace_details_test.rb test/controllers/accounts/scoped_source_operations_test.rb test/controllers/sources/documents_controller_test.rb test/controllers/sources/texts_controller_test.rb test/controllers/sources/qnas_controller_test.rb test/controllers/sources/websites_controller_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
mise exec ruby@4.0.7 -- env RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop test/controllers/sources_workspace_details_test.rb test/controllers/accounts/scoped_source_operations_test.rb
git diff --check
git add app/views/sources/_detail.html.erb app/views/sources/documents/show.html.erb app/views/sources/documents/_document.html.erb app/views/sources/texts/show.html.erb app/views/sources/qnas/show.html.erb app/views/sources/websites/show.html.erb app/assets/stylesheets/nosia/sources.css config/locales/en.nosia_sources_workspace.yml config/locales/fr.nosia_sources_workspace.yml test/controllers/sources_workspace_details_test.rb test/controllers/accounts/scoped_source_operations_test.rb
git commit -m "feat(sources): Align details and preserve safe content previews"
```

Expected: every targeted check passes. Do not treat the document metadata branch test as evidence that native browser PDF/DOCX rendering was manually inspected.

## Task 6: Verify workflows, responsive layouts, keyboard access, and measured contrast

**Extend:** `test/system/sources_workspace_test.rb`, preserving the earlier invalid-editor probe.
**Modify:** Sources-scoped motion rules and the specifically reviewed navigation/form fixes recorded in the execution adaptations above. Preserve all existing behavioral assertions; only the two documented protected Stimulus selectors change.

- [x] **Step 1: Add the complete system test below.** Tests use fixture records, the test queue adapter, real authorized requests, and local browser rendering; no LLM, crawl, parsing, or embedding job is performed. Evidence is written only to the ignored external directory printed by the test.

```ruby
# test/system/sources_workspace_test.rb
require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    @original_window_size = page.current_window.size
    @evidence_dir = "/tmp/opencode/sources-workspace-#{Process.pid}"
    FileUtils.mkdir_p(@evidence_dir)
    puts "Sources browser evidence: #{@evidence_dir}"
    sign_in_workspace_browser
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

  test "GET filters compose preserve browser history and keep the default account unchanged" do
    visit account_sources_path(@second)
    fill_in "source-q", with: "Research"
    click_on "Filter"
    find("[data-source-filter-type='text']").click
    select "Failed", from: "status"
    select "Title", from: "sort"
    assert_current_path account_sources_path(@second), ignore_query: true
    assert_selector "[data-source-filter-type='text'][aria-current='true']"
    assert_equal "Research", find("#source-q").value
    assert_equal "failed", find("#status").value
    assert_equal "title", find("#sort").value
    assert_selector "[data-source-id]", count: 1
    page.go_back
    assert_selector "#sort option[value='recent'][selected]"
    assert_equal "failed", find("#status").value
    find("[data-source-reset]").click
    assert_current_path account_sources_path(@second)
    assert_equal "", find("#source-q").value
    assert_equal "all", find("#status").value
    visit sources_path
    assert_selector "[data-workspace-scope]", text: "Default account: #{@first.name}"
    assert_equal @first, @user.first_account
  end

  test "every type creates and edits in the URL account using its original job flow" do
    SourceRow::TYPES.each do |type|
      visit public_send("new_account_sources_#{type}_path", @second)
      case type
      when "document"
        fill_in "document_title", with: "Browser document"
        attach_file "document_file", file_fixture("account_source.txt")
      when "text"
        fill_source_editor("Browser text")
      when "qna"
        fill_in "qna_question", with: "Browser question?"
        fill_source_editor("Browser answer")
      when "website"
        fill_in "website_url", with: "https://browser-source.example/reference"
        fill_source_editor("Browser website")
      end
      clear_enqueued_jobs
      click_on "Save"
      assert_selector "[data-source-detail]"
      record = @second.public_send(type.pluralize).order(:id).last
      assert_current_path public_send("account_sources_#{type}_path", @second, record)
      assert_enqueued_with job: ingestion_job(type), args: [ record.id ]
      assert_equal @second.id, record.account_id
      find("[data-source-edit]").click
      assert_selector "[data-source-fixed-account]", text: @second.name
      if type == "document"
        fill_in "document_title", with: "Edited browser document"
      elsif type == "qna"
        fill_in "qna_question", with: "Edited browser question?"
      else
        fill_source_editor("Edited browser content")
      end
      clear_enqueued_jobs
      click_on "Save"
      assert_selector "[data-source-detail]"
      assert_current_path public_send("account_sources_#{type}_path", @second, record)
      assert_enqueued_with job: ingestion_job(type), args: [ record.id ]
      find("[data-workspace-back]").click
      assert_current_path account_sources_path(@second, type: type)
    end
    assert_equal @first, @user.first_account
  end

  test "row retry uses the existing job and deletion confirms the actual source and account" do
    source = experience(:texts, :overview_second_text)
    other = experience(:texts, :overview_first_text)
    selector = "[data-source-id='#{source.id}']"
    visit account_sources_path(@second)
    clear_enqueued_jobs
    assert_enqueued_with job: AddTextJob, args: [ source.id ] do
      within(selector) { click_on "Retry" }
      assert_current_path account_sources_path(@second, type: "text")
      assert_selector "#{selector} [data-source-index-status='pending']"
    end
    assert_no_selector "#{selector} form"
    confirmation = /#{Regexp.escape(source.display_title)}.*#{Regexp.escape(@second.name)}/
    dismiss_confirm(confirmation) { within(selector) { click_on "Delete" } }
    assert @second.texts.exists?(source.id)
    clear_enqueued_jobs
    assert_no_enqueued_jobs do
      accept_confirm(confirmation) { within(selector) { click_on "Delete" } }
      assert_no_selector selector
    end
    assert_not @second.texts.exists?(source.id)
    assert @first.texts.exists?(other.id)
    assert_equal @first, @user.first_account
  end

  test "duplicate URL 422 focuses linked errors and retains editor input" do
    visit new_account_sources_website_path(@second)
    fill_in "website_url", with: experience(:websites, :overview_second_website).url
    fill_source_editor("Keep my draft after validation")
    assert_no_enqueued_jobs do
      click_on "Save"
      assert_selector ".n-source-errors:focus"
    end
    assert_selector "#website_url[aria-invalid='true'][aria-describedby='website_url_error']"
    assert_selector "#website_url_error", text: "has already been taken"
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep my draft after validation"
    find(".n-source-errors a[href='#website_url']").click
    assert_selector "#website_url:focus"
    assert_focused_source_visible
    save_source_screenshot("422-website")
  end

  test "document 422 retains non-file values and names the reselect requirement" do
    visit new_sources_document_path
    fill_in "document_title", with: "Retained title"
    select @second.name, from: "document_account_id"
    click_on "Save"
    assert_selector ".n-source-errors:focus"
    assert_equal "Retained title", find("#document_title").value
    assert_equal @second.id.to_s, find("#document_account_id").value
    assert_text "Browsers do not retain file selections after a failed save."
    assert_equal "", find("#document_file").value
    find(".n-source-errors a[href='#document_file']").click
    assert_selector "#document_file:focus"
    assert_equal @first, @user.first_account
  end

  test "Save disables truthfully while the real submission is pending" do
    visit new_account_sources_text_path(@second)
    fill_source_editor("Delayed real source submission")
    page.execute_script(<<~JS, account_sources_texts_path(@second))
      const target=arguments[0],original=window.fetch;
      window.fetch=function(...args){
        const request=args[0],url=request instanceof Request?request.url:request;
        const method=(args[1]?.method||(request instanceof Request?request.method:'GET')).toUpperCase();
        if(new URL(url,location.href).pathname===target&&method==='POST'){
          window.fetch=original;
          return new Promise((resolve,reject)=>{window.releaseSourceSave=()=>original.apply(window,args).then(resolve,reject);});
        }
        return original.apply(this,args);
      };
    JS
    click_on "Save"
    assert_selector "form input[type='submit'][disabled][value='Saving…']"
    page.execute_script("window.releaseSourceSave()")
    assert_selector "[data-source-detail]", text: "Delayed real source submission"
    assert_enqueued_jobs 1, only: AddTextJob
  end

  test "scoped live replacements retain locale status actions and seven unique counts" do
    source = experience(:texts, :overview_second_text)
    source.update_columns(index_status: "pending")
    %w[en fr].each do |locale|
      Capybara.using_session("sources-#{locale}") do
        sign_in_workspace_browser(locale: locale)
        visit account_sources_path(@second)
        assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
        assert_selector "[data-source-id='#{source.id}'] [data-source-index-status='pending']"
      end
    end
    source.mark_indexed!
    { "en" => "Indexed", "fr" => "Indexé" }.each do |locale, label|
      Capybara.using_session("sources-#{locale}") do
        assert_selector "[data-source-id='#{source.id}'] [data-source-index-status='indexed']", text: label
        assert_no_selector "[data-source-id='#{source.id}'] form"
        assert_equal 7, page.evaluate_script("Array.from(document.querySelectorAll('[id^=source_count_]')).length")
        assert_equal 7, page.evaluate_script("new Set(Array.from(document.querySelectorAll('[id^=source_count_]'),e=>e.id)).size")
        assert_selector "[data-source-id='#{source.id}'] [data-source-edit]"
      end
    end
  end

  test "long names fit every list viewport and both languages and themes with keyboard actions" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    source = experience(:texts, :overview_second_text)
    source.update_columns(title: "SourceSansEspaces" * 20)
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      visit account_sources_path(@second)
      [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
        resize_sources(width, height)
        %w[light dark].each do |theme|
          set_sources_theme(theme)
          assert_source_layout
          assert_selector "[data-source-id='#{source.id}'] [data-source-type-label]"
          assert_selector "[data-source-id='#{source.id}'] [data-source-index-status='failed']"
          verify_row_keyboard(source)
          measure_source_contrast([
            [ ".n-workspace-title", "color", 4.5 ], [ ".n-workspace-help", "color", 4.5 ],
            [ "[data-workspace-scope]", "color", 4.5 ], [ ".n-source-subtitle", "color", 4.5 ],
            [ "[data-source-index-status='failed']", "color", 4.5 ], [ "[data-source-index-status='indexed']", "color", 4.5 ],
            [ "[data-source-index-status='pending']", "color", 4.5 ],
            [ ".n-workspace-primary", "color", 4.5 ], [ ".n-workspace-danger", "color", 4.5 ],
            [ "#source-q", "borderColor", 3 ], [ ".n-source-row-actions :focus", "outlineColor", 3 ]
          ])
          page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
          save_source_screenshot("list-#{locale}-#{width}-#{height}-#{theme}")
        end
      end
    end
  end

  test "all typed new edit and detail pages stack in both themes without altering editor controls" do
    routes = SourceRow::TYPES.flat_map do |type|
      source = experience(type.pluralize, "overview_second_#{type}")
      [ [ "#{type}-new", public_send("new_account_sources_#{type}_path", @second) ],
        [ "#{type}-edit", public_send("edit_account_sources_#{type}_path", @second, source) ],
        [ "#{type}-show", public_send("account_sources_#{type}_path", @second, source) ] ]
    end
    [ [ "en", "light" ], [ "fr", "dark" ] ].each do |locale, theme|
      select locale.upcase, from: "language_preference_locale"
      [ [ 375, 812 ], [ 1440, 1000 ] ].each do |width, height|
        resize_sources(width, height)
        routes.each do |name, path|
          visit path
          set_sources_theme(theme)
          assert_source_layout
          if page.has_selector?("lexxy-editor", wait: 0)
            assert_selector "lexxy-editor[connected][attachments='false']"
            assert_selector "lexxy-toolbar"
            assert_operator page.evaluate_script("document.querySelector('.lexxy-editor__content').getBoundingClientRect().height"), :>=, 200
          end
          if page.has_selector?(".n-source-form-layout", wait: 0)
            columns = page.evaluate_script("getComputedStyle(document.querySelector('.n-source-form-layout')).gridTemplateColumns").split.length
            assert_equal width >= 1280 ? 2 : 1, columns
            page.execute_script("document.querySelector('.n-source-form-actions input').focus()")
            assert_focused_source_visible
            measure_source_contrast([ [ ".n-workspace-help", "color", 4.5 ], [ ".n-workspace-primary", "color", 4.5 ], [ ".n-source-form-actions :focus", "outlineColor", 3 ] ])
          end
          save_source_screenshot("#{name}-#{locale}-#{width}-#{theme}")
        end
      end
    end
  end

  test "no-account setup and reduced-motion fields remain usable" do
    visit new_account_sources_text_path(@second)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    assert page.evaluate_script("Array.from(document.querySelectorAll('.n-source-workspace .n-field,.n-source-workspace .n-select,.n-source-workspace .n-source-editor')).every(e=>getComputedStyle(e).transitionDuration==='0s')")
    page.driver.browser.manage.delete_all_cookies
    sign_in_workspace_browser(user: experience(:users, :overview_no_account))
    resize_sources(375, 812)
    %w[light dark].each do |theme|
      visit sources_path
      set_sources_theme(theme)
      assert_selector "[data-source-setup]"
      assert_no_selector "[data-source-workspace] form,[data-source-workspace] [data-source-upload]"
      assert_source_layout
      page.execute_script("document.querySelector('[data-source-setup] section a').focus()")
      assert_focused_source_visible
      measure_source_contrast([ [ ".n-workspace-help", "color", 4.5 ], [ ".n-workspace-primary", "color", 4.5 ] ])
      save_source_screenshot("no-account-#{theme}")
    end
  end

  private
    def sign_in_workspace_browser(user: @user, locale: "en")
      visit root_url
      fill_in "email", with: user.email
      fill_in "password", with: AccountExperienceFixtures::PASSWORD
      click_on "Sign in"
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang='#{locale}']"
    end

    def fill_source_editor(content)
      assert_selector "lexxy-editor[connected]"
      editor = find("lexxy-editor .lexxy-editor__content")
      editor.click
      editor.send_keys([ :control, "a" ], content)
    end

    def ingestion_job(type)
      { "document" => AddDocumentJob, "text" => AddTextJob, "qna" => AddQnaJob, "website" => CrawlWebsiteUrlJob }.fetch(type)
    end

    def resize_sources(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth,innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
    end

    def set_sources_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script(<<~JS)
        const done=arguments[0];
        Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());
      JS
    end

    def assert_source_layout
      assert_selector "[data-source-workspace] .n-workspace-header h1", count: 1
      assert_no_text(/translation missing|missing translation/i)
      assert page.evaluate_script("document.querySelector('main').scrollWidth<=document.querySelector('main').clientWidth+1"), "Sources page overflows horizontally"
    end

    def verify_row_keyboard(source)
      selector = "[data-source-id='#{source.id}']"
      page.execute_script("document.querySelector(arguments[0]+' .n-source-title').focus()", selector)
      [ "[data-source-edit]", "button", "[data-turbo-method='delete']" ].each do |control|
        page.send_keys(:tab)
        assert_selector "#{selector} #{control}:focus"
        assert_focused_source_visible
        dimensions = page.evaluate_script("(()=>{const r=document.activeElement.getBoundingClientRect();return [r.width,r.height];})()")
        dimensions.each { |value| assert_operator value, :>=, 44 }
      end
      page.send_keys([ :shift, :tab ])
      assert_selector "#{selector} button:focus"
    end

    def assert_focused_source_visible
      state = page.evaluate_script(<<~JS)
        (()=>{
          const e=document.activeElement,r=e.getBoundingClientRect(),s=getComputedStyle(e),main=document.querySelector('main').getBoundingClientRect();
          const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
          return {outline:parseFloat(s.outlineWidth),visible:r.top>=Math.max(0,main.top)&&r.bottom<=Math.min(innerHeight,main.bottom)&&points.every(([x,y])=>{const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));})};
        })()
      JS
      assert_operator state.fetch("outline"), :>=, 2
      assert state.fetch("visible"), "Focused source action is clipped or covered by fixed navigation"
    end

    def measure_source_contrast(samples)
      rows = page.evaluate_script(<<~JS, samples)
        (()=>{
          const samples=arguments[0],canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const ancestors=[];for(let a=e;a;a=a.parentElement)ancestors.unshift(a);return ancestors.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured gradient/opacity');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          return samples.map(([selector,property,minimum])=>{
            const e=Array.from(document.querySelectorAll(selector)).find(e=>e.getClientRects().length&&getComputedStyle(e).visibility==='visible');
            if(!e)throw new Error(`Missing visible contrast sample: ${selector}`);
            const s=getComputedStyle(e),bg=background(property==='color'?e:e.parentElement);
            const a=luminance(blend(rgba(s[property]),bg)),b=luminance(bg);
            return {selector,property,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};
          });
        })()
      JS
      rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.fetch("selector") }
      File.open("#{@evidence_dir}/contrast.jsonl", "a") do |file|
        file.puts({ path: page.current_path, viewport: page.evaluate_script("[innerWidth,innerHeight]"), dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: rows }.to_json)
      end
    end

    def save_source_screenshot(name)
      page.driver.browser.execute_async_script(<<~JS)
        const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));
      JS
      page.save_screenshot("#{@evidence_dir}/#{name}.png")
    end
end
```

- [x] **Step 2: Run the new browser file and inspect failures before changing presentation.**

```bash
record_check /tmp/opencode/sources-workspace-task6-first-browser.log browser_test test/system/sources_workspace_test.rb test/system/sources_workspace_upload_test.rb
```

Expected: the remaining field/editor transition test is RED because global field rules still transition colors under reduced motion. Other failures, if any, must be diagnosed against the approved design and actual browser output. Do not loosen focus, size, contrast, account, or content assertions to accommodate a defect. If an assumption in this plan is wrong, document the correction and retain the original failed log.

- [x] **Step 3: Add the minimal reduced-motion fix after observing that failure.** Append to the Sources stylesheet:

```css
@media (prefers-reduced-motion: reduce) {
  .n-source-workspace .n-field,
  .n-source-workspace .n-select,
  .n-source-workspace .n-source-editor,
  .n-source-workspace .n-source-title { transition: none; }
}
```

- [x] **Step 4: Run GREEN and protected browser regressions sequentially.**

```bash
rails_test tailwindcss:build
record_check /tmp/opencode/sources-workspace-task6-browser-green.log browser_test test/system/sources_workspace_test.rb test/system/sources_workspace_upload_test.rb
record_check /tmp/opencode/sources-workspace-task6-browser-regressions.log browser_test test/system/sources_dropzone_test.rb test/system/account_experience_test.rb test/system/localization_test.rb test/system/dashboard_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
mise exec ruby@4.0.7 -- env RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop test/system/sources_workspace_test.rb test/system/sources_workspace_upload_test.rb
git diff --check
```

Expected: both browser commands exit 0. Existing composer attachment and upload retry identity assertions remain intact. Only the two reviewed Stimulus token selectors change in one protected file; the other five files remain unchanged. Record actual counts, not the dashboard's historical browser totals.

- [x] **Step 5: Inspect application evidence, not just test exits.** Use the file/image tool to inspect these actual screenshots from the evidence directory printed by the successful run: English 375px light list; French 375px dark list; French 812×375 dark list; English desktop light list; document edit; text editor; Q&A form; website edit; each detail type; no-account; and website 422. Read `contrast.jsonl` and report the measured minimum text/control/focus ratios per theme. Tests cover the matrix; the report must identify which images were actually reviewed.

Check long words/URLs wrapping, visible type/status/counts/actions, native editor toolbar, paired Q&A spacing, file retention/reselection language, and last-action clearance above fixed navigation. A screenshot's CSS viewport is **not** native zoom evidence. If a native 200% browser-zoom/manual keyboard pass is available, record browser/viewport/pages/result separately; otherwise explicitly leave native 200% zoom unverified, without replacing it with CSS scaling or device-metric emulation.

- [x] **Step 6: Commit the regression and reviewed Sources-only fixes.** Final authorized scope and the CSRF-preserving follow-up are recorded above; stage explicit files, not unrelated changes.

```bash
git add test/system/sources_workspace_test.rb app/assets/stylesheets/nosia/sources.css
git commit -m "test(sources): Verify responsive workflows and accessibility"
```

## Task 7: Document the Sources workspace and unchanged boundaries

**Create:** `docs/sources-workspace.md`.
**Modify:** `docs/README.md`, `docs/DIAGRAMS.md`.

- [x] **Step 1: Create the following user/developer documentation.** Documentation describes the resulting interface; this task is not evidence of tests having passed.

````markdown
# Sources workspace

Sources manage documents, text, Q&As, and websites available to conversations in
an account. The workspace includes lists, full-page new/edit forms, and details;
it does not add source types, bulk actions, a wizard, or an ingestion pipeline.

## Account context and navigation

- `/sources` still uses the signed-in user’s default account. A query parameter
  does not turn it into an account switcher or cross-account directory.
- `/accounts/:account_id/sources` explicitly manages that authorized URL account.
  Links, creates, edits, retries, and deletes retain it; membership is rechecked.
- Legacy new forms keep their membership-account filing picker. Its choice does
  not change the user’s default account and is retained after validation errors.
- Scoped forms fix the account to the URL. Editing displays the record account
  read-only and never offers account transfer. Forged filing context retains the
  existing rejection behavior.
- Without an account membership, the unscoped list and legacy new forms offer an
  Accounts destination instead of account-dependent controls. Unauthorized scoped
  URLs and inaccessible records still return 404, not a setup page.
- Sources pages retain the shared header/navigation but not the unrelated chat
  history drawer. The generic desktop New chat destination remains available on
  legacy pages; it does not silently become an account-targeted chat shortcut.

## Filters, counts, and pagination

The URL carries `type`, `status`, `q`, `sort`, and `page`. Changing type or status
retains query/sort and the other selection while resetting pagination. The toolbar
submits a GET; status/sort controls use the existing submit-on-change behavior.
There is no keystroke polling. All sources changes only the type; Reset clears
the selections and restores recently added sorting.

- Types: `all`, `document`, `text`, `qna`, `website`.
- Statuses: `all`, `indexed`, `pending`, `failed`.
- Sorts: `recent`, `title`, `status`, `chunks`.
- Load more retains the selections and the existing 50-row page size.
- Navigation counts are account-wide; the matching total describes the current
  list request. Neither is a new reporting definition.

One responsive navigation contains the seven existing live counter IDs, including
zero values. Narrow layouts stack metadata without hiding type, status, or actions.

## Upload and processing feedback

Drop files onto the existing list target or use Choose files. The unchanged
dropzone owns size/type checks, upload requests, per-file state, retry/removal,
and stable upload intent. A lost successful response can be retried without
creating a second document or indexing job for that intent.

Uploaded is not Indexed. Source states remain pending, indexed, and failed;
websites may say Crawling while pending. Chunk counts use real data and unknown
pending counts are not invented. Failed sources offer the existing Retry action
with generic guidance unless a real stored reason exists.

Unsearched matching lists retain their existing live prepends and localized
row/status/count updates. Search views do not promise live prepends. Loaded rows
are not continuously re-sorted or re-filtered after a status change, and a loaded
matching total is a snapshot. Reload to reapply current query/order/page membership.

## Forms, errors, and content

Forms keep existing fields, model validation, job behavior, and route/format
contracts. Text and Q&A do not acquire new required business fields. Website
editing retains its body-only Markdown/frontmatter behavior. Rich-text editors
keep their native toolbar with attachments disabled.

Save displays its pending state. Existing success notices remain in use. A failed
save focuses a linked validation summary, connects inline errors to fields, and
retains submitted non-file values. Browser file selections are not retained after
an error: select the file again if adding or replacing one. A document edit keeps
the existing attachment unless a replacement is selected.

Details use the source’s meaningful title and show account/type/status/metadata
with separate Edit, conditional Retry, and Delete controls. Delete confirmation
names the source and account. Document viewing and original-file links remain;
this interface does not add native DOCX rendering support or a file converter.
Text/Q&A remain escaped plain text; Website keeps the established HTML sanitizer
and allowlist. Presentation never rewrites stored source content.

## Verification

The [implementation plan](superpowers/plans/2026-10-24-sources-workspace-ui-ux.md)
defines the isolated database, RED/GREEN gates, exact commands, protected existing
source/composer regressions, and final evidence requirements. Use fixtures and
the test queue adapter; do not perform live provider or ingestion jobs.

Application screenshots and measured contrast cover the specified responsive
matrix, both themes, English/French, long names, keyboard actions, 422 focus, and
fixed-navigation clearance. Read actual execution evidence before making a
verification claim. Native 200% browser zoom requires separate manual evidence;
device metrics or CSS scaling are not a substitute. Existing unrelated suite or
scanner issues must be reported with their true exits, not described as green.

Token usage, Agent skills, and MCP redesigns remain separate subprojects. Their
existing account/reporting behavior is not changed by the Sources foundation.
````

- [x] **Step 2: Add the documentation index link and the focused diagram.** Insert this line after the existing Signed-in dashboard link under `### Development` in `docs/README.md`:

```markdown
- [Sources workspace](sources-workspace.md) — default/scoped lists, composed filters, uploads, forms, live status, and safe details.
```

Insert the following entire section before `## RAG Pipeline Flow` in `docs/DIAGRAMS.md`. Other diagrams remain unchanged.

````markdown
## Sources Workspace Entry Points

```text
/sources (default account)       /accounts/:account_id/sources (URL account)
          \                                  /
           +-- type + status + query + sort --+
                           |
                 50-row list + Load more
                 |                 |
        existing dropzone     title -> detail -> edit
        browse/drop/retry          |               |
                 |             Retry/Delete    Save/Cancel
                 +---------- existing CRUD/jobs ---+
                                      |
                     localized row + seven count targets

Legacy new: membership filing picker; scoped new: fixed URL account
All edit: fixed record account; neither changes the default account
```

Upload completion and indexing completion are different states. Live replacement
does not continuously re-sort/re-filter the loaded page; searched lists do not
promise live prepends. Read pages do not enqueue processing. See
[Sources workspace](sources-workspace.md) for navigation, content-safety, and
verification boundaries.
````

- [x] **Step 3: Check links, diff, and scope, then commit the documentation.**

```bash
python3 - <<'PY'
from pathlib import Path
import re
for name in ("docs/sources-workspace.md", "docs/README.md", "docs/DIAGRAMS.md"):
    path = Path(name)
    for target in re.findall(r'\]\(([^)]+)\)', path.read_text()):
        target = target.split("#", 1)[0]
        if target and "://" not in target and not target.startswith("mailto:"):
            assert (path.parent / target).exists(), (name, target)
print("Documentation links resolve")
PY
git diff --check
git add docs/sources-workspace.md docs/README.md docs/DIAGRAMS.md
git commit -m "docs(sources): Describe workspace workflows and boundaries"
```

Expected: all checked local links resolve. If an unrelated preexisting link is broken, report it instead of silently modifying unrelated documentation.

## Task 8: Run final verification and review before integration

**Modify:** this plan's execution checkboxes/evidence only after real execution; application fixes require a new observed RED/GREEN cycle. No automatic merge, push, PR, worktree deletion, or later-workflow implementation.

- [x] **Step 1: Inspect the complete feature diff against the clean execution base.**

```bash
git status --short
git diff --check
git diff --stat "$(head -n1 /tmp/opencode/sources-workspace-execution-base.log)" HEAD
git log --oneline -10
```

The diff command uses the immutable base saved at Task 0, not a dashboard branch tip that might have moved. The new feature must not alter schema/dependencies, source model validations, queue transport, uploader intent/transport, legacy/scoped write formats, composer behavior, global fixtures, or permissions. Old tests change only the documented scoped presentation contracts, single French heading, two protected Stimulus token selectors, Sources drawer expectation, and separately user-authorized test-registry isolation; all behavioral assertions remain intact.

- [x] **Step 2: Build and run the full focused server regression set sequentially.**

```bash
rails_test tailwindcss:build
record_check /tmp/opencode/sources-workspace-final-focused.log rails_test test test/controllers/sources_workspace_shell_test.rb test/controllers/sources_workspace_filters_test.rb test/controllers/sources_workspace_rows_test.rb test/controllers/sources_workspace_forms_test.rb test/controllers/sources_workspace_details_test.rb test/controllers/sources_controller_test.rb test/controllers/sources/documents_controller_test.rb test/controllers/sources/texts_controller_test.rb test/controllers/sources/qnas_controller_test.rb test/controllers/sources/websites_controller_test.rb test/controllers/accounts/scoped_sources_test.rb test/controllers/accounts/scoped_source_operations_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_sources_controller_test.rb test/models/source_row_test.rb test/models/sourceable_test.rb test/models/sourceable_broadcast_test.rb test/models/account_source_broadcast_test.rb test/models/document_source_registration_test.rb test/integration/localized_pages_test.rb test/integration/localized_broadcasts_test.rb test/internationalization/catalogs_test.rb test/controllers/dashboards_controller_test.rb test/integration/header_navigation_test.rb
```

Expected: exit 0, no failures/errors. Record actual run/assertion counts and seed from the saved log. Do not apply an unrelated full-suite waiver to this feature-focused gate.

The final focused rerun additionally includes `account_experience_test.rb`,
`chat_account_citations_test.rb`, `chat_account_url_race_test.rb`, and
`ruby_llm_mcp_generation_test.rb` after the observed full-suite failures. No
original focused file was dropped. Exact command: `final-focused-02.log` below.

- [x] **Step 3: Run the complete server suite, then the entire protected browser set, without shared-database concurrency.**

```bash
record_check /tmp/opencode/sources-workspace-final-full.log rails_test test
record_check /tmp/opencode/sources-workspace-final-browser.log browser_test test/system/sources_workspace_test.rb test/system/sources_workspace_upload_test.rb test/system/sources_dropzone_test.rb test/system/account_experience_test.rb test/system/localization_test.rb test/system/dashboard_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
```

Expected: browser exit 0. For the full server suite, compare the actual exit/failures with the fresh Task 0 baseline and the user's explicit acceptance, if any. A remaining accepted `Chat::RequestOptionsTest` error is still exit 1 and must be reported as such; new failures/errors block completion. Never skip a test, change unrelated behavior, or suppress warnings just to get a green headline.

- [x] **Step 4: Run lint and the security scanner with honest exits.**

```bash
record_check /tmp/opencode/sources-workspace-final-rubocop.log mise exec ruby@4.0.7 -- env RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app/helpers/sources_helper.rb app/helpers/sources_workspace_helper.rb app/helpers/source_forms_helper.rb app/controllers/concerns/source_scoped.rb app/models/concerns/sourceable.rb test/controllers/sources_workspace_shell_test.rb test/controllers/sources_workspace_filters_test.rb test/controllers/sources_workspace_rows_test.rb test/controllers/sources_workspace_forms_test.rb test/controllers/sources_workspace_details_test.rb test/controllers/accounts/scoped_sources_test.rb test/controllers/accounts/scoped_source_operations_test.rb test/system/sources_workspace_test.rb test/system/sources_workspace_upload_test.rb test/integration/localized_pages_test.rb test/system/chat_account_selection_test.rb
record_check /tmp/opencode/sources-workspace-final-brakeman.log mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
git diff --check
```

Expected: changed-file lint exit 0. Brakeman must have no new feature-introduced findings. Compare with a freshly saved baseline scanner result from Task 0, not only historical line numbers; existing EOL/`PermitAttributes` warnings retain their actual nonzero exit. Investigate any difference before requesting user acceptance. Do not update dependencies, suppress warnings, or claim a full `bin/ci` pass from this narrower command set.

The actual final lint command also includes `account_experience_test.rb` and
`chat_account_url_race_test.rb`, for eighteen changed Ruby files in total.

- [x] **Step 5: Review the implementation against the specification and test evidence.** Under subagent-driven execution, request independent spec-compliance and code-quality reviews with the execution base/HEAD, both specifications, this plan, true test exits, and evidence paths. Under inline execution, perform those two review passes explicitly before reporting. Resolve feature findings, rerun every affected gate under a new log name, and preserve the old failures. No review agent is spawned while merely writing this plan.

Acceptance checklist:

- [x] Both route families and all four source types have coherent list/new/edit/detail flows.
- [x] Default account, scoped membership isolation, ordinary member capabilities, 404/406/422 distinctions, HTML/JSON write contracts, content conversion, and queued jobs remain intact.
- [x] URL filters compose, page resets appropriately, Load more stays 50 rows, zero counts have seven unique targets, and account-wide versus loaded-match counts are labeled.
- [x] Rows show meaningful identity, type/status/chunks/time, separate View/Edit/Retry/Delete destinations, and source/account deletion confirmation without per-row account queries.
- [x] Existing browse/drop/retry/removal uses stable upload intent; Uploaded never promises Indexed; searched/live replacement limitations remain explicit.
- [x] Forms retain non-file values and legacy filing on 422, fix edit identity, explain file reselection, keep attachment-disabled native editors, and connect summary/inline errors with focus and pending Save feedback.
- [x] Details keep escaped Text/Q&A, allowlisted Website HTML, and the original document preview/link behavior; reads remain read-only.
- [x] Responsive/keyboard/contrast/light-dark/EN-FR/long-name/reduced-motion evidence was actually reviewed; native 200% zoom is separately verified or explicitly unverified.
- [x] No unrelated dashboard, composer, usage, Skills, or MCP change was smuggled into the shared foundation. The separate registry test-isolation correction was explicitly user-authorized, not a production behavior change.
- [x] Actual test/scanner counts, seeds, exits, accepted baseline exceptions, image-review scope, and remaining manual limits are recorded.

- [x] **Step 6: Record final evidence and prepare integration choices after verification.** Actual commands/results, acceptance decisions and review outcomes are recorded below and in the execution notes. Commit the tracking-only change explicitly, then present integration choices without choosing one on the user's behalf:

```bash
git add docs/superpowers/plans/2026-10-24-sources-workspace-ui-ux.md
git commit -m "docs(sources): Record verified workspace execution evidence"
git status --short
```

Invoke `finishing-a-development-branch` after implementation/review gates are satisfied to present integration options. Do not choose an option on the user's behalf. Later Token usage work still needs its independent detailed-design and written-spec approval gates.

### Final execution evidence — application HEAD `590b30c`

The first final full run was **not accepted**: 1,096 runs / 20,396 assertions,
seed 16727, five failures/twenty errors, exit 1. It exposed the drawer/citation
boundaries and the proven base registry leak described above. Evidence remains
in `/tmp/opencode/sources-workspace-final-full.log`; diagnosis and exact base
reproducer commands are in `sources-workspace-task8-registry-diagnosis-results.json`.

- `62ba58e`: separately user-authorized registry test isolation. Permanent guard
  RED 3 / 59 with one failure; race + MCP GREEN 25 / 256, seed 16727; formerly
  failing ordered chain GREEN 2 / 26; preinitialized control GREEN 2 / 27.
  Explicit cold/warm teardown-fault probes restored exact prior state.
- `590b30c`: Sources/citation boundary and drawer presentation correction.
  Boundary RED 47 / 1,286 with three failures; affected contracts GREEN
  210 / 14,263, seed 16727. Shared citation partial restored to base bytes;
  citation authorization/preview/CSP assertions were not edited.
- Commands ran sequentially with dedicated database, Ruby 4.0.7, fixtures/test
  queue and no performed ingestion/provider calls. All earlier failed logs remain.

| Final gate | Runs / assertions and outcome | Seed | True exit | Log under `/tmp/opencode/` |
| --- | --- | ---: | ---: | --- |
| Tailwind build | Successful, v4.1.16 | — | 0 | `sources-workspace-final-build-02.log` |
| Expanded focused | 407 / 16,282; no failures/errors/skips | 4013 | 0 | `sources-workspace-final-focused-02.log` |
| Full, failed-order seed | 1,097 / 20,639; 0 failures, 1 accepted error, no skips | 16727 | **1** | `sources-workspace-final-full-02.log` |
| Full, baseline seed | 1,097 / 20,642; 0 failures, 1 accepted error, no skips | 47125 | **1** | `sources-workspace-final-full-47125-02.log` |
| All eight browser files | 119 / 6,530; no failures/errors/skips | 50589 | 0 | `sources-workspace-final-browser-02.log` |
| Changed Ruby lint | 18 files, no offenses | — | 0 | `sources-workspace-final-rubocop-02.log` |
| Brakeman | 0 scanner errors, 2 unchanged baseline warnings | — | **3** | `sources-workspace-final-brakeman-02.log` |

The sole error in both full runs is exactly
`Chat::RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults`,
missing `augmented_context`, `app/models/chat/completionable.rb:39` →
`test/models/chat/request_options_test.rb:32` (test begins at 29). It remains an
error/exit 1, not a passing suite. Brakeman retains only API-token
`PermitAttributes` at `api_tokens_controller.rb:62` and Rails EOL at
`Gemfile.lock:318`, exit 3. Duplicate-key JSON warnings remain unsuppressed.
There is no new baseline waiver or claim of a full `bin/ci` pass.

Detailed commands, RED/GREEN provenance, commit hashes and all final log paths:
`/tmp/opencode/sources-workspace-task8-final-results-02.json`. Final browser
images and 278 contrast samples:
`/tmp/opencode/sources-workspace-883753/`. Eight fresh representative screenshots
were reviewed by the verifier; the parent additionally opened the mobile
document detail and Website 422 retained draft. Text/border/focus minima are
unchanged from Task 6 and exceed their thresholds. Native 200% zoom is still
**UNVERIFIED**, not replaced by emulation or a full manual-audit claim.

### Latest reviewed revision — application HEAD `d5f7661`

Whole-feature specification review found a remaining 24px-high row View/title
target. It is an independent action covered by the approved 44px minimum. Commit
`d5f7661` adds Sources-only minimum width/height and permanent coverage of all
four types, ordinary and one-character titles, both themes, keyboard/focus and
non-overlap. RED 1 / 11 failed on 24px; GREEN 1 / 645, seed 16727. All sixteen
measured View targets were 44px high, at least 101.36px wide, with no overlaps.

| Latest gate | Actual result | Seed | True exit | Log under `/tmp/opencode/` |
| --- | --- | ---: | ---: | --- |
| Build | Tailwind successful | — | 0 | `sources-workspace-final-build-03.log` |
| Expanded focused | 407 / 16,282; no failures/errors/skips | 32985 | 0 | `sources-workspace-final-focused-03.log` |
| Full | 1,097 / 20,639; 0 failures, only accepted RequestOptions error | 16727 | **1** | `sources-workspace-final-full-03.log` |
| All eight browser files | 120 / 7,287; no failures/errors/skips | 47806 | 0 | `sources-workspace-final-browser-03.log` |
| Changed Ruby lint | 18 files, no offenses | — | 0 | `sources-workspace-final-rubocop-03.log` |
| Brakeman | 0 errors, exactly 2 baseline warnings | — | **3** | `sources-workspace-final-brakeman-03.log` |

These checks ran on the exact working bytes committed as `d5f7661`; their logged
parent HEAD is `590b30c`, with tested-file hashes and commit matching recorded in
`/tmp/opencode/sources-workspace-task8-final-results-03.json`. The seed 47125 full
result above is **reused from revision 02**, not represented as newly run after
this CSS/system-test-only change. No server implementation changed between them.

Fresh evidence: `/tmp/opencode/sources-workspace-897127/`, 310 passing contrast
samples. The implementer and spec reviewer opened normal, short-title, ordinary
View and focused-row mobile screenshots; earlier complete representative reviews
remain valid historical evidence. Native 200% zoom remains **UNVERIFIED**.

Whole-feature specification reviewer `ses_e8cd1c7e6ffew1CzkCf8le1LLp` re-approved
`d5f7661`, independently rerunning the touch-target regression: 1 / 645, exit 0
(`/tmp/opencode/sources-workspace-whole-spec-rereview-d5f7661-view-targets.log`).
Whole-feature quality reviewer `ses_e8cb3fa00ffe1NDqfcFMtt2kwG` approved the
complete `8c3328e` → `d5f7661` feature with no remaining Critical, Important or
Minor findings. Independent request/citation/registry verification: 64 / 1,340,
exit 0. Independent browser CSRF/navigation/error-focus verification: 4 / 104,
exit 0. Logs:
`/tmp/opencode/sources-workspace-whole-quality-d5f7661-targeted.log` and
`/tmp/opencode/sources-workspace-whole-quality-d5f7661-browser.log`.

Both independent whole-feature reviews are approved. The final tracking commit
changes only this plan; application bytes remain those tested and reviewed at
`d5f7661`. The remaining decision is integration, not a new feature failure or a
claim that the full suite/scanner/native-zoom checks are green. Offer local merge,
push/PR, keep-as-is, or explicitly confirmed discard. Nothing has been merged,
pushed, submitted as a PR, or removed, and later Token usage design still needs
its own approval gates.

## Planning self-review

Completed during planning, before implementation:

| Approved requirement | Planned coverage |
| --- | --- |
| Shared neutral/green workspace, real account context, existing navigation, no unrelated drawer, no-membership setup | Task 1 |
| Composed URL type/status/query/sort, page reset, one navigation DOM, account-wide zero/nonzero counters | Task 2 |
| Readable responsive rows, actual status, independent actions, named confirmation, safe background rendering, browse/drop/retry feedback | Task 3 |
| All four new/edit forms, existing fields/conversion, fixed edit identity, retained legacy filing/non-file values, linked errors and Save state | Task 4 |
| Meaningful details, permitted-empty-content fallback, original file behavior, escaped/allowlisted source content, read-only GETs | Tasks 3 and 5 |
| Real browser workflows/live locales, responsive themes/languages, long labels, keyboard/touch/focus/contrast/motion, honest native-zoom limit | Task 6 |
| Documentation and unchanged scope/ingestion/live/format contracts | Task 7 |
| Fresh baseline and explicit acceptance, protected source/composer tests, full-suite/scanner exits, independent or inline reviews before integration | Tasks 0 and 8 |

Static checks parsed all 17 Ruby snippets and 39 ERB snippets, checked 26 shell
blocks and nine JavaScript modules/heredocs, verified seven paired YAML sections
for duplicate keys, identical leaves and interpolations, and resolved all 33
test-file references to existing or explicitly planned files. The plan's fences,
local specification links, task sequence, and placeholder scan were checked.
Helper/local interfaces and source path/format contracts were reviewed against
the checkout. The checks used temporary scripts outside the repository; they are
not a new application dependency or an execution prerequisite.

No application code, worktree, test database, Rails suite, application CSS build,
or application browser regression was created/run during planning. CSS utilities,
runtime behavior, tests, and screenshots above still require actual execution;
static checks do not establish that the redesigned application works.
