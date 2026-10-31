# Orbite Navigation Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved lean History, directly anchored user menu and visible below-title context refinements without weakening Orbite's native navigation, accounting or reader guarantees.

**Architecture:** Keep the shared shell, the single responsive History dialog and `chat-dialog` as the sole modal/focus owner. Use one native nonmodal user-action popover, anchored to the actual desktop/mobile opener, and replace header accordions with ordinary inline context; preserve the live token-total subtree and the reader's existing observer wiring. Changes are presentation and bounded test migrations, not a transport, authorization, persistence or generation redesign.

**Tech Stack:** Actual checkout: Ruby 4.0.7, Rails 8.0.5.1, PostgreSQL, ERB, Turbo/Stimulus, Importmap/Propshaft, Tailwind CSS 4 (Ruby-native build), Minitest/file fixtures, installed local Selenium/Chromium. No dependency installation or upgrade.

---

## Authority, execution mode and ownership

- Approved amendment: [Orbite navigation refinements design](../specs/2026-10-31-orbite-navigation-refinements-design.md), committed as `21c3c5d`. Read the entire specification before implementation. **Usage also loses its accordion**; Sources, Reasoning, response details and native editor formatting do not.
- Original [implementation plan](2026-10-30-orbite-premium-chat.md), Tasks 0–6, is approved through `030e20ca42df7c0be66037f170b23594a3be38cf`. Original feature baseline is `7189d6de425122120f3fb4d7090d16a9ebb88f11`.
- The selected mode is already **fresh implementer per task → independent SPEC review → independent QUALITY review**. Do not ask the user to select it again. Parent self-reviews and commits this plan; do not dispatch a plan reviewer or implement while authoring it.
- Task 7 worker `ses_e6dfac0a3ffeAiSVdeOqukY067` is paused, with no jobs running. Do not resume it concurrently with amendment work.
- Preserve its five uncommitted drafts: new `docs/orbite-workspace.md`; modified `docs/chat-workspace.md`, `docs/chat-composer.md`, `docs/compact-headers.md`, `docs/README.md`. Only Task D below may deliberately reconcile those drafts, after reading their actual diff. Never discard/recreate them from an old listing.
- This plan's author owns **only this new Markdown file**. Code listings and execution commands below are instructions for subsequent authorized implementation, not actions performed during planning.

## Nonnegotiable execution envelope

Every future shell tool invocation must explicitly set:

```text
workdir=/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui
timeout=0 for foreground build/test/browser/scanner groups
```

Every shell, including git/static verification shells, starts with:

```bash
source /tmp/opencode/chat-workspace-env.sh
export ORBITE_SOURCE_SHA="$(git rev-parse HEAD)"
export E=/tmp/opencode/chat-workspace-recovery-Pbwj0x
export EVIDENCE="$E"
```

After Task 0 creates the external recorder, also source `"$E/orbite-refinement-record.sh"` in each execution shell. The preamble is part of **every** command block below, including blocks referring to the common preamble. Do not rely on a previous shell's variables or cwd.

The approved helper fixes test mode, isolated local PostgreSQL database `nosia_chat_workspace_ui_test`, dummy AI credentials, one test worker, mise Ruby 4.0.7, local installed Chromium/driver and `RUBOCOP_TARGET_RUBY_VERSION=4.0`. Do not display/read/copy dotenv contents or print an environment dump. The helper is not a network sandbox: audit each selected test's actual calls before runtime.

Run groups sequentially, foreground, without overlap, polling or sleeps. Do not use `bin/setup`, `bin/dev`, DB create/prepare/migrate/reset, package/gem/driver installation, new worktrees, queue drains, `perform_enqueued_jobs`, workers, live providers, MCP clients, crawling, indexing or embeddings. Never inspect/control user development processes. No unrestricted suite, merge, push or PR. Stop on an unexpected failure/error/skip or new safety risk; preserve the true exit and diagnose the actual cause rather than editing a timeout/tolerance/selector until a subset passes.

### Frozen production boundaries

Keep these production files byte-identical to the amendment starting point:

- `app/javascript/controllers/scroll_controller.js` — **entire file**, including 80px pre-growth policy, 1px paragraph anchors, accepted native input, Latest/new-content and own-success-only resume.
- `app/javascript/controllers/chat_disclosures_controller.js`, `chat_dialog_controller.js`, `chat_account_controller.js`, `chat_feedback_controller.js` and native composer/source handoff controllers.
- `app/views/chats/_token_totals.html.erb`, message/response/Sources/Reasoning partials, editor formatting markup and existing chat reading/dock placement in `chats/new.html.erb` and `chats/show.html.erb`.
- All server controllers, routes, models, jobs, schema, fixtures, runtime configuration, Gemfile and lockfile. Tests can create local accounting rows or enqueue into the existing test adapter; they must not perform jobs.

Do not add a replacement header accordion, fake action, tabindex on an ordinary heading, private-ledger write, fake observer delivery gate or second modal/focus trap to keep obsolete tests green. Keep all native language/theme controls, including signed-out 44px controls, unchanged. Meaningful icon strokes and focus indicators need ≥3:1, normal text ≥4.5:1, visible focus ≥2px and redesigned hit targets ≥44×44 CSS pixels; decorative edges do not acquire an invented 3:1 requirement.

## File map and atomic task boundaries

| Task | Production ownership | Coupled test ownership |
| --- | --- | --- |
| 0 — safety/source checkpoint | External evidence only | Static audit of exact selections and inherited support/vendor paths |
| A — lean History | `app/views/application/_orbite_shell.html.erb`, `app/views/chats/_history_items.html.erb`, `app/assets/stylesheets/nosia/orbite_shell.css`, `orbite_chat.css` | `test/integration/orbite_shell_test.rb`, `test/system/orbite_workspace_test.rb`, `chat_workspace_test.rb`, `compact_headers_test.rb`, `localization_test.rb` |
| B — directly anchored single user menu | New `app/javascript/controllers/user_menu_controller.js`, new `app/views/application/_orbite_user_menu.html.erb`; shell, `_orbite_utilities.html.erb`, `orbite_shell.css`; remove unused `workspace_navigation_controller.js#utilities` only | New `test/system/orbite_navigation_refinements_test.rb`; existing shell request tests; `test/support/orbite_browser_checks.rb`; profile/logout/native-navigation callers named below |
| C — inline useful context and visible Usage | `app/views/workspaces/_header.html.erb`, `app/views/chats/_header.html.erb`, `app/views/dashboards/show.html.erb`; explicit description callers below; `app/assets/stylesheets/nosia/application_shell.css`, `orbite_chat.css` | Header/rendering/account request tests and every coupled header/Usage browser test named below; no protected reader algorithm edits |
| D — reconcile Task 7 and verify frozen final source | Only the five inherited doc drafts; external evidence | Exact final safe selections, lint/syntax and newly sourced security comparison |

Tasks run **0 → A → B → C → D**, with one reviewed coherent commit for A, B and C. Each implementer owns its corresponding coupled test migrations in the same commit: do not postpone selector/helper repairs to a later “make green” task. A file appearing in multiple tasks is sequential shared ownership, not permission for concurrent edits.

## Task 0: Refresh the safety audit and source checkpoint

**Files:** Only new external evidence under `/tmp/opencode/chat-workspace-recovery-Pbwj0x`; no tracked edits.

- [ ] **Step 1: Confirm the starting source and preserve the paused drafts.**

Run with the mandatory cwd/preamble:

```bash
git status --short
git log -5 --oneline
git diff --stat
git diff -- docs/chat-workspace.md docs/chat-composer.md docs/compact-headers.md docs/README.md
```

Read the untracked `docs/orbite-workspace.md` with the read tool. Expect the approved spec/plan metadata above application `030e20`, and the five known drafts. Record any other change and stop before overwriting unfamiliar work. Capture full starting SHA and hash the protected production files into a fresh external checkpoint (do not overwrite earlier evidence):

```bash
checkpoint="$(mktemp "$E/orbite-refinement-start.XXXXXX.txt")"
git rev-parse HEAD > "$checkpoint"
sha256sum app/javascript/controllers/scroll_controller.js app/javascript/controllers/chat_disclosures_controller.js app/javascript/controllers/chat_dialog_controller.js app/javascript/controllers/chat_account_controller.js app/javascript/controllers/chat_feedback_controller.js app/views/chats/_token_totals.html.erb app/views/chats/new.html.erb app/views/chats/show.html.erb >> "$checkpoint"
```

- [ ] **Step 2: Write a fresh raw-log/true-exit recorder without modifying the approved helper.**

Using the patch tool during implementation, create external `$E/orbite-refinement-record.sh` with this content; if the path already exists, inspect it and use a new uniquely named recorder instead of overwriting unknown bytes:

```bash
nav_record() {
  local label="$1" log result
  shift
  log="$(mktemp "$E/${label}.XXXXXX.raw.log")" || return 1
  if "$@" >"$log" 2>&1; then result=0; else result=$?; fi
  printf '%s\n' "$result" >"${log%.raw.log}.TRUE.exit" || return 125
  tail -n 30 "$log" || return 125
  printf 'Raw evidence: %s; true exit: %s\n' "$log" "$result"
  return "$result"
}
```

Do not pipe a test through `tee` and record the pipe's exit. Expected REDs are invoked inside an explicit `if ...; then ...; else ...; fi`; inspect the raw failure and require the intended assertion failure, not a boot/safety error. Normal GREEN groups must stop the shell on nonzero (`|| exit $?`).

The recorder deliberately uses `result`, not zsh's read-only special variable
`status`. Only its preview is truncated; the complete raw log and actual exit
remain available for independent inspection.

- [ ] **Step 3: Audit the exact executable perimeter before any runtime command.**

Read `$E/orbite-task7-safety-audit.md`, its referenced Task 5.5/Task 6 audits and `$E/orbite-task7-selections.json`. Inspect changed/new selected tests and their actual inherited helpers, adapters, initializer and installed vendor call paths. Write a NEW `orbite-refinement-safety-audit.md` binding the current SHA and selected-file hashes. Confirm local Disk/mail, dummy provider key, test queues without perform flags, local Cable and the isolated database. Include new `test/system/orbite_navigation_refinements_test.rb` after it exists, and the new local TokenUsage broadcasts in Task C.

Explicitly retain `test/system/chat_refresh_draft_test.rb` in final chat coverage, including its real GET/in-flight native typing case and finite CDP latency cleanup. Audit actual commands rather than treating a filename or old safety verdict as permission. Profile/catalog click paths remain real UI actions; local MCP fixture transport stays fail-fast against live clients. Existing MCP JSON symbol/string duplicate-key encoding warnings remain unsuppressed debt, not a new blanket waiver.

- [ ] **Step 4: Record the checkpoint and obtain SPEC→QUALITY clearance.**

No broad before suite is needed merely to author a plan. During execution, first run the individual A REDs only after the safety audit. Existing passing characterizations are allowed and must be labelled characterization, not manufactured RED. Reports must distinguish source/test changes from a frozen run, actual raw logs/TRUE.exit from old artifacts, and expected UI failures from safety blockers.

## Task A: Remove redundant History chrome; use named icons and padded current links

**Production files:** `_orbite_shell.html.erb:26–32`, `_history_items.html.erb:7–17`, `orbite_shell.css:115–119`, `orbite_chat.css:44–47`.

**Tests:** `test/integration/orbite_shell_test.rb`; `test/system/orbite_workspace_test.rb:540–594,667–697`; `test/system/chat_workspace_test.rb` History close/delete calls only; `test/system/localization_test.rb:351–395`; `test/system/compact_headers_test.rb` new icon contrast case only.

- [ ] **Step 1: Add request REDs for accessible naming without visible duplicate chrome.**

Append to `OrbiteShellTest` (existing fixture setup remains):

```ruby
%i[en fr].each do |locale|
  test "lean History keeps localized accessible actions in #{locale}" do
    get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
    assert_response :success
    assert_select "dialog#chat-history[aria-labelledby=chat-history-title]", count: 1
    assert_select "#chat-history h2#chat-history-title.sr-only", text: I18n.t("nosia.orbite.navigation", locale: locale), count: 1
    assert_select "#chat-history .n-orbite-panel-heading, #chat-history .n-orbite-logo", count: 0
    close = I18n.t("nosia.chat_workspace.close", locale: locale)
    assert_select "#workspace-navigation-close[aria-label='#{close}'][title='#{close}']", count: 1 do
      assert_select "svg[aria-hidden=true]", count: 1
      assert_select "span", count: 0
    end
    assert_select "#workspace-navigation-close", text: "", count: 1
    row = "[data-history-chat='#{@chat.id}']"
    assert_select "#{row} a[aria-current=page]", count: 1
    assert_select "#{row} > div > p > span", count: 0
    assert_select "#{row} form[action='#{chat_path(@chat)}'] input[name=_method][value=delete]", count: 1
    label = I18n.t("nosia.nav.delete_chat", locale: locale)
    assert_select "#{row} button[aria-label='#{label}'][title='#{label}']", text: "", count: 1 do
      assert_select "svg[aria-hidden=true]", count: 1
    end
    assert_select "#{row} button[data-turbo-confirm]" do |buttons|
      assert_equal I18n.t("nosia.actions.confirm_delete", locale: locale), buttons.sole["data-turbo-confirm"]
    end
  end
end
```

- [ ] **Step 2: Change the eight existing row-matrix contracts before production; retain their geometric oracles.**

In `OrbiteWorkspaceSystemTest`'s `inline history keeps readable rows...` matrix, replace only the visible-current/visible-delete assertions with:

```ruby
assert_no_selector "#{row} > div > p > span", visible: :all
label = I18n.t("nosia.nav.delete_chat", locale: locale)
assert_equal label, button["aria-label"]
assert_equal label, button["title"]
assert_equal "", button.text
assert_selector "#{row} button svg[aria-hidden=true]", count: 1
assert_operator geometry.fetch("button").fetch("width"), :>=, 44
if entry == "saved" && conversation == @chat
  assert_operator geometry.fetch("paddingInlineStart"), :>=, 8
  assert_operator geometry.fetch("paddingInlineEnd"), :>=, 8
  assert_operator geometry.fetch("textInset"), :>=, 8
  assert_operator geometry.fetch("paddingBlockStart"), :>, 0
  assert_operator geometry.fetch("paddingBlockEnd"), :>, 0
end
```

Keep `button = find("#{row} button")` before that block. Keep exact localized confirmation, `_method=delete`, account/date, aria-current counts, native Tab/Shift+Tab, title/body ≥8 actual font ems, 240±1px panel, no overflow, text fit, five-point hits and separate action. Do not replace these with string-only checks. In `orbite_history_rows`, extend the returned row record without deleting fields:

```javascript
const style = getComputedStyle(link), range = document.createRange()
range.selectNodeContents(link)
const firstLine = [...range.getClientRects()][0]
// Add these fields to the existing returned row object:
paddingInlineStart: parseFloat(style.paddingInlineStart),
paddingInlineEnd: parseFloat(style.paddingInlineEnd),
paddingBlockStart: parseFloat(style.paddingBlockStart),
paddingBlockEnd: parseFloat(style.paddingBlockEnd),
textInset: firstLine ? firstLine.left - link.getBoundingClientRect().left : 0
```

Add this browser case inside `CompactHeadersSystemTest`, using its existing real color-composition helper; it tests actual SVG path strokes, not a decorative border:

```ruby
test "History cross and trash retain native targets focus and measured strokes" do
  %w[en fr].each do |locale|
    orbite_select_language(locale.upcase)
    [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
      header_viewport(width, height)
      visit chat_path(@chat)
      [ false, true ].each do |dark|
        header_theme(dark)
        orbite_open_utilities
        assert_selector "#chat-history h2.sr-only", visible: :all
        assert_no_selector "#chat-history .n-orbite-logo, .n-orbite-panel-heading", visible: :all
        close = "#workspace-navigation-close"
        trash = "#chat-history [data-history-chat='#{@chat.id}'] button"
        [ close, trash ].each do |selector|
          header_tab_to(selector)
          bounds = orbite_assert_reachable(selector)
          assert_operator bounds.fetch("width"), :>=, 44
          assert_operator bounds.fetch("height"), :>=, 44
          assert_equal "", find(selector).text
          header_icon_stroke(selector)
          header_contrast(selector, minimum: 3, property: "outlineColor")
        end
        header_record("lean-history-icons", header_matrix_geometry, screenshot: true)
        orbite_close_navigation
      end
    end
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

Add this helper inside `CompactHeadersSystemTest`'s private section. It proves every meaningful path uses the measured opaque color; it does not mistake an empty point in a trash glyph for the button's hit area:

```ruby
def header_icon_stroke(selector)
  assert page.evaluate_script(<<~JS, find("#{selector} svg"))
    (() => {
      const svg = arguments[0], paths = [...svg.querySelectorAll('path')]
      return paths.length > 0 && paths.every(path => {
        const paint = getComputedStyle(path)
        return paint.stroke === getComputedStyle(svg).color && Number(paint.strokeOpacity) === 1 && paint.fill === 'none'
      })
    })()
  JS
  header_contrast("#{selector} svg", minimum: 3, property: "color")
end
```

Run these REDs with mandatory cwd/preamble and the sourced recorder:

```bash
nav_record orbite-refinement-A-request-red rails_test test test/integration/orbite_shell_test.rb -i '/lean_History/'
nav_record orbite-refinement-A-rows-red browser_test test/system/orbite_workspace_test.rb -i '/inline_history_keeps_readable_rows/'
nav_record orbite-refinement-A-icons-red browser_test test/system/compact_headers_test.rb -i '/History_cross_and_trash/'
```

Invoke each expected RED in its own exit-preserving conditional. Expect missing sr-only/icon/padding contracts, not fixture/server failures. Capture all actual failing assertions before editing production.

- [ ] **Step 3: Implement the minimal ERB/CSS changes.**

Replace the panel's entire `.n-orbite-panel-heading` header with these independent children of the existing dialog:

```erb
<h2 id="chat-history-title" class="sr-only"><%= t("nosia.orbite.navigation") %></h2>
<button id="workspace-navigation-close" type="button" class="n-orbite-control n-orbite-navigation-close"
        aria-label="<%= t('nosia.chat_workspace.close') %>" title="<%= t('nosia.chat_workspace.close') %>"
        data-chat-dialog-initial-focus data-action="workspace-navigation#close">
  <%= inline_svg "svg/close.svg", aria_hidden: true, class: "h-5 w-5" %>
</button>
```

In History rows, remove only the conditional Current conversation span. Replace `button_to` with its block form, preserving its real destination/method/confirmation:

```erb
<%= button_to chat_path(conversation), method: :delete,
      class: "n-workspace-button n-workspace-danger n-chat-history-delete",
      aria: { label: t("nosia.nav.delete_chat") }, title: t("nosia.nav.delete_chat"),
      data: { turbo_confirm: t("nosia.actions.confirm_delete") } do %>
  <%= inline_svg "svg/trash-bin.svg", aria_hidden: true, class: "h-5 w-5" %>
<% end %>
```

Delete `.n-orbite-panel-heading` rules and its h2 selector; keep `.n-orbite-history-heading { font-size: .875rem; font-weight: 600; }`. Add:

```css
.n-orbite-navigation-close { align-self: flex-end; flex: none; }
.n-orbite-shell .n-chat-history-row .n-workspace-link {
  display: block; min-height: 44px; padding: .375rem .5rem;
  color: var(--orbite-text); overflow-wrap: anywhere;
}
.n-orbite-shell .n-chat-history-row .n-workspace-help { padding-inline: .5rem; }
.n-orbite-shell .n-chat-history-delete {
  display: inline-flex; align-items: center; justify-content: center;
  width: 44px; min-width: 44px; min-height: 44px; padding: .5rem;
  color: var(--orbite-text);
}
.n-orbite-shell .n-chat-history-row form { justify-self: end; }
```

Replace, do not append a competing copy of, the existing History link rule in `orbite_chat.css`. Retain the existing active background and one-column inline row grid: the smaller icon does not authorize narrowing the title or widening the 240px panel. Account/date padding aligns with the title's inset. The close control stays a reachable real button, not an absolutely overlaid hit area covering content.

- [ ] **Step 4: Migrate only the obsolete close/delete/logo assumptions in the same task.**

In `test/system/chat_workspace_test.rb`, all `within("#chat-history") { click_button "Close" }` calls become `find("#workspace-navigation-close").click`; the sole History-row delete click becomes `click_button "Delete chat", enable_aria_label: true`. Do not change Tools Close tests (including lines 65, 97 and 225), source confirmation, dialog focus loops, opener recovery or native `accept_confirm`. Extend the existing History deletion case with a real dismissed confirmation first:

```ruby
dismiss_confirm I18n.t("nosia.actions.confirm_delete") do
  within("[data-history-chat='#{first_chat.id}']") do
    click_button I18n.t("nosia.nav.delete_chat"), enable_aria_label: true
  end
end
assert Chat.exists?(first_chat.id)
assert_selector "#chat-history:modal"
```

Then retain its existing accepted confirmation, redirect and actual record-deletion assertions.

In `LocalizationSystemTest#assert_language_control_geometry`, replace the obsolete panel-logo sample with actual hidden naming and close-control geometry:

```javascript
// Replace the old logo field; keep every other sample field.
heading: { id: panel.querySelector('h2').id,
  text: panel.querySelector('h2').textContent.trim(),
  geometry: box(panel.querySelector('h2')) },
close: box(panel.querySelector('#workspace-navigation-close'))
```

Replace only the two logo-overlap assertions with:

```ruby
assert_equal "chat-history-title", layout.fetch("heading").fetch("id")
assert_equal I18n.t("nosia.orbite.navigation", locale: :fr), layout.fetch("heading").fetch("text")
assert_in_delta 1, layout.fetch("heading").fetch("geometry").fetch("width"), 0.1
assert_in_delta 1, layout.fetch("heading").fetch("geometry").fetch("height"), 0.1
close = layout.fetch("close")
assert_operator close.fetch("width"), :>=, 44
assert_operator close.fetch("height"), :>=, 44
assert control.fetch("left") >= close.fetch("right") || control.fetch("top") >= close.fetch("bottom") || control.fetch("right") <= close.fetch("left"), layout.to_json
```

Keep native select semantics/options, full reload `performance.timeOrigin`, exact URL, 1px hidden labels, 44px control geometry, actual hits, focus-before-Escape, return-to-opener and signed-out matrix assertions unchanged.

- [ ] **Step 5: Build, run atomic GREEN groups, inspect evidence, then commit exact files.**

With mandatory cwd/preamble and recorder:

```bash
nav_record orbite-refinement-A-build rails_test tailwindcss:build || exit $?
nav_record orbite-refinement-A-requests rails_test test test/integration/orbite_shell_test.rb test/controllers/chat_workspace_test.rb || exit $?
nav_record orbite-refinement-A-browser browser_test test/system/orbite_workspace_test.rb test/system/chat_workspace_test.rb test/system/localization_test.rb || exit $?
nav_record orbite-refinement-A-icon-green browser_test test/system/compact_headers_test.rb -i '/History_cross_and_trash/' || exit $?
nav_record orbite-refinement-A-rubocop test_command bundle exec rubocop test/integration/orbite_shell_test.rb test/system/orbite_workspace_test.rb test/system/chat_workspace_test.rb test/system/compact_headers_test.rb test/system/localization_test.rb || exit $?
git diff --check
git add -- app/views/application/_orbite_shell.html.erb app/views/chats/_history_items.html.erb app/assets/stylesheets/nosia/orbite_shell.css app/assets/stylesheets/nosia/orbite_chat.css test/integration/orbite_shell_test.rb test/system/orbite_workspace_test.rb test/system/chat_workspace_test.rb test/system/compact_headers_test.rb test/system/localization_test.rb
git commit -m "refactor(ui): Simplify History chrome and secondary actions"
```

Inspect actual screenshots/measurements for EN/FR, light/dark, all four sizes and long account/title wrapping. Preserve old 8em/hit/no-overlap oracles rather than accepting narrower text. SPEC then QUALITY must pass before B. Do not stage Task 7 drafts, generated CSS or evidence.

## Task B: Open one native user popover directly above its actual rail/mobile trigger

**Create:** `app/javascript/controllers/user_menu_controller.js`, `app/views/application/_orbite_user_menu.html.erb`, `test/system/orbite_navigation_refinements_test.rb`.

**Modify:** shell, utilities, `orbite_shell.css`, `workspace_navigation_controller.js#utilities` only; `test/support/orbite_browser_checks.rb`; shell request test; `test/system/orbite_workspace_test.rb`, `compact_headers_test.rb`, `account_experience_test.rb` user-menu callers. Other navigation tests retain their real language/theme/profile actions.

### Concrete ownership decision

There are two breakpoint-visible triggers (`#workspace-utilities-trigger` at ≥768px and `#dropdownUser` inside mobile History) but **one** `#dropdown` and one Profile/Settings/Sign out list. It is a native `popover="auto"`, not another dialog, ARIA `role=menu` with missing arrow semantics, Flowbite dropdown or custom focus trap. Ordinary links use normal Tab navigation. Remove signed-in `data-dropdown-toggle`/placement attributes so Flowbite cannot also own it; do not change global Flowbite imports or other dropdowns.

Keep the single menu initially in a shell home outside the closed History dialog. Before mobile opening, move **only that menu** into the invoking `dialog:modal`: an otherwise external popup would be natively inert. After hiding, return it home. Never reparent editor/history/message/stream nodes or duplicate IDs/preferences. `chat-dialog` alone continues to call `showModal()` and restore modal focus. Use native Popover Escape/outside dismissal, plus bounded opener restoration and cache/breakpoint cleanup; no document-level key trap.

- [ ] **Step 1: Add signed-in/public request REDs.**

Append to `OrbiteShellTest`:

```ruby
test "one user popover has distinct breakpoint triggers and no Flowbite owner" do
  [ accounts_path, new_chat_path, chat_path(@chat) ].each do |path|
    get path
    assert_response :success
    assert_select "#orbite-shell[data-controller~=user-menu]", count: 1
    assert_select "#workspace-utilities-trigger[aria-controls=dropdown][aria-expanded=false][data-action='user-menu#toggle']", count: 1
    assert_select "#workspace-utilities-trigger[aria-controls=chat-history]", count: 0
    assert_select "#dropdownUser[aria-controls=dropdown][aria-expanded=false]", count: 1
    assert_select "#dropdown[popover=auto][data-user-menu-target=menu]", count: 1
    assert_select "#workspace-user-menu-home > #dropdown", count: 1
    assert_select "[data-dropdown-toggle=dropdown], #dropdown[role=menu], #dropdown [role=menuitem]", count: 0
    assert_select "#dropdown a[href='#{profile_path}']", count: 1
    assert_select "#dropdown a[href='#{settings_path}']", count: 1
    assert_select "#dropdown a[href='#{logout_path}'][data-turbo-method=delete]", count: 1
    assert_select "#language_preference_locale, #theme-toggle", count: 2
  end
  delete logout_path
  get root_path
  assert_select "#dropdown, #dropdownUser, #workspace-utilities-trigger, [data-controller~=user-menu]", count: 0
  assert_select "#language_preference_locale, #theme-toggle", count: 2
end
```

- [ ] **Step 2: Prepare the new browser file and run its missing-behavior RED before production edits.**

Create this full test class. It uses local fixture records and real native clicks/keys; the replacement-trigger stream is explicitly a local DOM-lifecycle fixture, not a worker broadcast or private controller write:

```ruby
require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class OrbiteNavigationRefinementsSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include OrbiteBrowserChecks

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_button "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(*@original_size)
  end

  %w[en fr].product([false, true], [[375, 812], [768, 1024], [1400, 1000], [812, 375]]).each do |locale, dark, (width, height)|
    test "direct user menu in #{locale} #{dark ? 'dark' : 'light'} at #{width}x#{height}" do
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      [ accounts_path, new_chat_path(account_id: @second.id), chat_path(@chat) ].each do |path|
        visit path
        orbite_theme(dark)
        assert_selector "html[lang=#{locale}]"
        states = width >= 1280 && path != accounts_path ? [true, false] : [false]
        states.each do |expanded|
          if width >= 1280 && path != accounts_path && !expanded
            find("#workspace-history-rail-trigger").click
          end
          before = page.evaluate_script("({open: document.querySelector('#chat-history').open, expanded: document.querySelector('#orbite-shell').dataset.orbiteHistoryExpanded})")
          opener = width >= 768 ? "#workspace-utilities-trigger" : "#dropdownUser"
          orbite_open_utilities if width < 768
          orbite_tab_to(opener)
          page.driver.browser.action.send_keys(:enter).perform
          assert_selector "#dropdown:popover-open"
          assert_selector "#{opener}[aria-expanded=true]"
          assert_selector "#dropdown a[href='#{profile_path}']:focus"
          assert_selector "#dropdown", count: 1, visible: :all
          assert_selector "#dropdownUser", count: 1, visible: :all
          sample = refinement_menu_geometry(opener)
          orbite_record("direct-user-menu", sample, screenshot: true)
          assert_operator sample.fetch("menu").fetch("bottom"), :<=, sample.fetch("opener").fetch("top") - 7
          assert_operator sample.fetch("menu").fetch("left"), :>=, 8
          assert_operator sample.fetch("menu").fetch("right"), :<=, width - 8
          assert_operator sample.fetch("menu").fetch("top"), :>=, 8
          assert_operator sample.fetch("menu").fetch("bottom"), :<=, height - 8
          assert sample.fetch("sameModal"), sample.to_json
          [profile_path, settings_path, logout_path].each do |destination|
            selector = "#dropdown a[href='#{destination}']"
            bounds = orbite_tab_to(selector)
            assert_operator bounds.fetch("height"), :>=, 44
            assert_operator bounds.fetch("width"), :>=, 44
          end
          page.driver.browser.action.send_keys(:escape).perform
          assert_no_selector "#dropdown:popover-open"
          assert_selector "#{opener}[aria-expanded=false]:focus"
          if width >= 768
            assert_equal before, page.evaluate_script("({open: document.querySelector('#chat-history').open, expanded: document.querySelector('#orbite-shell').dataset.orbiteHistoryExpanded})")
            assert_no_selector "dialog:modal"
          else
            assert_selector "#chat-history:modal"
            assert_selector "dialog:modal", count: 1
            page.driver.browser.action.send_keys(:escape).perform
            assert_no_selector "#chat-history:modal"
            assert_no_selector "#dropdown:popover-open"
          end
        end
      end
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "rail pointer opens directly outside dismisses and real profile settings links navigate" do
    orbite_viewport(768, 1024)
    visit accounts_path
    find("#workspace-utilities-trigger").click
    assert_selector "#dropdown:popover-open"
    assert_no_selector "#chat-history[open]", visible: :all
    find("main h1").click
    assert_no_selector "#dropdown:popover-open"
    assert_selector "#workspace-utilities-trigger[aria-expanded=false]"
    [ [profile_path, ".n-profile"], [settings_path, "[data-settings-workspace]"] ].each do |destination, marker|
      find("#workspace-utilities-trigger").click
      assert_selector "#dropdown:popover-open"
      find("#dropdown a[href='#{destination}']").click
      assert_current_path destination
      assert_selector marker
      assert_no_selector "#dropdown:popover-open"
      assert_no_selector "dialog:modal"
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "popover closes on breakpoint changes modal closure and Turbo caching without hidden focus" do
    orbite_viewport(375, 812)
    visit chat_path(@chat)
    orbite_open_utilities
    find("#dropdownUser").click
    assert_selector "#chat-history:modal #dropdown:popover-open"
    find("#workspace-navigation-close").click
    assert_no_selector "#dropdown:popover-open"
    assert_no_selector "dialog:modal"
    assert page.evaluate_script("document.activeElement.checkVisibility() && !document.activeElement.closest('[inert]')")
    orbite_viewport(768, 1024)
    find("#workspace-utilities-trigger").click
    assert_selector "#dropdown:popover-open"
    orbite_viewport(375, 812)
    assert_no_selector "#dropdown:popover-open"
    assert page.evaluate_script("document.activeElement.checkVisibility() && !document.activeElement.closest('[inert]')")
    orbite_viewport(768, 1024)
    find("#workspace-utilities-trigger").click
    assert_selector "#dropdown:popover-open"
    leaving_url = page.current_url
    page.execute_script(<<~JS)
      document.addEventListener('turbo:before-cache', () => {
        sessionStorage.setItem('orbite-refinement-cached-popovers', JSON.stringify({
          url: location.href, count: document.querySelectorAll(':popover-open').length
        }))
      }, { once: true })
    JS
    find("#dropdown a[href='#{settings_path}']").click
    assert_current_path settings_path
    page.go_back
    assert_current_path chat_path(@chat)
    receipt = page.evaluate_script("JSON.parse(sessionStorage.getItem('orbite-refinement-cached-popovers'))")
    assert_equal leaving_url, receipt.fetch("url")
    assert_equal 0, receipt.fetch("count")
    assert_no_selector "#dropdown:popover-open"
    assert_selector "[aria-controls=dropdown][aria-expanded=false]", count: 2, visible: :all
    assert_selector "#workspace-user-menu-home > #dropdown", count: 1, visible: :all
    assert page.evaluate_script("document.activeElement.checkVisibility() && !document.activeElement.closest('[inert]')")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "actual background scroll closes the anchored menu without interfering with its own scrollport" do
    orbite_viewport(812, 375)
    visit accounts_path
    # Geometry-only overflow to make the actual background scrollport movable.
    page.execute_script(<<~JS)
      const tail = document.createElement('div')
      tail.dataset.refinementBackgroundOverflow = 'geometry-only'
      tail.inert = true
      tail.style.cssText = 'height:2200px;flex:none'
      document.querySelector('[data-application-scroll]').append(tail)
    JS
    orbite_tab_to("#workspace-utilities-trigger")
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "#dropdown:popover-open"
    page.execute_script("document.querySelector('[data-application-scroll]').scrollTop = 100")
    assert_no_selector "#dropdown:popover-open"
    assert_operator page.evaluate_script("document.querySelector('[data-application-scroll]').scrollTop"), :>, 0
    assert_selector "#workspace-utilities-trigger[aria-expanded=false]:focus"
    assert_no_selector "dialog:modal"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "open popover returns to the current streamed rail opener not its detached predecessor" do
    orbite_viewport(768, 1024)
    visit accounts_path
    orbite_tab_to("#workspace-utilities-trigger")
    page.driver.browser.action.send_keys(:space).perform
    assert_selector "#dropdown:popover-open"
    page.execute_script(<<~JS)
      const trigger = document.querySelector('#workspace-utilities-trigger')
      window.refinementOldOpener = trigger
      Turbo.renderStreamMessage(`<turbo-stream action="replace" target="workspace-utilities-trigger"><template>${trigger.outerHTML}</template></turbo-stream>`)
    JS
    assert_selector "#workspace-utilities-trigger[aria-expanded=true]"
    refute page.evaluate_script("window.refinementOldOpener.isConnected")
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#dropdown:popover-open"
    assert_selector "#workspace-utilities-trigger:focus"
    orbite_assert_reachable("#workspace-utilities-trigger")
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  private
    def refinement_menu_geometry(opener)
      page.evaluate_script(<<~JS, opener)
        (() => {
          const menu = document.querySelector('#dropdown'), trigger = document.querySelector(arguments[0])
          const modal = document.querySelector('dialog:modal')
          return { menu: menu.getBoundingClientRect().toJSON(), opener: trigger.getBoundingClientRect().toJSON(),
            sameModal: !modal || modal.contains(menu), active: document.activeElement.id,
            menuCount: document.querySelectorAll('#dropdown').length }
        })()
      JS
    end
end
```

The URL-keyed `sessionStorage` receipt is a test-only observation of the actual before-cache event, not production menu/draft storage and not a supplied zero. Both the returned snapshot's closed/unique state and the actual observed zero must pass; do not infer success from installing the listener.

Run request RED `/one_user_popover/` and browser RED `/direct_user_menu|rail_pointer/` with `nav_record`, mandatory cwd/preamble. Expect wrong rail behavior/missing popover. Do not run the broad old profile matrix against knowingly incompatible helper bytes and mistake that for the new behavior's RED.

- [ ] **Step 3: Implement one menu and two correctly named triggers.**

In the shell, add `user-menu` to `data-controller`, `data-user-menu-chat-dialog-outlet="#orbite-shell"`, and these actions **before** the existing matching cache/render actions so a menu closes before snapshot/modal cleanup:

```text
turbo:before-visit@document->user-menu#beforeVisit
turbo:before-cache@document->user-menu#beforeCache
turbo:before-render@document->user-menu#beforeCache
resize@window->user-menu#layout
scroll->user-menu#scrolled:capture
```

Change the rail utility button (same ID and class) to:

```erb
<button id="workspace-utilities-trigger" type="button" class="n-orbite-control n-orbite-utilities-trigger"
        aria-controls="dropdown" aria-expanded="false" data-user-menu-target="trigger" data-action="user-menu#toggle">
  <%= inline_svg "svg/user-circle.svg", aria_hidden: true, class: "h-5 w-5" %>
  <span class="sr-only"><%= t("nosia.nav.open_user_menu") %></span>
</button>
```

Do not give an ordinary link-list popup `aria-haspopup=menu` or `aria-haspopup=dialog`. Its controls/expanded relationship and native popover semantics are sufficient. On the History dialog prepend `close->user-menu#panelClosed` to its existing close actions; keep `aria-labelledby` and all existing modal actions.

Immediately after `</dialog>` and before the unchanged `main`, add:

```erb
<div id="workspace-user-menu-home" data-user-menu-target="home">
  <%= render "application/orbite_user_menu" %>
</div>
```

Keep `_orbite_utilities.html.erb`'s language render and theme button **byte-for-byte**, replacing only its entire `if Current.user` block with:

```erb
<% if Current.user %>
  <button id="dropdownUser" type="button" aria-controls="dropdown" aria-expanded="false"
          data-user-menu-target="trigger" data-action="user-menu#toggle"
          class="n-nav-link n-main-hover n-orbite-mobile-only flex shrink-0 rounded-full">
    <span class="sr-only"><%= t("nosia.nav.open_user_menu") %></span>
    <%= inline_svg "svg/user-circle.svg", aria_hidden: true, class: "w-6 h-6" %>
  </button>
<% end %>
```

New `_orbite_user_menu.html.erb` moves, rather than duplicates, the current actions:

```erb
<div id="dropdown" popover="auto" class="n-orbite-user-menu" data-user-menu-target="menu"
     data-action="beforetoggle->user-menu#beforeToggle toggle->user-menu#toggled">
  <ul aria-labelledby="workspace-utilities-trigger" class="n-dropdown-list">
    <li><%= link_to profile_path, class: "group n-dropdown-item n-main-hover n-main-focus" do %>
      <%= inline_svg "svg/identification.svg", aria_hidden: true, class: "w-6 h-6" %>
      <span><%= t("nosia.nav.user_info") %></span>
    <% end %></li>
    <li><%= link_to settings_path, class: "group n-dropdown-item n-main-hover n-main-focus" do %>
      <%= inline_svg "svg/cog.svg", aria_hidden: true, class: "w-6 h-6" %>
      <span><%= t("nosia.nav.settings") %></span>
    <% end %></li>
    <li><%= link_to logout_path, data: { turbo_method: :delete }, title: t("nosia.nav.sign_out"), class: "group n-dropdown-item n-main-hover n-main-focus" do %>
      <%= inline_svg "svg/power.svg", aria_hidden: true, class: "w-6 h-6" %>
      <span><%= t("nosia.nav.sign_out") %></span>
    <% end %></li>
  </ul>
</div>
```

The shell is signed-in-only; public rendering still emits only the unchanged language/theme bytes. No menu is rendered in the public header. Delete only `workspace_navigation_controller.js#utilities`; no remaining action may reference it. Retain navigation's expansion intent, breakpoint calculations, fallback and modal ownership unchanged.

- [ ] **Step 4: Add the focused controller and scoped popup styles.**

Create `user_menu_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["home", "menu", "trigger"]
  static outlets = ["chat-dialog"]

  connect() {
    this.observer = new MutationObserver(() => this.checkOpener())
    this.observer.observe(this.element, { childList: true, subtree: true, attributes: true, attributeFilter: ["open"] })
    this.reflect(false)
  }

  disconnect() {
    this.observer.disconnect()
    this.close(false)
  }

  triggerTargetConnected(trigger) {
    trigger.setAttribute("aria-expanded", String(this.open && trigger.id === this.opener?.id))
  }

  get open() {
    return this.hasMenuTarget && this.menuTarget.matches(":popover-open")
  }

  toggle(event) {
    event.preventDefault()
    const opener = event.currentTarget
    if (this.open && this.opener?.id === opener.id) this.close(true)
    else {
      this.close(false)
      this.opener = opener
      this.openerId = opener.id
      const modal = opener.closest("dialog:modal")
      ;(modal || this.homeTarget).append(this.menuTarget)
      this.menuTarget.querySelector("ul").setAttribute("aria-labelledby", opener.id)
      this.menuTarget.showPopover({ source: opener })
      this.position()
      this.reflect(true)
      if (this.open) this.menuTarget.querySelector("a").focus({ preventScroll: true })
    }
  }

  position() {
    if (!this.open || !this.currentOpener()) return

    const box = this.opener.getBoundingClientRect(), gap = 8
    this.menuTarget.style.maxHeight = `${Math.max(0, box.top - gap * 2)}px`
    const menu = this.menuTarget.getBoundingClientRect()
    this.menuTarget.style.left = `${Math.max(gap, Math.min(box.left, innerWidth - menu.width - gap))}px`
    this.menuTarget.style.top = `${Math.max(gap, box.top - menu.height - gap)}px`
  }

  currentOpener() {
    if (!this.opener?.isConnected && this.openerId) this.opener = document.getElementById(this.openerId)
    return this.hasChatDialogOutlet && this.chatDialogOutlet.focusable(this.opener) ? this.opener : null
  }

  checkOpener() {
    if (!this.open) return

    const opener = this.currentOpener(), modal = this.element.querySelector("dialog:modal")
    if (!opener || (modal && !modal.contains(this.menuTarget)) ||
        (this.menuTarget.closest("dialog") && !this.menuTarget.closest("dialog").matches(":modal"))) this.close(true)
    else {
      this.reflect(true)
      this.position()
    }
  }

  beforeToggle(event) {
    if (event.newState === "closed") this.restoreAfterHide = this.menuTarget.contains(document.activeElement)
  }

  toggled() {
    if (!this.open && this.openerId) this.finish(this.restoreAfterHide)
  }

  close(restore = true) {
    if (!this.hasMenuTarget) return

    const inside = this.menuTarget.contains(document.activeElement)
    if (this.open) this.menuTarget.hidePopover()
    this.finish(restore && inside)
  }

  finish(restore) {
    const opener = this.currentOpener()
    this.reflect(false)
    if (restore && this.hasChatDialogOutlet) {
      const fallback = [
        this.element.querySelector("#workspace-history-rail-trigger"),
        this.element.querySelector("[data-orbite-composer-navigation]"),
        this.element.querySelector("#workspace-mobile-trigger"), this.element
      ].find(element => this.chatDialogOutlet.focusable(element))
      ;(opener || fallback)?.focus({ preventScroll: true })
    }
    if (this.hasHomeTarget && this.menuTarget.parentElement !== this.homeTarget) this.homeTarget.append(this.menuTarget)
    this.opener = null
    this.openerId = null
    this.restoreAfterHide = false
  }

  reflect(open) {
    this.triggerTargets.forEach(trigger => trigger.setAttribute("aria-expanded", String(open && trigger.id === this.openerId)))
  }

  layout() {
    this.close(true)
  }

  scrolled(event) {
    if (this.open && !this.menuTarget.contains(event.target)) this.close(true)
  }

  panelClosed(event) {
    if (event.target.contains(this.menuTarget)) this.close(false)
  }

  beforeVisit(event) {
    if (!event.defaultPrevented) this.close(false)
  }

  beforeCache() {
    this.close(false)
  }
}
```

This is intentionally larger than a trivial Stimulus controller because it contains the one native popup's lifecycle, modal-safe home and actual-opener geometry—not a new positioning framework. `showPopover({ source: opener })` uses the installed platform, without requiring a new library/browser. Validate native Escape/outside ordering against the actual installed Chromium. Do not claim that syntax support proves browser behavior, or add a second modal if integration fails. Any failure gets a bounded browser RED/correction and review, not a package upgrade or hidden focus workaround.

Do not observe every attribute or listen to global focus/key events. The observer handles actual trigger replacement and native dialog `open` changes; resize closes rather than chasing a moving viewport. A captured scroll within the shell closes the popup if its anchor/background moves; the popup's own bounded content still scrolls normally. Menu reparenting remains entirely inside the same Stimulus shell. Native dismissal only restores an opener when focus was actually inside the dismissed menu; intentional outside focus is not stolen. A closing History delegates return focus to `chat-dialog`, via `panelClosed(false)`.

Add to `orbite_shell.css`:

```css
#workspace-user-menu-home { display: contents; }
.n-orbite-shell .n-orbite-user-menu {
  position: fixed; inset: auto; margin: 0; box-sizing: border-box;
  width: min(20rem, calc(100vw - 1rem)); min-width: 0;
  max-height: calc(100dvh - 1rem); overflow: auto; overscroll-behavior: contain;
  padding: 0; border: 1px solid var(--orbite-control); border-radius: .75rem;
  background: var(--orbite-paper); color: var(--orbite-text);
  box-shadow: 0 4px 22px rgb(0 0 0 / .12);
}
.n-orbite-shell .n-orbite-user-menu:not(:popover-open) { display: none; }
.n-orbite-shell .n-orbite-user-menu .n-dropdown-list { color: inherit; }
.n-orbite-shell .n-orbite-user-menu .n-dropdown-item {
  min-height: 44px; min-width: 44px; overflow-wrap: anywhere; white-space: normal;
}
```

The top layer escapes rail overflow without changing the rail's scrollport or absolute-positioning against the panel. Existing mobile-only selectors hide the mobile trigger ≥768 and show it below that breakpoint; there are no duplicate interactive IDs or new copies of preferences.

- [ ] **Step 5: Separate navigation/preferences helpers from user-action helpers atomically.**

Replace `OrbiteBrowserChecks#orbite_open_utilities` with the following. It opens **navigation** for language/theme; the profile-only rail user button is no longer a preference opener:

```ruby
def orbite_open_utilities
  return if page.has_selector?("#theme-toggle", wait: 0)

  selectors = if page.evaluate_script("innerWidth >= 768")
    [ "#workspace-history-rail-trigger", "#workspace-history-trigger" ]
  else
    [ "[data-orbite-composer-navigation]", "#workspace-mobile-trigger", "#workspace-history-trigger" ]
  end
  opener = selectors.filter_map { |selector| first(selector, minimum: 0, wait: 0) }.first
  assert opener, "No visible navigation/preference opener"
  opener.click
  assert_selector "#theme-toggle"
end

def orbite_user_menu_trigger
  if page.evaluate_script("innerWidth >= 768")
    "#workspace-utilities-trigger"
  else
    orbite_open_utilities
    "#dropdownUser"
  end
end

def orbite_open_user_menu(keyboard: false)
  selector = orbite_user_menu_trigger
  if keyboard
    orbite_tab_to(selector)
    page.driver.browser.action.send_keys(:enter).perform
  else
    find(selector).click
  end
  assert_selector "#dropdown:popover-open"
  assert_selector "#{selector}[aria-expanded=true]"
  selector
end
```

Keep `orbite_with_utilities`, `orbite_select_language`, `orbite_theme`, `orbite_tab_to` and their native form/theme behavior unchanged. Do not change a real Profile click into `visit profile_path` or select a hidden preference just to avoid opening navigation.

Apply this precise caller inventory before B's broad GREEN:

| File / case | Replacement | Preserve |
| --- | --- | --- |
| `test/system/account_experience_test.rb:256–257` profile entry; `test/system/orbite_workspace_test.rb:226–227` and its bottom utility case | Replace `orbite_open_utilities; find("#dropdownUser").click` with `orbite_open_user_menu` | The actual Profile/Settings destination click, account/default assertions and locale/theme |
| `test/system/compact_headers_test.rb:1069–1071` logout | `orbite_open_user_menu; find("#dropdown a[href='#{logout_path}']").click` | Real DELETE sign out and subsequent sign-in with the other role |
| `test/system/orbite_workspace_test.rb:623–640` bottom utility matrix | `opener = orbite_open_user_menu`; assert `#dropdown:popover-open`; close via `find(opener).click`; assert no open popover, then close navigation only if modal | All three actual action hit tests, both themes, screenshots, no jobs |
| `test/system/orbite_workspace_test.rb:644–663` mobile French/native Profile | Keep navigation opening, native Tab to `#dropdownUser`, Enter, native Tab/Enter to Profile; assert `#dropdown:popover-open` | One modal, FR dark, actual route and profile heading |
| `test/system/compact_headers_test.rb:65–84` native utility sizing | Use the two-phase replacement case below: panel preferences first, then the visible rail user button after closing a tablet modal | Every 44px dimension and actual hit test; never measure an inert rail button through an open modal |
| `test/system/compact_headers_test.rb:87–124` native language/theme/Profile matrix | Native Tab through visible panel Home/language/theme, then `trigger = orbite_user_menu_trigger; header_tab_to(trigger); Enter`; expect open popover, Tab/Enter Profile | All viewport/locale/theme loops, real route, persisted native preferences, screenshot |
| All `#dropdown:not(.hidden)` browser assertions | `#dropdown:popover-open` | Actual visibility/keyboard path, not `visible: :all` substituting for an open popup |

For the panel Profile case, use this exact replacement interaction block after native theme traversal:

```ruby
trigger = orbite_user_menu_trigger
header_tab_to(trigger)
page.driver.browser.action.send_keys(:enter).perform
assert_selector "#dropdown:popover-open"
header_tab_to("#dropdown a[href='#{profile_path}']")
page.driver.browser.action.send_keys(:enter).perform
assert_current_path profile_path
assert_selector ".n-profile"
```

On desktop this case has deliberately opened History for native preferences, making the rail inert until that modal closes. Therefore call `orbite_close_navigation` **after** native theme traversal and **before** `header_tab_to(trigger)` when `innerWidth >= 768` and `#chat-history:modal` is open. Do not programmatically click an inert rail button or broaden the new menu helper to open History first. On mobile leave History open so its visible trigger is invokable. Inline nonmodal History does not need closing.

Replace the complete utility-sizing case with these two legitimate visible phases:

```ruby
test "rail and native utilities retain full target sizes without an old global bar" do
  [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
    header_viewport(width, height)
    visit accounts_path
    assert_no_selector "[data-application-header], .n-nav-bottom", visible: :all
    orbite_open_utilities
    panel_controls = [ "#language_preference_locale", "#theme-toggle" ]
    panel_controls << "#dropdownUser" if width < 768
    panel_controls.each do |selector|
      sample = orbite_assert_reachable(selector)
      assert_operator sample.fetch("height"), :>=, 44, sample.to_json
      assert_operator sample.fetch("width"), :>=, 44, sample.to_json
    end
    header_record("orbite-panel-targets-#{width}x#{height}", header_matrix_geometry, screenshot: true)
    orbite_close_navigation
    if width >= 768
      header_tab_to("#workspace-utilities-trigger")
      sample = orbite_assert_reachable("#workspace-utilities-trigger")
      assert_operator sample.fetch("height"), :>=, 44, sample.to_json
      assert_operator sample.fetch("width"), :>=, 44, sample.to_json
      header_record("orbite-rail-user-target-#{width}x#{height}", sample, screenshot: true)
    end
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

Add inside `CompactHeadersSystemTest` a popup contrast/long-label case using its existing painter:

```ruby
test "user popover labels strokes focus and long localized actions remain readable" do
  %w[en fr].each do |locale|
    orbite_select_language(locale.upcase)
    [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
      header_viewport(width, height)
      visit accounts_path
      [ false, true ].each do |dark|
        # Reload native translated labels before applying this iteration's
        # explicitly enlarged-label geometry fixture; never multiply an old fixture.
        visit accounts_path
        header_theme(dark)
        opener = orbite_open_user_menu(keyboard: true)
        [profile_path, settings_path, logout_path].each do |destination|
          selector = "#dropdown a[href='#{destination}']"
          header_tab_to(selector)
          header_contrast("#{selector} span")
          header_icon_stroke(selector)
          header_contrast(selector, minimum: 3, property: "outlineColor")
        end
        # Labelled adversarial geometry, not a claim about untranslated copy.
        page.execute_script(<<~JS)
          document.querySelectorAll('#dropdown a span').forEach(span => {
            span.dataset.refinementLongLabel = 'geometry-only'
            span.textContent = Array(5).fill(span.textContent).join(' ')
          })
        JS
        header_settle
        assert_header_widths
        sample = page.evaluate_script(<<~JS)
          (() => {
            const menu = document.querySelector('#dropdown')
            return { geometryOnly: true, menu: menu.getBoundingClientRect().toJSON(),
              clientWidth: menu.clientWidth, scrollWidth: menu.scrollWidth,
              textFits: [...menu.querySelectorAll('a')].every(link => {
                const range = document.createRange(); range.selectNodeContents(link.querySelector('span'))
                const box = link.getBoundingClientRect()
                return [...range.getClientRects()].every(line => line.left >= box.left - 1 && line.right <= box.right + 1)
              }) }
          })()
        JS
        assert_operator sample.fetch("scrollWidth"), :<=, sample.fetch("clientWidth"), sample.to_json
        assert sample.fetch("textFits"), sample.to_json
        [profile_path, settings_path, logout_path].each do |destination|
          orbite_tab_to("#dropdown a[href='#{destination}']")
        end
        orbite_record("user-menu-long-localized-label-geometry-only", sample, screenshot: true)
        page.driver.browser.action.send_keys(:escape).perform
        assert_selector "#{opener}:focus"
        orbite_close_navigation
      end
    end
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

The `header_icon_stroke` helper from A checks every actual identification/cog/power path's computed stroke/opacity/fill, then measures that proven-identical SVG color against the opaque backing. Keep the compositor's opaque surface/error checks and all separate native control hit tests. Do not report a border contrast measurement as glyph contrast. The new popup has the shell's opaque paper backing even when moved into a native dialog.

- [ ] **Step 6: Run complete B gates and review before committing.**

After the source-specific safety audit is refreshed, run with mandatory cwd/preamble/recorder:

```bash
nav_record orbite-refinement-B-build rails_test tailwindcss:build || exit $?
nav_record orbite-refinement-B-requests rails_test test test/integration/orbite_shell_test.rb test/controllers/chat_account_access_test.rb || exit $?
nav_record orbite-refinement-B-browser browser_test test/system/orbite_navigation_refinements_test.rb test/system/orbite_workspace_test.rb test/system/account_experience_test.rb test/system/localization_test.rb test/system/color_theme_test.rb || exit $?
nav_record orbite-refinement-B-native-profile browser_test test/system/compact_headers_test.rb -i '/panel_controls_retain|rail_and_native_utilities|user_popover_labels|account_uid_and_viewer_role/' || exit $?
nav_record orbite-refinement-B-js node --input-type=module --check < app/javascript/controllers/user_menu_controller.js || exit $?
nav_record orbite-refinement-B-navigation-js node --input-type=module --check < app/javascript/controllers/workspace_navigation_controller.js || exit $?
nav_record orbite-refinement-B-rubocop test_command bundle exec rubocop test/support/orbite_browser_checks.rb test/integration/orbite_shell_test.rb test/system/orbite_navigation_refinements_test.rb test/system/orbite_workspace_test.rb test/system/compact_headers_test.rb test/system/account_experience_test.rb || exit $?
git diff --check
git add -- app/javascript/controllers/user_menu_controller.js app/javascript/controllers/workspace_navigation_controller.js app/views/application/_orbite_user_menu.html.erb app/views/application/_orbite_utilities.html.erb app/views/application/_orbite_shell.html.erb app/assets/stylesheets/nosia/orbite_shell.css test/support/orbite_browser_checks.rb test/integration/orbite_shell_test.rb test/system/orbite_navigation_refinements_test.rb test/system/orbite_workspace_test.rb test/system/compact_headers_test.rb test/system/account_experience_test.rb
git commit -m "feat(ui): Open the user menu directly from its visible trigger"
```

Record actual above-opener geometry and hit samples at 768×1024 on a non-chat page with closed History, plus wide saved/new History expanded and collapsed. Require first Escape to close only the mobile popover, second Escape to close History, correct expanded state, no hidden/inert focus after modal close/resize/Back, one native dialog owner and one menu ID. Exercise pointer, Enter and Space without synthetic key events. Check the cached-zero receipt, streamed opener replacement, real Profile/Settings clicks and existing real Sign out coverage. SPEC then QUALITY, with no Important/Critical open findings, precede C.

## Task C: Put useful context below h1 and keep the complete live Usage section visible

**Production files:** `app/views/workspaces/_header.html.erb`; `app/views/chats/_header.html.erb`; `app/views/dashboards/show.html.erb`; `app/views/accounts/index.html.erb`, `settings/show.html.erb`, `profiles/show.html.erb`, `sources/index.html.erb`, `agent_skills/index.html.erb`, `mcp_servers/index.html.erb`, `mcp_servers/new.html.erb`, `mcp_servers/edit.html.erb`, `token_usages/show.html.erb`; `app/assets/stylesheets/nosia/application_shell.css`, `orbite_chat.css`.

**Request tests:** `test/integration/compact_headers_test.rb`, `chat_message_rendering_test.rb`; `test/controllers/chat_workspace_test.rb`, `accounts_workspace_shell_test.rb`. Keep existing source/usage/MCP/profile/skills controller tests in GREEN coverage; they need no production controller edit.

**Browser migrations in the same commit:** `test/system/compact_headers_test.rb`, `chat_workspace_test.rb`, `accounts_settings_workspace_test.rb`, `mcp_workspace_test.rb`, `profile_management_test.rb`, `account_experience_test.rb`, `dashboard_test.rb`, `agent_skills_workspace_test.rb`, `sources_workspace_test.rb`, `token_usage_workspace_test.rb`. Live-Usage coverage stays with the existing reader/accounting fixture owners; the new B browser file remains menu-focused. Mutation ownership is only obsolete header-disclosure setup/assertions and the explicitly mapped timing fixtures, not unrelated workflows.

### Exact copy decisions (both existing locales, no raw replacement copy)

| Existing header string / source | Decision | Reason and remaining content |
| --- | --- | --- |
| Dashboard `nosia.dashboard.title` paragraph and `nosia.dashboard.introduction` | Remove these two rendered paragraphs and their details wrapper; keep `content_for :title` and welcome h1 | Repeats dashboard identity and visible composer/recent shortcuts |
| `nosia.accounts_workspace.description` | Remove `description:` from accounts index header invocation | Generic directory instruction; account cards/actions remain |
| `nosia.settings.description` | Remove header argument | Four setting cards retain their specific descriptions and actions |
| `nosia.profile.introduction` | Remove header argument | Generic manage-credentials wording; actual secure email/password guidance and confirmation remain |
| `nosia.sources_workspace.description` | Remove sources index header argument | Generic manage-knowledge wording; actual account scope, privacy/empty/error/index guidance remain |
| `nosia.skills_workspace.description` | Remove skills index header argument | Generic manage-instructions wording; availability/counts/empty help stay |
| `nosia.mcp_workspace.description` | Remove servers index header argument | Generic manage-tools wording; scope/status/transport/resource/security guidance stay |
| `nosia.mcp.new_help`, `nosia.mcp.edit_help` | Remove new/edit header description arguments | Generic connect/update wording; actual form labels, transport constraints and credential guidance stay |
| `nosia.usage_workspace.purpose` | Remove header argument | Generic accounting purpose; account/global scope and real estimate/methodology guidance stay |
| `nosia.sources_workspace.form_description` | **Retain inline** through shared header | Unique account-default nonmutation guidance, not just a title restatement |
| `nosia.mcp.catalog_help` | **Retain inline** | Specifies predefined activation behavior, distinct from title and navigation |
| `catalog_entry_description(@template)` | **Retain inline**, escaped by normal ERB | Actual tool/integration purpose, not generic page metadata |
| All `scope_label`, account UID/role labels, trail labels/URLs, return links and action URLs | **Retain inline or in existing actions** | Operational identity and authorized destinations |
| Chat account preview/full name, Usage h2, live totals/table/estimates/fallback notes | **Retain visibly below title**, no details | Approved discoverable live accounting |
| New-chat `nosia.chat_workspace.new_help`, no-account/setup/source-error/privacy/card guidance | **Retain in existing content** | Not a header accordion; real contextual instructions |

Do not delete translation keys/catalog entries in this task: the change is what headers render, not catalog pruning. Use existing EN/FR `t(...)` calls for all retained text. No unrelated copy audit or deletion of substantive operational/safety content.

- [ ] **Step 1: Add request REDs for ordinary context and complete visible accounting.**

Replace `CompactHeadersTest`'s `page heading discloses secondary description and breadcrumb` test with:

```ruby
test "page heading exposes useful trail without a redundant profile description" do
  %i[en fr].each do |locale|
    get profile_path, headers: { "Accept-Language" => locale.to_s }
    assert_response :success
    assert_select ".n-workspace-header h1", text: I18n.t("nosia.profile.title", locale: locale), count: 1
    assert_select ".n-workspace-header details, .n-header-details, [data-header-details]", count: 0
    assert_select ".n-workspace-header .n-workspace-context nav[aria-label='#{I18n.t('nosia.workspace.breadcrumb', locale: locale)}'] .n-workspace-trail", count: 1
    assert_select ".n-workspace-header p", text: I18n.t("nosia.profile.introduction", locale: locale), count: 0
    assert_select ".n-workspace-actions .n-workspace-trail", count: 0
    assert_select "#profile-email-form, #profile-password-form", count: 2
  end
end

test "saved Usage is a labelled visible section with the exact live accounting subtree" do
  %i[en fr].each do |locale|
    get chat_path(@chat), headers: { "Accept-Language" => locale.to_s }
    assert_response :success
    assert_select ".n-chat-header > section#chat-usage-details[aria-labelledby=chat-usage-summary]", count: 1 do
      assert_select "h2#chat-usage-summary:not([tabindex])", text: I18n.t("nosia.chat_workspace.usage_details", locale: locale), count: 1
      assert_select "summary, details, [data-chat-detail], [open]", count: 0
      assert_select "##{dom_id(@chat, :token_totals)}", count: 1
      assert_select "[data-chat-total-input]", text: "125", count: 1
      assert_select "[data-chat-total-output]", text: "24", count: 1
      assert_select "table caption", text: I18n.t("nosia.usage.per_kind", locale: locale), count: 1
      assert_select "thead th[scope=col]", count: 3
      assert_select "tbody tr[data-usage-kind] th[scope=row]", minimum: 1
      assert_select "[data-estimate-note]", count: 1
    end
    assert_select ".n-chat-toolbar #chat-usage-details", count: 0
    assert_select "#application-scroll > .n-chat-header", count: 1
    assert_select ".n-chat-dock ##{dom_id(@chat, :token_totals)}", count: 0
  end
end
```

In its existing saved-toolbar test replace the old `.n-chat-toolbar #chat-usage-details:not([open])` selector with `.n-chat-header > section#chat-usage-details`; retain heading/account/action/totals assertions. Also correct its remaining **superseded Task 2 intermediate-only** chat frame selector at lines 24–27 to the approved Task 3 final placement, matching `OrbiteShellTest`:

```ruby
assert_select "main#application-page.n-chat-main .n-orbite-reading#application-scroll[data-application-scroll]", count: 1
assert_select "main[data-application-scroll], .n-orbite-chat-frame", count: 0
```

Record this as a stale intermediate-selector correction, not a new reading-surface change or a new behavior RED. The actual surface/main distinction and one-primary-surface assertions remain strict.

In `test/controllers/chat_workspace_test.rb:24`, replace the collapsed selector with:

```ruby
assert_select "section#chat-usage-details > h2#chat-usage-summary", text: "Usage details", count: 1
assert_select "#chat-usage-details summary, .n-header-details", count: 0
```

In `test/integration/chat_message_rendering_test.rb:49,289`, require `section#chat-usage-details > h2#chat-usage-summary` instead of a summary. Keep all actual localized broadcast captures, normalized per-kind counters, estimates, explicit render locals, targets and accounting/source guards. In `AccountsWorkspaceShellTest`, replace each expected closed header details with `assert_select ".n-workspace-header details, [data-header-details]", count: 0` and require its existing trail under `.n-workspace-context`; replace the directory's description assertion with:

```ruby
assert_select ".n-workspace-header p", text: I18n.t("nosia.accounts_workspace.description", locale: locale), count: 0
assert_select ".n-workspace-context .n-workspace-trail", count: 1
```

Before production edits run the new request cases and the newly rewritten browser context/accounting cases below, with mandatory cwd/preamble/recorder. Expected RED: section/visible context absent or redundant generic copy still present. Existing accounting targets should continue to characterize PASS.

- [ ] **Step 2: Replace the generic header markup, dashboard redundancy and enumerated caller arguments.**

Replace `app/views/workspaces/_header.html.erb` with this complete body:

```erb
<%# locals: (title:, description: nil, scope_label: nil, trail: [], back_path: nil, show_new_chat: false, actions: nil, breadcrumb_label: nil) %>
<% content_for :title, title %>
<header class="n-workspace-header">
  <div class="n-workspace-heading-row">
    <div class="n-workspace-heading min-w-0">
      <h1 class="n-workspace-title"><%= title %></h1>
      <% if scope_label || description.present? || trail.any? %>
        <div class="n-workspace-context">
          <% if scope_label %><p class="n-workspace-scope" data-workspace-scope><%= scope_label %></p><% end %>
          <% if description.present? %><p class="n-workspace-help"><%= description %></p><% end %>
          <% if trail.any? %>
            <nav aria-label="<%= breadcrumb_label || t('nosia.workspace.breadcrumb') %>" class="n-workspace-help">
              <ol class="n-workspace-trail !list-none">
                <% trail.each_with_index do |item, index| %>
                  <% if index.positive? %><li aria-hidden="true">/</li><% end %>
                  <%= tag.li aria: { current: item[:path] ? nil : "page" } do %>
                    <% if item[:path] %>
                      <%= link_to item.fetch(:label), item.fetch(:path), class: "n-workspace-link" %>
                    <% else %>
                      <%= item.fetch(:label) %>
                    <% end %>
                  <% end %>
                <% end %>
              </ol>
            </nav>
          <% end %>
        </div>
      <% end %>
    </div>
    <div class="n-workspace-actions">
      <% if back_path %><%= link_to t("nosia.actions.back"), back_path, class: "n-workspace-link", data: { workspace_back: true } %><% end %>
      <% if show_new_chat %>
        <div class="hidden lg:block"><%= link_to t("nosia.nav.new_chat"), new_chat_path, class: "n-workspace-link" %></div>
      <% end %>
      <%= actions %>
    </div>
  </div>
</header>
```

In `dashboards/show.html.erb` remove exactly lines 5–9 of the starting source (the entire details block); do not remove title metadata, welcome h1, composer, usage overview, shortcuts or recents.

The other caller edits are exact deletions of the `description:` argument identified in the copy table. For multiline profile/accounts/settings/usage calls remove only that argument and its comma; for one-line sources/skills/MCP calls retain every other keyword/value. For clarity the two smallest resulting header calls are:

```erb
<%= render "workspaces/header", title: t("nosia.profile.title"),
    trail: [ { label: t("nosia.nav.home"), path: user_root_path },
             { label: t("nosia.profile.title"), path: nil } ] %>
```

```erb
<%= render "agent_skills/header", title: t("nosia.skills.title"), primary: (@agent_skills.any? ? link_to(t("nosia.skills.create"), skill_workspace_new_path, class: "n-workspace-button n-workspace-primary") : nil) %>
```

Retain the original `description:` calls in `sources/_form_page.html.erb`, `mcp_catalog/index.html.erb` and `mcp_catalog/show.html.erb` unchanged: the shared partial now places them visibly beneath h1. Do not alter data, role helpers or action URLs.

- [ ] **Step 3: Replace only the Usage wrapper and style ordinary below-title context.**

In `chats/_header.html.erb`, remove the persisted `details` block from inside `.n-chat-toolbar`. Immediately after that toolbar's closing `</div>` but before `</header>`, add:

```erb
<% if chat.persisted? %>
  <section id="chat-usage-details" class="n-chat-usage" aria-labelledby="chat-usage-summary">
    <h2 id="chat-usage-summary" class="n-chat-usage-title"><%= t("nosia.chat_workspace.usage_details") %></h2>
    <p class="n-workspace-help"><%= chat.account.name %></p>
    <%= render "chats/token_totals", chat: chat %>
  </section>
<% end %>
```

The legacy IDs now name a section and its heading, not an interaction. Do not retain `data-chat-detail`, `open`, `summary`, hidden/folded behavior or tabindex on this section/heading. Keep `chats/_token_totals.html.erb` **byte-identical**: `dom_id(chat, :token_totals)`, localized dl, full per-kind live table, estimates and fallback explanation remain the actual server-rendered broadcast subtree. The header still lives inside the existing reading DIV and scrolls away, never in the dock or fixed chrome.

Replace the four `.n-header-details` CSS rules in `application_shell.css` with:

```css
.n-workspace-heading { flex: 1 1 16rem; min-width: 0; }
.n-workspace-context { min-width: 0; margin-block-start: .25rem; }
.n-workspace-context :is(p, nav) { max-inline-size: 65ch; overflow-wrap: anywhere; }
.n-workspace-context a:focus-visible { @apply outline-2 outline-offset-2 outline-green-700 dark:outline-green-300; }
```

Remove only the obsolete `.n-application-page .n-chat-header .n-chat-details[open] { flex-basis: 100%; }` rule. Add to `orbite_chat.css`:

```css
.n-orbite-shell .n-chat-usage { min-width: 0; max-width: 100%; margin-block-start: .75rem; }
.n-orbite-shell .n-chat-usage-title { font-size: .875rem; line-height: 1.5; font-weight: 600; color: var(--orbite-text); }
.n-orbite-shell .n-chat-usage > .n-workspace-help { overflow-wrap: anywhere; white-space: normal; }
```

No table-local keyboard region is added: the existing three-column Usage table is readable static data and its existing overflow wrapper remains unchanged. Chromium may naturally focus a genuinely scrollable region; do not force-focus a noninteractive heading to salvage the old summary tests.

- [ ] **Step 4: Prepare the coupled browser replacements with RED, not after the production cutover.**

The listings here belong to the initial test preparation in Step 1; their later position is explanatory, not permission to postpone them. Replace the saved-header disclosure case in `CompactHeadersSystemTest` with this ordinary-reading/draft test:

```ruby
test "saved header keeps visible complete Usage and the same native draft editor" do
  header_viewport(1400, 1000)
  visit chat_path(@chat)
  assert_selector "lexxy-editor[connected]"
  find("lexxy-editor .lexxy-editor__content").send_keys("Keep this draft while reading usage")
  page.execute_script("window.headerDraftEditor = document.querySelector('lexxy-editor')")
  header_top
  assert_selector "section#chat-usage-details > h2#chat-usage-summary", text: I18n.t("nosia.chat_workspace.usage_details")
  assert_no_selector ".n-chat-header details, .n-header-details, [data-header-details]", visible: :all
  within "section#chat-usage-details" do
    assert_selector "[data-chat-total-input]", text: "125", exact_text: true
    assert_selector "[data-chat-total-output]", text: "24", exact_text: true
    assert_selector "table caption", text: I18n.t("nosia.usage.per_kind")
    assert_selector "[data-usage-kind=completion], [data-usage-kind=embedding]", count: 2
    assert_selector "[data-estimate-note]"
    assert_text "kWh"
    assert_text "gCO₂e"
  end
  assert page.evaluate_script("window.headerDraftEditor === document.querySelector('lexxy-editor')")
  assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this draft while reading usage"
  assert_selector "##{dom_id(@chat, :token_totals)}", count: 1, visible: :all
  sample = page.evaluate_script(<<~JS)
    (() => {
      const usage = document.querySelector('#chat-usage-details'), header = document.querySelector('.n-chat-header')
      const actions = document.querySelector('.n-chat-toolbar > .n-workspace-actions')
      const surface = document.querySelector('[data-application-scroll]'), dock = document.querySelector('.n-chat-dock')
      return { naturalHeader: header.getBoundingClientRect().height,
        ownRow: usage.getBoundingClientRect().top >= actions.getBoundingClientRect().bottom,
        insideReader: surface.contains(header), headerPosition: getComputedStyle(header).position,
        surface: surface.getBoundingClientRect().toJSON(), dock: dock.getBoundingClientRect().toJSON() }
    })()
  JS
  assert sample.fetch("ownRow"), sample.to_json
  assert sample.fetch("insideReader"), sample.to_json
  refute_includes %w[fixed sticky], sample.fetch("headerPosition")
  assert_operator sample.fetch("surface").fetch("bottom"), :<=, sample.fetch("dock").fetch("top") + 1
  header_record("visible-usage-natural-height", sample, screenshot: true)
  assert_no_enqueued_jobs only: ChatResponseJob
end

test "useful page context is visible under h1 with native breadcrumb navigation" do
  %w[en fr].each do |locale|
    visit profile_path
    orbite_select_language(locale.upcase)
    assert_selector "html[lang=#{locale}]"
    header_theme(locale == "fr")
    assert_no_selector ".n-header-details, [data-header-details]", visible: :all
    trail = ".n-workspace-context nav[aria-label='#{I18n.t('nosia.workspace.breadcrumb', locale: locale)}']"
    assert_selector trail
    assert_no_selector ".n-workspace-header p", text: I18n.t("nosia.profile.introduction", locale: locale)
    home = "#{trail} a[href='#{user_root_path}']"
    header_tab_to(home)
    header_hit(home)
    page.driver.browser.action.send_keys(:enter).perform
    assert_current_path user_root_path
    assert_selector "[data-dashboard]"
    assert_no_selector ".n-dashboard-heading details, .n-dashboard-heading p", visible: :all
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

The old ≤92px **collapsed** header cap is deliberately retired: the approved full live table is now visible and must use natural height. This is not permission to remove scrolling/dock/editor-identity/one-surface assertions. Do not impose a fixed height or clip accounting to recover the old cap.

Replace `header_disclosures(index)` with `header_context(index)`, and change both call sites (`matrix` and `labelled geometry probe`) to that exact new method. Full replacement helper:

```ruby
def header_context(index)
  assert_no_selector ".n-header-details, [data-header-details]", visible: :all
  if page.has_selector?("#chat-usage-details", wait: 0)
    assert_selector "section#chat-usage-details > h2#chat-usage-summary:not([tabindex])"
    assert_no_selector "#chat-usage-details summary, #chat-usage-details[open]", visible: :all
    assert_selector "#chat-usage-details > .n-workspace-help", text: @second.name, exact_text: true
    header_tab_to(".n-chat-toolbar a[href='#{user_root_path}']")
    sample = page.evaluate_script(<<~JS)
      (() => {
        const preview = document.querySelector('[data-chat-account-label]'), full = document.querySelector('#chat-usage-details > p')
        const usage = document.querySelector('#chat-usage-details'), actions = document.querySelector('.n-chat-toolbar > .n-workspace-actions')
        const range = document.createRange(); range.selectNodeContents(full)
        const rect = full.getBoundingClientRect()
        return { preview: { geometry: preview.getBoundingClientRect().toJSON(), clientWidth: preview.clientWidth,
            scrollWidth: preview.scrollWidth, textOverflow: getComputedStyle(preview).textOverflow, whiteSpace: getComputedStyle(preview).whiteSpace },
          fullAccount: { text: full.textContent, geometry: rect.toJSON(), fits: full.scrollWidth <= full.clientWidth && [...range.getClientRects()].every(line => line.left >= rect.left - 1 && line.right <= rect.right + 1) },
          ownRow: !actions.contains(usage) && usage.getBoundingClientRect().top >= actions.getBoundingClientRect().bottom }
      })()
    JS
    assert_operator sample.fetch("preview").fetch("scrollWidth"), :>, sample.fetch("preview").fetch("clientWidth")
    assert_operator sample.fetch("preview").fetch("geometry").fetch("left"), :>=, 0
    assert_operator sample.fetch("preview").fetch("geometry").fetch("right"), :<=, page.evaluate_script("innerWidth")
    assert_equal "ellipsis", sample.fetch("preview").fetch("textOverflow")
    assert_equal "nowrap", sample.fetch("preview").fetch("whiteSpace")
    assert sample.fetch("fullAccount").fetch("fits"), sample.to_json
    assert sample.fetch("ownRow"), sample.to_json
    assert_header_widths
    header_record("matrix-visible-account-usage-#{index}", header_matrix_geometry.merge(sample), screenshot: true)
  elsif page.has_selector?(".n-workspace-context .n-workspace-trail a", wait: 0)
    link = first(".n-workspace-context .n-workspace-trail a")
    selector = ".n-workspace-context .n-workspace-trail a[href='#{URI(link[:href]).request_uri}']"
    header_tab_to(selector)
    header_hit(selector)
    assert_header_widths
    header_record("matrix-inline-context-#{index}", header_matrix_geometry, screenshot: true)
  end
  header_top
end
```

In `header_scroll_context` replace `usageOpen: usage ? usage.open : null` with `usageInline: usage ? usage.tagName === 'SECTION' && !usage.hasAttribute('hidden') : null`; in `assert_header_scroll_movement` replace only the `usageOpen` key in its contexts list with `usageInline`. Preserve exact 700px movement, 1px heading/scrollport bounds, document/body scroll values, real long-chat versus labelled synthetic-overflow distinctions.

- [ ] **Step 5: Preserve live Usage growth, totals, notes, paragraph anchors and observer coverage with actual server payloads.**

`CompactHeadersSystemTest` needs `require "turbo/broadcastable/test_helper"` and `include Turbo::Broadcastable::TestHelper` for its new local accounting-stream helper. Add:

```ruby
def header_broadcast_usage
  Current.reset
  locale = page.evaluate_script("document.documentElement.lang").to_sym
  streams = capture_turbo_stream_broadcasts([ @chat, :token_totals, locale ]) do
    TokenUsage.create!(account: @second, chat_id: @chat.id, kind: :agent_skill,
      model_id: "picker-test-model", input_tokens: 1, output_tokens: 0)
  end
  replacement = streams.find { |stream| stream["target"] == dom_id(@chat, :token_totals) }
  assert replacement, "Expected the actual localized TokenUsage replacement"
  page.execute_script("Turbo.renderStreamMessage(arguments[0])", replacement.to_html)
  assert_selector "#chat-usage-details [data-usage-kind=agent_skill]", visible: :all
  assert_selector "#chat-usage-details [data-chat-total-input]", text: "126", visible: :all
  assert_selector "#chat-usage-details [data-estimate-note]", count: 1, visible: :all
end
```

This adds a real missing per-kind row (fixtures initially contain completion and embedding), causing a measured header height increase. It does not run a worker, forge totals HTML, alter the production table or imply a provider call. One new row per test is sufficient; never use a made-up TokenUsage enum.

In `ChatWorkspaceSystemTest#paused paragraph survives compact header height changes and viewport reflow`, replace only the `open=true/false` loop with this live header-growth block, using that class's existing capture/stream helpers:

```ruby
before_height = page.evaluate_script("document.querySelector('.n-chat-header').getBoundingClientRect().height")
Current.reset
streams = capture_turbo_stream_broadcasts([ @chat, :token_totals, :en ]) do
  TokenUsage.create!(account: @second, chat_id: @chat.id, kind: :agent_skill,
    model_id: "picker-test-model", input_tokens: 1, output_tokens: 0)
end
replacement = streams.find { |stream| stream["target"] == dom_id(@chat, :token_totals) }
assert replacement, "Expected a real live accounting replacement"
stream_html(replacement.to_html)
assert_selector "#chat-usage-details [data-usage-kind=agent_skill]", visible: :all
settle_workspace_layout
after_height = page.evaluate_script("document.querySelector('.n-chat-header').getBoundingClientRect().height")
assert_operator after_height, :>, before_height
assert_reader_following false
assert_reader_anchor anchor
assert_no_button "Latest message"
assert page.evaluate_script("window.compactReaderFocus === document.activeElement")
chat_measurement("kind" => "visible-usage-real-broadcast-growth", "beforeHeight" => before_height, "afterHeight" => after_height)
```

Keep the following mobile/desktop viewport reflow loop, actual answer growth → Latest, saved answer persistence, real same-URL GET refresh, focused editor ID and strict 1px anchor assertions. Change its historical diagnostic field from `usageProgrammaticGeometryOnly` to `usageActualAccountingBroadcast`, value true; do not relabel old recorded evidence.

Add this case to `CompactHeadersSystemTest` to expose the actual ResizeObserver path, using the held-frame helper migrated in Step 6:

```ruby
test "visible Usage growth preserves a paused paragraph through the actual header observer" do
  header_prepare_paused_chat("forward")
  anchor = header_reader_anchor
  height = page.evaluate_script("document.querySelector('.n-chat-header').getBoundingClientRect().height")
  header_hold_reader_frame(".n-chat-toolbar a[href='#{user_root_path}']")
  header_broadcast_usage
  assert_operator page.evaluate_script("document.querySelector('.n-chat-header').getBoundingClientRect().height"), :>, height
  2.times { header_settle }
  page.execute_script("window.headerOrderingBoundary.release()")
  3.times { header_settle }
  sample = page.evaluate_script("window.headerOrderingBoundary.sample()")
  assert sample.fetch("trace").any? { |entry| entry["event"] == "schedule" && entry["stack"].include?("ResizeObserver") }, sample.to_json
  current = header_reader_anchor(anchor.fetch("index"))
  assert_equal anchor.fetch("text"), current.fetch("text")
  assert_in_delta anchor.fetch("offset"), current.fetch("offset"), 1
  assert_selector ".n-chat-workspace[data-reader-following=false]"
  assert_no_button "Latest message"
  header_record("usage-header-actual-ro-growth", sample, screenshot: true)
  assert_no_enqueued_jobs only: ChatResponseJob
ensure
  page.execute_script("window.headerOrderingBoundary?.restore()")
end
```

Keep EN/FR accounting visibility in the existing live-disclosure EN/FR cases, which already use the actual localized broadcast helper. Do not duplicate those fixtures into the new menu browser file. The required migration of those existing cases is precise:

```ruby
# Replace the Usage click with static-section assertions before Sources/Response clicks.
assert_selector "section#chat-usage-details > h2#chat-usage-summary"
assert_no_selector "#chat-usage-details summary", visible: :all
# Replace [open]-coupled live total selector, retaining the exact captured stream.
assert_selector "section#chat-usage-details [data-chat-total-input]", text: "126"
```

`assert_live_disclosures` now starts with `assert_selector "section#chat-usage-details"` and `assert_no_selector "#chat-usage-details summary", visible: :all`; keep the response open/focus and independent Sources/Reasoning state assertions literally intact. In `live disclosure ownership never competes...`, remove the Usage click, retain real Response details activation, History refresh/focus/broadcast handling, and after navigating to the other chat assert its own unique totals ID and **absence of the old chat's totals ID** rather than absence of an `[open]` Usage state. The existing feedback-empty/closed-dialog assertions stay.

In `responsive stateful evidence details and retry`, replace native focus/activation of the former Usage summary with native focus on the actual header Home link:

```ruby
chat_keyboard_focus ".n-chat-toolbar a[href='#{user_root_path}']", reverse: true
assert_selector "section#chat-usage-details"
chat_contrast "#chat-usage-summary"
chat_contrast "[data-chat-total-input]"
chat_contrast "[data-chat-total-output]"
```

Do not press Enter on Home here (that would navigate away); Usage text is not a 3:1 control, so measure its heading/totals at ≥4.5. Keep native activation/contrast of Sources/response details, Reasoning state, real retry, Tools/History, wide table, reduced-motion and no-worker checks unchanged.

- [ ] **Step 6: Migrate native-input/held-RAF tests explicitly; preserve strict ordering without pretending Usage is actionable.**

**Important static fact:** `scroll_controller.js#disclosureClicked` only accepts `.n-chat-header details > summary`. Existing response/Reasoning disclosures are **not** header disclosures. Their clicks cannot honestly produce the old Usage `disclosureActivation`. Do not expand that production selector, insert a fake header details or inject a private activation/position ledger. The removed header-disclosure priority branch has no remaining production UI stimulus; retire its UI-specific assertions explicitly, not its independent reader guarantees.

Apply these exact migrations in `test/system/compact_headers_test.rb`:

| Existing test/helper | New action and retained oracle |
| --- | --- |
| `header_prepare_paused_chat(direction)` | Remove Usage click/open assertion. Native Tab to New chat for backward setup, Home for forward setup, then retain paragraph-19 geometric positioning/scroll event/paused assertion. No fake focus target. |
| `native header forward/backward navigation survives a pending resize acknowledgment` | Keep `header_defer_resize_acknowledgment` byte-for-byte. Both next actual targets are now `#workspace-history-trigger`: backward from New chat, forward from Home. Keep trusted Tab/Shift, changed dimensions versus stale ledger, deferred count >0, native hit/focus and main/transcript zero. |
| `resize alone preserves...` | Starting focus is the real New chat link; replace old summary focus/negative-bottom assertions with that link. Preserve text identity, 1px paragraph offset, paused mode, no invented follow input. |
| Four `native Usage keyboard/pointer keeps its summary operable...` cases | Retire collapsed/expanded/summary-activation contract. Replace with the four reading-and-real-History-action cases below, preserving native input, visible accounting/draft, no Latest on metadata-only change and no nested scrolling. |
| Two `native Usage stream overlap keeps the summary through HUD reflow...` cases | Real Reasoning activation + held reader RAF + actual answer-content replacement + visible accounting update. Assert paused paragraph/Latest/HUD RO/focus, not a fake pinned Usage summary or `restoreDisclosure:after restored=true`. |
| Two `native Tab supersedes a pending Usage activation...` cases | Real Reasoning activation followed by trusted native Tab to response details while actual metadata/header growth is pending. Keep inert-tail geometry, observed accepted scroll, >80px paused gap, 1px accepted position/focused-control offset, no Latest without content. Assert activation is null, not forged. |
| `header_hold_reader_frame` | Accept an observed real-control selector, retain its actual RAF boundary, methods/traces and restore logic unchanged except the selector sample. No added renderer/observer gate. |

The exact new setup line in `header_prepare_paused_chat` is:

```ruby
header_tab_to(direction == "backward" ? ".n-chat-toolbar a[href='#{new_chat_path}']" : ".n-chat-toolbar a[href='#{user_root_path}']")
```

In the pending-resize native-navigation test replace its old target ternary with `target = "#workspace-history-trigger"`; retain all later focus/hit/trust/dimension assertions. In resize-alone replace only its two former summary assertions with:

```ruby
link = ".n-chat-toolbar a[href='#{new_chat_path}']"
assert_selector "#{link}:focus", visible: :all
assert_operator page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().bottom", link), :<, 0
```

Change `header_hold_reader_frame` signature to `def header_hold_reader_frame(selector)`; its initial `page.execute_script(<<~JS)` becomes `page.execute_script(<<~JS, selector)`; its `const summary = root.querySelector('#chat-usage-summary')` becomes `const summary = root.querySelector(arguments[0])`. Existing sampled `summaryTop/summaryBottom` fields now observe the passed actual link/Reasoning summary, not a claim that Usage remains interactive. Keep every RAF hold/release/cancel/restore, actual trace wrapper and trusted event listener unchanged. All three new call sites pass an explicit selector. The helper never writes private reader state or focus/scroll.

Extract the existing genuine inert-tail setup into this test helper for both remaining native timing cases:

```ruby
def header_ordering_tail(target)
  geometry = page.evaluate_script(<<~JS, target)
    (() => {
      const surface = document.querySelector('[data-application-scroll]')
      const target = document.querySelector(arguments[0]), tail = document.createElement('div')
      tail.dataset.headerPausedTabTail = ''
      tail.inert = true
      tail.style.cssText = `height:${Math.ceil(surface.clientHeight + target.getBoundingClientRect().height + 81)}px;flex:none;overflow-anchor:none`
      document.querySelector('.n-chat-transcript').append(tail)
      return { geometryOnly: true, inert: tail.inert, height: tail.getBoundingClientRect().height,
        clientHeight: surface.clientHeight, targetHeight: target.getBoundingClientRect().height,
        parentClass: tail.parentElement.className }
    })()
  JS
  header_record("paused-native-ordering-adversarial-tail", geometry)
  assert geometry.fetch("inert")
  assert_equal "n-chat-transcript", geometry.fetch("parentClass")
  assert_operator geometry.fetch("height"), :>, geometry.fetch("clientHeight") + 80
  header_settle
end
```

Replace the four former Usage keyboard/pointer tests, keeping the same width/input product, with:

```ruby
test "visible Usage and native History #{input} preserve the draft at #{width}x#{height}" do
  header_viewport(width, height)
  visit chat_path(@chat)
  assert_selector "lexxy-editor[connected]"
  find("lexxy-editor .lexxy-editor__content").send_keys("Draft while reading visible accounting")
  page.execute_script("window.visibleUsageEditor = document.querySelector('lexxy-editor')")
  header_top
  assert_selector "section#chat-usage-details table"
  assert_no_selector "#chat-usage-details summary, #chat-usage-summary[tabindex]", visible: :all
  if input == "keyboard"
    header_tab_to("#workspace-history-trigger")
    page.driver.browser.action.send_keys(:enter).perform
  else
    find("#workspace-history-trigger").click
  end
  assert_selector "#chat-history:modal"
  page.driver.browser.action.send_keys(:escape).perform
  assert_selector "#workspace-history-trigger:focus"
  header_broadcast_usage
  header_settle
  assert_no_button "Latest message"
  assert page.evaluate_script("window.visibleUsageEditor === document.querySelector('lexxy-editor')")
  assert_selector "lexxy-editor .lexxy-editor__content", text: "Draft while reading visible accounting"
  assert_equal [0, 0], page.evaluate_script("[document.querySelector('main').scrollTop, document.querySelector('.n-chat-transcript').scrollTop]")
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

Full replacement overlap case inside the existing two-width loop:

```ruby
test "native Reasoning and new answer content retain paused reading through HUD reflow at #{width}x#{height}" do
  header_viewport(width, height)
  visit chat_path(@chat)
  assert_selector "lexxy-editor[connected]"
  message = workspace(:messages, :workspace_answer)
  target = "##{dom_id(message, :reasoning_summary)}"
  header_ordering_tail(target)
  header_tab_to(target)
  assert_selector ".n-chat-workspace[data-reader-following=false]"
  anchor = header_reader_anchor
  header_hold_reader_frame(target)
  page.driver.browser.action.send_keys(:enter).perform
  assert_selector "##{dom_id(message, :reasoning_details)}[open]"
  header_broadcast_usage
  text = message.content + "\n\nOrdering overlap: genuinely new content below the viewport."
  html = ApplicationController.render(partial: "messages/streaming_content",
    locals: { message: message, content_html: Message.render_markdown_content(text) })
  stream = %(<turbo-stream action="replace" target="#{dom_id(message, :content)}"><template>#{html}</template></turbo-stream>)
  page.execute_script("Turbo.renderStreamMessage(arguments[0])", stream)
  assert_selector ".ai-response-content p:last-child", text: "Ordering overlap:", visible: :all
  2.times { header_settle }
  page.execute_script("window.headerOrderingBoundary.mark('before-release'); window.headerOrderingBoundary.release()")
  3.times { header_settle }
  sample = page.evaluate_script("window.headerOrderingBoundary.sample()")
  assert sample.fetch("trace").any? { |entry| entry["event"] == "restoreAnchor:after" && entry["latestVisible"] }, sample.to_json
  assert sample.fetch("trace").any? { |entry| entry["event"] == "schedule" && entry["latestVisible"] && entry["stack"].include?("ResizeObserver") }, sample.to_json
  assert sample.fetch("trace").all? { |entry| entry["activation"].nil? }, sample.to_json
  current = header_reader_anchor(anchor.fetch("index"))
  assert_equal anchor.fetch("text"), current.fetch("text")
  assert_in_delta anchor.fetch("offset"), current.fetch("offset"), 1
  assert_selector "#{target}:focus", visible: :all
  assert_selector ".n-chat-workspace[data-reader-following=false]"
  assert_button "Latest message"
  header_record("reasoning-stream-usage-hud-real-ordering", sample, screenshot: true)
  assert_no_enqueued_jobs only: ChatResponseJob
ensure
  page.execute_script("window.headerOrderingBoundary?.restore()")
end
```

Full replacement newer-input case in that same width loop:

```ruby
test "trusted native Tab supersedes pending visible metadata reflow at #{width}x#{height}" do
  header_viewport(width, height)
  visit chat_path(@chat)
  assert_selector "lexxy-editor[connected]"
  message = workspace(:messages, :workspace_answer)
  reasoning = "##{dom_id(message, :reasoning_summary)}"
  target = "##{dom_id(message, :response_summary)}"
  header_ordering_tail(target)
  header_tab_to(reasoning)
  header_hold_reader_frame(reasoning)
  page.driver.browser.action.send_keys(:enter).perform
  assert_selector "##{dom_id(message, :reasoning_details)}[open]"
  header_broadcast_usage
  header_tab_to(target)
  page.execute_script("window.headerOrderingBoundary.mark('native-tab-accepted')")
  accepted = page.evaluate_script("window.headerOrderingBoundary.sample().trace.find(entry => entry.event === 'native-tab-accepted')")
  page.execute_script("window.headerOrderingBoundary.release()")
  3.times { header_settle }
  sample = page.evaluate_script("window.headerOrderingBoundary.sample()")
  key = sample.fetch("trace").find { |entry| entry["event"] == "keydown" && entry["key"] == "Tab" }
  assert key.fetch("trusted"), sample.to_json
  assert_nil key.fetch("activation"), sample.to_json
  assert_operator accepted.fetch("top"), :>, key.fetch("top"), sample.to_json
  assert sample.fetch("trace").any? { |entry| entry["event"] == "recordInput:before" && entry["active"] == dom_id(message, :response_summary) }, sample.to_json
  assert accepted.fetch("paused"), sample.to_json
  assert_operator accepted.fetch("gap"), :>, 80, sample.to_json
  assert_in_delta accepted.fetch("top"), page.evaluate_script("document.querySelector('[data-application-scroll]').scrollTop"), 1, sample.to_json
  assert_selector "#{target}:focus"
  assert_in_delta accepted.fetch("activeTop"), page.evaluate_script("document.activeElement.getBoundingClientRect().top"), 1
  header_hit(target)
  assert_no_button "Latest message"
  header_record("trusted-tab-over-pending-visible-metadata", sample, screenshot: true)
  assert_no_enqueued_jobs only: ChatResponseJob
ensure
  page.execute_script("window.headerOrderingBoundary?.restore()")
end
```

The old nonnil-activation/`restoreDisclosure restored=true` expectations are removed **only** because the approved header control no longer exists. The replacement tests retain actual native movement, actual Turbo payloads, actual header/HUD RO, real geometry, strict 1px/80px and newer-input-wins assertions. If the exact native action does not produce the asserted nonzero movement, diagnose geometry and select the genuinely reachable real target before claiming coverage; never forge a ledger/event/delivery boundary or broaden 1px. Keep the independent existing `chat_workspace_test.rb` cases for native forward/backward input around pending resize, lifecycle pause/resume at exactly 80px, chrome-only replacement, genuine new content, own-success resume, prevented/failed sends and same-chat draft preservation. Their whole-file GREEN is mandatory, not a filtered substitute.

- [ ] **Step 7: Migrate all remaining generic-header setup while retaining actual route/action matrices.**

Apply these bounded transformations in the same commit:

| File / exact affected case or helper | Replacement code | Assertions that must remain |
| --- | --- | --- |
| `test/system/accounts_settings_workspace_test.rb:105–107` three-page matrix | Replace header-summary click/open pair with `assert_no_selector "[data-header-details], .n-header-details", visible: :all`; keep visible `main .n-workspace-header nav` | Real link order, scoped account role/UID, settings columns/cards, native focus, contrast, all 48 states |
| `test/system/mcp_workspace_test.rb:45–47` six-page matrix | Same no-header-details assertion, then existing visible header-nav assertion | 96-state matrix, real catalog/new/edit/activation, local fail-fast client boundary, scopes/secrets and keyboard |
| `test/system/profile_management_test.rb:32–39` breadcrumb styling | Replace each click/open pair with no-header-details assertion and existing visible trail assertion | Real profile/accounts rendering, exact style comparison, all viewport/theme/locale bounds and credential forms |
| `test/system/account_experience_test.rb:419`; `dashboard_test.rb:201`; `agent_skills_workspace_test.rb:342,386`; `sources_workspace_test.rb:749`; `token_usage_workspace_test.rb:218`; `profile_management_test.rb:372` | Replace the old `page.execute_script("document.querySelectorAll('[data-header-details]').forEach(details => details.open = true)")` setup with `assert_no_selector "[data-header-details], .n-header-details", visible: :all` | Real native Tab/action/upload/CRUD/source/index/local registry/account/permission and color/geometry checks following the setup |
| `test/system/token_usage_workspace_test.rb:96` | Change the geometry-only close selector to `[data-usage-workspace] details` (remove only obsolete `:not([data-header-details])`) | Actual usage table disclosures remain real and retain keyboard/estimate/methodology semantics |
| `CompactAccountHeadersSystemTest` account UID/role case | Rename to `account uid and viewer role stay visible with inline heading context`; replace two closed-details assertions with no-header-details and visible trail | Owner/member exact translated role, escaped UID, hit samples, 1px/viewport containment, owner-only edit, native logout through B helper |
| `CompactAccountHeadersSystemTest#record_account_context` | Replace `closed: !header.querySelector('details[data-header-details]').open` with `inlineContext: !!header.querySelector('.n-workspace-context') && !header.querySelector('details[data-header-details]')` | Every existing rendered-text/scope bounds/visibility/hit/overflow field |

Retain exact no-account/setup/source-error/privacy and action URL assertions. Review the retained unique description through actual Sources form and MCP catalog tests; no descriptions are reintroduced merely to satisfy an old generic-copy expectation.

Run a static coupled-selector inventory with the mandatory cwd/preamble, without pretending that grep is browser evidence:

```bash
rg -n 'chat-usage-summary|chat-usage-details|data-header-details|n-header-details|usageOpen|header_disclosures' test app/views app/assets/stylesheets/nosia
```

Expected remaining occurrences: ordinary Usage section/h2 selectors, explicit negative assertions against removed header UI, historical-ID strings and genuine nonheader details. No positive `details[data-header-details]`, `[open]` Usage, native focus/Enter on Usage h2 or helper name `header_disclosures` may remain. `scroll_controller.js` and other protected production bytes still match Task 0.

- [ ] **Step 8: Run the atomic C RED/GREEN/protection gates, inspect actual evidence, then commit.**

Before any Step 2/3 production edit, run these newly prepared REDs with mandatory cwd/preamble/recorder (expected failures must be recorded in exit-preserving conditionals):

```bash
nav_record orbite-refinement-C-request-red rails_test test test/integration/compact_headers_test.rb -i '/page_heading_exposes|saved_Usage_is_a_labelled/'
nav_record orbite-refinement-C-context-red browser_test test/system/compact_headers_test.rb -i '/saved_header_keeps_visible|useful_page_context/'
nav_record orbite-refinement-C-growth-red browser_test test/system/compact_headers_test.rb -i '/visible_Usage_growth|visible_Usage_and_native_History/'
```

After production and all coupled migrations, build and run **whole files**, not only new cases:

```bash
nav_record orbite-refinement-C-build rails_test tailwindcss:build || exit $?
nav_record orbite-refinement-C-requests rails_test test test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/integration/chat_message_rendering_test.rb test/controllers/chat_workspace_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/profiles_controller_test.rb test/internationalization/catalogs_test.rb test/integration/token_footer_test.rb || exit $?
nav_record orbite-refinement-C-reader browser_test test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_refresh_draft_test.rb test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb || exit $?
nav_record orbite-refinement-C-workspaces browser_test test/system/dashboard_test.rb test/system/accounts_settings_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb || exit $?
nav_record orbite-refinement-C-navigation browser_test test/system/localization_test.rb test/system/color_theme_test.rb test/system/account_experience_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/system/sources_workspace_upload_test.rb || exit $?
git diff --check
```

Run installed RuboCop on the actual changed Ruby tests, preserving target 4.0; do not auto-correct unrelated files. Compare protected production hashes before accepting C. Inspect real four-viewport EN/FR/theme screenshots: the full account wraps, usage/table/notes are readable, ordinary context is below h1 and outside actions, context scrolls away, composer remains reserved/reachable, no global/header accordion remains, and Sources/Reasoning/response/editor formatting still behave natively.

Stage exactly the C production/test files below. Inspect the diff first: an unchanged listed file is harmless, but an unexpected mutation is not authorized. Never use `git add .`:

```bash
git add -- app/views/workspaces/_header.html.erb app/views/chats/_header.html.erb app/views/dashboards/show.html.erb app/views/accounts/index.html.erb app/views/settings/show.html.erb app/views/profiles/show.html.erb app/views/sources/index.html.erb app/views/agent_skills/index.html.erb app/views/mcp_servers/index.html.erb app/views/mcp_servers/new.html.erb app/views/mcp_servers/edit.html.erb app/views/token_usages/show.html.erb app/assets/stylesheets/nosia/application_shell.css app/assets/stylesheets/nosia/orbite_chat.css test/integration/compact_headers_test.rb test/integration/chat_message_rendering_test.rb test/controllers/chat_workspace_test.rb test/controllers/accounts_workspace_shell_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/accounts_settings_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb test/system/account_experience_test.rb test/system/dashboard_test.rb test/system/agent_skills_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb
git commit -m "refactor(ui): Show useful page context and live Usage below titles"
```

Record the retired UI contracts versus new evidence in the C report. SPEC review must check every copy decision, visible accounting and migration map; QUALITY must check meaningful movement/observer traces and unchanged protected production bytes, not merely green counts. Only after both pass may Task D resume Task 7 work.

## Task D: Reconcile paused Task 7 drafts and refresh all final evidence

**Tracked mutation ownership:** Only `docs/orbite-workspace.md`, `docs/chat-workspace.md`, `docs/chat-composer.md`, `docs/compact-headers.md`, `docs/README.md`. No new implementation changes during frozen verification. A discovered Important/Critical code defect returns to a separately scoped test-first correction and SPEC→QUALITY, then invalidates affected freezes/gates.

**External evidence:** Fresh audit, source/input freeze, raw logs/TRUE.exit, reviewed screenshots, exact security provenance/comparison and final manifest under the existing evidence root. Preserve original Task 7 artifacts; do not overwrite the newly recomputed baseline/current reports.

- [ ] **Step 1: Resume deliberately, preserving drafts and historical limits.**

Tell the paused Task 7 worker the exact accepted A/B/C commits, changed test inventory and this plan; do not let it run the earlier Task 7 recipe blindly. It may be resumed as D's fresh bounded implementer only after confirming that no prior group is running. Otherwise use a fresh D implementer and leave that worker paused. The already chosen task execution mode is not reopened.

Read the five actual drafts and their diffs first. Their retained sections on personal roots, account/sources, real PDF upload, worker authority, uncached bounded freshness, same-page HTML/native draft handoff, cancellation and source-bearing exclusions remain authoritative. Do not rewrite them from an older template. The amendment changes the current presentation contract, not the dated earlier results.

In `docs/orbite-workspace.md`, replace the first paragraph's claim that Appearance/profile opens all utilities with:

```markdown
At rail widths, the bottom user button opens Profile, Settings and Sign out
directly above that same button, without opening History. Language and theme
remain in the navigation utilities reached by the History/navigation button.
Below 768px, the user button is inside the native navigation panel and opens
the same user-action list above its visible mobile trigger. These are one
popover and one set of native preferences, not duplicate menus or modals.
```

After the responsive-navigation ownership paragraph add:

```markdown
Navigation's localized heading remains available to accessibility APIs but
its duplicate logo and visible title are removed. The upper-right cross and
each conversation's trash button retain localized accessible names and at
least 44px hit targets. The current conversation is marked by its padded
highlight and aria-current, not a repeated visible annotation. Confirmation,
authorization, account/date context and native focus recovery are unchanged.

The user-action list is a native nonmodal popover with ordinary links.
Escape/outside dismissal closes it without introducing a second modal owner.
Inside mobile navigation, the same menu node temporarily belongs to the
active dialog subtree so it is not inert; it returns to its shell home on
close/cache/resize. The editor, History and streaming nodes are never moved.
```

Under Conversation and composer add:

```markdown
Useful account/role/scope and breadcrumb context is visible beneath h1;
generic descriptions repeating titles or nearby controls are omitted.
Header Details accordions are gone, including chat Usage. Usage is now a
visible labelled section with the same live totals, per-kind table,
environmental estimates, explanatory notes and broadcast target. It remains
inside the reading surface and scrolls away. Sources, Reasoning, response
details and native Formatting retain their existing disclosure behavior.
```

Add links to the [amendment design](../specs/2026-10-31-orbite-navigation-refinements-design.md) and this plan in the guide using **docs-relative** destinations `superpowers/specs/2026-10-31-orbite-navigation-refinements-design.md` and `superpowers/plans/2026-10-31-orbite-navigation-refinements.md`, not the relative destinations of this plan file.

In `docs/chat-workspace.md`, change only the current History-entry description from “current conversation” text to “padded active highlight and aria-current”; retain account/date/order/escaped title limit/confirmed deletion. Replace the current Usage sentences with:

```markdown
Header **Usage details** is always-visible context below the saved chat title,
not an accordion. It retains the conversation's live Input/Output counters,
full usage-kind table, environmental estimates and fallback/methodology notes.
Its accounting and broadcast target are unchanged. Sources, Reasoning and
Response details remain independent native disclosures; their open/closed
state and normal focus restoration are retained across live replacements
and same-URL Turbo morphs.
```

Keep the narrowly accepted Turbo race paragraph and native draft/generation safeguards. Point current safe verification instructions to this plan's Task D, not the old unrestricted commands. Preserve the exact dated 2026-10-30 results as historical text, not a current pass.

In `docs/compact-headers.md`, replace only its opening supersession notice with:

```markdown
**Historical presentation boundary:** the signed-in global bar, outer chat
scroller, in-flow chat-page composer and mobile pill below were superseded
by [Orbite](orbite-workspace.md). The 2026-10-31 navigation refinement also
supersedes the header Details accordion, collapsed Usage and Usage-summary
activation descriptions below: useful context and complete live Usage are
now visible beneath h1. Sources, Reasoning, response details and native
Formatting remain disclosures. Visible account scope/role, native-input and
paused-reader safeguards still apply. Earlier geometry, test counts and
security results are historical, not fresh evidence for the amended UI.
```

In `docs/chat-composer.md`, retain its drafted Dedicated chat-page shell and native handoff sections; add after that shell section:

```markdown
The 2026-10-31 navigation refinements do not change composer ownership or
native Formatting. Visible context/Usage stays in the reading surface above
the reserved dock; the direct user-action popover is not an editor control
or another modal owner. Use the current Orbite refinement plan's explicit
safe verification selection, not the historical unrestricted commands.
```

In `docs/README.md` keep the existing Orbite guide link and change the compact-header description to “historical header presentation, retained reader safeguards and explicit supersession boundaries.” These documentation edits need no fabricated application RED: verify links and truthful descriptions statically, then run the real frozen gates below.

- [ ] **Step 2: Refresh the audit for the final exact selection; build once and freeze inputs.**

Re-read the Task 0/Task 7 audits against final accepted source. Add new popup tests/supports to the explicit selection; confirm TokenUsage creation/broadcast arithmetic remains local and does not execute jobs. Preserve existing real upload/source/account/Stop/Retry/local MCP/credential actions. Record the actual test-adapter and runtime-config binding, not just an assumption from an old audit. No test, source, fixture or runtime-config edits while gates run.

Run the final build with mandatory cwd/preamble/recorder:

```bash
nav_record orbite-refinement-final-build rails_test tailwindcss:build || exit $?
```

Create external `$E/orbite-refinement-freeze.py` using the patch tool, with this complete static input-fingerprint script:

```python
import hashlib
import json
import subprocess
import sys
from pathlib import Path

root = Path("/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui")
paths = subprocess.check_output([
    "git", "ls-files", "-z", "--", "app", "test", "config", "lib", "db",
    "vendor", "bin", "Gemfile", "Gemfile.lock", ".ruby-version", ".rubocop.yml",
    "docs/orbite-workspace.md", "docs/chat-workspace.md", "docs/chat-composer.md",
    "docs/compact-headers.md", "docs/README.md"
], cwd=root).decode().split("\0")
# The new guide can still be untracked before its final documentation commit.
paths = sorted(set(filter(None, paths)) | {"docs/orbite-workspace.md"})
result = {}
for name in paths:
    path = root / name
    if path.name == ".env" or path.name.startswith(".env."):
        raise SystemExit("Environment input is outside this freeze")
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"Unexpected nonregular frozen input: {name}")
    result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
destination = Path(sys.argv[1])
if sys.argv[2] == "write":
    with destination.open("x") as output:
        json.dump(result, output, indent=2, sort_keys=True)
    print(f"Frozen {len(result)} source/test/fixture/config/doc inputs")
elif sys.argv[2] in ("check", "check-runtime"):
    before = json.loads(destination.read_text())
    changed = sorted(name for name in before.keys() | result.keys() if before.get(name) != result.get(name))
    if sys.argv[2] == "check-runtime":
        changed = [name for name in changed if not name.startswith("docs/")]
    print(json.dumps({"changed": changed, "count": len(result)}, indent=2))
    if changed:
        raise SystemExit(1)
else:
    raise SystemExit("Expected write or check")
```

Use a newly named path, not an overwritten freeze:

```bash
freeze="$(mktemp "$E/orbite-refinement-final-freeze.XXXXXX.json")"
# mktemp reserved the owned path; write mode requires exclusive creation.
# Supply a new sibling instead of removing that reserved file.
freeze="${freeze%.json}.inputs.json"
nav_record orbite-refinement-freeze python3 "$E/orbite-refinement-freeze.py" "$freeze" write || exit $?
printf '%s\n' "$freeze" > "$E/orbite-refinement-final-freeze-path.txt"
```

This hashes selected tracked inputs and the actual doc drafts, not ignored `.env` files, databases, generated logs or development process state. Store the exact source SHA, dirty-doc status, protected-file hashes and selected-entrypoint inventory alongside the freeze. Build output is not a substitute for source binding; do not stage ignored generated CSS.

- [ ] **Step 3: Run the exact complete final safe groups sequentially with fresh true exits.**

With mandatory cwd/preamble/recorder, execute each group in foreground `timeout=0`, stop on nonzero, and inspect its actual summary before the next. These are the original Task 7 safe inputs plus the **new refinement browser file** and **Task 6 `chat_refresh_draft_test.rb`**, not an unrestricted suite or a narrowed green subset:

```bash
nav_record orbite-refinement-final-focused rails_test test test/integration/orbite_shell_test.rb test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb test/controllers/chat_account_url_race_test.rb test/controllers/chat_sources_controller_test.rb test/models/chat_test.rb test/models/dashboard_recents_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/profiles_controller_test.rb test/internationalization/catalogs_test.rb test/integration/token_footer_test.rb || exit $?
nav_record orbite-refinement-final-chat browser_test test/system/orbite_workspace_test.rb test/system/orbite_navigation_refinements_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb test/system/chat_refresh_draft_test.rb || exit $?
nav_record orbite-refinement-final-workspaces browser_test test/system/dashboard_test.rb test/system/accounts_settings_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb || exit $?
nav_record orbite-refinement-final-navigation browser_test test/system/localization_test.rb test/system/color_theme_test.rb test/system/account_experience_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb test/system/sources_workspace_upload_test.rb || exit $?
```

Require actual nonzero counts, seeds/assertions, zero unexpected failures/errors/skips and real raw-log/TRUE.exit pairs for every group. Do not copy Task 7's earlier numbers or call a timeout/interruption a pass. The previous three limited exceptions (GET `/login` waiting scaffold, two exact Brakeman warnings, narrow Turbo-native focus race) remain narrow; the existing MCP JSON warning debt remains visible. No new popup/reader/native focus failure is automatically accepted.

Required protected evidence includes real PDF chooser/upload/stored-byte equality; membership/source/account/reference guards; Stop/partial answer/eligible Retry; distinct-worker stopped feedback; exactly bounded uncached account/id freshness queries; localized live totals; pre-growth 80px/1px anchors/Latest/own-success-only follow; same-chat native HTML/ordinary-link draft preservation; real GET in-flight typing and cancellation/source-bearing exclusions. No worker/provider is used to manufacture those outcomes. Final native-reader and draft files must run in full.

- [ ] **Step 4: Lint/syntax-check actual changed source and statically verify protection/link bindings.**

With mandatory cwd/preamble/recorder:

```bash
git diff --name-only --diff-filter=ACMR 7189d6de425122120f3fb4d7090d16a9ebb88f11 -- '*.rb' > "$E/orbite-refinement-changed-ruby.txt"
nav_record orbite-refinement-final-lint test_command bundle exec ruby -e 'files=File.readlines(ARGV.fetch(0),chomp:true); abort "No Ruby files" if files.empty?; exec "bundle","exec","rubocop",*files' "$E/orbite-refinement-changed-ruby.txt" || exit $?
nav_record orbite-refinement-final-js-user-menu node --input-type=module --check < app/javascript/controllers/user_menu_controller.js || exit $?
nav_record orbite-refinement-final-js-navigation node --input-type=module --check < app/javascript/controllers/workspace_navigation_controller.js || exit $?
nav_record orbite-refinement-final-js-dialog node --input-type=module --check < app/javascript/controllers/chat_dialog_controller.js || exit $?
nav_record orbite-refinement-final-js-reader node --input-type=module --check < app/javascript/controllers/scroll_controller.js || exit $?
nav_record orbite-refinement-final-js-disclosures node --input-type=module --check < app/javascript/controllers/chat_disclosures_controller.js || exit $?
nav_record orbite-refinement-final-js-feedback node --input-type=module --check < app/javascript/controllers/chat_feedback_controller.js || exit $?
git diff --exit-code 030e20ca42df7c0be66037f170b23594a3be38cf -- app/javascript/controllers/scroll_controller.js app/javascript/controllers/chat_disclosures_controller.js app/javascript/controllers/chat_dialog_controller.js app/javascript/controllers/chat_account_controller.js app/javascript/controllers/chat_feedback_controller.js app/views/chats/_token_totals.html.erb app/views/chats/new.html.erb app/views/chats/show.html.erb || exit $?
git diff --exit-code 030e20ca42df7c0be66037f170b23594a3be38cf -- app/controllers app/models app/jobs config db Gemfile Gemfile.lock test/support/fixtures || exit $?
git diff --check
```

Use only the installed JS syntax runtime; no Node build/dependency is introduced. All added/changed Markdown links must resolve relative to their owning doc; verify anchors in the retained handoff/reader/composer references. Static syntax/links are not application/native accessibility proof.

- [ ] **Step 5: Parent-review the security recovery provenance; rescan the NEW final code.**

Read `$E/orbite-task7-security-recovery-report.md` and `/tmp/opencode/orbite-task7-security-recompute-yj_gmyrs/{source-bindings.json,comparison.json}`. The parent has not independently reviewed that recovery yet: review before accepting it as the immutable baseline provenance. The original `task7-baseline-security.json` is lost; the user explicitly authorized **NEW analysis**, not fabrication/restoration of the lost JSON.

The newly recomputed baseline is:

```text
commit: 7189d6de425122120f3fb4d7090d16a9ebb88f11
report: /tmp/opencode/orbite-task7-security-recompute-yj_gmyrs/orbite-recomputed-baseline-security.json
report SHA256: 59ef757700e7e6085e546eb5616c901e1768509e64a678bd62e2bced217b052c
Brakeman: 8.0.4; Ruby: 4.0.7; Rails: 8.0.5.1; 79 checks
baseline/current lockfile SHA256: 986f83c2ca94da7780c4a98eada046adb1e63fed8c9a63357986594dd66b8bd4
baseline/current old scan exits: 3 / 3; comparison exit: 0
```

Original/current old scan `030e20` is **stale after amendment code changes**. Reuse only the actual immutable NEW baseline after verifying its hash, source-tree/archive binding, scanner/config/dependency parity and no errors/ignored warnings. No configuration/ignore files existed in that recovery; inspect current repository/user/system scanner configuration paths using the recorded provenance before scanning, and stop if they differ. Do not conceal an altered scanner input by preserving just the fingerprint set. If the baseline/provenance is missing or unverifiable, stop and ask the parent/user; do not manufacture the old filename, suppress a warning or upgrade dependencies.

Record this exact static preflight before scanning (mandatory cwd/preamble/recorder); it reads no environment file:

```bash
nav_record orbite-refinement-security-inputs python3 - <<'PY'
import hashlib
import json
from pathlib import Path
root = Path('/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui')
recovery = Path('/tmp/opencode/orbite-task7-security-recompute-yj_gmyrs')
binding = json.loads((recovery / 'source-bindings.json').read_text())
assert binding['baseline'] == '7189d6de425122120f3fb4d7090d16a9ebb88f11'
assert hashlib.sha256((root / 'Gemfile.lock').read_bytes()).hexdigest() == '986f83c2ca94da7780c4a98eada046adb1e63fed8c9a63357986594dd66b8bd4'
for path in [root / 'config/brakeman.yml', root / 'config/brakeman.ignore',
             recovery / 'baseline-source/config/brakeman.yml',
             recovery / 'baseline-source/config/brakeman.ignore',
             Path.home() / '.brakeman/config.yml', Path('/etc/brakeman/config.yml')]:
    assert not path.exists(), f'Unexpected scanner configuration: {path}'
print('Immutable NEW baseline binding, unchanged lockfile and absent recorded scanner configs verified')
PY
```

Use an explicit `if`/exit check around the heredoc call so its nonzero status stops the shell. Parent provenance review additionally checks the recorded archive/tree manifest and actual regular-file hashes, not only this short preflight.

Run with mandatory cwd/preamble/recorder; reserve a NEW report pathname and keep true exit 3, then separately compare:

```bash
nav_record orbite-refinement-scanner-version test_command bundle exec brakeman --version || exit $?
security="$(mktemp "$E/orbite-refinement-security.XXXXXX.json")"
security="${security%.json}.report.json"
if nav_record orbite-refinement-final-security test_command bundle exec brakeman --path /home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui --format json --output "$security"; then
  security_exit=0
else
  security_exit=$?
fi
test "$security_exit" -eq 0 || test "$security_exit" -eq 3 || exit "$security_exit"
printf '%s\n' "$security" > "$E/orbite-refinement-final-security-path.txt"
```

Add external `$E/orbite-refinement-security-compare.py` with:

```python
import hashlib
import json
import sys
from pathlib import Path

baseline = Path("/tmp/opencode/orbite-task7-security-recompute-yj_gmyrs/orbite-recomputed-baseline-security.json")
current = Path(sys.argv[1])
expected = {
    "4fad3c218f35052d2f3a3eff4544480d05b60bc9199a001ec6242a8921b93ae3",
    "d84924377155b41e094acae7404ec2e521629d86f97b0ff628e3d1b263f8101c",
}
assert hashlib.sha256(baseline.read_bytes()).hexdigest() == "59ef757700e7e6085e546eb5616c901e1768509e64a678bd62e2bced217b052c"
old = json.loads(baseline.read_text())
new = json.loads(current.read_text())
for report in (old, new):
    assert not report.get("errors")
    assert not report.get("ignored_warnings")
    assert len(report["warnings"]) == 2
    assert {warning["fingerprint"] for warning in report["warnings"]} == expected
    assert report["scan_info"]["brakeman_version"] == "8.0.4"
    assert report["scan_info"]["ruby_version"] == "4.0.7"
    assert report["scan_info"]["rails_version"] == "8.0.5.1"
    assert len(report["scan_info"]["checks_performed"]) == 79
assert old["scan_info"]["checks_performed"] == new["scan_info"]["checks_performed"]
print(json.dumps({
    "baseline": str(baseline), "current": str(current),
    "baseline_sha256": hashlib.sha256(baseline.read_bytes()).hexdigest(),
    "current_sha256": hashlib.sha256(current.read_bytes()).hexdigest(),
    "new": [], "removed": [], "errors": [], "checks": 79,
    "fingerprints": sorted(expected)
}, indent=2))
```

Then, with mandatory cwd/preamble/recorder:

```bash
security="$(cat "$E/orbite-refinement-final-security-path.txt")"
nav_record orbite-refinement-security-comparison python3 "$E/orbite-refinement-security-compare.py" "$security" || exit $?
freeze="$(cat "$E/orbite-refinement-final-freeze-path.txt")"
nav_record orbite-refinement-final-freeze-check python3 "$E/orbite-refinement-freeze.py" "$freeze" check || exit $?
```

Require exactly the two existing warnings, no additions **or removals**, no errors/ignored warnings, same default 79 checks and proven scanner/config/lockfile inputs. Exit 3 alone is not success, and equality is not “security clean.” Preserve actual new JSON/raw log/TRUE.exit paths and the comparison's actual exit 0. Never overwrite the old current `030e20` report or pass it off as the new final scan.

- [ ] **Step 6: Inspect the real evidence and write an honest final manifest.**

Write new `$E/orbite-refinement-final-manifest.md`, with actual values rather than predicted counts:

- Approved spec commit, original baseline, A/B/C commits and exact verified source SHA; task SPEC→QUALITY outcomes; frozen input paths/hash and zero-change check.
- Every executed command, raw log, TRUE.exit, test count/assertions/seed and any actual failure classification. No earlier PASS substituted for a new source/test run.
- EN/FR × light/dark × four actual CSS viewports (375×812, 768×1024, 1400×1000, 812×375), eleven page families, saved/new/no-account and long names; public separation and unchanged native preference targets.
- Actual History padded text inset, ≥8em row readability, cross/trash accessible names, no duplicate visible chrome/current annotation, native confirmed deletion, ≥44px dimensions, ≥2px focus, five-point hits, nonoverlap and measured text/stroke/focus contrast.
- Direct rail opener with History expanded/collapsed on chat and closed non-chat; mobile same-node menu inside the modal, correct above-opener bounds/top-layer unclipped placement, no duplicate IDs, native Enter/Space/Tab/Escape/outside, current streamed-opener return, modal closure, resize/cache/back and no hidden/inert focus.
- Visible complete Usage table/totals/estimates/notes with stable target and real localized accounting broadcasts, actual new-kind header growth/RO and no Latest for metadata alone. Record exactly which former Usage-toggle assertions were retired and their new visible-metadata/native-input/response-disclosure replacements. Reader JS and other protected production bytes remain unchanged.
- Genuine new-content Latest/HUD/RO traces; independent trusted Tab/Shift and accepted-native-input/resize ordering; strict 80px/1px; own-success-only resume; native same-chat HTML/ordinary-link/in-flight typing/source-bearing cancellation coverage; actual real PDF bytes, source guards and uncached worker freshness.
- Screenshot/measurement paths **actually opened and inspected**, including compact landscape, long labels, themes and real long conversation. Mark synthetic overflow/label fixtures explicitly; do not infer a pass from screenshot filenames or app string matching.
- NEW security baseline provenance, final scan source/hash/version/config/79-check equality, exact warning set and real raw exits. Say “new scoped static comparison”; the lost original remains lost.
- NOT RUN limits: unrestricted unsafe suite, native zoom, screen readers, physical OS/mobile keyboard and live providers/workers. Original Task 3 raw RED/probe artifacts remain lost and the interrupted compact run remains UNKNOWN; this amendment does not recover or relabel them. Existing GET login/scanner/focus limitations and unsuppressed MCP JSON debt do not expand.
- Confirmation of no env/development-process/database-lifecycle/dependency/worker/live-service action, no route/backend/native handoff/reader algorithm change, no auto-integration.

The manifest is external evidence. Append a short dated current-verification paragraph to `docs/orbite-workspace.md` **only after** these actual gates/inspection exist; include actual source/groups/exits and limitations, not `/tmp` log contents or secrets. This planned final paragraph is a documentation-only change after the freeze. Run this exact follow-up with mandatory cwd/preamble/recorder:

```bash
freeze="$(cat "$E/orbite-refinement-final-freeze-path.txt")"
nav_record orbite-refinement-post-doc-runtime-check python3 "$E/orbite-refinement-freeze.py" "$freeze" check-runtime || exit $?
final_freeze="$(mktemp "$E/orbite-refinement-doc-freeze.XXXXXX.json")"
final_freeze="${final_freeze%.json}.inputs.json"
nav_record orbite-refinement-post-doc-freeze python3 "$E/orbite-refinement-freeze.py" "$final_freeze" write || exit $?
nav_record orbite-refinement-post-doc-freeze-check python3 "$E/orbite-refinement-freeze.py" "$final_freeze" check || exit $?
```

Record the new freeze path and show that the only after-gate tracked changes are the planned guide verification paragraph and evidence manifests outside the repository. The runtime-only check excludes all docs, so review the exact doc diff as well; it cannot authorize other doc rewrites. Do not call the original all-input freeze unchanged after deliberately editing the guide.

- [ ] **Step 7: Complete independent reviews, commit only reconciled docs and hand back without integration.**

SPEC then QUALITY review D against this plan, the approved amendment and actual manifest/security provenance. The parent also reviews the whole A→D amendment diff and original preserved boundaries; obtain the independent whole-feature review still required by original Task 7 before claiming feature completion. No new plan-review dispatch is needed. An Important/Critical finding requires a bounded correction with its own evidence/review and re-frozen affected gates.

With mandatory cwd/preamble (no application runtime needed):

```bash
git diff --check
git diff --stat
git add -- docs/orbite-workspace.md docs/chat-workspace.md docs/chat-composer.md docs/compact-headers.md docs/README.md
git commit -m "docs(ui): Explain refined Orbite navigation and visible Usage"
git status --short
```

Bind the final doc commit to the verified application/test/config hashes. Report the actual outcome, accepted limitations and pending manual checks; do not merge, push, open a PR, delete a worktree or resume unrelated work automatically.

## Coverage and planning self-review

| Approved design requirement | Atomic implementation and evidence |
| --- | --- |
| Remove header accordions; useful context under h1, retain unique operational/safety guidance | C exact copy-decision table, shared header/source form/catalog retention, generic-header request/native matrices |
| Complete live Usage visible, actual table/totals/estimates/notes/identity retained | C section/h2 wrapper; byte-identical token partial; real localized TokenUsage broadcasts/new-kind row; no hidden replacement |
| Context scrolls away, one reading surface, reserved native composer | C full compact/Orbite geometry + D protected composer/layout groups; unchanged new/show surface markup |
| Remove duplicate panel logo/visible title; retain accessible heading and icon Close | A request naming/hidden h2, native close/focus/Escape, localized geometry replacement |
| Icon Delete, no Current span, aria-current, real padded active highlight | A eight-row matrices and native confirmation cancellation/acceptance; ≥8em/title/account/date/hit/44px/stroke/focus |
| Rail directly opens existing user actions above same actual trigger | B native one-menu controller/real viewport geometry; tablet non-chat closed History, saved/new expanded/collapsed intent unchanged |
| Mobile fallback, one modal owner, unique IDs, preferences retained | B same-node modal-safe reparent; public byte preservation; separate preference/user helpers; native Escape ordering/lifecycle/native form tests |
| Native keyboard/themes/locales/long labels/reduced motion | A/B/C real Tab/Shift, pointer/Enter/Space, four sizes/themes/ENFR, inherited reduced-motion/public targets and measured contrast |
| No reader regression from obsolete Usage-test migration | C explicit retired-versus-new mapping, real metadata growth/RO, held RAF/response/newer input, full strict independent reader/draft cases, byte-frozen reader |
| Scope/upload/source/generation/freshness/HTML-draft invariants | D complete safe request/chat/workspace/navigation groups, including refresh in-flight typing; no business/server edits |
| Paused Task 7 drafts/evidence/security remain truthful | 0/D preserve drafts/old UNKNOWN/lost artifacts; parent provenance review, NEW final scan, fresh frozen groups and manifest |

### Planning validation and bounded uncertainties

- This is an amendment implementation plan, not a renewed palette/design exercise. It retains the already selected task mode and independent SPEC→QUALITY gates.
- Static source confirms the native Popover choice still requires actual installed-browser integration proof. Menu Escape ordering inside a modal, `{ source: opener }`, clamped bounds and streamed-opener focus are **test obligations**, not assertions of verified runtime behavior.
- Static source also exposes a stale Task 2 intermediate-frame assertion in `test/integration/compact_headers_test.rb`; C explicitly migrates it to the already accepted actual Task 3 placement, without changing production scrolling.
- Ordinary Usage h2 is never an action or artificial focus stop. Former header-activation-specific traces cannot be kept literally when no header disclosure exists; the exact retirement/replacement inventory is required, with independent strict native ordering retained.
- Future executable commands use the prescribed cwd/helper/source binding/true exits and are contingent on the refreshed path-specific safety audit. No application boot, test, build, DB/browser/scanner/gem/environment/process action was performed to author this plan.
- Parent self-review must check referenced paths/symbols, the complete written spec, all coupled selectors, exact commands, paired locales, doc-relative links and code listings before committing this plan. Plan authors do not commit it or dispatch reviewers/implementers.

### Static authoring validation — 2026-10-31

- Checked 83 literal source/test/doc paths: the three absent implementation files are explicitly declared new; `config/brakeman.yml` is an intentionally absent scanner-config probe, not a missing dependency.
- Checked four Markdown destinations with their owning context, including the docs-relative link inside the proposed historical-notice snippet. All resolve.
- Checked balanced fenced blocks, 30 checkbox steps and no unresolved placeholder markers. Parsed the three Python listings/heredocs statically; Ruby/JavaScript/browser behavior was not executed or claimed verified.
- Reconciled the spec coverage table, actual TokenUsage enum/fixture kinds, existing controller/helper symbols and explicit old-versus-new native timing contracts. Only this new plan file was written; inherited drafts/spec/application files were not changed.

### Parent planning self-review — 2026-10-31

- Read the entire approved specification and plan, then checked the actual shell,
  utilities, shared/chat/dashboard headers, History rows and styles; account,
  profile and settings call sites; native SVG assets; accounting model/fixture;
  reader timing helpers and affected request/browser tests.
- Corrected the paused worker's exact session ID. Corrected the external
  recorder's local variable to avoid zsh's read-only `status`, retaining full raw
  logs and true exits while showing only a concise preview.
- Corrected the utility-size migration to two genuine visible phases: measure
  language/theme inside the panel, close any desktop modal, then measure the
  actual rail opener. An inert rail button behind a modal cannot pass a hit test.
- Reload translated labels before each long-label fixture, avoiding accidental
  repeated multiplication between themes. Added per-task changed-Ruby lint and
  navigation syntax gates before commits.
- Confirmed the existing per-kind enum includes `agent_skill`, native icon paths
  are stroked with `currentColor`/no fill, profile form IDs and the scoped History
  action methods exist, and ordinary Usage must not become a fake focus control.
- Native popover behavior and replacement native-input geometry remain runtime
  test obligations. This static self-review does not claim browser or scanner
  execution, an existing failure waiver, or acceptance of future source changes.

## Execution handoff

Plan-only handoff: parent self-reviews and commits this file. Execution is already selected as fresh implementer per atomic task with SPEC then QUALITY reviews; start Task 0 only after that handoff, retain paused Task 7 until D, and do not ask for the execution-mode choice again.
