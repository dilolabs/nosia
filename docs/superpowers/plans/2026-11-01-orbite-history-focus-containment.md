# Orbite History Focus Containment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the actual focused History rail opener fully inside its own scrollport after the shared navigation dialog closes.

**Architecture:** Preserve native dialog focus restoration and the existing single focus owner. After navigation reflects a genuinely closed panel, reveal only an already-focused History rail trigger by the minimum vertical rail-scroll delta calculated from client bounds. Do not change History layout, generic dialog handling, toolbar previews, reader scrolling or target sizes.

**Tech Stack:** Existing Rails8.0.5.1/Ruby4.0.7/PostgreSQL application, Stimulus/importmap, Minitest/fixtures and installed local Chromium/WebDriver.

---

## Authority and restart provenance

The user explicitly selected **“Autoriser (Recommended)”** on2026-11-01 for a
targeted JavaScript correction making the History button entirely visible upon
focus return, without a design change, target shrink or weaker test. This is the
only exception to the JavaScript freeze in the earlier
[History density plan](2026-10-31-orbite-history-density.md). Execution mode remains
fresh implementer followed by independent SPEC → QUALITY; do not ask again.

The previous server restart removed `/tmp/opencode/chat-workspace-recovery-Pbwj0x`,
the original helper, raw logs, traces, images and historical manifests. Those
artifacts are **unavailable**, not restored. Do not rerun a completed diagnostic
to manufacture replacement evidence. The following findings have conversation
provenance only:

- Full native selection failed245/94,616/4F/0E/0S, seed31719.
- Bounded diagnostic EoQ0i3 reached the unchanged original oracle:
  1/1,184/1F/0E/0S;36events/11,154bytes/0drops.
- Actual click preparation partially revealed the rail opener before pointer
  focus/modal opening; scroll44 persisted through Escape focus return.
- Rail client bottom353 versus opener bottom366 left13px clipped. Focus returned
  before document close capture, so generic dialog `closed` was not the first
  restoration that produced this position. Internal browser/driver scrolling
  choices and historical baseline browser behavior remain unproven.

Fresh static restart checkpoint:
`/tmp/opencode/orbite-restart-20261101-e0fbccov/checkpoint.json`. It snapshots19
current files. HEAD is `f73333b2b708e4010d7878a09697c2e8c6c6e663`; index empty.
The native test still hashes to
`da61ccd5b230ba08a0090cfe839a5dcd67899c8f0b85950aa4ad4bd6d052aac7`.
The lost1096-file map and original density before/after comparison cannot be
reverified from this new checkpoint; label historical evidence accordingly.

## Ownership

| Path | Allowed change |
| --- | --- |
| `app/javascript/controllers/workspace_navigation_controller.js` | Closed-panel, already-focused History rail opener containment only |
| `test/system/orbite_history_density_test.rb` | Add regression and small geometry sampler; retain every existing oracle and six permanent characterization units |
| This plan | Parent-owned authority record, committed separately before execution |

During implementation the other seven existing density paths remain exact
restart-snapshot bytes. The five D drafts (`docs/README.md`, `docs/chat-workspace.md`,
`docs/chat-composer.md`, `docs/compact-headers.md`, `docs/orbite-workspace.md`) remain
unchanged and unstaged. All other JavaScript, generic dialog/helper/fixtures/backend,
reader80px/paused1px/Latest/own-success behavior, native formatting/PDF/Sources/Tools,
Stop/Retry/accounting/privacy, both themes/locales and reduced-motion support stay
unchanged. No new focus owner, forced test scroll/focus, CSS workaround or smaller
target is authorized.

The eventual coherent implementation commit contains the original eight density
paths plus this one navigation controller: **exactly nine paths**. No documentation
draft enters that commit. User approval here does not authorize integration.

## Task1: Recover a transparent execution envelope

- [ ] Snapshot current source before edits into a NEW unique evidence directory;
  build a NEW full input map from current tracked app/test/config/lib/db/vendor/bin,
  Gemfile/lock, Ruby/RuboCop configuration and docs, explicitly including the new
  native test and D guide. Reject dotenv paths, symlinks, unexpected untracked files
  or unrelated staged changes. Bind parent plan HEAD and the19-file restart receipt.
- [ ] Reconstruct the helper from the exact committed recipe in
  `2026-10-28-chat-workspace-ui-ux.md:91–114`, with an explicit new-provenance comment.
  Use a new evidence pointer/base SHA; never recreate old path names as if original.
  The new recorder must preserve real raw logs and adjacent true exits.
- [ ] Read actual new test, all six native files, requests and inherited fixture,
  model/callback, queue, Cable, browser and database adapters before application
  boot. Record NEW safety/source bindings; old lost238/1096 maps are not proof.
- [ ] Confirm installed Ruby/bundle/Chromium/driver and configured/connected isolated
  database `nosia_chat_workspace_ui_test`, without DB preparation, migration,
  reset/create/install, workers or unknown-process inspection/control. Missing
  prerequisite means BLOCKED, not permission to install or alter the environment.

The nondisplaying dotenv process may consume the main `.env` only via the reviewed
helper, with fixed test overrides after dotenv. Do not read/source/copy/display its
contents or dump environment variables. No provider/MCP/crawl/index/embedding/job
performance or unrestricted suite. Original file fixtures and test job adapter
must prevent live work. A helper is not a network sandbox.

Every runtime command runs sequentially, foreground, timeout0, through the new
recording helper. Record actual cwd, HEAD, frozen working bytes, invocation, raw
hash/true exit, seed/counts/F/E/S and artifact originals. Protect existing generated
screenshots from overwrite with an explicitly audited evidence-only save path;
do not alter driver/transport/focus behavior. No polling, sleeps or retry hunt.

## Task2: Add a NEW strict containment regression before production code

Add this test before `private` in the existing native test file. Existing setup,
fixtures, characterization, matrix and helpers remain unchanged. The new regression
is new work, not a rerun of the completed historical diagnostic.

```ruby
  test "rail opener return stays inside its client scrollport" do
    %w[en fr].product([ false, true ], %w[escape close]).each do |locale, dark, closure|
      orbite_viewport(812, 375)
      orbite_select_language(locale.upcase)
      density_open(812, dark)
      orbite_tab_to("#workspace-navigation-close")
      before = density_rail_return_geometry
      page.driver.browser.action.send_keys(closure == "escape" ? :escape : :enter).perform
      assert_no_selector "#chat-history[open]", visible: :all
      assert_selector "#workspace-history-rail-trigger:focus"
      sample = density_rail_return_geometry
      orbite_record("rail-return-#{locale}-#{dark}-#{closure}", sample, screenshot: true)
      assert_equal before.fetch("readerScroll"), sample.fetch("readerScroll"), sample.to_json
      assert_equal before.fetch("rootScroll"), sample.fetch("rootScroll"), sample.to_json
      assert_equal before.fetch("railLeft"), sample.fetch("railLeft"), sample.to_json
      %w[width height].each { |dimension| assert_operator sample.fetch("button").fetch(dimension), :>=, 44, sample.to_json }
      %w[top left].each { |edge| assert_operator sample.fetch("button").fetch(edge), :>=, sample.fetch("port").fetch(edge), sample.to_json }
      %w[bottom right].each { |edge| assert_operator sample.fetch("button").fetch(edge), :<=, sample.fetch("port").fetch(edge), sample.to_json }
      orbite_assert_reachable("#workspace-history-rail-trigger")
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-history:modal"
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end
```

Add this private sampler after `density_header`, outside all six permanent units:

```ruby
    def density_rail_return_geometry
      page.evaluate_script(<<~JS)
        (() => {
          const button = document.querySelector('#workspace-history-rail-trigger')
          const rail = button.closest('.n-orbite-rail'), box = rail.getBoundingClientRect()
          const reader = document.querySelector('[data-application-scroll]'), root = document.scrollingElement
          return { button: button.getBoundingClientRect().toJSON(), railTop: rail.scrollTop, railLeft: rail.scrollLeft,
            port: { top: box.top + rail.clientTop, left: box.left + rail.clientLeft,
              bottom: box.top + rail.clientTop + rail.clientHeight, right: box.left + rail.clientLeft + rail.clientWidth },
            readerScroll: [reader.scrollLeft, reader.scrollTop], rootScroll: [root.scrollLeft, root.scrollTop] }
        })()
      JS
    end
```

- [ ] Audit actual inserted test before boot. Preserve source snapshot and native
  test diff; verify six units against NEW restart snapshot, not missing old proof.
- [ ] Build current assets if needed for the fresh environment; then run the NEW
  regression only, using the new reviewed helper/recorder:

```bash
nav_record rail-return-red browser_test test/system/orbite_history_density_test.rb -n /rail_opener_return_stays_inside_its_client_scrollport/
```

Expected: meaningful containment assertion failure, actual exit1, zero errors/skips.
Inspect the full original log/sample/PNG. A wrong failure, initial pass, missing
database/tool or unexpected error returns BLOCKED; do not silently retry or weaken
reader/rail bounds, hit points, target size or native input.

## Task3: Implement only minimum navigation-owned rail reveal

Only after meaningful NEW RED, append `this.revealFocusedRailTrigger()` after
`this.reflect()` in `closed()`. Keep its existing caching/open guards unchanged.
Add the following method immediately after `closed()`:

```javascript
  revealFocusedRailTrigger() {
    const trigger = this.triggerTargets.find(element => element === document.activeElement)
    const rail = trigger?.closest(".n-orbite-rail")
    if (!rail) return

    const button = trigger.getBoundingClientRect(), box = rail.getBoundingClientRect()
    const top = box.top + rail.clientTop, bottom = top + rail.clientHeight
    if (button.top < top) rail.scrollTop += button.top - top
    else if (button.bottom > bottom) rail.scrollTop += button.bottom - bottom
  }
```

This never calls focus or touches a non-rail/mobile trigger, reader, root or
horizontal scroll. It measures actual borders/scrollbar-reduced client height,
uses no13px/44px hardcoded offset, no timer/RAF and no smooth animation. It does
not act during cache preparation, while the panel is open, or if some other
element has focus. Do not add generic scroll/focus infrastructure.

- [ ] Run the unchanged NEW regression to GREEN. Capture full original geometry
  and native hit/focus evidence for Escape and Close/Enter, EN/FR/both themes.
- [ ] If it fails, stop and explain the actual mismatch. No second production
  approach, rail redesign, helper adjustment or generic dialog rewrite is
  conditionally authorized.

## Task4: Fresh final-source validation and exact nine-path commit

Freeze current complete working inputs after build and before these final gates.
The original density baseline artifacts are lost: run current characterization
as present-state regression only; do not produce a replacement before/after claim.

```bash
nav_record rail-return-build rails_test tailwindcss:build
nav_record rail-return-requests rails_test test test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb
nav_record rail-return-native browser_test test/system/orbite_history_density_test.rb test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb test/system/chat_workspace_test.rb test/system/compact_headers_test.rb test/system/chat_refresh_draft_test.rb
nav_record rail-return-localization browser_test test/system/localization_test.rb
nav_record rail-return-lint test_command bundle exec rubocop test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/system/orbite_workspace_test.rb test/system/orbite_history_density_test.rb
```

Run installed Node syntax checking on the controller as an ES module via stdin,
without adding Node/build dependencies or package files:

```bash
node --input-type=module --check < app/javascript/controllers/workspace_navigation_controller.js
git diff --check
```

Stop after any unexpected nonzero/F/E/S. Known duplicate-`last_test_at` warnings
remain unsuppressed historical backend debt, not hidden or corrected here. All
existing80px/1px/Latest/source/native-draft/account-isolation oracles run unchanged.
No fresh full-feature/security-clean claim is authorized by these bounded gates.

- [ ] Read actual whole gate logs, seeds, counts, geometry and native hit evidence.
  Open full-size original corrected landscape, EN/FR themes, focus/Close, mobile
  and desktop samples. Log exactly which originals were opened; inventories alone
  are not visual inspection. Native zoom, SR, physical devices and native tooltip
  UI remain NOT RUN.
- [ ] Verify complete tested freeze still exact, all nonowned inputs and five D
  drafts match the NEW restart checkpoint. Preserve six permanent units. Compare
  other seven density paths to their NEW19-file snapshots; do not relabel these
  as checks against the missing old1096-input map.
- [ ] Self-review complete nine-path diff, then conditionally commit ONLY when all
  prescribed gates and preservation checks pass. Stage nine explicit paths:

```bash
git add -- app/views/chats/_history_items.html.erb app/views/application/_orbite_shell.html.erb app/assets/stylesheets/nosia/orbite_chat.css app/assets/stylesheets/nosia/orbite_shell.css test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/system/orbite_workspace_test.rb test/system/orbite_history_density_test.rb app/javascript/controllers/workspace_navigation_controller.js
git diff --cached --check
git commit -m "feat(ui): Compact Orbite History and reveal its focused rail opener"
```

Before commit, prove exact nine-path staged blobs/modes equal frozen tested bytes;
afterward verify parent HEAD, exact committed blobs/modes, empty index and only
five D drafts dirty. Capture actual working-source SHA/patch, never claim execution
against a future commit. No automatic push/merge/PR/docs-draft commit or cleanup.

## Task5: Parent inspection and independent reviews

- [ ] Parent inspects real diff/current hashes/raw exits/native geometry/original
  PNGs and honest lost-evidence limitations.
- [ ] Fresh independent SPEC; only after approval, different fresh QUALITY.
- [ ] Separate TaskD documentation/final-source security/whole-feature review
  follows; this plan does not invent missing security-baseline artifacts or
  authorize rerunning completed work just to recreate them.

**Parent self-review:** The added production path is exactly the user-authorized
navigation controller. The test proves full client-scrollport containment and
no reader/root/horizontal movement, preserving the original five-point oracle.
The reveal method retains existing native focus ownership and cache/open guards.
No layout, generic modal, source/account/reader behavior or density unit changes
are authorized. Historical diagnostics are not repeated or promoted to fresh
evidence. This document plans future execution; it does not claim runtime results.
