# Compact Scrolling Headers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reclaim vertical content space throughout Nosia with an approximately 48px global bar, compact page headings and both headers scrolling away with content.

**Architecture:** Put the existing application bar and page/layout row inside one stable application scroll element. Keep the semantic `main` inside that element, without its own primary vertical scroll, and adapt the existing chat reader to the ancestor scroll element. Reuse native details for secondary header descriptions; preserve primary actions, account/security context, composer ownership and live-update targets.

**Tech Stack:** Existing Rails ERB, Tailwind CSS, Importmap, Turbo, Stimulus, Minitest fixtures and Selenium/Chromium. No dependency installation, schema, route, backend, authentication or accounting change.

---

## Approved scope and execution boundary

- Specification: `docs/superpowers/specs/2026-10-29-compact-headers-design.md`, approved with **“Go”** after written-spec commit `2257c51c7e1196135cc777bb402985514de8e7e9`.
- This is an amendment to the existing chat-workspace branch, not a fresh rewrite. It intentionally supersedes the prior unchanged-global-header boundary and desktop-versus-narrow primary-scroll placement.
- Both top headers must actually leave the viewport. Merely removing `position: fixed` cannot work while the global bar remains outside the scrolling element.
- Preserve existing reader intent, the 80px pre-growth boundary, paragraph anchoring, success-only own-follow-up resume, native dialogs, message IDs/order, localized broadcasts, usage calculations and authoritative Stop feedback.
- Existing bottom navigation is not being redesigned. It remains fixed and must not cover focused controls or the composer footer.
- User-owned `.env` and `bin/dev` web/CSS/worker processes remain untouched. Do not inspect environment contents, install packages, start workers, alter development databases or test against the user's server.
- The accepted narrow Turbo-native ID-focus race remains documented. Do not reintroduce RAF-gated delivery, a Turbo fork, custom stream delivery or a global focus patch.
- The unrestricted suite remains **UNVERIFIED / NOT AUTHORIZED** because existing crawl/embedding paths can contact external services. The old GET `/login` waiting-test setup error and the two baseline Brakeman warnings remain accepted exceptions only; new failures are not waived.
- Planning creates documentation only. No application change, browser run or fresh baseline is claimed in this document.

## File and responsibility map

| File | Responsibility |
| --- | --- |
| `app/views/layouts/application.html.erb` | Wrap existing flash, global header and existing layout row in a stable primary scroller; preserve every layout guard and sidebar/action URL |
| `app/assets/stylesheets/nosia/application_shell.css` — new | Primary scroll geometry, compact global bar, page-heading density and native header details; no form/editor redesign |
| `app/assets/tailwind/application.css` | Import the new unlayered shell stylesheet after `chat_workspace.css` |
| `app/views/application/_header.html.erb` | Smaller logo/bar classes and stable measurement marker; preserve every existing control/menu/form |
| `app/javascript/controllers/scroll_controller.js` | Use the application ancestor as the one reader surface; retain the measured-position ledger and block anchors |
| `app/views/workspaces/_header.html.erb` | Compact title/actions, secondary description/trail disclosure, visible scope label and primary actions |
| `app/views/chats/_header.html.erb` | One compact title/context/actions row; stable Usage disclosure and totals target |
| `app/views/chats/new.html.erb` | Remove redundant eyebrow; retain one modest introduction heading, existing form and no-account guidance |
| `app/views/dashboards/show.html.erb` | Compact welcome heading; existing descriptive copy in native details, dashboard content unchanged |
| `app/views/accounts/_breadcrumb.html.erb` | Reduce breadcrumb outer spacing, not links or authorization/context |
| `config/locales/en.nosia_layout.yml`, `config/locales/fr.nosia_layout.yml` — new | Paired `nosia.layout.details` label |
| `test/system/compact_headers_test.rb` — new | Application-wide size/scroll/keyboard/localization evidence using existing safe fixtures |
| `test/integration/compact_headers_test.rb` — new | Shared layout/heading markup, control preservation and details content |
| `test/system/chat_workspace_test.rb`, `test/system/chat_workspace_layout_test.rb`, `test/support/chat_workspace_browser_checks.rb` | Intentional reader-surface and tablet contract migration, without weakening behavior assertions |
| Existing workspace system tests listed in Task 4 | Replace obsolete programmatic `main` scrolling; retain geometry measurements of actual `main` and all action/security assertions |
| `docs/chat-workspace.md`, `docs/chat-composer.md`, `docs/README.md`, `docs/compact-headers.md` — new guide | Explain the global shell and superseded scroll-surface documentation |

Do not change `chat-account`, source/upload or composer controllers, generation models/jobs, routes, schemas, dependencies or transport. The separate background-Stop fix is already committed as `8cc53f3`; Task 0 must close its outstanding reviews before treating it as an approved baseline.

## Task 0: Confirm the existing checkpoint and capture isolated before evidence

**Files:** External evidence/checklist only; no application edits.

- [ ] **Step 1: Verify source ownership and the current commit.**

Run from `/home/cbldev/gitd/dilolabs/nosia/.worktrees/chat-workspace-ui`:

```bash
git status --short
git rev-parse HEAD
git log -4 --oneline
```

Expect the approved spec/plan documentation and the existing `8cc53f3` Stop fix, with no unknown application changes. If unrelated work appears, investigate without resetting or deleting it.

- [ ] **Step 2: Close the background-Stop review gate.**

Dispatch specification review of `ac667c5..8cc53f3`, then quality review only after specification approval. Provide the existing report `/tmp/opencode/chat-workspace-hqSpCt/final-stop-report.md` and actual changed files. It describes the real EN/FR unlock-before-refresh regression, authoritative form metadata, valid RED logs and selected GREEN results. Do not call those historical results fresh or alter the fix while planning this amendment. New review findings require their own reproducer and bounded correction before proceeding.

- [ ] **Step 3: Use the existing isolated helper, not development processes.**

Every following test shell must use the explicit worktree directory and begin:

```bash
source /tmp/opencode/chat-workspace-env.sh
```

The helper targets `RAILS_ENV=test`, `postgresql:///nosia_chat_workspace_ui_test`, dummy AI credentials and one test worker. `record` saves a fresh log and its real `.exit`. It is **not** a network sandbox; only the listed safe selections are authorized. Do not copy or display `.env`, reset the database, run live workers or execute unrestricted `bin/rails test`.

- [ ] **Step 4: Capture the existing selected baseline sequentially.**

```bash
record compact-before-build rails_test tailwindcss:build
record compact-before-contracts rails_test test test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chats_controller_test.rb test/controllers/chat_account_citations_test.rb test/integration/token_footer_test.rb test/internationalization/catalogs_test.rb
record compact-before-chat browser_test test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb
```

Expected: no new failures. Preserve actual counts, seeds and exits; do not prefill them. The pending Stop review and known exceptions do not authorize overlooking a new baseline failure.

- [ ] **Step 5: Retain the immutable before checkpoint.**

```bash
git rev-parse HEAD > "$EVIDENCE/compact-baseline-sha.txt"
```

Task 1's new browser test records native before rectangles and screenshots **before** asserting the absent new layout. Preserve those artifacts from its RED run. Task 2 records the unchanged 64px bar before changing its size. Do not fabricate a previously executed measurement or call test setup errors a layout RED.

## Task 1: Put headers and content in one primary application scroller

**Files:** Layout, new shell stylesheet/import, reader controller, new integration/system tests and existing chat scroll-test helpers.

- [ ] **Step 1: Add request coverage before layout changes.**

Create `test/integration/compact_headers_test.rb`:

```ruby
require "test_helper"
require_relative "../support/chat_workspace_fixtures"

class CompactHeadersTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "application layout has one scrolling ancestor containing both headers" do
    [ user_root_path, accounts_path, account_path(@second), sources_path,
      token_usage_path, settings_path, profile_path,
      account_agent_skills_path(@second), account_mcp_servers_path(@second),
      new_chat_path, chat_path(@chat) ].each do |path|
      get path
      assert_response :success
      assert_select "[data-application-scroll]", count: 1
      assert_select "[data-application-scroll] > nav[data-application-header]", count: 1
      assert_select "[data-application-scroll] main", count: 1
      assert_select "#theme-toggle", count: 1
      assert_select "#language_preference_locale", count: 1
      assert_select "#dropdownUser", count: 1
    end
  end

  test "signed out root retains its login and language controls in the shared shell" do
    delete logout_path
    get root_path
    assert_response :success
    assert_select "[data-application-scroll]", count: 1
    assert_select "form[action='#{login_path}']", count: 1
    assert_select "#language_preference_locale", count: 1
    assert_select "#dropdownUser", count: 0
  end
end
```

- [ ] **Step 2: Add the real browser scroll regression.**

Create `test/system/compact_headers_test.rb`:

```ruby
require "application_system_test_case"
require "json"
require "tmpdir"
require_relative "../support/chat_workspace_fixtures"

class CompactHeadersSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(*@original_size)
  end

  test "global and page headers scroll away without a reserved slot" do
    [ user_root_path, account_path(@second), sources_path, chat_path(@chat) ].each do |path|
      visit path
      assert_selector "main h1"
      header_record("before-scroll", page.evaluate_script(<<~JS), screenshot: true)
        (() => {
          const global = document.querySelector('[data-application-header]') || document.querySelector('body > nav')
          const heading = document.querySelector('main h1')
          return { global: global.getBoundingClientRect().toJSON(), heading: heading.getBoundingClientRect().toJSON() }
        })()
      JS
      # Explicit geometry fixture: it forces overflow without executing providers
      # or claiming that an otherwise short page naturally has this much content.
      page.execute_script(<<~JS)
        const main = document.querySelector('main')
        main.insertAdjacentHTML('beforeend', '<div data-header-overflow-fixture style="height:2200px"></div>')
        const surface = document.querySelector('[data-application-scroll]') || main
        surface.scrollTop = 700
        surface.dispatchEvent(new Event('scroll'))
      JS
      assert_selector "[data-application-scroll]"
      assert page.evaluate_script(<<~JS), "Both headers must leave the viewport: #{path}"
        (() => {
          const surface = document.querySelector('[data-application-scroll]')
          const global = document.querySelector('[data-application-header]')
          const heading = document.querySelector('main h1')
          const boundary = surface.getBoundingClientRect().top
          return surface.scrollTop >= 699 && global.getBoundingClientRect().bottom <= boundary &&
            heading.getBoundingClientRect().bottom <= boundary && document.querySelector('main').scrollTop === 0
        })()
      JS
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  private
    def header_record(label, sample, screenshot: false)
      @header_evidence ||= Dir.mktmpdir("compact-headers-", ENV.fetch("EVIDENCE"))
      context = page.evaluate_script("({ path: location.pathname, locale: document.documentElement.lang, dark: document.documentElement.classList.contains('dark'), viewport: [innerWidth, innerHeight] })")
      record = context.merge("label" => label, "sample" => sample)
      File.open(File.join(@header_evidence, "geometry.jsonl"), "a") { |file| file.puts(record.to_json) }
      if screenshot
        page.save_screenshot(File.join(@header_evidence, "#{label}-#{Dir.glob(File.join(@header_evidence, '*.png')).length}.png"))
      end
      puts "Compact header evidence: #{@header_evidence}"
    end
end
```

The synthetic overflow is a layout fixture, not a substitute for the actual long-chat, table, composer, form and keyboard cases in later steps.

- [ ] **Step 3: Run valid REDs.**

```bash
record compact-scroll-request-red rails_test test test/integration/compact_headers_test.rb
record compact-scroll-browser-red browser_test test/system/compact_headers_test.rb
```

Expect missing primary-scroll markup or headers staying visible. Fixture, authentication, route or browser errors are not feature REDs and must be corrected before application code.

- [ ] **Step 4: Wrap the existing layout without changing its guards.**

In `app/views/layouts/application.html.erb`, keep the existing `body` attributes. Inside `body`, wrap **all** existing flash/header/layout-row markup:

```erb
<div id="application-scroll" class="n-application-scroll" data-application-scroll>
  <%= render "flash" unless agent_skills_workspace_page? || mcp_workspace_page? %>
  <%= render "application/header" %>
  <div class="n-application-frame">
    <%= render "menu" %>
    <main class="n-application-page <%= 'n-chat-main' if chat_workspace_page? %>">
```

Keep the original navbar/account-breadcrumb guards, `yield`, right-history condition, drawer and their closing tags/content unchanged. Close the new wrapper immediately before `</body>`. The sidebar remains a sibling of `main` inside the layout row, and there is still exactly one semantic `main`. Do not put repeated branding inside `main` or duplicate the global header.

Add `data-application-header` to the existing global `nav`; leave its existing sizing for Task 2.

Create `app/assets/stylesheets/nosia/application_shell.css` and import it unlayered immediately after `chat_workspace.css`:

```css
.n-application-scroll {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
  width: 100%;
  overflow-y: auto;
  scroll-padding-block: .5rem 6rem;
}
.n-application-frame { display: flex; flex: 1 0 auto; min-width: 0; width: 100%; }
/* Preserve access to the existing desktop rail without pinning either top header. */
.n-application-frame > [data-controller~="reveal"] { position: sticky; top: 0; align-self: flex-start; flex-shrink: 0; max-height: 100dvh; }
.n-application-page { flex: 1 1 0%; min-width: 0; padding: .75rem; overflow: visible; }
.n-application-scroll:has(.n-chat-workspace) { overflow-anchor: none; }
.n-application-page.n-chat-main { display: flex; overflow: visible; padding: .75rem; }
.n-application-page .n-chat-workspace { flex: 1; height: auto; min-height: 0; }
.n-application-page .n-chat-workspace--new { overflow: visible; scrollbar-gutter: auto; }
.n-application-page .n-chat-transcript { flex: none; overflow: visible; }
@media (max-width: 1023px) {
  .n-application-page { padding-block-end: 6rem; }
}
```

This supersedes the old `main` and transcript overflow rules through the later unlayered import. Do not add a hard-coded `calc(100vh - ...)` or an arbitrary nested height. The desktop navigation rail keeps its existing bounded menu scrolling; it is not a second primary content owner. Editors, native dialogs and wide table/code wrappers retain their bounded local scrolling.

- [ ] **Step 5: Adapt only the reader's surface wiring, not its algorithm.**

In `scroll_controller.js`, replace the `surface` getter and these wiring fragments:

```javascript
get surface() {
  return this.main
}
```

```javascript
this.main = this.element.closest("[data-application-scroll]")
this.viewport = this.viewportTarget
this.main.addEventListener("scroll", this.onScroll)
```

Remove the now-unnecessary viewport scroll listener and its matching teardown; keep the observer on the transcript and the existing resize observations. Do **not** replace the measured-position ledger, affected-message comparisons, block anchors or submission listener.

Retarget on ancestor replacement as well as transcript replacement:

```javascript
if (this.viewport !== this.viewportTarget || this.main !== this.element.closest("[data-application-scroll]")) {
  this.observeSurface()
}
```

Keep the rest of `reconcile()` unchanged. The variable `main` remains an internal reference to the measured surface; renaming every internal method is unnecessary churn. Add a short comment explaining the name if useful.

- [ ] **Step 6: Migrate chat tests to the explicitly approved primary surface.**

Replace `reader_surface` in `test/system/chat_workspace_test.rb` with:

```ruby
def reader_surface
  "document.querySelector('[data-application-scroll]')"
end
```

The two old assertions comparing `className` to `n-chat-main` and `n-chat-transcript` must instead assert the **same** `application-scroll` ID before and after reflow. Preserve their paragraph text/offset, follow/paused and exact 1px assertions. Add an assertion that the transcript and `main` have no separate vertical scroll offset.

In `test/support/chat_workspace_browser_checks.rb`, replace the two synthetic scroll dispatches in `chat_scroll_to` with:

```javascript
document.querySelector('[data-application-scroll]').dispatchEvent(new Event('scroll'))
```

Keep native `main`/control rectangle and page-width measurements: those describe geometry, not ownership. Add the application surface to the recorded diagnostic geometry list instead of calling the old main a primary scroller.

In `test/system/chat_workspace_layout_test.rb`, replace the obsolete tablet “must retain transcript-scroll layout” assertion with actual ownership checks:

```ruby
assert_equal "application-scroll", geometry.fetch("surface").fetch("id")
assert_equal 0, geometry.fetch("nested_scroll_offsets").values.max
```

Add these fields to its existing geometry object:

```javascript
surface: (() => {
  const element = document.querySelector('[data-application-scroll]')
  return { id: element.id, top: element.scrollTop, height: element.scrollHeight, client: element.clientHeight }
})(),
nested_scroll_offsets: {
  main: document.querySelector('main').scrollTop,
  transcript: document.querySelector('.n-chat-transcript').scrollTop
},
```

Before taking the footer geometry, scroll the actual application surface to the end and allow the existing reconciliation frames. Keep all footer-versus-fixed-nav bounds and hit tests, and both themes. Do not increase anchor tolerances or silently drop a native-growth race. If an old “recent paragraph” setup falls in the composer after this geometry change, position an actual response paragraph and retain the same behavioral assertion.

- [ ] **Step 7: Run the new tests and all protected chat regressions.**

```bash
record compact-scroll-request-green rails_test test test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb
record compact-scroll-chat-green browser_test test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb
```

Add this case to the existing `ChatWorkspaceSystemTest` before the application correction, preserving its existing transcript-replacement case:

```ruby
test "replacing the application scroll ancestor retains the reader and retargets ownership" do
  visit_reader(1400, 1000)
  assert_selector "[data-application-scroll]"
  pause_reader
  anchor = reader_anchor
  page.execute_script(<<~JS)
    window.previousApplicationSurface = document.querySelector('[data-application-scroll]')
    window.preservedReaderRoot = document.querySelector('.n-chat-workspace--saved')
    const old = window.previousApplicationSurface, top = old.scrollTop
    const replacement = old.cloneNode(false)
    old.replaceWith(replacement)
    replacement.append(...old.childNodes)
    replacement.scrollTop = top
  JS
  settle_workspace_layout
  assert page.evaluate_script("window.preservedReaderRoot === document.querySelector('.n-chat-workspace--saved')")
  assert_not page.evaluate_script("window.previousApplicationSurface.isConnected")
  assert_reader_following false
  assert_reader_anchor anchor
  stream_answer(reader_answer(100))
  assert_button "Latest message"
  assert_reader_anchor anchor
  click_button "Latest message"
  assert_reader_following true
  assert_operator reader_gap, :<=, 80
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

- [ ] **Step 8: Review and commit the atomic scroll migration.**

```bash
git diff --check
git add app/views/layouts/application.html.erb app/views/application/_header.html.erb app/assets/stylesheets/nosia/application_shell.css app/assets/tailwind/application.css app/javascript/controllers/scroll_controller.js test/integration/compact_headers_test.rb test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_workspace_layout_test.rb test/support/chat_workspace_browser_checks.rb
git commit -m "refactor(layout): Share one scrolling surface with application headers"
```

Specification review precedes quality review. No next task while an Important/Critical scroll, focus or ownership finding remains.

## Task 2: Compact the global Nosia bar on signed-in and signed-out pages

**Files:** Global header, shell CSS and compact-header tests.

- [ ] **Step 1: Add the bar-height and usable-control regression.**

Append to `CompactHeadersSystemTest`:

```ruby
test "global bar is compact without shrinking its usable controls" do
  [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: width, height: height, deviceScaleFactor: 1, mobile: false)
    visit accounts_path
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const header = document.querySelector('[data-application-header]')
        const controls = [header.querySelector('a'), document.getElementById('theme-toggle'),
          document.getElementById('dropdownUser'), document.getElementById('language_preference_locale')]
        return { viewport: [innerWidth, innerHeight], height: header.getBoundingClientRect().height,
          controls: controls.map(element => ({ id: element.id || 'home', width: element.getBoundingClientRect().width,
            height: element.getBoundingClientRect().height })) }
      })()
    JS
    header_record("bar-normal", geometry, screenshot: true)
    assert_equal [ width, height ], geometry.fetch("viewport")
    assert_operator geometry.fetch("height"), :>=, 48
    assert_operator geometry.fetch("height"), :<=, 52
    geometry.fetch("controls").each do |control|
      assert_operator control.fetch("height"), :>=, 44, control.to_json
      assert_operator control.fetch("width"), :>=, 44, control.to_json
    end
  end
end
```

The 48–52px range is for the normal-text fixture and accommodates the border. It must not become a fixed maximum that clips enlarged text or wrapped controls.

- [ ] **Step 2: Run RED before resizing the bar.**

```bash
record compact-bar-red browser_test test/system/compact_headers_test.rb -i '/global_bar_is_compact/'
```

Expected: existing 64px bar or undersized control geometry, not missing login/session setup.

- [ ] **Step 3: Keep the complete header content and change only its sizing hooks.**

Change the opening global `nav` and logo link/image classes:

```erb
<nav data-application-header class="n-application-header flex flex-wrap w-full items-center justify-between border-b n-main-border n-main-bg">
```

```erb
<%= link_to root_path, aria: { label: t("nosia.nav.home_page") }, class: "n-application-home rounded-lg n-main-focus" do %>
  <%= image_tag "nosia-logo.png", alt: "", aria: { hidden: true }, class: "h-6" %>
<% end %>
```

Preserve the existing language form and no-script submit, theme toggle IDs, dropdown attributes, profile/settings/logout links and conditional signed-in logic. Do not replace controls with new icons or a menu library.

Append to `application_shell.css`:

```css
.n-application-header { flex: none; min-height: 3rem; gap: .5rem; padding: .125rem .75rem; }
.n-application-header .n-application-home,
.n-application-header .n-nav-link {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 2.75rem;
  min-height: 2.75rem;
  padding: .25rem;
}
.n-application-header #language_preference_locale { min-width: 2.75rem; min-height: 2.75rem; padding-block: .25rem; }
.n-application-header :is(a, button, select):focus-visible {
  @apply outline-2 outline-offset-2 outline-green-700 dark:outline-green-300;
}
```

- [ ] **Step 4: Verify real language, theme and user-menu interactions.**

Add these private helpers to `CompactHeadersSystemTest` (keep the existing `header_record`):

```ruby
def header_viewport(width, height)
  page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
    width: width, height: height, deviceScaleFactor: 1, mobile: false)
  assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
end

def header_settle
  page.evaluate_async_script("const done = arguments[arguments.length - 1]; requestAnimationFrame(() => requestAnimationFrame(done))")
end

def header_top
  page.execute_script(<<~JS)
    const surface = document.querySelector('[data-application-scroll]')
    surface.scrollTop = 0
    surface.dispatchEvent(new Event('scroll'))
  JS
  header_settle
end

def header_theme(dark)
  header_top
  find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != dark
  assert_equal dark, page.evaluate_script("document.documentElement.classList.contains('dark')")
  header_settle
end

def header_tab_to(selector)
  160.times do
    if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
      assert_selector "#{selector}:focus"
      header_hit(selector)
      return
    end
    page.driver.browser.action.send_keys(:tab).perform
  end
  flunk "Keyboard traversal did not reach #{selector}"
end

def header_hit(selector)
  element = find(selector)
  sample = page.evaluate_script(<<~JS, element)
    (() => {
      const element = arguments[0], rect = element.getBoundingClientRect()
      const points = [[rect.left + rect.width / 2, rect.top + rect.height / 2],
        [rect.left + 2, rect.top + 2], [rect.right - 2, rect.bottom - 2]]
      return { ...rect.toJSON(), viewport: [innerWidth, innerHeight], hits: points.map(([x, y]) => {
        const hit = document.elementFromPoint(x, y)
        return !!hit && (hit === element || element.contains(hit))
      }) }
    })()
  JS
  assert_operator sample.fetch("left"), :>=, 0
  assert_operator sample.fetch("right"), :<=, sample.fetch("viewport").first + 1
  assert_operator sample.fetch("top"), :>=, 0
  assert_operator sample.fetch("bottom"), :<=, sample.fetch("viewport").last + 1
  assert sample.fetch("hits").all?, sample.to_json
  header_record("keyboard-hit", sample)
end
```

Add this public test above the class's `private` section:

```ruby
test "bar controls retain native language theme and profile navigation" do
  %w[en fr].each do |locale|
    visit accounts_path
    select locale.upcase, from: "language_preference_locale"
    assert_selector "html[lang='#{locale}']"
    [ false, true ].each do |dark|
      header_theme(dark)
      header_tab_to("#language_preference_locale")
      header_tab_to("#theme-toggle")
      header_tab_to("#dropdownUser")
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#dropdown:not(.hidden)"
      profile = "#dropdown a[href='#{profile_path}']"
      header_tab_to(profile)
      page.driver.browser.action.send_keys(:enter).perform
      assert_current_path profile_path
      assert_selector ".n-profile"
      assert_selector "html[lang='#{locale}']"
    end
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

These are real native controls and keyboard traversal, not `focus()` standing in
for keyboard navigation. Check signed-out root separately through Task 1's
request test. Save actual bar/menu rectangles and screenshots through the helper;
menus must not be clipped by the new scroll element.

```bash
record compact-bar-build rails_test tailwindcss:build
record compact-bar-green browser_test test/system/compact_headers_test.rb
record compact-bar-contracts rails_test test test/integration/compact_headers_test.rb test/internationalization/catalogs_test.rb
```

- [ ] **Step 5: Commit and pass both review gates.**

```bash
git add app/views/application/_header.html.erb app/assets/stylesheets/nosia/application_shell.css test/system/compact_headers_test.rb test/integration/compact_headers_test.rb
git commit -m "feat(layout): Compact the global application bar"
```

## Task 3: Compact page headings and disclose secondary descriptions

**Files:** Shared workspace/chat/dashboard headers, new-chat intro, account breadcrumb, shell CSS, paired layout locales and compact-header tests.

- [ ] **Step 1: Add markup and browser regressions before changing headings.**

Append to `CompactHeadersTest`:

```ruby
test "workspace descriptions are available without permanent header rows" do
  get profile_path
  assert_response :success
  assert_select ".n-workspace-header h1", count: 1
  assert_select ".n-workspace-header details[data-header-details]:not([open])", count: 1 do
    assert_select "summary", text: I18n.t("nosia.layout.details")
    assert_select ".n-workspace-help", text: I18n.t("nosia.profile.introduction")
    assert_select "nav[aria-label] .n-workspace-trail", count: 1
  end
end

test "saved header keeps primary context and live usage in one compact toolbar" do
  get chat_path(@chat)
  assert_response :success
  assert_select ".n-chat-toolbar h1.n-chat-title", count: 1
  assert_select ".n-chat-toolbar [data-chat-account-label]", text: @second.name
  assert_select ".n-chat-toolbar button[aria-controls=chat-history]", count: 1
  assert_select ".n-chat-toolbar a[href='#{new_chat_path}']", count: 1
  assert_select ".n-chat-toolbar #chat-usage-details:not([open])", count: 1
  assert_select "#chat-usage-details ##{dom_id(@chat, :token_totals)}", count: 1
end
```

The integration class includes `ActionView::RecordIdentifier`; the target
assertion uses the actual existing DOM identity rather than a guessed prefix.

Add this browser case to `CompactHeadersSystemTest`:

```ruby
test "saved header is compact and preserves the draft while disclosing usage" do
  page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
    width: 1400, height: 1000, deviceScaleFactor: 1, mobile: false)
  visit chat_path(@chat)
  assert_selector "lexxy-editor[connected]"
  find("lexxy-editor .lexxy-editor__content").send_keys("Keep this draft while reading usage")
  page.execute_script("window.headerDraftEditor = document.querySelector('lexxy-editor')")
  find("#chat-usage-summary").click
  assert_selector "#chat-usage-details[open] [data-chat-total-input]", text: "125"
  assert_selector "#chat-usage-details[open] [data-chat-total-output]", text: "24"
  find("#chat-usage-summary").click
  assert_no_selector "#chat-usage-details[open]", visible: :all
  geometry = page.evaluate_script(<<~JS)
    (() => {
      const header = document.querySelector('.n-chat-header'), title = header.querySelector('h1')
      const history = header.querySelector('[aria-controls=chat-history]')
      return { height: header.getBoundingClientRect().height,
        titleTop: title.getBoundingClientRect().top, actionTop: history.getBoundingClientRect().top }
    })()
  JS
  header_record("saved-heading", geometry, screenshot: true)
  assert_operator geometry.fetch("height"), :<=, 92
  assert_in_delta geometry.fetch("titleTop"), geometry.fetch("actionTop"), 20
  assert page.evaluate_script("window.headerDraftEditor === document.querySelector('lexxy-editor')")
  assert_includes find("lexxy-editor .lexxy-editor__content").text, "Keep this draft while reading usage"
  assert_selector "##{dom_id(@chat, :token_totals)}", count: 1, visible: :all
  assert_no_enqueued_jobs only: ChatResponseJob
end

test "page heading descriptions and trails remain operable through native details" do
  visit profile_path
  assert_selector ".n-workspace-header details[data-header-details]:not([open])"
  summary = ".n-workspace-header [data-header-details] > summary"
  160.times do
    break if page.evaluate_script("document.activeElement.matches(arguments[0])", summary)
    page.driver.browser.action.send_keys(:tab).perform
  end
  assert_selector "#{summary}:focus"
  page.driver.browser.action.send_keys(:enter).perform
  assert_selector ".n-workspace-header details[open] .n-workspace-help", text: I18n.t("nosia.profile.introduction")
  assert_selector ".n-workspace-header details[open] nav .n-workspace-trail"
  page.driver.browser.action.send_keys(:space).perform
  assert_no_selector ".n-workspace-header details[open]", visible: :all
end
```

- [ ] **Step 2: Run RED with real fixtures.**

```bash
record compact-heading-request-red rails_test test test/integration/compact_headers_test.rb
record compact-heading-browser-red browser_test test/system/compact_headers_test.rb -i '/page_heading|saved_header/'
```

The supplied test names match this selection. Verify the recorded run count is
nonzero; a zero-test selection is not RED.

- [ ] **Step 3: Add the paired native disclosure label.**

`config/locales/en.nosia_layout.yml`:

```yaml
en:
  nosia:
    layout:
      details: Details
```

`config/locales/fr.nosia_layout.yml`:

```yaml
fr:
  nosia:
    layout:
      details: Détails
```

- [ ] **Step 4: Replace the shared workspace header without losing actions/context.**

Complete `app/views/workspaces/_header.html.erb`:

```erb
<%# locals: (title:, description: nil, scope_label: nil, trail: [], back_path: nil, show_new_chat: false, actions: nil, breadcrumb_label: nil) %>
<% content_for :title, title %>
<header class="n-workspace-header">
  <div class="n-workspace-heading-row">
    <div class="min-w-0">
      <h1 class="n-workspace-title"><%= title %></h1>
      <% if scope_label %><p class="n-workspace-scope" data-workspace-scope><%= scope_label %></p><% end %>
    </div>
    <div class="n-workspace-actions">
      <% if description.present? || trail.any? %>
        <details class="n-header-details" data-header-details>
          <summary><%= t("nosia.layout.details") %></summary>
          <% if description %><p class="n-workspace-help"><%= description %></p><% end %>
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
        </details>
      <% end %>
      <% if back_path %><%= link_to t("nosia.actions.back"), back_path, class: "n-workspace-link", data: { workspace_back: true } %><% end %>
      <% if show_new_chat %>
        <div class="hidden lg:block"><%= link_to t("nosia.nav.new_chat"), new_chat_path, class: "n-workspace-link" %></div>
      <% end %>
      <%= actions %>
    </div>
  </div>
</header>
```

Scope labels remain directly visible: do not put selected-account/security context, validation errors, required guidance or primary action buttons inside this disclosure. Description/trail content remains escaped server-rendered markup with the same destinations.

- [ ] **Step 5: Compact saved chat while retaining stable usage ownership.**

Complete `app/views/chats/_header.html.erb`:

```erb
<header class="n-chat-header">
  <div class="n-chat-toolbar">
    <% if chat.persisted? %>
      <div class="n-chat-heading min-w-0">
        <h1 class="n-chat-title"><%= chat_workspace_title(chat, titles: titles) %></h1>
        <p class="n-workspace-help n-chat-account-preview" data-chat-account-label><%= chat.account.name %></p>
      </div>
    <% else %>
      <%= link_to t("nosia.nav.home"), user_root_path, class: "n-workspace-link" %>
    <% end %>
    <div class="n-workspace-actions">
      <% if chat.persisted? %>
        <%= link_to t("nosia.nav.home"), user_root_path, class: "n-workspace-link" %>
        <details id="chat-usage-details" data-chat-detail class="n-chat-details n-header-details">
          <summary id="chat-usage-summary"><%= t("nosia.chat_workspace.usage_details") %></summary>
          <p class="n-workspace-help"><%= chat.account.name %></p>
          <%= render "chats/token_totals", chat: chat %>
        </details>
      <% end %>
      <button type="button" class="n-workspace-button" aria-controls="chat-history" aria-haspopup="dialog"
              data-action="chat-dialog#open" data-chat-dialog-id-param="chat-history"><%= t("nosia.chat_workspace.history") %></button>
      <% if chat.persisted? %>
        <%= link_to t("nosia.chat_workspace.new_chat"), new_chat_path, class: "n-workspace-button" %>
      <% end %>
    </div>
  </div>
</header>
```

The readable full account name remains available in the operable Usage disclosure; the visible account preview supplies immediate context. The full first question remains in the transcript. There is still one Usage disclosure, one summary ID and one existing totals target. Do not change the background partial or stream subscription.

- [ ] **Step 6: Compact dashboard/new-chat/legacy heading presentation.**

Replace only the dashboard header, preserving its following composer/report/recent partials:

```erb
<header class="n-dashboard-heading n-workspace-heading-row">
  <h1><%= t("nosia.dashboard.welcome") %></h1>
  <details class="n-header-details" data-header-details>
    <summary><%= t("nosia.layout.details") %></summary>
    <p class="n-dashboard-help"><%= t("nosia.dashboard.title") %></p>
    <p class="n-dashboard-help"><%= t("nosia.dashboard.introduction") %></p>
  </details>
</header>
```

In `chats/new.html.erb`, remove the redundant `n-chat-eyebrow` paragraph only; preserve its h1, useful introduction paragraph, exact composer/actions and no-account guidance. The introduction is not required form guidance and can remain concise; do not remove PDF/account-source capabilities or add prompts.

Change the account breadcrumb's opening class from `mb-5 ...` to `mb-2 ...`; keep all links, `aria-current` and account labels unchanged. Add these density styles to the new shell stylesheet:

```css
.n-application-page :is(.n-workspace-title, .n-main-title, .n-title, .n-dashboard-heading h1) {
  font-size: 1.25rem;
  line-height: 1.4;
  font-weight: 600;
  overflow-wrap: anywhere;
}
.n-application-page > h1 { font-size: 1.25rem; line-height: 1.4; font-weight: 600; }
.n-application-page :is(.n-workspace-header, .n-dashboard-heading) { margin-block: 0 .75rem; }
.n-application-page :is(.n-workspace-heading-row, .n-account-header) { align-items: center; gap: .5rem 1rem; }
.n-application-page .n-workspace-actions { gap: .5rem; }
.n-application-page .n-workspace-scope { margin-block-start: .25rem; }
.n-header-details { min-width: 0; margin: 0; }
.n-header-details > summary {
  @apply text-sm font-medium text-green-800 dark:text-green-200;
  min-height: 2.75rem;
  cursor: pointer;
  padding: .625rem .25rem;
}
.n-header-details :is(p, nav) { max-inline-size: 65ch; overflow-wrap: anywhere; }
.n-header-details :is(summary, a):focus-visible { @apply outline-2 outline-offset-2 outline-green-700 dark:outline-green-300; }
.n-application-page .n-chat-heading { flex: 1 1 16rem; }
.n-application-page .n-chat-header .n-chat-title { margin: 0; font-size: 1rem; line-height: 1.4; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.n-application-page .n-chat-account-preview { max-inline-size: 36ch; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.n-application-page .n-chat-header .n-chat-details { margin: 0; }
.n-application-page .n-chat-title { font-size: 1.25rem; }
.n-application-page .n-chat-start { padding-block: .75rem; }
```

Do not apply single-line clipping to every h1 or to required form guidance. Only
the saved-chat preview is bounded, with full text available as described. The new
workspace header has one direct heading-row child, so the old sibling-spacing
utility no longer creates permanent description/trail rows.

- [ ] **Step 7: Verify hidden-copy access and protected actions.**

Open each new native Details through keyboard Enter; assert the exact existing description/trail text and primary account context, then close it. Normal headings must be compact; deliberately expanded details may grow naturally and scroll away. No fixed height may cut off translated text.

```bash
record compact-heading-build rails_test tailwindcss:build
record compact-heading-contracts rails_test test test/integration/compact_headers_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/profiles_controller_test.rb test/controllers/chat_workspace_test.rb test/internationalization/catalogs_test.rb
record compact-heading-browser-green browser_test test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_workspace_layout_test.rb
```

- [ ] **Step 8: Commit and pass specification then quality review.**

```bash
git add app/views/workspaces/_header.html.erb app/views/chats/_header.html.erb app/views/chats/new.html.erb app/views/dashboards/show.html.erb app/views/accounts/_breadcrumb.html.erb app/assets/stylesheets/nosia/application_shell.css config/locales/en.nosia_layout.yml config/locales/fr.nosia_layout.yml test/integration/compact_headers_test.rb test/system/compact_headers_test.rb
git commit -m "feat(layout): Compact page headings and disclose secondary context"
```

## Task 4: Migrate global geometry tests and verify every affected header family

**Files:** New compact-header system tests and narrow intentional changes to existing workspace browser tests; only browser-proven shell/header corrections.

- [ ] **Step 1: Update obsolete scrolling calls, not geometry assertions.**

Search these exact locations/files before editing:

```bash
rg -n "querySelector\('main'\).*scroll|const main = document.querySelector\('main'\)|nativeScroll" test/system test/support
```

The known affected set is:

```text
test/system/account_experience_test.rb
test/system/accounts_settings_workspace_test.rb
test/system/dashboard_test.rb
test/system/mcp_catalog_test.rb
test/system/mcp_workspace_test.rb
test/system/sources_workspace_test.rb
test/system/token_usage_workspace_test.rb
test/support/mcp_browser_checks.rb
```

Use these exact replacement semantics:

```javascript
// A deliberate programmatic scroll now targets the actual scroll owner.
document.querySelector('[data-application-scroll]').scrollTo({ top: 0, behavior: 'instant' })
```

```javascript
const surface = document.querySelector('[data-application-scroll]')
surface.scrollTop = surface.scrollHeight
```

If a test uses `const main = ...` for width, control containment or a rectangle, retain that reference and introduce `surface` separately. Do not globally replace every `main` selector: the semantic page still has its own real width/rectangle. Rename diagnostic fields where appropriate so evidence does not mislabel `main` as the scroller.

Tests in `agent_skills_workspace_test.rb`, `profile_management_test.rb` and the files above that assert visible header descriptions/trails must explicitly open their header's `[data-header-details]` before checking newly disclosed content. Preserve the text, destination, count, contrast and account-isolation assertions. Existing request `assert_select` checks still inspect server markup and should not need weakening.

- [ ] **Step 2: Add the application-wide locale/theme/size matrix.**

Extend `CompactHeadersSystemTest` using the existing fixture user and these real routes:

```ruby
def header_pages
  [ user_root_path, accounts_path, account_path(@second), sources_path,
    token_usage_path, settings_path, profile_path,
    account_agent_skills_path(@second), account_mcp_servers_path(@second),
    new_chat_path(account_id: @second.id), chat_path(@chat) ]
end
```

Add this private contrast sampler beside the Task 2 helpers. It measures only
supported opaque/alpha-composed normal surfaces and deliberately rejects effects
it cannot describe; native dialogs retain their existing separate checks.

```ruby
def header_contrast(selector, outline: false)
  header_hit(selector)
  sample = page.evaluate_script(<<~JS, find(selector), outline)
    (() => {
      const element = arguments[0], outline = arguments[1]
      if (element.closest('dialog')) throw new Error('Native top layer needs its existing separate measurement')
      const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
      const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
      const rgba = color => {
        if (!CSS.supports('color', color)) throw new Error('Unsupported CSS color')
        context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1)
        return [...context.getImageData(0, 0, 1, 1).data].map(value => value / 255)
      }
      const over = (fg, bg) => [...fg.slice(0, 3).map((value, i) => value * fg[3] + bg[i] * (1 - fg[3])), 1]
      const chain = []; for (let node = element; node; node = node.parentElement) chain.unshift(node)
      for (const node of chain) {
        const style = getComputedStyle(node)
        if (style.backgroundImage !== 'none' || Number(style.opacity) !== 1 || style.filter !== 'none' ||
            style.backdropFilter !== 'none' || style.mixBlendMode !== 'normal') throw new Error('Unmeasured paint effect')
      }
      const backgrounds = chain.map(node => getComputedStyle(node).backgroundColor)
      const background = backgrounds.slice(0, outline ? -1 : undefined).reduce((bg, color) => over(rgba(color), bg), [1, 1, 1, 1])
      const style = getComputedStyle(element), foreground = over(rgba(outline ? style.outlineColor : style.color), background)
      const light = color => color.slice(0, 3).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4)
        .reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0)
      const a = light(foreground), b = light(background)
      return { backgrounds, background, foreground, ratio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05),
        outlineWidth: parseFloat(style.outlineWidth), outlineStyle: style.outlineStyle }
    })()
  JS
  minimum = outline ? 3 : 4.5
  assert_operator sample.fetch("ratio"), :>=, minimum, sample.to_json
  if outline
    assert_selector "#{selector}:focus-visible"
    assert_operator sample.fetch("outlineWidth"), :>=, 2
    refute_equal "none", sample.fetch("outlineStyle")
  end
  header_record("contrast", sample.merge("selector" => selector, "minimum" => minimum))
end
```

Add the following public matrix test; `header_pages` belongs in the private
section. All context fields remain separate from sample fields in `header_record`.

```ruby
test "every header family reflows and scrolls in both locales and themes" do
  @second.update_columns(name: "CompteDeRecherche" * 12)
  %w[en fr].each do |locale|
    visit accounts_path
    select locale.upcase, from: "language_preference_locale"
    assert_selector "html[lang='#{locale}']"
    [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].each do |width, height|
      header_viewport(width, height)
      [ false, true ].each do |dark|
        header_pages.each_with_index do |path, index|
          visit path
          header_theme(dark)
          assert_selector "html[lang='#{locale}']"
          assert_selector "main h1", count: 1
          assert_selector "[data-application-header]", count: 1
          header_top
          assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
          assert page.evaluate_script("document.querySelector('[data-application-scroll]').scrollWidth <= innerWidth")
          header_contrast("main h1")
          header_tab_to("#theme-toggle")
          header_contrast("#theme-toggle")
          header_contrast("#theme-toggle", outline: true)
          header_top
          header_record("matrix-top-#{index}", { "route" => path }, screenshot: true)
          if page.has_selector?("[data-workspace-scope]", visible: :all)
            assert_selector "[data-workspace-scope]"
            assert_not page.evaluate_script("!!document.querySelector('[data-workspace-scope]').closest('[data-header-details]')")
          end
          sample = page.evaluate_script(<<~JS)
            (() => {
              const surface = document.querySelector('[data-application-scroll]'), main = document.querySelector('main')
              const synthetic = surface.scrollHeight - surface.clientHeight < 900
              if (synthetic) main.insertAdjacentHTML('beforeend', '<div data-header-overflow-fixture style="height:2200px"></div>')
              surface.scrollTop = 700
              surface.dispatchEvent(new Event('scroll'))
              return { syntheticOverflow: synthetic }
            })()
          JS
          header_settle
          gone = page.evaluate_script(<<~JS)
            (() => {
              const surface = document.querySelector('[data-application-scroll]'), boundary = surface.getBoundingClientRect().top
              return { globalBottom: document.querySelector('[data-application-header]').getBoundingClientRect().bottom,
                titleBottom: document.querySelector('main h1').getBoundingClientRect().bottom,
                boundary, top: surface.scrollTop, nestedMainTop: document.querySelector('main').scrollTop }
            })()
          JS
          header_record("matrix-scrolled-#{index}", sample.merge(gone), screenshot: true)
          assert_operator gone.fetch("globalBottom"), :<=, gone.fetch("boundary")
          assert_operator gone.fetch("titleBottom"), :<=, gone.fetch("boundary")
          assert_equal 0, gone.fetch("nestedMainTop")
        end
      end
    end
  end
  assert_no_enqueued_jobs only: ChatResponseJob
end

test "headers allow enlarged text to grow without clipping controls" do
  header_viewport(375, 812)
  visit profile_path
  begin
    page.execute_script("document.documentElement.style.fontSize = '200%'")
    header_top
    header_tab_to("#theme-toggle")
    header_tab_to("#language_preference_locale")
    assert page.evaluate_script("document.querySelector('[data-application-header]').getBoundingClientRect().height > 52")
    assert page.evaluate_script("document.querySelector('[data-application-scroll]').scrollWidth <= innerWidth")
    header_record("enlarged-css-text", { "nativeZoomVerified" => false }, screenshot: true)
  ensure
    page.execute_script("document.documentElement.style.removeProperty('font-size')")
  end
end
```

The CSS text-size case is explicitly **not** a native-zoom or screen-reader test.
For EN and FR, both themes, and the four actual viewports, inspect these outcomes:

1. Use the actual locale select/theme button, assert `html[lang]`, theme and actual `innerWidth/innerHeight`.
2. Record global/header/control rectangles at the top before scrolling. Preserve one meaningful h1 on pages that already have one.
3. Check width of the page, application surface and controls without hiding overflow. Long account names/titles must remain operably available.
4. With real long chat content, scroll the actual surface to an earlier paragraph and prove both top headers leave the viewport. For short non-chat pages, label added overflow fixtures explicitly; verify real controls independently.
5. Use real Tab/Shift+Tab, native details Enter/Space and actual dropdown interaction. Check all focused control bounds and center/inset hit tests, including the fixed bottom navigation and top-layer dialogs.
6. Save and visually inspect representative before/after screenshots for every header family, both chat pages in all four viewports and both themes, long labels, open details, language/user menus, History and Tools. Label the locale, theme, viewport, source commit and whether synthetic overflow was used.

For geometry evidence, use the existing canvas contrast sampler for supported normal surfaces, and keep its native-dialog exclusions/pixel checks. Do not infer normal text or glyph contrast from focus-outline color. Preserve minimum sampled text 4.5:1, meaningful icon/border 3:1 and a visible at-least-2px focus outline.

- [ ] **Step 3: Add a long-header/reflow reader regression.**

Starting with the existing 80-paragraph answer and a long account name, pause at a real paragraph. Expand header Usage (which changes content height above the transcript), collapse it, change from desktop to narrow and back, and deliver actual streamed body updates plus same-URL morph. Assert the same paragraph text and offset within the existing 1px tolerance, one surface ID throughout, unchanged focus under the existing Turbo exception, and Latest visibility only for actual new content below the reader.

Add to `ChatWorkspaceSystemTest` using its existing helpers:

```ruby
test "paused paragraph survives compact header height changes and viewport reflow" do
  @second.update_columns(name: "CompteDeRecherche" * 12)
  visit_reader(1400, 1000)
  pause_reader
  anchor = reader_anchor
  [ true, false ].each do |open|
    # Geometry-only stimulus: exercise height changes above the paused viewport
    # without pretending a deliberate keyboard scroll to the header should not move it.
    page.execute_script("document.getElementById('chat-usage-details').open = arguments[0]", open)
    settle_workspace_layout
    assert_reader_anchor anchor
  end
  [ [ 375, 812 ], [ 1400, 1000 ] ].each do |width, height|
    set_reader_viewport(width, height)
    settle_workspace_layout
    assert_equal "application-scroll", page.evaluate_script("#{reader_surface}.id")
    assert_reader_following false
    assert_reader_anchor anchor
  end
  stream_answer(reader_answer(100))
  assert_button "Latest message"
  assert_reader_anchor anchor
  refresh_workspace
  assert_reader_following false
  assert_reader_anchor anchor
  assert_no_enqueued_jobs only: ChatResponseJob
end
```

Actual keyboard opening/closing of native details is independently covered in
Task 3; this test isolates layout changes rather than claiming keyboard behavior.

- [ ] **Step 4: Run the affected suites sequentially and investigate failures.**

```bash
record compact-global-browser browser_test test/system/compact_headers_test.rb test/system/dashboard_test.rb test/system/accounts_settings_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb
record compact-account-browser browser_test test/system/account_experience_test.rb test/system/mcp_catalog_test.rb
record compact-protected-chat browser_test test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb
```

Statically audit the two additional legacy account/catalog files for external operations before executing them. Use the same local fixture adapters as their existing tests; if a test can contact a real service, stop and record it as unverified instead of silently stubbing away its workflow or launching it.

Classify failures as measurement/setup problems, intentionally migrated contracts or actual application regressions. A stale assumption about `main.scrollTop` is not evidence that reader physics must change. A real clipped footer, missing control, target loss, focus theft outside the accepted race or broken account authorization is not waived by this amendment. Run the reproducer before the minimal correction; preserve every failing log/screenshot.

- [ ] **Step 5: Commit only the verified migration/corrections.**

Stage the exact reviewed changed file list, not the whole worktree. Use:

```bash
git diff --check
git diff --name-only
git add -- test/system/compact_headers_test.rb test/system/account_experience_test.rb test/system/accounts_settings_workspace_test.rb test/system/dashboard_test.rb test/system/mcp_catalog_test.rb test/system/mcp_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/profile_management_test.rb test/system/chat_workspace_test.rb test/support/mcp_browser_checks.rb
git commit -m "test(layout): Verify compact scrolling headers across workspaces" -- test/system/compact_headers_test.rb test/system/account_experience_test.rb test/system/accounts_settings_workspace_test.rb test/system/dashboard_test.rb test/system/mcp_catalog_test.rb test/system/mcp_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/profile_management_test.rb test/system/chat_workspace_test.rb test/support/mcp_browser_checks.rb
```

Omit unchanged paths from staging if convenient. A browser-proven application
correction requires an additional explicit reviewed path in its own small commit;
do not stage an unknown file or blindly run `git add .`. Specification review and
quality review must inspect actual screenshots/measurements and test migrations
before approval.

## Task 5: Update documentation and run the final protected selections

**Files:** New `docs/compact-headers.md`, existing docs index/composer/chat guides; external evidence manifest/checklist.

- [ ] **Step 1: Write the user guide and remove superseded scroll claims.**

Create `docs/compact-headers.md` with this content:

```markdown
# Compact headers

The global Nosia bar and page headings share the content's scrolling surface on
all application pages. They scroll away rather than reserving permanent space
above the content. The global bar is approximately 48px at normal text size;
controls and translated/enlarged labels may grow instead of being clipped.

Titles and primary actions share a compact row where space permits. Details
reveals secondary descriptions and breadcrumbs; selected-account context,
required form guidance, validation errors and primary actions remain available.
Language, theme, profile/settings/logout, account navigation and chat controls
retain their existing functions. Keyboard navigation can scroll controls into
view; it does not require a permanently pinned bar.

Chat keeps its existing 80px pre-growth follow threshold, paragraph anchors,
Latest message and successful-own-follow-up resume. The application scroll
element is its primary surface at every viewport size; the previous desktop
transcript-versus-narrow-page split no longer applies. Editors, dialogs and wide
code/tables retain bounded local scrolling. Fixed bottom navigation still has
clearance and is not part of the top-header redesign.

The existing narrow Turbo-native focus-race exception remains documented in
[Chat workspace](chat-workspace.md). Native zoom, screen readers, live providers
and the unsafe unrestricted suite require separate verification; viewport and
screenshot tests do not establish those checks.
```

Update `docs/chat-workspace.md`'s old breakpoint-based primary-scroll paragraph to the new single application surface, without deleting the 80px rule, safeguards, accepted Turbo exception or verification limitations. Add a compact-headers link to `docs/README.md` and a brief link/boundary update in `docs/chat-composer.md`. Do not rewrite historical evidence as if rerun.

- [ ] **Step 2: Run the complete explicit protected contract selection.**

```bash
record compact-final-build rails_test tailwindcss:build
record compact-final-focused rails_test test test/integration/compact_headers_test.rb test/controllers/chat_workspace_test.rb test/integration/chat_message_rendering_test.rb test/integration/chat_composer_ui_test.rb test/integration/composer_partials_render_test.rb test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_sources_test.rb test/controllers/chat_account_tools_test.rb test/controllers/chat_account_citations_test.rb test/controllers/chat_account_url_race_test.rb test/controllers/chat_sources_controller_test.rb test/models/chat_test.rb test/models/dashboard_recents_test.rb test/controllers/accounts_workspace_shell_test.rb test/controllers/sources_workspace_shell_test.rb test/controllers/token_usage_workspace_shell_test.rb test/controllers/settings_workspace_test.rb test/controllers/mcp_workspace_shell_test.rb test/controllers/agent_skills_workspace_shell_test.rb test/controllers/profiles_controller_test.rb test/internationalization/catalogs_test.rb test/integration/token_footer_test.rb
record compact-final-chat browser_test test/system/compact_headers_test.rb test/system/chat_workspace_test.rb test/system/chat_composer_ui_test.rb test/system/chat_account_selection_test.rb test/system/chat_workspace_layout_test.rb
record compact-final-workspaces browser_test test/system/dashboard_test.rb test/system/accounts_settings_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/agent_skills_workspace_test.rb test/system/mcp_workspace_test.rb test/system/profile_management_test.rb
```

Run only after checking each file exists and remains fixture/local-adapter safe. The Task 4 extra legacy selection is reported separately, including any safety-blocked checks. Never substitute an unrestricted suite or a live worker.

- [ ] **Step 3: Lint exact changed Ruby files and compare security fingerprints.**

```bash
git diff --name-only --diff-filter=ACMR 2257c51 -- '*.rb' > "$EVIDENCE/compact-changed-ruby.txt"
record compact-final-lint test_command bundle exec ruby -e 'files=File.readlines(ARGV.fetch(0),chomp:true); abort "No Ruby files" if files.empty?; exec "bundle","exec","rubocop",*files' "$EVIDENCE/compact-changed-ruby.txt"
if record compact-final-security test_command bundle exec brakeman --no-pager --format json --output "$EVIDENCE/compact-final-security.json"; then
  security_exit=0
else
  security_exit=$?
fi
test "$security_exit" -eq 0 || test "$security_exit" -eq 3 || exit "$security_exit"
```

Keep the helper's `RUBOCOP_TARGET_RUBY_VERSION=4.0`; no auto-fix of unrelated code. The scanner may return the known exit 3. Compare the actual JSON fingerprints with `/tmp/opencode/chat-workspace-hqSpCt/task7-baseline-security.json`:

```text
4fad3c218f35052d2f3a3eff4544480d05b60bc9199a001ec6242a8921b93ae3
d84924377155b41e094acae7404ec2e521629d86f97b0ff628e3d1b263f8101c
```

Compare actual machine-readable results, then parse the four existing chat
controllers using only the already installed runtime:

```bash
record compact-final-security-compare python3 -c 'import json,sys; from pathlib import Path; root=Path(sys.argv[1]); baseline=json.loads((root/"task7-baseline-security.json").read_text()); current=json.loads((root/"compact-final-security.json").read_text()); before={w["fingerprint"] for w in baseline["warnings"]}; after={w["fingerprint"] for w in current["warnings"]}; result={"new":sorted(after-before),"fixed":sorted(before-after),"errors":current.get("errors",[])}; print(json.dumps(result,indent=2)); sys.exit(0 if before==after and not result["errors"] else 1)' "$EVIDENCE"
record compact-js-reader node --input-type=module --check < app/javascript/controllers/scroll_controller.js
record compact-js-dialog node --input-type=module --check < app/javascript/controllers/chat_dialog_controller.js
record compact-js-disclosures node --input-type=module --check < app/javascript/controllers/chat_disclosures_controller.js
record compact-js-feedback node --input-type=module --check < app/javascript/controllers/chat_feedback_controller.js
```

No new warnings are accepted automatically; do not suppress either baseline
finding. An unexpected removal also gets inspected rather than silently called a
security repair. Do not install Node or a bundler for this task. Check relative
Markdown links, `git diff --check`, `git diff --stat 2257c51` and source ownership.

- [ ] **Step 4: Record an honest handoff and commit documentation.**

The evidence manifest must include the exact implementation commits, commands/logs/true exits/counts, before/after header geometry, screenshots actually inspected, meaningful contrast samples, all intentional test-contract migrations and pending manual checks. Note explicitly that no live providers/workers, native-zoom substitute, screen-reader certification or unrestricted full-suite pass is claimed. Keep the user-owned environment/process boundary.

```bash
git add docs/compact-headers.md docs/README.md docs/chat-workspace.md docs/chat-composer.md
git commit -m "docs(layout): Explain compact scrolling application headers"
```

- [ ] **Step 5: Complete final independent review and ask before integration.**

After task specification/quality gates, dispatch a whole-feature review covering the original chat work plus this layout amendment. Provide the actual baseline, head, accepted decisions, evidence and known limitations. Fix new Important/Critical findings through a test-first implementer and re-review. Only then offer merge/PR/keep-branch options; do not push, merge, open a PR or remove any worktree automatically.

## Spec coverage and planning self-review

| Approved requirement | Tasks |
| --- | --- |
| Both top headers scroll out on every application page | 1, 4 |
| Approximately 48px global bar, usable controls and preserved menus | 2, 4 |
| Compact title/actions and operable secondary information | 3, 4 |
| Visible account/security context, errors and required guidance | 3, 4 |
| One primary scroll owner, no blank reserved slot or auto-hide timers | 1 |
| Reader 80px pre-growth semantics/anchors/morph/own-success resume | 1, 4, 5 |
| Existing Stop correction independently reviewed; truthful background unlock | 0, 1, 5 |
| Composer, dialogs, IDs/order/streams, unchanged authorization/accounting | 1, 3, 4, 5 |
| EN/FR, themes, long content, keyboard, short/narrow/tablet layouts | 2, 3, 4 |
| Isolated sequential verification and preserved exceptions/limitations | 0, all tasks, 5 |
| Documentation, independent gates and user-directed integration | 5 |

The proposed code uses the existing fixture loader and route names verified in
the repository. The application scroll marker is consistently
`[data-application-scroll]`, with stable ID `application-scroll`. No new production
Ruby API, model state or JS lifecycle owner is required. Runtime measurements and
command outcomes belong to execution evidence; none have been fabricated during
planning.

## Planning validation record

- Checked all 11 coverage mappings against the approved written specification and
  its explicit Decisions, including the global scope and non-pinned behavior.
- Verified referenced source/test/document paths exist or are explicitly listed
  new files. Checked existing route/helper names against the current source.
- Parsed the plan's Ruby, JavaScript and shell code blocks without executing them;
  getter/object fragments were wrapped only for syntax checking. This does not
  establish application behavior or test outcomes.
- Reviewed the marker/ID, `surface` reference, retarget condition, geometry-field
  names, paired locale key and closed-details semantics across tasks. Sample data
  is nested under `sample` to avoid overwriting evidence context.
- No application implementation, Rails boot, browser run, database operation,
  asset build, security scan or dependency installation was performed for this
  planning change. Execution mode and the Task 0 gates remain the next steps.
