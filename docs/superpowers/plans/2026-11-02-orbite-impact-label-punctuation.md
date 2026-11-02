# Orbite Impact Label Punctuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development or superpowers-ruby:executing-plans for this coherent bounded correction. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Catalog the existing impact-label punctuation without changing rendered content, calculations or the localization oracle.

**Architecture:** Move the existing trailing colon into the existing EN/FR translation value and remove the matching literal colon at its two call sites. No new key, helper, markup wrapper or audit exception is needed.

**Tech Stack:** Existing Rails/Ruby, ERB, YAML, Minitest/fixtures and native browser verification. No dependency changes.

---

## Authority and actual failure

User selected **“Autoriser (Recommended)”** when asked to move only this
punctuation into the EN/FR translations in both partials, explicitly retaining
identical appearance/counts/calculations and the strict localization check.

Actual final request raw:
`/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/premium-final-format-20261102-4dW0Ui2K/premium-final-requests.DuOTGrcw.raw.log`.
It ran146 tests/14329 assertions/3 failures/0errors/0skips, seed64146, exit1.
The three existing view-copy assertions report `: kWh · gCO₂e` in the chat totals
and response footer. Parent read the complete raw, both partials, all of the
actual source-audit helper and existing test. The helper already permits the
technical unit fragment `kWh · gCO₂e`; removing translated ERB expressions leaves
the uncatalogued colon attached to that fragment. Do not weaken its allowlist,
change the validator, skip/filter the failing tests or claim a historical pass.

The earlier exact44-space formatting bridge is preserved. Final16-file lint
passed at those formatted Ruby bodies. The requests failed; final native,
localization, geometry and commit have not run. No old diagnostic/build/baseline
replay is required to establish RED: the existing meaningful three failures
are the regression evidence for this punctuation correction.

## Exact four-path correction

- [ ] Verify current HEAD is the plan-only child of
  `eeb9b921333c9a3f47d098ffd6266bea73d50775`, index empty. Bind all1104 previous
  source entries/modes unchanged plus this new document as1105 inputs. Start from
  the preserved post-request map under the evidence directory above:
  `freeze-after-premium-final-requests.json`, SHA256
  `0c10051b89aeb46cd745209bff36e1c456f0a5e2decffb94fa0b995679593d51`.
- [ ] Patch exactly these two YAML lines, preserving all other bytes:

```yaml
# config/locales/en.nosia_chat_workspace.yml
      estimates: "Environmental impact estimates:"
```

```yaml
# config/locales/fr.nosia_chat_workspace.yml
      estimates: "Estimations de l’impact environnemental:"
```

These are the original values plus one colon. Do not add or remove a space
inside either translated value; preserve the existing rendered punctuation.

- [ ] In each of `app/views/chats/_token_totals.html.erb` and
  `app/views/messages/_token_footer.html.erb`, replace the single exact fragment:

```erb
<%= t("nosia.chat_workspace.estimates") %>:
```

with:

```erb
<%= t("nosia.chat_workspace.estimates") %>
```

The response footer must otherwise stay whole-file exact. The chat totals must
otherwise retain the premium markup. No helper/validator/test/literal allowlist,
precision, number formatting, energy/fallback, method note, visibility, language
selection, reader, draft, History, CSS or JavaScript change is authorized.

- [ ] Read exact actual four-path diff and bind expected-body equality. Parse
  actual YAML offline; require each new value equals the old value plus `:`.
  Verify the two call sites remove exactly one colon each and grep confirms the
  only other usage is an unchanged test assertion. This proves the label's
  rendered string is unchanged without pretending a baseline rerun occurred.
- [ ] Retain all1101 other source entries, five D drafts,14 protected methods,
  six density units, whole rail regression, exact reader correction and all
  test bodies/modes. Preserve all11504 non-generated runtime bindings and the
  current owned199200-byte CSS until the authorized new-source build.

## Final verification and coherent commit

Every shell uses the reviewed helper/recorder preamble, exact repository cwd,
new exclusive evidence directory, sequential foreground timeout0 and real exits:

```bash
source /tmp/opencode/chat-workspace-env.sh || exit $?
export E=/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq
export EVIDENCE="$E"
export ORBITE_SOURCE_SHA="$(git rev-parse HEAD)"
source "$E/recorder.sh" || exit $?
```

- [ ] Audit the new four-path source delta before boot. Reuse unchanged callers,
  JS syntax and16-file lint by exact source/configuration hashes; do not rerun
  already passing unchanged static groups for receipts. No additional RED run.
- [ ] Run one normal source-bound build, then create a new final1105-source/
  11505-runtime freeze with all27 candidate blobs/modes before final tests:

```bash
nav_record premium-punctuation-build rails_test tailwindcss:build || exit $?
```

Only that owned build may update its generated output, which must be bound to
the actual current source/tool/raw/exit; all11504 other runtime entries stay
strict. No wildcard asset exception or external compiler diagnostic.

- [ ] Run the same complete14-file final request group, now at corrected source,
  with seed64146. Require146 tests, positive assertions,0F/0E/0S/true exit0.
- [ ] Only on request success, run the unchanged complete seven-file final native
  selection (expected255 tests), then exactly test/system/localization_test.rb.
  Preserve actual seeds/counts/raws/originals and strict source/runtime equality
  after each group. Unexpected F/E/S/drift stops; no fix or filtered retry.
- [ ] Use the single candidate16-context characterization from that native group
  against the preserved phase1 real-before baseline. Require equal fixture,
  account, exact counts/kinds, reader/dock dimensions within1px and smaller
  ordinary-fixture header height/more transcript space. No baseline rerun,
  synthetic gain, hidden fields, smaller typography or comparator waiver.
- [ ] Open actual candidate originals and representative zero/one-sided/large/
  full account/live/focus/draft/reader/rail originals; record paths/hashes/
  dimensions/observations and coverage limits honestly.
- [ ] Conditional coherent code commit scope becomes **27 paths**: the reader
  plan's26 plus **only** `app/views/messages/_token_footer.html.erb`. This new
  plan is committed separately and excluded from code. The code commit's parent
  must be this new plan-only commit, not the superseded eeb parent requirement.
- [ ] Only allGREEN/comparison/actual full27-path self-review/strict freezes and
  original inspection permit explicit27-path staging. Prove every staged blob/
  Git mode equals the pre-gates tested27 freeze; inspect the full-index binary
  staged diff, including new files. No docs/generated CSS/dependencies staged.
- [ ] Commit, then verify exact27 committed paths/blobs/modes, actual parent,
  unchanged source/runtime, empty index and only five unchanged D drafts dirty.
  State that tests ran at the plan HEAD plus working bytes; do not relabel them
  as executions at the future code SHA.
- [ ] Parent inspects actual diff/raws/originals; fresh SPEC then different fresh
  QUALITY remain mandatory. Documentation reconciliation, missing security
  baseline provenance and final whole-feature review remain pending.

No automatic merge/push/PR/cleanup. No dotenv disclosure, process inspection/
control, DB lifecycle/DDL/setup, install, provider/MCP/crawl/embedding, performed
jobs/workers/drain, unsafe unrestricted suite or withdrawn localized_broadcasts
selection. All old failures/artifacts remain unchanged. Native zoom, screen
readers, real devices, live providers and security-clean claims are not covered.

## Parent self-review

User-authorized scope is precisely four existing production paths; only one is
new to the combined code list. Existing translations plus colons preserve both
rendered labels, technical unit spellings, numbers and estimates. The existing
strict failing tests are retained and rerun at changed source. Reader/native
guarantees, formatting bridge, all other sources and five D drafts remain exact.
27-path tested-byte proof, parent binding and independent reviews are preserved.
This document authors instructions only; no punctuation implementation, build,
request retry, native/localization gate, stage or code commit has run here.
