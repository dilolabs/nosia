# Token Usage Workspace UI/UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved overview-first Token usage workspace on both existing report routes without changing reporting definitions, permissions, stored usage, or the dashboard.

**Architecture:** Keep the controller, `TokenUsage::Report`, account estimators and legacy dashboard overview intact. Build report-only, explicit-local partials around the shared workspace header; normalize date keys only for presentation, use the existing numeric SVG helper, and cache scoped lifetime sections independently of recent activity. Use native disclosures and narrowly scoped CSS, not new JavaScript, services, endpoints or dependencies.

**Tech Stack:** Actual checkout: Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL, Minitest/fixtures, Turbo/Stimulus, Importmap, Propshaft and Tailwind 4.1. Generic repository instructions describe a different stack; do not change this checkout's runtime or dependencies to match them.

---

## Authority, scope and execution boundary

- Approved [Token usage specification](../specs/2026-10-25-token-usage-workspace-ui-ux-design.md), initially committed as `100bd1c`; user answered **“Go”** to written-spec review. The [shared foundation](../specs/2026-10-24-workspace-tools-ui-ux-design.md) still applies.
- This plan is only Token usage. Agent skills and MCP each need their own detailed design/specification/plan cycle. No new routes, schema, reporting calculations, account/date selectors, billing, quotas, exports, forecasts, tracking writes or provider calls.
- Preserve the exact global calendar window and thirty zero-filled dates, account lifetime headlines and its lower-bound-only recent query, all account query buckets (including future buckets), membership checks, counter/ledger distinctions and estimation policies.
- Source branch `feat/sources-workspace-ui` remains `4be5ab1f0f7399b6f7766115fb709ee5929664cb`; `main` remains `c08cbfe22260059dd76a085a1c0aec1dfaeee17d`. No merge into `main`, push, PR or worktree removal is authorized here.
- Writing the original plan did not execute it. No application edits, dependency setup, database preparation or application tests were performed during planning. Static snippet checks were not application-test evidence; subsequent execution is recorded below.
- **Execution gate satisfied:** after plan commit `d5f3961`, the user selected **1 — Subagent-Driven** on 2026-10-25. After the fresh Task 0 baseline and reviews, the user answered **“Yes”** to only the exact reproduced issues below. The previous Sources choice/acceptance was not reused as authorization.

## Execution record — 2026-10-25

**Outcome: execution complete with concerns, not a clean full suite or security
scan.** Tasks 0–7 were completed using the user-selected Subagent-Driven method.
Independent whole-feature specification and quality reviews approved both the
implementation and completed final evidence without findings. The parent read the
raw logs, baselines, command manifest and report and authorized this Phase B
documentation-only record. No application checks were rerun for this record.

### Decisions, revisions and safety

- The user approved the written specification with **“Go”**, then selected
  **1 — Subagent-Driven** after this plan was committed. Planning itself used
  inline self-review, not a fresh-agent planning review.
- Worktree: `/home/cbldev/gitd/dilolabs/nosia/.worktrees/token-usage-workspace-ui`;
  branch: `feat/token-usage-workspace-ui`.
- Immutable execution base: `d5f396108d1041c0ed5c6febf217f24bc3e85049`, validated
  from `/tmp/opencode/token-usage-workspace-base.log`.
- Final tested feature revision and Task 6 documentation HEAD:
  `b94e35dd540ad20854d14307078517956b5563b9`. Last application commit:
  `4db80a89c713fc3ffaf5305a20d596b06c5dee1c` (Task 5). This record references
  that preceding tested revision, not its own future commit SHA. Phase B changes
  only this plan; pre/post-commit byte-identity checks compare every other tracked
  path, including all application/test/configuration files, to the tested HEAD.
- Actual runtime: Ruby 4.0.7, Rails 8.0.5.1/PostgreSQL, Tailwind 4.1.16 and local
  Chromium/ChromeDriver 156.0.8078.47. No packages were installed or upgraded.
- Every final-verification shell sourced the external helpers. Ruby/Bundler ran through
  `mise exec ruby@4.0.7`; Rails/browser launchers fixed `RAILS_ENV=test`, dedicated
  `nosia_token_usage_workspace_test`, sentinel `AI_API_KEY=nosia-test-key`, and
  `PARALLEL_WORKERS=1`. Database-sharing commands were sequential. Environment
  files were only loaded nondisplaying by dotenv, never inspected/copied/edited.
  No live provider, ingestion or queue worker was started.
- Task 0 quality review found a minor external-recorder reuse risk, not an invalid
  baseline: the original logger rewrote logs when adding trailers. Before Task 1,
  the external helper was hardened to exclusive creation, append-only trailers,
  refusal of existing files/symlinks, and recorder-failure exit 125 with the
  original command exit reported separately. Sentinel checks verified exits
  0/7, overwrite refusal 2 and recorder failure 125. Task 1 reviews approved it;
  all old logs remained intact. The original logger snippet below is historical,
  superseded by this reviewed helper, not the logger used for final execution.

### Fresh Task 0 baseline and limited user acceptance

Task 0 created/prepared only the isolated feature checkout and named test database,
verified the environment/database, and built ignored CSS. There was no tracked
source change or Task 0 source commit. The user answered **“Yes”** after the fresh
results and Task 0 reviews, before application implementation.

All log names in this record are under `/tmp/opencode/` unless another directory
is stated. `F/E/S` means failures/errors/skips; exits are true command exits.

| Fresh baseline | Tests/assertions | F/E/S | Seed | Exit | Log |
| --- | --- | --- | --- | --- | --- |
| Focused | 136 / 12,313 | 0/0/0 | 27318 | 0 | `token-usage-baseline-focused.log` |
| Full | 1,097 / 20,642 | 0/1/0 | 20411 | **1, not green** | `token-usage-baseline-full.log` |
| Browser | 117 / 7,247 | 0/0/0 | 52369 | 0 | `token-usage-baseline-browser.log` |
| Brakeman | Two high-confidence warnings; zero scan errors | n/a | n/a | **3, not green** | `token-usage-baseline-brakeman.log` |

Acceptance was limited to these unchanged existing issues:

1. Full-suite error
   `Chat::RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults`:
   `NoMethodError: undefined method 'augmented_context'`,
   `app/models/chat/completionable.rb:39` →
   `test/models/chat/request_options_test.rb:32` (test starts at line 29).
2. Brakeman `PermitAttributes` at `app/controllers/api_tokens_controller.rb:62`
   (`params.require(:api_token).permit(:account_id, :name)`) and `EOLRails` at
   `Gemfile.lock:318`, support ended **2026-10-07**. Both high confidence.
3. Seven JSON duplicate-key warnings in each focused/full run, for `tools_cache`
   and `last_test_at`, from Active Support JSON encoding/decoding.
4. Disclosed limited disk headroom: Task 0 ended with root 2.4G free/97% used.

This was not a waiver for new regressions, permission to fix baseline bugs,
suppress warnings/skip tests, alter reporting definitions, clean unrelated data,
change other branches, merge/push/create a PR, or implement Agent skills/MCP.
No accepted issue was fixed, skipped or suppressed by this feature.

### Task commits and RED/GREEN evidence

| Task | Commit(s) | Delivered responsibility |
| --- | --- | --- |
| 0 | No source commit; base `d5f396108d1041c0ed5c6febf217f24bc3e85049` | Isolated setup, fresh baseline, user acceptance |
| 1 | `3efb464d72cdfa0d7d70b7b41025bb833471f9a1` | Report shell, true scope and navigation |
| 2 | `b9e1c970e2ed6f6eaef08522afe23b135b0989a6`; test-only follow-up `04b2fbcc520802ec6fb0818aac1794ac5e249a8e` | Date-faithful activity and component contract coverage |
| 3 | `4de98ba78665511ebddec6208f67d68f1e8185c6` | Exact overview/rail, breakdowns and full methodology |
| 4 | `7dc2efcba4f9391a5856d8fe7db8c21e233255c0` | Scoped lifetime cache isolation and recent freshness |
| 5 | `4db80a89c713fc3ffaf5305a20d596b06c5dee1c` | Scoped responsive CSS and browser verification |
| 6 | `b94e35dd540ad20854d14307078517956b5563b9` | Guide/index/diagram only |
| 7 | This documentation-only record references tested HEAD `b94e35d` | Final checks, whole-feature reviews and evidence |

| Task/attempt | Tests/assertions | F/E/S | Seed | Exit | Exact log filename |
| --- | --- | --- | --- | --- | --- |
| 1 RED | 4 / 25 | 3/0/0 | 61562 | 1 | `token-usage-task1-red.log` |
| 1 GREEN | 110 / 12,323 | 0/0/0 | 65410 | 0 | `token-usage-task1-green.log` |
| 2 feature RED | 3 / 0 | 0/3/0 | 25074 | 1 | `token-usage-task2-red.log` |
| 2 initial GREEN | 15 / 132 | 0/0/0 | 17190 | 0 | `token-usage-task2-green.log` |
| 2 added characterization, first PASS | 5 / 83 | 0/0/0 | 33336 | 0 | `token-usage-task2-review-characterization.log` |
| 2 combined final GREEN | 17 / 163 | 0/0/0 | 54113 | 0 | `token-usage-task2-review-regressions.log` |
| 3 RED | 10 / 49 | 4/3/0 | 56712 | 1 | `token-usage-task3-red.log` |
| 3 GREEN | 155 / 13,053 | 0/0/0 | 10041 | 0 | `token-usage-task3-green.log` |
| 4 initial RED, missing cache hits | 3 / 43 | 1/0/0 | 58815 | 1 | `token-usage-task4-red.log` |
| 4 literal `skip:` attempt, failed despite filename | 85 / 1,409 | 3/0/0 | 13247 | 1 | `token-usage-task4-green.log` |
| 4 global cache-write coverage RED | 3 / 40 | 2/0/0 | 53104 | 1 | `token-usage-task4-global-cache-events-red.log` |
| 4 corrected GREEN | 85 / 1,420 | 0/0/0 | 22750 | 0 | `token-usage-task4-cache-unless-green.log` |
| 5 initial RED, including invalid arrangement | 3 / 35 | 1/1/0 | 26014 | 1 | `token-usage-task5-red.log` |
| 5 corrected valid-counter RED | 3 / 70 | 2/0/0 | 53651 | 1 | `token-usage-task5-red-corrected-counters.log` |
| 5 focused attempt 1, failed | 3 / 1,143 | 1/0/0 | 36369 | 1 | `token-usage-task5-green-focused-1.log` |
| 5 focused attempt 2, failed | 3 / 1,143 | 1/0/0 | 33808 | 1 | `token-usage-task5-green-focused-2.log` |
| 5 focus diagnostic, failed | 1 / 989 | 1/0/0 | 62771 | 1 | `token-usage-task5-focus-diagnostic.log` |
| 5 focused attempt 3, settling alone failed | 3 / 1,143 | 1/0/0 | 15823 | 1 | `token-usage-task5-green-focused-3.log` |
| 5 edge diagnostic, failed | 1 / 989 | 1/0/0 | 61507 | 1 | `token-usage-task5-focus-edge-diagnostic.log` |
| 5 focused final GREEN | 3 / 8,507 | 0/0/0 | 33778 | 0 | `token-usage-task5-green-focused-4.log` |
| 5 protected eight-file browser GREEN | 120 / 15,754 | 0/0/0 | 46584 | 0 | `token-usage-task5-green.log` |

Task 2's specification review found missing localized text/first-date,
singleton-marker and strict-local assertions. The same implementer added
test-only characterization; its first PASS above is **not a new feature RED**.
Re-review approved it. Task 3 subsequently added explicit global bounds/all-zero
row coverage, resolving Task 2's optional quality coverage note.

Task 1's six-file lint and scope checks passed (`token-usage-task1-rubocop.log`,
`token-usage-task1-postcommit-scope.log`). Task 2 lint/boundary and follow-up checks
passed (`token-usage-task2-rubocop.log`, `token-usage-task2-boundary.log`,
`token-usage-task2-review-rubocop.log`, `token-usage-task2-review-boundary.log`).
Task 3's five-file lint, scope and final status checks passed
(`token-usage-task3-lint.log`, `token-usage-task3-scope-check.log`,
`token-usage-task3-final-status.log`). Task 4's two-file lint, corrected scope and
post-commit checks passed (`token-usage-task4-cache-unless-rubocop.log`,
`token-usage-task4-cache-unless-scope.log`, `token-usage-task4-postcommit.log`).

Task 5 build, link-spacing rebuild, lint and final boundaries passed
(`token-usage-task5-build.log`, `token-usage-task5-build-link-spacing.log`,
`token-usage-task5-rubocop.log`, `token-usage-task5-final-boundary.log`), exit 0.
`token-usage-task5-attempts-before-full.json` indexes the preserved attempts.
Task 6 verified 28 local Markdown targets, whitespace and documentation-only scope,
all exit 0; evidence is in `/tmp/opencode/token-usage-task6-docs-RvR7UO2M/`, including
`final-markdown-links.log`, `committed-diff-check.log`,
`final-protected-boundary.log` and `final-status.log`. Task 6 had no artificial
RED or new application-test claim; all application bytes remained unchanged.

### Authoritative corrections — supersede historical proposed snippets

The task bodies below preserve the original plan for traceability. These reviewed
execution corrections are authoritative wherever an original example differs:

1. **Task 4: SUPERSEDES all three literal `cache(..., skip:)` wrappers.** Installed
   Rails 8.0.5.1 ignores `:skip`; the parent read `cache_helper.rb:176–240` and the
   three failing tests before authorizing the narrow correction. Actual code uses
   `cache_unless account.nil?, usage_lifetime_cache_key(account, section)` for
   `headline`, `estimates` and `breakdowns`. The key still contains version,
   locale, explicit authorized account, both counters and section. Global incurs
   **no cache reads OR writes**; recent chart/table/date output stays outside
   lifetime fragments. No query, policy or reporting change. See
   `token-usage-task4-api-adaptation.log` and failed/corrected logs above.
2. **Task 5: SUPERSEDES the persistent 9e12 counter sample and derived totals.**
   Existing counters are int32; `9_123_456_789_012` raised `ActiveModel::RangeError`
   before the matrix could exercise CSS. Parent approved test-only input
   `2_123_456_789` plus output `1_234_567_890`, with lifetime account total
   `3_358_024_679` and global total `3_358_024_699`. Aggregate totals still exceed
   INT32. No schema/policy/production change; Task 3's pure-view
   `9_123_456_789_012` example remains. The corrected RED genuinely measured 24px
   summaries with 1px outlines; report CSS supplies at least 44px/2px.
3. **Task 5 focus correction:** real edge hit-testing exposed adjacent text
   obscuring inline-flex methodology links. Waiting two animation frames alone
   still failed. Scoped `.n-usage-methodology-content .n-workspace-link` `mx-1`
   margins fixed the overlap; settling remains for native autoscroll. No focus,
   contrast, clipping, exact-value or protected-page assertion was weakened.
4. **Recorder and final log identity:** use the hardened external recorder
   described above, not the original rewrite-based snippet. The completed final
   full-suite attempt is `token-usage-final-full-attempt2.log`, not the
   incomplete `token-usage-final-full.log`. All failed/partial logs remain intact;
   filenames containing “green” do not override actual nonzero statuses.

### Independent review outcomes

Each task had a fresh specification review followed by a fresh quality review;
findings went back to the same implementer before re-review. Session IDs are
recorded separately, not represented as extra tests or planning-agent review.

| Task | Specification reviewer | Quality reviewer | Outcome |
| --- | --- | --- | --- |
| 0 | `ses_e8b4cff79ffep03vArJ2FXuAwT` | `ses_e8b4aee72ffesEQ71Y2U22HFE0` | Approved; minor recorder reuse note resolved/reviewed in Task 1; user baseline “Yes” followed |
| 1 | `ses_e8b411d33ffe3T2FKIJpLihs6y` | `ses_e8b3fcd7fffe5nTiUGJYeP4Smy` | Approved, no findings |
| 2 | `ses_e8b3b1088ffeVcG9v0Cwly7Gxm` | `ses_e8b36ffc4ffe5RltYYDkc8frvC` | Spec gaps fixed by test-only follow-up; spec re-review approved; quality approved; optional coverage resolved by Task 3 |
| 3 | `ses_e8b2f3222ffelfJoFQ34JhIEpd` | `ses_e8b2e510fffeI178N8e1xMp7dc` | Approved, no findings |
| 4 | `ses_e8b26d4e1ffenLuk3D1SbO7PRL` | `ses_e8b25dd48ffeG92iX17f3rN4P6` | Supported API correction approved, no findings |
| 5 | `ses_e8b166108ffeO4sSbO6W2U1lpB` | `ses_e8b13d2f7ffeWqpx9cwiTFcvMx` | Approved after browser/artifact review, no findings |
| 6 | `ses_e8b0e3eceffeSGw3RNpqMcPvcn` | `ses_e8b0d46c3fferz7D7U79ULGXRb` | Documentation scope approved, no findings |
| 7 whole feature | `ses_e8b0540c7ffeeKvcnDTnZVcsuk` | `ses_e8b028ee0ffe2eUD5motVLB3Dk` | Implementation approved; both re-reviewed completed final evidence and approved without findings |

The whole-feature reviewers initially deferred in-flight test results. Before
Phase B, both checked raw baselines/logs, hashes, exact commands, interrupted-run
separation and the final artifact matrix. The parent read/accepted the completed
evidence and then explicitly authorized only this plan update and evidence commit.

### Final Task 7 results — all six gates completed

| Final gate | Tests/assertions or result | F/E/S | Seed | True exit | Exact log filename |
| --- | --- | --- | --- | --- | --- |
| Focused, prescribed 17 files | 158 / 13,104 | 0/0/0 | 13430 | 0 | `token-usage-final-focused.log` |
| Full, completed rerun | 1,119 / 21,433 | 0/1/0 | 42700 | **1, NOT GREEN** | `token-usage-final-full-attempt2.log` |
| Tailwind build | Tailwind 4.1.16, completed in 190ms | n/a | n/a | 0 | `token-usage-final-build.log` |
| Browser, prescribed eight files | 120 / 15,754 | 0/0/0 | 16557 | 0 | `token-usage-final-browser.log` |
| RuboCop | Prescribed 14 files, no offenses | n/a | n/a | 0 | `token-usage-final-lint.log` |
| Brakeman 8.0.4 | Exactly two accepted high-confidence warnings; zero scan errors | n/a | n/a | **3, NOT GREEN** | `token-usage-final-brakeman.log` |

Final full has only the exact accepted RequestOptions error/callsites above, with
zero failures/skips. Final focused/full each contain seven duplicate-key JSON
warnings, exactly baseline. Scanner warning detail matches baseline exactly.
Focused/full gained 22 tests/791 assertions each; browser gained three tests/8,507
assertions. Nothing was skipped, filtered or suppressed to achieve these results.
The six command bodies were those prescribed in Task 7, in focused → full → build
→ browser → lint → scanner order, except the separately preserved full retry.

The first full attempt, `token-usage-final-full.log`, seed 59622, was interrupted
by an incorrectly supplied **120-second harness timeout**. It has no suite summary
or true-exit trailer: its actual command exit is **UNKNOWN**, not an invented 124
and not a completed test result. The terminated test PID was confirmed absent
before the same full command was rerun with timeout disabled and a new exclusive
filename. No real database overlap occurred. An overbroad process guard first
returned 1 on a pre-existing foreman `tailwindcss:watch` process; read-only
classification distinguished it from a DB/test worker, and the corrected guard
passed. That watcher was left untouched. The timeout/process-diagnostic artifacts
are preserved separately; no source fix or warning waiver resulted.

Final evidence lives outside Git:

- `token-usage-task7-verification-report.md`: complete Phase A report and limits.
- `token-usage-task7-command-manifest.json`: exact invocation/order/log identity.
- `token-usage-task7-final-evidence-check.log`: parsed counts/seeds/exits, SHA-256
  hashes, exact baseline comparison, final links/protected refs/cleanliness.
- `token-usage-task7-baseline-comparison.log`,
  `token-usage-task7-whole-diff.log`, `token-usage-task7-boundaries.log`,
  `token-usage-task7-static-review.log`, `token-usage-task7-commits.log`,
  `token-usage-task7-browser-artifacts.log`, `token-usage-task7-report-validation.log`.
- `token-usage-task7-full-timeout-diagnosis.log` (conservative guard exit 1),
  `token-usage-task7-process-inspection.log`,
  `token-usage-task7-process-classification.log`,
  `token-usage-task7-full-timeout-diagnosis-v2.log` (last three exit 0).
- Phase B static/commit verification uses new
  `token-usage-task7-phaseb-*.log` artifacts and
  `token-usage-task7-phaseb-report.md`; no application/DB/build/test/scanner rerun.

### Whole-feature scope, navigation and data boundaries

The whole actual diff was inspected from immutable base, not only the Task 6
commit: **29 files, 1,241 insertions and 45 deletions before this record**.
Including this plan, the completed feature has **30 changed paths**. All 29 prior
paths are the approved UI/tests/catalogs/guide/index/diagram files; this record is
the only Phase B tracked change.

Protected controller/report/account/token-model queries and estimators; legacy
dashboard overview and standalone summary/summary-content/transparency; shared
workspace header/CSS; Sources; composer/app JavaScript; routes; schema/database;
dependencies; test support and fixtures remain unchanged from execution base.
The existing numeric SVG helper is byte-identical. The only shared-layout edit is
the approved report drawer predicate. New CSS is usage-scoped; authored strings
are escaped and decorative widths are numeric. Legacy selector updates retain
their exact values, counts, authorization, tenant/cache restoration and locale
assertions, rather than weakening them.

Global current-membership account-wide data still uses thirty local calendar
dates/zero-filled days and separate lifetime counter sums. Account headlines remain
lifetime; recent activity retains exclusive `created_at > 30.days.ago`, SQL DATE
grouping, no upper bound and every returned future bucket. Permissions/data
isolation/default account, read-only behavior, existing estimation policy and
complete methodology remain intact. Global New chat stays generic; scoped Back
returns to its account; unrelated drawers/Sources/composer remain unchanged.

Protected refs remain `feat/sources-workspace-ui`
`4be5ab1f0f7399b6f7766115fb709ee5929664cb`, `main`
`c08cbfe22260059dd76a085a1c0aec1dfaeee17d`, and
`docs/token-usage-workspace-design` `d5f396108d1041c0ed5c6febf217f24bc3e85049`.
The feature tree was clean after Phase A. Main's unrelated local work was neither
inspected nor discarded; **there is no claim that main's working tree is clean**.
Protected-byte/allowed-path/whitespace and all 28 local targets in the three
changed guide/index/diagram docs passed again after the final gates, including
all 20 prescribed protected file/directory specifications.

### Actual browser artifacts and manual limits

Final directory: `/tmp/opencode/token-usage-workspace-1008233/`.
`matrix.json` has **32 distinct states**: both scopes × EN/FR × 375×812, 768×1024,
1440×1000 and 812×375 × light/dark. **72 PNGs** comprise 64 matrix images plus
eight empty/global-old/account-old/no-membership images. All expected filenames
exist, matrix PNG dimensions match viewports, and `contrast.jsonl` has **32
records**. Every sampled ratio meets its target. Actual final minima:

| Category | Light | Dark | Required | Samples per theme |
| --- | --- | --- | --- | --- |
| Normal text | 6.54163621921436 | 10.2097248855386 | 4.5:1 | 1,586 |
| Chart | 4.945457412311979 | 10.802270175720084 | 3:1 | 16 |
| Summary border | 4.741667181590045 | 5.857398603056878 | 3:1 | 32 |
| Focus outline | 4.945457412311979 | 10.802270175720084 | 3:1 | 16 |

The Phase A worker actually opened these **10 final-run images**, relative to that
directory, not every final image or every content position:

```text
global-en-1440-1000-light-overview.png
global-en-375-812-light-overview.png
global-en-375-812-dark-methodology.png
375-empty-dark.png
375-no-memberships-light.png
global-en-768-1024-dark-overview.png
account-fr-375-812-dark-overview.png
account-fr-375-812-dark-methodology.png
account-en-812-375-light-methodology.png
account-fr-1440-1000-light-overview.png
```

Task 5's implementer opened 40 images in
`/tmp/opencode/token-usage-workspace-997488/`, recorded in
`opened-manifest-and-ui-review.json`; the parent opened four; Task 5 spec and
quality reviewers each opened 18 representatives. Its complete browser rerun
directory was `token-usage-workspace-997937`, also 32 states/72 PNGs/32 contrast
records. The whole-feature spec reviewer opened 22 prior images and 10 final;
the whole-feature quality reviewer opened 14 prior and four final. These counts
are per observer/run and **are not summed as unique images** because overlap is
not established.

Reviewed representatives show the desktop overview/detail rail, readable exact
EN/FR quantities, wrapping long account/model names, clear native disclosure/link
focus and honest empty guidance. A pathological mobile account name makes a long
header requiring scrolling before metrics. Fixed mobile navigation can overlay
unfocused mid-page content at rest; native-Tab autoscroll/edge hit-testing verifies
sampled focused targets fully clear it. Viewport screenshots do not show every
section at once; range-geometry tests cover number/model clipping across states.
**Native 200% browser zoom remains UNVERIFIED**. CDP viewport emulation is not
native zoom, and this is not a full screen-reader/assistive-technology audit or a
blanket WCAG claim.

Final Phase A disk: **root 2.1G free / 97% used**, `/tmp` 2.2G free / 45% used;
available bytes 2,193,440,768 and 2,311,143,424 respectively. No cleanup occurred.

### Completion boundary

Task checkboxes below record completed work, including reviewed API/test-data
adaptations, not a claim that every original proposal was used verbatim. Accepted
full exit 1/scanner exit 3 and native-zoom limits remain explicit. Phase B performs
only static documentation/link/checkbox/scope checks and a documentation commit;
it does not claim a new application test, build, lint or scanner run. The parent
will read this record and verify the final commit before user-facing completion.

Agent skills and MCP remain unimplemented later subprojects requiring separate
approval. No new account/date/report selectors, reporting metrics, billing,
quotas, exports, forecasting, tracking or background work were added. No baseline
bug fix, merge, push, PR, worktree removal, cleanup or integration action is
authorized by this execution record.

## File responsibilities and contracts

| Unit | Files | Responsibility |
| --- | --- | --- |
| Workspace shell | Modify `app/views/token_usages/show.html.erb`, `app/views/layouts/application.html.erb`, `app/helpers/token_usages_helper.rb`; create paired `config/locales/{en,fr}.nosia_usage_workspace.yml` | Single h1, real global/account scope, shared header, useful Back, preserved generic desktop New chat, report-only drawer suppression. |
| Date presentation | Extend `TokenUsagesHelper`; create `app/views/token_usages/_activity.html.erb` | Convert existing Date/ISO-string bucket keys to sorted Dates without aggregation/filtering/zero filling; chart and table consume the same ordered hash. |
| Report composition | Create `app/views/token_usages/_workspace.html.erb`, `_metrics.html.erb`, `_estimates.html.erb`, `_breakdowns.html.erb`, `_methodology.html.erb` | Overview + detail rail, exact quantities, separately labeled lifetime content, all supplied breakdown rows, honest fallback and complete existing methodology. |
| Scoped lifetime caching | Add `usage_lifetime_cache_key(account, section)` to existing helper; add three cache blocks in `_workspace` | Account/locale/counter/version/section identity; global rendering uncached; recent chart/table and dates outside every lifetime fragment. |
| Responsive styling | Create `app/assets/stylesheets/nosia/usage_workspace.css`; add its import to `app/assets/tailwind/application.css` | Only `.n-usage-workspace` descendants and `main:has([data-usage-workspace])`; 1280px rail, wrapping, contrast, native disclosure focus/targets, fixed-nav clearance. |
| New coverage | Create `test/controllers/token_usage_workspace_shell_test.rb`, `token_usage_workspace_test.rb`; `test/helpers/token_usage_activity_test.rb`, `token_usage_workspace_content_test.rb`; `test/integration/token_usage_workspace_cache_test.rb`; `test/system/token_usage_workspace_test.rb` | Route/scoping/read-only, data/empty/content, date presentation, fragment boundaries, browser/a11y evidence. Reuse opt-in `DashboardFixtures`; do not alter global fixtures. |
| Narrow legacy assertion updates | `test/controllers/global_token_usage_test.rb`, `test/controllers/accounts/scoped_tokens_usage_test.rb`, `test/controllers/account_experience_test.rb`, `test/integration/token_usages_test.rb`, `test/integration/localized_pages_test.rb`, `test/integration/localized_cache_test.rb`, `test/system/dashboard_test.rb` | Replace report-page presentation selectors only. Retain all values, counts, authorization, ambient-tenant, cache, methodology, locale and dashboard assertions. |
| Docs | Create `docs/token-usage-workspace.md`; modify `docs/README.md`, `docs/DIAGRAMS.md`; update this plan's checkboxes/evidence during execution | Current report semantics, cache/freshness boundaries, navigation, accessibility and actual verification limitations. |

**Protected files:** `app/controllers/token_usages_controller.rb`, `app/models/token_usage/report.rb`, `app/models/account.rb`, `app/models/token_usage.rb`, `app/views/token_usages/_overview.html.erb`, `_summary.html.erb`, `_summary_content.html.erb`, `_transparency.html.erb`, the shared workspace header/styles, Sources code, composer code, routes and dependencies. Legacy summary partials remain available for existing background/standalone rendering contracts; the redesigned report uses its own components. Do not redesign the dashboard by changing `_overview`.

**Explicit component inputs:** `_workspace(account:, headline:, lifetime:, green_summary:, tokens_by_kind:, daily_totals:, starts_at: nil, ends_at: nil)` receives already-authorized data. `account == nil` means global, including a no-membership report. `_metrics(totals:, prefix:)` requires input/output/total; `prefix` is only the literal `period` or `lifetime`. `_activity(daily_totals:, scoped:, starts_at: nil, ends_at: nil)` receives ordered Date keys. No component infers an account from `Current` or a query parameter.

## Safe launchers and evidence

The following launchers are the original planning examples; the execution record's hardened external-recorder correction supersedes the historical `record_check` body. Execution used the isolated feature worktree, not the documentation checkout. Every database-sharing command was sequential. Source `/tmp/opencode/token-usage-workspace-helpers.zsh` in each fresh shell; these are external conveniences, not repository files. Do not overwrite preserved evidence to replay these historical commands.

```bash
rails_test() {
  mise exec ruby@4.0.7 -- env RAILS_ENV=test DATABASE_URL=postgresql:///nosia_token_usage_workspace_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails "$@"
}

browser_test() {
  mise exec ruby@4.0.7 -- env RAILS_ENV=test DATABASE_URL=postgresql:///nosia_token_usage_workspace_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test "$@"
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

Never print/copy/edit/commit `.env`; the relative path above loads the original repository's file without exposing it. Never use `db:reset`, shared development databases, live workers, live ingestion or model providers. Do not install packages, upgrade dependencies or clean unrelated caches/databases. Preserve every failed attempt with a new filename. Do not enable shell `errexit` for expected RED commands. Read each saved log and record tests/assertions/seed/true exit, not merely the launcher's final message.

Historical Sources evidence is only context: focused/browser runs passed; full server runs retained `Chat::RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults`, `NoMethodError: undefined method 'augmented_context'`, `app/models/chat/completionable.rb:39` → `test/models/chat/request_options_test.rb:32` (test starts at 29), exit 1. Brakeman retained API-token `PermitAttributes` (`app/controllers/api_tokens_controller.rb:62`) and Rails EOL (`Gemfile.lock:318`), exit 3; duplicate-key JSON warnings occurred. **Run a fresh baseline and stop for the user's explicit acceptance of exact failures/warnings before application edits.** Past acceptance is not a waiver here.

## Task 0: Isolated execution checkout and fresh baseline

**Files:** No tracked application changes. Existing ignored CSS may be built. Keep evidence outside Git.

- [x] **Step 1: Verify the planning tree and create the execution worktree.** Inspect existing branches/paths instead of overwriting them. Run from this documentation worktree:

```bash
git status --short --branch
git worktree list
git -C /home/cbldev/gitd/dilolabs/nosia check-ignore .worktrees/token-usage-workspace-ui
git worktree add ../token-usage-workspace-ui -b feat/token-usage-workspace-ui HEAD
```

Expected: clean documentation tree; ignored destination; feature worktree `/home/cbldev/gitd/dilolabs/nosia/.worktrees/token-usage-workspace-ui` based on the committed plan. Move the session there using the harness session-move tool, or set every tool's working directory explicitly. Never modify Sources or `main` to establish the execution base.

- [x] **Step 2: Check installed tools and preserve the execution base.** All following commands use the new worktree.

```bash
mise exec ruby@4.0.7 -- ruby --version
mise exec ruby@4.0.7 -- bundle check
/usr/bin/chromium --version
/usr/bin/chromedriver --version
df -h . /tmp/opencode
record_check /tmp/opencode/token-usage-workspace-base.log git rev-parse HEAD
```

Expected: installed dependencies, matching local browser/driver and adequate disk space. Ask if missing/insufficient; do not install or delete other work.

- [x] **Step 3: Verify the explicit environment and prepare only the new test database.**

```bash
mise exec ruby@4.0.7 -- env RAILS_ENV=test DATABASE_URL=postgresql:///nosia_token_usage_workspace_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -e 'abort "Unsafe test environment" unless ENV["RAILS_ENV"] == "test" && ENV["DATABASE_URL"] == "postgresql:///nosia_token_usage_workspace_test" && ENV["AI_API_KEY"] == "nosia-test-key" && ENV["PARALLEL_WORKERS"] == "1"; puts "Dedicated test environment verified"'
rails_test db:prepare
rails_test runner 'abort "Wrong database" unless Rails.env.test? && ActiveRecord::Base.connection.select_value("SELECT current_database()") == "nosia_token_usage_workspace_test"; puts "Dedicated test database verified"'
rails_test tailwindcss:build
```

Expected: only the named test database is prepared; Tailwind output remains ignored.

- [x] **Step 4: Run fresh focused, full, browser and scanner baselines sequentially.**

```bash
record_check /tmp/opencode/token-usage-baseline-focused.log rails_test test test/models/token_usage/report_test.rb test/helpers/token_usages_helper_test.rb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/dashboards_controller_test.rb test/controllers/account_experience_test.rb test/integration/token_summary_cache_test.rb test/integration/token_usages_test.rb test/integration/token_footer_test.rb test/integration/localized_pages_test.rb test/integration/localized_cache_test.rb test/internationalization/catalogs_test.rb
record_check /tmp/opencode/token-usage-baseline-full.log rails_test test
record_check /tmp/opencode/token-usage-baseline-browser.log browser_test test/system/dashboard_test.rb test/system/account_experience_test.rb test/system/localization_test.rb test/system/sources_workspace_test.rb test/system/sources_dropzone_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
record_check /tmp/opencode/token-usage-baseline-brakeman.log mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

Expected: focused/browser pass; full suite/scanner results are inspected, not assumed. Stop for acceptance of any reproduced existing failures/warnings; investigate new baseline differences rather than silently waiving them.

- [x] **Step 5: Record readiness.** `git status --short` must show no tracked application changes. Record immutable base SHA, exact counts/exits/logs and any user baseline acceptance in execution notes. If Subagent-Driven was selected, obtain the method's task reviews before proceeding. No environment-only source commit is needed.

## Task 1: Workspace header, scope and report-only navigation

**Create:** `test/controllers/token_usage_workspace_shell_test.rb`, paired usage-workspace catalogs.
**Modify:** `app/helpers/token_usages_helper.rb`, `app/views/token_usages/show.html.erb`, `app/views/layouts/application.html.erb`, `test/controllers/account_experience_test.rb`, and three report heading assertions identified below.

- [x] **Step 1: Add the failing shell tests.**

```ruby
# test/controllers/token_usage_workspace_shell_test.rb
require "test_helper"
require_relative "../support/dashboard_fixtures"

class TokenUsageWorkspaceShellTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
  end
  teardown { travel_back }

  test "global and scoped reports have one heading and their authorized scope" do
    get token_usage_path, params: { account_id: @foreign.id }
    assert_response :success
    assert_select "main h1", text: I18n.t("nosia.usage.title"), count: 1
    assert_select "[data-usage-workspace] [data-workspace-scope]", text: "All your accounts"
    assert_select "[data-usage-workspace] a[href='#{user_root_path}']"
    assert_select "[data-usage-workspace] a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
    assert_select "#accordion-right-actions, #drawer-right", count: 0

    get account_token_usage_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_select "main h1", count: 1
    assert_select "[data-workspace-scope]", text: "Account: #{@second.name}"
    assert_select "nav[aria-label='Breadcrumb'] a[href='#{account_path(@second)}']"
    assert_select "[data-workspace-back][href='#{account_path(@second)}']"
    assert_select "[data-usage-workspace] a[href='#{new_chat_path}']", count: 0
    assert_select "#accordion-right-actions, #drawer-right", count: 0
    assert_equal @first, @user.reload.first_account
  end

  test "French scope is translated and authored account names are escaped" do
    @second.update_columns(name: "<script>Compte</script>")
    get account_token_usage_path(@second), headers: { "Accept-Language" => "fr" }
    assert_select "[data-workspace-scope]", text: "Compte : #{@second.name}"
    assert_select "main script", count: 0
    refute_match(/translation missing|missing translation/i, response.body)
    get token_usage_path, headers: { "Accept-Language" => "fr" }
    assert_select "[data-workspace-scope]", text: "Tous vos comptes"
  end

  test "no memberships remain a successful zero report rather than a setup replacement" do
    sign_in_overview(experience(:users, :overview_no_account))
    assert_no_enqueued_jobs { get token_usage_path }
    assert_response :success
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='0']"
    assert_select "[data-usage-no-memberships] a[href='#{accounts_path}']"
    assert_select "details", minimum: 1
  end

  test "unrelated tools keep their drawers and Sources keep their existing shell" do
    [ new_chat_path, api_tokens_path ].each do |path|
      get path
      assert_response :success
      assert_select "#accordion-right-actions, #drawer-right", count: 2
    end
    get sources_path
    assert_select "[data-source-workspace]"
    assert_select "#accordion-right-actions, #drawer-right", count: 0
  end
end
```

- [x] **Step 2: Run RED.**

```bash
record_check /tmp/opencode/token-usage-task1-red.log rails_test test test/controllers/token_usage_workspace_shell_test.rb
```

Expected: missing h1/workspace/scope/Accounts guidance and existing global drawers. Infrastructure errors are not a valid feature RED.

- [x] **Step 3: Add the shell predicate and catalogs.** Insert before `usage_trend_points`; retain that method byte-for-byte.

```ruby
  # @return [Boolean] Whether this request renders the Token usage workspace
  def token_usage_workspace_page?
    controller_path == "token_usages"
  end
```

Create the complete paired catalogs now; later tasks consume these keys without editing shared usage translations:

```yaml
# config/locales/en.nosia_usage_workspace.yml
en:
  nosia:
    usage_workspace:
      all_accounts: "All your accounts"
      purpose: "Understand token activity and the estimates behind it."
      global_scope: "Account-wide usage across your current memberships, including other members’ activity."
      account_scope: "Account-wide usage, including other members’ activity in this account."
      no_memberships: "You have no account memberships. This report contains zero usage."
      overview: "Usage overview"
      lifetime: "Lifetime"
      recent: "Recent activity"
      trend_title: "Daily token activity"
      account_window: "The account report uses activity recorded after its rolling 30-day cutoff, not the global calendar window."
      bucket_dates: "Returned activity dates: %{start} – %{end}"
      no_recent: "No recent activity in this report. Lifetime usage may still be present."
      estimates: "Environmental estimates"
      estimate_caveat: "Estimates, not measured consumption. Lifetime top-five model estimates plus embedding energy use the existing coefficients."
      context: "Report context"
      fallback: "Fallback estimate*"
      lifetime_breakdowns: "Lifetime breakdowns"
```

```yaml
# config/locales/fr.nosia_usage_workspace.yml
fr:
  nosia:
    usage_workspace:
      all_accounts: "Tous vos comptes"
      purpose: "Comprendre l’activité des jetons et les estimations associées."
      global_scope: "Utilisation de tous les comptes dont vous êtes membre, y compris l’activité des autres membres."
      account_scope: "Utilisation de l’ensemble de ce compte, y compris l’activité des autres membres."
      no_memberships: "Vous n’êtes membre d’aucun compte. Ce rapport présente une utilisation nulle."
      overview: "Vue d’ensemble de l’utilisation"
      lifetime: "Depuis la création"
      recent: "Activité récente"
      trend_title: "Activité quotidienne des jetons"
      account_window: "Le rapport du compte utilise l’activité enregistrée après son seuil glissant de 30 jours, et non la période calendaire globale."
      bucket_dates: "Dates d’activité renvoyées : %{start} – %{end}"
      no_recent: "Aucune activité récente dans ce rapport. Une utilisation antérieure peut être présente."
      estimates: "Estimations environnementales"
      estimate_caveat: "Il s’agit d’estimations, et non d’une consommation mesurée. Les estimations des cinq premiers modèles et de la vectorisation depuis la création utilisent les coefficients existants."
      context: "Contexte du rapport"
      fallback: "Estimation de repli*"
      lifetime_breakdowns: "Détails depuis la création"
```

- [x] **Step 4: Replace `show.html.erb` with this transitional shell.** It intentionally retains the old report components until Task 3.

```erb
<% content_for :account_tool_title, t("nosia.usage.title") if @account %>
<div class="n-workspace n-usage-workspace" data-usage-workspace>
  <%= render "workspaces/header", title: t("nosia.usage.title"), description: t("nosia.usage_workspace.purpose"), scope_label: @usage_account ? t("nosia.workspace.account", name: @usage_account.name) : t("nosia.usage_workspace.all_accounts"), trail: @usage_account ? [] : [{ label: t("nosia.nav.home"), path: user_root_path }, { label: t("nosia.usage.title"), path: nil }], back_path: @usage_account ? account_path(@usage_account) : nil, show_new_chat: @usage_account.nil? %>
  <p class="n-workspace-help"><%= t(@usage_account ? "nosia.usage_workspace.account_scope" : "nosia.usage_workspace.global_scope") %></p>
  <% if @report && Current.user.accounts.empty? %>
    <p class="n-workspace-help" data-usage-no-memberships><%= t("nosia.usage_workspace.no_memberships") %> <%= link_to t("nosia.nav.accounts"), accounts_path, class: "n-workspace-link" %></p>
  <% end %>
  <% if @report %>
    <%= render "overview", report: @report, title_id: "global-usage-title", show_report_link: false %>
    <section id="global-lifetime-summary" aria-labelledby="global-lifetime-title">
      <h2 id="global-lifetime-title"><%= t("nosia.dashboard.lifetime_details") %></h2>
      <%= render "summary_content", token_totals: @report.lifetime_totals, green_summary: @report.green_summary, tokens_by_kind: @report.tokens_by_kind, tokens_by_day: {} %>
    </section>
  <% else %>
    <%= render "summary", account: @usage_account, token_totals: @token_totals, green_summary: @green_summary, tokens_by_kind: @tokens_by_kind, tokens_by_day: @tokens_by_day %>
  <% end %>
  <%= render "transparency" %>
</div>
```

In `app/views/layouts/application.html.erb`, change only the drawer condition to:

```erb
<% if Current.user && !account_page? && !dashboard_page? && !sources_workspace_page? && !token_usage_workspace_page? %>
```

- [x] **Step 5: Update only obsolete presentation assertions.** Change the report h2 assertions to h1 in `test/integration/token_usages_test.rb` (first test), `test/integration/localized_pages_test.rb` (French usage test) and `test/integration/localized_cache_test.rb` (French usage cache test). Keep the dashboard absence assertion as h2. Replace the complete account-experience test starting at its current line 122 with:

```ruby
  test "global tools retain navigation and workspace reports omit conversation drawers" do
    [ sources_path, new_sources_text_path, api_tokens_path, token_usage_path,
      system_prompt_path(experience(:prompts, :overview_second_shared)) ].each do |path|
      get path
      assert_response :success
      assert_select "nav[aria-label='Breadcrumb']", count: 0
      sources_workspace = [ sources_path, new_sources_text_path ].include?(path)
      report_workspace = path == token_usage_path
      assert_select "#accordion-right-actions, #drawer-right", count: sources_workspace || report_workspace ? 0 : 2
      if sources_workspace || report_workspace
        workspace = sources_workspace ? "[data-source-workspace]" : "[data-usage-workspace]"
        assert_select workspace, count: 1
        assert_select "#{workspace} a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
      end
    end
  end
```

The new expected heading lines are (the French line occurs in both localized test files):

```ruby
assert_select "h1", text: /Token usage & environmental impact/
assert_select "h1", text: "Utilisation des jetons et impact environnemental"
```

- [x] **Step 6: Run GREEN and commit the shell.**

```bash
record_check /tmp/opencode/token-usage-task1-green.log rails_test test test/controllers/token_usage_workspace_shell_test.rb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/account_experience_test.rb test/integration/token_usages_test.rb test/integration/localized_pages_test.rb test/integration/localized_cache_test.rb test/internationalization/catalogs_test.rb
git diff --check
git add app/helpers/token_usages_helper.rb app/views/token_usages/show.html.erb app/views/layouts/application.html.erb config/locales/en.nosia_usage_workspace.yml config/locales/fr.nosia_usage_workspace.yml test/controllers/token_usage_workspace_shell_test.rb test/controllers/account_experience_test.rb test/integration/token_usages_test.rb test/integration/localized_pages_test.rb test/integration/localized_cache_test.rb
git commit -m "feat(usage): Add the scoped report workspace shell"
```

Expected: focused tests pass. No controller/model/query/default-account changes.

## Task 2: Date-faithful static activity component

**Create:** `test/helpers/token_usage_activity_test.rb`, `app/views/token_usages/_activity.html.erb`.
**Modify:** `app/helpers/token_usages_helper.rb`. The dashboard numeric helper remains unchanged.

- [x] **Step 1: Write direct component tests with explicit locals and no session.**

```ruby
# test/helpers/token_usage_activity_test.rb
require "test_helper"

class TokenUsageActivityTest < ActionView::TestCase
  include TokenUsagesHelper

  test "date normalization preserves every returned bucket and quantity" do
    supplied = { "2026-11-30" => 71, Date.new(2026, 9, 24) => 9, "2026-10-24" => 12 }
    original = supplied.dup
    days = usage_display_days(supplied)
    assert_equal [ Date.new(2026, 9, 24), Date.new(2026, 10, 24), Date.new(2026, 11, 30) ], days.keys
    assert_equal [ 9, 12, 71 ], days.values
    assert_equal original, supplied
    assert_equal({}, usage_display_days({}))
  end

  test "chart and accessible table use exactly the same ordered values in both locales" do
    days = { Date.new(2026, 9, 24) => 9, Date.new(2026, 10, 24) => 1234, Date.new(2026, 11, 30) => 71 }
    %i[en fr].each do |locale|
      html = I18n.with_locale(locale) do
        ApplicationController.render(partial: "token_usages/activity", locals: { daily_totals: days, scoped: true })
      end
      fragment = Nokogiri::HTML.fragment(html)
      assert_select fragment, "svg[role='img'][aria-labelledby='usage-trend-title usage-trend-description']"
      assert_select fragment, "svg title#usage-trend-title", count: 1
      assert_select fragment, "svg title#usage-trend-title", text: I18n.t("nosia.usage_workspace.trend_title", locale: locale)
      assert_select fragment, "svg desc#usage-trend-description", count: 1
      assert_select fragment, "polyline[points='#{usage_trend_points(days)}']"
      assert_equal days.keys.map(&:iso8601), fragment.css("[data-usage-day]").map { |row| row["data-usage-day"] }
      assert_equal days.values, fragment.css("[data-usage-day] td").map { |cell| cell["data-value"].to_i }
      assert_select fragment, "details[data-usage-daily] > summary", count: 1
      assert_select fragment, "th[scope='col']", count: 2
      assert_select fragment, "th[scope='row']", count: 3
      assert_select fragment, "[data-usage-bucket-dates]", text: /#{Regexp.escape(I18n.l(days.keys.last, format: :short, locale: locale))}/
      refute_match(/translation missing|missing translation|NaN|Infinity/i, html)
    end
  end

  test "empty and single point series remain honest and finite" do
    [ {}, { Date.new(2026, 10, 24) => 8 } ].each do |days|
      html = ApplicationController.render(partial: "token_usages/activity", locals: { daily_totals: days, scoped: true })
      fragment = Nokogiri::HTML.fragment(html)
      assert_select fragment, "[data-usage-day]", count: days.length
      assert_select fragment, "[data-usage-no-recent]", count: days.empty? ? 1 : 0
      assert_select fragment, "polyline[points='#{usage_trend_points(days)}']"
      assert_select fragment, "[data-usage-window]", count: 0
      refute_match(/NaN|Infinity/, html)
    end
  end
end
```

- [x] **Step 2: Run RED.**

```bash
record_check /tmp/opencode/token-usage-task2-red.log rails_test test test/helpers/token_usage_activity_test.rb
```

Expected: missing presentation method/partial. Then implement only those component contracts.

- [x] **Step 3: Add this helper before the unchanged SVG method.** Invalid internal date keys should raise, not silently disappear or become zero usage. SQL date grouping supplies unique Date/ISO-string keys; do not add unrelated input coercion/aggregation.

```ruby
  # @param buckets [Hash{Date, String => Integer}] Existing SQL/report date buckets
  # @return [Hash{Date => Integer}] Chronological buckets with quantities unchanged
  def usage_display_days(buckets)
    buckets.map { |date, tokens| [ date.to_date, tokens ] }.sort_by(&:first).to_h
  end
```

- [x] **Step 4: Create the complete activity partial.** There is no invented account upper bound or forced thirty-day series. A singleton also gets a visible circle; an empty series has an explicit empty explanation and empty table.

```erb
<%# locals: (daily_totals:, scoped:, starts_at: nil, ends_at: nil) %>
<section class="n-workspace-panel n-usage-activity" aria-labelledby="usage-activity-title">
  <h2 id="usage-activity-title" class="n-workspace-section-title"><%= t("nosia.usage_workspace.recent") %></h2>
  <% if scoped %>
    <p class="n-workspace-help"><%= t("nosia.usage_workspace.account_window") %></p>
  <% else %>
    <p class="n-workspace-help" data-usage-window><%= l(starts_at.to_date, format: :short) %> – <%= l(ends_at.to_date, format: :short) %></p>
  <% end %>
  <% if daily_totals.any? %>
    <p class="n-workspace-help" data-usage-bucket-dates><%= t("nosia.usage_workspace.bucket_dates", start: l(daily_totals.keys.first, format: :short), end: l(daily_totals.keys.last, format: :short)) %></p>
  <% end %>
  <% if daily_totals.values.all?(&:zero?) %>
    <p class="n-workspace-help" data-usage-no-recent><%= t("nosia.usage_workspace.no_recent") %></p>
  <% end %>
  <svg viewBox="0 0 300 40" class="n-usage-chart" preserveAspectRatio="none" role="img" aria-labelledby="usage-trend-title usage-trend-description">
    <title id="usage-trend-title"><%= t("nosia.usage_workspace.trend_title") %></title>
    <desc id="usage-trend-description"><%= t("nosia.dashboard.trend_description") %></desc>
    <polyline fill="none" stroke="currentColor" stroke-width="2" vector-effect="non-scaling-stroke" points="<%= usage_trend_points(daily_totals) %>"></polyline>
    <% if daily_totals.one? %><circle cx="0" cy="<%= usage_trend_points(daily_totals).split(',').last %>" r="2" fill="currentColor"></circle><% end %>
  </svg>
  <details class="n-usage-disclosure" data-usage-daily>
    <summary><%= t("nosia.dashboard.daily_data") %></summary>
    <table>
      <caption class="sr-only"><%= t("nosia.dashboard.daily_data") %></caption>
      <thead><tr><th scope="col"><%= t("nosia.dashboard.date") %></th><th scope="col"><%= t("nosia.usage.tokens_title") %></th></tr></thead>
      <tbody>
        <% daily_totals.each do |date, tokens| %>
          <tr data-usage-day="<%= date.iso8601 %>"><th scope="row"><%= l(date, format: :short) %></th><td data-value="<%= tokens %>"><%= number_with_delimiter(tokens) %></td></tr>
        <% end %>
      </tbody>
    </table>
  </details>
</section>
```

- [x] **Step 5: Run GREEN including the unchanged dashboard helper contract; commit.**

```bash
record_check /tmp/opencode/token-usage-task2-green.log rails_test test test/helpers/token_usage_activity_test.rb test/helpers/token_usages_helper_test.rb test/models/token_usage/report_test.rb
git diff --check
git add app/helpers/token_usages_helper.rb app/views/token_usages/_activity.html.erb test/helpers/token_usage_activity_test.rb
git commit -m "feat(usage): Add a date-faithful accessible activity chart"
```

Expected: all pass; no query, aggregation, zero-fill or dashboard markup changes.

## Task 3: Overview, rail, exact breakdowns and complete methodology

**Create:** `test/controllers/token_usage_workspace_test.rb`, `test/helpers/token_usage_workspace_content_test.rb` and five report-only partials listed in the file table.
**Modify:** `show.html.erb`; narrowly adapt existing report-page selectors. CSS polish follows Task 5; do not add caching until Task 4's tests exist.

- [x] **Step 1: Add request coverage before switching the report.**

```ruby
# test/controllers/token_usage_workspace_test.rb
require "test_helper"
require_relative "../support/dashboard_fixtures"

class TokenUsageWorkspaceTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
  end
  teardown { travel_back }

  test "global overview separates calendar totals from lifetime detail and stays read only" do
    counts = [ Chat.count, Message.count, Prompt.count, TokenUsage.count, Document.count, Text.count, Qna.count, Website.count ]
    counters = @user.accounts.order(:id).pluck(:id, :input_tokens_count, :output_tokens_count, :updated_at)
    assert_no_enqueued_jobs { get token_usage_path, params: { account_id: @foreign.id } }
    assert_response :success
    assert_select "[data-period-total][data-value='1057']"
    assert_select "[data-period-input][data-value='952']"
    assert_select "[data-period-output][data-value='105']"
    assert_select "#global-lifetime-summary [data-lifetime-total][data-value='1065']"
    assert_select "#global-lifetime-summary [data-lifetime-input][data-value='959']"
    assert_select "#global-lifetime-summary [data-lifetime-output][data-value='106']"
    rows = css_select("[data-usage-day]")
    assert_equal 30, rows.length
    assert_equal "2026-09-25", rows.first["data-usage-day"]
    assert_equal "2026-10-24", rows.last["data-usage-day"]
    assert_equal 1057, css_select("[data-usage-day] td").sum { |cell| cell["data-value"].to_i }
    assert_select "[data-usage-model]", count: 1
    assert_select "[data-usage-model='private-model']", count: 0
    assert_select "[data-usage-kind='embedding'][data-value='40']"
    assert_select "[data-usage-kind='agent_skill'][data-value='5']"
    assert_select "[data-usage-fallback]", count: 1
    assert_equal counts, [ Chat.count, Message.count, Prompt.count, TokenUsage.count, Document.count, Text.count, Qna.count, Website.count ]
    assert_equal counters, @user.accounts.order(:id).pluck(:id, :input_tokens_count, :output_tokens_count, :updated_at)
    assert_equal @first, @user.reload.first_account
  end

  test "account uses lifetime headlines and every bucket from its existing lower bound query" do
    cutoff = 30.days.ago
    dashboard_usage(:dashboard_second_member).update_columns(created_at: cutoff)
    dashboard_usage(:dashboard_skill).update_columns(created_at: @report_time + 40.days)
    get account_token_usage_path(@second)
    assert_response :success
    assert_select "[data-period-total]", count: 0
    assert_select "[data-lifetime-total][data-value='1045']", count: 1
    assert_select "[data-lifetime-input][data-value='942']"
    assert_select "[data-lifetime-output][data-value='103']"
    assert_select "[data-usage-day='#{cutoff.to_date.iso8601}']", count: 0
    assert_select "[data-usage-day='#{(@report_time + 40.days).to_date.iso8601}'] td[data-value='5']"
    assert_equal 45, css_select("[data-usage-day] td").sum { |cell| cell["data-value"].to_i }
    assert_select "[data-usage-window]", count: 0
    assert_select "[data-usage-bucket-dates]", text: /#{Regexp.escape(I18n.l((@report_time + 40.days).to_date, format: :short))}/

    dashboard_usage(:dashboard_second_member).update_columns(created_at: cutoff + 1.second)
    get account_token_usage_path(@second)
    assert_select "[data-usage-day='#{cutoff.to_date.iso8601}'] td[data-value='1000']"
    assert_equal 1045, css_select("[data-usage-day] td").sum { |cell| cell["data-value"].to_i }
  end

  test "scoped reads do not change stored counters content or enqueue work" do
    counts = [ Chat.count, Message.count, Prompt.count, TokenUsage.count, Document.count, Text.count, Qna.count, Website.count ]
    before = @second.reload.attributes
    usages = @second.token_usages.order(:id).map(&:attributes)
    assert_no_enqueued_jobs { get account_token_usage_path(@second) }
    assert_response :success
    assert_equal before, @second.reload.attributes
    assert_equal usages, @second.token_usages.order(:id).map(&:attributes)
    assert_equal counts, [ Chat.count, Message.count, Prompt.count, TokenUsage.count, Document.count, Text.count, Qna.count, Website.count ]
    assert_equal @first, @user.reload.first_account
  end

  test "no recent activity does not erase lifetime counters or breakdowns" do
    TokenUsage.where(account_id: @user.accounts.select(:id)).update_all(created_at: @report_time - 60.days)
    get token_usage_path
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='1065']"
    assert_select "[data-usage-model]", count: 1
    assert_select "[data-usage-no-recent]", count: 1
    get account_token_usage_path(@second)
    assert_select "[data-lifetime-total][data-value='1045']"
    assert_select "[data-usage-no-recent]", count: 1
    assert_select "[data-usage-day]", count: 0
  end

  test "zero states keep estimates honest and methodology complete in both locales" do
    %i[en fr].each do |locale|
      get account_token_usage_path(@empty), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "[data-lifetime-total][data-value='0']"
      assert_select "[data-usage-no-recent]"
      assert_select "[data-usage-fallback]", count: 0
      assert_select "[data-usage-model]", count: 0
      assert_select "[data-usage-models] li, [data-usage-kinds] li", text: I18n.t("nosia.usage.none", locale: locale), count: 2
      assert_select "[data-usage-estimate-caveat]", text: I18n.t("nosia.usage_workspace.estimate_caveat", locale: locale)
      assert_select "[data-usage-methodology] summary", text: I18n.t("nosia.usage.methodology_question", locale: locale)
      assert_select "[data-usage-methodology] strong", text: "ISO 14044"
      assert_select "[data-usage-methodology] code", text: "N/A"
      assert_select "[data-usage-methodology]", text: /Etalab 2\.0/
      assert_select "[data-usage-methodology]", text: /#{Regexp.escape(I18n.l(Date.new(2026, 7, 2), format: :dataset_snapshot, locale: locale))}/
      [ "https://ecologits.ai", "https://comparia.beta.gouv.fr", "https://comparia.beta.gouv.fr/ranking" ].each do |url|
        assert_select "[data-usage-methodology] a[href='#{url}'][rel='noopener'][target='_blank']"
      end
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "malformed and revoked explicit accounts never become another report" do
    get "/accounts/not-an-account/token_usage", params: { account_id: @second.id }
    assert_response :not_found
    experience(:account_users, :overview_owner_second).destroy!
    get account_token_usage_path(@second), params: { account_id: @first.id }
    assert_response :not_found
    get token_usage_path
    assert_select "[data-period-total][data-value='12']"
    assert_select "[data-lifetime-total][data-value='20']"
  end

  test "report query failures are not successful zero reports" do
    failure = ->(_name, _start, _finish, _id, payload) do
      if payload[:sql].match?(/\ASELECT/i) && payload[:sql].include?('"token_usages"')
        raise ActiveRecord::StatementInvalid, "Token usage query failure probe"
      end
    end
    [ token_usage_path, account_token_usage_path(@second) ].each do |path|
      error = assert_raises(ActiveRecord::StatementInvalid, ActionView::Template::Error) do
        ActiveSupport::Notifications.subscribed(failure, "sql.active_record") { get path }
      end
      assert_match(/Token usage query failure probe/, error.message)
    end
  end
end
```

The failure probe is a scoped notification subscriber removed by the framework's block ensure, not a permanent monkey patch or real database outage. Keep these tests single-worker. Existing controller tests retain ordinary-member and ambient-tenant coverage.

Also create this explicit-input content test before its partials. These are view
contract samples, not new reporting fixtures or fake application evidence:

```ruby
# test/helpers/token_usage_workspace_content_test.rb
require "test_helper"

class TokenUsageWorkspaceContentTest < ActionView::TestCase
  test "nonfallback environmental estimates retain precision without inventing fallback" do
    %i[en fr].each do |locale|
      html = I18n.with_locale(locale) do
        ApplicationController.render(partial: "token_usages/estimates", locals: {
          green_summary: { kwh: 0.1234567, co2e_g: 12.345, fallback_used: false }
        })
      end
      fragment = Nokogiri::HTML.fragment(html)
      assert_select fragment, "[data-usage-energy]", text: locale == :fr ? "0,123457" : "0.123457"
      assert_select fragment, "p", text: locale == :fr ? "kWh · 12,35 gCO₂e" : "kWh · 12.35 gCO₂e"
      assert_select fragment, "[data-usage-fallback]", count: 0
      assert_select fragment, "[data-usage-estimate-caveat]", text: I18n.t("nosia.usage_workspace.estimate_caveat", locale: locale)
    end
  end

  test "all five supplied models keep exact counts energy and actual fallback flags" do
    models = 5.times.map do |index|
      { model_id: index.zero? ? "<script>Long model</script>" : "model-#{index}",
        tokens: 1234 + index, kwh: 0.1234567 + index, fallback: index == 2 }
    end
    %i[en fr].each do |locale|
      html = I18n.with_locale(locale) do
        ApplicationController.render(partial: "token_usages/breakdowns", locals: {
          green_summary: { models: models }, tokens_by_kind: { "completion" => 1, "embedding" => 2, "agent_skill" => 0 }
        })
      end
      fragment = Nokogiri::HTML.fragment(html)
      assert_select fragment, "[data-usage-model]", count: 5
      assert_select fragment, "[data-usage-kind]", count: 3
      assert_select fragment, "[data-usage-model-fallback]", count: 1
      assert_select fragment, "script", count: 0
      fragment.css("[data-usage-model]").zip(models).each do |row, model|
        assert_equal model[:model_id], row["data-usage-model"]
        assert_equal model[:tokens], row["data-value"].to_i
        formatted = I18n.with_locale(locale) { number_with_delimiter(model[:tokens]) }
        energy = I18n.with_locale(locale) { number_with_precision(model[:kwh], precision: 6) }
        assert_includes row.text, formatted
        assert_includes row.text, "#{energy} kWh#{model[:fallback] ? '*' : ''}"
      end
      fragment.css("[style]").each { |element| assert_match(/\Awidth: \d+%\z/, element["style"]) }
    end
  end

  test "new metrics preserve exact localized values and native plural units without a session" do
    %i[en fr].each do |locale|
      [ 0, 1, 2, 9_123_456_789_012 ].each do |count|
        html = I18n.with_locale(locale) do
          ApplicationController.render(partial: "token_usages/metrics", locals: {
            totals: { input: count, output: 0, total: count }, prefix: "lifetime"
          })
        end
        fragment = Nokogiri::HTML.fragment(html)
        formatted = I18n.with_locale(locale) { number_with_delimiter(count) }
        assert_select fragment, "[data-lifetime-total][data-value='#{count}']", text: formatted
        assert_select fragment, "[data-lifetime-input][data-value='#{count}']", text: formatted
        assert_select fragment, "[data-lifetime-output][data-value='0']", text: "0"
        assert_select fragment, "dd", text: I18n.t("nosia.usage.token_unit", locale: locale, count: count), minimum: 2
      end
    end
  end
end
```

- [x] **Step 2: Run RED.**

```bash
record_check /tmp/opencode/token-usage-task3-red.log rails_test test test/controllers/token_usage_workspace_test.rb test/helpers/token_usage_workspace_content_test.rb
```

Expected: missing semantic metrics, account daily table/future bucket, explicit estimate/fallback metadata and methodology marker. Existing passing characterization cases are not relabeled RED.

- [x] **Step 3: Create the metrics and estimates components.** Exact formatting uses existing locale helpers; no compact K/M values, estimation recalculation or changed precision.

```erb
<%# app/views/token_usages/_metrics.html.erb %>
<%# locals: (totals:, prefix:) %>
<dl class="n-usage-metrics">
  <% [:total, :input, :output].each do |kind| %>
    <div class="n-usage-stat">
      <dt class="n-workspace-help"><%= t("nosia.usage.#{kind}") %></dt>
      <%= tag.dd number_with_delimiter(totals.fetch(kind)), class: kind == :total ? "n-usage-number n-usage-primary-number" : "n-usage-number", data: { "#{prefix}_#{kind}" => true, value: totals.fetch(kind) } %>
      <dd class="n-workspace-help"><%= t("nosia.usage.token_unit", count: totals.fetch(kind)) %></dd>
    </div>
  <% end %>
</dl>
```

```erb
<%# app/views/token_usages/_estimates.html.erb %>
<%# locals: (green_summary:) %>
<section class="n-workspace-panel" aria-labelledby="usage-estimates-title">
  <h2 id="usage-estimates-title" class="n-workspace-section-title"><%= t("nosia.usage_workspace.estimates") %></h2>
  <p class="n-workspace-help"><%= t("nosia.usage_workspace.lifetime") %></p>
  <p class="n-workspace-help"><%= t("nosia.usage.energy") %></p>
  <p class="n-usage-number" data-usage-energy data-value="<%= green_summary[:kwh] %>"><%= number_with_precision(green_summary[:kwh], precision: 6) %></p>
  <p class="n-workspace-help">kWh · <%= number_with_precision(green_summary[:co2e_g], precision: 2) %> gCO₂e</p>
  <p class="n-workspace-help" data-usage-estimate-caveat><%= t("nosia.usage_workspace.estimate_caveat") %></p>
  <% if green_summary[:fallback_used] %><p class="n-workspace-help" data-usage-fallback><%= t("nosia.usage.fallback_note") %></p><% end %>
</section>
```

- [x] **Step 4: Create the full breakdown partial.** Ratios are only decorative widths from existing counts. All supplied rows are retained; text carries the exact values. Preserve the existing asterisk as well as adding its readable fallback label.

```erb
<%# app/views/token_usages/_breakdowns.html.erb %>
<%# locals: (green_summary:, tokens_by_kind:) %>
<% max_model = green_summary[:models].map { |entry| entry[:tokens] }.max.to_f; max_kind = tokens_by_kind.values.max.to_f %>
<section class="n-workspace-panel" aria-labelledby="usage-breakdowns-title">
  <h2 id="usage-breakdowns-title" class="n-workspace-section-title"><%= t("nosia.usage_workspace.lifetime_breakdowns") %></h2>
  <div class="n-usage-breakdowns">
    <section aria-labelledby="usage-models-title" data-usage-models>
      <h3 id="usage-models-title"><%= t("nosia.usage.per_model") %></h3>
      <ul class="!list-none">
        <% green_summary[:models].each do |entry| %>
          <li data-usage-model="<%= entry[:model_id] %>" data-value="<%= entry[:tokens] %>">
            <div class="n-usage-row"><span><%= entry[:model_id] %></span><span><%= t("nosia.usage.token_quantity", count: entry[:tokens], formatted_count: number_with_delimiter(entry[:tokens])) %></span></div>
            <div class="n-usage-bar" aria-hidden="true"><div style="width: <%= max_model.zero? ? 0 : (entry[:tokens].to_f / max_model * 100).round %>%"></div></div>
            <p class="n-workspace-help"><%= number_with_precision(entry[:kwh], precision: 6) %> kWh<%= entry[:fallback] ? "*" : "" %></p>
            <% if entry[:fallback] %><p class="n-workspace-help" data-usage-model-fallback><%= t("nosia.usage_workspace.fallback") %></p><% end %>
          </li>
        <% end %>
        <% if green_summary[:models].empty? %><li class="n-workspace-help"><%= t("nosia.usage.none") %></li><% end %>
      </ul>
    </section>
    <section aria-labelledby="usage-kinds-title" data-usage-kinds>
      <h3 id="usage-kinds-title"><%= t("nosia.usage.per_kind") %></h3>
      <ul class="!list-none">
        <% tokens_by_kind.each do |kind, tokens| %>
          <li data-usage-kind="<%= kind %>" data-value="<%= tokens %>">
            <div class="n-usage-row"><span class="capitalize"><%= t("nosia.usage.kinds.#{kind}") %></span><span><%= t("nosia.usage.token_quantity", count: tokens, formatted_count: number_with_delimiter(tokens)) %></span></div>
            <div class="n-usage-bar" aria-hidden="true"><div style="width: <%= max_kind.zero? ? 0 : (tokens.to_f / max_kind * 100).round %>%"></div></div>
          </li>
        <% end %>
        <% if tokens_by_kind.empty? %><li class="n-workspace-help"><%= t("nosia.usage.none") %></li><% end %>
      </ul>
    </section>
  </div>
</section>
```

- [x] **Step 5: Create the report-only methodology wrapper, retaining every existing text key/link/snapshot.** Native summary marker replaces structural icons. Shared translation content remains the authoritative methodology, including caveats rather than rewriting scientific claims.

```erb
<%# app/views/token_usages/_methodology.html.erb %>
<details class="n-workspace-panel n-usage-disclosure" data-usage-methodology>
  <summary><%= t("nosia.usage.methodology_question") %></summary>
  <div class="n-usage-methodology-content">
    <p><%= t("nosia.usage.methodology_intro_html", ecologits: link_to("Ecologits", "https://ecologits.ai", target: "_blank", rel: "noopener", class: "n-workspace-link"), comparia: link_to("compar:IA", "https://comparia.beta.gouv.fr", target: "_blank", rel: "noopener", class: "n-workspace-link")) %></p>
    <p><%= t("nosia.usage.methodology_lifecycle_html") %></p>
    <p><%= t("nosia.usage.methodology_measurement_html") %></p>
    <p><%= t("nosia.usage.methodology_caveat") %></p>
    <section aria-labelledby="usage-data-source-title">
      <h2 id="usage-data-source-title" class="n-workspace-section-title"><%= t("nosia.usage.data_source") %></h2>
      <p><%= t("nosia.usage.dataset_source_html", dataset: link_to(t("nosia.usage.dataset_name"), "https://comparia.beta.gouv.fr/ranking", target: "_blank", rel: "noopener", class: "n-workspace-link"), date: l(Date.new(2026, 7, 2), format: :dataset_snapshot)) %></p>
      <p><%= t("nosia.usage.dataset_fallback_html") %></p>
    </section>
  </div>
</details>
```

- [x] **Step 6: Create the uncached workspace composition.** Its DOM reading order is main overview/trend → rail → lifetime breakdowns → methodology; the desktop layout does not change that order.

```erb
<%# app/views/token_usages/_workspace.html.erb %>
<%# locals: (account:, headline:, lifetime:, green_summary:, tokens_by_kind:, daily_totals:, starts_at: nil, ends_at: nil) %>
<div class="n-usage-top">
  <div class="n-usage-main">
    <section class="n-workspace-panel" aria-labelledby="usage-overview-title">
      <h2 id="usage-overview-title" class="n-workspace-section-title"><%= t("nosia.usage_workspace.overview") %></h2>
      <p class="n-workspace-help"><%= t(account ? "nosia.usage_workspace.lifetime" : "nosia.usage.last_30_days") %></p>
      <%= render "token_usages/metrics", totals: headline, prefix: account ? "lifetime" : "period" %>
    </section>
    <%= render "token_usages/activity", daily_totals: daily_totals, scoped: account.present?, starts_at: starts_at, ends_at: ends_at %>
  </div>
  <aside class="n-usage-rail" aria-label="<%= t('nosia.usage_workspace.context') %>">
    <% if account %>
      <section class="n-workspace-panel"><h2 class="n-workspace-section-title"><%= t("nosia.usage_workspace.context") %></h2><p class="n-workspace-help"><%= t("nosia.usage_workspace.account_scope") %></p></section>
    <% else %>
      <section id="global-lifetime-summary" class="n-workspace-panel" aria-labelledby="global-lifetime-title">
        <h2 id="global-lifetime-title" class="n-workspace-section-title"><%= t("nosia.dashboard.lifetime_details") %></h2>
        <%= render "token_usages/metrics", totals: lifetime, prefix: "lifetime" %>
      </section>
    <% end %>
    <%= render "token_usages/estimates", green_summary: green_summary %>
  </aside>
</div>
<%= render "token_usages/breakdowns", green_summary: green_summary, tokens_by_kind: tokens_by_kind %>
<%= render "token_usages/methodology" %>
```

In `show.html.erb`, retain the header, scope paragraph and no-memberships block from Task 1. Replace its old `if @report` report body and trailing transparency render with this block (the outer workspace closing div remains):

```erb
<% if @report %>
  <%= render "workspace", account: nil, headline: @report.period_totals, lifetime: @report.lifetime_totals, green_summary: @report.green_summary, tokens_by_kind: @report.tokens_by_kind, daily_totals: @report.daily_totals, starts_at: @report.starts_at, ends_at: @report.ends_at %>
<% else %>
  <% lifetime = @token_totals.merge(total: @token_totals.fetch(:input) + @token_totals.fetch(:output)) %>
  <%= render "workspace", account: @usage_account, headline: lifetime, lifetime: lifetime, green_summary: @green_summary, tokens_by_kind: @tokens_by_kind, daily_totals: usage_display_days(@tokens_by_day) %>
<% end %>
```

The one addition above is display of the existing lifetime input+output total, not a new recent-period account calculation. No controller edit is needed.

- [x] **Step 7: Adapt legacy selectors precisely, retaining their expected quantities.** These are presentation updates, not permission to delete failing tests. Leave direct `_summary` rendering tests unchanged.

In `test/controllers/global_token_usage_test.rb`, use these replacements:

```ruby
assert_select "#global-lifetime-summary [data-lifetime-input][data-value='959']"
assert_select "#global-lifetime-summary [data-lifetime-output][data-value='106']"
# Account route assertions:
assert_select "[data-lifetime-input][data-value='942']"
assert_select "[data-lifetime-output][data-value='103']"
```

In `test/controllers/accounts/scoped_tokens_usage_test.rb`, replace **only request-response** `section p` selectors using the following full mapping; retain the final direct-render test's `assert_select fragment, "section p"` lines:

```ruby
# Replace these literal lines at all request-response occurrences:
assert_select "[data-lifetime-input][data-value='900']"
assert_select "[data-lifetime-output][data-value='100']"
assert_select "#global-lifetime-summary [data-lifetime-input][data-value='910']"
assert_select "#global-lifetime-summary [data-lifetime-output][data-value='102']"
assert_select "[data-lifetime-input][data-value='901']"
assert_select "[data-lifetime-output][data-value='101']"
assert_select "#global-lifetime-summary [data-lifetime-input][data-value='911']"
assert_select "#global-lifetime-summary [data-lifetime-output][data-value='103']"
# In the cached-path loop, replace its two section-p assertions with:
assert_select "[data-lifetime-input][data-value='#{input}']"
assert_select "[data-lifetime-output][data-value='#{output}']"
```

Keep the scoped `section li` quantity assertion and all raw cache restoration/default-account/authorization assertions. In `test/integration/localized_pages_test.rb`, the French report's old visible fallback sentence now appears in `[data-usage-fallback]` with the exact same text; its per-model precision assertion still matches `kWh*`. Its legacy unit/standalone summary test is unchanged. No additional assertion update is required there.

In `test/system/dashboard_test.rb`, replace only its three report-page `.n-dashboard-daily-data` selectors after `visit token_usage_path(account_id: @second.id)`:

```ruby
find("[data-usage-daily] summary").click
assert_selector "[data-usage-daily] tbody tr", count: 30
assert_equal 1057, all("[data-usage-daily] tbody td").sum { |cell| cell["data-value"].to_i }
```

All dashboard-page selectors/values, shortcut links, composer and layout checks stay unchanged.

- [x] **Step 8: Run GREEN and commit the report composition.**

```bash
record_check /tmp/opencode/token-usage-task3-green.log rails_test test test/controllers/token_usage_workspace_test.rb test/controllers/token_usage_workspace_shell_test.rb test/helpers/token_usage_activity_test.rb test/helpers/token_usage_workspace_content_test.rb test/helpers/token_usages_helper_test.rb test/models/token_usage/report_test.rb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/dashboards_controller_test.rb test/controllers/account_experience_test.rb test/integration/token_usages_test.rb test/integration/localized_pages_test.rb test/integration/localized_cache_test.rb test/integration/token_summary_cache_test.rb test/integration/token_footer_test.rb test/internationalization/catalogs_test.rb
git diff --check
git add app/views/token_usages/show.html.erb app/views/token_usages/_workspace.html.erb app/views/token_usages/_metrics.html.erb app/views/token_usages/_estimates.html.erb app/views/token_usages/_breakdowns.html.erb app/views/token_usages/_methodology.html.erb test/controllers/token_usage_workspace_test.rb test/helpers/token_usage_workspace_content_test.rb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/system/dashboard_test.rb
git commit -m "feat(usage): Compose exact overview and lifetime report details"
```

Expected: all focused tests pass, including existing global local-zone/endpoints/counter-drift tests, scoped member/ambient-tenant tests, numeric style safety and complete methodology assertions.

## Task 4: Isolated lifetime fragments and independently fresh activity

**Create:** `test/integration/token_usage_workspace_cache_test.rb`.
**Modify:** `app/helpers/token_usages_helper.rb`, `app/views/token_usages/_workspace.html.erb`.

**Historical-snippet correction:** the execution record explicitly supersedes
Step 4's proposed `cache(..., skip:)` with supported `cache_unless` wrappers.
Those original snippets are retained only to explain the failed attempt.

- [x] **Step 1: Add the cache regression suite before adding fragment blocks.** Real MemoryStore, real requests, restored controller/Rails stores; no providers or jobs.

```ruby
# test/integration/token_usage_workspace_cache_test.rb
require "test_helper"
require_relative "../support/dashboard_fixtures"

class TokenUsageWorkspaceCacheTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
    @previous_cache = Rails.cache
    @previous_store = ActionController::Base.cache_store
    @previous_caching = ActionController::Base.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = Rails.cache
    ActionController::Base.perform_caching = true
  end

  teardown do
    Rails.cache = @previous_cache
    ActionController::Base.cache_store = @previous_store
    ActionController::Base.perform_caching = @previous_caching
    travel_back
  end

  test "scoped lifetime fragments hit but activity buckets refresh with unchanged counters" do
    get account_token_usage_path(@second)
    hits = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      hits << payload[:key] if payload[:hit] && payload[:key].to_s.include?("usage-workspace-v1")
    end
    dashboard_usage(:dashboard_indexing).update_columns(created_at: @report_time - 60.days)
    ActiveSupport::Notifications.subscribed(subscriber, "cache_read.active_support") do
      get account_token_usage_path(@second)
    end
    assert_response :success
    assert_operator hits.length, :>=, 3
    assert_select "[data-lifetime-total][data-value='1045']"
    assert_select "[data-usage-kind='embedding'][data-value='40']"
    assert_select "[data-usage-day='2026-10-20']", count: 0
    assert_equal 1005, css_select("[data-usage-day] td").sum { |cell| cell["data-value"].to_i }
  end

  test "rolling activity and global date labels move without counter changes" do
    get account_token_usage_path(@second)
    get token_usage_path
    original_window = css_select("[data-usage-window]").first.text
    travel_to @report_time + 31.days
    get account_token_usage_path(@second)
    assert_select "[data-usage-day]", count: 0
    assert_select "[data-usage-no-recent]"
    assert_select "[data-lifetime-total][data-value='1045']"
    get token_usage_path
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='1065']"
    refute_equal original_window, css_select("[data-usage-window]").first.text
    assert_equal (@report_time + 31.days).to_date.iso8601, css_select("[data-usage-day]").last["data-usage-day"]
  end

  test "account locale and counter identities remain isolated and global reports never use these fragments" do
    [ [ @first, 20 ], [ @second, 1045 ] ].each do |account, total|
      %i[en fr].each do |locale|
        get account_token_usage_path(account), headers: { "Accept-Language" => locale.to_s }
        assert_select "[data-lifetime-total][data-value='#{total}']"
        assert_select "[data-usage-estimate-caveat]", text: I18n.t("nosia.usage_workspace.estimate_caveat", locale: locale)
      end
    end
    before = @second.reload.updated_at
    @second.update_columns(input_tokens_count: 943, output_tokens_count: 104)
    assert_equal before, @second.reload.updated_at
    get account_token_usage_path(@second)
    assert_select "[data-lifetime-total][data-value='1047']"
    reads = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      reads << payload[:key] if payload[:key].to_s.include?("usage-workspace-v1")
    end
    ActiveSupport::Notifications.subscribed(subscriber, "cache_read.active_support") { get token_usage_path }
    assert_empty reads
    assert_select "[data-lifetime-total][data-value='1067']"
    assert_select "[data-period-total][data-value='1057']"
    experience(:account_users, :overview_owner_second).destroy!
    get account_token_usage_path(@second)
    assert_response :not_found
  end
end
```

- [x] **Step 2: Run RED.**

```bash
record_check /tmp/opencode/token-usage-task4-red.log rails_test test test/integration/token_usage_workspace_cache_test.rb
```

Expected: the cache-hit assertion fails because Task 3 deliberately has no lifetime fragments; the existing freshness assertions may already pass. Do not count that as a stale-window regression reproduction. The suite permanently protects against later caching the entire report.

- [x] **Step 3: Add the documented explicit-account cache key.** Before the existing numeric helper:

```ruby
  # @param account [Account, nil] Already-authorized scoped account; nil is uncached global
  # @param section [String] Headline, estimates or breakdowns presentation identity
  # @return [Array] Locale/account/counter/version identity, never a recent-window key
  def usage_lifetime_cache_key(account, section)
    [ "usage-workspace-v1", I18n.locale, account, account&.input_tokens_count,
      account&.output_tokens_count, section ]
  end
```

- [x] **Step 4: Wrap exactly these three existing render statements in `_workspace.html.erb`.** Global skips **every** cache read/write; activity/dates remain outside all three blocks. The separate global lifetime metrics render is also left uncached.

```erb
<% cache usage_lifetime_cache_key(account, "headline"), skip: account.nil? do %>
  <%= render "token_usages/metrics", totals: headline, prefix: account ? "lifetime" : "period" %>
<% end %>
```

```erb
<% cache usage_lifetime_cache_key(account, "estimates"), skip: account.nil? do %>
  <%= render "token_usages/estimates", green_summary: green_summary %>
<% end %>
```

```erb
<% cache usage_lifetime_cache_key(account, "breakdowns"), skip: account.nil? do %>
  <%= render "token_usages/breakdowns", green_summary: green_summary, tokens_by_kind: tokens_by_kind %>
<% end %>
```

This preserves the current lifetime invalidation policy; it does not promise to repair estimator freshness after out-of-band ledger edits with unchanged counters. The recent series **does** refresh independently in that scenario.

- [x] **Step 5: Run GREEN and commit.**

```bash
record_check /tmp/opencode/token-usage-task4-green.log rails_test test test/integration/token_usage_workspace_cache_test.rb test/integration/token_summary_cache_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/global_token_usage_test.rb test/controllers/token_usage_workspace_test.rb test/controllers/token_usage_workspace_shell_test.rb test/integration/localized_pages_test.rb
git diff --check
git add app/helpers/token_usages_helper.rb app/views/token_usages/_workspace.html.erb test/integration/token_usage_workspace_cache_test.rb
git commit -m "fix(usage): Keep activity outside lifetime-only fragments"
```

Expected: three or more scoped lifetime hits on the repeat request, fresh recent output, isolated locales/accounts and zero global lifetime-fragment reads.

## Task 5: Browser-first responsive layout, keyboard and measured contrast

**Create:** `test/system/token_usage_workspace_test.rb`, `app/assets/stylesheets/nosia/usage_workspace.css`.
**Modify:** `app/assets/tailwind/application.css`. No JavaScript or shared design-system edits.

**Historical-sample correction:** the execution record supersedes the persistent
9e12 counter/derived-total sample below with parent-approved int32-safe counters,
and records the final scoped link-margin/autoscroll correction. The pure-view
large-number test remains unchanged; no schema or assertion was weakened.

- [x] **Step 1: Add the browser suite before report-specific CSS.** Use these complete tests and helpers in one file. Browser data mutations are test-only arrangements; reads must still enqueue no jobs. Evidence is written under a new process directory, not committed.

```ruby
# test/system/token_usage_workspace_test.rb
require "application_system_test_case"
require_relative "../support/dashboard_fixtures"

class TokenUsageWorkspaceSystemTest < ApplicationSystemTestCase
  include DashboardFixtures

  setup do
    travel_to @report_time
    @original_window_size = page.current_window.size
    @evidence_dir = "/tmp/opencode/token-usage-workspace-#{Process.pid}"
    FileUtils.mkdir_p(@evidence_dir)
    puts "Token usage workspace evidence: #{@evidence_dir}"
    sign_in_usage_browser(@user)
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    page.current_window.resize_to(*@original_window_size) if @original_window_size
    travel_back
    Capybara.reset_sessions!
  end

  test "global detail navigation and scoped Back keep their reporting and conversation meanings" do
    visit user_root_path
    within(".n-usage-overview") { click_on "Usage details" }
    assert_current_path token_usage_path
    assert_selector "[data-workspace-scope]", text: "All your accounts"
    assert_selector "[data-period-total][data-value='1057']"
    assert_selector "[data-lifetime-total][data-value='1065']"
    assert_no_selector "#accordion-right-actions, #drawer-right", visible: :all
    focus_usage_by_tab("[data-usage-daily] summary")
    page.send_keys(:enter)
    assert_selector "[data-usage-daily][open]"
    assert_selector "[data-usage-day]", count: 30
    assert_equal 1057, all("[data-usage-day] td").sum { |cell| cell["data-value"].to_i }
    page.send_keys(" ")
    assert_no_selector "[data-usage-daily][open]"
    focus_usage_by_tab("[data-usage-methodology] summary")
    page.send_keys(:enter)
    assert_selector "[data-usage-methodology][open] a", text: "Ecologits"

    visit account_token_usage_path(@second)
    assert_selector "[data-workspace-scope]", text: "Account: #{@second.name}"
    assert_selector "[data-lifetime-total][data-value='1045']", count: 1
    assert_no_selector "[data-period-total]"
    find("[data-workspace-back]").click
    assert_current_path account_path(@second)
    visit token_usage_path
    within(".n-workspace-actions") { click_on "New chat" }
    assert_current_path new_chat_path
    assert_equal @first, @user.reload.first_account
    assert_no_enqueued_jobs
  end

  test "both report scopes fit every required viewport locale and theme with exact large values" do
    @second.update_columns(name: "CompteDeRecherche" * 12, input_tokens_count: 9_123_456_789_012, output_tokens_count: 234_567_890_123)
    TokenUsage.where(account_id: @second.id).where.not(model_id: nil).update_all(model_id: "long-model-identifier/" * 12)
    states = []
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang='#{locale}']", visible: :all
      { global: token_usage_path, account: account_token_usage_path(@second) }.each do |scope, path|
        visit path
        [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
          resize_usage_viewport(width, height)
          %w[light dark].each do |theme|
            set_usage_theme(theme)
            assert_selector "[data-usage-workspace] h1", count: 1
            assert_no_text(/translation missing|missing translation/i)
            assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
            assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth + 1")
            assert page.evaluate_script("Array.from(document.querySelectorAll('.n-usage-number')).every(e => e.scrollWidth <= e.clientWidth + 1)")
            columns = page.evaluate_script("getComputedStyle(document.querySelector('.n-usage-top')).gridTemplateColumns").split.length
            assert_equal width >= 1280 ? 2 : 1, columns
            total = scope == :global ? 9_358_024_679_155 : 9_358_024_679_135
            assert_selector "[data-lifetime-total][data-value='#{total}']", text: I18n.with_locale(locale) { ActiveSupport::NumberHelper.number_to_delimited(total) }
            assert_selector "[data-usage-model]", text: "long-model-identifier/" * 12
            page.execute_script("document.querySelectorAll('[data-usage-daily], [data-usage-methodology]').forEach(e=>e.open=false)")
            focus_usage_by_tab("[data-usage-daily] summary")
            assert_usage_focus_visible
            page.send_keys(:enter)
            assert_selector "[data-usage-daily][open]"
            focus_usage_by_tab("[data-usage-methodology] summary")
            assert_usage_focus_visible
            page.send_keys(:enter)
            assert_selector "[data-usage-methodology][open]"
            measure_usage_contrast
            page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
            save_usage_screenshot("#{locale}-#{scope}-#{width}-#{height}-#{theme}-overview")
            focus_usage_by_tab("[data-usage-methodology] a[href='https://comparia.beta.gouv.fr/ranking']")
            assert_usage_focus_visible
            save_usage_screenshot("#{locale}-#{scope}-#{width}-#{height}-#{theme}-methodology")
            states << { locale: locale, scope: scope, viewport: page.evaluate_script("[innerWidth,innerHeight]"), theme: theme }
          end
        end
      end
    end
    File.write("#{@evidence_dir}/matrix.json", { states: states, native_200_percent_zoom: "UNVERIFIED" }.to_json)
    assert_equal 32, states.length
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    assert page.evaluate_script("Array.from(document.querySelectorAll('[data-usage-workspace] a, [data-usage-workspace] summary')).every(e => getComputedStyle(e).transitionDuration.split(',').every(v => parseFloat(v) === 0))")
    assert_no_enqueued_jobs
  end

  test "zero no-membership and lifetime-without-recent states remain readable in both themes" do
    resize_usage_viewport(375, 812)
    TokenUsage.where(account_id: @user.accounts.select(:id)).update_all(created_at: @report_time - 60.days)
    [ [ "global-lifetime", token_usage_path, "1065" ], [ "account-lifetime", account_token_usage_path(@second), "1045" ], [ "empty-account", account_token_usage_path(@empty), "0" ] ].each do |name, path, lifetime|
      visit path
      assert_selector "[data-lifetime-total][data-value='#{lifetime}']"
      assert_selector "[data-usage-no-recent]"
      %w[light dark].each do |theme|
        set_usage_theme(theme)
        save_usage_screenshot("375-#{name}-#{theme}")
      end
    end
    Capybara.reset_sessions!
    sign_in_usage_browser(experience(:users, :overview_no_account))
    visit token_usage_path
    assert_selector "[data-period-total][data-value='0']"
    assert_selector "[data-lifetime-total][data-value='0']"
    assert_selector "[data-usage-no-memberships] a[href='#{accounts_path}']"
    assert_no_selector "[data-usage-fallback]"
    %w[light dark].each do |theme|
      set_usage_theme(theme)
      save_usage_screenshot("375-no-memberships-#{theme}")
    end
    assert_no_enqueued_jobs
  end

  private
    def sign_in_usage_browser(user)
      visit root_url
      fill_in "email", with: user.email
      fill_in "password", with: AccountExperienceFixtures::PASSWORD
      click_on "Sign in"
      assert_selector "[data-dashboard]"
    end

    def resize_usage_viewport(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth,innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
    end

    def set_usage_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script(<<~JS)
        const done=arguments[0];
        Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());
      JS
    end

    def focus_usage_by_tab(selector)
      200.times do
        page.send_keys(:tab)
        return if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
      end
      flunk "Keyboard could not reach #{selector}"
    end

    def assert_usage_focus_visible
      sample = page.evaluate_script(<<~JS)
        (()=>{
          const e=document.activeElement,r=e.getBoundingClientRect(),s=getComputedStyle(e),main=document.querySelector('main').getBoundingClientRect();
          const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
          return {text:e.textContent.trim(),height:r.height,outline:parseFloat(s.outlineWidth),visible:r.top>=Math.max(0,main.top)&&r.bottom<=Math.min(innerHeight,main.bottom)&&points.every(([x,y])=>{const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));})};
        })()
      JS
      assert_operator sample.fetch("height"), :>=, 44, sample.to_json
      assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
      assert sample.fetch("visible"), "Focused action is obscured: #{sample}"
    end

    def measure_usage_contrast
      rows = page.evaluate_script(<<~JS)
        (()=>{
          const root=document.querySelector('[data-usage-workspace]'),canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const ancestors=[];for(let a=e;a;a=a.parentElement)ancestors.unshift(a);return ancestors.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured gradient/opacity');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          function visible(e){return e.getClientRects().length>0&&getComputedStyle(e).visibility==='visible';}
          function measure(e,property,minimum,parent=false){const s=getComputedStyle(e),bg=background(parent?e.parentElement:e),fg=blend(rgba(s[property]),bg),a=luminance(fg),b=luminance(bg);return {element:e.tagName,text:e.textContent.trim().slice(0,160),property,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};}
          const selectors=['h1','h2','h3','.n-workspace-help','.n-workspace-scope','.n-usage-number','.n-workspace-link','.n-usage-row span','.n-usage-disclosure summary','.n-usage-disclosure th','.n-usage-disclosure td','.n-usage-methodology-content p','.n-usage-methodology-content strong','.n-usage-methodology-content em','.n-usage-methodology-content code'];
          const rows=selectors.flatMap(selector=>{const elements=Array.from(root.querySelectorAll(selector)).filter(visible);if(!elements.length)throw new Error(`No visible contrast sample: ${selector}`);return elements.map(e=>measure(e,'color',4.5));});
          rows.push(measure(root.querySelector('.n-usage-chart'),'color',3));
          root.querySelectorAll('summary').forEach(e=>rows.push(measure(e,'borderTopColor',3)));
          if(!root.contains(document.activeElement))throw new Error('Missing focused workspace action');
          rows.push(measure(document.activeElement,'outlineColor',3,true));
          return rows;
        })()
      JS
      rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.to_json }
      File.open("#{@evidence_dir}/contrast.jsonl", "a") do |file|
        file.puts({ viewport: page.evaluate_script("[innerWidth,innerHeight]"), locale: page.find("html", visible: :all)["lang"], dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: rows }.to_json)
      end
    end

    def save_usage_screenshot(name)
      page.driver.browser.execute_async_script(<<~JS)
        const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));
      JS
      page.save_screenshot("#{@evidence_dir}/#{name}.png")
    end
end
```

- [x] **Step 2: Run browser RED and inspect the real cause.**

```bash
record_check /tmp/opencode/token-usage-task5-red.log browser_test test/system/token_usage_workspace_test.rb
```

Expected: missing grid columns, oversized/unwrapped chart or absent summary outline/44px target. Some navigation/data tests may already pass. If a test instead fails because of a fixture/locale/browser race, correct the test setup before treating it as CSS evidence. Native `details` interaction is real Enter/Space after Tab traversal; test-only opening/closing resets do not replace that assertion.

- [x] **Step 3: Add the complete report-only CSS.** These values continue the approved neutral/green/system-font foundation. The normal-text target remains 4.5:1 even for large metrics; chart/summary-border/focus targets are 3:1. Browser measurements, not the palette names, decide acceptance.

```css
/* app/assets/stylesheets/nosia/usage_workspace.css */
main:has([data-usage-workspace]) { min-width: 0; scroll-padding-block-end: 7rem; }
.n-usage-workspace .n-usage-top { @apply grid min-w-0 grid-cols-1 items-start gap-6; }
.n-usage-workspace .n-usage-main,
.n-usage-workspace .n-usage-rail { @apply min-w-0 space-y-6; }
.n-usage-workspace .n-workspace-panel { @apply space-y-4; }
.n-usage-workspace .n-usage-metrics { @apply grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-2; }
.n-usage-workspace .n-usage-stat { @apply min-w-0 space-y-1; }
.n-usage-workspace .n-usage-stat:first-child { @apply sm:col-span-2; }
.n-usage-workspace .n-usage-number { overflow-wrap: anywhere; @apply min-w-0 text-2xl font-semibold tabular-nums tracking-tight; }
.n-usage-workspace .n-usage-primary-number { @apply text-3xl sm:text-4xl; }
.n-usage-workspace .n-usage-chart { overflow: visible; @apply block h-28 w-full text-green-700 dark:text-green-300; }
.n-usage-workspace .n-usage-breakdowns { @apply grid min-w-0 grid-cols-1 gap-6 md:grid-cols-2; }
.n-usage-workspace .n-usage-breakdowns section { @apply min-w-0 space-y-4; }
.n-usage-workspace .n-usage-breakdowns h3 { @apply text-sm font-semibold; }
.n-usage-workspace .n-usage-breakdowns ul { @apply space-y-5; }
.n-usage-workspace .n-usage-breakdowns li { @apply min-w-0 space-y-2; }
.n-usage-workspace .n-usage-row { @apply flex min-w-0 flex-wrap items-baseline justify-between gap-x-4 gap-y-1 text-sm; }
.n-usage-workspace .n-usage-row span { overflow-wrap: anywhere; @apply min-w-0 max-w-full; }
.n-usage-workspace .n-usage-bar { @apply h-2 overflow-hidden rounded-full bg-neutral-200 dark:bg-neutral-700; }
.n-usage-workspace .n-usage-bar > div { @apply h-full rounded-full bg-green-700 dark:bg-green-300; }
.n-usage-workspace .n-usage-disclosure { @apply min-w-0; }
.n-usage-workspace .n-usage-disclosure > summary { overflow-wrap: anywhere; @apply min-h-11 cursor-pointer rounded-md border border-neutral-500 px-3 py-3 text-sm font-medium text-neutral-900 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:border-neutral-400 dark:text-neutral-100 dark:focus:outline-green-300; }
.n-usage-workspace .n-usage-disclosure table { @apply mt-4 w-full table-fixed text-left text-sm; }
.n-usage-workspace .n-usage-disclosure th,
.n-usage-workspace .n-usage-disclosure td { overflow-wrap: anywhere; @apply border-b border-neutral-400 px-2 py-3 font-normal dark:border-neutral-500; }
.n-usage-workspace .n-usage-disclosure thead th { @apply font-semibold; }
.n-usage-workspace .n-usage-methodology-content { overflow-wrap: anywhere; @apply space-y-4 pt-4 text-sm leading-relaxed text-neutral-700 dark:text-neutral-200; }
.n-usage-workspace .n-usage-methodology-content section { @apply space-y-3; }
.n-usage-workspace .n-usage-methodology-content code { @apply text-neutral-800 dark:text-neutral-100; }
@media (min-width: 1280px) {
  .n-usage-workspace .n-usage-top { grid-template-columns: minmax(0, 2fr) minmax(18rem, 1fr); }
  .n-usage-workspace .n-usage-rail .n-usage-metrics { @apply grid-cols-1; }
  .n-usage-workspace .n-usage-rail .n-usage-stat:first-child { grid-column: auto; }
}
@media (prefers-reduced-motion: reduce) {
  .n-usage-workspace a,
  .n-usage-workspace summary { transition: none; animation: none; }
}
```

Add exactly one import after the shared workspace/Sources imports in `app/assets/tailwind/application.css`:

```css
@import "../stylesheets/nosia/usage_workspace.css" layer(utilities);
```

- [x] **Step 4: Build, run browser GREEN and preserve protected regressions.**

```bash
record_check /tmp/opencode/token-usage-task5-build.log rails_test tailwindcss:build
record_check /tmp/opencode/token-usage-task5-green.log browser_test test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/account_experience_test.rb test/system/localization_test.rb test/system/sources_workspace_test.rb test/system/sources_dropzone_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
```

Expected: new suite plus existing browser regressions pass. Read logs for counts/exits/evidence path. If CSS needs correction, reproduce the specific failing viewport/theme first, change only the report stylesheet and preserve the failed log. Do not lower contrast/target assertions, truncate data, hide rows, change chart data, or weaken protected-page checks.

- [x] **Step 5: Inspect actual screenshots and record manual boundaries.** Open at minimum the EN global and FR account overview/methodology at 375px in both themes; both route scopes at tablet, desktop and narrow landscape; all three empty/lifetime states and no-membership screenshots in both themes. Confirm exact-number wrapping remains readable, model names are fully visible, disclosure markers/focus are clear, the chart has room and mobile actions are not obscured. Record which files were actually opened and the measured contrast minima from `contrast.jsonl`.

Native 200% browser zoom requires actual native-browser evidence separately. If unavailable, retain **UNVERIFIED** in the evidence/summary; CDP viewport emulation above verifies viewport size only. Do not claim a screen-reader audit, all WCAG compliance or native zoom based on these tests. If manual zoom is performed, record browser/version/OS, both scopes/themes and overlap/scroll results in a separate evidence note; do not overwrite the automated matrix's truthful limitation.

- [x] **Step 6: Commit only the browser tests, import and scoped stylesheet.**

```bash
git diff --check
git add test/system/token_usage_workspace_test.rb app/assets/stylesheets/nosia/usage_workspace.css app/assets/tailwind/application.css
git commit -m "feat(usage): Polish responsive reporting and keyboard access"
```

## Task 6: Document the delivered report and its limits

**Create:** `docs/token-usage-workspace.md`.
**Modify:** `docs/README.md`, `docs/DIAGRAMS.md`.

- [x] **Step 1: Create the report guide with this content.** Documentation describes implemented behavior, not a promise that verification has already succeeded.

```markdown
# Token usage workspace

The existing Token usage routes use the neutral/green workspace shared with
Sources. Reports are read-only and use normal navigation/reload, not live polling.

## Scope and periods

- `/token_usage` aggregates account-wide activity across your current memberships,
  including other members' activity. Its main overview uses the existing 30 local
  calendar dates: midnight 29 days before the reference date through request time,
  inclusive. Future records are excluded. The chart/table have 30 zero-filled days.
- `/accounts/:account_id/token_usage` requires current membership in the URL
  account. Its headline is lifetime input/output account counters. Its separate
  recent activity keeps the existing exclusive `created_at > 30.days.ago` cutoff
  and SQL `DATE(created_at)` grouping, with no added upper bound or zero filling.
  Every returned date bucket is displayed, including future buckets if present.
- Lifetime totals remain account counters, not a ledger recount. Model/type
  breakdowns remain lifetime ledger data; counter drift is not repaired here.
- Query parameters do not change report scope, authorization or the default
  account. Inaccessible/revoked/malformed account context retains the existing 404.

## Reading and navigation

The overview and activity lead. Desktop adds a secondary rail; mobile stacks the
same information without hiding metrics. Global lifetime counters appear in the
rail; account lifetime counters are not duplicated there. Model and usage-type
breakdowns follow, then the complete methodology disclosure.

The static SVG and keyboard-operable daily table use the same chronological data.
Quantities are exact and locale-formatted, not K/M abbreviations. Empty recent
activity does not erase lifetime usage. With no memberships, the global report
still succeeds with zero values and an Accounts link.

The report omits unrelated conversation drawers while retaining shared desktop
and mobile navigation. Scoped Back returns to the account hub. The global desktop
New chat link keeps its generic existing destination; viewing an account report
does not silently select that account for a new conversation.

## Environmental estimates

Energy and CO₂e are estimates, not measured consumption, billing or savings.
Preserve the existing top-five-model plus embedding-energy policy, coefficients,
six-decimal kWh and two-decimal gCO₂e. Actual fallback flags have readable labels
and the existing asterisk explanation; a zero report does not invent fallback.

The full methodology retains Ecologits/compar:IA links, ISO 14044/lifecycle and
measurement caveats, the Comparia dataset/license/snapshot (2 July 2026), and the
fallback explanation. No model-provider request is needed to read a report.

## Freshness and cache boundaries

Scoped lifetime headline/estimate/breakdown fragments use locale, explicit
account, input/output counters and `usage-workspace-v1` section identity. Recent
activity, its table and period/date labels are outside those fragments. Global
report rendering remains uncached. An unchanged counter does not freeze a rolling
activity window; this does not add a repair policy for out-of-band lifetime edits.

The dashboard's shared overview and legacy standalone summary partials are not
redesigned. Reporting queries, estimator algorithms, writes, jobs and permissions
are unchanged. Database failures remain errors, not successful zero reports.

## Verification

Use the dedicated test-database commands and task gates in the
[implementation plan](superpowers/plans/2026-10-25-token-usage-workspace-ui-ux.md).
New request/helper/cache/system tests cover both scopes, distinct periods, all
date buckets, exact values, empty states, content, read-only behavior and cache
isolation. Existing dashboard/Sources/composer/navigation suites remain guards.

The browser matrix exercises English/French, light/dark, 375px, tablet, desktop
and narrow landscape, long names/large values, native keyboard disclosures,
visible focus, measured contrast and fixed-nav clearance. Read the execution
record for actual counts, exits, screenshots opened and accepted baseline issues.
Viewport emulation is not native 200% zoom. Native zoom remains unverified unless
separately recorded, and these checks are not a full assistive-technology audit.

Agent skills and MCP are later independently approved subprojects. No new report
filters, dates, account switchers, quotas, billing, exports or forecasts are added.
```

- [x] **Step 2: Add the guide to the docs index.** After the existing Sources workspace item in `docs/README.md`, add:

```markdown
- [Token usage workspace](token-usage-workspace.md) — global/account reporting periods, overview/detail layout, estimates, accessibility and cache freshness.
```

- [x] **Step 3: Add this diagram before `## RAG Pipeline Flow` in `docs/DIAGRAMS.md`.**

````markdown
## Token Usage Workspace

```text
/token_usage                         /accounts/:account_id/token_usage
current memberships                 current URL-account membership
       |                                         |
30 local dates + lifetime counters  lifetime counters + existing rolling query
       \                                         /
        +-- overview / static trend / daily table --+
        |          secondary context + estimates   |
        +-- lifetime model/type details + method --+

Scoped lifetime fragments: locale + account + counters + version + section
Recent chart/table/date labels: outside lifetime fragments
Dashboard overview: existing independent presentation, unchanged
```

Global and account recent periods deliberately remain different. All supplied
account date buckets are preserved; neither route changes the default account.
See [Token usage workspace](token-usage-workspace.md) for scope and limitations.

````

- [x] **Step 4: Verify local links/whitespace and commit documentation.**

```bash
python3 - <<'PY'
from pathlib import Path
import re
for filename in ("docs/token-usage-workspace.md", "docs/README.md", "docs/DIAGRAMS.md"):
    path = Path(filename)
    for target in re.findall(r'\]\(([^)]+)\)', path.read_text()):
        target = target.split('#', 1)[0]
        if target and '://' not in target and not target.startswith('mailto:'):
            assert (path.parent / target).exists(), (filename, target)
print("Documentation links verified")
PY
git diff --check
git add docs/token-usage-workspace.md docs/README.md docs/DIAGRAMS.md
git commit -m "docs(usage): Explain report scope and freshness boundaries"
```

Expected: links/check pass. This is not a new application-test claim.

## Task 7: Whole-feature verification and review gate

**Files:** Review the entire feature diff against the immutable Task 0 base. Update only this plan's execution record after actual evidence; corrections require their own failing test and narrow fix.

**Recorded log correction:** the original full-run filename in the historical
command block below is the preserved interrupted attempt, not final evidence.
Use the completed `token-usage-final-full-attempt2.log` result in the execution
record; do not overwrite either file. Phase B does not rerun these commands.

- [x] **Step 1: Run the complete focused acceptance set and existing server suite sequentially.**

```bash
record_check /tmp/opencode/token-usage-final-focused.log rails_test test test/controllers/token_usage_workspace_shell_test.rb test/controllers/token_usage_workspace_test.rb test/helpers/token_usage_activity_test.rb test/helpers/token_usage_workspace_content_test.rb test/integration/token_usage_workspace_cache_test.rb test/models/token_usage/report_test.rb test/helpers/token_usages_helper_test.rb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/dashboards_controller_test.rb test/controllers/account_experience_test.rb test/integration/token_summary_cache_test.rb test/integration/token_usages_test.rb test/integration/token_footer_test.rb test/integration/localized_pages_test.rb test/integration/localized_cache_test.rb test/internationalization/catalogs_test.rb
record_check /tmp/opencode/token-usage-final-full.log rails_test test
record_check /tmp/opencode/token-usage-final-build.log rails_test tailwindcss:build
record_check /tmp/opencode/token-usage-final-browser.log browser_test test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/account_experience_test.rb test/system/localization_test.rb test/system/sources_workspace_test.rb test/system/sources_dropzone_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb
record_check /tmp/opencode/token-usage-final-lint.log mise exec ruby@4.0.7 -- bundle exec rubocop app/helpers/token_usages_helper.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/token_usage_workspace_test.rb test/helpers/token_usage_activity_test.rb test/helpers/token_usage_workspace_content_test.rb test/integration/token_usage_workspace_cache_test.rb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/account_experience_test.rb test/integration/token_usages_test.rb test/integration/localized_pages_test.rb test/integration/localized_cache_test.rb test/system/dashboard_test.rb test/system/token_usage_workspace_test.rb
record_check /tmp/opencode/token-usage-final-brakeman.log mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

Expected: focused/browser/build/lint pass. Full/scanner exits are reported exactly and compared against the explicitly accepted fresh Task 0 baseline; even a reproduced accepted exit 1/3 is not called green. Do not skip tests or suppress warnings. Unexpected differences block completion.

- [x] **Step 2: Verify protected bytes, change scope and documentation.** Read the Task 0 base SHA from its evidence file, then use it explicitly in these checks; do not compare only with the last commit.

```bash
python3 - <<'PY'
from pathlib import Path
import re, subprocess
base = Path('/tmp/opencode/token-usage-workspace-base.log').read_text().splitlines()[0].strip()
assert re.fullmatch(r'[0-9a-f]{40}', base), 'Missing immutable execution base'
protected = [
    'app/controllers/token_usages_controller.rb', 'app/models/token_usage/report.rb',
    'app/models/account.rb', 'app/models/token_usage.rb',
    'app/views/token_usages/_overview.html.erb', 'app/views/token_usages/_summary.html.erb',
    'app/views/token_usages/_summary_content.html.erb', 'app/views/token_usages/_transparency.html.erb',
    'app/views/workspaces/_header.html.erb', 'app/assets/stylesheets/nosia/workspace.css',
    'app/controllers/sources', 'app/views/sources', 'app/helpers/sources_workspace_helper.rb',
    'app/javascript', 'config/routes.rb', 'db', 'Gemfile', 'Gemfile.lock', 'test/support', 'test/fixtures'
]
subprocess.run(['git', 'diff', '--exit-code', base, '--', *protected], check=True)
subprocess.run(['git', 'diff', '--check', base], check=True)
subprocess.run(['git', 'diff', '--stat', base], check=True)
print('Protected data/query/dashboard/Sources/dependency boundaries unchanged')
PY
git diff --stat
git status --short
```

Inspect the whole feature's `git diff <base> --stat` and full diff as well as the working-tree stat. Review CSS selectors, raw HTML interpolation, cache blocks and all legacy assertion edits. Protected byte checks are scope guards, not a substitute for tests. If a protected file genuinely needs a change, stop, explain the evidence and obtain explicit scope approval instead of bypassing the guard.

- [x] **Step 3: Perform final specification and code-quality/security review.** Use `requesting-code-review` and Rails review skills. With Subagent-Driven execution, request independent whole-feature spec and quality reviews against the immutable base; include approved spec/plan, actual diff, task review history, baseline acceptance, test logs, screenshots actually inspected and truthful limitations. With Inline Execution, self-review and request an independent review only if authorized by the applicable skill/user. Fix real findings with RED/GREEN evidence, then rerun affected checks. Never dispatch two implementers into this shared branch/database concurrently.

- [x] **Step 4: Record evidence and completion accurately.** Mark only completed steps, and append an execution record to this plan containing the immutable base/final application SHA, commit per task, test counts/assertions/seeds/exits, user acceptance of specific baseline issues, review outcomes, screenshot paths actually opened, contrast minima by theme and native-zoom status. Keep transient logs/screenshots out of Git; record enough detail to understand the outcome without those files. A documentation-only evidence update may reference the preceding application revision, avoiding a self-referential commit SHA.

```bash
git diff --check
git add docs/superpowers/plans/2026-10-25-token-usage-workspace-ui-ux.md
git commit -m "docs(usage): Record workspace verification and review evidence"
git status --short --branch
```

Expected: clean feature tree. Use `verification-before-completion` before any success claim. Report outcome and exact remaining limitations to the user; do not merge, push, create a PR, remove worktrees or begin Agent skills/MCP without a separate instruction.

## Planning self-review coverage map

This map is for inline plan review, not a claim that execution has occurred.

| Approved requirement | Task/gate |
| --- | --- |
| Global membership scope, lifetime counters versus ledger, local calendar endpoints/zero-filled days, future exclusion | Tasks 0/3/7 run existing `TokenUsage::ReportTest` unchanged; Tasks 1/3 protect global request scope and visible values. |
| Account-wide explicit URL scope, member access, malformed/revoked context, forged query params, ambient tenant/default-account restoration | Tasks 1/3 plus existing scoped tests in Tasks 0/3/4/7. |
| Account lower-bound-only recent query, every returned bucket, future/boundary buckets and no synthesized period total | Task 2 presentation tests; Task 3 account boundary/future request test; protected controller bytes in Task 7. |
| Overview-first desktop main/rail, nonduplicated account lifetime headline, mobile stack and exact localized quantities | Task 3 components/content tests; Task 5 grid/large-value/locale/theme matrix and screenshot inspection. |
| All top-five model/type rows, per-model kWh/true fallback, complete methodology/links/snapshot | Task 3 explicit-input five-row tests, request/legacy locale tests and preserved translation keys; Task 5 expanded-method screenshot/contrast. |
| Genuine zero/no-membership/no-recent-but-lifetime states, successful global no-account path and honest query errors | Tasks 1/3/5; Accounts link/zero metrics remain alongside methodology. |
| Read-only data, no provider calls/jobs/tracking, no routes/schema/dependencies or later-tool work | Task 3 count/counter/job assertions, Task 5 job assertions and Task 7 protected-byte/scope review. |
| Account/locale/counter/version lifetime cache identity, recent/date freshness independent, global uncached | Task 4 repeat-hit, time-travel, out-of-band date, account/locale/counter/revocation and uncached-global checks. |
| Dashboard/Sources isolation, report-only drawers, generic desktop New chat and relevant scoped Back | Task 1 shell plus narrow legacy update; unchanged `_overview`/legacy summaries and protected browsers in Tasks 0/5/7. |
| Static named SVG + daily table, keyboard disclosures, semantic headings, readable units, safe escaping/numeric widths | Tasks 2/3 helper/request/content tests; Task 5 actual keyboard and browser measurement. |
| 375px/tablet/desktop/landscape, EN/FR/light/dark, long values/names, no overflow, focus/44px/contrast/nav clearance/reduced motion | Task 5 complete 32-state matrix, measured contrast, focus hit-testing and screenshot review. |
| Native 200% zoom and evidence limitations, fresh baseline, true exits, reviews and docs | Tasks 0/5/6/7; no emulator/mockup evidence represented as native zoom or application verification. |

## Execution status

Inline planning self-review found no remaining specification gaps. Static-only
checks passed for 14 Ruby snippets, 12 ERB snippets, 20 shell snippets, both YAML
catalogs (17 paired keys), Markdown fences/links, test-file references and the
documentation-only change boundary. These checks do not boot Rails or prove that
the proposed implementation/tests pass. No subagent was dispatched for plan review.

The paragraph above records planning-time facts only. Subsequently the user chose
**1 — Subagent-Driven** and accepted only the exact fresh baseline issues with
**“Yes”**. Tasks 0–7 are complete as documented in the dated execution record;
whole-feature specification and quality reviews, including final evidence, are
approved. This documentation-only evidence commit preserves the tested application
revision. Full suite exit 1 and scanner exit 3 remain accepted nonzero outcomes,
not a clean suite/security scan; native 200% zoom remains **UNVERIFIED**. No merge,
push, PR, cleanup or later-tool work follows without separate authorization.
