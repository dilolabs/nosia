# Remove Topbar Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Only dispatch subagents if the user explicitly selects delegated execution.

**Goal:** Completely remove the existing topbar search and its exclusively owned support code without adding replacement search or changing backend retrieval.

**Architecture:** Delete the search branch from the shared header and remove its partial. Remove the now-unused helper, icon, translations, and Tailwind Plus Elements dependency. Existing header controls, shared JavaScript libraries, and all search/retrieval models other than the unused recent-chat helper retain their contracts.

**Tech Stack:** Checked-in Ruby runtime (`.ruby-version`: 4), Rails 8.0, PostgreSQL, Minitest with existing fixtures, ERB, Hotwire, Importmap, Propshaft, and Tailwind CSS. Do not perform stack upgrades as part of this change.

**Approved specification:** `docs/superpowers/specs/2026-10-23-remove-topbar-search-design.md`.

---

## File map

| Action | File | Responsibility |
| --- | --- | --- |
| Create | `test/integration/header_navigation_test.rb` | Header rendering across authentication/account contexts and both locales; dependency removal. |
| Modify | `app/views/application/_header.html.erb` | Remove only the old search trigger and partial render. |
| Delete | `app/views/application/_search.html.erb` | Remove the command-palette dialog and its eager queries. |
| Modify | `app/models/user.rb` | Remove the otherwise unused `recent_chats` method. |
| Delete | `app/assets/images/svg/search.svg` | Remove the old trigger's exclusively owned icon. |
| Modify | `config/locales/en.nosia_shell.yml`, `config/locales/fr.nosia_shell.yml` | Remove only seven search-specific navigation keys. |
| Modify | `app/javascript/application.js` | Stop importing Tailwind Plus Elements. |
| Modify | `config/importmap.rb` | Remove the Tailwind Plus Elements pin. |
| Delete | `vendor/javascript/@tailwindplus--elements.js` | Remove the unused vendored dependency. |

Preserve `app/views/application/_language_preference.html.erb`, all existing styles, `svg/file-search.svg`, other `User` methods, Flowbite, Turbo, Stimulus, Lexxy, routes, and backend search. Existing locale files already contain unrelated language-selector edits; do not overwrite or commit those edits.

## Task 0: Establish a safe baseline

- [ ] **Step 1: Inspect the workspace and dependencies.**

Run these commands separately:

```sh
git status --short --branch
git diff --cached --name-only
bundle check
```

Use an isolated feature branch/worktree when executing if the current workspace cannot safely accommodate these changes. Do not reset, stash, discard, or absorb existing user work. Recheck scoped files for concurrent edits. If another task has staged changes, stop before staging this task's changes.

- [ ] **Step 2: Check ownership of the code scheduled for removal.**

```sh
rg -n 'recent_chats|svg/search\.svg|<el-|@tailwindplus|nosia\.nav\.(search|search_placeholder|quick_actions|ask_question|jump_to|no_search_results)' app config test vendor/javascript --glob '!@tailwindplus--elements.js'
```

Expected: runtime usage is limited to the existing search partial, header, helper, and dependency wiring. Inspect any newly introduced caller before deleting shared code; do not silently expand the removal scope. Historical documents are not runtime consumers.

- [ ] **Step 3: Run the existing targeted regressions before modifying application code.**

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/controllers/chat_account_access_test.rb test/controllers/localization_test.rb test/controllers/language_preferences_controller_test.rb
```

Expected: zero failures/errors. These processes use the configured PostgreSQL test database and existing encryption environment. If dependencies, database access, encryption configuration, or assets prevent booting, report the exact error; do not treat an infrastructure error as the required failing behavioral test. Do not print `.env` or real credentials, run AI/MCP workers, or change database configuration.

## Task 1: Remove the search UI and exclusively owned application support

**Files:** Create `test/integration/header_navigation_test.rb`; modify `app/views/application/_header.html.erb`, `app/models/user.rb`, and both shell locale files; delete `app/views/application/_search.html.erb` and `app/assets/images/svg/search.svg`.

- [ ] **Step 1: Write the header regression tests.**

Create `test/integration/header_navigation_test.rb` with this complete content:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class HeaderNavigationTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  %w[en fr].each do |locale|
    test "account headers omit search and preserve controls in #{locale}" do
      sign_in_picker_user

      [ user_root_url, new_chat_url(account_id: @second.id), chat_url(chats(:picker_second_chat)) ].each do |url|
        get url, headers: { "Accept-Language" => locale }

        assert_header_without_search(locale: locale, signed_in: true)
      end
    end

    test "no-account headers omit search and preserve controls in #{locale}" do
      sign_in_picker_user(users(:picker_no_account))

      [ user_root_url, new_chat_url ].each do |url|
        get url, headers: { "Accept-Language" => locale }

        assert_header_without_search(locale: locale, signed_in: true)
      end
    end

    test "anonymous headers omit search and preserve controls in #{locale}" do
      get root_url, headers: { "Accept-Language" => locale }

      assert_header_without_search(locale: locale, signed_in: false)
    end
  end

  private
    def assert_header_without_search(locale:, signed_in:)
      assert_response :success
      assert_select "html[lang='#{locale}']"
      assert_select "#toggleSidebarMobileSearch", count: 0
      assert_select "[commandfor=dialog]", count: 0
      assert_select "dialog#dialog", count: 0
      assert_select "el-command-palette", count: 0

      assert_select "body > nav", count: 1 do
        assert_select "a[href='#{root_path}'] img", count: 1
        assert_select "form[action='#{language_preference_path}'] select#language_preference_locale", count: 1
        assert_select "#theme-toggle", count: 1
        assert_select "#dropdownUser", count: signed_in ? 1 : 0
        assert_select "#dropdown a[href='#{profile_path}']", count: signed_in ? 1 : 0
        assert_select "#dropdown a[href='#{settings_path}']", count: signed_in ? 1 : 0
        assert_select "#dropdown a[href='#{logout_path}']", count: signed_in ? 1 : 0
      end
    end
end
```

Keep these fixtures opt-in through `ChatAccountFixtures`. Do not add fixtures to `test/fixtures` or change `test/test_helper.rb`.

- [ ] **Step 2: Run the new tests and confirm the behavioral failure.**

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/header_navigation_test.rb
```

Expected: the authenticated-with-account tests fail because `#toggleSidebarMobileSearch` is still present. Anonymous and no-account cases should already pass. Do not change application code until this intended failure has been observed.

- [ ] **Step 3: Remove the search branch, helper, and files.**

Apply these exact removals without rewriting surrounding code:

```diff
--- a/app/views/application/_header.html.erb
+++ b/app/views/application/_header.html.erb
@@
     <%= render "language_preference" %>
     <div class="flex items-center">
-      <% if Current.user && Current.account %>
-        <button command="show-modal" commandfor="dialog" id="toggleSidebarMobileSearch" type="button" class="n-nav-link n-main-hover">
-          <span class="sr-only"><%= t("nosia.nav.search") %></span>
-          <%= inline_svg "svg/search.svg", aria_hidden: true, class:"w-5 h-5" %>
-        </button>
-        <%= render "search" %>
-      <% end %>
       <button id="theme-toggle" type="button" class="n-nav-link n-main-hover">
--- a/app/models/user.rb
+++ b/app/models/user.rb
@@
   def first_account
     accounts.order(:created_at).first
   end
-
-  def recent_chats(limit: 5)
-    chats.order(:created_at).limit(limit)
-  end
 end
```

Delete the complete files with the patch tool:

```text
*** Begin Patch
*** Delete File: app/views/application/_search.html.erb
*** Delete File: app/assets/images/svg/search.svg
*** End Patch
```

Do not insert replacement markup, a disabled button, keyboard hooks, extra spacing, or a feature flag.

- [ ] **Step 4: Remove the seven search-only translation keys.**

Apply only the deletions below, preserving all other entries and in-progress edits. This is also the exact selective-staging patch: save it as `/tmp/opencode/remove-topbar-search-locales.patch` using the patch tool, for Step 6. Its line numbers target the committed baseline; Git can match surrounding context when the working copy has extra language keys above it.

```diff
diff --git a/config/locales/en.nosia_shell.yml b/config/locales/en.nosia_shell.yml
--- a/config/locales/en.nosia_shell.yml
+++ b/config/locales/en.nosia_shell.yml
@@ -41,9 +41,2 @@
       delete_chat: "Delete chat"
-      search: "Search"
-      search_placeholder: "Search..."
-      recent_chats: "Recent chats"
-      quick_actions: "Quick actions"
-      ask_question: "Ask any question..."
-      jump_to: "Jump to..."
-      no_search_results: "We couldn’t find any projects with that term. Please try again."
       dark_mode: "Dark mode"
diff --git a/config/locales/fr.nosia_shell.yml b/config/locales/fr.nosia_shell.yml
--- a/config/locales/fr.nosia_shell.yml
+++ b/config/locales/fr.nosia_shell.yml
@@ -41,9 +41,2 @@
       delete_chat: "Supprimer la conversation"
-      search: "Rechercher"
-      search_placeholder: "Rechercher…"
-      recent_chats: "Conversations récentes"
-      quick_actions: "Actions rapides"
-      ask_question: "Posez votre question…"
-      jump_to: "Accéder à…"
-      no_search_results: "Aucun projet ne correspond à ce terme. Veuillez réessayer."
       dark_mode: "Mode sombre"
```

- [ ] **Step 5: Run the new tests and the existing focused regressions.**

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/header_navigation_test.rb test/controllers/chat_account_access_test.rb test/controllers/localization_test.rb test/controllers/language_preferences_controller_test.rb
```

Expected: all tests pass, including six new header tests. Fix only removal-related failures; preserve account isolation and all existing localization assertions.

- [ ] **Step 6: Inspect and commit only this task's changes.**

Only stage these complete files if Step 0 confirmed they had no pre-existing edits:

```sh
git add -- test/integration/header_navigation_test.rb app/views/application/_header.html.erb app/views/application/_search.html.erb app/models/user.rb app/assets/images/svg/search.svg
git apply --cached --check /tmp/opencode/remove-topbar-search-locales.patch
git apply --cached /tmp/opencode/remove-topbar-search-locales.patch
git diff --cached --check
git diff --cached
git commit -m "refactor(search): Remove the topbar search interface"
```

Run commands separately and inspect the staged diff before committing. If any clean-file assumption changed, stop and stage only this task's exact hunks; never include another task's edits. The locale diff must contain only the seven removed keys per locale. After the commit, unrelated language-selector additions must remain uncommitted if they were uncommitted before.

## Task 2: Remove the now-unused browser dependency

**Files:** Modify `test/integration/header_navigation_test.rb`, `app/javascript/application.js`, and `config/importmap.rb`; delete `vendor/javascript/@tailwindplus--elements.js`.

- [ ] **Step 1: Add a dependency regression test before `private` in `HeaderNavigationTest`.**

```ruby
  test "the application importmap omits the removed search dependency" do
    get root_url

    assert_response :success
    assert_select "script[type=importmap]", count: 1 do |scripts|
      imports = JSON.parse(scripts.first.content).fetch("imports")

      refute imports.key?("@tailwindplus/elements")
      %w[application @hotwired/turbo-rails @hotwired/stimulus flowbite lexxy].each do |name|
        assert imports.key?(name), "Expected shared import #{name} to remain"
      end
    end
  end
```

- [ ] **Step 2: Run the new dependency test and observe the intended failure.**

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/header_navigation_test.rb -n /importmap/
```

Expected: failure at the `refute` because Tailwind Plus Elements is still pinned. A parse/boot error is not the intended failure.

- [ ] **Step 3: Remove the import, pin, and vendored file together.**

```diff
--- a/app/javascript/application.js
+++ b/app/javascript/application.js
@@
 import "@hotwired/turbo-rails"
 import "controllers"
-import "@tailwindplus/elements"
 import "flowbite"
 import "lexxy"
--- a/config/importmap.rb
+++ b/config/importmap.rb
@@
 pin "flowbite-datepicker" # @1.3.2
-pin "@tailwindplus/elements", to: "@tailwindplus--elements.js" # @1.0.13
 pin "lexxy", to: "lexxy.js" # Rich text editor [https://github.com/excid3/lexxy]
```

```text
*** Begin Patch
*** Delete File: vendor/javascript/@tailwindplus--elements.js
*** End Patch
```

Do not remove any other vendored package or change the Gemfile, lockfile, or shared imports.

- [ ] **Step 4: Run all seven new header tests.**

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/header_navigation_test.rb
```

Expected: seven tests pass with no failures/errors.

- [ ] **Step 5: Inspect and commit the dependency cleanup.**

```sh
git add -- test/integration/header_navigation_test.rb app/javascript/application.js config/importmap.rb vendor/javascript/@tailwindplus--elements.js
git diff --cached --check
git diff --cached
git commit -m "chore(search): Remove unused Tailwind Plus Elements"
```

Apply the same pre-existing-edit safeguards as Task 1.

## Task 3: Verify the complete removal and review the scope

- [ ] **Step 1: Check for dangling runtime references.**

```sh
rg -n 'toggleSidebarMobileSearch|commandfor="dialog"|<el-|render "(application/)?search"|recent_chats|svg/search\.svg|@tailwindplus|nosia\.nav\.(search|search_placeholder|quick_actions|ask_question|jump_to|no_search_results)' app config vendor/javascript
```

Expected: no matches (ripgrep exit status 1). Test assertions and historical spec/plan text intentionally retain old names and are excluded. Confirm `app/assets/images/svg/file-search.svg` still exists and both navigation-menu uses remain.

- [ ] **Step 2: Re-run the focused suite sequentially and lint changed Ruby.**

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/header_navigation_test.rb test/controllers/chat_account_access_test.rb test/controllers/localization_test.rb test/controllers/language_preferences_controller_test.rb test/integration/chat_composer_ui_test.rb
RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app/models/user.rb config/importmap.rb test/integration/header_navigation_test.rb
```

Expected: zero new failures/errors and no lint offenses. Record counts and exact blockers without rewriting unrelated tests or configuration. Test processes share a database; do not run them in parallel.

- [ ] **Step 3: Validate production asset precompilation.**

```sh
AI_API_KEY=nosia-test-key RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

Expected: successful Tailwind/Propshaft compilation without missing search SVG or Tailwind Plus Elements references. This may create ignored build artifacts; do not stage them, remove unrelated artifacts, or run broad cleanup commands. Report unavailable credentials/database/runtime setup as an explicit verification blocker, not as a pass.

- [ ] **Step 4: Smoke-check remaining browser controls.**

Using the existing development environment, inspect an anonymous page, an account-owning user's chat page, and a no-account user's page. In English and French, at desktop and narrow mobile width, confirm there is no search button, empty placeholder, or search dialog. Confirm the language selector, theme toggle, home link, and authenticated user menu remain usable; verify both light and dark themes and no missing-import browser errors. Do not introduce a replacement control or change styles to make this check pass.

- [ ] **Step 5: Review the final diff and report verified results.**

```sh
git status --short
git diff --check
git log -2 --oneline
```

Review the two task commits against the approved specification: all seven translation keys removed in both locales, only `recent_chats` removed from `User`, all three obsolete files deleted, no backend search changes, no replacement UI, and no unrelated work staged or committed. No new public Ruby API was introduced, so new YARD documentation is not required. The approved spec/plan documents this removal; do not rewrite historical docs or advertise a replacement.

Report the removal scope, actual test/lint/asset results, any browser verification performed, and exact outstanding blockers. Do not claim tests or browser interactions passed without running them. Do not merge, push, or open a PR without authorization.
