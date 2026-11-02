# Orbite New Chat History Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the saved-chat New chat action into History, left of Close on one compact row, without changing navigation, accounting, drafts or reader guarantees.

**Architecture:** Move existing ERB into the shared dialog under the existing saved-chat condition. Add only scoped flex/wrapping CSS. Migrate presentation-coupled tests to the new location and replace removed-header focus scenarios with ordinary transcript links or genuine native reader scrolling; retain the existing focus and reader owners.

**Tech Stack:** Actual checkout: Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL, ERB, Turbo/Stimulus, Importmap/Propshaft, Ruby-native Tailwind, Minitest/fixtures, Chromium/Selenium 4.43.0. No dependency changes.

---

## Authority, source bridge and execution order

- User approved the [written relocation specification](../specs/2026-11-02-orbite-new-chat-history-action-design.md), committed as `552b0e4dcced24eeb567e56e8234326971f3fc75`, with **“Validée”**. Keep the approved same-row placement; do not reopen design or execution-choice questions.
- Remain in this existing worktree. Execution remains implementer → fresh independent SPEC → different fresh independent QUALITY. Parent self-reviews this plan; no plan-review agent is needed.
- The old implementer `ses_e63d1e045ffe1sCgDEpqjSvOdV` is paused, no command active. Its old conditional code-commit permission was withdrawn. Do not resume its old-contract commands or run overlapping source/runtime work.
- Static pre-plan receipt: `/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/new-chat-plan-20261102-wijrCi1h/baseline.json`, SHA256 `45c7d66161e24ce444d43ecffb74719041f50067305857643c7fc50c24347a4c`. Paired `relocation-plan-baseline.NXzJPqI6` exit0 verifies all1106 source inputs, all11505 runtime entries,27 candidates and five drafts at HEAD552b0e4. It is not an application result.
- This plan and the spec approval metadata are the only permitted parent documentation changes. The implementation starts at their actual docs-only child of552b0e4; record that full SHA as `implementationParent`. The eventual coherent code commit must have exactly that parent. Any intervening source/commit change requires an explicit bridge, not a hardcoded old-HEAD bypass.
- Four punctuation changes already exist but their offline audit/build/final gates have not run. Preserve and audit them against `/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/premium-punctuation-final-20261102-UpLJUzwk/before/`; do not reapply them or run the old HEAD-specific guard unchanged.
- Preserve the verified reader correction,44-space formatting bridge, no-Delete History, inset reveal, rail return, removed header Home/History and all earlier pending work. The failed146/14329/3F request run remains failed history.

## Execution safety

Use this reviewed preamble and repository working directory for execution shells:

```bash
# workdir=/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui
source /tmp/opencode/chat-workspace-env.sh || exit $?
export E=/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq
export EVIDENCE="$E"
export ORBITE_SOURCE_SHA="$(git rev-parse HEAD)"
source "$E/recorder.sh" || exit $?
```

Reserve a new exclusive child of `E` and use it as `EVIDENCE`. Bind each command,
actual source/configuration/runtime, raw and true exit there. Application/build/
browser groups run sequentially, foreground, tool timeout0. Never poll an agent
or retry an unchanged failure. Expected meaningful RED is the sole nonzero gate
that may be followed by implementation after inspecting its actual failure.

No dotenv disclosure, process inspection/control, installation, DB setup/DDL,
provider/MCP/crawl/embedding, performed jobs/workers/drain, unrestricted suite,
merge/push/PR or cleanup. The isolated Cable setup is complete: do not repeat it.
`test/integration/localized_broadcasts_test.rb` remains withdrawn, even filtered.
Use exactly `test/system/localization_test.rb` for final system localization.
Do not recreate old diagnostics, lost security evidence or the before baseline.

## File ownership and coherent commit boundary

### New production edits: exactly three existing paths

| File | Responsibility |
| --- | --- |
| `app/views/chats/_header.html.erb` | Remove only the existing New chat link and its empty actions container. |
| `app/views/application/_orbite_shell.html.erb` | Wrap the unchanged Close control in the shared action row and insert the moved saved-chat-only link before it. |
| `app/assets/stylesheets/nosia/orbite_shell.css` | Scoped single-row layout, wrapping and right-aligned Close. |

### Coupled test edits: exactly nine existing candidate paths

- `test/integration/premium_chat_header_test.rb`: migrate the two locale header assertions and add two locale visibility-boundary tests.
- `test/integration/compact_headers_test.rb`: migrate one toolbar action assertion/name, retain heading/account/Usage checks.
- `test/integration/orbite_shell_test.rb`: extend the two existing no-account cases with row/link/Close assertions.
- `test/system/premium_chat_header_test.rb`: add two permanent relocation tests, move old button focus/contrast checks into the real History-row test; retain all bar/account/zero/live/density oracles.
- `test/system/compact_headers_test.rb`: exact geometry, pending-resize pair, companion, observer target and matrix recovery migrations below. Other ordering/interception helpers and assertions stay exact.
- `test/system/orbite_history_density_test.rb`: replace only the obsolete post-navigation header-link recovery block; all six permanent units and entire rail regression/sampler stay exact.
- `test/system/chat_workspace_test.rb`: replace only the responsive details case's obsolete reverse-header-link traversal with native reader recovery. Reader fix/regression and all reader/draft/Stop/Retry/source/upload assertions stay exact.
- `test/system/orbite_workspace_test.rb`: change the mobile header action assertions to absence in the header and saved-only presence in the hidden History row; preserve actual opener/draft/Close/Escape tests.
- `test/support/orbite_browser_checks.rb`: add only `orbite_read_start`, a genuine native wheel action. Do not change existing reachability, Tab, focus, contrast, settle, opener or language/theme helpers.

No new repository code file is needed. Combined code candidates remain **exact27**:

```text
app/assets/stylesheets/nosia/orbite_chat.css
app/assets/stylesheets/nosia/orbite_shell.css
app/javascript/controllers/scroll_controller.js
app/javascript/controllers/workspace_navigation_controller.js
app/views/application/_orbite_shell.html.erb
app/views/chats/_header.html.erb
app/views/chats/_history_items.html.erb
app/views/chats/_token_totals.html.erb
app/views/messages/_token_footer.html.erb
config/locales/en.nosia_chat_workspace.yml
config/locales/fr.nosia_chat_workspace.yml
test/controllers/chat_workspace_test.rb
test/controllers/dashboards_controller_test.rb
test/controllers/settings_workspace_test.rb
test/controllers/sources_workspace_shell_test.rb
test/controllers/token_usage_workspace_shell_test.rb
test/integration/chat_message_rendering_test.rb
test/integration/compact_headers_test.rb
test/integration/orbite_shell_test.rb
test/integration/premium_chat_header_test.rb
test/integration/token_footer_test.rb
test/support/orbite_browser_checks.rb
test/system/chat_workspace_test.rb
test/system/compact_headers_test.rb
test/system/orbite_workspace_test.rb
test/system/orbite_history_density_test.rb
test/system/premium_chat_header_test.rb
```

This is not editing permission for preserved candidates outside the twelve
relocation paths. No additional punctuation, locale, accounting, JavaScript,
reader, composer, route, model, sanitizer or dependency edit is authorized.
Five D drafts stay byte/mode exact and unstaged during the code task:
`docs/README.md`, `docs/chat-composer.md`, `docs/chat-workspace.md`,
`docs/compact-headers.md`, `docs/orbite-workspace.md`.

## Task 0 — Static bridge, exact migration guards and pending punctuation audit

- [ ] Verify the implementation HEAD is the docs-only child specified above, index empty, known dirty paths only. Bridge all1106 baseline entries with exactly this new plan and the approved spec metadata change, yielding1107 sources. Snapshot all27 candidates and five drafts into the new external directory before edits. Do not relabel the baseline as an execution at the new SHA.
- [ ] Reuse byte-bound read-only inventory/runtime primitives from `premium-phase0-20261102-7ME3BKhT/checkpoint-v2.py` (SHA256 `591c8bd6ec22d533406a3674d22e023aea227a512c69a8ac1e7fb6cf19a03785`), not its obsolete checkpoint main. Preserve11505 runtime bindings and symlink identities from the pre-plan baseline. Generated CSS remains199200bytes/SHA256 `987e72d3a3158f64bb048337285bdfd2a99fbeb4b4c7b6705cfb3298cb89e067` until the owned build below. No external compiler diagnostic.
- [ ] Retain the original14 protected method receipts and six density-unit/rail receipts. Explicitly bridge only `header_prepare_paused_chat` using the complete replacement below; do not silently remove its guard. Thirteen other protected methods remain exact. Add exact-body guards for all enumerated reader test migrations, the approved Close block (ignoring only its two-space nesting indentation), reader JS, the permanent cache regression, and all unchanged shared helpers. After test migration freeze all new bodies before runtime.
- [ ] Audit the already-present four punctuation deltas offline: each YAML value equals its original plus `:`, other parsed YAML data equal; each partial loses exactly one literal colon at the specified translation call, Ruby fragments/calculations/precision/fallback unchanged. Record new actual receipts. The existing failed request group provides RED; do not repeat it just for failure evidence.
- [ ] Read actual new test code, all changed callers, wrappers and the installed Selenium4.43.0 `WheelActions#scroll_from`/`ScrollOrigin.element` implementations before boot. Existing synchronous TokenUsage broadcast/capture and local fixture operations stay within the audited no-performed-job envelope. Reuse unchanged audit bindings honestly; new test/helper bodies require fresh audit and Ruby/embedded-JS parsing.
- [ ] Freeze selection paths before execution:14 final request files, seven native files and exact system localization listed in Task4. Record expected new named tests statically and actual runtime counts later; do not turn the old predicted255 native count into an observed result or waive missing tests.

Return this static readiness checkpoint to parent before adding/running tests.
No boot, build, test, staging or code commit belongs to Task0.

## Task 1 — Meaningful relocation tests before production edits

### Request contracts

- [ ] In the existing locale loop in `test/integration/premium_chat_header_test.rb`, replace only its old `.n-chat-toolbar a` assertion with:

```ruby
assert_select ".n-chat-header a[href='#{new_chat_path}'], .n-chat-header .n-workspace-actions", count: 0
assert_select "#chat-history > .n-orbite-navigation-actions > a.n-workspace-button[href='#{new_chat_path}']",
  text: I18n.t("nosia.chat_workspace.new_chat", locale: locale), count: 1
assert_select "#chat-history > .n-orbite-navigation-actions > #workspace-navigation-close[type=button][data-chat-dialog-initial-focus][data-action='workspace-navigation#close']", count: 1 do |buttons|
  assert_equal I18n.t("nosia.chat_workspace.close", locale: locale), buttons.first["aria-label"]
end
assert_select "#chat-history .n-orbite-panel-content .n-orbite-navigation-actions", count: 0
```

- [ ] In that same locale loop, add this complete test:

```ruby
test "History top action remains saved chat only in #{locale}" do
  [ new_chat_path(account_id: @second.id), new_chat_path, accounts_path,
    account_path(@second), settings_path ].each do |path|
    get path, headers: { "Accept-Language" => locale.to_s }
    assert_response :success
    assert_select "#chat-history > .n-orbite-navigation-actions", count: 1 do
      assert_select "a", count: 0
      assert_select "#workspace-navigation-close[data-chat-dialog-initial-focus][data-action='workspace-navigation#close']", count: 1
    end
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

- [ ] Extend the existing EN/FR no-account tests in `test/integration/orbite_shell_test.rb` with these assertions immediately after successful response, preserving their fixture setup and all other checks:

```ruby
assert_select "#chat-history > .n-orbite-navigation-actions > a", count: 0
assert_select "#chat-history > .n-orbite-navigation-actions > #workspace-navigation-close[data-chat-dialog-initial-focus]", count: 1
```

### Native row, closing, draft and activation contracts

- [ ] Add these two tests to `test/system/premium_chat_header_test.rb` before `private`. They use existing helpers and the geometry helper supplied next; no production edit yet:

```ruby
test "History top row keeps the moved action accessible without disturbing the draft" do
  premium_contexts do |locale, width, height, dark|
    link = "#chat-history > .n-orbite-navigation-actions > a[href='#{new_chat_path}']"
    assert_selector link, text: I18n.t("nosia.chat_workspace.new_chat", locale: locale), exact_text: true, count: 1, visible: :all
    assert_no_selector ".n-chat-header a, .n-chat-header button, .n-chat-header .n-workspace-actions", visible: :all
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep this History action draft")
    page.execute_script("window.historyActionEditor = document.querySelector('lexxy-editor')")
    find("#workspace-navigation-close").click if page.has_selector?("#chat-history[open]", wait: 0)
    opener = orbite_navigation_trigger
    orbite_tab_to(opener)
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector width >= 1280 ? "#chat-history[data-inline=true][open]" : "#chat-history:modal"
    assert_selector "#workspace-navigation-close:focus" if width < 1280
    orbite_tab_to(link, reverse: true)
    chat_contrast link
    chat_contrast link, minimum: 3, outline: true
    sample = premium_history_actions
    assert_in_delta sample.fetch("link").fetch("top"), sample.fetch("close").fetch("top"), 1, sample.to_json
    assert_operator sample.fetch("link").fetch("right"), :<=, sample.fetch("close").fetch("left"), sample.to_json
    %w[link close].each do |name|
      %w[width height].each { |axis| assert_operator sample.fetch(name).fetch(axis), :>=, 44, sample.to_json }
    end
    assert sample.fetch("outsideContent"), sample.to_json
    assert sample.fetch("labelFits"), sample.to_json
    assert_operator sample.fetch("panelScrollWidth"), :<=, sample.fetch("panelClientWidth"), sample.to_json
    assert_operator sample.fetch("pageWidth"), :<=, sample.fetch("viewportWidth"), sample.to_json
    orbite_assert_reachable(link)
    orbite_tab_to("#workspace-navigation-close")
    orbite_record("history-action-row-#{locale}-#{width}x#{height}-#{dark}", sample, screenshot: true)
    page.driver.browser.action.send_keys(:enter).perform
    assert_no_selector "#chat-history[open]", visible: :all
    assert_selector "#{opener}:focus"
    orbite_assert_reachable(opener)
    if width < 1280
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-history:modal"
      page.driver.browser.action.send_keys(:escape).perform
      assert_no_selector "#chat-history[open]", visible: :all
      assert_selector "#{opener}:focus"
      orbite_assert_reachable(opener)
    end
    assert page.evaluate_script("window.historyActionEditor === document.querySelector('lexxy-editor')")
    assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this History action draft", exact_text: true
    assert_no_enqueued_jobs only: ChatResponseJob
  end
end

test "History New chat retains native keyboard and pointer navigation" do
  %w[en fr].product([ [ 375, 812 ], [ 1400, 1000 ] ], %w[keyboard pointer]).each do |locale, (width, height), input|
    orbite_viewport(width, height)
    orbite_select_language(locale.upcase)
    visit chat_path(@chat)
    assert_selector "lexxy-editor[connected]"
    orbite_theme(input == "pointer")
    find("#workspace-navigation-close").click if page.has_selector?("#chat-history[open]", wait: 0)
    opener = orbite_navigation_trigger
    orbite_tab_to(opener)
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#chat-history[open]"
    link = "#chat-history > .n-orbite-navigation-actions > a[href='#{new_chat_path}']"
    counts = [ Chat.count, Message.count ]
    if input == "keyboard"
      orbite_tab_to(link, reverse: true)
      page.driver.browser.action.send_keys(:enter).perform
    else
      orbite_assert_reachable(link)
      find(link).click
    end
    assert_current_path new_chat_path
    assert_selector "lexxy-editor[connected]"
    assert_selector "html[lang='#{locale}']"
    assert_no_selector "#chat-history > .n-orbite-navigation-actions > a", visible: :all
    assert_equal counts, [ Chat.count, Message.count ]
    orbite_record("history-new-chat-#{locale}-#{width}-#{input}", { input: input, counts: counts }, screenshot: true)
    assert_no_enqueued_jobs only: ChatResponseJob
  end
end
```

- [ ] Add this private read-only geometry helper to the same file:

```ruby
def premium_history_actions
  page.evaluate_script(<<~JS)
    (() => {
      const panel = document.querySelector('#chat-history'), row = panel.querySelector('.n-orbite-navigation-actions')
      const link = row.querySelector('a'), close = row.querySelector('#workspace-navigation-close')
      const rect = link.getBoundingClientRect(), range = document.createRange()
      range.selectNodeContents(link)
      return { link: rect.toJSON(), close: close.getBoundingClientRect().toJSON(),
        outsideContent: row.parentElement === panel && !panel.querySelector('.n-orbite-panel-content').contains(row),
        labelFits: link.scrollWidth <= link.clientWidth && [...range.getClientRects()].every(line => line.left >= rect.left - 1 && line.right <= rect.right + 1 && line.top >= rect.top - 1 && line.bottom <= rect.bottom + 1),
        panelScrollWidth: panel.scrollWidth, panelClientWidth: panel.clientWidth,
        pageWidth: document.scrollingElement.scrollWidth, viewportWidth: innerWidth }
    })()
  JS
end
```

- [ ] Audit/parse actual new bodies, freeze them, then run request RED and native RED separately. Record actual exits without a shell continuation that hides unexpected errors:

```bash
nav_record history-action-request-red rails_test test test/integration/premium_chat_header_test.rb -i /premium_header_retains_all_information/ --seed 64146
```

Expected: two meaningful failures caused by the action still being in the header,
no errors/skips. Inspect the raw before proceeding.

```bash
nav_record history-action-native-red browser_test test/system/premium_chat_header_test.rb -i /History_top_row_keeps/ --seed 91
```

Expected: one meaningful failure for the missing saved History-row action, no
errors/skips. Do not run the old bar or density characterization to recreate RED.
Return these originals to parent; only accepted meaningful RED permits Task2.

## Task 2 — Minimal relocation and explicitly coupled migrations

### Production

- [ ] Remove exactly this block from `app/views/chats/_header.html.erb`, leaving the title, toolbar and Usage subtree unchanged:

```erb
      <div class="n-workspace-actions">
        <%= link_to t("nosia.chat_workspace.new_chat"), new_chat_path, class: "n-workspace-button" %>
      </div>
```

- [ ] In `app/views/application/_orbite_shell.html.erb`, replace the original Close block with this complete row. Preserve every Close attribute/icon and all other shell markup/actions:

```erb
    <div class="n-orbite-navigation-actions">
      <% if chat_workspace_page? && @chat.persisted? %>
        <%= link_to t("nosia.chat_workspace.new_chat"), new_chat_path, class: "n-workspace-button" %>
      <% end %>
      <button id="workspace-navigation-close" type="button" class="n-orbite-control n-orbite-navigation-close"
              aria-label="<%= t('nosia.chat_workspace.close') %>" title="<%= t('nosia.chat_workspace.close') %>"
              data-chat-dialog-initial-focus data-action="workspace-navigation#close">
        <%= inline_svg "svg/close.svg", aria_hidden: true, class: "h-5 w-5" %>
      </button>
    </div>
```

- [ ] Immediately after the existing `.n-orbite-navigation-close` rule in `app/assets/stylesheets/nosia/orbite_shell.css`, add only:

```css
.n-orbite-navigation-actions { display: flex; flex: none; align-items: flex-start; gap: .5rem; min-width: 0; }
.n-orbite-shell .n-orbite-navigation-actions > .n-workspace-button { flex: 0 1 auto; max-inline-size: calc(100% - 3.25rem); white-space: normal; overflow-wrap: anywhere; }
.n-orbite-navigation-actions > .n-orbite-navigation-close { align-self: flex-start; margin-inline-start: auto; flex: 0 0 2.75rem; }
```

The existing scoped44px minimum remains effective. No wrapping of the flex row,
overlay, new scroll owner, JavaScript, focus controller or header CSS cleanup.
Without the link, automatic start margin keeps Close at the right.

### Request/native location migrations

- [ ] Rename the one integration compact-header test to `saved chat toolbar keeps its heading account and existing usage target`; replace only its old link assertion with:

```ruby
assert_select ".n-chat-header a[href='#{new_chat_path}'], .n-chat-header .n-workspace-actions", count: 0
assert_select "#chat-history > .n-orbite-navigation-actions > a[href='#{new_chat_path}']", text: I18n.t("nosia.chat_workspace.new_chat"), count: 1
```

- [ ] In the mobile accounted-header test in `test/system/orbite_workspace_test.rb`, replace its old saved-header-link/conditional-empty-actions assertions with:

```ruby
assert_no_selector ".n-chat-header a, .n-chat-header button, .n-chat-header .n-workspace-actions", visible: :all
assert_selector "#chat-history > .n-orbite-navigation-actions > a[href='#{new_chat_path}']", count: entry == "saved" ? 1 : 0, visible: :all
```

Keep every opener, draft identity, native Close/Escape and return assertion.

### Genuine reader recovery, not a fake focusable header

- [ ] Add only this private helper before the existing `orbite_tab_to` in `test/support/orbite_browser_checks.rb`. It uses installed Selenium4.43.0 APIs, observes geometry without writing it and performs one actual wheel action in the real reader. Its bounded wait observes completion, not a hidden retry or altered reader oracle:

```ruby
def orbite_read_start
  reader = find("[data-application-scroll]")
  origin = Selenium::WebDriver::WheelActions::ScrollOrigin.element(reader.native)
  distance = page.evaluate_script("document.querySelector('[data-application-scroll]').scrollHeight").ceil
  page.driver.browser.action.scroll_from(origin, 0, -distance).perform
  Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
    page.evaluate_script("document.querySelector('[data-application-scroll]').scrollTop === 0")
  end
  orbite_settle
  assert_equal 0, page.evaluate_script("document.querySelector('[data-application-scroll]').scrollTop")
  assert_equal 0, page.evaluate_script("document.scrollingElement.scrollTop")
end
```

- [ ] Replace only the obsolete three-line reverse-traversal recovery block/comment in the density matrix with:

```ruby
# Native wheel navigation recovers the ordinary reader start without a new focus owner.
orbite_read_start
orbite_record("#{label}-recovered-account", density_header, screenshot: true)
```

Preserve its existing root-scroll/job checks and every full label/glyph/containment
assertion before it. No alteration to six permanent units or rail regression.

- [ ] In `test/system/chat_workspace_test.rb`'s responsive stateful details case, replace only `chat_keyboard_focus ".n-chat-toolbar a...", reverse: true` with `orbite_read_start`. Existing Usage/source/contrast/Stop/Retry oracles and subsequent genuine traversal remain exact.
- [ ] In the premium bar test, replace only its old header-button traversal/outline/reachability/44px block with `orbite_read_start`. That complete button focus/outline/44px coverage now lives in the new actual History-row test; do not remove or weaken its new assertions. Retain all segment math, contrast, values, overflow, reduced-motion, live and16-context density helpers byte-identically.

### Strict pending-resize reader scenarios

The header now has no focusable action. Do not aim reader input at the relocated
dialog action: it is outside the reader and would stop testing reader ownership.
Use two adjacent ordinary local Markdown links in the existing question, above
paused Paragraph20. Do not use the empty Commonmarker heading anchor, add DOM/
tabindex controls, change the assistant fixture or script focus. Preserve the
original question prefix, all80 assistant paragraphs and reasoning data.

- [ ] Replace only `header_prepare_paused_chat` with this complete method:

```ruby
def header_prepare_paused_chat(direction, navigation_pair: false)
  @second.update_columns(name: "CompteDeRecherche" * 12)
  question = workspace(:messages, :workspace_question)
  original = question.content
  suffix = " [Home](#{root_path}) [Research account](#{account_path(@second)})"
  content = original + suffix
  assert_equal original, content.delete_suffix(suffix)
  question.update_columns(content: content)
  header_viewport(375, 812)
  visit chat_path(@chat)
  assert_selector "lexxy-editor[connected]"
  header_wait_for_message_animations
  href = navigation_pair && direction == "backward" ? account_path(@second) : root_path
  source = "##{dom_id(question, :messages)} .n-chat-user-body a[href='#{href}']"
  assert_selector "##{dom_id(question, :messages)} .n-chat-user-body a", count: 2
  header_tab_to(source)
  page.execute_script(<<~JS)
    const surface = document.querySelector('[data-application-scroll]')
    const paragraph = document.querySelectorAll('.n-chat-transcript .ai-response-content p')[19]
    surface.scrollTop += paragraph.getBoundingClientRect().top - surface.getBoundingClientRect().top - 24
    surface.dispatchEvent(new Event('scroll'))
  JS
  header_settle
  assert_selector ".n-chat-workspace[data-reader-following='false']"
end
```

- [ ] Rename the generated pair to `native reader #{direction} navigation crosses adjacent transcript links with pending resize acknowledgment`. Change only its record label to `native-reader-transcript-links-#{direction}` and target line to:

```ruby
href = direction == "backward" ? root_path : account_path(@second)
target = "##{dom_id(workspace(:messages, :workspace_question), :messages)} .n-chat-user-body a[href='#{href}']"
```

Retain one actual Tab/Shift+Tab, trusted/direction assertions, ledger-width
mismatch, deferred>0, focus/hit, paused state, single-scroll-owner and no-job
assertions without tolerance/order changes. Freeze acknowledgment/sample helpers.

- [ ] Rename the companion to `resize alone preserves the paused paragraph without pinning an already focused transcript link`; replace only its obsolete target line with:

```ruby
target = "##{dom_id(workspace(:messages, :workspace_question), :messages)} .n-chat-user-body a[href='#{root_path}']"
```

Keep exact paragraph text,±1px offset, offscreen focused target and paused checks.
- [ ] In `visible Usage growth preserves a paused paragraph through the actual header observer`, replace only the argument to `header_hold_reader_frame` with that same root-path question-link selector. All real observer/frame ordering, activation=nil, growth, paragraph/±1px/paused/Latest/job assertions and the entire interception helper stay exact.

### Header geometry and matrix recovery

- [ ] In `saved header keeps visible complete Usage and the same native draft editor`, change the JavaScript geometry keys `actionsBottom`→`toolbarBottom` with `.n-chat-toolbar` as its node, remove `newChatTop`, and change `titleTop`→`titleBottom` with the title's `.bottom`. Replace the obsolete title/button alignment assertion by `usageTop >= titleBottom`; change only the existing Usage-order assertion's key to `toolbarBottom`. Add header actions absence:

```ruby
assert_operator geometry.fetch("usageTop"), :>=, geometry.fetch("toolbarBottom"), geometry.to_json
assert_operator geometry.fetch("usageTop"), :>=, geometry.fetch("titleBottom"), geometry.to_json
assert_no_selector ".n-chat-header .n-workspace-actions, .n-chat-header a, .n-chat-header button", visible: :all
```

Retain header-in-reader/nonsticky/minimum-content/dock bounds, exact Usage values,
same editor/draft and live target uniqueness assertions.
- [ ] In `header_context`, replace only `header_tab_to` of the old header link with `orbite_read_start`. Change the sampler's `actions` node to `toolbar = document.querySelector('.n-chat-toolbar')` and `ownRow` expression to:

```javascript
ownRow: !toolbar.contains(usage) && usage.getBoundingClientRect().top >= toolbar.getBoundingClientRect().bottom
```

Preserve all full-account text/range fit/nonellipsis/viewport/own-row checks and
existing `header_top` after each matrix case. No changed typography, dimensions
or comparator threshold to make geometry pass.

## Task 3 — Audit, one owned build and focused acceptance

- [ ] Inspect the exact diff against Task0 snapshots. Require precisely the three production deltas above, enumerated test/helper changes, unchanged punctuation/reader/other candidates and five drafts. Parse actual Ruby/ERB/embedded JS. Verify the Close block's attributes/icon identity and13 unchanged protected methods, the explicit new paused-setup body, six density units and rail regression. Stop on any unexpected byte/mode drift.
- [ ] Run fresh16-file lint from Task4 first because nine Ruby paths changed; no auto-fix. Reuse inherited successful production-JS syntax only by exact JS/config/runtime hashes, not as an execution at the new SHA.
- [ ] Only on static success, run one normal new-source build and freeze the actual output. All11504 other runtime entries remain strict; this is the sole generated-CSS change permitted. No external probe or old build replay:

```bash
nav_record history-action-build rails_test tailwindcss:build || exit $?
```

- [ ] Create a fresh1107-source/11505-runtime post-build freeze, actual implementation HEAD, exact27 blob/git-mode candidates and bound test selection before GREEN. Snapshot the owned output and command/tool/true-exit/source provenance.
- [ ] Run the relocation request contracts and three strict resize cases once at amended source, in that order:

```bash
nav_record history-action-request-green rails_test test test/integration/premium_chat_header_test.rb test/integration/compact_headers_test.rb test/integration/orbite_shell_test.rb --seed 64146 || exit $?
nav_record history-action-resize-green browser_test test/system/compact_headers_test.rb -i '/native_reader_.*_navigation_crosses_adjacent|resize_alone_preserves/' --seed 91 || exit $?
```

Require three resize tests, positive assertions,0F/0E/0S and actual trusted
Tab/Shift+Tab traces with pending ledger mismatch/deferred acknowledgment, plus
unchanged±1px companion. An unexpected failure stops; no alternate link insertion,
oracle adjustment, production focus fix or unchanged retry is authorized.

- [ ] Only on success, run the exact affected native group. This exercises changed helper/scenario bodies, not old diagnostic recreation:

```bash
nav_record history-action-focused-native browser_test test/system/premium_chat_header_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/orbite_workspace_test.rb -i '/History_top_row_keeps|History_New_chat_retains|single_distribution_replaces|visible_Usage_growth|cache_cleanup_preserves|paused_paragraph_survives_compact_header|visible_Usage_and_native_History|responsive_stateful_evidence_details|mobile_accounted_chat_headers/' || exit $?
```

Require actual nonzero test/assertion counts,0F/0E/0S, real row/Close/activation
originals, unchanged source/runtime after every group. Return to parent before
Task4. No final group, comparison, stage or code commit in this checkpoint.

## Task 4 — Complete final groups, retained real baseline and original inspection

- [ ] Verify the complete final selection/audits and final pre-gate freeze. If a test/support source changed after GREEN, stop and establish a bounded correction rather than relabel receipts.
- [ ] This is the exact16-file lint command used before the build in Task3. Do not rerun it in Task4 if all its inputs/configuration/runtime stay equal:

```bash
nav_record history-action-final-lint test_command bundle exec rubocop test/integration/premium_chat_header_test.rb test/integration/compact_headers_test.rb test/integration/chat_message_rendering_test.rb test/integration/token_footer_test.rb test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb test/controllers/dashboards_controller_test.rb test/controllers/settings_workspace_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/support/orbite_browser_checks.rb test/system/premium_chat_header_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/orbite_workspace_test.rb test/system/orbite_history_density_test.rb || exit $?
```

- [ ] Run complete14-file requests, then seven-file native, then exact system localization, checking each real result/preservation before the next:

```bash
nav_record history-action-final-requests rails_test test test/integration/premium_chat_header_test.rb test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/controllers/dashboards_controller_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/sources_workspace_shell_test.rb test/integration/chat_message_rendering_test.rb test/integration/token_footer_test.rb test/controllers/chat_account_access_test.rb test/models/chat_test.rb test/internationalization/catalogs_test.rb test/internationalization/view_copy_test.rb --seed 64146 || exit $?
nav_record history-action-final-native browser_test test/system/premium_chat_header_test.rb test/system/orbite_history_density_test.rb test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb test/system/chat_workspace_test.rb test/system/compact_headers_test.rb test/system/chat_refresh_draft_test.rb || exit $?
nav_record history-action-final-localization browser_test test/system/localization_test.rb || exit $?
```

Requests should now include the two additional locale-boundary tests, not an
invented unchanged146 count. Record every actual count/seed/raw/exit and require
0F/0E/0S/nonzero assertions. Native count is actual, not the old predicted255.
Duplicate-key warnings remain visible known debt. Unexpected failure/drift stops.

- [ ] Compare the ONE final candidate characterization from this full native run against the immutable real16-context before file:
  `/tmp/opencode/orbite-newrecovery-20261101-NLNQZUxq/premium-phase1-20261102-FNBDlTc1/orbite-20261102-103985-g4kigk/measurements.jsonl`, SHA256 `ab3941c14f24af58ba13ea7aacd64475a026f32a080aced6adb5fc25df49c050`.
  Use the premium plan's exact comparator predicates:16 unique matching locale/theme/viewport contexts; equal chat/account/counts and all kind values; reader width/height and dock boundary within1px; strictly smaller ordinary-fixture header and earlier transcript top. Write a new external comparator accepting that explicit immutable before path and the final native run's single candidate JSONL path, not a recursive mixed evidence scan. No before rerun, omitted context, synthetic gain or relaxed predicate. Declare that final UI additionally relocates New chat.
- [ ] Open actual originals for all four viewports, EN/FR/themes, History-row focus/wrapping/Close/activation, zero/one-sided/large/full-account/live states, paused anchors, drafts and rail return. Record paths/hashes/dimensions/observations honestly; inspect complete raws and actual diffs, not implementer summaries alone. Zoom, screen readers, physical devices/keyboards, native tooltips and live providers remain NOT RUN.

## Task 5 — Tested27-path commit proof and independent reviews

- [ ] Parent inspects Task4 handback, actual27-path full diff (including new untracked tests), raw results, candidate/baseline comparison, originals and strict source/runtime proof before authorizing staging. Successful focused groups alone never authorize a commit.
- [ ] On allGREEN/comparison/inspection/self-review, the new conditional code boundary is exactly27 paths listed above, excluding all documentation, generated CSS and dependencies. Record `implementationParent` from Task0; it must still be actual HEAD. Freeze tested SHA256/blob/git mode for each before staging. Stage only those explicit paths, then require exact staged path-set equality and every staged blob/mode equal to that pre-gate freeze; run `git diff --cached --check`, inspect a saved full-index binary staged diff and compare working/runtime freezes again. Any mismatch stops without discarding user work.
- [ ] Only after parent acceptance of that proof, commit with `feat(ui): Refine compact chat history and premium usage header`. Verify actual parent equals `implementationParent`, exact27 committed paths/blobs/modes equal tested freeze, index empty and only five unchanged D drafts dirty. State tests ran at the plan HEAD plus working bytes, never at a future code SHA. No merge/push/PR/cleanup.
- [ ] Parent dispatches a fresh independent SPEC reviewer against relocation/premium/reader/punctuation requirements and actual code/evidence. Only after SPEC passes dispatch a different fresh QUALITY reviewer. Important/Critical findings require a bounded verified correction, not acceptance by self-report or weakened tests. Do not reuse the implementer as either reviewer.
- [ ] After code reviews, reconcile the five pending documentation drafts in a separate bounded documentation task; preserve historical results, current reader/draft/source/upload safeguards and honest limits. Update the prior premium documentation wording so New chat is explicitly at the top of History, saved-chat-only, left of Close. Link this approved spec/plan using paths relative to the owning guide. Documentation staging/commit needs its separate authorization; no rewrite of the preserved drafts during code execution.
- [ ] Security-baseline provenance and final whole-feature independent review remain pending separate work. Historical warning fingerprints do not replace a retained baseline. Do not report security-clean, whole-feature complete or verified external accessibility before those gates.

## Parent plan self-review

The approved action moves, not duplicates: saved-only guard, same translation/
route/style, New chat left and unchanged Close right, row outside list, wrapping
and44px targets. Request boundaries include new/account/non-chat/no-account.
Native tests cover16 EN/FR/theme/viewport contexts, modal initial focus, native
Close/Escape return and actual keyboard/pointer navigation without generation.
Inline mode retains its existing nonmodal focus/Escape policy; no invented
initial-focus or inline Escape behavior is asserted. Existing modal containment
tests remain in the full native selection.

All obsolete targets are enumerated, including the shared reader-setup method,
frame observer argument, header geometry, native recovery and mobile contract.
Two real adjacent transcript links preserve reader input ownership; one native
wheel helper replaces removed-header recovery without synthetic focus. Strict
trusted input, observer ordering,80px following,±1px anchors, genuine Latest,
own-success-only resume and all other reader/draft tests remain protected. Six
density units/rail regression and the real16-context before baseline are retained.
The four pending punctuation changes are audited, not reapplied; final source
and27 tested blobs/modes, actual commit parent and independent review gates are
explicit. No application command or relocation source/test edit occurred while
authoring this plan.
