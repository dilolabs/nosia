# Notes Compact Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development or superpowers-ruby:executing-plans after the user chooses the execution mode. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the Notes header with Sources without adding permanent rows or changing the account dropdown.

**Architecture:** Reuse the shared workspace title and control classes in the Notes views. Keep Notes' own responsive flex layout and existing navigation, account popover, and Turbo replacement boundaries.

**Tech Stack:** Rails ERB, Tailwind CSS, Stimulus, Minitest and Chromium.

---

Approved spec: `docs/superpowers/specs/2026-11-22-notes-compact-header-design.md`. Execute in `.worktrees/notes-compact-header` on `feat/notes-compact-header`, starting at `f303879`. The root `feat/notebook` has unrelated unstaged CSS, test, import and schema changes; do not copy, stash, reset, or overwrite them. Leave integration for a separate decision.

Use the isolated PostgreSQL test database `nosia_notes_header_f303879_test`. In a shell started with `unshare -Urn zsh`, use:

```sh
ip link set lo up
source /tmp/opencode/nosia-notes-test-env.sh
export RAILS_ENV=test
export DATABASE_URL='postgresql:///nosia_notes_header_f303879_test?host=%2Fvar%2Frun%2Fpostgresql&port=5432&user=cbldev'
browser() {
  bundle exec ruby -rselenium-webdriver -e '
    Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"
    Selenium::WebDriver::Chrome.path = "/tmp/opencode/nosia-notes-release-chromium"
    load "bin/rails"
  ' test "$@"
}
```

The committed baseline differs from `4bb79e1` only by the design document. After `bin/rails tailwindcss:build`, the Notes request and view-copy baseline at seed `35658` passed 77 tests / 691 assertions. No database or dependency changes are required.

### Task 1: Reuse the Sources visual language in the compact Notes header

**Files:**
- Modify `app/views/notes/workspaces/show.html.erb` (title and search).
- Modify `app/views/notes/workspaces/_header_actions.html.erb` (primary/secondary action classes).
- Modify `app/views/notes/workspaces/_accounts.html.erb` and `_dropdown.html.erb` (header-only styling while retaining the same account popover).
- Modify `app/assets/stylesheets/nosia/notes_workspace.css` (scoped layout and responsive overflow).
- Test `test/system/notes_workspace_test.rb` and run `test/controllers/notes_workspace_test.rb`.

- [x] **Write a red layout test** in `NotesWorkspaceBrowserTest`; reuse the existing account menu keyboard, long French label and no-JavaScript tests:

```ruby
test "the Notes header keeps its controls on one row when space permits" do
  visit account_notes_workspace_path(@account, view: "list")
  [ [ 1440, 900 ], [ 900, 768 ], [ 375, 800 ] ].each do |width, height|
    orbite_viewport(width, height)
    [ false, true ].each do |dark|
      orbite_theme(dark)
      title = find(".n-notes-header h1")
      account = find("[data-notes-accounts] button")
      search = find(".n-notes-search input[type=search]")
      primary = find_link("New note")
      midpoints = page.evaluate_script(<<~JS, title, account, search, primary)
        [...arguments].map(node => {
          const rect = node.getBoundingClientRect();
          return rect.top + rect.height / 2;
        })
      JS
      if width == 1440
        assert_in_delta midpoints.first, midpoints.max, 1
        assert_in_delta midpoints.first, midpoints.min, 1
      elsif width == 375
        assert_operator midpoints[0], :<, midpoints[1]
        assert_operator midpoints[1], :<, midpoints[2]
      end
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
    end
  end
end
```

- [x] **Run red.** `browser test/system/notes_workspace_test.rb -i '/controls on one row/'` failed at 1440 px: the title and controls had centers 36.4 px apart in the old layout.

- [x] **Implement the header styling.** Use the existing `.n-workspace-title` on the Notes workspace `h1`, `.n-field` on the search field, and `.n-workspace-button` on the existing submit and secondary header links. Use `class: "n-workspace-button n-workspace-primary"` for New note; don't keep the Notes primary class, which would override the shared palette. Keep `#notes-header-actions`, `data-notes-accounts`, all targets, labels, and route arguments. Give `_dropdown.html.erb` an optional strict local `button_class: "n-notes-button"` and change only the button class string to:

```erb
class="<%= button_class %> n-notes-menu-trigger<%= " n-notes-icon-button" if icon %>"
```

Opt into shared account control styles from the compact header only, keeping the conflict page unchanged. Give the compact single-account paragraph `.n-workspace-scope` and reset its margin in the header. In `notes_workspace.css`, retain the current `.n-notes-header` and `.n-notes-search` flex behavior, keep legacy typography off the shared title and account label, and add:

```css
.n-notes-header .n-notes-identity {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: .375rem .75rem;
}
.n-notes-header [data-notes-accounts] { min-inline-size: 0; max-inline-size: 100%; }
.n-notes-header [data-notes-accounts] > .n-workspace-scope { margin-block-start: 0; }

@media (width < 48rem) {
  .n-notes-header [data-notes-accounts] { flex-basis: 100%; }
}
```

Keep the existing search mobile full-width breakpoint and native account popover. Use the same links and form submit in all layouts. Keep the field at 44 px, exclude it from the Notes-only form palette and preserve the primary action's visible focus ring. Scope changes to the header and do not edit shared Sources styles, `lexxy.css`, or preview styles.

- [x] **Run green and verify.** Run `bin/rails tailwindcss:build`; repeat the new test and run `browser test/system/notes_workspace_test.rb test/system/notes_markdown_import_test.rb` to cover CSS, switching accounts, Escape, keyboard order, long French labels, 375/900/1440 widths and the existing importer link. Run `bin/rails test test/controllers/notes_workspace_test.rb test/internationalization/view_copy_test.rb`, scoped `RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop test/system/notes_workspace_test.rb`, and `git diff --check`. Inspect the final diff for changes outside the header and its tests.

  The full Rails run passed 1,889 tests and the Chromium Notes suites passed 104 tests on retry. Final review narrowed the new styling to the workspace header, leaving the existing conflict page unchanged. After that adjustment, the build, lint, whitespace checks, 77 Rails tests and 9 Chromium tests (including the conflict page and account switcher) passed.

- [x] **Commit the scoped branch change.** Include only the tested Notes templates, Notes stylesheet, system test, and this plan. Do not merge, push, or alter the root workspace.
