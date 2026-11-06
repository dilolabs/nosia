# Rails 8.1 Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the existing test baseline and upgrade Nosia from Rails 8.0.5.1 to Rails 8.1.4.1.

**Architecture:** Preserve the current PostgreSQL, Hotwire, Solid Queue, RubyLLM, and authentication integrations. Repair obsolete presentation assertions rather than reverting the redesigned interface. Upgrade Rails dependencies first, then verify the 8.1 framework defaults separately.

**Tech Stack:** Ruby 4.0, Rails, PostgreSQL with pgvector, Minitest with fixtures, Importmap, Turbo, Stimulus.

---

### Task 1: Restore presentation test coverage

**Files:**
- Modify: `test/controllers/language_preferences_controller_test.rb`
- Modify: `test/integration/localized_pages_test.rb`
- Reference: `app/views/layouts/application.html.erb`
- Reference: `app/views/application/_header.html.erb`
- Reference: `app/views/messages/_assistant.html.erb`
- Reference: `app/views/messages/_thinking_animation.html.erb`

- [x] Reproduce the three existing failures:

```sh
bin/rails test test/controllers/language_preferences_controller_test.rb:61 test/integration/localized_pages_test.rb:816 test/integration/localized_pages_test.rb:929
```

Expected: three failures caused by obsolete HTML selectors.

- [x] Assert the current anonymous shell instead of removed utility classes:

```ruby
assert_select "#application-scroll[data-application-scroll]" do
  assert_select "nav[data-application-header].flex-wrap"
  assert_select "main.n-application-page"
end
```

- [x] Assert source and reasoning summaries by their stable message identities:

```ruby
assert_select "summary##{dom_id(message, :sources_summary)}", text: count == 1 ? "1 source" : "2 sources"
assert_select "summary##{dom_id(message, :reasoning_summary)}", text: "Afficher le raisonnement"
```

- [x] Keep explicit French copy expectations while selecting the current phase component:

```ruby
assert_select fragment, ".n-chat-phase-title", text: title
assert_select fragment, ".n-chat-phase .n-workspace-help", text: subtitle
```

- [x] Run both affected files. Result: 59 tests, 1,017 assertions, no failures or errors.

```sh
bin/rails test test/controllers/language_preferences_controller_test.rb test/integration/localized_pages_test.rb
```

### Task 2: Establish a complete Rails 8.0 baseline

**Files:**
- Inspect and, only when a reproduced failure requires it, modify: `test/models/website/crawlable_test.rb`
- Modify: `test/integration/localized_broadcasts_test.rb`
- Modify: `test/models/message_placeholder_test.rb`
- Modify: `test/integration/header_navigation_test.rb`
- Modify: `test/models/chat/request_options_test.rb`

- [x] Run `bin/rails test` with enough time for completion; preserve all failures before attempting fixes.
- [x] Investigate external embedding requests from the crawl conversion tests. Stub `RubyLLM.embed` locally and restore it in `ensure`, retaining the real chunk creation callbacks. Result: 3 tests, 7 assertions, no failures or errors with both provider URLs pointing to unavailable loopback port 9.
- [x] Repair two additional obsolete presentation expectations reproduced by the complete suite: assert the localized token unit in `.n-chat-token-total`, and assert the generation phase indicator rather than the removed spinner class.
- [x] Update header assertions for both anonymous and authenticated shells; cover augmented context enabled and disabled with restored environment state.
- [x] Repeat the complete suite until it passes. Baseline: 1,377 tests, 28,667 assertions, no failures, errors, or skips. Use `DATABASE_URL=postgresql:///nosia_rails81_test TMPDIR=/tmp/opencode/nosia81 PARALLEL_WORKERS=4 bin/rails test --seed 9831` to isolate the database and worker sockets. A prior shared-temporary-directory run lost its DRb socket; the single-process retry exceeded ten minutes without completing.
- [x] Present the compatibility findings and framework-default transition to the user for approval before changing Rails dependencies. User approved "Appliquer ce plan".

### Task 3: Upgrade Rails and adopt verified defaults

**Files:**
- Modify: `Gemfile`
- Regenerate: `Gemfile.lock`
- Modify: `config/application.rb`
- Modify: `config/database.yml`
- Update: `docs/ARCHITECTURE.md` and `docs/README.md` where they specify the framework version

- [x] After approval, create a dedicated upgrade branch without discarding existing changes: `rails-8.1.4.1-upgrade`.
- [x] Use the following Rails constraint, preserving unrelated dependency pins:

```ruby
gem "rails", "~> 8.1.0", ">= 8.1.4.1"
```

- [x] Run `bundle update rails --conservative`; review the lockfile diff for unrelated upgrades. Only Rails and its required HTML sanitization dependencies changed; Action Text adds `action_text-trix`, and Active Support no longer requires `benchmark`.
- [x] Run the complete suite with `config.load_defaults 8.0` first. Result: 1,377 tests and 28,667 assertions passed.
- [x] Review `bin/rails app:update --pretend --skip` changes without blindly overwriting custom configuration. Its nested Active Storage update still copied three historical migrations despite pretend mode; removed those generated files after confirming their changes already exist in the schema.
- [x] Enable finder ordering alone in a temporary initializer and run the full suite. Result: 1,377 tests and 28,667 assertions passed; no affected unordered models found.
- [x] Verify finder ordering and path-relative redirects, then adopt:

```ruby
config.load_defaults 8.1
```

- [x] Rename the connection pool setting without changing its capacity:

```yaml
max_connections: <%= ENV.fetch("RAILS_MAX_THREADS") { 7 } %>
```

- [x] Preserve production SSL settings and current storage behavior; do not install optional infrastructure merely because the application generator includes it.
- [x] Update framework-version documentation and record any deployment implications in `docs/upgrades/rails-8-1.md`.

### Task 4: Verify and review

- [x] Run `bin/rails test` and record final results: 1,377 tests, 28,667 assertions, no failures, errors, or skips with all 8.1 defaults.
- [x] Attempt `bin/rails test:system --fail-fast`; report limitations explicitly. Bundled Selenium Manager is x86-64 on this ARM64 host, so a temporary external preload selected `/usr/bin/chromedriver`. Result: 66 tests, 16,249 assertions, no assertion failures, one setup error in the unchanged Settings tools language helper. Reproduced that same error under the original Rails 8.0.5.1 lockfile and defaults using a temporary external comparison harness. Remaining system tests were not run; shared legacy browser-helper maintenance is a separate follow-up.
- [x] Run `RAILS_ENV=test bin/rails zeitwerk:check`: passed.
- [x] Run `bin/rubocop` on all nine changed Ruby/Gemfile files and inspect `git diff --check`: passed.
- [x] Verify production boot and asset precompilation, writing compiled output outside the repository. Passed; optional image-processing and third-party source-map warnings remain.
- [x] Self-review using Rails code review guidance; ensure unrelated user changes are untouched. Independent read-only review also found no actionable Critical, Important, or Minor findings.
- [x] Report the exact Rails version, verification results, and remaining browser-suite limitation. The user subsequently authorized a local commit on this branch; no push or pull request is requested.
