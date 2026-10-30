# Orbite Premium Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved Orbite shell, personal chat-history column, premium conversation surfaces and always-accessible non-overlay composer without changing existing chat capabilities or authorization.

**Architecture:** Keep one shared signed-in shell and one authoritative navigation/history panel. Present that same native dialog in normal flow on wide chat pages and in the top layer on smaller screens; reuse the existing dialog controller as the sole modal/focus owner. Give the chat context/transcript an explicit primary scroll target above the reserved composer and adapt only the existing reader's surface wiring, not its intent/anchor algorithm.

**Tech Stack:** Existing Rails/ERB, Minitest/fixtures, Turbo/Stimulus, importmap/Propshaft, Ruby-native Tailwind and installed Chromium. No new dependency, route, model, persistence or generation protocol.

---

## Approval, workspace and safety

The user approved the written specification at `f1b03b7` with “Oui”; this plan does not itself start implementation. Authoritative spec: [`2026-10-30-premium-chat-experience-design.md`](../specs/2026-10-30-premium-chat-experience-design.md). Application baseline: `7189d6de425122120f3fb4d7090d16a9ebb88f11`; `f1b03b7` adds only the spec. Later planning metadata/doc commits are not an application baseline change.

Use the existing isolated worktree:

```text
/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui
```

Every shell must specify that cwd. Leave user-owned `.env` and `bin/dev` web/CSS/worker processes untouched. Do not read/copy dotenv contents, inspect/control development processes, create/reset databases, install packages/drivers, start workers, contact live AI/MCP/crawl/index services, or run the unsafe unrestricted suite. The already approved helper loads dotenv without displaying it, then overrides the effective test configuration; it is not a network sandbox.

Before each **execution** test/build/lint shell:

```bash
source /tmp/opencode/chat-workspace-env.sh
export ORBITE_SOURCE_SHA="$(git rev-parse HEAD)"
```

The existing `record`, `rails_test`, `browser_test` and `test_command` functions write fresh logs and actual exit files under `/tmp/opencode/chat-workspace-hqSpCt`. They select `RAILS_ENV=test`, `DATABASE_URL=postgresql:///nosia_chat_workspace_ui_test`, a dummy AI key, one worker, Ruby 4.0.7 and installed local Chrome/driver. Keep `RUBOCOP_TARGET_RUBY_VERSION=4.0`. Run DB/browser commands sequentially. Await original background completion notifications; never poll/sleep or launch an overlapping group.

Only the previously accepted GET `/login` waiting-scaffold error, two exact Brakeman fingerprints and narrow Turbo-native ID focus-restoration race remain exceptions. No new failure, warning or focus exception is automatically accepted. Native browser zoom, screen readers, physical/mobile-keyboard behavior, live integrations and unsafe full-suite execution remain separate checks, never inferred from CSS/CDP measurements.

Each task follows tests/characterization → actual RED when behavior is missing → minimal implementation → GREEN → exact-file commit → SPEC then QUALITY review. Do not advance with open Important/Critical findings. No automatic merge, push, PR or cleanup.

## File structure and ownership

| Unit | Create/modify | Responsibility |
| --- | --- | --- |
| History content | New `app/views/chats/_history_items.html.erb`; existing `_history.html.erb` | Extract authorized items from their old dialog wrapper; publish existing request-supplied locals to the shell |
| Shared utilities | New `app/views/application/_orbite_utilities.html.erb`; existing `_header.html.erb` | Preserve one native locale/theme/profile control set; public header reuses it |
| Shared navigation | New `app/views/application/_orbite_links.html.erb`, `_orbite_shell.html.erb`; layout body | Existing destinations, one native panel and a 64px rail; no history query in layout |
| Navigation presentation | New `app/javascript/controllers/workspace_navigation_controller.js` | Width mode, transient history expansion and delegated panel actions only |
| Modal/focus ownership | Existing `app/javascript/controllers/chat_dialog_controller.js` | One owner for navigation and Tools, current-opener fallback and cache/layout cleanup |
| Shell styles | New `app/assets/stylesheets/nosia/orbite_shell.css`; Tailwind import | Signed-in tokens/grid/native panel/controls; retain public-shell CSS |
| Conversation styles | New `app/assets/stylesheets/nosia/orbite_chat.css`; Tailwind import | Reading measure, open assistant prose, reserved dock and scoped native-editor bounds |
| Conversation markup | Existing `app/views/chats/new.html.erb`, `show.html.erb`, `_header.html.erb` | One reading surface containing context/transcript, separate composer |
| Composer navigation | Existing `app/views/chats/_form.html.erb`, `_composer.html.erb`, `app/views/messages/_form.html.erb` | Optional explicit navigation local; saved worker-rendered form passes it without Current |
| Reader wiring | Existing `app/javascript/controllers/scroll_controller.js` | Explicit surface target and root-scoped input listeners; preserve measured ledger/anchors |
| Copy | New `config/locales/en.nosia_orbite.yml`, `fr.nosia_orbite.yml` | Paired navigation/utility labels, not new product language |
| New checks | New `test/integration/orbite_shell_test.rb`, `test/system/orbite_workspace_test.rb`, `test/support/orbite_browser_checks.rb` | Shared-shell/privacy contracts and real layout/native-navigation evidence |
| Migrations | Existing request/system/helper files named in Tasks 3, 5 and 6 | Intentionally superseded placement contracts only; preserve unrelated assertions |
| Docs | New `docs/orbite-workspace.md`; existing docs index/chat/composer/compact-header guides | Current ownership and historical-versus-current verification boundaries |

Keep `app/views/chats/_transcript.html.erb`, role/message partials, models/jobs/controllers/routes/schema and feedback/disclosure business behavior unchanged. Do not delete the now-unused legacy menu/sidebar files as collateral cleanup. Do not rewrite the reader's 80px/paragraph/content-change/own-submit logic. If real browser evidence requires an additional production correction, stop for explicit bounded-path authorization and its own RED→GREEN/review.

### Chosen implementation detail: a single responsive native panel

Use `dialog#chat-history` as the single panel on signed-in pages. On chat pages ≥1280px its `open` property exposes it **non-modally in the grid** (`position: static`, no `showModal()` and no autofocus). At 768–1279px it starts closed and opens modally. Below 768px it includes app links and history in the same modal. Other pages have no history items or reserved history column; the rail's utility button can open their navigation/utility modal.

Native locale/theme/profile controls exist once inside that panel, accessible from the rail's utility entry or mobile opener. This preserves their IDs without moving/duplicating them during morphs. Inline history includes the utility area; collapsed history can be opened from the persistent rail entry. Only `chat-dialog` performs `showModal`, close/focus restoration and layout-driven native-dialog cleanup. The navigation controller delegates through a Stimulus outlet on the same shell root.

Retain `#application-scroll[data-application-scroll]` as the **actual** primary surface on every page: it is non-chat `main`, but a child of the chat workspace containing context/transcript on chat pages. Chat `main` itself is `#application-page` and non-scrolling. This preserves most existing measurement queries while intentionally changing placement. No reader lookup may assume that the primary surface remains an ancestor of the controller root.

## Task 0: Establish the approved isolated before checkpoint

**Files:** External evidence only; no application edits.

- [ ] **Step 1: Confirm ownership and the current source.**

```bash
git status --short
git rev-parse HEAD
git log -5 --oneline
```

Expect only approved spec/plan documentation above the application baseline. Investigate unfamiliar changes without resetting/deleting them. Record the current SHA to a new `orbite-baseline-sha.txt`; do not overwrite a different prior checkpoint.

- [ ] **Step 2: Confirm the effective dedicated target without exposing credentials.**

```bash
record orbite-before-database test_command bin/rails runner 'abort "not test" unless Rails.env.test?; name = ActiveRecord::Base.connection_db_config.database; abort "wrong database" unless name == "nosia_chat_workspace_ui_test"; puts "test / #{name}"'
```

Expect exactly the test target and exit 0. No `db:create`, migrate, reset or fixture loading outside the selected tests.

- [ ] **Step 3: Run fresh existing selections sequentially.**

```bash
record orbite-before-build rails_test tailwindcss:build
record orbite-before-contracts rails_test test test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_url_race_test.rb test/internationalization/catalogs_test.rb
record orbite-before-chat browser_test test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb
```

Require actual summaries and exit pairs, not historical counts. The preceding approved final run was 215 chat/browser tests; record the current run's actual count rather than predicting equality. Any new failure blocks implementation until classified. Do not include the known unsafe full suite.

- [ ] **Step 4: Write the external checkpoint report and pass SPEC→QUALITY.**

Write `/tmp/opencode/chat-workspace-hqSpCt/orbite-task0-report.md` with SHA, explicit cwd/helper/DB proof, exact commands, exits, counts/seeds and the existing environment/process boundary. Capture the current normal saved/new screenshots through their existing tests; label historical measurements separately. No application commit for this task.

## Task 1: Extract authorized history content and unchanged utilities

**Files:**
- Create `app/views/chats/_history_items.html.erb`.
- Modify `app/views/chats/_history.html.erb`.
- Create `app/views/application/_orbite_utilities.html.erb`.
- Modify `app/views/application/_header.html.erb`.
- Create `test/integration/orbite_shell_test.rb`.

- [ ] **Step 1: Add passing characterization before extraction.**

Start the new test file with existing fixtures and assertions, preserving server-side privacy independently of future desktop/mobile presentation:

```ruby
require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class OrbiteShellTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "history keeps personal roots current item and existing delete confirmation" do
    get chat_path(@chat)
    assert_response :success
    assert_select "[data-history-chat='#{@chat.id}']", count: 1 do
      assert_select "a[href='#{chat_path(@chat)}'][aria-current=page]", count: 1
      assert_select "form[action='#{chat_path(@chat)}'] [name=_method][value=delete]", count: 1
      assert_select "[data-turbo-confirm]", count: 1 do |controls|
        assert_equal I18n.t("nosia.actions.confirm_delete"), controls.first["data-turbo-confirm"]
      end
    end
    [ workspace(:chats, :workspace_peer_chat), workspace(:chats, :workspace_child_chat), chats(:picker_foreign_chat) ].each do |excluded|
      assert_select "[data-history-chat='#{excluded.id}']", count: 0
    end
    assert_select "##{dom_id(@chat, :token_totals)}", count: 1
  end

  test "native utility identities and logout method remain unique" do
    get chat_path(@chat)
    %w[theme-toggle theme-toggle-dark-icon theme-toggle-light-icon language_preference_locale dropdownUser dropdown].each do |id|
      assert_select "[id='#{id}']", count: 1
    end
    assert_select "form[action='#{language_preference_path}'] [name=_method][value=patch]", count: 1
    assert_select "a[href='#{logout_path}'][data-turbo-method=delete]", count: 1
    assert_select "a[href='#{profile_path}']", minimum: 1
  end
end
```

```bash
record orbite-extraction-characterization rails_test test test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb
```

Expected PASS before extraction. The confirmation assertion accepts its existing generated control location but requires its exact localized message; no confirmation placement or behavior is changed.

- [ ] **Step 2: Create the history-content partial.**

Move the existing help/list/empty body into the following strict-local partial. No model query, new title source or changed URL:

```erb
<%# locals: (chat:, conversations:, titles:) %>
<p class="n-workspace-help"><%= t("nosia.chat_workspace.history_help") %></p>
<% if conversations.any? %>
  <ul class="n-chat-history-list !list-none">
    <% conversations.each do |conversation| %>
      <li class="n-chat-history-row" data-history-chat="<%= conversation.id %>">
        <div>
          <%= link_to chat_workspace_title(conversation, titles: titles), chat_path(conversation),
            class: "n-workspace-link", aria: { current: conversation == chat ? "page" : nil } %>
          <p class="n-workspace-help"><%= conversation.account.name %></p>
          <p class="n-workspace-help">
            <time datetime="<%= conversation.updated_at.iso8601 %>"><%= l(conversation.updated_at, format: :short) %></time>
            <% if conversation == chat %><span><%= t("nosia.chat_workspace.current") %></span><% end %>
          </p>
        </div>
        <%= button_to t("nosia.nav.delete_chat"), chat_path(conversation), method: :delete,
          class: "n-workspace-button n-workspace-danger", data: { turbo_confirm: t("nosia.actions.confirm_delete") } %>
      </li>
    <% end %>
  </ul>
<% else %>
  <p class="n-workspace-help" data-history-empty><%= t("nosia.chat_workspace.no_history") %></p>
<% end %>
```

In `_history.html.erb`, keep its current `tag.dialog`, attributes, title and Close header exactly, replacing its body after that header with:

```erb
<%= render "chats/history_items", chat: chat, conversations: conversations, titles: titles %>
```

- [ ] **Step 3: Extract the existing utility controls without changing their lifecycle.**

Copy the current `_header.html.erb` lines 7–43 (language render, theme button/icons, signed-in user button and menu) into `_orbite_utilities.html.erb`. This is the complete replacement utility body:

```erb
<%= render "language_preference" %>
<button id="theme-toggle" type="button" class="n-nav-link n-main-hover">
  <span class="sr-only"><%= t("nosia.nav.toggle_dark_mode") %></span>
  <%= inline_svg "svg/moon.svg", id: "theme-toggle-dark-icon", aria_hidden: true, class: "hidden h-6 w-6" %>
  <%= inline_svg "svg/sun.svg", id: "theme-toggle-light-icon", aria_hidden: true, class: "hidden h-6 w-6" %>
</button>
<% if Current.user %>
  <button id="dropdownUser" data-dropdown-toggle="dropdown" data-dropdown-placement="top-end"
          aria-expanded="false" class="n-nav-link n-main-hover flex shrink-0 rounded-full">
    <span class="sr-only"><%= t("nosia.nav.open_user_menu") %></span>
    <%= inline_svg "svg/user-circle.svg", aria_hidden: true, class: "w-6 h-6" %>
  </button>
  <div id="dropdown" class="hidden n-dropdown-menu border n-main-border">
    <ul aria-labelledby="dropdownUser" class="n-dropdown-list">
      <li><%= link_to profile_path, class: "group n-dropdown-item n-main-hover n-main-focus" do %>
        <%= inline_svg "svg/identification.svg", aria_hidden: true, class: "w-6 h-6" %>
        <span><%= t("nosia.nav.user_info") %></span>
      <% end %></li>
      <li><%= link_to settings_path, class: "group n-dropdown-item n-main-hover n-main-focus" do %>
        <%= inline_svg "svg/cog.svg", aria_hidden: true, class: "w-6 h-6" %>
        <span><%= t("nosia.nav.settings") %></span>
      <% end %></li>
      <li><%= link_to logout_path, data: { turbo_method: :delete }, title: t("nosia.nav.sign_out"), class: "group n-dropdown-item n-main-hover n-main-focus" do %>
        <%= inline_svg "svg/power.svg", aria_hidden: true, class: "w-6 h-6" %>
        <span><%= t("nosia.nav.sign_out") %></span>
      <% end %></li>
    </ul>
  </div>
<% end %>
```

Preserve the current header's outer nav/logo. Replace only its second controls div with:

```erb
<div class="flex flex-wrap items-center gap-2"><%= render "application/orbite_utilities" %></div>
```

The menu's corrected `aria-labelledby` references its existing trigger; the upward placement will be verified physically, not assumed. No dark-mode controller rewrite.

- [ ] **Step 4: Verify the extraction and commit exact paths.**

```bash
record orbite-extraction-green rails_test test test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/compact_headers_test.rb
record orbite-extraction-lint test_command bundle exec rubocop test/integration/orbite_shell_test.rb
git diff --check
git add -- app/views/chats/_history_items.html.erb app/views/chats/_history.html.erb app/views/application/_orbite_utilities.html.erb app/views/application/_header.html.erb test/integration/orbite_shell_test.rb
git commit -m "refactor(ui): Extract history items and native utilities"
```

Pass SPEC→QUALITY before the structural cutover.

## Task 2: Build the shared shell and single responsive navigation owner

**Files:** New `app/views/application/_orbite_links.html.erb`, `_orbite_shell.html.erb`, `app/javascript/controllers/workspace_navigation_controller.js`, `app/assets/stylesheets/nosia/orbite_shell.css`, paired `config/locales/{en,fr}.nosia_orbite.yml`; modify layout, `_history.html.erb`, `_header.html.erb` chat trigger, `chat_dialog_controller.js`, Tailwind import and new request test. This task also creates the helper/browser files printed in Steps 9–10 and applies Task 5's test-only navigation migrations.

**Test-first ordering:** The complete new helper and browser-test source is printed in Steps 9–10. Prepare those files together with Step 1, then run both `orbite-shell-red` and `orbite-shell-native-red` **before any Step 2–6 production edit**. Steps 9–10 are source listings for that initial test preparation, not permission to postpone browser RED. The whole structural task remains one implementation/review unit.

- [ ] **Step 1: Add the missing shared-shell request contract and run RED.**

Append inside `OrbiteShellTest`:

```ruby
test "signed in pages share one rail panel and unique native utilities" do
  [ user_root_path, accounts_path, account_path(@second), sources_path, token_usage_path,
    settings_path, profile_path, account_agent_skills_path(@second), account_mcp_servers_path(@second),
    api_tokens_path, system_prompts_path, new_chat_path, chat_path(@chat) ].each do |path|
    get path
    assert_response :success
    assert_select "#orbite-shell[data-controller~='workspace-navigation'][data-controller~='chat-dialog']", count: 1
    assert_select ".n-orbite-rail", count: 1
    assert_select "dialog#chat-history:not([open])", count: 1
    assert_select "main", count: 1
    assert_select "#theme-toggle, #language_preference_locale, #dropdownUser", count: 3
    assert_select "[data-application-header], .n-nav-bottom, #accordion-right-actions, #drawer-right", count: 0
    composer = if [ account_agent_skills_path(@second), account_mcp_servers_path(@second) ].include?(path)
      new_chat_path(account_id: @second.id)
    else
      new_chat_path
    end
    assert_select "#chat-history a[href='#{composer}']", minimum: 1
    assert_select "[data-history-chat]", count: 0 unless [ new_chat_path, chat_path(@chat) ].include?(path)
  end
end

test "signed out retains branding native controls and no private panel" do
  delete logout_path
  get root_path
  assert_response :success
  assert_select "[data-application-header]", count: 1
  assert_select "#theme-toggle, #language_preference_locale", count: 2
  assert_select "#orbite-shell, #chat-history, [data-history-chat], #dropdownUser", count: 0
  assert_select "form[action='#{login_path}']", count: 1
end
```

```bash
record orbite-shell-red rails_test test test/integration/orbite_shell_test.rb
record orbite-shell-native-red browser_test test/system/orbite_workspace_test.rb
```

Expect missing `#orbite-shell`/new structure, not routing/setup errors. The signed-out case can already pass.

- [ ] **Step 2: Add paired labels and reusable existing links.**

```yaml
# config/locales/en.nosia_orbite.yml
en:
  nosia:
    orbite:
      navigation: Navigation
      utilities: Appearance and profile
      collapse_history: Collapse history
      expand_history: Show history
```

```yaml
# config/locales/fr.nosia_orbite.yml
fr:
  nosia:
    orbite:
      navigation: Navigation
      utilities: Apparence et profil
      collapse_history: Replier l’historique
      expand_history: Afficher l’historique
```

Create `_orbite_links.html.erb`:

```erb
<%# locals: (compact: false) %>
<% new_chat_shortcut = if agent_skills_workspace_page?
  skill_workspace_new_chat_path
elsif mcp_workspace_page?
  mcp_new_chat_path
else
  new_chat_path
end %>
<% [ [root_path, "home", "home"], [new_chat_shortcut, "chats", "new_chat"],
     [accounts_path, "folders", "accounts"], [sources_path, "file-search", "sources"],
     [token_usage_path, "chart-bar", "token_usage"], [settings_path, "cog", "settings"] ].each do |path, icon, key| %>
  <%= link_to path, class: "n-orbite-link", aria: { label: t("nosia.nav.#{key}") }, title: t("nosia.nav.#{key}") do %>
    <%= inline_svg "svg/#{icon}.svg", aria_hidden: true, class: "h-5 w-5" %>
    <span class="<%= 'sr-only' if compact %>"><%= t("nosia.nav.#{key}") %></span>
  <% end %>
<% end %>
```

- [ ] **Step 3: Create the shared shell partial.**

```erb
<%# locals: (page:) %>
<div id="orbite-shell" class="n-orbite-shell"
     data-controller="chat-dialog workspace-navigation"
     data-workspace-navigation-chat-dialog-outlet="#orbite-shell"
     data-workspace-navigation-history-value="<%= chat_workspace_page? %>"
     data-action="turbo:before-cache@document->workspace-navigation#beforeCache turbo:before-cache@document->chat-dialog#beforeCache turbo:render@document->workspace-navigation#layout turbo:before-morph-attribute@document->workspace-navigation#preserve">
  <nav class="n-orbite-rail" aria-label="<%= t('nosia.orbite.navigation') %>">
    <%= link_to root_path, class: "n-orbite-logo", aria: { label: t("nosia.nav.home_page") } do %>
      <%= image_tag "nosia-logo.png", alt: "", aria: { hidden: true } %>
    <% end %>
    <%= render "application/orbite_links", compact: true %>
    <button type="button" id="workspace-history-rail-trigger" class="n-orbite-control"
            aria-controls="chat-history" aria-expanded="false"
            data-workspace-navigation-target="trigger" data-action="workspace-navigation#toggle">
      <%= inline_svg "svg/menu.svg", aria_hidden: true, class: "h-5 w-5" %>
      <span class="sr-only"><%= t("nosia.orbite.expand_history") %></span>
    </button>
    <button type="button" id="workspace-utilities-trigger" class="n-orbite-control n-orbite-utilities-trigger"
            aria-controls="chat-history" aria-haspopup="dialog" data-action="workspace-navigation#utilities">
      <%= inline_svg "svg/user-circle.svg", aria_hidden: true, class: "h-6 w-6" %>
      <span class="sr-only"><%= t("nosia.orbite.utilities") %></span>
    </button>
  </nav>

  <dialog id="chat-history" class="n-orbite-navigation" aria-labelledby="chat-history-title"
          data-workspace-navigation-target="panel" <%= 'data-history-empty=true' if content_for?(:orbite_history_empty) %>
          data-action="close->chat-dialog#closed close->workspace-navigation#closed">
    <header class="n-orbite-panel-heading">
      <%= link_to root_path, class: "n-orbite-logo", aria: { label: t("nosia.nav.home_page") } do %>
        <%= image_tag "nosia-logo.png", alt: "", aria: { hidden: true } %>
      <% end %>
      <h2 id="chat-history-title"><%= t("nosia.orbite.navigation") %></h2>
      <button type="button" class="n-orbite-control" autofocus data-action="workspace-navigation#close"><%= t("nosia.chat_workspace.close") %></button>
    </header>
    <div class="n-orbite-panel-content">
      <nav class="n-orbite-panel-links" aria-label="<%= t('nosia.orbite.navigation') %>"><%= render "application/orbite_links" %></nav>
      <% if content_for?(:orbite_history) %>
        <section aria-label="<%= t('nosia.chat_workspace.history_title') %>" data-orbite-history>
          <h3 class="n-orbite-history-heading"><%= t("nosia.chat_workspace.history_title") %></h3>
          <%= content_for :orbite_history %>
        </section>
      <% end %>
    </div>
    <div class="n-orbite-utilities" aria-label="<%= t('nosia.orbite.utilities') %>"><%= render "application/orbite_utilities" %></div>
  </dialog>

  <%= tag.main id: "application-scroll", class: "n-application-page n-orbite-main #{'n-chat-main' if chat_workspace_page?}", data: { application_scroll: true } do %>
    <%= render "flash" unless agent_skills_workspace_page? || mcp_workspace_page? %>
    <div class="n-orbite-page-trail">
      <% unless agent_skills_workspace_page? || account_workspace_header? || mcp_workspace_page? || chat_workspace_page? %>
        <% if account_page? && @account %>
          <%= render "accounts/breadcrumb", account: @account, title: content_for(:account_tool_title) %>
        <% else %>
          <%= render "navbar" %>
        <% end %>
      <% end %>
    </div>
    <% unless chat_workspace_page? %>
      <button type="button" id="workspace-mobile-trigger" class="n-orbite-control n-orbite-mobile-only"
              aria-controls="chat-history" aria-haspopup="dialog" data-workspace-navigation-target="trigger" data-action="workspace-navigation#toggle"><%= t("nosia.orbite.navigation") %></button>
    <% end %>
    <%= page %>
  <% end %>
</div>
```

This task temporarily leaves the existing chat scroll placement intact; Task 3 performs its explicit target cutover. The sole primary marker moves then, not in two separate partial implementations. The New chat destination reuses the existing MCP/Skills scoped-path helpers; never replace it with an unscoped global shortcut on those pages.

In layout, preserve the entire `<head>` and body dark-mode controller. Replace its signed-in body contents with `render "application/orbite_shell", page: capture { yield }`. The complete new body is:

```erb
<body data-controller="dark-mode" class="h-dvh flex flex-col overflow-hidden bg-neutral-100 dark:bg-neutral-900 dark:text-white">
  <% if Current.user %>
    <%= render "application/orbite_shell", page: capture { yield } %>
  <% else %>
    <div id="application-scroll" class="n-application-scroll" data-application-scroll>
      <%= render "flash" %>
      <%= render "application/header" %>
      <main class="n-application-page"><%= yield %></main>
    </div>
  <% end %>
</body>
```

Remove the old layout's invocations of `menu` and legacy chat drawers, not their source files. No model lookup is introduced.

Replace `_history.html.erb` completely with the strict-local content publisher:

```erb
<%# locals: (chat:, conversations:, titles:) %>
<% content_for :orbite_history do %>
  <%= render "chats/history_items", chat: chat, conversations: conversations, titles: titles %>
<% end %>
<% content_for :orbite_history_empty, "true" if conversations.empty? %>
```

Remove `chat-dialog` from both chat workspace `data-controller` lists and remove only `turbo:before-cache@document->chat-dialog#beforeCache` from their action lists; the shell now owns it once. Preserve every other action, target and status attribute. In the chat header, keep the existing History button text/shape/URL context but change its ID/action to:

```erb
<button type="button" id="workspace-history-trigger" class="n-workspace-button"
        aria-controls="chat-history" aria-expanded="false" data-workspace-navigation-target="trigger"
        data-action="workspace-navigation#toggle"><%= t("nosia.chat_workspace.history") %></button>
```

- [ ] **Step 4: Extend the existing modal owner; do not add a second focus restorer.**

Replace `chat_dialog_controller.js` with:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() { this.openers = new Map(); this.caching = false }

  open(event) {
    event.preventDefault()
    this.openDialog(document.getElementById(event.params.id), event.currentTarget)
  }

  openDialog(dialog, opener) {
    if (!dialog || !this.element.contains(dialog)) return
    this.caching = false
    this.openers.set(dialog.id, { element: opener, id: opener?.id })
    this.element.querySelectorAll("dialog:modal").forEach(item => { if (item !== dialog) item.close() })
    if (!dialog.matches(":modal")) {
      if (dialog.open) dialog.close()
      dialog.showModal()
    }
  }

  close(event) { event.preventDefault(); this.closeDialog(event.target.closest("dialog")) }

  closeDialog(dialog, fallback = null) {
    if (!dialog) return
    if (!this.openers.has(dialog.id) && fallback) this.openers.set(dialog.id, { element: fallback, id: fallback.id })
    dialog.close()
  }

  closed(event) {
    if (event.target.open) return
    const entry = this.openers.get(event.target.id)
    let opener = entry?.element
    if (!opener?.isConnected && entry?.id) opener = document.getElementById(entry.id)
    if (!opener?.isConnected && entry) {
      const id = CSS.escape(event.target.id)
      opener = this.element.querySelector(`[data-chat-dialog-id-param="${id}"][aria-controls="${id}"]`)
    }
    if (!this.caching && !this.element.querySelector("dialog:modal") && opener?.isConnected) opener.focus()
    this.openers.delete(event.target.id)
  }

  reconfigure(dialog, configure, fallback) {
    const active = document.activeElement, inside = dialog.contains(active)
    this.openers.delete(dialog.id)
    if (dialog.open) dialog.close()
    configure()
    if (active?.isConnected && active.checkVisibility()) {
      if (document.activeElement !== active) active.focus({ preventScroll: true })
    } else if (inside && fallback?.isConnected) {
      fallback.focus({ preventScroll: true })
    }
  }

  focus(element) { element?.focus() }

  beforeCache() {
    this.caching = true
    this.openers.clear()
    this.element.querySelectorAll("dialog[open]").forEach(dialog => dialog.close())
  }
}
```

The owner closes only top-layer dialogs when opening Tools/navigation; it does not collapse an inline desktop history panel. Stable opener IDs precede the existing Tools-selector fallback after background form replacement. `reconfigure` owns focus across responsive changes; navigation code must not call `focus()` independently.

- [ ] **Step 5: Add the focused navigation presentation controller.**

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "trigger"]
  static values = { history: Boolean }
  static outlets = ["chat-dialog"]

  connect() {
    this.caching = false
    this.expanded = this.element.dataset.orbiteHistoryExpanded !== "false"
    this.wide = matchMedia("(min-width: 1280px)")
    this.mobile = matchMedia("(max-width: 767px)")
    this.changed = () => this.layout()
    this.wide.addEventListener("change", this.changed)
    this.mobile.addEventListener("change", this.changed)
    this.layout()
  }

  disconnect() {
    this.wide.removeEventListener("change", this.changed)
    this.mobile.removeEventListener("change", this.changed)
  }

  get desiredMode() { return this.historyValue && this.wide.matches ? "inline" : this.mobile.matches ? "mobile" : "modal" }

  layout() {
    if (!this.wide || !this.mobile || !this.hasChatDialogOutlet || !this.hasPanelTarget) return
    const mode = this.desiredMode
    if (mode !== this.mode) {
      this.chatDialogOutlet.reconfigure(this.panelTarget, () => {
        this.panelTarget.dataset.inline = String(mode === "inline")
        this.panelTarget.open = mode === "inline" && this.expanded
      }, this.fallback())
      this.mode = mode
    } else if (mode === "inline" && !this.panelTarget.matches(":modal")) {
      this.panelTarget.open = this.expanded
    }
    this.reflect()
  }

  chatDialogOutletConnected() { this.layout() }
  triggerTargetConnected() { if (this.mode) this.reflect() }

  toggle(event) {
    event.preventDefault()
    this.caching = false
    if (this.mode === "inline") {
      this.expanded = !this.panelTarget.open
      this.chatDialogOutlet.reconfigure(this.panelTarget, () => { this.panelTarget.open = this.expanded }, this.fallback())
    } else {
      this.chatDialogOutlet.openDialog(this.panelTarget, event.currentTarget)
    }
    this.reflect()
  }

  utilities(event) {
    event.preventDefault()
    this.caching = false
    if (this.mode === "inline") { this.expanded = true; this.panelTarget.open = true }
    else this.chatDialogOutlet.openDialog(this.panelTarget, event.currentTarget)
    this.reflect()
    this.chatDialogOutlet.focus(this.panelTarget.querySelector("#dropdownUser"))
  }

  close(event) {
    event.preventDefault()
    this.chatDialogOutlet.closeDialog(this.panelTarget, this.fallback())
  }

  closed() {
    if (this.caching || this.panelTarget.open) return
    if (this.mode === "inline") this.expanded = false
    this.reflect()
  }

  fallback() {
    return this.triggerTargets.find(element => {
      const box = element.getBoundingClientRect()
      return element.checkVisibility() && box.top >= 0 && box.bottom <= innerHeight
    }) || this.element.querySelector("#workspace-utilities-trigger")
  }

  reflect() {
    this.element.dataset.orbiteNavigationMode = this.mode
    this.element.dataset.orbiteHistoryExpanded = String(this.expanded)
    this.triggerTargets.forEach(button => {
      button.setAttribute("aria-expanded", String(this.panelTarget.open))
      if (this.mode === "inline") button.removeAttribute("aria-haspopup")
      else button.setAttribute("aria-haspopup", "dialog")
    })
  }

  preserve(event) {
    if (event.target === this.panelTarget && ["open", "data-inline"].includes(event.detail.attributeName)) event.preventDefault()
  }

  beforeCache() {
    this.caching = true
    this.element.dataset.orbiteHistoryExpanded = String(this.expanded)
  }
}
```

The initial outlet-connected callback can precede `connect`; `layout()` guards its media queries before reading `desiredMode`. This is a lifecycle guard, not a timer. State stays on the current page, not in localStorage. Do not register a second native modal controller on chat roots.

- [ ] **Step 6: Add shell CSS and import it after `application_shell.css`.**

```css
.n-orbite-shell {
  --orbite-shell: #eef1eb; --orbite-paper: #fcfdf9; --orbite-text: #26332a;
  --orbite-muted: #5b685e; --orbite-line: #cfd8cb; --orbite-control: #71806f;
  --orbite-accent: #335940; --orbite-on-accent: #fff; --orbite-bubble: #e9eee5;
  display: grid; grid-template-columns: 4rem minmax(0, 1fr); grid-template-rows: minmax(0, 1fr);
  flex: 1; min-height: 0; min-width: 0; padding: .75rem; gap: .5rem;
  overflow: hidden; background: var(--orbite-shell); color: var(--orbite-text);
}
.dark .n-orbite-shell {
  --orbite-shell: #171e18; --orbite-paper: #232b23; --orbite-text: #e5ede1;
  --orbite-muted: #aebda7; --orbite-line: #3e4b39; --orbite-control: #819176;
  --orbite-accent: #c2dcb4; --orbite-on-accent: #1d301d; --orbite-bubble: #34432e;
}
.n-orbite-shell:has(> .n-orbite-navigation[data-inline=true][open]) { grid-template-columns: 4rem 15rem minmax(0, 1fr); }
.n-orbite-rail { display: flex; flex-direction: column; align-items: center; gap: .375rem; min-height: 0; overflow-y: auto; padding: .25rem; }
.n-orbite-logo, .n-orbite-control, .n-orbite-link { display: inline-flex; align-items: center; justify-content: center; gap: .5rem; min-width: 2.75rem; min-height: 2.75rem; border-radius: .625rem; }
.n-orbite-logo { padding: .25rem; background: #fff; }
.n-orbite-logo img { max-width: 2.5rem; height: auto; }
.n-orbite-control { border: 0; padding: .5rem; background: transparent; color: var(--orbite-text); cursor: pointer; }
.n-orbite-link { padding: .5rem; color: var(--orbite-muted); text-decoration: none; }
.n-orbite-control:hover, .n-orbite-link:hover { background: var(--orbite-bubble); color: var(--orbite-text); }
.n-orbite-utilities-trigger { margin-top: auto; }
.n-orbite-shell .n-orbite-main { min-height: 0; min-width: 0; overflow-y: auto; padding: 1rem; background: var(--orbite-paper); border: 1px solid var(--orbite-line); border-radius: 1.25rem; scroll-padding-block: .75rem 2rem; }
.n-orbite-shell .n-orbite-page-trail > ul { margin-block: 0 .75rem; }
.n-orbite-navigation { width: min(24rem, calc(100vw - 1.5rem)); max-height: calc(100dvh - 1.5rem); padding: 1rem; border: 1px solid var(--orbite-control); border-radius: 1rem; background: var(--orbite-paper); color: var(--orbite-text); }
.n-orbite-navigation[open] { display: flex; flex-direction: column; }
.n-orbite-navigation:not([open]) { display: none; }
.n-orbite-navigation:modal { position: fixed; }
.n-orbite-navigation::backdrop { background: rgb(0 0 0 / .6); }
.n-orbite-navigation[data-inline=true][open] { position: static; grid-column: 2; width: 15rem; max-width: none; height: 100%; max-height: none; margin: 0; padding: .5rem; border: 0; border-radius: 0; background: transparent; }
.n-orbite-shell:has(> .n-orbite-navigation[data-inline=true][open]) > main { grid-column: 3; }
.n-orbite-panel-heading { display: flex; justify-content: space-between; align-items: center; gap: .5rem; flex: none; }
.n-orbite-panel-heading h2, .n-orbite-history-heading { font-size: .875rem; font-weight: 600; }
.n-orbite-panel-content { min-height: 0; overflow: auto; flex: 1; padding-block: .5rem; }
.n-orbite-panel-links { display: grid; margin-bottom: 1rem; }
.n-orbite-panel-links .n-orbite-link { justify-content: flex-start; }
.n-orbite-navigation[data-inline=true] .n-orbite-panel-links { display: none; }
.n-orbite-utilities { display: flex; flex-wrap: wrap; gap: .5rem; flex: none; align-items: center; padding-top: .75rem; border-top: 1px solid var(--orbite-line); }
.n-orbite-utilities :is(#theme-toggle, #dropdownUser, #language_preference_locale) { min-height: 2.75rem; min-width: 2.75rem; border-radius: .375rem; }
.n-orbite-utilities #language_preference_locale { font-size: .75rem; padding-block: .25rem; }
.n-orbite-shell :is(a, button, select, summary):focus-visible { outline: 2px solid var(--orbite-accent); outline-offset: -2px; }
.n-orbite-mobile-only { display: none; }
@media (max-width: 767px) {
  .n-orbite-shell { grid-template-columns: minmax(0, 1fr); padding: .5rem; gap: 0; }
  .n-orbite-rail { display: none; }
  .n-orbite-mobile-only { display: inline-flex; }
  .n-orbite-shell .n-orbite-main { padding: .75rem; border-radius: .875rem; }
}
@media (prefers-reduced-motion: reduce) {
  .n-orbite-shell *, .n-orbite-shell *::before, .n-orbite-shell *::after { animation: none !important; transition: none !important; scroll-behavior: auto !important; }
}
```

```css
@import "../stylesheets/nosia/orbite_shell.css";
```

At this checkpoint existing chat scroll CSS still applies; no fixed composer is claimed yet. Actual contrast/hit measurements may require a scoped token correction after valid browser RED; do not assume these seed tokens have been measured.

- [ ] **Step 7: Verify syntax and run the new request contract before migrating old placement assertions.**

```bash
record orbite-shell-build rails_test tailwindcss:build
record orbite-shell-requests rails_test test test/integration/orbite_shell_test.rb test/integration/chat_message_rendering_test.rb test/internationalization/catalogs_test.rb
record orbite-navigation-js node --input-type=module --check < app/javascript/controllers/workspace_navigation_controller.js
record orbite-dialog-js node --input-type=module --check < app/javascript/controllers/chat_dialog_controller.js
```

The old request assertions demanding exactly one History trigger or the old global bar are intentionally migrated in Step 8. Their failures are not application GREEN. Steps 8–11 belong to this same task/implementer/commit; do not hand an unverified structural cutover to another task.

- [ ] **Step 8: Migrate only the superseded request placement contracts.**

In `test/integration/compact_headers_test.rb`, replace the first test with:

```ruby
test "application pages retain one primary surface and all native utilities" do
  [ user_root_path, accounts_path, account_path(@second), sources_path, token_usage_path,
    settings_path, profile_path, account_agent_skills_path(@second), account_mcp_servers_path(@second),
    new_chat_path, chat_path(@chat) ].each do |path|
    get path
    assert_response :success
    assert_select "#orbite-shell", count: 1
    assert_select "#application-scroll[data-application-scroll]", count: 1
    assert_select "main", count: 1
    assert_select ".n-orbite-rail > .n-orbite-logo[href='#{root_path}'][aria-label] img[alt=''][aria-hidden=true]", count: 1
    assert_select "#theme-toggle", count: 1
    assert_select "#language_preference_locale", count: 1
    assert_select "#dropdownUser", count: 1
    assert_select "[data-application-header]", count: 0
  end
end
```

Leave its signed-out case and the description/Usage data/role contracts intact. Keep the toolbar History trigger assertion pointed at `#workspace-history-trigger`.

The complete mechanical request-selector migrations are:

| Files | Replace | With |
| --- | --- | --- |
| `test/controllers/chat_workspace_test.rb`, `test/controllers/dashboards_controller_test.rb` | `button[aria-controls=chat-history]` in the exactly-one trigger assertion | `button#workspace-history-trigger[aria-controls=chat-history]` |
| `test/controllers/sources_workspace_shell_test.rb`, `settings_workspace_test.rb`, `token_usage_workspace_shell_test.rb` | `button[aria-controls='chat-history'][data-action='chat-dialog#open']` | `button#workspace-history-trigger[aria-controls='chat-history'][data-action='workspace-navigation#toggle']` |
| `test/controllers/settings_workspace_test.rb`, `token_usage_workspace_shell_test.rb` | API-token/system-prompt legacy drawer count `2` | count `0`, plus existing-page primary actions and global New chat availability |

Also migrate `test/controllers/agent_skills_workspace_shell_test.rb` and `test/controllers/mcp_workspace_shell_test.rb`'s unrelated-page drawer counts from 2 to 0 with the same no-history/New-chat assertions. In `settings_workspace_test.rb` replace only `.lg\\:hidden a[href='#{new_chat_path}']` navigation availability selectors with `#chat-history .n-orbite-panel-links a[href='#{new_chat_path}']`. In `mcp_workspace_shell_test.rb`, replace `.lg\\:hidden a.n-nav-bottom[aria-label=?]` with `#chat-history .n-orbite-panel-links a[aria-label=?]`; preserve the exact `composer` URL comparison, membership/default assertions and escaped-secret checks. Rename drawer-retention test descriptions to reflect replacement by the shared navigation, not the retained legacy drawer. These files are included in this task's exact-file ownership/commit.

For each non-chat legacy-drawer loop add the following, preserving all surrounding authorization/scoped action assertions:

```ruby
assert_select "#accordion-right-actions, #drawer-right", count: 0
assert_select "#orbite-shell .n-orbite-rail a[href='#{new_chat_path}']", count: 1
assert_select "#chat-history [data-history-chat]", count: 0
```

Do not change the empty-history, personal-root exclusion, revocation, escaped-title/full-transcript, source/settings/MCP links, worker rendering or token-count assertions. These selectors migrate presentation ownership, not permissions.

- [ ] **Step 9: Add a standalone browser-support module.**

Create `test/support/orbite_browser_checks.rb`:

```ruby
require "json"
require "tmpdir"

module OrbiteBrowserChecks
  private
    def orbite_viewport(width, height)
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      page.current_window.resize_to(width, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
      orbite_settle
    end

    def orbite_settle
      page.evaluate_async_script("const done=arguments[arguments.length-1]; requestAnimationFrame(()=>requestAnimationFrame(done))")
    end

    def orbite_record(label, sample, screenshot: false)
      @orbite_evidence ||= Dir.mktmpdir("orbite-", ENV.fetch("EVIDENCE", Dir.tmpdir))
      context = page.evaluate_script("({path:location.pathname,query:location.search,locale:document.documentElement.lang,theme:document.documentElement.classList.contains('dark')?'dark':'light',viewport:[innerWidth,innerHeight]})")
      payload = context.merge("sourceCommit" => ENV.fetch("ORBITE_SOURCE_SHA", "UNRECORDED"), "label" => label, "sample" => sample)
      File.open(File.join(@orbite_evidence, "measurements.jsonl"), "a") { |file| file.puts(payload.to_json) }
      page.save_screenshot(File.join(@orbite_evidence, "#{label}-#{SecureRandom.hex(4)}.png")) if screenshot
      puts "Orbite evidence: #{@orbite_evidence}"
    end

    def orbite_open_utilities
      return if page.has_selector?("#theme-toggle", wait: 0)
      selectors = [ "[data-orbite-composer-navigation]", "#workspace-mobile-trigger", "#workspace-utilities-trigger", "#workspace-history-trigger" ]
      opener = selectors.filter_map { |selector| first(selector, wait: 0) }.first
      assert opener, "No operable Orbite navigation opener"
      opener.click
      assert_selector "#theme-toggle"
    end

    def orbite_close_navigation
      if page.has_selector?("#chat-history:modal", wait: 0)
        find("#chat-history [data-action='workspace-navigation#close']").click
        assert_no_selector "#chat-history:modal", visible: :all
      end
    end

    def orbite_with_utilities
      hidden_before = !page.has_selector?("#theme-toggle", wait: 0)
      previous_url = page.current_url
      orbite_open_utilities
      yield
    ensure
      if hidden_before && page.current_url == previous_url
        if page.has_selector?("#chat-history:modal", wait: 0)
          orbite_close_navigation
        elsif page.has_selector?("#chat-history[data-inline=true][open]", wait: 0)
          find("#workspace-history-rail-trigger").click
        end
      end
    end

    def orbite_select_language(label)
      if page.has_selector?("#orbite-shell", wait: 0)
        orbite_with_utilities { select label, from: "language_preference_locale" }
      else
        select label, from: "language_preference_locale"
      end
    end

    def orbite_theme(dark)
      if page.evaluate_script("document.documentElement.classList.contains('dark')") != dark
        orbite_with_utilities { find("#theme-toggle").click }
      end
      assert_equal dark, page.evaluate_script("document.documentElement.classList.contains('dark')")
      orbite_settle
    end

    def orbite_assert_reachable(selector)
      sample = page.evaluate_script(<<~JS, find(selector))
        (()=>{const e=arguments[0],r=e.getBoundingClientRect(),s=getComputedStyle(e);
          const points=[[r.x+r.width/2,r.y+r.height/2],[r.x+r.width/2,r.top+2],[r.x+r.width/2,r.bottom-2],[r.left+2,r.y+r.height/2],[r.right-2,r.y+r.height/2]];
          const hits=points.map(([x,y])=>{const h=document.elementFromPoint(x,y);return !!h&&(h===e||e.contains(h))});
          return {bounds:r.toJSON(),hits,viewport:[innerWidth,innerHeight],focusVisible:e.matches(':focus-visible'),outline:parseFloat(s.outlineWidth)};})()
      JS
      orbite_record("reachability", { selector: selector, measurement: sample })
      rect = sample.fetch("bounds")
      assert_operator rect.fetch("left"), :>=, 0, sample.to_json
      assert_operator rect.fetch("right"), :<=, sample.fetch("viewport").first + 1, sample.to_json
      assert_operator rect.fetch("top"), :>=, 0, sample.to_json
      assert_operator rect.fetch("bottom"), :<=, sample.fetch("viewport").last + 1, sample.to_json
      assert sample.fetch("hits").all?, sample.to_json
      sample
    end

    def orbite_tab_to(selector, reverse: false)
      160.times do
        if reverse
          page.driver.browser.action.key_down(:shift).send_keys(:tab).key_up(:shift).perform
        else
          page.driver.browser.action.send_keys(:tab).perform
        end
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          orbite_settle
          sample = orbite_assert_reachable(selector)
          assert sample.fetch("focusVisible"), sample.to_json
          assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
          return
        end
      end
      flunk "Native traversal did not reach #{selector}"
    end
end
```

The `UNRECORDED` source fallback permits ordinary CI without undeclared environment requirements; final execution evidence must supply `ORBITE_SOURCE_SHA`. No test helper may call `.focus()` or `scrollIntoView()` to claim native traversal.

- [ ] **Step 10: Add native navigation browser cases.**

Create `test/system/orbite_workspace_test.rb`:

```ruby
require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class OrbiteWorkspaceSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include OrbiteBrowserChecks

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(*@original_size) if @original_size
  end

  test "wide history is inline and collapse does not replace the editor" do
    orbite_viewport(1400, 1000)
    visit chat_path(@chat)
    assert_selector "#chat-history[data-inline=true][open]"
    refute page.evaluate_script("document.querySelector('#chat-history').matches(':modal')")
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep the actual editor")
    page.execute_script("window.orbiteEditor=document.querySelector('lexxy-editor')")
    find("#workspace-history-rail-trigger").click
    assert_no_selector "#chat-history[open]", visible: :all
    assert_selector "#workspace-history-rail-trigger[aria-expanded=false]"
    find("#workspace-history-rail-trigger").click
    assert_selector "#chat-history[data-inline=true][open]"
    assert page.evaluate_script("window.orbiteEditor===document.querySelector('lexxy-editor')")
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep the actual editor"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "tablet and mobile use one native panel and preserve its node through resize" do
    orbite_viewport(375, 812)
    visit new_chat_path(account_id: @second.id)
    assert_selector "#chat-history:not([open])", visible: :all
    find("#workspace-history-trigger").click
    assert_selector "#chat-history:modal"
    page.execute_script("window.orbitePanel=document.querySelector('#chat-history')")
    orbite_tab_to("#language_preference_locale")
    orbite_tab_to("#chat-history [data-action='workspace-navigation#close']", reverse: true)
    orbite_viewport(768, 1024)
    assert_no_selector "#chat-history:modal", visible: :all
    assert page.evaluate_script("window.orbitePanel===document.querySelector('#chat-history')")
    find("#workspace-history-rail-trigger").click
    assert_selector "#chat-history:modal"
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#chat-history[open]", visible: :all
    assert_selector "#workspace-history-rail-trigger:focus"
    orbite_viewport(1400, 1000)
    assert_selector "#chat-history[data-inline=true][open]"
    refute page.evaluate_script("document.querySelector('#chat-history').matches(':modal')")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "utilities operate natively and other pages have no history items" do
    orbite_viewport(375, 812)
    visit accounts_path
    orbite_select_language("FR")
    assert_selector "html[lang=fr]"
    orbite_theme(true)
    orbite_open_utilities
    assert_selector "#chat-history:modal"
    assert_no_selector "[data-history-chat]", visible: :all
    orbite_tab_to("#dropdownUser")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#dropdown:not(.hidden)"
    orbite_tab_to("#dropdown a[href='#{profile_path}']")
    page.driver.browser.action.send_keys(:enter).perform
    assert_current_path profile_path
    assert_selector "main h1", text: I18n.t("nosia.profile.title", locale: :fr)
    assert_selector "html.dark[lang=fr]"
    assert_no_enqueued_jobs only: ChatResponseJob
  end
end
```

These tests must exist and fail before production cutover, in the ordering stated at the start of this task. Avoid claiming wide nonmodal history has modal focus containment; only tablet/mobile do.

- [ ] **Step 11: Complete the atomic shell gate and commit.**

Apply **Task 5 Steps 1–4 now**, before this gate; they are fully specified test-only migrations coupled to the shell cutover, not a later green-fixing allowance. Record their files in this same task's ownership/commit. Task 5 then retains only its broad verification/review step. Task 3 must not depend on an unspecified future setup migration.

```bash
record orbite-shell-native browser_test test/system/orbite_workspace_test.rb
record orbite-shell-contracts-green rails_test test test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/controllers/dashboards_controller_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/integration/chat_message_rendering_test.rb test/internationalization/catalogs_test.rb
record orbite-shell-existing-native browser_test test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
record orbite-shell-lint test_command bundle exec rubocop test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/controllers/dashboards_controller_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/support/orbite_browser_checks.rb test/system/orbite_workspace_test.rb
git diff --check
```

Require no missing controls, stacked modals, hidden focus, duplicate IDs or authorization regression. Confirm the same native panel node survives responsive changes and actual editor/draft survive history toggles. Commit exactly this task's changed paths (the Task 2 list plus its named helper/browser/request migrations), using `feat(ui): Introduce the Orbite shared navigation shell`. Record the explicit staged file list in the external report. Pass SPEC→QUALITY before Task 3.

## Task 3: Reserve the composer and retarget the existing reader atomically

**Files:** `app/views/chats/new.html.erb`, `show.html.erb`, `_form.html.erb`, `_composer.html.erb`, `app/views/messages/_form.html.erb`, `app/views/application/_orbite_shell.html.erb`, `app/javascript/controllers/scroll_controller.js`, new `app/assets/stylesheets/nosia/orbite_chat.css`, Tailwind import, `test/system/orbite_workspace_test.rb`, `test/system/chat_workspace_test.rb`, `test/support/chat_workspace_browser_checks.rb`, `test/system/chat_workspace_layout_test.rb`; request renderer tests retain all existing data assertions.

- [ ] **Step 1: Add geometry/identity RED before moving the surface.**

Append to `OrbiteWorkspaceSystemTest`:

```ruby
test "context scrolls away while the real composer remains visible in every viewport" do
  @second.update_columns(name: "CompteDeRecherche" * 12)
  [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
    orbite_viewport(width, height)
    visit chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Draft must stay in this editor")
    page.execute_script("window.orbiteDockEditor=document.querySelector('lexxy-editor')")
    page.execute_script(<<~JS)
      const surface=document.querySelector('[data-application-scroll]')
      surface.scrollTop=0; surface.dispatchEvent(new Event('scroll'))
    JS
    orbite_settle
    before = page.evaluate_script("document.querySelector('.n-chat-dock').getBoundingClientRect().toJSON()")
    page.execute_script(<<~JS)
      const surface=document.querySelector('[data-application-scroll]')
      surface.scrollTop=700; surface.dispatchEvent(new Event('scroll'))
    JS
    orbite_settle
    sample = page.evaluate_script(<<~JS)
      (()=>{const rect=s=>document.querySelector(s).getBoundingClientRect().toJSON();
        return {surface:rect('[data-application-scroll]'),header:rect('.n-chat-header'),dock:rect('.n-chat-dock'),
          top:document.querySelector('[data-application-scroll]').scrollTop,
          nested:[document.querySelector('main').scrollTop,document.querySelector('.n-chat-transcript').scrollTop],
          sameEditor:window.orbiteDockEditor===document.querySelector('lexxy-editor'),viewport:[innerWidth,innerHeight]};})()
    JS
    orbite_record("dock-#{width}x#{height}", sample, screenshot: true)
    assert_operator sample.fetch("top"), :>=, 699, sample.to_json
    assert_operator sample.fetch("header").fetch("bottom"), :<=, sample.fetch("surface").fetch("top"), sample.to_json
    assert_in_delta before.fetch("top"), sample.fetch("dock").fetch("top"), 1, sample.to_json
    assert_operator sample.fetch("surface").fetch("bottom"), :<=, sample.fetch("dock").fetch("top") + 1, sample.to_json
    assert_operator sample.fetch("dock").fetch("bottom"), :<=, height, sample.to_json
    assert_equal [ 0, 0 ], sample.fetch("nested"), sample.to_json
    assert sample.fetch("sameEditor"), sample.to_json
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Draft must stay in this editor"
    orbite_assert_reachable(".n-composer-send")
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end

test "mobile navigation remains usable after the context has scrolled away and during generation" do
  orbite_viewport(375, 812)
  @chat.start_generation!
  visit chat_path(@chat)
  assert_button "Stop generating", enable_aria_label: true
  assert_selector "[data-orbite-composer-navigation]:not([disabled])"
  orbite_assert_reachable("[data-orbite-composer-navigation]")
  find("[data-orbite-composer-navigation]").click
  assert_selector "#chat-history:modal"
  orbite_tab_to("#chat-history [data-action='workspace-navigation#close']")
  page.driver.browser.action.send_keys(:escape).perform
  assert_selector "[data-orbite-composer-navigation]:focus"
  orbite_assert_reachable(".n-composer-stop")
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

```bash
record orbite-dock-red browser_test test/system/orbite_workspace_test.rb -i '/context_scrolls|mobile_navigation_remains/'
```

Expect the flow composer to move/out-of-bounds or the absent mobile composer opener, with actual tests executed. Capture the before screenshot and true exit.

- [ ] **Step 2: Move context/transcript into one explicit child surface.**

In `_orbite_shell.html.erb` replace only `tag.main`'s identity/data expression:

```erb
<%= tag.main id: chat_workspace_page? ? "application-page" : "application-scroll",
      class: "n-application-page n-orbite-main #{'n-chat-main' if chat_workspace_page?}",
      data: { application_scroll: chat_workspace_page? ? nil : true } do %>
```

For `show.html.erb`, keep its opening workspace tag/attributes/action list from Task 2 unchanged. Replace only the body after that opening tag with:

```erb
  <div id="application-scroll" class="n-orbite-reading" data-application-scroll data-scroll-target="surface">
    <%= render "chats/header", chat: @chat, titles: @history_titles %>
    <p id="chat-feedback-status-<%= @chat.id %>" class="sr-only" role="status" aria-live="polite" aria-atomic="true" data-chat-feedback-target="status" data-turbo-permanent></p>
    <div class="n-chat-follow">
      <button type="button" class="n-workspace-button" hidden data-scroll-target="latest" data-action="scroll#latest"><%= t("nosia.chat_workspace.latest") %></button>
    </div>
    <section class="n-chat-transcript" aria-label="<%= t('nosia.chat_workspace.transcript') %>" data-scroll-target="viewport">
      <%= render "chats/transcript", chat: @chat %>
    </section>
  </div>
  <section class="n-chat-dock n-chat-reading-column" aria-label="<%= t('nosia.chat_workspace.reply') %>">
    <%= render partial: "messages/form", locals: { chat: @chat } %>
  </section>
  <%= turbo_stream_from @chat, :messages, I18n.locale %>
  <%= turbo_stream_from @chat, :token_totals, I18n.locale %>
  <%= render "chats/history", chat: @chat, conversations: @history, titles: @history_titles %>
  <%= render "chats/mcp_selector", chat: @chat %>
</div>
```

For `new.html.erb`, keep its opening workspace tag/data/action list from Task 2 unchanged. Its complete body becomes:

```erb
  <div id="application-scroll" class="n-orbite-reading" data-application-scroll>
    <%= render "chats/header", chat: @chat, titles: @history_titles %>
    <section class="n-chat-start n-chat-reading-column">
      <h1 class="n-chat-title"><%= t("nosia.chat_workspace.new_title") %></h1>
      <p class="n-workspace-help"><%= t("nosia.chat_workspace.new_help") %></p>
      <% unless @chat.account %>
        <%= render "chats/no_account" %>
        <%= link_to t("nosia.chat_workspace.setup_account"), accounts_path, class: "n-workspace-link" %>
      <% end %>
    </section>
  </div>
  <% if @chat.account %>
    <section class="n-chat-dock n-chat-reading-column" aria-label="<%= t('nosia.chat_workspace.reply') %>">
      <%= render "form", chat: @chat, navigation: true %>
    </section>
  <% end %>
  <%= render "chats/history", chat: @chat, conversations: @history, titles: @history_titles %>
</div>
```

No-account guidance renders once, not a fake disabled editor. Its mobile navigation remains available through the context History trigger. Never alter message wrappers, transcript partial queries or cable subscriptions.

- [ ] **Step 3: Pass an explicit presentation local into the native composer.**

Add strict locals to `chats/_form.html.erb`, then pass the optional flag into its composer render:

```erb
<%# locals: (chat:, navigation: false) %>
```

```erb
<%= render "chats/composer", form: form, chat: chat, field: :prompt,
  skills: skills, generating: generating, stop_form_id: stop_form_id, navigation: navigation %>
```

Change the composer strict-locals line to:

```erb
<%# locals: (form:, chat:, field:, skills:, generating:, stop_form_id:, navigation: false) %>
```

Immediately inside `.n-composer-actions`, **outside** the inert editing-tools group, insert:

```erb
<% if navigation %>
  <button type="button" id="<%= dom_id(chat, :navigation) %>" class="n-composer-control n-orbite-mobile-only"
          aria-label="<%= t('nosia.orbite.navigation') %>" aria-controls="chat-history" aria-haspopup="dialog" aria-expanded="false"
          data-orbite-composer-navigation data-workspace-navigation-target="trigger" data-action="workspace-navigation#toggle">
    <%= inline_svg "svg/menu.svg", aria_hidden: true, class: "n-composer-icon" %>
  </button>
<% end %>
```

In `messages/_form.html.erb` add only `navigation: true` to its existing `render "chats/composer"` call. Keep the uncached scoped busy/stopped pair, forms/owners, all other locals and attributes byte-identical. Dashboard still calls `chats/form` without the flag; its composer does not acquire a duplicate launcher. Background forms do not inspect Current or the request path.

- [ ] **Step 4: Retarget the existing reader, preserving its algorithm.**

Change the targets declaration to:

```javascript
static targets = ["surface", "viewport", "latest"]
```

Change `connect`'s `onFocusOut` body to clear navigation only when leaving the shared input ancestor:

```javascript
this.onFocusOut = event => {
  if (!this.inputRoot.contains(event.relatedTarget)) this.navigation = null
}
```

Add the explicit target lifecycle callback:

```javascript
surfaceTargetConnected() {
  if (this.state && this.element.isConnected && this.hasViewportTarget) {
    this.observeSurface()
    this.schedule()
  }
}
```

Replace `observeSurface()` and `stopObserving()` completely with:

```javascript
observeSurface() {
  this.stopObserving()
  this.main = this.surfaceTarget
  this.inputRoot = this.element.closest("#orbite-shell")
  this.viewport = this.viewportTarget
  this.main.addEventListener("scroll", this.onScroll)
  for (const [type, listener] of [["keydown", this.onKeydown], ["keyup", this.onKeyup],
    ["focusin", this.onFocus], ["focusout", this.onFocusOut], ["click", this.onDisclosureClick]]) {
    this.inputRoot.addEventListener(type, listener)
  }
  this.contentChanged()
  this.rememberPosition()
  this.mutations = new MutationObserver(records => {
    this.contentChanged(this.mutationMessageIds(records))
    this.rememberPosition()
    this.schedule()
  })
  this.mutations.observe(this.viewport, { childList: true, subtree: true, characterData: true })
  this.resize = new ResizeObserver(() => { this.rememberPosition(); this.schedule() })
  for (const element of [this.main, this.element, this.viewport, this.viewport.firstElementChild]) {
    if (element) this.resize.observe(element)
  }
}

stopObserving() {
  this.main?.removeEventListener("scroll", this.onScroll)
  for (const [type, listener] of [["keydown", this.onKeydown], ["keyup", this.onKeyup],
    ["focusin", this.onFocus], ["focusout", this.onFocusOut], ["click", this.onDisclosureClick]]) {
    this.inputRoot?.removeEventListener(type, listener)
  }
  this.navigation = null
  this.disclosureActivation = null
  this.mutations?.disconnect()
  this.resize?.disconnect()
}
```

In `focused()` consume the transient key event as before, but require the new active element to belong to this chat before recording its actual surface movement:

```javascript
if (navigation && this.element.contains(document.activeElement) &&
    !navigation.event.defaultPrevented && navigation.top !== this.surface.scrollTop) this.recordInput()
```

Replace only the first two guards in `reconcile()`:

```javascript
if (!this.element.isConnected || !this.hasViewportTarget || !this.hasSurfaceTarget) return
if (this.viewport !== this.viewportTarget || this.main !== this.surfaceTarget ||
    this.inputRoot !== this.element.closest("#orbite-shell")) this.observeSurface()
```

The input ancestor covers real Tab movement from rail/history/composer **into** the reading area; only the explicit reading surface owns scroll position. This adds no second focus restorer. Keep `scrolled`, `recordInput`, gap/80px semantics, capture/restore blocks, mutation-ID/content maps, disclosure activation/newer-input invalidation, post-HUD capture, scheduling, Latest and own-success submission handling unchanged.

- [ ] **Step 5: Add the structural conversation stylesheet and import.**

Create `orbite_chat.css`:

```css
.n-orbite-shell .n-chat-main { display: flex; flex-direction: column; overflow: hidden; padding: 0; min-height: 0; }
.n-orbite-shell .n-chat-main > .n-orbite-page-trail:empty { display: none; }
.n-orbite-shell .n-chat-workspace { display: grid; grid-template-rows: minmax(0, 1fr) auto; flex: 1; gap: 0; height: auto; min-height: 0; overflow: hidden; }
.n-orbite-shell .n-chat-workspace > turbo-cable-stream-source { display: none; }
.n-orbite-shell .n-orbite-reading { min-height: 0; min-width: 0; overflow-y: auto; overflow-anchor: none; scrollbar-gutter: stable; scroll-padding-block: .75rem; }
.n-orbite-shell .n-chat-transcript { flex: none; overflow: visible; padding: 1rem; }
.n-orbite-shell .n-chat-header { padding: .75rem 1rem 0; }
.n-orbite-shell .n-chat-reading-column { max-width: 74ch; }
.n-orbite-shell .n-chat-start { min-height: 0; padding: 1.5rem 1rem; }
.n-orbite-shell .n-chat-dock { width: 100%; max-width: 76ch; padding: .75rem 1rem .5rem; margin-inline: auto; min-width: 0; }
.n-orbite-shell .n-chat-dock .lexxy-editor__content { min-block-size: 3rem; max-block-size: min(20dvh, 10rem); overflow-y: auto; }
.n-orbite-shell .n-chat-dock .n-composer-errors { max-block-size: 4rem; overflow-y: auto; }
.n-orbite-shell .n-chat-dock .n-composer-meta { padding-block: .25rem 0; }
.n-orbite-shell .n-chat-dock .n-composer-notice { margin-block: .375rem 0; }
.n-orbite-shell .n-chat-workspace--new { overflow: hidden; scrollbar-gutter: auto; }
.n-orbite-shell .n-chat-composer .n-orbite-mobile-only { display: none; }
@media (max-width: 767px), (max-height: 700px) {
  .n-orbite-shell .n-chat-main { padding: 0; }
  .n-orbite-shell .n-chat-dock { padding: .5rem .625rem; }
  .n-orbite-shell .n-chat-transcript { padding: .75rem; }
}
@media (max-width: 767px) {
  .n-orbite-shell .n-chat-composer .n-orbite-mobile-only { display: inline-flex; }
}
```

```css
@import "../stylesheets/nosia/orbite_chat.css";
```

Import after `orbite_shell.css`. Do not give the dock `overflow: hidden` or turn its transient native Tools popover into clipped content. Errors/editor scroll locally; required guidance stays readable. A real short-screen/formatting/upload overflow is a bug, not an accepted geometry exception.

- [ ] **Step 6: Migrate only reader-owner wiring in protected tests.**

Keep `reader_surface` returning `document.querySelector('[data-application-scroll]')` and all 1px/80px physics assertions. In the existing owner-retarget test, select that actual surface, clone/replace it and append the original children exactly as before; the reader root now stays outside its replaced **child**, not inside its replaced ancestor. Rename the test/diagnostic from ancestor retarget to explicit-surface retarget; preserve the exact controller root, paragraph, Latest and resume assertions.

In `test/system/compact_headers_test.rb`, the two native ordering-boundary setups currently using `root.closest('[data-application-scroll]')` must use:

```javascript
const root = document.querySelector('.n-chat-workspace--saved')
const surface = root.querySelector('[data-scroll-target~="surface"]')
```

Do not change their delivery boundary, trusted input, real Turbo payloads, native visible-control oracle, subsequent ResizeObserver checks or tolerances.

In `test/support/chat_workspace_browser_checks.rb`, preserve all actual reader and control sampling; `document.querySelector('[data-application-scroll]')` remains the real owner. Change only the now-supported inline-dialog exclusion from `element.closest('dialog')` to `element.closest('dialog:modal')`; true modal/backdrop checks still use their independent sampler. Change `chat_evidence_directory`'s default from `/tmp/opencode` to `Dir.tmpdir` so including it never introduces an undeclared CI directory requirement.

For its independent `chat_native_close_contrast`, stop the existing path-to-ancestor loop **after checking the opaque native dialog** rather than examining irrelevant out-of-top-layer ancestor shadows. Add this as the final statement inside that loop:

```javascript
if (node === dialog) break
```

Preserve every stroke/path/opacity/uniformity/pseudo-element rejection inside the dialog and the independently sampled glyph/focus ratios, pixel points and 40×40 legacy Tools geometry assertions. This is an opaque-top-layer sampling boundary, not permission to ignore painted effects within the dialog or infer its backdrop contrast.

- [ ] **Step 7: Replace the obsolete bottom-pill clearance test with dock/viewport clearance, not weaker visibility.**

In `test/system/chat_workspace_layout_test.rb` retain the two themes, actual 768×1024 viewport, all nine hit points per help/disclaimer sample and main containment checks. Remove only the `.n-nav-bottom.closest('.fixed')` dependency and its fixed-nav bounds. In `composer_geometry` return:

```javascript
nav: { visible: false },
dock: document.querySelector('.n-chat-dock').getBoundingClientRect().toJSON(),
reading: surface.getBoundingClientRect().toJSON()
```

Replace its old nav assertions with:

```ruby
assert_no_selector ".n-nav-bottom", visible: :all
assert_operator geometry.fetch("reading").fetch("bottom"), :<=, geometry.fetch("dock").fetch("top") + 1, geometry.to_json
geometry.fetch("composer").each do |sample|
  assert_operator sample.fetch("bounds").fetch("bottom"), :<=, geometry.fetch("dock").fetch("bottom"), sample.to_json
  assert_operator sample.fetch("bounds").fetch("bottom"), :<=, geometry.fetch("viewport").last, sample.to_json
  assert sample.fetch("unobscured"), "Composer text is clipped or covered: #{sample.to_json}"
end
```

Theme setup must use `orbite_theme(theme == 'dark')` from the shared helper, not a hidden direct utility button. Include that helper through the explicit require/include pattern from the new system test. Rename the case/comment to reserved-composer viewport clearance. No `main` rectangle is replaced with a fictitious surface rectangle.

- [ ] **Step 8: Verify the atomic reader/dock change.**

```bash
record orbite-dock-build rails_test tailwindcss:build
record orbite-dock-green browser_test test/system/orbite_workspace_test.rb
record orbite-reader-green browser_test test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb
record orbite-dock-contracts rails_test test test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb
record orbite-reader-syntax node --input-type=module --check < app/javascript/controllers/scroll_controller.js
git diff --check
```

Task 5 Steps 1–4 were already applied in Task 2. Do not call a failing group passing or alter production reader physics to satisfy an obsolete setup. Do not defer a new reader failure to later tasks.

Commit exact task paths only after actual GREEN, using `feat(chat): Reserve the Orbite composer and reading surface`; pass SPEC→QUALITY. If a real reader algorithm defect appears, keep its RED and ask before expanding production scope.

## Task 4: Apply the approved materials and measured visual hierarchy

**Files:** `app/assets/stylesheets/nosia/orbite_shell.css`, `orbite_chat.css`; `test/system/orbite_workspace_test.rb`, `test/system/chat_workspace_test.rb`. No generated-message markup/content change.

- [ ] **Step 1: Add real typography, surface and target measurements.**

Append inside `OrbiteWorkspaceSystemTest`:

```ruby
test "Orbite prose and controls retain measured typography and native editing" do
  %w[EN FR].each do |language|
    orbite_select_language(language)
    [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
      [ false, true ].each do |dark|
        orbite_viewport(width, height)
        visit chat_path(@chat)
        orbite_theme(dark)
        find("lexxy-editor .lexxy-editor__content").send_keys((1..35).map { |i| "Native draft line #{i}" }.join("\n"))
        find("[data-composer-chrome-target=formatting] > summary").click
        assert_selector "[data-formatting-open] lexxy-toolbar", visible: true
        sample = page.evaluate_script(<<~JS)
          (()=>{const box=s=>document.querySelector(s).getBoundingClientRect().toJSON();
            const body=document.querySelector('.n-chat-assistant-body:not([data-chat-error=true])'),style=getComputedStyle(body);
            const text=getComputedStyle(body.querySelector('.ai-response-content'));
            const editor=document.querySelector('.lexxy-editor__content');
            const measure=document.createElement('canvas').getContext('2d');measure.font=text.fontSize+' '+text.fontFamily;
            const selectors=['.n-composer-send','.n-composer-control[aria-label]', '.n-composer-formatting > summary'];
            return {assistant:{border:style.borderTopWidth,background:style.backgroundColor,padding:style.paddingLeft},
              typography:{size:parseFloat(text.fontSize),line:parseFloat(text.lineHeight),font:text.fontFamily,zero:measure.measureText('0').width},
              prose:box('.n-chat-transcript .n-chat-reading-column'),editor:{client:editor.clientHeight,height:editor.scrollHeight},
              reading:box('[data-application-scroll]'),dock:box('.n-chat-dock'),
              overflow:{document:document.documentElement.scrollWidth-innerWidth,main:document.querySelector('main').scrollWidth-document.querySelector('main').clientWidth},
              controls:selectors.flatMap(s=>[...document.querySelectorAll(s)]).filter(e=>e.checkVisibility()).map(e=>({name:e.getAttribute('aria-label')||e.textContent,box:e.getBoundingClientRect().toJSON()}))};})()
        JS
        orbite_record("visual-materials-#{language}-#{width}-#{dark}", sample, screenshot: true)
        assert_equal "0px", sample.fetch("assistant").fetch("border"), sample.to_json
        assert_equal "rgba(0, 0, 0, 0)", sample.fetch("assistant").fetch("background"), sample.to_json
        assert_in_delta 16, sample.fetch("typography").fetch("size"), 0.1
        assert_operator sample.fetch("typography").fetch("line"), :>=, 25.6
        assert_operator sample.fetch("typography").fetch("line"), :<=, 28
        if width >= 1280
          characters = sample.fetch("prose").fetch("width") / sample.fetch("typography").fetch("zero")
          assert_operator characters, :>=, 65
          assert_operator characters, :<=, 75
        end
        assert_operator sample.fetch("editor").fetch("height"), :>, sample.fetch("editor").fetch("client")
        assert_equal({ "document" => 0, "main" => 0 }, sample.fetch("overflow"))
        assert_operator sample.fetch("reading").fetch("bottom"), :<=, sample.fetch("dock").fetch("top") + 1
        assert_operator sample.fetch("reading").fetch("height"), :>, 0
        sample.fetch("controls").each do |control|
          assert_operator control.fetch("box").fetch("width"), :>=, 44, control.to_json
          assert_operator control.fetch("box").fetch("height"), :>=, 44, control.to_json
        end
        orbite_assert_reachable(".n-composer-send")
        page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
        assert page.evaluate_script("[...document.querySelectorAll('#orbite-shell button')].every(e=>getComputedStyle(e).transitionDuration.split(',').every(v=>parseFloat(v)===0))")
        page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
      end
    end
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

The assertion uses a real long native draft and formatting toolbar, not a replacement contenteditable fixture. Existing upload-byte and blocked-send cases run in the full protected group below. The complete EN/FR × themes × viewport matrix already exercises saved **and new** in the migrated existing chat test; do not replace it with this saved-only addition.

- [ ] **Step 2: Run the visual RED.**

```bash
record orbite-materials-red browser_test test/system/orbite_workspace_test.rb -i '/Orbite_prose/'
```

Expect heavy assistant border/background or sub-44px composer controls, not a missing fixture/translation/editor. Record actual failing assertion and screenshots.

- [ ] **Step 3: Append scoped premium finish CSS.**

Append to `orbite_chat.css`:

```css
.n-orbite-shell { font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
.n-orbite-shell .n-chat-workspace { color: var(--orbite-text); }
.n-orbite-shell .n-chat-workspace :is(.n-workspace-help, .n-chat-account-preview) { color: var(--orbite-muted); }
.n-orbite-shell .n-chat-workspace .n-chat-assistant-body:not([data-chat-error=true]) { border: 0; border-radius: 0; background: transparent; padding: .25rem 0 .75rem; }
.n-orbite-shell .n-chat-workspace .n-chat-user-body { border: 0; background: var(--orbite-bubble); color: var(--orbite-text); border-radius: 1.125rem 1.125rem .375rem 1.125rem; max-width: 88%; padding: .875rem 1rem; }
.n-orbite-shell .n-chat-workspace :is(.ai-response-content, .n-chat-user-body) { font-size: 1rem; line-height: 1.7; }
.n-orbite-shell .n-chat-workspace :is(.n-chat-assistant-name, .n-chat-details > summary) { color: var(--orbite-accent); }
.n-orbite-shell .n-chat-workspace .n-chat-message { margin-bottom: 1.75rem; }
.n-orbite-shell .n-chat-workspace .n-chat-source { background: var(--orbite-paper); color: var(--orbite-text); border-color: var(--orbite-control); }
.n-orbite-shell .n-chat-composer {
  --composer-paper: var(--orbite-paper); --composer-text: var(--orbite-text);
  --composer-muted: var(--orbite-muted); --composer-border: var(--orbite-control);
  --composer-hover: var(--orbite-bubble); --composer-accent: var(--orbite-accent);
  --composer-on-accent: var(--orbite-on-accent);
}
.n-orbite-shell .n-chat-composer .n-composer-surface { border-radius: 1.25rem; box-shadow: 0 3px 14px rgb(0 0 0 / .06); }
.n-orbite-shell .n-chat-composer :is(.n-composer-control, .n-composer-send) { min-height: 44px; min-width: 44px; }
.n-orbite-shell .n-chat-composer .n-composer-send { width: 44px; height: 44px; }
.n-orbite-shell .n-chat-composer .n-composer-account select { min-height: 44px; }
.n-orbite-shell .n-chat-composer .n-composer-account { min-width: 0; }
.n-orbite-shell .n-chat-composer .n-composer-actions { gap: .25rem; }
.n-orbite-shell .n-chat-workspace .n-chat-follow { width: fit-content; margin-inline: auto; }
.n-orbite-shell .n-chat-workspace .n-chat-follow button { box-shadow: 0 2px 8px rgb(0 0 0 / .1); background: var(--orbite-paper); color: var(--orbite-text); }
.n-orbite-shell .n-chat-history-row { border-color: var(--orbite-line); padding-block: .625rem; gap: .375rem; }
.n-orbite-shell .n-chat-history-row .n-workspace-link { display: block; min-height: 44px; padding-block: .375rem; color: var(--orbite-text); }
.n-orbite-shell .n-chat-history-row [aria-current=page] { background: var(--orbite-bubble); border-radius: .375rem; }
.n-orbite-shell .n-chat-history-row .n-workspace-help { color: var(--orbite-muted); font-size: .75rem; }
.n-orbite-shell .n-chat-workspace :is(button, summary, a) { scroll-margin-block: .75rem; }
.n-orbite-shell .n-chat-workspace :is(button, summary, a):focus-visible { outline: 2px solid var(--orbite-accent); outline-offset: -2px; }
```

Append to `orbite_shell.css`:

```css
.n-orbite-shell .n-orbite-main { box-shadow: 0 4px 22px rgb(0 0 0 / .035); }
.n-orbite-shell .n-orbite-navigation .n-workspace-button { min-height: 44px; min-width: 44px; }
.n-orbite-shell .n-orbite-utilities { position: relative; }
```

Keep borders that identify Sources and actionable controls ≥3:1; shell/canvas dividing lines and user-bubble edges are decorative. The open assistant body is not an interactive bordered control. Do not apply the transparent-body rule to `[data-chat-error=true]`: errors remain visible alerts. No remote font, image asset, blur or token animation is added.

- [ ] **Step 4: Migrate only decorative border assertions.**

In `test/system/chat_workspace_test.rb`, replace its two stateful `chat_contrast` calls asserting user-bubble and assistant-card **borders** with:

```ruby
chat_contrast ".n-chat-user-body p"
chat_contrast ".n-chat-assistant-body .ai-response-content h2"
```

Leave `chat_contrast ".n-chat-source", minimum: 3, border: true` and all text/focus/icon/error contrast assertions unchanged. The new material test explicitly requires zero assistant border, so removing an obsolete decorative-card border claim is not silently dropping its replacement contract. Tools close is unchanged legacy 40×40 and keeps its independently sampled stroke/focus test; all newly redesigned shell/composer controls are ≥44×44.

- [ ] **Step 5: Build, measure, inspect and commit.**

```bash
record orbite-materials-build rails_test tailwindcss:build
record orbite-materials-green browser_test test/system/orbite_workspace_test.rb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_workspace_layout_test.rb test/system/compact_headers_test.rb
git diff --check
git add -- app/assets/stylesheets/nosia/orbite_shell.css app/assets/stylesheets/nosia/orbite_chat.css test/system/orbite_workspace_test.rb test/system/chat_workspace_test.rb
git commit -m "feat(ui): Refine Orbite conversation materials and controls"
```

Inspect actual screenshots for both themes, saved/new, each viewport, open Usage/formatting/Sources/Reasoning, long account labels, navigation modal and errors. Use `read` on the saved images; a file existing is not a visual review. Keep screenshots/raw measurements tied to exact source SHA and diff. Palette seed values are not measured passes; any contrast/hit/short-screen failure blocks this task and needs a scoped correction plus a fresh GREEN. Pass SPEC→QUALITY.

## Task 5: Migrate native navigation access and application-wide geometry contracts

**Execution order:** Steps 1–4 are a required **test prelude inside Task 2**, performed before its acceptance/commit. They do not wait until after Task 4. Step 5 runs after Tasks 3–4 as the broad regression gate. This deliberate split prevents hidden-utility setup failures from being mistaken for reader regressions.

**Files:** `test/support/chat_workspace_browser_checks.rb`; `test/system/chat_workspace_test.rb`, `compact_headers_test.rb`, `chat_composer_ui_test.rb`, `account_experience_test.rb`, `localization_test.rb`, `mcp_workspace_test.rb`, `mcp_connection_tests_test.rb`, `sources_workspace_upload_test.rb`, `mcp_catalog_test.rb`, `dashboard_test.rb`, `agent_skills_workspace_test.rb`, `sources_workspace_test.rb`, `token_usage_workspace_test.rb`, `accounts_settings_workspace_test.rb`, `profile_management_test.rb`. Leave unrelated data/role/stream/upload assertions untouched.

- [ ] **Step 1: Make utility access explicit in existing browser fixtures.**

In each named system-test class that uses theme/language/profile controls add:

```ruby
require_relative "../support/orbite_browser_checks"
```

```ruby
include OrbiteBrowserChecks
```

Do not include it globally in `ApplicationSystemTestCase`. In the existing `ChatWorkspaceBrowserChecks` module add `require_relative "orbite_browser_checks"` and `include OrbiteBrowserChecks`; replace `chat_theme` with:

```ruby
def chat_theme(dark)
  orbite_theme(dark)
  settle_workspace_layout
end
```

Correct its native reverse-key helper (not the outcomes) to:

```ruby
if reverse
  page.driver.browser.action.key_down(:shift).send_keys(:tab).key_up(:shift).perform
else
  page.driver.browser.action.send_keys(:tab).perform
end
```

Replace **only** utility access operations in the listed classes, using this complete mapping:

| Existing operation | Replacement |
| --- | --- |
| `select locale.upcase, from: "language_preference_locale"` | `orbite_select_language(locale.upcase)` |
| `select locale.to_s.upcase, from: "language_preference_locale"` | `orbite_select_language(locale.to_s.upcase)` |
| `select "FR", from: "language_preference_locale"` | `orbite_select_language("FR")` |
| `select "EN", from: "language_preference_locale"` | `orbite_select_language("EN")` |
| `select language, from: "language_preference_locale"` | `orbite_select_language(language)` |
| `select(locale.upcase, from: "language_preference_locale")` | `orbite_select_language(locale.upcase)` |
| theme helper's direct condition/click/assert block | `orbite_theme(theme == "dark")` |
| `find("#dropdownUser").click` | `orbite_open_utilities` followed by the unchanged click |
| post-sign-in `assert_selector "#dropdownUser"` used only as login readiness | `assert_selector "#orbite-shell"` |

Signed-out selection in `localization_test.rb` remains direct; its signed-in selections use the helper. Public `color_theme_test.rb` stays unchanged and continues testing the public theme button. Keep the account test's forced theme-refresh double toggle inside:

```ruby
orbite_with_utilities { 2.times { find("#theme-toggle").click } }
```

In `accounts_settings_workspace_test.rb`'s `assert_settings_hover`, the old theme-button hover merely moves the pointer off a card. Replace it with `find("main h1").hover` rather than opening a modal above the card. Preserve the real card hover, computed colors, contrast, fine-pointer capability, screenshot and hit assertions. Do not replace native profile navigation with `visit profile_path`. Existing source error-link tests containing `'#language_preference_locale'` are hostile/invalid-link fixtures, not UI selection; preserve them.

For the localization mobile control case, open the signed-in utilities panel before the existing label/select/Escape/`:focus-visible` assertions. Replace `nav label.sr-only`, `nav select#language_preference_locale` and `nav form[action=...]` selectors with the unique `.n-language-preference` form descendants; preserve exact translated label, option, reload `performance.timeOrigin`, URL and focus assertions. The public-only compact-language test keeps its 32–36px historical public-control size; do not change it to claim signed-in modal geometry. Its selectors may use the unique form class without a `nav` ancestor. Modal controls get separate ≥44px coverage in Task 2/new tests.

- [ ] **Step 2: Keep modal tests modal and distinguish wide inline behavior.**

In `test/system/chat_workspace_test.rb`, use `#workspace-history-trigger` instead of broad `button[aria-controls=chat-history]` queries, in Ruby selectors **and** JavaScript. Change navigation Close queries from `data-action='chat-dialog#close'` to `data-action='workspace-navigation#close'` only for `#chat-history`; Tools actions stay unchanged.

Before the first `visit` in each existing test that asserts `assert_native_dialog "chat-history"`, add:

```ruby
set_reader_viewport(1024, 1000)
```

Do this for modal History, modal replacement, Back/cache, pending-source, live-disclosure-vs-modal and accepted-race `destination == 'modal'` cases. Do not change explicit viewport matrix loops or tests intentionally exercising desktop reading. The latter keep 1400px and gain separate wide history assertions below. In both async-race JavaScript probes that deliberately focus outside the chat root, replace only `document.getElementById('theme-toggle')` with:

```javascript
document.getElementById('workspace-utilities-trigger')
```

That control is visible outside `.n-chat-workspace` on the default desktop viewport; do not open a dialog or move the timing boundary. Keep all native Turbo caller traces, exact `BODY`/summary focus assertions and accepted exception count unchanged.

The existing EN/FR responsive matrix needs its navigation section replaced with the following, while retaining its editor, counts, target identities, screenshot naming, bounds and Send focus/contrast checks:

```ruby
if width >= 1280
  assert_selector "#chat-history[data-inline=true][open]"
  refute page.evaluate_script("document.querySelector('#chat-history').matches(':modal')")
  trigger = "#workspace-history-rail-trigger"
  chat_keyboard_focus trigger, reverse: true
  chat_contrast trigger, minimum: 3, outline: true
  page.driver.browser.action.send_keys(:enter).perform
  assert_no_selector "#chat-history[open]", visible: :all
  assert_selector "#{trigger}:focus"
  page.driver.browser.action.send_keys(:space).perform
  assert_selector "#chat-history[data-inline=true][open]"
else
  trigger = "#workspace-history-trigger"
  chat_keyboard_focus trigger, reverse: true
  chat_contrast trigger, minimum: 3, outline: true
  page.driver.browser.action.send_keys(:enter).perform
  assert_native_dialog "chat-history"
  close = "#chat-history button[data-action='workspace-navigation#close']"
  chat_reachable close
  assert_equal I18n.t("nosia.chat_workspace.close", locale: locale), find(close).text
  find(close).click
  assert_no_selector "#chat-history[open]", visible: :all
  assert_selector "#{trigger}:focus"
end
```

Wide history now has its own inline/collapse/native Space/Enter contract rather than a fake modal assertion. Tablet/mobile keep focus containment and return. No accounting, upload bytes, worker unlock, source guard, status region or 1px/80px assertion is removed.

- [ ] **Step 3: Migrate the compact-header helpers to real shell/page geometry.**

In `test/system/compact_headers_test.rb`, replace `header_geometry` with:

```ruby
def header_geometry
  page.evaluate_script(<<~JS)
    (() => {
      const sample = element => ({ ...element.getBoundingClientRect().toJSON(),
        id: element.id, scrollTop: element.scrollTop, scrollHeight: element.scrollHeight, clientHeight: element.clientHeight })
      return { navigation: sample(document.querySelector('.n-orbite-rail')),
        heading: sample(document.querySelector('main h1')), main: sample(document.querySelector('main')),
        surface: sample(document.querySelector('[data-application-scroll]')),
        syntheticOverflow: !!document.querySelector('[data-header-overflow-fixture]') }
    })()
  JS
end
```

Replace all `global` measurement uses with correctly named `navigation`, but **do not** assert that a persistent rail scrolls away. Replace only the old global-header offscreen assertion at the two geometry sites with:

```ruby
assert_no_selector "[data-application-header]", visible: :all
if page.evaluate_script("innerWidth >= 768")
  assert_operator geometry.fetch("navigation").fetch("top"), :>=, 0, geometry.to_json
end
```

Use `sample` rather than `geometry` in the matrix site. Preserve heading-offscreen and 1px movement checks. Replace the `main.scrollTop == 0` assertion in those two sites with:

```ruby
if page.has_selector?(".n-chat-workspace", wait: 0)
  assert_equal 0, geometry.fetch("main").fetch("scrollTop"), geometry.to_json
else
  assert_equal geometry.fetch("surface").fetch("scrollTop"), geometry.fetch("main").fetch("scrollTop"), geometry.to_json
end
```

Again use `sample` at the matrix site. Non-chat main **is** the actual scroller; do not report a fabricated zero. Keep all chat nested-scroll zero assertions in native-ordering cases unchanged.

In `header_overflow_fixture`, replace only its placement/diagnostics: append the same inert `height:2200px;flex:none` fixture to `[data-application-scroll]` and assert `[data-application-scroll] > [data-header-overflow-fixture][inert]`; record placement as `"inert nonshrinking child of the actual primary surface"`. Replace `refute fixture.fetch("insideMain")` with `assert fixture.fetch("insideMain")`. Preserve its overflow threshold, real-saved-chat `refute syntheticOverflow`, actual dimensions and `flexShrink == '0'`. Rename the first four generated test labels to “page header scrolls away beside persistent navigation …”.

Replace `header_theme` with:

```ruby
def header_theme(dark)
  header_top
  orbite_theme(dark)
  header_settle
end
```

Replace the old “global bar is compact” case completely with:

```ruby
test "rail and native utilities retain full target sizes without an old global bar" do
  [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
    header_viewport(width, height)
    visit accounts_path
    assert_no_selector "[data-application-header], .n-nav-bottom", visible: :all
    orbite_open_utilities
    sample = page.evaluate_script(<<~JS)
      ({ controls: ['#language_preference_locale','#theme-toggle','#dropdownUser'].map(selector=>({selector,geometry:document.querySelector(selector).getBoundingClientRect().toJSON()})) })
    JS
    header_record("orbite-targets-#{width}x#{height}", sample, screenshot: true)
    sample.fetch("controls").each do |control|
      assert_operator control.fetch("geometry").fetch("height"), :>=, 44, control.to_json
      assert_operator control.fetch("geometry").fetch("width"), :>=, 44, control.to_json
      orbite_assert_reachable(control.fetch("selector"))
    end
    orbite_close_navigation
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

For `header_matrix_geometry`, change only the control-selector prefix from `[data-application-header] a, [data-application-header] button, [data-application-header] select` to `.n-orbite-rail a, .n-orbite-rail button, #chat-history a, #chat-history button, #chat-history select`; preserve page-header control sampling and actual visibility filter. The eleven-route matrix replaces its global-header count with `#orbite-shell` count 1 and old-header count 0. Wrap its three utility contrast/Tab operations with:

```ruby
orbite_with_utilities do
  header_contrast("#language_preference_locale")
  header_contrast("#theme-toggle svg:not(.hidden)", minimum: 3, property: "fill")
  header_tab_to("#language_preference_locale")
  header_tab_to("#theme-toggle")
end
```

On widths ≥768px add this known-currentColor rail-icon check to the same matrix after the modal is closed:

```ruby
if width >= 768
  icon = ".n-orbite-rail .n-orbite-link[href='#{root_path}'] svg"
  assert page.evaluate_script(<<~JS, find(icon))
    (()=>{const svg=arguments[0],path=svg.querySelector('path'),paint=getComputedStyle(path);
      return paint.stroke===getComputedStyle(svg).color&&Number(paint.strokeOpacity)===1&&paint.fill==='none';})()
  JS
  header_contrast(icon, minimum: 3, property: "color")
end
```

The static icon has a 2px opaque currentColor stroke; verify that equality before using its inherited color measurement. This does not infer glyph contrast from a focus outline or decorative border.

The native profile navigation case opens utilities before traversal; replace its old global-home Tab target with `#chat-history .n-orbite-panel-links a[href='#{root_path}']` and sample panel controls instead of removed header controls. Keep native Enter, resulting URL/h1/theme/locale and screenshot assertions. Use `#workspace-history-trigger` in saved-header `historyTop` and native-forward target queries, not the rail trigger.

In `test/system/mcp_workspace_test.rb`'s “mobile New chat opens the scoped account composer by keyboard” test, replace only the removed-bottom-pill target/setup with:

```ruby
find("#workspace-mobile-trigger").click
assert_selector "#chat-history:modal"
target = "#chat-history .n-orbite-panel-links a[aria-label='#{I18n.t('nosia.nav.new_chat')}']"
assert_selector target, count: 1
```

Keep its native Tab loop/Enter, exact scoped account URL/picker value, unchanged default account and no-chat-created assertions. In `test/system/profile_management_test.rb`, its optional old-bottom-pill geometry is already null-safe; leave its actual-main/five-point focus containment assertions intact. Update only its stale failure text to “inside main and unobscured by navigation”.

The enlarged-CSS-text test opens utilities before Tab and wraps both native enlarged-hit calls in `orbite_with_utilities`. Replace its obsolete “global.height > 52” with actual control growth:

```ruby
assert_operator find("#language_preference_locale").native.rect.height, :>=, 44
assert_operator page.evaluate_script("document.querySelector('#chat-history').scrollWidth"), :<=,
  page.evaluate_script("document.querySelector('#chat-history').clientWidth")
```

Perform these assertions while the panel is open. Keep the rounded-corner hit sampler, translated labels, all focus/contrast checks and `nativeZoomVerified: false`. The account UID/role companion class only gains explicit utilities access for locale/logout; its visible scope/role/owner-action assertions remain identical.

- [ ] **Step 4: Sample modal interiors honestly without pretending to measure backdrops.**

In `header_contrast`, remove only the blanket `element.closest('dialog')` rejection. In **both** `header_contrast` and `header_hit`, replace the chain-building line with:

```javascript
const modal = element.closest('dialog:modal')
const chain = []
for (let node = element; node; node = node.parentElement) {
  chain.unshift(node)
  if (node === modal) break
}
if (modal) {
  const paint = rgba(getComputedStyle(modal).backgroundColor)
  if (paint[3] !== 1) throw new Error('Modal interior sampling requires opaque backing')
}
```

Preserve all paint-effect rejection, actual text/glyph/outline property selection, composition, luminance, thresholds and hit testing. This composes only the **opaque interior**, never the native backdrop or page behind it. Record modal screenshots and existing `chat_dialog_sample` output separately; no backdrop contrast claim. Ordinary inline history now participates in the ordinary ancestor sampler because it is not modal.

Replace `localization_test.rb`'s `assert_language_control_geometry` with this explicit signed-in modal sampler (the public-root compact-language test does not call it):

```ruby
def assert_language_control_geometry
  layout = page.evaluate_script(<<~JS)
    (()=>{const panel=document.querySelector('#chat-history'),form=panel.querySelector('.n-language-preference');
      const box=e=>e.getBoundingClientRect().toJSON(),focus=document.activeElement,style=getComputedStyle(focus);
      const logo=panel.querySelector('.n-orbite-logo'),select=form.querySelector('select'),r=select.getBoundingClientRect();
      const points=[[r.x+r.width/2,r.y+r.height/2],[r.left+2,r.y+r.height/2],[r.right-2,r.y+r.height/2]];
      return {overflow:document.documentElement.scrollWidth-innerWidth,panel:box(panel),logo:box(logo),control:box(select),
        wrap:getComputedStyle(form.parentElement).flexWrap,focus:box(focus),outline:style.outlineStyle,
        outlineWidth:parseFloat(style.outlineWidth),outlineOffset:parseFloat(style.outlineOffset),
        hits:points.map(([x,y])=>{const hit=document.elementFromPoint(x,y);return !!hit&&(hit===select||select.contains(hit))})};})()
  JS
  assert_equal 0, layout.fetch("overflow")
  assert_equal "wrap", layout.fetch("wrap")
  control = layout.fetch("control")
  assert control.fetch("left") >= layout.fetch("logo").fetch("right") || control.fetch("top") >= layout.fetch("logo").fetch("bottom")
  assert_operator control.fetch("left"), :>=, 0
  assert_operator control.fetch("right"), :<=, 375
  assert_operator control.fetch("bottom"), :<=, layout.fetch("panel").fetch("bottom")
  assert_operator control.fetch("width"), :>=, 44
  assert_operator control.fetch("height"), :>=, 44
  assert layout.fetch("hits").all?, layout.to_json
  assert_not_equal "none", layout.fetch("outline")
  assert_operator layout.fetch("outlineWidth"), :>=, 2
  outset = [ layout.fetch("outlineWidth") + layout.fetch("outlineOffset"), 0 ].max
  assert_operator layout.fetch("focus").fetch("left") - outset, :>=, 0
  assert_operator layout.fetch("focus").fetch("right") + outset, :<=, 375
end
```

The interior contrast thresholds are tested by the migrated header sampler; this geometry helper does not invent a contrast result. Public-root localization coverage retains its unchanged public branding and native control tests.

- [ ] **Step 5: Run all affected safe workspace selections, sequentially.**

```bash
record orbite-wide-regressions browser_test test/system/compact_headers_test.rb test/system/dashboard_test.rb test/system/accounts_settings_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb
record orbite-navigation-regressions browser_test test/system/localization_test.rb test/system/color_theme_test.rb test/system/account_experience_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/system/sources_workspace_upload_test.rb
```

Before launching the second group, audit those exact files and required support for external work: existing upload, MCP-connection, source-registration and catalog tests must use their existing local fixture/HTTP adapters or queue-only assertions. Do not execute queued crawl/index/embedding/provider jobs. A newly discovered live path blocks that case; record it as NOT RUN and seek a bounded safe adapter rather than weakening its assertions or silently running it. No runtime test is authorized during planning.

Retain actual command exits and counts rather than predicting the previous 73 workspace count. New tests and this larger navigation selection intentionally change totals. There is no separate commit for Steps 1–4 already committed with Task 2. If Step 5 finds a real bounded defect, add its own RED/GREEN correction commit and SPEC→QUALITY before advancing.

## Task 6: Add the new reflow, live-panel and current-opener regressions

**Files:** `test/system/chat_workspace_test.rb`, `test/system/orbite_workspace_test.rb`. Reuse the actual 80-paragraph fixture, existing reader anchor helpers and real Turbo renderer; do not mock geometry or freeze production delivery.

- [ ] **Step 1: Add the history-width reflow test to `ChatWorkspaceSystemTest`.**

```ruby
test "history width reflow preserves a paused paragraph without advertising new content" do
  visit_reader(1400, 1000)
  pause_reader
  anchor = reader_anchor
  page.execute_script("window.historyWidthEditor=document.querySelector('lexxy-editor')")
  [ false, true ].each do |open|
    find("#workspace-history-rail-trigger").click
    assert_selector "#workspace-history-rail-trigger[aria-expanded=#{open}]"
    settle_reader_animations
    assert_reader_following false
    assert_reader_anchor anchor
    assert_no_button "Latest message"
    assert page.evaluate_script("window.historyWidthEditor===document.querySelector('lexxy-editor')")
  end
  stream_answer(reader_answer(100))
  assert_button "Latest message"
  assert_reader_anchor anchor
  click_button "Latest message"
  assert_reader_following true
  assert_operator reader_gap, :<=, 80
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

Keep `assert_reader_anchor`'s 1px tolerance unchanged. A width-only change is not new message content.

- [ ] **Step 2: Add native current-opener replacement and same-page morph tests to `OrbiteWorkspaceSystemTest`.**

Add `include Turbo::Broadcastable::TestHelper` and `include ActionView::RecordIdentifier` to the class and `require "turbo/broadcastable/test_helper"` to that file. Then add:

```ruby
test "mobile navigation returns focus to its current streamed composer opener" do
  orbite_viewport(375, 812)
  @chat.start_generation!
  visit chat_path(@chat)
  trigger = "[data-orbite-composer-navigation]"
  page.execute_script("window.oldOrbiteTrigger=document.querySelector(arguments[0])", trigger)
  find(trigger).click
  assert_selector "#chat-history:modal"
  @chat.stop_generation!
  Current.reset
  replacement = ApplicationController.render(
    inline: '<%= turbo_stream.replace target, partial: "messages/form", locals: { chat: chat } %>',
    locals: { target: "#{dom_id(@chat)}_message_form", chat: @chat })
  page.execute_script("Turbo.renderStreamMessage(arguments[0])", replacement)
  assert_selector "button[aria-label=Send]:not([disabled])", visible: :all
  refute page.evaluate_script("window.oldOrbiteTrigger.isConnected")
  assert_selector "#chat-history:modal"
  page.driver.browser.action.send_keys(:escape).perform
  assert_selector "#{trigger}:focus"
  orbite_assert_reachable(trigger)
  assert_no_enqueued_jobs only: ChatResponseJob
end

test "same page refresh retains collapsed wide history without duplicate interactive ids" do
  orbite_viewport(1400, 1000)
  visit chat_path(@chat)
  find("#workspace-history-rail-trigger").click
  assert_no_selector "#chat-history[open]", visible: :all
  find("lexxy-editor .lexxy-editor__content").send_keys("Refresh draft")
  page.execute_script("Turbo.visit(location.href, {action:'replace'})")
  assert_selector "lexxy-editor[connected]"
  orbite_settle
  assert_selector "#workspace-history-rail-trigger[aria-expanded=false]"
  assert_no_selector "#chat-history[open]", visible: :all
  ids = page.evaluate_script("[...document.querySelectorAll('[id]')].map(e=>e.id)")
  assert_equal ids.uniq, ids
  find("#workspace-history-rail-trigger").click
  assert_selector "#chat-history[data-inline=true][open]"
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

Use the existing real same-page `Turbo.visit` refresh pattern from `refresh_workspace`, with an actual `turbo:render` readiness marker rather than accepting pre-refresh markup. Replace the simple visit/settle lines above with:

```ruby
page.execute_script(<<~JS)
  document.documentElement.removeAttribute('data-orbite-refreshed')
  document.addEventListener('turbo:render', () => document.documentElement.dataset.orbiteRefreshed = 'true', { once: true })
  Turbo.visit(location.href, { action: 'replace' })
JS
assert_selector "html[data-orbite-refreshed=true]"
assert_selector "lexxy-editor[connected]"
orbite_settle
assert_selector "lexxy-editor .lexxy-editor__content", text: "Refresh draft"
```

This is the existing same-page morph path, not a promise that full navigation preserves unsent file choices. Do not substitute a synthetic lifecycle event.

- [ ] **Step 3: Run the selected regressions before making any correction.**

```bash
record orbite-new-boundaries browser_test test/system/orbite_workspace_test.rb test/system/chat_workspace_test.rb -i '/history_width_reflow|current_streamed_composer_opener|same_page_refresh/'
```

These are additional behavior-characterization tests over the implementation. PASS without production change is valid; do not manufacture a RED. A real failure requires a genuine reproducer before correction. Confine any correction to the already listed navigation/modal/ownership CSS paths; reader-algorithm, business logic, transport or persistence expansion requires authorization. Preserve all established focus/stream/privacy assertions.

- [ ] **Step 4: Commit the additional coverage after GREEN and review.**

```bash
git diff --check
git add -- test/system/chat_workspace_test.rb test/system/orbite_workspace_test.rb
git commit -m "test(chat): Protect Orbite history reflow and focus ownership"
```

Pass SPEC→QUALITY. If a correction was needed, commit its exact owned files with its RED/GREEN evidence separately; do not conceal production changes inside the coverage-only commit.

## Task 7: Document the current boundary and verify the complete safe selection

**Files:** New `docs/orbite-workspace.md`; `docs/chat-workspace.md`, `docs/chat-composer.md`, `docs/compact-headers.md`, `docs/README.md`. Execution reports remain external under `$EVIDENCE`.

- [ ] **Step 1: Write `docs/orbite-workspace.md` with the following content.**

```markdown
# Orbite workspace

Signed-in pages share a slim application rail and an inset content surface.
Home, New chat, Accounts, Sources, usage, Settings, Profile and sign-out keep
their existing routes and authorization. Appearance/profile opens the unique
native language, theme and profile controls. Signed-out pages keep their public
branding and controls and never render private history.

## Responsive navigation

Chat pages show personal history inline at CSS widths of 1280px and above,
initially open and collapsible. At 768–1279px the rail stays visible and history
starts closed. Below 768px one on-demand native panel contains navigation and
history; no competing bottom pill is present. Other pages reserve no history
column and make no global history query.

One panel owns the authorized chat history. Entries remain personal root chats
in accessible accounts, with escaped title previews, account/date/current-item
context, empty guidance and unchanged confirmed deletion. This is not chat
renaming, search, folders or pinning. Expansion is temporary page state, not a
new persisted preference.

Native modal focus/inert behavior applies on tablet/mobile. Close/Escape returns
focus to the current opener, including a replacement composer trigger. Desktop
inline history is not modal. The shared chat-dialog controller is the sole
native-modal/focus owner for navigation and Tools. Breakpoint and Turbo-cache
cleanup must never leave a hidden focused control or inert page.

## Conversation and composer

On chat pages, #application-scroll is an explicit reading surface containing
compact context and the transcript. Context scrolls away. The composer has a
reserved bottom area and never covers messages; long drafts scroll inside the
native bounded editor. The mobile composer's navigation action remains available
when context is offscreen, including during generation. No-account new chats show
existing setup guidance instead of an active decorative editor.

Other pages use main#application-scroll as their content scroller. Dialogs,
history, editor, code and wide tables may scroll locally; they do not become a
second conversation owner. The 80px pre-growth follow rule, 1px paused-paragraph
tolerance, genuine-new-content Latest and own-success-only resume remain unchanged.

The premium finish uses system fonts, restrained light/dark materials, bounded
16px prose, quiet user bubbles and open assistant text. Sources/count, Reasoning,
response details, Usage and required error/guidance remain discoverable. Native
PDF uploads, formatting, account/source coordination, Tools, Send/Stop/Retry,
localized streaming and accounting retain their existing owners and identities.
Background form rendering retains its authoritative uncached busy/stopped read.

## Verification boundaries

See the approved [specification](superpowers/specs/2026-10-30-premium-chat-experience-design.md)
and [implementation plan](superpowers/plans/2026-10-30-orbite-premium-chat.md) for
explicit isolated selections and evidence gates. Prior compact-header results
are historical, not proof of this layout. Fresh command exits/counts, geometry,
contrast and screenshots belong in the implementation evidence manifest.

CSS viewport/CDP and enlarged-CSS-text checks are not native browser zoom or
physical on-screen-keyboard verification. Screen-reader operation, native zoom,
physical/mobile-keyboard behavior and live providers remain separately unverified
unless actually performed. Do not execute unsafe full-suite/crawl/index/provider
work or alter user-owned environment/development processes.

The existing narrow Turbo-native focus-restoration exception, GET /login
waiting-scaffold issue and two exact Brakeman baseline fingerprints remain
scoped limitations; no new failure or warning is waived. No full-suite or
security-clean claim is made.
```

- [ ] **Step 2: Update the superseded documentation without rewriting old evidence.**

In `docs/chat-workspace.md`, replace the History paragraphs before “New-chat account selection” with:

```markdown
**History** is initially inline and collapsible on chat pages at CSS widths of
1280px and above. Tablet history starts closed; mobile navigation and history
share one on-demand native panel. Inline history is nonmodal. Modal History
contains keyboard focus; Escape or Close returns it to the current opener.
See [Orbite](orbite-workspace.md) for the shared shell and responsive contract.

History lists only your root conversations in accounts you currently belong
to—not another member's chats or child conversations. Entries show a plain-text
title preview, account, activity time, and current conversation, ordered by recent
activity. Titles come from the first question, with a localized fallback and a
120-character limit; the full question remains in the transcript. This is not
conversation renaming. Opening a conversation uses existing authorization;
deletion still asks for confirmation and uses the existing home redirect.
Empty history has a localized explanation.
```

The replacement preserves all personal-root membership/title/date/delete/empty guarantees and the full-question/120-character contract. Replace the old paragraph beginning “At every viewport size” through “Reduced-motion settings” with:

```markdown
On chat pages, #application-scroll is the single reading surface containing
compact context and transcript, above a separately reserved composer. Context
scrolls away; the composer remains accessible without covering messages.
Other pages use main#application-scroll. History, bounded editors, dialogs,
wide code and tables may scroll locally. Reduced motion remains respected.
This intentionally supersedes the old outer-scroller/in-flow-composer and
mobile-bottom-pill arrangement; see [Orbite](orbite-workspace.md).
```

Keep the 80px, own-submit, status, scoped freshness and accepted Turbo-race sections unchanged. Before its historical dated verification paragraph add:

```markdown
The following compact-header results predate Orbite and remain historical.
Fresh Orbite evidence must be reported separately; old counts are not reused
as a pass for the current shell.
```

In `docs/chat-composer.md`, replace the entire “Dedicated chat-page shell” body with:

```markdown
New and saved chat pages use the [Orbite workspace](orbite-workspace.md).
The native composer occupies a reserved bottom zone; its explicit navigation
local adds a mobile launcher outside generation-inert editing tools. Dashboard
composition stays in flow. Shared signed-in shell/composer tokens are scoped
under .n-orbite-shell; the public theme preference remains unchanged.

The shared shell's chat-dialog controller owns native Tools/navigation focus.
Add/Remove, uploads, submission/Stop ownership and background-renderable explicit
locals are unchanged. Messages/form retains the uncached account-scoped
busy/stopped presentation read. Redesigned Send/Stop controls are at least
44px; earlier 40px composer measurements are historical.
```

Replace only `40px Send/Stop targets` in its current styling guidance with `at least 44px Send/Stop targets under the Orbite shell (legacy 40px outside it)`. Directly above its old verification command block add **“Historical commands, not the current safe execution recipe. Do not run the unrestricted suite shown here; use the explicit isolated Orbite plan selection.”** Keep dated results unchanged.

Add after `docs/compact-headers.md`'s title:

```markdown
Historical presentation boundary: the signed-in global bar, outer chat scroller,
flow composer and mobile bottom-pill descriptions below are superseded by
[Orbite](orbite-workspace.md). Compact page headings, native Details, visible
scope/role, reader/input safeguards and the recorded limitations still apply.
This document's old geometry/results are not fresh Orbite verification.
```

In `docs/README.md` replace the compact-header quick link with:

```markdown
- [Orbite workspace](orbite-workspace.md) — shared rail, responsive private history, reading surface and reserved native composer.
- [Compact application headers](compact-headers.md) — retained page-heading safeguards and the explicitly superseded earlier shell boundary.
```

- [ ] **Step 3: Run the full explicit final selection sequentially.**

Run only during authorized implementation, after checking file existence and local-adapter safety. Each shell begins with the existing helper and exports its actual source SHA; never run against development processes.

```bash
record orbite-final-build rails_test tailwindcss:build
record orbite-final-focused rails_test test test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb test/controllers/chat_account_url_race_test.rb test/controllers/chat_sources_controller_test.rb test/models/chat_test.rb test/models/dashboard_recents_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/profiles_controller_test.rb test/internationalization/catalogs_test.rb test/integration/token_footer_test.rb
record orbite-final-chat browser_test test/system/orbite_workspace_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb
record orbite-final-workspaces browser_test test/system/dashboard_test.rb test/system/accounts_settings_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb
record orbite-final-navigation browser_test test/system/localization_test.rb test/system/color_theme_test.rb test/system/account_experience_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/system/sources_workspace_upload_test.rb
```

Require actual nonzero test counts and zero unexpected failures/errors/skips for every executed group. Explain any safety-blocked case separately rather than claiming that selection passed. Capture the existing real PDF bytes, account/source safeguards, native input/resize ordering, Usage/Latest overlap, partial Stop/eligible Retry, stale distinct-worker Stop feedback and broadcast totals evidence. No worker job is executed to manufacture verification.

- [ ] **Step 4: Lint the actual changed Ruby files and compare exact security fingerprints.**

```bash
git diff --name-only --diff-filter=ACMR 7189d6de425122120f3fb4d7090d16a9ebb88f11 -- '*.rb' > "$EVIDENCE/orbite-changed-ruby.txt"
record orbite-final-lint test_command bundle exec ruby -e 'files=File.readlines(ARGV.fetch(0),chomp:true); abort "No Ruby files" if files.empty?; exec "bundle","exec","rubocop",*files' "$EVIDENCE/orbite-changed-ruby.txt"
if record orbite-final-security test_command bundle exec brakeman --no-pager --format json --output "$EVIDENCE/orbite-final-security.json"; then
  security_exit=0
else
  security_exit=$?
fi
test "$security_exit" -eq 0 || test "$security_exit" -eq 3 || exit "$security_exit"
record orbite-security-compare python3 -c 'import json,sys; from pathlib import Path; root=Path(sys.argv[1]); old=json.loads((root/"task7-baseline-security.json").read_text()); new=json.loads((root/"orbite-final-security.json").read_text()); a={w["fingerprint"] for w in old["warnings"]}; b={w["fingerprint"] for w in new["warnings"]}; result={"new":sorted(b-a),"removed":sorted(a-b),"errors":new.get("errors",[])}; print(json.dumps(result,indent=2)); sys.exit(0 if a==b and not result["errors"] else 1)' "$EVIDENCE"
record orbite-js-navigation node --input-type=module --check < app/javascript/controllers/workspace_navigation_controller.js
record orbite-js-dialog node --input-type=module --check < app/javascript/controllers/chat_dialog_controller.js
record orbite-js-reader node --input-type=module --check < app/javascript/controllers/scroll_controller.js
record orbite-js-disclosures node --input-type=module --check < app/javascript/controllers/chat_disclosures_controller.js
record orbite-js-feedback node --input-type=module --check < app/javascript/controllers/chat_feedback_controller.js
git diff --check
git diff --stat 7189d6de425122120f3fb4d7090d16a9ebb88f11
```

Use only the already installed syntax runtime; no Node dependency/build is added. Preserve the helper's RuboCop target. The two baseline fingerprints are:

```text
4fad3c218f35052d2f3a3eff4544480d05b60bc9199a001ec6242a8921b93ae3
d84924377155b41e094acae7404ec2e521629d86f97b0ff628e3d1b263f8101c
```

Exit 3 is not itself permission to accept warnings: require exact set equality and no scan errors. Inspect unexpected removals too; do not suppress/upgrade dependencies to pass this UI task. If the previous baseline artifact is unavailable, stop rather than inventing its JSON. Check changed Markdown relative links/anchors. Do not add broad cleanup or stage generated CSS/evidence ignored by the project.

- [ ] **Step 5: Write the final evidence manifest before claiming completion.**

Write `$EVIDENCE/orbite-final-manifest.md` with actual values for:

- Implementation baseline and exact verified source/diff; each task commit and SPEC→QUALITY decision.
- Exact commands, raw logs, true exit files, test counts/assertions/seeds, build/lint/JS results and exact warning comparison.
- EN/FR × light/dark × saved/new × four actual CSS viewports; eleven signed-in page families, plus API-token/system-prompt reachability and signed-out separation.
- Real bounds/hits, text ≥4.5, controls/icons ≥3, visible ≥2px focus, ≥44px redesigned targets, prose measure and reduced motion. Distinguish decorative edges from actionable controls and unchanged legacy Tools close.
- Screenshot paths actually opened/inspected, before/after geometry, synthetic overflow labels and real long-chat evidence. No pass inferred from filenames.
- The privacy/upload/generation/accounting/reader invariants, current-opener replacement, resize/cache cleanup, history reflow and native held-Shift+Tab evidence.
- Manual NOT RUN boundaries: native zoom, screen readers, physical mobile keyboard, live providers and unsafe full suite; accepted old login/security/focus limitations, plus any newly blocked check.
- Confirmation that no user environment/development process, route/schema/backend, transport, package/driver or live-worker operation was changed.

Append a short dated “Orbite selected verification” section to `docs/orbite-workspace.md` only after actual evidence exists; copy actual source/counts/exits and limitations, not predicted values or old results. Do not put secrets or external `/tmp` log contents in tracked documentation.

- [ ] **Step 6: Commit docs, complete the whole-feature review and await integration instructions.**

```bash
git add -- docs/orbite-workspace.md docs/chat-workspace.md docs/chat-composer.md docs/compact-headers.md docs/README.md
git commit -m "docs(ui): Explain Orbite navigation and reading boundaries"
git status --short
```

After all task SPEC→QUALITY gates, review the entire Orbite diff against the approved spec and preserved application baseline. In the chosen subagent mode, dispatch an independent whole-feature reviewer with exact commits and manifest; in inline mode use its review checkpoint and explicitly disclose any independent review still pending. A new Important/Critical finding needs its own test-first bounded correction and re-review. Only then report the actual outcome and ask what the user wants to do with the branch. Do not merge, push, open a PR or remove a worktree automatically.

## Coverage and planning self-review

| Approved requirement | Implementation and evidence |
| --- | --- |
| Slim shared rail, coherent inset canvas, public separation and all old destinations | Tasks 1–2, 5 and 7; shell request matrix plus existing scoped-action/controller tests |
| Single private dataset; current/account/date/escaped previews, empty state, confirmed authorized delete | Tasks 1–2; unchanged controller/privacy tests and real navigation/delete browser cases |
| ≥1280 inline history; tablet collapsed; unified mobile panel; no bottom pill | Task 2 native tests, Task 5 mode-aware matrices, Task 6 reflow |
| No hidden focus/inert leftovers, one modal owner, current opener after replacement, cache cleanup | Tasks 2, 5–6; existing Tools replacement/cache tests plus new streamed mobile trigger |
| Context scrolls away; separately reserved native composer; mobile opener during generation | Task 3 explicit surface/dock geometry and generation case |
| Both themes, premium system typography/materials, open assistant prose, quiet user bubble | Tasks 2 and 4 with actual screenshots/measurements |
| Sources/count, Reasoning, Usage, errors/Retry and required guidance discoverable | Unchanged partials; Tasks 4–5 preserved stateful keyboard/contrast/Usage regressions |
| Real uploads, native formatting, long drafts, account/source/Tools/Stop, stable IDs/localized streams/totals | Tasks 3–5 and final protected selections; authoritative worker freshness is unchanged |
| 80px pre-growth, 1px shared paragraph anchors, Latest/new-content, success-only resume | Task 3 wiring-only reader cutover, Task 6 history reflow, full protected regressions |
| Trusted native input/resize, Usage/HUD/newer-input ordering and accepted Turbo exception | Task 3 exact owner lookup migration; Task 5 preserved timing/traces/oracles, no delivery gate |
| EN/FR, themes, four viewports, long labels, native Tab/held Shift+Tab, pointer/Enter/Space, focus/contrast/44px/reduced motion | Tasks 2, 4–6 and final matrix/evidence inspection |
| Sequential isolated safety, actual evidence/security fingerprints, honest manual limits, no auto-integration | Task 0, all task gates, Task 7 |

Execution sequence: **0 → 1 → 2 (including 5.1–5.4) → 3 → 4 → 5.5 → 6 → 7**. The printed Task 2 browser listings are prepared with its initial RED, not after implementation. Every cutover's coupled test migrations belong to its own accepted commit. No production code, Rails boot, build, database operation or application test is performed by writing this plan.

The planning self-review must statically check relative links, existing-versus-created paths, code-block syntax, named methods/targets/outlets/locals, test-first ordering and the above coverage. It is a parent review, not a plan-review subagent dispatch. Final implementation claims still require Task 7's runtime evidence and chosen execution-mode authorization.

### Planning validation record — 2026-10-30

- Parent self-review mapped every approved design section and acceptance row to
  the tasks above; no plan-review subagent was dispatched.
- Corrected the shell/dock task reference, test-first browser ordering and coupled
  legacy-test sequencing. Test-only navigation migrations are owned by Task 2,
  not deferred until after its acceptance.
- Preserved the MCP/Skills scoped New chat shortcuts and added their actual
  mobile-panel keyboard path to the explicit migration inventory.
- Checked controller method names, targets, outlet names, stable modal/composer
  opener IDs, explicit locals and current-opener fallback across the listings.
- Static parsing checked all 30 Ruby blocks, two complete JavaScript controllers,
  19 shell blocks and two YAML blocks. Six CSS blocks have balanced braces.
  Referenced 72 literal source/test/doc paths; the 13 absent paths are declared
  new files, not unexplained missing dependencies. No unresolved placeholder or
  missing relative linked destination was found, accounting for doc examples
  intended for the docs directory and the explicitly planned Orbite guide.
- These are documentation/static syntax checks only. No application code, Rails
  boot, build, database operation, application/browser test or security scan was
  executed for planning. Runtime behavior and measured accessibility remain
  subject to the implementation gates, not established by these listings.
