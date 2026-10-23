# Remove topbar search

**Date:** 2026-10-23

**Status:** Design and written specification approved; implementation planning authorized. Application implementation has not started.

## Goal

Completely remove the existing topbar search button and search dialog. Do not implement a replacement search.

## Decisions

- "completely remove the search button in the topbar and search dialog @app/views/application/_search.html.erb" — remove the existing entry point and dialog, rather than hiding them.
- "I'll implement a new search later" — replacement search is outside this change.
- "Full cleanup (Recommended)" — remove verified search-only supporting dependencies, assets, translations, and helper code along with the button and dialog.
- "Good" in response to the proposed design — approve full removal, preservation of the remaining header and backend behavior, and regression coverage before implementation.
- "Go" after the committed specification was presented for review — approve the written specification and proceed to implementation planning.

## Current context

- `app/views/application/_header.html.erb` renders the search button and `search` partial when both `Current.user` and `Current.account` are present.
- `app/views/application/_search.html.erb` supplies the Tailwind Plus command palette and eagerly loads chats, sources, and accounts for it.
- Application code currently uses Tailwind Plus Elements only in this dialog. Its JavaScript import, importmap pin, and vendored file become unused after removal.
- The search SVG, dialog translation keys, and `User#recent_chats` are specific to this UI in the inspected application code. Recheck references during implementation to account for concurrent workspace changes.
- Existing integration tests cover authenticated account contexts and already assert the search button is absent for a user without an account.
- There are unrelated tracked and untracked changes in the workspace; preserve them and exclude them from this design commit.

## Approaches

1. **Full removal (selected):** delete the entry point, dialog, and verified exclusively owned support code. This leaves no dormant implementation to maintain and matches the selected cleanup scope.
2. **UI-only removal:** delete the button and dialog but retain their dependencies and assets. This is a smaller diff but leaves dead code and unnecessary browser JavaScript.
3. **Disable behind a feature flag:** retain the existing implementation for possible reactivation. This is reversible but conflicts with complete removal and adds unnecessary configuration before an independently designed replacement.

## Architecture and removal boundary

- Remove the authenticated search conditional, button, and partial render from `app/views/application/_header.html.erb`, and delete `app/views/application/_search.html.erb`.
- Remove the Tailwind Plus Elements import in `app/javascript/application.js`, pin in `config/importmap.rb`, and vendored `vendor/javascript/@tailwindplus--elements.js`; the dialog is the only application markup using its custom elements.
- Delete `app/assets/images/svg/search.svg` after a final reference check. Preserve the distinct `file-search.svg` icon used by the navigation menu.
- Delete `User#recent_chats`, whose only caller is the removed partial, and the seven search-only `nosia.nav` keys from both `config/locales/en.nosia_shell.yml` and `config/locales/fr.nosia_shell.yml`: `search`, `search_placeholder`, `recent_chats`, `quick_actions`, `ask_question`, `jump_to`, and `no_search_results`. Preserve all other locale entries and concurrent locale edits.

## Preserved behavior and data flow

- Preserve the home link, language preference, theme toggle, user menu, existing navigation, and all backend retrieval/search behavior. Do not add replacement UI, routes, database changes, or a feature flag.
- The header no longer renders search-related records or markup. There is no replacement data flow or error state; a deleted search partial must have no remaining render calls or dangling dialog controls.
- Keep Flowbite, Turbo, Stimulus, Lexxy, and their imports intact. Removing Tailwind Plus Elements must not remove shared UI infrastructure.
- Do not retain hidden search markup, add a disabled placeholder, or reserve an empty search slot. Existing flex spacing naturally closes around the removed button.

## Verification and acceptance criteria

- Add Minitest integration coverage using existing fixtures before changing application code. Run the new authenticated-with-account absence test and confirm it fails because the existing search is rendered, then implement the removal and confirm it passes.
- Verify the search trigger (`#toggleSidebarMobileSearch`), its `commandfor="dialog"` control, `dialog#dialog`, and `el-command-palette` are absent for an authenticated user with an account, an authenticated user without an account, and an anonymous visitor. Exercise English and French responses.
- Verify the home link, language preference control, and theme toggle remain present. Authenticated responses retain the user menu; anonymous responses retain its existing absence.
- Verify the rendered importmap no longer includes Tailwind Plus Elements and no application references remain to the deleted partial, helper, icon, translation keys, or dependency. Historical documentation and explicit regression assertions are not dangling runtime references.
- Run the focused rendering tests and existing account-access and localization regression tests. Verify asset precompilation has no missing dependency or asset references; if the local environment prevents execution, report the exact blocker rather than claiming verification.
- Keep all unrelated tracked and untracked workspace changes untouched. Where a scoped file already contains other edits, change only the search-specific lines.
