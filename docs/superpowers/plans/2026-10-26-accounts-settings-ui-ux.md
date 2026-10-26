# Accounts Navigation and Settings UI/UX Implementation Plan

**Status: execution complete with accepted baseline concerns, not a clean full-suite/security gate.** Tasks 0–4 and Task 5 verification/reviews/record are complete; parent documentation-record re-review, handoff and the user's integration choice remain pending. Application evidence covers the freshly tested revision `bc94c1ed8eee7f958bf969310cd6a25ccf4a3a68`, not this later documentation-only record.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved Accounts breadcrumbs/actions and balanced four-card Settings hub without changing account behavior or redesigning Settings destinations.

**Architecture:** Reuse the shared workspace header/buttons, with an optional breadcrumb-label local that preserves existing consumers. Accounts supplies explicit authorized breadcrumb context; Settings owns static linked cards and narrowly scoped CSS. Extend existing layout guards only for the exact pages in scope, preserving the recently merged Agent skills behavior.

**Tech Stack:** Observed checkout: Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL, Minitest/fixtures, Selenium/Capybara, Turbo/Stimulus, Importmap, Propshaft, Tailwind 4.1.16. Do not alter dependencies to match the generic stack description in AGENTS.md.

## Execution record — 2026-10-26

### Authority, revision and scope

- The user approved the written specification with **“go”**, then selected **“1 — Subagent-driven”** after plan commit `e3c475b`. After fresh Task 0 baselines, the user selected **“Proceed (Recommended)”**, accepting only the exact full/browser/security/JSON issues recorded below for this feature. This did **not** authorize fixing, skipping or suppressing them, or waiving new failures. Limited disk headroom was reported, not represented as an explicit user waiver.
- Immutable feature base: `e3c475b46e58b783c38de8057c6377784696f5ac`. Worktree: `/home/cbldev/gitd/dilolabs/nosia/.worktrees/accounts-settings-ui`; branch: `feat/accounts-settings-ui`.
- Freshly tested revision: **`bc94c1ed8eee7f958bf969310cd6a25ccf4a3a68`**; tree: **`7cbb07600578c6a20accdafb56456e2d18e52fe9`**. Last application/test commit: `9c5f796d64687abe327d02de84ab06c69ce3cc2a`.
- Runtime: Ruby **4.0.7**, Rails **8.0.5.1**, PostgreSQL **18.6**, Tailwind **4.1.16**, Brakeman **8.0.4**, Chromium/ChromeDriver **156.0.8078.47**, Minitest fixtures, single worker, local Selenium/Puma. Every execution shell sourced `/tmp/opencode/accounts-settings-env.sh`. Nondisplaying dotenv loaded the main environment only before fixed test/database/sentinel-key/worker overrides; no main `.env` was read, printed or copied. Database-sharing checks were sequential in the dedicated `nosia_accounts_settings_ui_test` database.
- Before this record, the complete feature diff was exactly **25 allowed files, 642 insertions / 59 deletions**. No controllers/models/auth/routes/dependencies/schema/JavaScript/destination views changed. Shared-header default labels, nested account/form and Skills guards, escaping, 403/404 behavior, read-only routing and default-account preservation were reviewed and tested. This record changes **only this plan**, making 26 feature-diff paths without changing code.

| Task | Actual commit(s) |
| --- | --- |
| 0: isolated baseline / external recorder correction | No application commit |
| 1: Accounts header/actions; review-driven title correction | `7be274895ac8705f3ea0512774424098d69f9ba8`, `5cc21b666347a67990d703519783e62407d2c061` |
| 2: four-card Settings hub | `b73bfda1da469b180f078ec08a3e8d0a0a0dfbfb` |
| 3: scoped styling/browser coverage; review-driven genuine-hover correction | `25c02862bacb41b4eb39070823fa8b10bfaac9b0`, `9c5f796d64687abe327d02de84ab06c69ce3cc2a` |
| 4: navigation guide / documentation links | `bc94c1ed8eee7f958bf969310cd6a25ccf4a3a68` |

### Baseline versus fresh final verification

External evidence root **E** is `/tmp/opencode/accounts-settings-f6n4RE/`; log names in this record are relative to E unless otherwise specified. Every recorded log has a same-stem `.exit` retaining its actual status. Result notation below is **runs/assertions; failures/errors/skips; seed; exit**. Reviews are not tests and are not added to these counts.

| Category | Fresh Task 0 baseline | Fresh final at tested revision |
| --- | --- | --- |
| Focused | 253/15124; 0/0/0; 3761; **0** — `baseline-focused.OGEmjD.log` | 261/15499; 0/0/0; 22112; **0** — `final-focused.CVZ20E.log` |
| Full | 1152/22566; 0/1/0; 27439; **1** — `baseline-full.kHrIDg.log` | 1160/22941; 0/1/0; 21917; **1** — `final-full.dldN1i.log` |
| Browser | 44/18632; 0/6/0; 36679; **1** — `baseline-browser.yyfERE.log` | Combined six files: 47/23986; 0/6/0; 59252; **1** — `final-browser.BcbAho.log` |
| Brakeman | 79 checks, 0 scan errors, 2 high-confidence warnings; **3** — `baseline-security.nAVHxa.log` | 79 checks, 0 scan errors, same 2 warnings; **3** — `final-security.V0OhJA.log` |
| Build | Tailwind build; **0** — `baseline-build.AJB0wp.log` | Tailwind 4.1.16, 197ms; **0** — `final-build.eR9vXt.log` |
| Targeted lint | Not a Task 0 category | 8 files, no offenses; **0** — `final-lint.XCIypV.log` |

The exact six final commands are retained in Task 5 Step 1 below and in **`E/task5-phase-a-qba8uzgs/command-manifest.json`**. That directory also contains `results.json` (commands/logs/counts/seeds/exits/hashes), `support-command-manifest.sh`, `report.md`, `complete-feature.diff`, `source-boundary.json`, `baseline-comparison.json`, `artifact-summary.json` and `final-checkpoint.json`. These are local external evidence, not portable repository attachments. Selected task-level commands/raw paths are in the task reports listed below. No previous redesign evidence substitutes for this final run.

Final supporting raw logs (all exit **0**) are `final-tree-check.VOAQw4.log`, `final-status.2tDfpi.log`, `final-log.EgEhLh.log`, `final-diff-stat.YdkGoS.log`, `final-feature-whitespace.rVnru3.log`, `final-source-artifact-audit.Gmhh03.log`, `final-runtime.CIVFcl.log`, `final-disk.5Vz9FW.log`, `final-browser-version.jmsnN0.log`, `final-driver-version.FHjtcS.log` and `final-return-checkpoint.5OLFmC.log`. Final focused/full/browser runtimes were **72.047241s / 441.663029s / 281.494399s**; Brakeman **1.441690156s**. The final clean checkpoint was 22:11:01 UTC, 1145.054815s after Phase A began.

**Exact accepted issues, still not green:**

- Full: `Chat::RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults` — `NoMethodError: undefined method 'augmented_context'` on the Struct double; `app/models/chat/completionable.rb:39`, called from `test/models/chat/request_options_test.rb:32` (test starts 29).
- Browser: all six are `ProfileManagementTest`, `Capybara::ElementNotFound: Unable to find css "button[type=submit]"` in the language-preference form, from `switch_language` at `test/system/profile_management_test.rb:272` (block starts 270):
  - `test_long_email_and_French_validation_errors_stay_contained_in_the_mobile_scrolling_region` (test 171, call 173).
  - `test_signed_language_preferences_keep_mobile_profile_controls_contained_and_keyboard_accessible_in_both_themes` (test 126, call 130).
  - `test_native_Tab_keeps_every_en_light_mobile_profile_control_fully_above_the_bottom_navigation`.
  - `test_native_Tab_keeps_every_en_dark_mobile_profile_control_fully_above_the_bottom_navigation`.
  - `test_native_Tab_keeps_every_fr_light_mobile_profile_control_fully_above_the_bottom_navigation`.
  - `test_native_Tab_keeps_every_fr_dark_mobile_profile_control_fully_above_the_bottom_navigation` (four generated tests start 147, call 149).
- Brakeman: high-confidence **`PermitAttributes`**, `params.require(:api_token).permit(:account_id, :name)`, `app/controllers/api_tokens_controller.rb:62`; high-confidence **`EOLRails`**, “Support for Rails 8.0.5.1 ended on 2026-10-07”, `Gemfile.lock:318`. Neither warning was suppressed.
- Focused and full each emit **7 JSON duplicate-key warnings**: `tools_cache` twice, `last_test_at` five times; ActiveSupport `encoding.rb:110` / `decoding.rb:25` warn about JSON 3.0 without `allow_duplicate_key: true`.

Final comparison used exact test identities/messages (normalizing only the transient object address for the full error), the complete identical Brakeman warning sections and byte-identical error source files at immutable base/tested HEAD/working tree, **not merely equal counts**. There were no new failures/errors/warnings observed. Affected later Profile assertions did not execute and are not claimed passing. All three new feature browser tests passed within the combined run; per-file assertion totals are not invented.

### TDD and review-driven corrections — selected preserved evidence

All test rows use the notation above; original failed attempts remain intact. Full command arguments and additional diagnostic/build/lint/commit evidence are in `task1-final-report.md`, `task1-title-fix-supplement.md`, `task2-implementation-report-b73bfda.md`, `task3-implementer-report-yw7xuq.md` and `task3-hover-fix-report-d9svw7.md` under E.

| Check | Actual result | Raw log |
| --- | --- | --- |
| Task 1 scoped feature RED before app edits | 5/30; 3/0/0; 32805; **1** | `accounts-red-scoped.sJB9Py.log` |
| Task 1 request GREEN after pagination scope adapter | 187/14069; 0/0/0; 12300; **0** | `accounts-green-scoped.JOJuEn.log` |
| Task 1 exact-title RED before title fix | 5/26; 2/0/0; 49443; **1** | `accounts-title-red.PtsnbQ.log` |
| Task 1 bilingual title/request GREEN | 187/14077; 0/0/0; 35278; **0** | `accounts-title-green.yguXHM.log` |
| Task 2 feature RED | 3/12; 3/0/0; 59680; **1** | `settings-red.DWjiUY.log` |
| Task 2 root/descendant selector probe | 1/17; 0/0/0; 38810; **0** | `settings-selector-probe.GhxQcX.log` |
| Task 2 request GREEN | 52/12084; 0/0/0; 1189; **0** | `settings-green.Cx04iR.log` |
| Task 3 unstyled-card browser RED before CSS | 3/921; 2/0/0; 60112; **1** | `browser-red.3RvPfW.log` |
| Task 3 initial browser GREEN — **not genuine-hover proof** | 3/5180; 0/0/0; 17783; **0** | `browser-green.c8PYpo.log` |
| Task 3 actual-hover regression RED before capability fix | 3/1068; 1/0/0; 10392; **1** | `task3-hover-red.hTtWi5.log` |
| Task 3 genuine-hover browser GREEN | 3/5333; 0/0/0; 5223; **0** | `task3-hover-green.Q8Nwmk.log` |
| Task 3 corrected protected suite — not green | 44/18653; 0/6/0; 15099; **1** | `task3-hover-protected-browser.y50bGc.log` |

Task 4 was prose-only, with static documentation/link/YARD/source-byte checks, **no artificial RED or app reruns**; see `E/task4-documentation-report-bc94c1e.md` and `E/task4-static-checks-20261026-implementer.json` / `.exit`. Final Phase A then freshly verified the complete implementation.

### AUTHORITATIVE PLAN CORRECTIONS

These corrections **supersede the historical snippets below**; checked boxes mean completion as actually corrected and evidenced, not that every original snippet was correct or native zoom was verified.

1. **Task 0 recorder:** the original snippet conflated logfile-open failure with command status and failed to classify a failed final `printf`. The external helper was hardened with a separately opened FD and recorder-error exit **125**, preserving actual command exits in sidecars. Harmless local sentinels passed **11/11 assertions in each of Bash and zsh**; original helper failed 3/11 in each (suite exits 1 versus corrected 0). Evidence: `E/recorder-review-cl8WOv/recorder-supplement-cl8WOv.md`, `recorder-review-cl8WOv/patched-bash-eEZSe1/sentinel-report.log`, `recorder-review-cl8WOv/patched-zsh-Sk3Wy8/sentinel-report.log`, original-shell counterparts, and `recorder-review-cl8WOv/supplemental-integrity.Oa4sC9.log`. All **47 original evidence files** were byte-preserved. This was external-only; no baseline app/build/DB checks were repeated for the recorder correction. Use this actual implementation, not the original Task 0 version:

   ```sh
   record() {
     local label="$1" log result log_fd recorder_result=0
     shift
     log="$(mktemp "$EVIDENCE/$label.XXXXXX.log")" || return 125
     exec {log_fd}>"$log" || return 125
     if "$@" >&"$log_fd" 2>&1; then result=0; else result=$?; fi
     printf '%s\n' "$result" >"${log%.log}.exit" || recorder_result=125
     exec {log_fd}>&- || recorder_result=125
     if test "$recorder_result" -ne 0; then
       printf 'Recorder failed; command exit was %s\n' "$result" >&2
       return 125
     fi
     tail -n 25 "$log" || return 125
     printf 'Evidence: %s (command exit %s)\n' "$log" "$result" || return 125
     return "$result"
   }
   ```

2. **Task 1 selectors and titles:** `main nav` scoping excludes the global Home-logo link from overview/form assertions; directory trail count uses its exact localized breadcrumb label to exclude preserved pagination navigation. Counts, paths, labels, keyboard/contrast thresholds and form contracts were retained. Original diagnostic logs include `accounts-red.92pPrR.log` and `accounts-green.JULkOp.log`. The plan had retained duplicate `content_for :title` writers; Action View appends, producing `AccountsAccounts` / `ComptesComptes` and doubled account names. The approved requirement to preserve titles took precedence: remove the two redundant Accounts assignments, leaving the shared header the **sole writer**, with exact EN/FR count/equality RED→GREEN coverage. No unrelated shared `flush` change.
3. **Task 2 selected-anchor root:** nested `assert_select "a, button, input, select"` includes the selected card anchor itself. Use explicit descendants (`[data-settings-card] a`, `button`, `input`, `select` with the same prefix each), preserving zero nested controls. The in-memory probe injected **each of all four controls** and confirmed the corrected assertion rejects them; no semantic weakening. Initial selector failure remains in `settings-green.HEmDaC.log`.
4. **Task 3 actual hover:** initial headless Chromium advertised `hover:none` / `pointer:none`, so the media-gated card backgrounds never activated despite `:hover` and heading underline. **The old hover-contrast claim is WITHDRAWN**; initial `contrast.jsonl` is not actual hovered-surface proof. The new RED required effective hover/fine media, real pointer-off/default background, native pointer-on/`:hover`, changed expected computed background and stable bounds. CDP touch/media probes did not enable effective capability; failures/probes remain in `E/task3-hover-investigation-l08kug.md` and `/tmp/opencode/accounts-settings-browser-20261026-98080-l08kug/hover.jsonl`. Parent approved only `--blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4` in dedicated driver `accounts_settings_workspace_desktop_hover` and unique `accounts_settings_workspace_<object-id>` session. Phase/capability/background metadata and nested-ensure quit/selection/default-registration restoration were added; no forced CSS/pseudostyles, default-driver overwrite or production CSS change. The portability correction creates the evidence parent before `Dir.mktmpdir` (`task3-parent-directory-probe.vCzPf7.log`, exit 0). Both review findings were resolved and re-reviewed.

### Fresh browser artifacts and remaining limits

- Final source: `/tmp/opencode/accounts-settings-browser-20261026-105885-sw46v0`. Snapshots: **`E/task5-phase-a-qba8uzgs/browser-snapshots/accounts-settings-browser-20261026-105885-sw46v0/`** (`matrix.json`, `hover.jsonl`, `contrast.jsonl`, `driver-cleanup.json`, 40 feature PNGs). The sibling `accounts-settings-browser-20261026-105885-tmmxcw` and `accounts-settings-browser-20261026-105885-uldbul` snapshot directories contain the other two successful cleanup records. Paths/hashes are in `artifact-summary.json`.
- **48 unique states**: directory/account/settings × en/fr × light/dark × 375×812, 768×1024, 1440×1000, 812×375. Native Tab/Shift+Tab/Enter, >=44px target heights, >=2px outlines, full focused-action containment/four-edge visibility, no horizontal overflow/clipping, reduced motion, 768px two-column Settings grid, mobile clearance and exact routes/context/record/job invariants passed.
- **16 genuine hover pairs**, all effective hover/fine, actual false→true `:hover`, correct changed backgrounds and identical bounds. **64 contrast records / 1256 samples**, including 16 unhovered and 16 hovered Settings records: minimum text **4.9454574123:1** (>=4.5), non-text/focus **3.1916051526:1** (>=3). Actual light backgrounds `[255,255,255,255]`→`[250,250,250,255]`, dark `[38,38,38,255]`→`[23,23,23,255]`; first-card inner-border ratios change 4.7416671816→4.5428484140 and 3.1916051526→3.7809149328. **All three cleanup records** restore `selenium` / `default` and unchanged original registration. Combined protected execution introduced no new failure/error.
- Phase A implementer opened **32/40 final PNGs**: all 8 directory and 8 account images for `{en,fr}` × `{375-812,1440-1000}` × `{light,dark}`, plus all 16 corresponding Settings phase-tagged PNGs (8 unhovered/hovered pairs). Exact selection is in `final-checkpoint.json` and `report.md`. The 8 additional Settings images without phase suffixes were preserved, not separately opened. Viewport/post-reset/intentional-hover-scroll images are **not focused-state proof**; strict keyboard visibility assertions run before those later captures. Long headings can naturally extend below the viewport. Parent opened selected prior-phase images and final reviewers inspected final representatives; no claim that parent/reviewers opened all final screenshots.
- **Native headed/manual 200% browser zoom remains UNVERIFIED.** Viewport/CDP/device-scale and the startup flag are not zoom proof. The flag is explicitly **desktop-input capability emulation, not physical hardware evidence**. Remote configuration is structurally preserved but unexercised; the local wrapper clears `CAPYBARA_SERVER_PORT`. These sampled checks are not an exhaustive screen-reader/assistive-technology/device or target-width audit.
- Final root headroom was about **7.3 GiB** (89% used); `/tmp` about **3.7 GiB**. No observed disk blocker, no cleanup. No merge/push/PR/worktree removal/discard authorization. Main user work and the parent's ignored tracker were not touched; no unsupported assertion about other worktree contents.

### Independent review record and docs-only handoff boundary

| Task | Implementer session | Specification review | Quality review |
| --- | --- | --- | --- |
| 0 | `ses_e8638c64effe3yQ4yLIggmzhTi` | `ses_e86283450ffe53tTrsZgWp4y3o` | `ses_e8625cf71ffeN7oevyOCfFJE6I` |
| 1 | `ses_e861a01a0ffeMoOK8YRQXqUE8K` | `ses_e8610377effeERhtQ2CFL9qsIS` | `ses_e86097144ffeJzd6t7lsQSsRBD` |
| 2 | `ses_e86063001ffevkslKx26iVXPzf` | `ses_e860130b1ffefYapAWp4ATu6LB` | `ses_e85ff8bc5ffeuCNt3vRfgSp4rK` |
| 3 | `ses_e85fb99a4ffe0VIgM7YMnfiacY` | `ses_e85f25115ffeiqvgu1uQXbNKRm` | `ses_e85eff1a7ffeh8hMISCWZHy4fH` |
| 4 | `ses_e85d615d9ffeNQxoaHGD9XYvEU` | `ses_e85d2319bffewTfimu3d2dO01H` | `ses_e85d08bd0ffeXHRPcHu8SzU13m` |
| 5 Phase A / whole feature | `ses_e85cd7f95ffeOw4mftYSIVoNAS` | `ses_e85b9ff1fffeweT1sCwpYNqXsf` | `ses_e85b60ed7ffeIigWB59k7ssFvl` |

Tasks 0–4 received independent spec/quality approval: Task 0 reviewers re-reviewed the recorder correction; Task 1 spec's duplicate-title finding was fixed/re-reviewed; Task 3's genuine-hover and evidence-parent findings were fixed/re-reviewed. Fresh whole-feature SPEC found implementation + Phase A evidence compliant, no issues; final QUALITY approved the implementation + fresh evidence for documentation record/handoff, no issues. Parent independently read the actual final raw logs/diff and confirmed results. **These verdicts are not a clean full-suite/security gate or merge approval.**

Phase B is this authorized plan-only record. No app/test/build/DB/security reruns are needed or claimed for unchanged bytes. Before editing, all **1223 other tracked paths** (including modes/index) matched the exact tested revision; digest of their complete manifest: `4255d4df65f3178bb412169413e6547e2ec2b3f7b06b2aba8cfb1afceda4e98b`. Helper SHA-256: `46b34e5925b8395831df7653f31be98decdbcbfe795a2eab05bcad878aa9c241`; Phase A `source-boundary.json` SHA-256: `77f3bc051f9c765473d1d1f33a4164a3ba6e8f1606f654eb6cb225ab2c7513a3`. New static docs, before/after identity proofs, exact documentation commit identity and a separate Phase B report are retained under **`E/task5-phase-b-P8xZeN/`**; that external report, not a self-referential future SHA here, records the docs commit. Parent documentation-record re-review/handoff and Task 5 Step 5/user integration choice remain pending.

---

## Authority and execution boundary

**Historical planning context:** the original task bodies and planning-only self-review below are retained for traceability. Pending-tense execution instructions here describe the pre-execution state; the execution record and authoritative corrections above supersede them. Checked steps include disclosed baseline/zoom limitations, not unqualified green gates.

- Approved [specification](../specs/2026-10-26-accounts-settings-ui-ux-design.md), originally committed as `52f026b`; user answered **“go”** to written-spec review.
- Scope is `/accounts`, `/accounts/:id`, `/settings`. Preserve account New/Edit and nested tool pages. Settings still has exactly Agent skills, API tokens, MCP servers and System prompts, in that order.
- Planning checkout is `main` at `52f026b`, containing Agent skills merge `dc5fa43`. Record the actual execution base after this plan is committed. Do not overwrite new changes if HEAD moves.
- This planning pass edits documentation only. Task 0 creates the dedicated execution worktree after the user selects execution; do not run implementation, database setup or application tests while writing this plan.
- Preserve unrelated local work: `Procfile.dev`, `.agents/`, the existing untracked July/September plans/specification, `skills-lock.json`, and `test/packaging/embedding_dimensions.rb`. No stash, reset, merge, push, PR or worktree removal is authorized.
- Load the relevant TDD, Rails, testing, verification and review skills when execution starts. Do not dispatch workers until the user selects the subagent execution option.

## File structure and responsibilities

| File | Responsibility |
| --- | --- |
| `app/helpers/accounts_helper.rb` | Exact Accounts header-page predicate and authorized breadcrumb locals; retain existing helpers |
| `app/views/accounts/index.html.erb` | Workspace directory header/actions; existing account cards/empty state/pagination intact |
| `app/views/accounts/show.html.erb` | Workspace account header/actions; existing account overview panels intact |
| `app/views/workspaces/_header.html.erb` | Optional `breadcrumb_label` local; default output unchanged for other workspaces |
| `app/helpers/settings_helper.rb` (new) | Exact Settings hub predicate; not account settings or destination pages |
| `app/views/settings/show.html.erb` | Settings header and four explicit destination cards |
| `app/views/settings/_card.html.erb` (new) | One static destination link, heading, description, decorative icon/chevron |
| `app/views/layouts/application.html.erb` | Preserve existing guards; suppress redundant Accounts trail and Settings drawer only |
| `app/assets/stylesheets/nosia/settings.css` (new) | Settings grid/card layout, focus, hover and mobile clearance |
| `app/assets/tailwind/application.css` | Import Settings CSS without reordering existing imports |
| `app/assets/images/svg/key.svg`, `server.svg` (new) | Small local outline SVG assets; no package |
| `config/locales/{en,fr}.nosia_accounts_workspace.yml` (new) | Directory purpose sentence |
| `config/locales/{en,fr}.nosia_settings.yml` (new) | Settings purpose and four descriptions; reuse existing tool names |
| `test/controllers/accounts_workspace_shell_test.rb` (new) | Accounts breadcrumbs/actions, localization, escaping and isolation |
| `test/controllers/settings_workspace_test.rb` (new) | Settings semantics, exact destinations, shell boundaries and read-only behavior |
| `test/system/accounts_settings_workspace_test.rb` (new) | Real navigation, responsive/theme/locale matrix, focus, contrast and evidence |
| `test/system/account_experience_test.rb` | Keep existing contrast checks, updating header selectors without dropping coverage |
| `test/controllers/agent_skills_workspace_shell_test.rb` | Replace only its now-intentionally-obsolete Settings drawer expectation |
| `test/integration/token_usages_test.rb` | Keep its no-Token-usage-card assertion meaningful with new markup |
| `docs/accounts-settings-navigation.md` (new), `docs/account-experience.md`, `docs/README.md` | User-facing behavior and documentation links |

Do not modify controllers, models, authentication, routes, database files, JavaScript or Settings destination views. Do not rewrite `accounts/_breadcrumb.html.erb`: forms/nested tools still consume it. Do not restyle global `.n-account-primary`/`.n-account-secondary`, which other account surfaces use.

## Task 0: Isolated execution environment and fresh baseline

**Files:** No tracked application edits. External evidence under `/tmp/opencode/`; a dedicated worktree/database for this task only.

- [x] **Step 1: Inspect the current checkout and create isolation.** Use using-git-worktrees before creating the worktree. From the main repository, verify the branch/path do not already exist; if they do, investigate rather than overwrite. Run:

```sh
git status --short
git log -4 --oneline
git worktree list
git worktree add .worktrees/accounts-settings-ui -b feat/accounts-settings-ui HEAD
```

Move the session to `/home/cbldev/gitd/dilolabs/nosia/.worktrees/accounts-settings-ui` when it becomes the execution directory. PostgreSQL is in use; do not copy development databases or `.env` files into it. Record `git rev-parse HEAD` as the immutable feature base.

- [x] **Step 2: Save these shell helpers outside the repository.** Create `/tmp/opencode/accounts-settings-env.sh` with this content; source it in each execution shell. Commands assume the worktree is the working directory. Loading the existing environment through dotenv is allowed; do not display its contents or real keys.

```sh
export NOSIA_MAIN=/home/cbldev/gitd/dilolabs/nosia
export RUBOCOP_TARGET_RUBY_VERSION=4.0
export EVIDENCE="$(mktemp -d /tmp/opencode/accounts-settings-XXXXXX)"

test_command() {
  mise exec ruby@4.0.7 -- bundle exec dotenv -f "$NOSIA_MAIN/.env" -- env \
    RAILS_ENV=test DATABASE_URL=postgresql:///nosia_accounts_settings_ui_test \
    AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 "$@"
}

rails_test() { test_command bin/rails "$@"; }

browser_test() {
  test_command bundle exec ruby -rselenium-webdriver -e \
    'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' \
    -- test "$@"
}

record() {
  local label="$1" log result
  shift
  log="$(mktemp "$EVIDENCE/$label.XXXXXX.log")" || return 125
  if "$@" >"$log" 2>&1; then result=0; else result=$?; fi
  if ! printf '%s\n' "$result" >"${log%.log}.exit"; then
    printf 'Recorder failed; command exit was %s\n' "$result" >&2
    return 125
  fi
  tail -n 25 "$log" || return 125
  printf 'Evidence: %s (command exit %s)\n' "$log" "$result"
  return "$result"
}
```

Keep the first `EVIDENCE` directory when sourcing in later shells: replace the `mktemp` assignment in the saved helper with that actual absolute directory after the first source. Every `record` call creates a new filename; failed runs remain intact. No pipeline may hide the original exit. No provider/ingestion/queue workers. Do not install missing packages without permission.

- [x] **Step 3: Check prerequisites and prepare only the named test database.** Run sequentially:

```sh
mise exec ruby@4.0.7 -- ruby --version
mise exec ruby@4.0.7 -- bundle check
command -v chromium
command -v chromedriver
df -h . /tmp/opencode
record prepare rails_test db:prepare
record environment rails_test runner 'abort "wrong environment" unless Rails.env.test?; abort "wrong database" unless ActiveRecord::Base.connection_db_config.database == "nosia_accounts_settings_ui_test"; puts "Verified isolated test database"'
record baseline-build rails_test tailwindcss:build
```

If database preparation, extensions, runtime or browser prerequisites are unavailable, stop and report the blocker. Never reset/drop a shared database or change the app to make setup easier.

- [x] **Step 4: Record fresh baselines before new tests/application edits.** Run sequentially:

```sh
record baseline-focused rails_test test test/controllers/account_experience_test.rb test/controllers/accounts_controller_test.rb test/controllers/accounts test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/dashboards_controller_test.rb test/integration/token_usages_test.rb test/integration/header_navigation_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record baseline-full rails_test test
record baseline-browser browser_test test/system/account_experience_test.rb test/system/agent_skills_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/profile_management_test.rb
record baseline-security mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

Previous work reported a missing `augmented_context` method in a `Chat::RequestOptionsTest` double, Brakeman `PermitAttributes`/`EOLRails` warnings, JSON duplicate-key warnings and limited disk headroom. These are historical clues, not current acceptance. Record actual errors/warnings/exits and obtain explicit user acceptance of any reproduced baseline failures before proceeding. Do not fix, suppress or skip unrelated failures.

- [x] **Step 5: Checkpoint.** Confirm no tracked application files changed and no generated CSS is staged. No source commit is needed for environment preparation.

## Task 1: Accounts workspace breadcrumbs and actions

**Files:** `test/controllers/accounts_workspace_shell_test.rb`; `app/helpers/accounts_helper.rb`; `app/views/accounts/{index,show}.html.erb`; `app/views/workspaces/_header.html.erb`; `app/views/layouts/application.html.erb`; the two Accounts workspace locale files; `test/system/account_experience_test.rb`.

- [x] **Step 1: Write this complete request test file before application edits.**

```ruby
require "test_helper"
require_relative "../support/account_experience_fixtures"

class AccountsWorkspaceShellTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "directory has one localized trail heading and primary creation action" do
    %i[en fr].each do |locale|
      get accounts_path, headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "main h1", text: I18n.t("nosia.nav.accounts", locale: locale), count: 1
      assert_select "main nav", count: 1
      assert_select "nav[aria-label='#{I18n.t('nosia.account_experience.breadcrumb', locale: locale)}']" do
        assert_select "a[href='#{user_root_path}']", text: I18n.t("nosia.nav.home", locale: locale)
        assert_select "[aria-current='page']", text: I18n.t("nosia.nav.accounts", locale: locale), count: 1
        assert_select "a[href='#{accounts_path}']", count: 0
        assert_select "li[aria-hidden='true']", count: 1
      end
      assert_select ".n-workspace-header .n-workspace-primary[href='#{new_account_path}']" do
        assert_select "span", text: I18n.t("nosia.accounts.add", locale: locale)
        assert_select "svg[aria-hidden='true']", count: 1
      end
      assert_select ".n-workspace-help", text: I18n.t("nosia.accounts_workspace.description", locale: locale)
      assert_select "[data-account-id]", count: 3
      assert_select "#accordion-right-actions, #drawer-right", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "overview has a complete escaped trail and authorized account actions" do
    @second.update_columns(name: "<script>Research account</script>", uid: "<img src=x onerror=alert(1)>")
    %i[en fr].each do |locale|
      get account_path(@second), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "main h1", text: @second.name, count: 1
      assert_select "main nav", count: 1
      assert_select "nav" do
        assert_select "a[href='#{user_root_path}']"
        assert_select "a[href='#{accounts_path}']"
        assert_select "[aria-current='page']", text: @second.name, count: 1
        assert_select "a[href='#{account_path(@second)}']", count: 0
      end
      assert_select ".n-workspace-header .n-workspace-help", text: /#{Regexp.escape(@second.uid)}/
      assert_select ".n-workspace-header a.n-workspace-button[href='#{edit_account_path(@second)}']:not(.n-workspace-primary)"
      assert_select ".n-workspace-header a.n-workspace-primary[href='#{new_chat_path(account_id: @second.id)}']" do
        assert_select "span", text: I18n.t("nosia.account_experience.new_conversation", locale: locale)
        assert_select "svg[aria-hidden='true']", count: 1
      end
      assert_select "main script, main img[onerror]", count: 0
      assert_select "[data-conversation-id]", count: 5
    end
    assert_equal @first, @user.reload.first_account
  end

  test "member retains contextual conversation action without owner editing" do
    sign_in_overview(@member)
    get account_path(@second)
    assert_response :success
    assert_select ".n-workspace-header a[href='#{edit_account_path(@second)}']", count: 0
    assert_select ".n-workspace-header a[href='#{new_chat_path(account_id: @second.id)}']"
    get edit_account_path(@second)
    assert_response :forbidden
    get account_path(@foreign)
    assert_response :not_found
  end

  test "revocation does not fall back to another account" do
    experience(:account_users, :overview_owner_second).destroy!
    get account_path(@second), params: { id: @first.id }
    assert_response :not_found
  end

  test "new and edit forms retain their existing breadcrumb contracts" do
    get new_account_path
    assert_select "nav[aria-label='Breadcrumb'] a", count: 1
    assert_select "nav a[href='#{accounts_path}']"
    get edit_account_path(@second)
    assert_select "nav[aria-label='Breadcrumb'] a", count: 2
    assert_select "nav a[href='#{account_path(@second)}']"
    assert_select "nav a[href='#{user_root_path}']", count: 0
  end
end
```

- [x] **Step 2: Run RED.**

```sh
record accounts-red rails_test test test/controllers/accounts_workspace_shell_test.rb
```

Expected new-feature failures: directory lacks a semantic trail/workspace header; overview lacks the Home ancestor/new action styling. Existing form/member/404 characterization may already pass. Missing fixture/setup/runtime failures are not a valid RED.

- [x] **Step 3: Implement the minimal header contracts.** Append these public helpers inside `AccountsHelper`, keeping existing helpers unchanged:

```ruby
# @return [Boolean] Whether the page owns an Accounts workspace header/trail
def account_workspace_header?
  controller_path == "accounts" && %w[index show].include?(action_name)
end

# @param account [Account, nil] An already-authorized overview account
# @return [Array<Hash>] Explicit localized ancestor/current-page breadcrumb items
def account_workspace_trail(account: nil)
  trail = [ { label: t("nosia.nav.home"), path: user_root_path } ]
  trail << { label: t("nosia.nav.accounts"), path: account ? accounts_path : nil }
  trail << { label: account.name, path: nil } if account
  trail
end
```

In `workspaces/_header.html.erb`, replace its strict-local declaration and nav opening with these lines; leave all other markup unchanged:

```erb
<%# locals: (title:, description: nil, scope_label: nil, trail: [], back_path: nil, show_new_chat: false, actions: nil, breadcrumb_label: nil) %>
```

```erb
<nav aria-label="<%= breadcrumb_label || t('nosia.workspace.breadcrumb') %>" class="n-workspace-help">
```

In `layouts/application.html.erb`, change only the outer guard around existing breadcrumb/navbar rendering from `unless agent_skills_workspace_page?` to:

```erb
<% unless agent_skills_workspace_page? || account_workspace_header? %>
```

Do not alter the nested `account_page? && @account` logic or Skills flash/header/drawer guards. Rails renders the view before the layout; these two exact actions always supply the replacement below.

Replace only the existing top header in `accounts/index.html.erb` with:

```erb
<%= render "workspaces/header", title: t("nosia.nav.accounts"),
    description: t("nosia.accounts_workspace.description"),
    trail: account_workspace_trail,
    breadcrumb_label: t("nosia.account_experience.breadcrumb"),
    actions: capture {
      link_to(new_account_path, class: "n-workspace-button n-workspace-primary") do
        concat inline_svg("svg/plus.svg", aria_hidden: true, class: "h-5 w-5 shrink-0")
        concat tag.span(t("nosia.accounts.add"))
      end
    } %>
```

Replace only the existing top header in `accounts/show.html.erb` with:

```erb
<%= render "workspaces/header", title: @account.name,
    description: "#{@account.uid} · #{account_role_label(@account)}",
    trail: account_workspace_trail(account: @account),
    breadcrumb_label: t("nosia.account_experience.breadcrumb"),
    actions: capture {
      if account_owner?
        concat link_to(t("nosia.account_experience.edit_account"), edit_account_path(@account), class: "n-workspace-button")
      end
      concat(link_to(new_chat_path(account_id: @account.id), class: "n-workspace-button n-workspace-primary") do
        concat inline_svg("svg/chats.svg", aria_hidden: true, class: "h-5 w-5 shrink-0")
        concat tag.span(t("nosia.account_experience.new_conversation"))
      end)
    } %>
```

Keep the existing `.n-accounts` wrapper, `data-account-overview`, page title, panels, lists and pagination. Do not apply `html_safe` to the interpolated UID/name.

Create the two locale files with exactly:

```yaml
# config/locales/en.nosia_accounts_workspace.yml
en:
  nosia:
    accounts_workspace:
      description: "Open an account to manage its sources and conversations."
```

```yaml
# config/locales/fr.nosia_accounts_workspace.yml
fr:
  nosia:
    accounts_workspace:
      description: "Ouvrez un compte pour gérer ses sources et ses conversations."
```

- [x] **Step 4: Preserve the existing account browser contrast test after the markup migration.** In `record_account_contrast`, replace its initial action lookup with:

```ruby
tab_to_account_action(URI(find(".n-workspace-header .n-workspace-primary", match: :first)[:href]).request_uri)
```

Replace only the text sample selector array in its JavaScript with:

```js
...['.n-accounts h1', '.n-account-panel h2', '.n-workspace-header .n-workspace-help',
  '.n-account-panel .n-account-help', '.n-account-prompt',
  '.n-workspace-header .n-workspace-primary',
  '.n-workspace-header .n-workspace-button:not(.n-workspace-primary)',
  '.n-accounts .n-account-link', '.n-account-source span'].map(s => measure(s, 'text', 4.5)),
```

Retain icon/focus samples, all thresholds, keyboard order assertions and every other test. This is an intentional selector update, not permission to skip failing accessibility checks.

- [x] **Step 5: Run GREEN and protected regressions.**

```sh
record accounts-green rails_test test test/controllers/accounts_workspace_shell_test.rb test/controllers/account_experience_test.rb test/controllers/accounts_controller_test.rb test/controllers/accounts test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/internationalization/catalogs_test.rb
record accounts-build rails_test tailwindcss:build
record accounts-browser browser_test test/system/account_experience_test.rb
```

Expected: new account tests pass; existing account forms/nested trails, workspace default breadcrumb labels, owner/member permissions and context remain unchanged. Investigate any new failure rather than changing unrelated behavior.

- [x] **Step 6: Review the exact diff and commit.**

```sh
git diff --check
git add app/helpers/accounts_helper.rb app/views/accounts/index.html.erb app/views/accounts/show.html.erb app/views/workspaces/_header.html.erb app/views/layouts/application.html.erb config/locales/en.nosia_accounts_workspace.yml config/locales/fr.nosia_accounts_workspace.yml test/controllers/accounts_workspace_shell_test.rb test/system/account_experience_test.rb
git commit -m "feat: align accounts navigation and actions with workspace headers"
```

## Task 2: Settings hub semantics, destinations and isolated shell

**Files:** New Settings request test/helper/card/locale/SVG files; `settings/show.html.erb`; exact Settings drawer guard; existing Skills shell and Token usage navigation tests.

- [x] **Step 1: Write `test/controllers/settings_workspace_test.rb`.**

```ruby
require "test_helper"
require_relative "../support/account_experience_fixtures"

class SettingsWorkspaceTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "hub has one localized breadcrumb heading and four descriptive links" do
    destinations = [ agent_skills_path, api_tokens_path, mcp_servers_path, system_prompts_path ]
    titles = %w[skills tokens mcp prompts]
    descriptions = %w[skills_description tokens_description mcp_description prompts_description]
    %i[en fr].each do |locale|
      get settings_path, headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "title", text: I18n.t("nosia.nav.settings", locale: locale)
      assert_select "main h1", text: I18n.t("nosia.nav.settings", locale: locale), count: 1
      assert_select "main nav", count: 1
      assert_select "nav a[href='#{user_root_path}']"
      assert_select "nav [aria-current='page']", text: I18n.t("nosia.nav.settings", locale: locale), count: 1
      assert_equal destinations, css_select("[data-settings-card]").map { |link| link["href"] }
      destinations.each_with_index do |path, index|
        assert_select "a[data-settings-card][href='#{path}']" do
          assert_select "h2", text: I18n.t("nosia.#{titles[index]}.title", locale: locale)
          assert_select "p", text: I18n.t("nosia.settings.#{descriptions[index]}", locale: locale)
          assert_select "svg[aria-hidden='true']", count: 2
          assert_select "a, button, input, select", count: 0
        end
      end
      assert_select "[data-settings-workspace] form, [data-settings-workspace] input", count: 0
      assert_select "main svg:not([aria-hidden='true'])", count: 0
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "only Settings loses its unrelated drawer while retaining New chat access" do
    get settings_path
    assert_select "#accordion-right-actions, #drawer-right, [data-drawer-target]", count: 0
    assert_select "[data-settings-workspace] .hidden.lg\\:block a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
    assert_select ".lg\\:hidden a[href='#{new_chat_path}']", minimum: 1
    [ new_chat_path, api_tokens_path, mcp_servers_path, system_prompts_path ].each do |path|
      get path
      assert_response :success
      assert_select "#accordion-right-actions, #drawer-right", count: 2
    end
    get account_settings_path(@second)
    assert_redirected_to account_path(@second)
  end

  test "hub remains static and read only for members and users without accounts" do
    [ @user, @member, experience(:users, :overview_no_account) ].each do |user|
      sign_in_overview(user)
      before = [ Account.count, Chat.count, Prompt.count, Document.count, Text.count, Qna.count, Website.count, ApiToken.count ]
      assert_no_enqueued_jobs { get settings_path, params: { account_id: @foreign.id } }
      assert_response :success
      assert_select "[data-settings-card]", count: 4
      assert_select "[data-workspace-scope]", count: 0
      assert_equal before, [ Account.count, Chat.count, Prompt.count, Document.count, Text.count, Qna.count, Website.count, ApiToken.count ]
    end
  end
end
```

- [x] **Step 2: Run RED.**

```sh
record settings-red rails_test test test/controllers/settings_workspace_test.rb
```

Expected: missing Settings `h1`, semantic trail/descriptive card anchors and drawer suppression. Do not treat missing helper methods that tests never call as valid setup errors.

- [x] **Step 3: Add the exact-page helper and the card partial.**

```ruby
# app/helpers/settings_helper.rb
module SettingsHelper
  # @return [Boolean] Whether this is the global Settings navigation hub
  def settings_workspace_page?
    controller_path == "settings" && action_name == "show"
  end
end
```

```erb
<%# app/views/settings/_card.html.erb %>
<%# locals: (path:, title:, description:, icon:) %>
<li class="min-w-0">
  <%= link_to path, class: "n-settings-card", data: { settings_card: true } do %>
    <span class="n-settings-card-icon"><%= inline_svg icon, aria_hidden: true, class: "h-6 w-6" %></span>
    <div class="n-settings-card-heading">
      <h2 class="n-workspace-section-title"><%= title %></h2>
      <%= inline_svg "svg/chevron-right.svg", aria_hidden: true, class: "n-settings-card-chevron h-5 w-5 shrink-0" %>
    </div>
    <p class="n-workspace-help"><%= description %></p>
  <% end %>
</li>
```

Replace `app/views/settings/show.html.erb` with:

```erb
<section class="n-workspace n-settings-workspace" data-settings-workspace>
  <%= render "workspaces/header", title: t("nosia.nav.settings"),
      description: t("nosia.settings.description"), show_new_chat: true,
      trail: [ { label: t("nosia.nav.home"), path: user_root_path }, { label: t("nosia.nav.settings"), path: nil } ] %>
  <ul class="n-settings-grid !list-none" role="list">
    <%= render "card", path: agent_skills_path, title: t("nosia.skills.title"), description: t("nosia.settings.skills_description"), icon: "svg/code-bracket.svg" %>
    <%= render "card", path: api_tokens_path, title: t("nosia.tokens.title"), description: t("nosia.settings.tokens_description"), icon: "svg/key.svg" %>
    <%= render "card", path: mcp_servers_path, title: t("nosia.mcp.title"), description: t("nosia.settings.mcp_description"), icon: "svg/server.svg" %>
    <%= render "card", path: system_prompts_path, title: t("nosia.prompts.title"), description: t("nosia.settings.prompts_description"), icon: "svg/chats.svg" %>
  </ul>
</section>
```

Append `&& !settings_workspace_page?` to the existing `Current.user && ...` drawer guard in `layouts/application.html.erb`. Keep all other predicates, including `!agent_skills_workspace_page?`. Do not suppress the global flash on Settings.

Create these paired catalogs:

```yaml
# config/locales/en.nosia_settings.yml
en:
  nosia:
    settings:
      description: "Configure assistant behavior and integrations."
      skills_description: "Manage reusable instructions and how they are triggered."
      tokens_description: "Create and revoke your personal API access tokens."
      mcp_description: "Connect external tools and resources through MCP."
      prompts_description: "Review the instructions that guide your assistants."
```

```yaml
# config/locales/fr.nosia_settings.yml
fr:
  nosia:
    settings:
      description: "Configurez le comportement des assistants et les intégrations."
      skills_description: "Gérez les instructions réutilisables et leur déclenchement."
      tokens_description: "Créez et révoquez vos jetons personnels d’accès à l’API."
      mcp_description: "Connectez des outils et des ressources externes via MCP."
      prompts_description: "Consultez les instructions qui guident vos assistants."
```

Create the two assets, matching the existing small outline SVG style:

```xml
<!-- app/assets/images/svg/key.svg -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="8" cy="8" r="5"/>
  <path d="m12 12 9 9m-4-4 3-3m-6 0 3-3"/>
</svg>
```

```xml
<!-- app/assets/images/svg/server.svg -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="3" y="3" width="18" height="7" rx="2"/>
  <rect x="3" y="14" width="18" height="7" rx="2"/>
  <path d="M7 6.5h.01M7 17.5h.01M11 6.5h6M11 17.5h6"/>
</svg>
```

- [x] **Step 4: Update only intentionally changed legacy assertions.** In `test/controllers/agent_skills_workspace_shell_test.rb`, replace its Settings request/assertion pair with:

```ruby
get settings_path
assert_select "[data-settings-workspace]"
assert_select "#accordion-right-actions, #drawer-right", count: 0
get api_tokens_path
assert_select "#accordion-right-actions, #drawer-right", count: 2
```

Keep the subsequent account Skills-link/default-account checks and all Skills assertions. In the `settings page no longer shows a token usage card` test in `test/integration/token_usages_test.rb`, replace only its old `p.n-card-title` assertion with:

```ruby
assert_select "[data-settings-card]", count: 4
assert_select "a[data-settings-card][href='#{token_usage_path}']", count: 0
```

- [x] **Step 5: Run GREEN.**

```sh
record settings-green rails_test test test/controllers/settings_workspace_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/account_experience_test.rb test/integration/token_usages_test.rb test/integration/header_navigation_test.rb test/internationalization/catalogs_test.rb
```

Expected: all new semantic/scope/shell tests pass. Cards are intentionally not styled yet; Task 3 must prove the responsive visual gap before adding CSS. No new Settings data queries or connection checks are needed.

- [x] **Step 6: Commit only this task's files.**

```sh
git diff --check
git add app/helpers/settings_helper.rb app/views/settings/show.html.erb app/views/settings/_card.html.erb app/views/layouts/application.html.erb app/assets/images/svg/key.svg app/assets/images/svg/server.svg config/locales/en.nosia_settings.yml config/locales/fr.nosia_settings.yml test/controllers/settings_workspace_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/integration/token_usages_test.rb
git commit -m "feat: organize settings into descriptive navigation cards"
```

## Task 3: Browser-first responsive styling, accessibility and real navigation

**Files:** New system test; Settings CSS/import. Keep existing account panel styles unchanged unless a new scoped browser assertion demonstrates a required header-only fix.

- [x] **Step 1: Create the complete `test/system/accounts_settings_workspace_test.rb` below.** It uses existing fixture contracts and the actual browser theme/language controls, not injected replacement UI.

```ruby
require "tmpdir"
require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class AccountsSettingsWorkspaceSystemTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    @original_window_size = page.current_window.size
    @evidence_dir = Dir.mktmpdir("accounts-settings-browser-", "/tmp/opencode")
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    page.current_window.resize_to(*@original_window_size) if @original_window_size
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    Capybara.reset_sessions!
  end

  test "header creation actions work by keyboard without starting generation" do
    resize_workspace(1440, 1000)
    before = [ Chat.count, Prompt.count ]
    assert_no_enqueued_jobs do
      visit accounts_path
      focus_by_tab(".n-workspace-header a[href='#{new_account_path}']")
      assert_focused_action
      page.send_keys(:enter)
      assert_current_path new_account_path
      assert_selector "#account_name"
      visit account_path(@second)
      focus_by_tab(".n-workspace-header a[href='#{new_chat_path(account_id: @second.id)}']")
      assert_focused_action
      page.send_keys(:enter)
      assert_current_path new_chat_path(account_id: @second.id)
      assert_selector "select[name='chat[account_id]'] option[value='#{@second.id}']:checked"
    end
    assert_equal before, [ Chat.count, Prompt.count ]
    assert_equal @first, @user.reload.first_account
  end

  test "all Settings cards navigate and generic New chat remains accessible" do
    resize_workspace(1440, 1000)
    [ agent_skills_path, api_tokens_path, mcp_servers_path, system_prompts_path ].each do |path|
      visit settings_path
      focus_by_tab("[data-settings-card][href='#{path}']")
      assert_focused_action
      page.send_keys(:enter)
      assert_current_path path
    end
    visit settings_path
    focus_by_tab(".n-workspace-header a[href='#{new_chat_path}']")
    page.send_keys(:enter)
    assert_current_path new_chat_path
    assert_equal @first, @user.reload.first_account
    assert_no_enqueued_jobs
  end

  test "three pages reflow with readable focus across locales viewports and themes" do
    @second.update_columns(name: "CompteDeRecherche" * 12, uid: "identifiant-sans-espace-" * 7)
    states = []
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang='#{locale}']", visible: :all
      [ [ :directory, accounts_path ], [ :account, account_path(@second) ], [ :settings, settings_path ] ].each do |name, path|
        [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
          resize_workspace(width, height)
          %w[light dark].each do |theme|
            visit path
            set_workspace_theme(theme)
            assert_selector "main h1", count: 1
            assert_selector "main .n-workspace-header nav", count: 1
            assert_no_text(/translation missing|missing translation/i)
            assert_workspace_layout
            if name == :settings
              columns = page.evaluate_script("getComputedStyle(document.querySelector('.n-settings-grid')).gridTemplateColumns").split.length
              assert_equal width >= 768 ? 2 : 1, columns
              assert_selector "[data-settings-card]", count: 4
              assert_no_selector "#drawer-right, #accordion-right-actions", visible: :all
              assert_equal width >= 1024 ? 1 : 0, all(".n-workspace-header a[href='#{new_chat_path}']").length
            end
            if name == :account
              assert_selector "h1", text: @second.name
              assert_selector ".n-workspace-header .n-workspace-help", text: @second.uid
            end
            root = name == :settings ? "[data-settings-workspace]" : ".n-accounts > .n-workspace-header"
            selectors = all("#{root} a").map { |link| "#{root} a[href='#{URI(link[:href]).request_uri}']" }
            focus_by_tab(selectors.first)
            assert_focused_action
            selectors.drop(1).each do |selector|
              page.send_keys(:tab)
              wait_for_keyboard_scroll
              assert page.evaluate_script("document.activeElement.matches(arguments[0])", selector), "Tab order differs from visible link order"
              assert_focused_action
            end
            page.send_keys([ :shift, :tab ])
            wait_for_keyboard_scroll
            assert page.evaluate_script("document.activeElement.matches(arguments[0])", selectors[-2])
            assert_focused_action
            assert_text_unclipped(root)
            measure_workspace_contrast(root)
            if name == :settings
              card = first("[data-settings-card]")
              page.execute_script("arguments[0].scrollIntoView({block:'center'})", card)
              wait_for_keyboard_scroll
              before_hover = page.evaluate_script("(()=>{const r=arguments[0].getBoundingClientRect();return [r.x,r.y,r.width,r.height];})()", card)
              card.hover
              wait_for_keyboard_scroll
              assert_equal before_hover, page.evaluate_script("(()=>{const r=arguments[0].getBoundingClientRect();return [r.x,r.y,r.width,r.height];})()", card)
              measure_workspace_contrast(root)
            end
            page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
            image = "#{name}-#{locale}-#{width}-#{height}-#{theme}.png"
            page.save_screenshot(File.join(@evidence_dir, image)) if [ 375, 1440 ].include?(width)
            states << { page: name, locale: locale, viewport: [ width, height ], theme: theme }
            File.write(File.join(@evidence_dir, "matrix.json"), { states: states, native_200_percent_zoom: "UNVERIFIED" }.to_json)
          end
        end
      end
    end
    assert_equal 48, states.size
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    [ accounts_path, account_path(@second), settings_path ].each do |path|
      visit path
      assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
      assert page.evaluate_script("Array.from(document.querySelectorAll('main .n-workspace-header a, [data-settings-card]')).every(e=>getComputedStyle(e).transitionDuration==='0s')")
    end
    assert_equal @first, @user.reload.first_account
    puts "Accounts/Settings browser evidence: #{@evidence_dir}"
  end

  private
    def resize_workspace(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth,innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
    end

    def set_workspace_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script("const done=arguments[0]; Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());")
    end

    def assert_workspace_layout
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1")
    end

    def focus_by_tab(selector)
      200.times do
        page.send_keys(:tab)
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          wait_for_keyboard_scroll
          return
        end
      end
      flunk "Keyboard could not reach #{selector}"
    end

    def wait_for_keyboard_scroll
      page.driver.browser.execute_async_script("const done=arguments[0]; requestAnimationFrame(()=>requestAnimationFrame(done));")
    end

    def assert_focused_action
      sample = page.evaluate_script(<<~JS)
        (()=>{
          const e=document.activeElement,r=e.getBoundingClientRect(),s=getComputedStyle(e),m=document.querySelector('main').getBoundingClientRect();
          const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
          return {text:e.textContent.trim(),height:r.height,outline:parseFloat(s.outlineWidth),visible:r.top>=Math.max(0,m.top)&&r.bottom<=Math.min(innerHeight,m.bottom)&&points.every(([x,y])=>{const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));})};
        })()
      JS
      assert_operator sample.fetch("height"), :>=, 44, sample.to_json
      assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
      assert sample.fetch("visible"), sample.to_json
    end

    def assert_text_unclipped(root)
      samples = page.evaluate_script(<<~JS, root)
        Array.from(document.querySelector(arguments[0]).querySelectorAll('h1,h2,p,a span')).filter(e=>e.getClientRects().length).map(e=>{
          const s=getComputedStyle(e),r=e.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(e);
          return {text:e.textContent,ellipsis:s.textOverflow==='ellipsis',fits:e.scrollWidth<=e.clientWidth+1&&Array.from(range.getClientRects()).every(t=>t.left>=r.left-1&&t.right<=r.right+1)};
        })
      JS
      assert_not_empty samples
      samples.each do |sample|
        refute sample.fetch("ellipsis"), sample.to_json
        assert sample.fetch("fits"), sample.to_json
      end
    end

    def measure_workspace_contrast(root)
      rows = page.evaluate_script(<<~JS, root)
        (()=>{
          const root=document.querySelector(arguments[0]),canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const ancestors=[];for(let a=e;a;a=a.parentElement)ancestors.unshift(a);return ancestors.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured surface');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          function measure(e,property,minimum,parent=false){const s=getComputedStyle(e),bg=background(parent?e.parentElement:e),fg=blend(rgba(s[property]),bg),a=luminance(fg),b=luminance(bg);return {text:e.textContent.trim().slice(0,100),property,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};}
          const visible=e=>e.getClientRects().length>0&&getComputedStyle(e).visibility==='visible';
          const rows=Array.from(root.querySelectorAll('h1,h2,p,a,svg')).filter(visible).map(e=>measure(e,'color',e.tagName.toLowerCase()==='svg'?3:4.5));
          root.querySelectorAll('[data-settings-card]').forEach(e=>{rows.push(measure(e,'borderTopColor',3,true));rows.push(measure(e,'borderTopColor',3));});
          if(!root.contains(document.activeElement))throw new Error('Missing focused workspace link');
          rows.push(measure(document.activeElement,'outlineColor',3,true));return rows;
        })()
      JS
      assert_not_empty rows
      rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.to_json }
      File.open(File.join(@evidence_dir, "contrast.jsonl"), "a") do |file|
        file.puts({ path: URI(page.current_url).path, viewport: page.evaluate_script("[innerWidth,innerHeight]"),
          locale: find("html", visible: :all)["lang"], dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: rows }.to_json)
      end
    end
end
```

`tmpdir` is Ruby standard library, not a dependency change. Preserve the explicit require so evidence-directory creation does not depend on another test loading it first.

- [x] **Step 2: Run the browser RED before adding CSS.**

```sh
record browser-red browser_test test/system/accounts_settings_workspace_test.rb
```

Expected: the unstyled Settings grid lacks the two-column layout and cards lack the required focus treatment. Log each real failure; fix test syntax/setup errors before counting RED. Do not assert every page is broken: Accounts already reuses tested workspace styles.

- [x] **Step 3: Add Settings-only presentation.** Create `app/assets/stylesheets/nosia/settings.css`:

```css
.n-settings-grid { @apply grid min-w-0 grid-cols-1 items-stretch gap-4 md:grid-cols-2; }
.n-settings-card { @apply block h-full min-w-0 rounded-xl border border-neutral-500 bg-white p-5 text-neutral-900 hover:bg-neutral-50 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:bg-neutral-800 dark:text-neutral-100 dark:hover:bg-neutral-900 dark:focus:outline-green-300 sm:p-6; }
.n-settings-card-icon { @apply mb-4 inline-flex h-10 w-10 items-center justify-center rounded-lg bg-green-50 text-green-800 dark:bg-green-950 dark:text-green-200; }
.n-settings-card-heading { @apply mb-2 flex min-w-0 items-start justify-between gap-3; }
.n-settings-card-heading h2 { overflow-wrap: anywhere; @apply min-w-0; }
.n-settings-card-chevron { @apply text-neutral-600 dark:text-neutral-300; }
.n-settings-card:hover h2 { @apply underline underline-offset-4; }
main:has([data-settings-workspace]) { min-width: 0; scroll-padding-block-end: 6rem; }
```

Add this single import after the existing workspace import, preserving every other import:

```css
@import "../stylesheets/nosia/settings.css" layer(utilities);
```

No transitions, transforms, fixed action bars, fixed card heights, gradients, new fonts or global selector restyling. Existing `.n-workspace` supplies bottom clearance and reduced-motion behavior. If focused keyboard edge tests identify a genuine new Accounts header wrapping/clearance problem, reproduce it with the browser test first, then add only a `.n-accounts > .n-workspace-header` scoped fix. Do not weaken hit testing, text contrast or overflow checks.

- [x] **Step 4: Run GREEN and inspect actual screenshots.**

```sh
record styled-build rails_test tailwindcss:build
record browser-green browser_test test/system/accounts_settings_workspace_test.rb
record protected-browser browser_test test/system/account_experience_test.rb test/system/agent_skills_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/profile_management_test.rb
```

Read the screenshot paths printed by the test and inspect representative directory/account/Settings views at 375px and 1440px in both themes and locales. Confirm the long account heading/UID is readable and card hover does not move layout bounds. Review the 48-state matrix and contrast data, not screenshots alone. These checks are sampled browser evidence, not a complete assistive-technology audit.

Attempt a headed/manual native 200% browser zoom check if available and record the actual result separately. Otherwise explicitly keep it UNVERIFIED; CDP viewport/device scale and CSS zoom do not substitute. Do not mark the whole visual/accessibility verification complete without disclosing that limitation.

- [x] **Step 5: Commit.**

```sh
git diff --check
git add app/assets/stylesheets/nosia/settings.css app/assets/tailwind/application.css test/system/accounts_settings_workspace_test.rb
git commit -m "feat: polish responsive settings cards and verify workspace navigation"
```

If a reproduced Accounts-only CSS fix was required, stage its exact stylesheet explicitly and describe it in the commit body. Never stage generated builds/evidence.

## Task 4: Focused documentation and public helper contracts

**Files:** `docs/accounts-settings-navigation.md`, `docs/account-experience.md`, `docs/README.md`; new public helper YARD comments already supplied in Tasks 1–2.

- [x] **Step 1: Create `docs/accounts-settings-navigation.md` with this content.**

```markdown
# Accounts navigation and Settings

Accounts uses a Home → Accounts breadcrumb. An account overview adds the current
account name and retains its UID and your role. Add account opens the existing
account form. New conversation opens the composer with that account selected;
opening it does not send a message or start generation. Edit account remains
available only to the owner. Visiting accounts does not change a default account.

Settings is a navigation hub, not a settings form. Its four linked cards are:

- Agent skills: reusable instructions and their triggers.
- API tokens: your personal API access tokens.
- MCP servers: external tools and resources through MCP.
- System prompts: instructions that guide assistants.

Each destination retains its existing account/personal scope and permissions.
The hub does not add account switching, shared management permissions or new
destinations. Cards have distinct local icons, descriptions and one link each.

Settings uses two columns from 768px and one below that width. The unrelated
conversation-history drawer is absent on Settings; desktop New chat remains in
its header, and mobile retains the existing navigation action. Account forms,
nested tools and unrelated destination-page drawers are unchanged.

The three pages retain English/French, light/dark themes and keyboard navigation.
Long account names and labels wrap. Browser verification includes layout, focus,
contrast and clearance above mobile navigation. Native 200% browser zoom must be
reported separately from viewport emulation.

See [Account experience](account-experience.md) for permissions/data boundaries
and the [approved design](superpowers/specs/2026-10-26-accounts-settings-ui-ux-design.md)
for scope and acceptance requirements.
```

- [x] **Step 2: Add a short cross-link without rewriting historical verification.** In `docs/account-experience.md`, after the opening paragraph add:

```markdown
The directory and overview now use the shared workspace header, complete Home /
Accounts breadcrumbs, and distinct primary/secondary header actions. Account
forms and nested-tool trails retain their existing presentation contracts. See
[Accounts navigation and Settings](accounts-settings-navigation.md).
```

In the Development quick links in `docs/README.md`, immediately after Account experience add:

```markdown
- [Accounts navigation and Settings](accounts-settings-navigation.md) — workspace breadcrumbs/actions and the four-card Settings hub.
```

- [x] **Step 3: Review docs and YARD against actual code.** Confirm both new helper predicates identify exact controllers/actions and `account_workspace_trail` documents the authorized-account precondition. Do not add action/private-method comments or new documentation dependencies. Check links and whitespace:

```sh
test -f docs/accounts-settings-navigation.md
test -f docs/superpowers/specs/2026-10-26-accounts-settings-ui-ux-design.md
git diff --check
git diff --stat
```

- [x] **Step 4: Commit only the documentation.**

```sh
git add docs/accounts-settings-navigation.md docs/account-experience.md docs/README.md
git commit -m "docs: explain accounts navigation and the settings hub"
```

No artificial failing test is required for prose. Do not insert unrun test counts or update unrelated historic baseline statements.

## Task 5: Final verification, spec fidelity and execution handoff

**Files:** No application changes unless a newly reproduced in-scope defect has its own failing test. Record evidence externally, then update this plan with an honest execution record.

- [x] **Step 1: Run fresh final checks sequentially in the isolated environment.**

```sh
record final-build rails_test tailwindcss:build
record final-focused rails_test test test/controllers/accounts_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/account_experience_test.rb test/controllers/accounts_controller_test.rb test/controllers/accounts test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/dashboards_controller_test.rb test/integration/token_usages_test.rb test/integration/header_navigation_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record final-full rails_test test
record final-browser browser_test test/system/accounts_settings_workspace_test.rb test/system/account_experience_test.rb test/system/agent_skills_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/profile_management_test.rb
record final-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/helpers/accounts_helper.rb app/helpers/settings_helper.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/integration/token_usages_test.rb test/system/account_experience_test.rb test/system/accounts_settings_workspace_test.rb
record final-security mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
git diff --check
git status --short
git log --oneline -6
```

Do not combine database-sharing runs in parallel. Expected feature outcome: all focused/new/browser tests pass. Report full-suite/security nonzero exits exactly, compared with the fresh Task 0 baseline and explicit user acceptance. A known error does not make the suite green. Any new failure blocks completion until investigated. No exclusions, changed thresholds, warning suppressions or unrelated fixes.

- [x] **Step 2: Compare the complete diff to the immutable Task 0 base.** Run `git diff --stat BASE..HEAD` and `git diff --check BASE..HEAD`, substituting the exact recorded SHA for `BASE`. Verify only the mapped files changed; no controller/model/auth/route/dependency/schema/JavaScript files or destination templates changed. Inspect shared-header default output, exact Settings drawer predicate, preserved Skills guards, account 403/404 paths, escaped names/UIDs and default-account preservation.

- [x] **Step 3: Run the approved execution method's specification and quality reviews.** Review the specification's Decisions section against the implemented tasks. Confirm all links, English/French descriptions, icons, responsive breakpoint, single-heading/single-trail semantics and account action behavior. Check YARD, scoped CSS, no extra Settings queries and test evidence. If subagent execution was selected, use its required fresh reviews; otherwise perform the executing-plans review checkpoints without spawning unauthorized agents.

- [x] **Step 4: Record the actual outcome in this plan, then commit documentation only.** Include immutable base, tested revision, task commits, commands/log paths, counts/exits, browser matrix/screenshots, baseline acceptance and remaining limitations. Record native zoom as verified only with real evidence; otherwise UNVERIFIED. Do not manufacture a success outcome or treat mockups as screenshots. A prose-only evidence record does not require rerunning unchanged application bytes, but state exactly which revision the evidence covers.

- [ ] **Step 5: Offer the user the completed result and integration choices.** Implementation execution does not authorize merging to main, pushing, opening a PR, deleting a worktree or discarding local work. Keep the feature branch/worktree intact until the user chooses.

## Plan self-review coverage

| Approved requirement | Tasks |
| --- | --- |
| Directory/overview trails, exact actions, owner/member isolation and escaping | 1, 3, 5 |
| Complete Settings hub, four existing destinations/order, icons/descriptions and no new capabilities | 2, 3, 5 |
| One ordinary link per card, accessible headings/labels and localized copy | 1, 2, 3 |
| Exact layout suppression without breaking Skills, forms, nested tools or unrelated drawers | 1, 2, 5 |
| 768px Settings grid, long account text, both themes/locales, focus/contrast/mobile clearance | 3, 5 |
| No scope/default/account/report changes, provider calls or GET-created domain records/jobs | 1, 2, 5 |
| Minitest/fixtures RED before application edits, isolated baseline, honest outcomes | 0–5 |
| Public helper YARD and concise linked documentation | 1, 2, 4 |

Planning self-review completed against the specification and current files: every requirement maps to the tasks above; helper/local names agree; the shared-header label remains backward compatible; current Skills guards and intentional assertion migrations are explicit. Browser checks preserve real Tab/Shift+Tab order, hover geometry, both sides of interactive borders, and no chat/prompt creation. Ruby/YAML/SVG snippets passed static syntax checks, and complete ERB snippets compiled with the installed Action View handler. No application boot, database preparation, build, application tests or browser checks were performed during planning. Execution-method selection is the next gate.
