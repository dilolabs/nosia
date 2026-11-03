# Orbite Reader Cache Geometry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development or superpowers-ruby:executing-plans to implement this coherent correction task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the paused paragraph through real Turbo cache cleanup and refresh without weakening native reader or draft guarantees.

**Architecture:** Treat lifecycle capture against unacknowledged reader geometry like the already-guarded pending reconciliation. Reuse the existing surface/height/client-height/client-width ledger comparison; actual input still captures through the unchanged no-event path. Do not change cache closing, History layout, focus, animations or reconciliation.

**Tech Stack:** Existing checkout: Rails 8.0.5.1, Ruby 4.0.7, Stimulus/Turbo, ERB, native Tailwind, Minitest/fixtures, Selenium/Chromium. No dependency or environment changes.

---

## Authority, measured cause and supersession

The user selected **“Autoriser (Recommended)”** after explicitly being asked to
expand the frozen JavaScript scope for a targeted reader correction, preserving
strict assertions, drafts and independent reviews. No new design/execution-mode
decision is required. Same coherent implementer, then independent SPEC and a
different QUALITY reviewer remain selected.

This amends only the reader-JS freeze, one test-file additive boundary and final
candidate/parent bookkeeping of the
[premium header plan](2026-11-02-orbite-compact-premium-chat-header.md).
Its approved compact B presentation and accounting contracts do not change.
The previous exact25 code candidates become **26**, adding only
`app/javascript/controllers/scroll_controller.js`. The new native regression is
inside an existing candidate. This corrective plan is committed separately, not
inside the code commit. The eventual code commit's parent is this plan-only
commit, not the superseded `a23a235` parent requirement. No code is staged now.

Actual causal evidence:
`/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/premium-reader-cache-causal-20261102-LYhsxxiJ/`.
Parent read its full report, original raw, timeline and cache/native-close pairs.
The single invocation (seed46448) failed the unchanged paragraph oracle with
1run/57assertions/1failure/0errors/0skips, exit1. Trace SHA256
`33fae4ef906dc8ae166e544e5dc45cb746ddbf78d3732b13c536f8b8a8f4467f`:
61 main records and three complete pairs, zero drops/errors.

Native-close pair3/n7→n8 directly brackets the original
`chat-dialog#beforeCache` → `chat-history.close()` at line110. It closes the
nonmodal inline panel, changes the grid from three columns to two, widens the
reader1044→1292px and changes header339→319.5px while scrollTop stays1351.
Before-render capture n12→n13 then replaces stored P19 with P20 against the
unacknowledged geometry; reconciliation restores P20. Reader identities and
accounting stay equal, and no sampled animation or recordInput call intervenes.
This does not justify changing the dialog/cache policy or assigning unrelated
editor cleanup to an unmeasured operation.

Original failed diagnostics/export error and original reader9/351/1F remain
immutable history. Previous requests46/1214 and bar1/1189 pass at their actual
source, not this future correction. Do not rerun historical work for receipts.

## Exact scope and safety

New application permission is **only** the reader controller delta in Task2.
New test permission is **only** the complete additive block in Task1, inserted
before the existing `paused paragraph survives compact header height changes
and viewport reflow` test. That existing test and every helper/oracle stay exact.
All existing premium production/test bodies, History/rail correction, five D
drafts, dependencies, backend, other JS/CSS, shared helpers and fixtures remain
the current post-reader bytes/modes. No other refactor or assertion migration.

The canonical starting source/runtime map is
`premium-phase2-resume-20261102-txUb7dVe/freeze-after-reader.json`, SHA256
`5040e879b26c74b6fee796f2d6565d44771a031623f745fd414ce708ad791338`,
under the same evidence root. Its1103 inputs remain exact before this plan is
added. Bridge the new plan-only commit explicitly to a fresh1104-input checkpoint;
do not patch old hardcoded-HEAD utilities or rerun their mains. Runtime11505 uses
the actual owned-build CSS199200bytes/SHA256
`987e72d3a3158f64bb048337285bdfd2a99fbeb4b4c7b6705cfb3298cb89e067`,
with11504 strict non-generated entries. Earlier writer/time remain unknown.

Every shell uses exact repository cwd and this reviewed preamble:

```bash
source /tmp/opencode/chat-workspace-env.sh || exit $?
export E=/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq
export EVIDENCE="$E"
export ORBITE_SOURCE_SHA="$(git rev-parse HEAD)"
source "$E/recorder.sh" || exit $?
```

Then set EVIDENCE to a new exclusive child; use sequential foreground timeout0
and actual exit-preserving nav_record commands. No dotenv disclosure, development
process inspection/control, install, DB setup/prepare/DDL/migrate/reset, provider/
MCP/crawl/embedding, performed jobs/drain/workers, unsafe unrestricted suite or
localized_broadcasts selection. No merge/push/PR/cleanup. Source snapshots and
all old receipts stay unchanged. Stop on unexpected failure/error/skip or drift.

## Task 1 — Add a permanent real-cache regression and observe RED

**Modify:** `test/system/chat_workspace_test.rb` (additive block only).

- [ ] Bind current source/runtime, source-bound caller audit, plan-only ancestry,
  protected14 methods/six density units/rail test, five drafts and26 candidate
  paths. Create external before snapshots of the two corrective paths; verify
  index empty. No app gate until this bridge and actual new-test source audit.
- [ ] Insert exactly this block immediately before the existing paused compact
  header/refresh test. Measurements are passive; the scenario uses the real GET
  and unchanged helpers. It does not dispatch a synthetic lifecycle event, hold
  a frame, override a method, write a private ledger, or disable an animation.

```ruby
  test "cache cleanup preserves a paused paragraph through refresh geometry" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    visit_reader(1400, 1000)
    assert_selector "#chat-history[data-inline=true][open]"
    pause_reader
    anchor = reader_anchor
    page.execute_script(<<~JS)
      window.readerCacheGeometry = {}
      const sample = () => {
        const root = document.querySelector('.n-chat-workspace--saved')
        const surface = document.querySelector('[data-application-scroll]')
        const panel = document.getElementById('chat-history')
        const anchor = root.chatReaderState.anchor
        return { width: surface.clientWidth, height: surface.clientHeight, top: surface.scrollTop,
          headerHeight: root.querySelector('.n-chat-header').getBoundingClientRect().height,
          panelOpen: panel.open, inline: panel.dataset.inline,
          anchor: anchor && { id: anchor.id, block: anchor.block, offset: anchor.offset } }
      }
      document.addEventListener('turbo:before-cache', () => {
        window.readerCacheGeometry.beforeCache = sample()
      }, { once: true, capture: true })
      document.addEventListener('turbo:before-render', () => {
        window.readerCacheGeometry.beforeRender = sample()
      }, { once: true, capture: true })
    JS

    refresh_workspace
    evidence = page.evaluate_script("window.readerCacheGeometry")
    chat_measurement("kind" => "reader-cache-cleanup-geometry", "measurement" => evidence)
    before = evidence.fetch("beforeCache")
    rendering = evidence.fetch("beforeRender")
    assert before.fetch("panelOpen"), evidence.to_json
    assert_equal "true", before.fetch("inline")
    refute rendering.fetch("panelOpen"), evidence.to_json
    assert_equal "true", rendering.fetch("inline")
    assert_operator rendering.fetch("width"), :>, before.fetch("width"), evidence.to_json
    assert_equal before.fetch("top"), rendering.fetch("top"), evidence.to_json
    assert_equal before.fetch("anchor"), rendering.fetch("anchor"), evidence.to_json
    assert_reader_following false
    assert_reader_anchor anchor
    assert_selector "#chat-history[data-inline=true][open]"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

```

- [ ] Parse the actual added Ruby/embedded JS and audit its local fixture/login/
  GET/refresh/passive measurement callers. Freeze exact test addition and all
  immutable sources/runtime before boot. Existing controller must still be exact.
- [ ] Run only the new native regression before JS changes. Require one meaningful
  paused paragraph/offset failure, zero errors/skips, exit1; preserve actual raw,
  seed, native original and the real cache geometry witness. Unexpected PASS or
  unrelated failure stops rather than altering the scenario to manufacture RED.

```bash
if nav_record reader-cache-regression-red browser_test test/system/chat_workspace_test.rb -i /cache_cleanup_preserves/ --seed 46448; then
  exit 125
else
  result=$?
  test "$result" -eq 1 || exit "$result"
fi
```

The existing original protected failure is already observed repeatedly; do not
rerun it before the fix solely to recreate RED evidence.

## Task 2 — Reuse the existing geometry ledger, then GREEN

**Modify:** `app/javascript/controllers/scroll_controller.js` only.

- [ ] After meaningful Task1 RED, insert this getter immediately before scrolled:

```javascript
  get geometryChanged() {
    const surface = this.surface
    return this.position?.surface !== surface || this.position.height !== surface.scrollHeight ||
      this.position.clientHeight !== surface.clientHeight || this.position.clientWidth !== surface.clientWidth
  }

```

- [ ] In scrolled replace only the existing multi-line geometry condition with
  `if (this.geometryChanged) {`. The condition moved to the getter is byte-for-
  byte equivalent in operands and short-circuit behavior; retain all other code.
- [ ] Replace only capture's first guard with:

```javascript
    if (!this.state.paused || (event && (this.frame || this.geometryChanged))) return
```

The no-event capture used by recordInput is deliberately unchanged: genuine
reader movement still wins even if resize acknowledgment is pending. Do not
change rememberPosition, capture's anchor selection, restoreAnchor, reconciliation,
Latest, native key/focus handling, submission logic, cache behavior or draft code.

- [ ] Audit exact two-path deltas/current full source; parse actual JS with native
  node --check. Do not alter Ruby formatting or any unchanged original test.
- [ ] Run one normal source-bound build for this new correction state, freeze its
  actual output before tests, and retain all11504 other runtime bindings strictly.
  This is not a replay of the old CSS diagnostics or a wildcard runtime exception.

```bash
nav_record reader-cache-js-syntax test_command node --check app/javascript/controllers/scroll_controller.js || exit $?
nav_record reader-cache-build rails_test tailwindcss:build || exit $?
nav_record reader-cache-regression-green browser_test test/system/chat_workspace_test.rb -i '/cache_cleanup_preserves|paused_paragraph_survives_compact_header/' --seed 46448 || exit $?
nav_record reader-cache-focused-green browser_test test/system/compact_headers_test.rb test/system/chat_workspace_test.rb -i '/cache_cleanup_preserves|native_reader_.*_navigation_crosses|resize_alone_preserves|visible_Usage_growth|paused_paragraph_survives_compact_header|visible_Usage_and_native_History/' || exit $?
```

Require two runs in the first GREEN group and ten in the focused group, actual
nonzero assertions,0F/0E/0S/TRUE.exit0. Read complete raws before advancing; freeze
and compare current sources/runtime after each group. On unexpected F/E/S/drift,
stop without a corrective loop or weaker assertions. A diagnostic PASS is never
a substitute for these uninstrumented native assertions.

- [ ] Self-review and return actual test counts/seeds/raws/originals and exact
  source/runtime preservation. Do not stage/commit or run final groups yet.

## Task 3 — Fresh final groups, coherent26-path commit and independent review

Parent must first inspect actual corrective diff, RED/GREEN raws, original images
and preservation proof. No old request/bar/diagnostic run is repeated merely for
lost receipts. The previously approved complete final groups remain necessary at
the corrected frozen source:14 request files, seven native files (new regression
is inside the existing chat file), exactly test/system/localization_test.rb and
lint16. Add scroll_controller.js node syntax; all other JS remains frozen.

- [ ] On separate parent dispatch, create a fresh final current source/runtime
  freeze, with tested26 candidate blobs/modes and the actual plan-only parent.
- [ ] Execute the exact complete final selections in the premium plan sequentially,
  without the withdrawn job-performing localized_broadcasts file or any filter
  from it. Read each actual raw and require0F/0E/0S/exits0 before the next.
- [ ] Compare the retained phase1 real-before16 contexts to the single candidate
  characterization produced by the final seven-file native group. Preserve
  fixture/account/counts/kinds, reader/dock bounds within1px; require smaller
  ordinary-fixture header height. Do not rerun before or create a synthetic gain.
- [ ] Inspect actual originals, long account/large/zero/one-sided/live variants,
  native input/drafts/80px/±1px/Latest/own-success rules and History/rail regressions.
- [ ] Only allGREEN plus parent inspection permit stage/commit. Use the original
  exact25 list plus scroll_controller.js, count26, no docs/generated CSS. Prove
  every staged blob/Git mode equals the tested freeze, then commit the coherent
  code task. Verify actual parent equals this plan-only commit and only the five
  unchanged D drafts remain dirty; do not infer future-SHA test execution.
- [ ] Parent inspects full actual commit/raws/originals, then a fresh SPEC reviewer
  and different fresh QUALITY reviewer. Correct findings through bounded gates;
  no automatic merge/push/PR/cleanup. Documentation reconciliation, missing
  security-baseline provenance and final whole-feature review remain pending.

## Parent self-review

- User-authorized narrow scope: one reader getter/guard, reused scrolled condition;
  no dialog/navigation/cache-policy rewrite or draft/focus owner.
- Measured cause: original native cache close changes geometry before lifecycle
  capture; no hidden UI/content/timing/tolerance workaround.
- TDD: new permanent real-GET regression RED, original failing test unchanged,
  minimal JS only after RED, strict uninstrumented GREEN groups.
- Genuine native input remains no-event capture; full final files retain the
  pending-resize, Latest, own-success, focus and streaming coverage.
- Exact bounds: two corrective code paths,26 combined candidates, one new plan
  document, all five D drafts and protected units/helpers preserved.
- Fresh source/owned build freezes, honest historical evidence, parent inspection,
  independent SPEC→different QUALITY and no security-clean/integration claim.

This is a written corrective plan only. The plan author did not apply its new
test or reader code, run its RED/build/GREEN/final groups or stage pending code.
