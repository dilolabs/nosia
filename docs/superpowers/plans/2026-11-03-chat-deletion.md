# Saved Chat Deletion Implementation Plan

> **For agentic workers:** Use `executing-plans` to implement this plan task-by-task in the current session. Steps use checkbox syntax for tracking.

**Goal:** Offer polished, confirmed deletion directly from a saved conversation.

**Architecture:** Reuse `ChatsController#destroy`, its authorization, and the shell's `chat-dialog` controller. Add a focused confirmation partial and local Orbite styles. No migrations, dependencies, or new JavaScript controller.

**Tech Stack:** Rails, ERB, Turbo, Stimulus, CSS/Tailwind, Minitest fixtures, Selenium.

**Specification:** `docs/superpowers/specs/2026-11-03-chat-deletion-design.md`.

---

## Files and responsibilities

- Create `test/integration/chat_deletion_test.rb`: localized dialog/form contract, actual cascade, redirect, access isolation.
- Create `test/system/chat_deletion_test.rb`: actual modal interaction, cancellation, keyboard focus, draft preservation, confirmation, responsive themes.
- Modify `test/system/premium_chat_header_test.rb`: replace the obsolete blanket ban on header buttons with an assertion allowing only the delete trigger.
- Modify `test/system/orbite_workspace_test.rb` and `test/system/compact_headers_test.rb`: update the same saved-header expectation, while retaining the no-action contract for new chats.
- Modify `app/views/chats/_header.html.erb`: add the delete opener beside the title.
- Create `app/views/chats/_deletion.html.erb`: confirmation dialog and destructive Rails form.
- Modify `app/views/chats/show.html.erb`: render the dialog outside the scroll surface.
- Modify `app/assets/stylesheets/nosia/orbite_chat.css`: button, modal surface, warning, and responsive action row.
- Modify `config/locales/{en,fr}.nosia_chat_workspace.yml`: action, warning, cancel, and submission labels.
- Modify `app/controllers/chats_controller.rb`: explicit 303 after deletion.

## Task 1: Characterize and test the complete deletion contract

- [x] Add fixture-based integration tests using `ChatWorkspaceFixtures` and `sign_in_picker_user`. For each English/French locale, request the chat and assert one `#chat-delete-trigger`, its accessible name, hidden decorative SVG, and `aria-controls=chat-delete-dialog`. Assert a closed, labelled and described `dialog#chat-delete-dialog`, Cancel with `data-chat-dialog-initial-focus`, and a form with the correct chat action, `_method=delete`, and localized `data-turbo-submits-with`.

```ruby
test "deletes the owned chat and messages with a safe redirect" do
  message_ids = @chat.messages.ids
  assert_not_empty message_ids
  delete chat_path(@chat)
  assert_response :see_other
  assert_redirected_to root_path
  refute Chat.exists?(@chat.id)
  assert_empty Message.where(id: message_ids)
end
```

- [x] Also assert no deletion trigger/dialog on `new_chat_path`; deleting another user's chat or an owned chat after membership revocation returns 404 and preserves records.
- [x] Run `PARALLEL_WORKERS=1 bin/rails test test/integration/chat_deletion_test.rb`. Expected red: missing trigger/dialog and 302 instead of 303; authorization characterization already passes.

## Task 2: Implement the server-rendered interface

- [x] Add the following header button next to `.n-chat-heading`:

```erb
<button id="chat-delete-trigger" type="button" class="n-orbite-control n-chat-delete-trigger"
        aria-label="<%= t('nosia.nav.delete_chat') %>" title="<%= t('nosia.nav.delete_chat') %>"
        aria-controls="chat-delete-dialog" aria-haspopup="dialog"
        data-action="chat-dialog#open" data-chat-dialog-id-param="chat-delete-dialog">
  <%= inline_svg "svg/trash-bin.svg", aria_hidden: true, class: "h-5 w-5" %>
</button>
```

- [x] Create the deletion partial, using `chat_workspace_title(chat, titles: titles)` for a safely escaped conversation title:

```erb
<%# locals: (chat:, titles:) %>
<dialog id="chat-delete-dialog" class="n-chat-dialog n-chat-delete-dialog"
        aria-labelledby="chat-delete-title" aria-describedby="chat-delete-description"
        data-action="close->chat-dialog#closed">
  <div class="n-chat-delete-symbol" aria-hidden="true"><%= inline_svg "svg/trash-bin.svg", aria_hidden: true, class: "h-6 w-6" %></div>
  <h2 id="chat-delete-title"><%= t("nosia.chat_workspace.delete_title") %></h2>
  <p class="n-chat-delete-name"><%= chat_workspace_title(chat, titles: titles) %></p>
  <p id="chat-delete-description"><%= t("nosia.chat_workspace.delete_description") %></p>
  <div class="n-chat-delete-actions">
    <button type="button" class="n-workspace-button" data-chat-dialog-initial-focus data-action="chat-dialog#close"><%= t("nosia.chat_workspace.cancel") %></button>
    <%= button_to t("nosia.nav.delete_chat"), chat_path(chat), method: :delete,
          class: "n-workspace-button n-chat-delete-confirm",
          data: { turbo_submits_with: t("nosia.chat_workspace.deleting") } %>
  </div>
</dialog>
```

- [x] Render at the bottom of `show.html.erb` with `<%= render "chats/deletion", chat: @chat, titles: @history_titles %>`.
- [x] Add translations: EN `delete_title: Delete this conversation?`, `delete_description: This conversation and all its messages will be permanently deleted. This action cannot be undone.`, `cancel: Cancel`, `deleting: Deleting…`; FR `delete_title: Supprimer cette conversation ?`, `delete_description: Cette conversation et tous ses messages seront définitivement supprimés. Cette action est irréversible.`, `cancel: Annuler`, `deleting: Suppression…`.
- [x] Change only the destroy redirect to `redirect_to root_path, status: :see_other`.
- [x] Style within `.n-orbite-shell`: 44px nonshrinking trigger; neutral resting color; danger hover/focus; 28rem modal with `margin: auto`, 1.5rem padding, 1rem radius, opaque theme surface, and shadow; visible warning icon; wrap long titles; flex action row wrapping at narrow widths. Reuse existing danger colors and buttons. No new animation; respect inherited reduced motion behavior.
- [x] Run `PARALLEL_WORKERS=1 bin/rails test test/integration/chat_deletion_test.rb test/integration/premium_chat_header_test.rb test/controllers/chat_account_access_test.rb`. Expected green.

## Task 3: Verify real interaction and regressions

- [x] Add browser tests with `ChatWorkspaceFixtures`. Log in through the existing email/password form, visit the saved chat, close open history if needed, and scroll the reading surface to the header. In light/dark themes at 375px and desktop width, open the dialog, assert Cancel focus, cancel and Escape with focus restored, and assert a typed composer draft survives. Verify no overflow and a 44px trigger. Confirm deletion from the actual form and assert navigation away, database deletion, and absence from history.

```ruby
find("#chat-delete-trigger").click
assert_selector "#chat-delete-dialog:modal"
assert_selector "#chat-delete-dialog [data-chat-dialog-initial-focus]:focus"
click_on "Cancel"
assert_no_selector "#chat-delete-dialog[open]", visible: :all
assert_selector "#chat-delete-trigger:focus"
```

- [x] Run the browser tests once before implementation when possible; missing trigger is the expected red. Change the older premium-header assertion to forbid only unrelated header links/buttons, explicitly allowing `#chat-delete-trigger`.
- [x] Run `PARALLEL_WORKERS=1 bin/rails test test/system/chat_deletion_test.rb test/system/premium_chat_header_test.rb` and the chat integration/controller suites. Check screenshots in both themes and at narrow width.
- [x] Run `bundle exec rubocop app/controllers/chats_controller.rb test/integration/chat_deletion_test.rb test/system/chat_deletion_test.rb test/system/premium_chat_header_test.rb` and `git diff --check`. Self-review with Rails review guidance, confirm no unrelated changes, and report exact verification results. No new public Ruby domain API requires YARD. Keep feature implementation uncommitted unless requested.

## Execution notes

- The user explicitly selected the current directory, a dedicated feature branch, and no implementation commit; no worktree or subagents are used.
- Baseline account-access tests passed: 3 runs, 100 assertions.
- Red integration run: 6 runs, 26 assertions, 3 expected failures (missing localized trigger/dialog and 302 instead of 303).
- On this ARM host, Selenium's bundled manager is x86-only. Use the existing documented process-local driver override, without modifying dependencies: `PARALLEL_WORKERS=1 EVIDENCE=/tmp/opencode bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test <explicit files>`.
- The red browser run using that override reached the saved conversation and failed because `#chat-delete-trigger` was absent.

## Verification results

- Ruby-native `bin/rails tailwindcss:build`: passed.
- Application regression selection: `PARALLEL_WORKERS=1 bin/rails test test/integration/chat_deletion_test.rb test/integration/premium_chat_header_test.rb test/integration/chat_composer_ui_test.rb test/integration/orbite_shell_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_workspace_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chats_controller_test.rb test/controllers/messages_controller_test.rb test/models/chat_test.rb`: **102 runs, 1,453 assertions, no failures/errors/skips**.
- Browser run with the process-local driver override and explicit files `test/system/chat_deletion_test.rb test/system/premium_chat_header_test.rb`: **12 runs, 4,001 assertions, no failures/errors/skips**. This run preceded the extra landscape-only deletion test; production code is unchanged afterward.
- Final browser selection with the same override: `test/system/chat_deletion_test.rb test/system/orbite_workspace_test.rb test/system/compact_headers_test.rb --include '/cancellation|confirmed_deletion|long_titles|mobile_accounted_chat_headers|saved_header_keeps/'`: **6 runs, 944 assertions, no failures/errors/skips**. Covers all four final deletion tests and the two updated older header tests.
- RuboCop on the controller and five changed/new Ruby test files: **6 files, no offenses**. `git diff --check`: passed.
- Inspected English desktop and French 375px modal screenshots in both themes, the French saved-header screenshot, and the 812×375 reduced-motion long-title dialog. Evidence remains under `/tmp/opencode/orbite-20261103-314945-yr4xuf/`, `/tmp/opencode/orbite-20261103-316234-nrpl2s/`, `/tmp/opencode/orbite-20261103-316234-pfl03e/`, and `/tmp/opencode/orbite-20261103-316234-iyrvzb/`.
- Self-review: no blocking findings. The change retains existing ownership/membership authorization, safely escaped bounded titles, CSRF-protected DELETE forms, and a single existing modal owner. No new public domain API, migration, dependency, or worker execution was introduced.
- The unrestricted suite and unrelated scanners were not run. The implementation was initially left uncommitted on `feat/chat-deletion`; the user subsequently requested committing the feature.
