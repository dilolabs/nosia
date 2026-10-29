# Prompts, Members and API Tokens Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the approved Balanced workspace rollout while keeping prompts, account members and personal API tokens on separate pages.

**Architecture:** Install small, opt-in shared presentation primitives, then implement three independently testable resource slices. Existing controllers retain their authorization/query boundaries; targeted HTML recovery and token-reveal behavior change without redesigning models, authentication or API contracts.

**Tech Stack:** Actual checkout: Rails/ERB, Turbo/Stimulus, Importmap, Tailwind, PostgreSQL, Minitest/fixtures; use installed Ruby 4.0.7 for this environment. No packages or schema changes.

---

## Authority, order and boundaries

The user approved the [written specification](../specs/2026-10-28-prompts-members-tokens-ui-ux-design.md)
with **Go** after commit `9b8998bd960581a2a24ad808cdf30c83606fabed`.
This is planning, not execution approval. Do not run the commands/code below while
reviewing the plan. Select execution at the handoff first.

Use this order; the resource plans are separate because their domains are independent:

1. This plan: baseline and shared shell/primitives.
2. [Prompts](2026-10-28-prompts-workspace.md): five prompt page variants.
3. [Members](2026-10-28-account-members-workspace.md): owner-only membership.
4. [Personal tokens](2026-10-28-personal-api-tokens-workspace.md): global/account token pages.
5. [Verification](2026-10-28-settings-tools-verification.md): 128 states, workflows, docs and final gates.

Prompts/members/tokens may be reviewed independently, but do not run parallel
implementers or DB-sharing commands in the same execution worktree. Shared
fixture/header contracts below are prerequisites, not an instruction to merge
resource screens. No combined admin page, invitations, role editing, token scopes,
prompt runners, extra dependencies, database migrations or API authentication changes.

All failed-test attempts are retained. New unrelated regressions stop execution;
existing presentation assertions explicitly migrated by a resource plan must retain
their substantive coverage. Old MCP waivers do not authorize a nonzero new baseline.

## File structure and ownership

| Owner | Files / responsibility |
| --- | --- |
| Shared preparation | `app/helpers/settings_tools_helper.rb`: opt-in shell, trail, scope-safe New chat and field-error presentation |
| Shared preparation | `app/views/settings_tools/{_header,_feedback,_errors}.html.erb`: display only; no resource queries/forms |
| Shared preparation | `app/assets/stylesheets/nosia/settings_tools.css`, one Tailwind import: styles scoped to `.n-settings-tool` |
| Shared preparation | `config/locales/{en,fr}.nosia_settings_tools.yml`: all new owned copy; existing global labels remain intact |
| Shared preparation | Three layout guard additions and one mobile New chat branch; no other navigation changes |
| Shared preparation | `test/support/settings_tool_fixtures.rb`, `test/helpers/settings_tools_helper_test.rb`: reuse existing fixture sets |
| Shared preparation | `test/internationalization/catalogs_test.rb`: register the new explicit error-count plural without dropping existing keys |
| Prompts | `app/helpers/system_prompts_helper.rb`, five existing prompt views and two shared prompt partials; global update 422 only |
| Members | Existing membership controller/view and its form/row partials; no model/schema/permission changes |
| Tokens | Existing token controller/views plus `_created`/`_token`; scoped `token_reveal_controller.js`; no `ApiToken`/API authentication changes |
| Verification | Dedicated browser helper/system tests, targeted legacy assertion migrations, `docs/settings-tools-workspace.md` and docs index |

## Task 0: Fresh isolated baseline and durable recording

**Files:** only ignored execution evidence/recorder files in this task. No application changes.

- [ ] **Step 1: Establish an execution worktree from the reviewed planning commit.**

Run from this documentation worktree, after execution choice:

```bash
PLAN_BASE="$(git rev-parse HEAD)"
MAIN=/home/cbldev/gitd/dilolabs/nosia
WORKTREE="$MAIN/.worktrees/settings-tools-ui"
test ! -e "$WORKTREE"
! git show-ref --verify --quiet refs/heads/feat/settings-tools-ui
git -C "$MAIN" check-ignore -q .worktrees/settings-tools-ui
git worktree add -b feat/settings-tools-ui "$WORKTREE" "$PLAN_BASE"
cd "$WORKTREE"
git status --short
mise exec ruby@4.0.7 -- bundle check
command -v psql
command -v chromium
command -v chromedriver
git check-ignore -q .superpowers/settings-tools-evidence
mkdir -p .superpowers/settings-tools-evidence
git rev-parse HEAD > .superpowers/settings-tools-evidence/base-sha.txt
```

If any target is already used, prerequisite is absent or ignore check fails,
stop rather than overwrite/install. When this becomes the primary worktree, move
the harness session there. Keep main, MCP and documentation worktrees intact.

- [ ] **Step 2: Write the following ignored `.superpowers/settings-tools-env.sh`.**

```bash
export NOSIA_MAIN=/home/cbldev/gitd/dilolabs/nosia
export RUBOCOP_TARGET_RUBY_VERSION=4.0
export EVIDENCE="$PWD/.superpowers/settings-tools-evidence"
test -d "$EVIDENCE" || return 125
export BASE="$(< "$EVIDENCE/base-sha.txt")"
test_command() {
  mise exec ruby@4.0.7 -- bundle exec dotenv -f "$NOSIA_MAIN/.env" -- env -u DB_HOST \
    RAILS_ENV=test DATABASE_URL=postgresql:///nosia_settings_tools_ui_test \
    AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 "$@"
}
rails_test() { test_command bin/rails "$@"; }
browser_test() {
  test_command bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test "$@"
}
record() {
  local label="$1" log result fd
  shift
  log="$(mktemp "$EVIDENCE/$label.XXXXXX.log")" || return 125
  exec {fd}>"$log" || return 125
  if "$@" >&"$fd" 2>&1; then result=0; else result=$?; fi
  printf '%s\n' "$result" >"${log%.log}.exit" || return 125
  exec {fd}>&- || return 125
  tail -n 25 "$log" || return 125
  printf 'Evidence: %s (command exit %s)\n' "$log" "$result"
  return "$result"
}
```

Source it in **every** test shell. Do not display/read/source/copy `.env`; only
the nondisplaying dotenv invocation may consume it. Evidence lives on the worktree's
persistent filesystem, not only `/tmp`. Never run production workers/providers.

- [ ] **Step 3: Prepare only the new test database, after proving its name is unused.**

```bash
source .superpowers/settings-tools-env.sh
test -z "$(psql -d postgres -Atc "SELECT datname FROM pg_database WHERE datname = 'nosia_settings_tools_ui_test'")"
createdb nosia_settings_tools_ui_test
record baseline-prepare rails_test db:prepare
record baseline-db rails_test runner 'abort "wrong database" unless ActiveRecord::Base.connection.select_value("SELECT current_database()") == "nosia_settings_tools_ui_test"; puts "isolated test database verified"'
```

If the DB already exists, stop for ownership/isolation confirmation; never drop it
or silently reuse someone else's database. Missing pgvector/prerequisites require
user direction, not installation or substitution. No development DB copying is
needed: this checkout is PostgreSQL, not the generic SQLite stack description.

- [ ] **Step 4: Collect every baseline gate sequentially, retaining true exits.**

```bash
record baseline-build rails_test tailwindcss:build
record baseline-focused rails_test test test/controllers/system_prompts_controller_test.rb test/controllers/accounts/system_prompts_controller_test.rb test/controllers/accounts/administration_test.rb test/controllers/accounts/account_users_authorization_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/api_tokens_controller_test.rb test/models/api_token_test.rb test/integration/system_prompt_materialization_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record baseline-full rails_test test
record baseline-browser browser_test test/system/api_tokens_test.rb test/system/accounts_settings_workspace_test.rb test/system/account_experience_test.rb test/system/agent_skills_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/profile_management_test.rb test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb
record baseline-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/controllers/system_prompts_controller.rb app/controllers/accounts/system_prompts_controller.rb app/controllers/accounts/account_users_controller.rb app/controllers/api_tokens_controller.rb app/helpers/accounts_helper.rb test/controllers/system_prompts_controller_test.rb test/controllers/accounts/system_prompts_controller_test.rb test/controllers/accounts/administration_test.rb test/controllers/accounts/account_users_authorization_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/api_tokens_controller_test.rb test/system/api_tokens_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record baseline-security mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

These are separate commands, not a `set -e` script: collect the baseline even if
one gate is nonzero, then report exact failures/warnings, seeds, counts and raw
paths. No implementation until the user directs how to proceed with reproduced
nonzero results. Prior Chat/Profile/Brakeman findings are clues only. Copy any
new `/tmp/opencode/mcp-browser-*` baseline artifacts into the durable evidence
directory immediately after the gate; do not alter the protected MCP helper.

- [ ] **Step 5: Record baseline direction and review before source edits.**

Write `baseline-direction.md` in the evidence directory with the actual gate table,
identities/messages and verbatim user answer. If executing subagent-driven, use
independent baseline/spec then quality review. No tracked commit for this task.

## Task 1: Opt-in shared presentation primitives

**Create:** helper, shared partials, scoped stylesheet, paired locales and helper
test below. **Modify:** `app/views/layouts/application.html.erb` guards,
`app/views/application/_menu.html.erb` one branch,
`app/assets/tailwind/application.css` one import.

The shell is **opt-in through `content_for` in the rendered header**, not a
controller-family blanket switch. Thus this preparation commit does not remove
legacy headers/flash from resource pages before their own plan replaces them.

- [ ] **Step 1: Add the shared fixture adapter.**

`test/support/settings_tool_fixtures.rb`:

```ruby
require_relative "account_experience_fixtures"

module SettingsToolFixtures
  extend ActiveSupport::Concern
  include AccountExperienceFixtures

  included do
    setup do
      @shared = experience(:prompts, :overview_second_shared)
      @personal = experience(:prompts, :overview_second_personal)
      @own_token = experience(:api_tokens, :overview_second_token)
      @other_token = experience(:api_tokens, :overview_member_token)
      @outsider = experience(:users, :overview_outsider)
      @no_account = experience(:users, :overview_no_account)
    end
  end
end
```

This adapter reuses fixtures; do not add a second user factory, mutate global
fixture configuration or replace the existing teardown/tenant/job-adapter reset.

- [ ] **Step 2: Write the missing-header/helper test before production files.**

Also insert this exact line after `nosia.mcp.errors` in the existing
`CatalogsTest::PLURAL_PATHS` list in `test/internationalization/catalogs_test.rb`:

```ruby
    nosia.settings_tools.errors
```

This is a `%w[...]` list item, not standalone Ruby. Its test must first fail
because the new catalog plural is absent, then pass after adding both locales.

`test/helpers/settings_tools_helper_test.rb`:

```ruby
require "test_helper"
require_relative "../support/settings_tool_fixtures"

class SettingsToolsHelperTest < ActionView::TestCase
  include SettingsToolFixtures

  test "header opts in once and never gives a global page scoped navigation" do
    @account = @second
    request.path_parameters = { controller: "system_prompts", action: "index" }
    refute settings_tool_workspace_page?
    render partial: "settings_tools/header", locals: {
      title: "Owned title", trail: [ { label: "Owned title", path: nil } ]
    }
    assert settings_tool_workspace_page?
    assert_includes rendered, new_chat_path
    refute_includes rendered, new_chat_path(account_id: @second.id)
    assert_equal "Owned title", content_for(:title)
  end

  test "account route trail and new chat use the authorized URL account" do
    @account = @second
    request.path_parameters = { controller: "api_tokens", action: "index", account_id: @second.id }
    assert_equal new_chat_path(account_id: @second.id), settings_tool_new_chat_path
    trail = settings_tool_trail(resource: "Tokens", path: account_api_tokens_path(@second))
    assert_equal [ user_root_path, accounts_path, account_path(@second), nil ], trail.map { |item| item[:path] }
    assert_equal "Tokens", trail.last[:label]
    assert_equal @first, @user.reload.first_account
  end

  test "summary counts displayed items and escapes authored messages" do
    render partial: "settings_tools/errors", locals: { items: [
      { message: "<script>One</script>", target: "first" },
      { message: "Two", target: "second" }
    ] }
    assert_includes rendered, I18n.t("nosia.settings_tools.errors", count: 2)
    assert_includes rendered, 'data-error-field="first"'
    refute_includes rendered, "<script>"
  end
end
```

- [ ] **Step 3: Run RED, then add the complete helper/partials.**

```bash
source .superpowers/settings-tools-env.sh
record shared-red rails_test test test/helpers/settings_tools_helper_test.rb test/internationalization/catalogs_test.rb
```

Expected: missing settings-tool helper/partial, not a fixture/login error.

`app/helpers/settings_tools_helper.rb`:

```ruby
# Presentation-only conventions for the separately rendered Settings tools.
module SettingsToolsHelper
  # @return [Boolean] Whether this view has opted into its own workspace shell
  def settings_tool_workspace_page?
    content_for?(:settings_tool_workspace)
  end

  # @return [Boolean] Whether the existing route contains an account context
  def settings_tool_account_route?
    request.path_parameters.key?(:account_id)
  end

  # @return [String] Existing composer; never changes the user's default
  def settings_tool_new_chat_path
    settings_tool_account_route? ? new_chat_path(account_id: @account.id) : new_chat_path
  end

  # @param resource [String] Localized resource label
  # @param path [String] Existing resource index/read path
  # @param record [Hash, nil] Optional already-authorized detail ancestor
  # @param current [String, nil] Optional current Edit/detail label
  # @return [Array<Hash>] Linked ancestors followed by one plain current item
  def settings_tool_trail(resource:, path:, record: nil, current: nil)
    trail = [ { label: t("nosia.nav.home"), path: user_root_path } ]
    if settings_tool_account_route?
      trail += [ { label: t("nosia.nav.accounts"), path: accounts_path },
        { label: @account.name, path: account_path(@account) } ]
    else
      trail << { label: t("nosia.nav.settings"), path: settings_path }
    end
    trail << { label: resource, path: (record || current) ? path : nil }
    trail << record if record
    trail << { label: current, path: nil } if current
    trail
  end

  # @param record [ActiveRecord::Base] Invalid record; no values are serialized
  # @param targets [Hash{Symbol => String}] Only fields actually rendered by the form
  # @return [Array<Hash>] Escaped by the partial; uneditable errors have no link
  def settings_tool_errors(record, targets:)
    record.errors.map { |error| { message: error.full_message, target: targets[error.attribute] } }
  end

  # @param id [String] Rendered input ID
  # @param invalid [Boolean] Whether an inline error with this ID is rendered
  # @return [Hash] Connected help/error attributes
  def settings_tool_field_aria(id, invalid:)
    { invalid: invalid ? "true" : nil, describedby: "#{id}_help#{invalid ? " #{id}_error" : ''}" }
  end
end
```

`app/views/settings_tools/_header.html.erb`:

```erb
<%# locals: (title:, trail:, description: nil, scope_label: nil, actions: nil) %>
<% content_for :settings_tool_workspace, "true" %>
<% buttons = capture do %>
  <div class="hidden lg:block"><%= link_to t("nosia.nav.new_chat"), settings_tool_new_chat_path, class: "n-workspace-link" %></div>
  <%= actions %>
<% end %>
<%= render "workspaces/header", title: title, trail: trail, description: description, scope_label: scope_label, actions: buttons %>
```

`app/views/settings_tools/_feedback.html.erb`:

```erb
<% [ :notice, :alert ].each do |kind| %>
  <% if flash[kind].present? %><div class="n-settings-tool-message" role="<%= kind == :alert ? 'alert' : 'status' %>"><%= flash[kind] %></div><% end %>
<% end %>
```

`app/views/settings_tools/_errors.html.erb`:

```erb
<%# locals: (items:) %>
<% if items.any? %>
  <section class="n-settings-tool-errors" role="alert" tabindex="-1" data-form-errors-target="summary" aria-labelledby="settings-tool-errors-title">
    <h2 id="settings-tool-errors-title" class="n-workspace-section-title"><%= t("nosia.settings_tools.errors", count: items.size) %></h2>
    <ul class="!list-none" role="list"><% items.each do |item| %><li>
      <% if item[:target] %><%= link_to item[:message], "##{item[:target]}", class: "n-workspace-link", data: { error_field: item[:target] } %><% else %><%= item[:message] %><% end %>
    </li><% end %></ul>
  </section>
<% end %>
```

- [ ] **Step 4: Add scoped CSS and the two locale files.**

`app/assets/stylesheets/nosia/settings_tools.css`:

```css
.n-settings-tool { overflow-wrap: anywhere; }
.n-settings-tool [hidden] { display: none !important; }
.n-settings-tool .n-workspace-link { min-inline-size: 2.75rem; }
.n-settings-tool .n-workspace-link:hover { @apply bg-neutral-100 dark:bg-neutral-700; }
.n-settings-tool .n-workspace-button:not(.n-workspace-primary):hover { @apply bg-neutral-50 dark:bg-neutral-900; }
.n-settings-tool .n-workspace-button:disabled { opacity: 1; }
.n-settings-tool form { max-inline-size: 100%; }
.n-settings-tool-rows { @apply grid min-w-0 gap-4; }
.n-settings-tool-row { @apply flex min-w-0 flex-wrap items-center justify-between gap-4 rounded-xl border border-neutral-500 bg-white p-5 dark:bg-neutral-800; }
.n-settings-tool-row > :first-child { min-inline-size: 0; flex: 1 1 15rem; }
.n-settings-tool-badge { @apply inline-flex rounded-full border border-neutral-500 px-3 py-1 text-sm; }
.n-settings-tool-label { @apply mb-2 block text-base font-medium; }
.n-settings-tool-input { @apply block min-h-11 w-full min-w-0 rounded-md border border-neutral-500 bg-white px-3 py-2 text-base text-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:bg-neutral-800 dark:text-neutral-100 dark:focus:outline-green-300; }
.n-settings-tool-input[aria-invalid=true] { @apply border-red-700 dark:border-red-300; }
.n-settings-tool-editor { min-block-size: 20rem; resize: vertical; line-height: 1.75; }
.n-settings-tool-reading { max-inline-size: 80ch; white-space: pre-wrap; overflow-wrap: anywhere; @apply text-base leading-relaxed; }
.n-settings-tool-errors { @apply rounded-lg border border-red-700 bg-red-50 p-4 text-red-900 focus:outline-2 focus:outline-offset-2 focus:outline-red-700 dark:border-red-300 dark:bg-red-950 dark:text-red-200 dark:focus:outline-red-300; }
.n-settings-tool-error { @apply text-base text-red-800 dark:text-red-200; }
.n-settings-tool-message { @apply rounded-lg border border-neutral-500 bg-white p-4 text-base dark:bg-neutral-800; }
.n-settings-tool-form { @apply grid min-w-0 gap-5; }
.n-settings-tool-token-layout { @apply grid min-w-0 items-start gap-5 lg:grid-cols-[minmax(16rem,1fr)_minmax(0,2fr)]; }
.n-settings-tool-copy { @apply flex min-w-0 flex-wrap items-end gap-3; }
.n-settings-tool-copy > div { min-inline-size: 0; flex: 1 1 18rem; }
.n-settings-tool-reveal:focus { @apply outline-2 outline-offset-2 outline-green-700 dark:outline-green-300; }
main:has([data-settings-tool]) { min-width: 0; scroll-padding-block-start: .5rem; scroll-padding-block-end: 6rem; }
```

Insert immediately after the workspace import in `app/assets/tailwind/application.css`:

```css
@import "../stylesheets/nosia/settings_tools.css" layer(utilities);
```

`config/locales/en.nosia_settings_tools.yml`:

```yaml
en:
  nosia:
    settings_tools:
      errors:
        one: "1 error:"
        other: "%{count} errors:"
      required: Required
      saving: Saving…
      prompts_description: Review the instructions associated with your accounts.
      prompt_title: System prompt
      prompt_edit: Edit system prompt
      prompt_open: Open prompt
      prompt_edit_action: Edit prompt
      account_default: Account default
      user_specific: User-specific
      prompt_saved: Saved account prompt
      prompt_builtin: Built-in default
      prompt_fallback: This account has no saved default prompt. The built-in instructions are shown below; only a successful Save creates a saved account prompt.
      prompt_precedence: A user-specific prompt takes precedence over the account default.
      prompt_help: Edit plain text. Existing placeholders and formatting are retained; the content cannot be blank.
      prompts_empty: No saved system prompts
      prompts_empty_help: Open an account to review its saved or built-in default instructions.
      open_accounts: Open accounts
      members_title: Account members
      members_description: Manage membership for this account. Only its owner can add or remove members.
      add_existing: Add an existing user
      existing_user_help: Enter the email of someone who already has a Nosia user account. This does not send an invitation.
      email: Email address
      add_member: Add member
      adding_member: Adding member…
      remove_member: Remove member
      removing_member: Removing member…
      member_confirm: "Remove %{email} from %{account}? This removes their membership from this account, not their user account."
      member_unknown: No existing user was found for this email address.
      member_duplicate: This user already belongs to this account.
      member_failed: The member could not be added. Check the email and try again.
      owner: Owner
      you: You
      member: Member
      owner_protected: The owner cannot be removed.
      no_additional_members: No additional members yet. Add an existing user above to share this account.
      tokens_description: Create and revoke your personal API access tokens.
      personal_tokens: Your tokens
      create_token: Create a token
      token_name: Token name
      default_account: Default account
      account_help: Choose the default account for requests using this token.
      generate: Generate
      generating: Generating…
      revoke: Revoke token
      revoking: Revoking…
      revoke_confirm: "Revoke %{name} (default account: %{account})? Clients using this token will stop authenticating."
      token_removed: The API token has been revoked.
      created_title: Copy your new token now
      created_help: This value is shown only once and cannot be retrieved later. Store it securely before leaving this page.
      secret_label: New token value
      copy: Copy token
      copying: Copying…
      copied: Copied.
      copy_failed: Copying was not available. Select the value above and copy it manually.
      token_security: Saved token values cannot be retrieved. Revoke a token when it is no longer needed.
      tokens_empty: You have no API tokens yet.
      tokens_empty_account: You have no API tokens for this account.
      setup_account: Add an account
      setup_account_help: An account is needed before you can create a token. Existing personal tokens remain available below.
```

`config/locales/fr.nosia_settings_tools.yml`:

```yaml
fr:
  nosia:
    settings_tools:
      errors:
        one: "1 erreur :"
        other: "%{count} erreurs :"
      required: Obligatoire
      saving: Enregistrement…
      prompts_description: Consultez les instructions associées à vos comptes.
      prompt_title: Instructions système
      prompt_edit: Modifier les instructions système
      prompt_open: Ouvrir les instructions
      prompt_edit_action: Modifier les instructions
      account_default: Instructions par défaut du compte
      user_specific: Instructions propres à un utilisateur
      prompt_saved: Instructions enregistrées du compte
      prompt_builtin: Instructions intégrées par défaut
      prompt_fallback: Ce compte n’a pas d’instructions par défaut enregistrées. Les instructions intégrées sont affichées ci-dessous ; seul un enregistrement réussi crée les instructions du compte.
      prompt_precedence: Les instructions propres à un utilisateur priment sur celles du compte.
      prompt_help: Modifiez le texte brut. Les variables et la mise en forme sont conservées ; le contenu ne peut pas être vide.
      prompts_empty: Aucune instruction système enregistrée
      prompts_empty_help: Ouvrez un compte pour consulter ses instructions enregistrées ou intégrées.
      open_accounts: Ouvrir les comptes
      members_title: Membres du compte
      members_description: Gérez les membres de ce compte. Seul son propriétaire peut ajouter ou retirer des membres.
      add_existing: Ajouter un utilisateur existant
      existing_user_help: Saisissez l’adresse d’une personne ayant déjà un compte utilisateur Nosia. Aucune invitation n’est envoyée.
      email: Adresse e-mail
      add_member: Ajouter un membre
      adding_member: Ajout du membre…
      remove_member: Retirer le membre
      removing_member: Retrait du membre…
      member_confirm: "Retirer %{email} de %{account} ? Ce retrait concerne son appartenance à ce compte, pas son compte utilisateur."
      member_unknown: Aucun utilisateur existant ne correspond à cette adresse e-mail.
      member_duplicate: Cet utilisateur est déjà membre de ce compte.
      member_failed: Le membre n’a pas pu être ajouté. Vérifiez l’adresse et réessayez.
      owner: Propriétaire
      you: Vous
      member: Membre
      owner_protected: Le propriétaire ne peut pas être retiré.
      no_additional_members: Aucun autre membre pour le moment. Ajoutez un utilisateur existant ci-dessus pour partager ce compte.
      tokens_description: Créez et révoquez vos jetons personnels d’accès à l’API.
      personal_tokens: Vos jetons
      create_token: Créer un jeton
      token_name: Nom du jeton
      default_account: Compte par défaut
      account_help: Choisissez le compte par défaut des requêtes utilisant ce jeton.
      generate: Générer
      generating: Génération…
      revoke: Révoquer le jeton
      revoking: Révocation…
      revoke_confirm: "Révoquer %{name} (compte par défaut : %{account}) ? Les clients utilisant ce jeton ne pourront plus s’authentifier."
      token_removed: Le jeton API a été révoqué.
      created_title: Copiez votre nouveau jeton maintenant
      created_help: Cette valeur n’est affichée qu’une fois et ne peut pas être récupérée ensuite. Conservez-la en lieu sûr avant de quitter cette page.
      secret_label: Valeur du nouveau jeton
      copy: Copier le jeton
      copying: Copie…
      copied: Copié.
      copy_failed: La copie n’est pas disponible. Sélectionnez la valeur ci-dessus et copiez-la manuellement.
      token_security: Les valeurs des jetons enregistrés ne peuvent pas être récupérées. Révoquez les jetons devenus inutiles.
      tokens_empty: Vous n’avez pas encore de jeton API.
      tokens_empty_account: Vous n’avez pas de jeton API pour ce compte.
      setup_account: Ajouter un compte
      setup_account_help: Un compte est nécessaire pour créer un jeton. Vos jetons personnels existants restent disponibles ci-dessous.
```

- [ ] **Step 5: Make only these shared-layout/menu replacements.**

In `app/views/layouts/application.html.erb`, change the three opening guards only:

```erb
<%= render "flash" unless agent_skills_workspace_page? || mcp_workspace_page? || settings_tool_workspace_page? %>
```

```erb
<% unless agent_skills_workspace_page? || account_workspace_header? || mcp_workspace_page? || settings_tool_workspace_page? %>
```

```erb
<% if Current.user && !account_page? && !dashboard_page? && !sources_workspace_page? && !token_usage_workspace_page? && !agent_skills_workspace_page? && !settings_workspace_page? && !mcp_workspace_page? && !settings_tool_workspace_page? %>
```

In the existing `new_chat_shortcut` conditional in `app/views/application/_menu.html.erb`,
insert only this branch after the MCP branch and before its `else`:

```erb
elsif settings_tool_workspace_page?
  settings_tool_new_chat_path
```

Keep Skills/MCP precedence and every other class/icon/nav item/predicate/body.

- [ ] **Step 6: Verify GREEN/build/lint and commit only Task 1 paths.**

```bash
record shared-build rails_test tailwindcss:build
record shared-green rails_test test test/helpers/settings_tools_helper_test.rb test/controllers/settings_workspace_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/mcp_workspace_shell_test.rb test/internationalization/catalogs_test.rb
record shared-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/helpers/settings_tools_helper.rb test/helpers/settings_tools_helper_test.rb test/support/settings_tool_fixtures.rb test/internationalization/catalogs_test.rb
git diff --check
git add app/helpers/settings_tools_helper.rb app/views/settings_tools app/assets/stylesheets/nosia/settings_tools.css app/assets/tailwind/application.css config/locales/en.nosia_settings_tools.yml config/locales/fr.nosia_settings_tools.yml app/views/layouts/application.html.erb app/views/application/_menu.html.erb test/support/settings_tool_fixtures.rb test/helpers/settings_tools_helper_test.rb test/internationalization/catalogs_test.rb
git diff --cached --check
git commit -m "feat: Add opt-in presentation primitives for separate Settings tools"
```

Expected: helper tests pass, protected existing pages unchanged because no resource
view opts in yet. Verify public helper YARD against signatures, record tested
tree/commit, then spec and quality review before the resource plans. If an actual
Rails view-test API assumption fails, correct the test honestly with its raw
failure retained; do not fake a successful UI RED with fixture errors.

## Handoff

This plan plus its three resource plans and final verification plan forms one
ordered delivery set. Complete each resource's tests and commit/reviews before
advancing; it must work without depending on another resource's UI conversion.
Do not execute the verification plan until all three resource slices pass.

Planning self-review and the execution choice are recorded after all five plan
documents are complete. Application implementation has not started.

## Planning self-review and coverage ledger

This is a documentation review, not application verification. Self-review is
performed inline; no plan-review subagent or previous execution-method choice is
carried forward. The application tasks above remain unchecked deliberately.

| Specification requirement | Implementation / verification task |
| --- | --- |
| Eight dedicated variants; no combined management | P1 five prompt views, M1 member page, T1 two token variants; P1/M1/T1 separation assertions and V1 exact screen map |
| Single title, trail, route context, New chat, drawer isolation | Shared Task 1 opt-in shell/helper/menu; P1/T1 contextual requests; V1 native keyboard/layout; existing AccountExperience/Settings tests retained |
| Current prompt record set/order; truthful labels and literal text | P1 unchanged global query, row/read helper/partials and request checks; V1 long literal/placeholder content |
| Unsaved fallback, precedence, only explicit valid save | P1 request checks plus existing materialization/administration tests; V2 editor/empty workflows |
| Plain editor, native required, retained 422, inline/linked summary, Cancel/status | P1 editor/global failure branch; V2 actual submit/focus/Enter/Cancel; V1 layout/contrast |
| Owner-only existing-user membership; no invites, roles or deletion of users | M1 unchanged owner guard/model, retained lookup semantics and no-job/count/permission tests |
| Wrapping identity, static owner protection, contextual cancel/confirm | M1 row/owner-forgery tests; V1 long email and V2 real dialogs/DB outcomes |
| Unknown/duplicate email retained with focused recovery and no extra members state | M1 paired 422 tests/row state; V2 native email/summary/owner-only workflows |
| Global/scoped personal tokens; authorized default-account choices | T1 retained token/account methods, private-row tests and fixed/picker form; protected ScopedTokensUsage test migrations retain foreign/revoked/malformed coverage |
| Retained 422 creation; no-account versus empty states | T1 request and no-account-owned-token revocation checks; V2 native/422/empty workflows |
| Digest-only, same one-time handoff, labeled result/manual fallback | T1 unchanged model/success redirect and digest/authentication checks; T2 scoped clipboard with explicit promise outcomes and selection |
| No snapshot/refresh/app-Back reveal, no persistent secret storage | T1 result-only no-cache meta; T2 before-cache/pagehide clear and real refresh/breadcrumb/Back/storage tests; no secret value in evidence probe |
| Contextual revocation/status, cancellation and distinct busy states | T1 notices/confirmation; V2 actual cancel/accept and five held-submit busy labels; T2 copy busy/focus |
| English/French, light/dark, long strings, actual four viewports | Shared paired 61-key locale payload; V1 exact 128 completed Cartesian-product states, computed samples and PNGs |
| Native Tab/Shift+Tab/Enter, ≥44px actions, focus clearance, reduced motion | V1 isolated-session native traversal/probe and reduced-motion pass; V2 submit-result/field focus; T2 copy focus/manual selection |
| Text ≥4.5:1, nontext ≥3:1, genuine hover surfaces in both themes | V1 composed-color sampler, native hover before/after and both surfaces; V2 error and busy contrast samples |
| Fresh isolated baselines; no previous waiver; durable true exits | Task 0 unique PostgreSQL database, worktree/recorder/direction gate; V3 baseline comparison, manifests and persistent evidence |
| Protected regressions and precise presentation migrations | P1 Administration/SystemPrompts; M1 French lifecycle; T1 ScopedTokensUsage/Settings/French; T2 eight ApiTokens responsive cases and AccountExperience; V3 protected/full/browser/security/lint gates |
| YARD/docs/reviews; honest native-zoom/hardware limits | Shared public helpers/V1 helper YARD, V3 guide/index and two-stage review; native 200% zoom stays UNVERIFIED absent actual proof |
| No dependency/schema/API/permissions/default/unrelated changes or integration | Explicit path ownership and V3 empty protected-source diff; no merge/push/PR/cleanup commands |

Inline review corrected the explicit plural-key registry, protected prompt tests'
duplicate Edit expectations, scoped-token headings/global 422 expectations,
AccountExperience one-time-output selectors/redaction and copy-focus preservation.
Helper signatures, resource screen names, field/error IDs, fixture names and
route-helper names were checked across all five plans and the current checkout.
No known uncovered specification requirement or implementation placeholder remains.

Static-only checks cover Ruby syntax (complete snippets plus explicitly wrapped
branch/list fragments), Rails Erubi-generated template syntax, standalone/embedded
JS parsing, shell syntax, YAML parsing, locale-key/interpolation parity, plan/spec
links and exact command paths. The installed Node parser is used only for syntax
checking plan text; it is not an application/runtime dependency. These checks
cannot prove Rails requests, rendered layout, clipboard behavior or test results.
Raw planning output is retained in ignored `.superpowers/settings-tools-plan-checks.json`.

For execution-time verification of the introduced Markdown links, run this
standalone command (no Rails boot) after creating the V3 guide:

```bash
ruby <<'RUBY'
paths = Dir["docs/superpowers/plans/2026-10-28-*.md"] + [
  "docs/superpowers/specs/2026-10-28-prompts-members-tokens-ui-ux-design.md",
  "docs/settings-tools-workspace.md"
]
errors = paths.flat_map do |path|
  text = File.read(path).gsub(/^```[^\n]*\n.*?^```\s*$/m, "")
  text.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.filter_map do |target|
    next if target.match?(/\A(?:https?:|#)/)
    resolved = File.expand_path(target.split("#").first, File.dirname(path))
    "#{path}: #{target}" unless File.exist?(resolved)
  end
end
errors << "Missing docs index entry" unless File.read("docs/README.md").include?("[Separate Settings Tools Workspaces](settings-tools-workspace.md)")
abort errors.join("\n") unless errors.empty?
puts "Introduced documentation links verified"
RUBY
```

Execution still waits for the user's new choice: **Subagent-Driven** or **Inline
Execution**. Planning approval is not permission to run the application tasks.
