# Orbite Chat Header Without Home or History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Home and History controls from new and saved chat headers while preserving New chat, conversation context and mobile navigation.

**Architecture:** Keep the header container and render its toolbar/Usage only for saved chats. Reuse the existing composer navigation control on mobile, rail control on larger screens, and existing global mobile navigation entry only when no chat composer exists. Change no production JavaScript/CSS or reader algorithms; migrate only tests coupled to removed controls.

**Tech Stack:** Existing Rails/ERB, Turbo/Stimulus, Minitest/fixtures and audited isolated local browser/test helper.

---

## User amendment / preserved state

User explicitly requested removing **“History” (`n-workspace-button`) and “Home”
(`n-workspace-link`) from `app/views/chats/_header.html.erb` on new and existing
chats**, attaching the current partial. Keep saved-chat New chat, heading/account,
Usage section and live token totals. Global Home/navigation and backend routes
are outside the removal request. This direct revision overrides previous header
Home/History preservation; it is not a new speculative design or execution choice.

Previous amendment worker paused cleanly: no command, staging or code commit.
Available pause receipt:
`/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/history-inset-20261102-4b2f98/pause-index.json`.
Parent checked all1098 paused source hashes. Pre-amendment focused1/938,
requests24/404, native246/83,532, localization8/643, lint6 and Node passed; those
results do not establish the new header contract. Delete removal, full-width
History rows, native focus inset and rail reveal remain frozen. DDL/setup and
completed historical diagnostics must not run again.

## Exact production changes

### `app/views/chats/_header.html.erb`

Replace its content with:

```erb
<header class="n-chat-header">
  <% if chat.persisted? %>
    <div class="n-chat-toolbar">
      <div class="n-chat-heading min-w-0">
        <h1 class="n-chat-title"><%= chat_workspace_title(chat, titles: titles) %></h1>
        <p class="n-workspace-help n-chat-account-preview" data-chat-account-label><%= chat.account.name %></p>
      </div>
      <div class="n-workspace-actions">
        <%= link_to t("nosia.chat_workspace.new_chat"), new_chat_path, class: "n-workspace-button" %>
      </div>
    </div>
    <section id="chat-usage-details" class="n-chat-usage" aria-labelledby="chat-usage-summary">
      <h2 id="chat-usage-summary" class="n-chat-usage-title"><%= t("nosia.chat_workspace.usage_details") %></h2>
      <p class="n-workspace-help"><%= chat.account.name %></p>
      <%= render "chats/token_totals", chat: chat %>
    </section>
  <% end %>
</header>
```

The existing outer reading-context container remains, but new chats have no
empty toolbar/actions or header controls. Saved heading/Usage/token contents and
their identities remain unchanged. Do not add a replacement header menu/button.

### `app/views/application/_orbite_shell.html.erb`

Change only the existing mobile-trigger guard:

```erb
<% unless chat_workspace_page? && @chat.account %>
```

This replaces `unless chat_workspace_page?`; the existing `#workspace-mobile-trigger`
button, attributes/localized name/44px styles remain unchanged. Short-circuiting
protects non-chat pages without `@chat`. Normal new/saved chats use their existing
composer mobile control; no-account chats without a composer use the existing
global entry outside the chat header. No duplicate mobile entry for accounted
chats, no new focus owner or JS/CSS change.

## Test ownership and migrations

The following directly coupled paths are allowed; unrelated assertions remain:

- `test/support/orbite_browser_checks.rb`: add selector-only helper below and
  remove the obsolete header-selector fallbacks from `orbite_open_utilities`.
  Keep Tab/ShiftTab/hit/contrast/focus implementations and tolerances unchanged.
- Requests: `test/integration/orbite_shell_test.rb`,
  `test/integration/compact_headers_test.rb`,
  `test/controllers/chat_workspace_test.rb`,
  `test/controllers/dashboards_controller_test.rb`,
  `test/controllers/token_usage_workspace_shell_test.rb`,
  `test/controllers/settings_workspace_test.rb`,
  `test/controllers/sources_workspace_shell_test.rb`.
- Native: `test/system/orbite_workspace_test.rb`,
  `test/system/orbite_history_density_test.rb`,
  `test/system/compact_headers_test.rb`, `test/system/chat_workspace_test.rb`.

```ruby
    def orbite_navigation_trigger
      if page.evaluate_script("innerWidth >= 768")
        "#workspace-history-rail-trigger"
      elsif page.has_selector?("[data-orbite-composer-navigation]", wait: 0)
        "[data-orbite-composer-navigation]"
      else
        "#workspace-mobile-trigger"
      end
    end
```

Use the helper to locate the actual opener; ordinary native pointer/keyboard
activation, focus return, aria-expanded, real target replacement, draft/root
identity, reflow, protocol and80px/1px/Latest assertions remain. For adversarial
tests that already deliberately dispatch a synthetic click, change only its
selector/actual target, not the existing stimulus/timing or scenario.

Replace removed header Home focus anchors with the surviving saved-chat New chat
link **without activating it**; retain genuine traversal direction and full Usage
recovery. Replace removed header History geometry with actual saved heading/title
geometry when the assertion is about context scrolling away. Do not drop those
context or anchoring assertions or substitute a different reader owner.

The density `density_open` unit necessarily changes only its opener selector;
declare that authorized unit delta rather than falsely claiming all six units
unchanged. Its five other permanent units, fixture IDs/data/semantic order and
sampler remain byte-identical. The rail containment regression/sampler, no-Delete
row contracts, text/date/44px/contrast/hit/strict containment and navigation JS/CSS
stay frozen. Update full-value recovery's Home focus selector to New chat.

## Task1: NEW header absence RED before production

- [ ] New checkpoint bridges the1098 paused map plus this one parent plan commit,
  snapshots all scoped files and D drafts, binds current actual HEAD and original
  receipts. Reuse unchanged audited helper/installed/runtime source bindings.
  Read/audit newly selected request files before boot; no live jobs/providers.
- [ ] Add EN/FR request cases for both new and saved chats:

```ruby
    test "chat headers omit Home and History controls in #{locale}" do
      [new_chat_path(account_id: @second.id), chat_path(@chat)].each do |path|
        get path, headers: { "Accept-Language" => locale.to_s }
        assert_response :success
        assert_select ".n-chat-header #workspace-history-trigger, .n-chat-header [aria-controls=chat-history]", count: 0
        assert_select ".n-chat-header a[href='#{user_root_path}']", count: 0
        assert_select "#workspace-history-rail-trigger", count: 1
        assert_select "[data-orbite-composer-navigation]", count: 1
        assert_select "#workspace-mobile-trigger", count: 0
      end
    end
```

```bash
nav_record header-controls-red rails_test test test/integration/orbite_shell_test.rb -n /chat_headers_omit_Home_and_History_controls/
```

Require meaningful absent-control failures, exit1/zero errors/skips before edits.
Add no-account request coverage: no composer/header controls, one global mobile
trigger and existing setup/empty guidance. Saved requests retain title/account/
Usage/tokens/New chat; new requests retain main question heading and no actions.

## Task2: Minimal markup and bounded selector migrations

- [ ] Apply only the two production changes above. Add the selector helper and
  migrate direct callers found by `workspace-history-trigger`, `click_button
  "History"`, toolbar Home focus and header geometry searches. Do not blindly
  replace removed-target geometry with a fixed/visible rail where offscreen
  context is the assertion's point.
- [ ] Add native mobile coverage for normal new/saved composer navigation and
  no-account global fallback: true open/close/Escape/focus return,44px targets,
  locale/theme, preserved native draft/source/job guarantees. Keep rail and
  composer markup unchanged, only the existing shell fallback guard changes.
- [ ] Audit actual new source. Run new request filter GREEN, then focused native
  opener/replacement/refresh/reflow/full-value cases before final groups. Unexpected
  F/E/S stops; no JS/CSS/physics/helper-tolerance workaround is authorized.

## Task3: Final-source verification and review

Freeze current source/runtime/installed/generated bytes after build before final
gates; use unchanged reviewed helper/preamble/recorder/cwd, foreground timeout0,
sequential execution. No DDL/setup/prerequisite/old diagnostic replay, dotenv
disclosure, process control, provider/worker, installs, unrestricted suite or cleanup.

```bash
nav_record header-controls-build rails_test tailwindcss:build
nav_record header-controls-requests rails_test test test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/controllers/dashboards_controller_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/sources_workspace_shell_test.rb
nav_record header-controls-native browser_test test/system/orbite_history_density_test.rb test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb test/system/chat_workspace_test.rb test/system/compact_headers_test.rb test/system/chat_refresh_draft_test.rb
nav_record header-controls-localization browser_test test/system/localization_test.rb
nav_record header-controls-lint test_command bundle exec rubocop test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/controllers/dashboards_controller_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/sources_workspace_shell_test.rb test/system/orbite_workspace_test.rb test/system/orbite_history_density_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/support/orbite_browser_checks.rb
git diff --check
```

- [ ] Preserve existing JS Node success if actual JS bytes remain unchanged; do not
  mislabel it as executed at a future commit. Read full actual new raw logs/exits/
  counts/seeds/native geometry. Open current new/saved headers and mobile normal/
  no-account navigation/draft/recovery/focus originals across locales/themes.
- [ ] All nonowned source/five D drafts unchanged; approved rail JS and all CSS
  remain byte-identical. Only declared selector/opener/removed-target migrations
  may change protected tests. No weak tolerance/physics/streaming/privacy changes.
- [ ] Conditional combined code commit only allGREEN/self-review/tested staged
  blobs+modes proof. Scope is old11 plus header, shared browser helper and five new
  request files: **exact18 code/test paths**. No docs/D drafts included; index empty
  and only five D drafts dirty afterward. No integration/push/PR/cleanup.
- [ ] Parent actual diff/raw/PNG review, then fresh SPEC → different fresh QUALITY.
  D docs/current security/whole-feature review remain separate and pending.

**Parent self-review:** Header-only controls are removed exactly as requested;
New chat/heading/Usage/tokens preserved. Existing mobile composer navigation covers
normal chats, and existing global navigation is reused for no-account fallback.
Production remains ERB-only for this amendment. Test selector migrations keep the
meaning of old native focus/reader scenarios rather than weakening them.
