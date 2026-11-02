# Orbite History Without Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Delete chat action from History items while retaining their ordinary navigation, complete metadata and current-chat state.

**Architecture:** Delete the existing `button_to` block and its now-unused action column/styles. Keep the authorized scoped rail-focus correction and all backend deletion routes unchanged. Migrate only tests coupled to the removed History action; retain their other native, visual, privacy and reader checks.

**Tech Stack:** Existing Rails/ERB/scoped CSS, Hotwire/importmap and Minitest/fixtures; the existing isolated test helper and local browser.

---

## Explicit user amendment to the active approved design

User: **“Remove the 'Delete chat' button on the chat history items
@app/views/chats/_history_items.html.erb”**, with the exact current partial attached.
This direct amendment supersedes earlier Delete-preservation clauses in the
History density design/plan and focus-containment plan. It is not a request to
remove server-side deletion, other deletion controls or unrelated chat behavior.
No alternative design or execution-mode selection is needed.

Before this amendment, worker `ses_e6771990affeeUdaK5QMGfA4Z7` paused cleanly at
HEAD784d25. Requests22/410, six native files246/95,242 and localization8/643 passed
against the old Delete-present contract; those are preserved results, not fresh
acceptance of the new contract. The authorized rail containment regression has a
meaningful RED1/39 and unchanged-test GREEN1/362. No command remains active.

Available pause receipt:
`/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/continuation3-pause-index.json`.
Parent checked all1097 paused input hashes and14 candidate/draft hashes. Earlier
pre-restart baseline/raw artifacts remain lost; do not recreate or relabel them.
Cable setup is complete; **do not rerun DDL or completed environment diagnostics**.

## Exact amendment paths

1. `app/views/chats/_history_items.html.erb`: remove only the Delete `button_to` block.
2. `app/assets/stylesheets/nosia/orbite_chat.css`: single-column History row;
   remove only `.n-chat-history-delete` and History `form` alignment rules.
3. `test/integration/orbite_shell_test.rb`: absent destructive History controls,
   retaining current names, escaping, dates, private roots and link contracts.
4. `test/system/orbite_workspace_test.rb`: existing eight History cases and
   `orbite_history_rows` sampler only; native links replace link/trash traversal.
5. `test/system/orbite_history_density_test.rb`: migrate only trash-dependent
   design/matrix/sampler assertions; preserve six characterization units and the
   complete rail containment regression/sampler byte-for-byte.
6. `test/system/compact_headers_test.rb`: History cross/trash case only; preserve
   the full Close-cross matrix,44px/focus/stroke/contrast assertions.
7. `test/system/chat_workspace_test.rb`: History navigation/deletion case only;
   retain real navigation, assert no destructive row controls and chat still exists.

All other source stays pause-checkpoint-identical, particularly navigation JS,
generic dialog/shared helpers, backend/models/routes/fixtures/locales, reader and
composer. The five pending D drafts stay unchanged and unstaged. The coherent
combined implementation now spans the previous nine paths plus the two newly
coupled native test files: **exactly eleven code/test paths**. No docs enter that
code commit. Separate fresh SPEC → different fresh QUALITY reviews still follow.

## Task1: Failing no-Delete contract, minimal removal and coupled migrations

- [ ] Create a new unique evidence prefix and checkpoint. Bridge the pause map
  to the parent one-document plan commit; do not mutate old receipts. Snapshot
  all amendment files, inherited protected inputs and D drafts. Reuse audited
  helper/recorder and available installed bindings; inspect only new risk paths.
- [ ] Add this request test inside the existing EN/FR loop before production edits:

```ruby
    test "history rows omit delete controls in #{locale}" do
      get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "#chat-history [data-history-chat]", minimum: 1 do |rows|
        rows.each do |row|
          assert_select row, "form, button, [data-turbo-method=delete], [data-method=delete], [data-turbo-confirm]", count: 0
          assert_select row, "div > a[href]", count: 1
        end
      end
    end
```

```bash
nav_record history-no-delete-red rails_test test test/integration/orbite_shell_test.rb -n /history_rows_omit_delete_controls/
```

Require meaningful request assertion failures, exit1, zero errors/skips. A wrong
failure blocks without a production edit or retry hunt.

- [ ] Remove exactly the attached partial's `button_to ... method: :delete` block,
  including its SVG and matching ERB `end`. Keep surrounding link/div/li/loop and
  all title/account/date/native-title/current/empty markup unchanged.
- [ ] In the History CSS row change only
  `grid-template-columns: minmax(0, 1fr) 44px` to
  `grid-template-columns: minmax(0, 1fr)`. Delete the two now-unused rules:
  `.n-orbite-shell .n-chat-history-delete` and
  `.n-orbite-shell .n-chat-history-row form`. No font, height, padding, color,
  panel dimensions, focus style or other layout changes.
- [ ] Request migrations: replace each History-row form/delete-button/confirmation
  expectation with `assert_select "form, button, [data-turbo-confirm]", count: 0`.
  Rename old native-delete test descriptions. Keep all escaping/full-value,
  datetime/date, current-link, scoped-root, names and other assertions unchanged.
- [ ] Existing Orbite eight cases: remove form/button bounds and `separateAction`
  expectations; measure only body/link, both at least8actualfontems, link44px,
  and require link width fills its row within1px. Traverse both real conversation
  links forward/reverse with unchanged trusted helper. Assert row forms/buttons
  absent. Sampler drops form/button dereferences/rectangles/separateAction fields;
  all label/date/padding/full-value/native-title fields remain.
- [ ] Density test: rename placement case to compact navigation-only rows; require
  absent row forms/buttons and full-width link. Matrix retains all fourteen rows,
  EN/FR/themes/viewports, short-fit/long-overflow, title/account one-line ellipsis,
  complete dates, text contrast,44px links, close outline/stroke/hit/native keys,
  full-value transcript/Usage recovery and unchanged rail-return oracle. Remove
  only trash controls, deleted form/button geometry and icon contrast fields from
  `density_rows`/`density_assert_row`; do not dereference absent nodes. Forward and
  reverse controls are now the first two links, not link/button pairs. Keep six
  permanent characterization units and rail regression/sampler exactly unchanged.
- [ ] Compact-header case retains only Close in its icon-control loop; add explicit
  absent History-row forms/buttons. Preserve every Close44px/focus/stroke/contrast
  check over the existing full locale/theme/viewport matrix.
- [ ] Chat workspace case retains native opening and actual different-chat link
  activation; reopen History, assert all rows lack forms/buttons and the navigated
  chat still exists. Remove only obsolete native cancel/confirm-delete steps.
  Do not change or remove backend authorization/deletion tests elsewhere.
- [ ] Run the unchanged new request contract to GREEN. Stop on unexpected F/E/S.

## Task2: Fresh final-source gates and exact scope proof

The partial/shared History CSS and native traversal changed, so rerun these groups
on NEW frozen bytes; this is validation of a new contract, not replay of completed
diagnostics or lost baseline proof. Reuse existing environment/DDL/prerequisite
successes without rerunning them.

```bash
nav_record history-no-delete-build rails_test tailwindcss:build
nav_record history-no-delete-requests rails_test test test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb
nav_record history-no-delete-native browser_test test/system/orbite_history_density_test.rb test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb test/system/chat_workspace_test.rb test/system/compact_headers_test.rb test/system/chat_refresh_draft_test.rb
nav_record history-no-delete-localization browser_test test/system/localization_test.rb
nav_record history-no-delete-lint test_command bundle exec rubocop test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/system/orbite_workspace_test.rb test/system/orbite_history_density_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb
node --input-type=module --check < app/javascript/controllers/workspace_navigation_controller.js
git diff --check
```

- [ ] Use the existing exact helper/preamble/recorder/cwd, sequential foreground
  timeout0. No dotenv disclosure, DB lifecycle, worker/provider/live API, unsafe
  unrestricted suite, process inspection/control, dependency install or cleanup.
- [ ] Freeze full current inputs/runtime bindings after build and before final
  tests. Preserve all old raw logs and write new true exits/counts/seeds/provenance.
  Stop on unexpected nonzero/F/E/S; no helper/oracle weakening or out-of-scope fix.
- [ ] Inspect actual current original no-Delete desktop/mobile/landscape EN/FR
  themes, complete metadata/native links/focus and corrected rail button. Inspect
  actual full raw gate summaries, unchanged control/reader guarantees and snapshots.
  Old counts/before-after density are historical, not a new comparison claim.
- [ ] Verify complete frozen tested bytes, all nonowned and five D drafts unchanged,
  six characterization units and rail regression untouched. Conditional code commit
  only after all gates/self-review/eleven explicit staged blobs+Git modes match
  tested freeze. Exact commit scope is the original nine plus
  `test/system/compact_headers_test.rb` and `test/system/chat_workspace_test.rb`.
  Empty index and only five D drafts dirty afterward; no automatic docs commit,
  push/merge/PR or whole-feature/security-clean claim.
- [ ] Parent independently inspects actual source/raw/artifacts, then fresh SPEC
  and different fresh QUALITY. Pending D/final whole-feature work remains separate.

**Parent self-review:** This is the user's explicit revision to the active design,
not a new speculative feature. The requested action alone is removed; no hidden
replacement, backend change or unrelated deletion removal. The unused column is
removed without shrinking targets or typography. Coupled tests retain all
applicable native/metadata/privacy/reader invariants and the approved rail fix.
