# Separate Settings Tools Workspaces

System prompts, account members and personal API tokens have separate pages with shared Balanced styling. Shared presentation does not merge their management or permissions.

## System prompts

`/system_prompts` lists existing system-prompt records in the accounts you are authorized to access. **Account default** and **User-specific** describe the record type, not a new privacy boundary. Read pages display the literal prompt; use **Edit** where permitted, then explicitly **Save**, or **Cancel** to discard unsaved changes.

`/accounts/:account_id/system_prompt` displays the saved account default or a clearly identified built-in fallback. Reading or opening Edit does not save that fallback: only a valid, explicit Save materializes it. User-specific prompt precedence is unchanged. These pages add no prompt runner, autosave, history, or create/delete controls.

## Account members

`/accounts/:account_id/account_users` is owner-only. Add an **existing Nosia user** by email. This creates an account membership, not an invitation, a new User, or an email message.

Unknown and duplicate emails remain in the form, with a linked error summary and inline errors. The account owner is protected from removal. **Remove member** asks for confirmation identifying the member and account; accepting removes only that membership, not the User or their memberships in other accounts. Cancelling preserves the membership.

## Personal API tokens

`/api_tokens` lists the current user's credentials across their default accounts. `/accounts/:account_id/api_tokens` filters their own credentials by the authorized account in the URL. Account owners do not gain access to other users' credentials. A token's default account is not a new API permission scope.

Generation requires a name and, globally, an authorized account from the picker. Account pages instead use a fixed account context. Invalid submissions retain input. If no account is available, setup guidance replaces only generation; existing personal token rows remain revocable.

**Copy the value before leaving.** A generated token is shown once, has no later retrieval control, and is stored as a digest. Copy success is reported only after the clipboard operation actually completes. If it rejects or the clipboard API is unavailable, manual-copy guidance appears and the read-only value remains selectable. Nothing copies automatically, and the UI does not persist the value in browser storage.

Result pages opt out of Turbo snapshots and bind a clearing handler to `turbo:before-cache` and `pagehide`. Ordinary Turbo navigation from a no-cache page does **not** dispatch `turbo:before-cache`; clearing is not guaranteed to run on every navigation and is not JavaScript-memory erasure. Exercised refresh and application-navigation/Back flows do not redisplay the value. This does not promise erasure of the OS clipboard, screenshots, or browser-internal retention.

**Revoke token** identifies the name and account in its confirmation. Confirming revocation invalidates authentication using that credential; cancelling preserves it.

## Navigation, validation and compatibility

Global **New chat** opens the generic existing composer. In account context it opens that composer with the account preselected. Neither changes the default account nor creates a chat merely by navigating.

Breadcrumbs, one page title, localized feedback and normal-flow actions replace unrelated drawers only on these eight page variants: prompt list/read/editor, account prompt read/editor, members, global tokens and account tokens. All text links remain transparent on hover, with underlines and native keyboard focus preserved. Buttons retain hover feedback.

Forms use native required/email validation. Server rejection returns HTTP 422 with retained input, a focused linked summary and inline errors, including repeated errors after Turbo morphing. Save, add, generate, remove and revoke have distinct busy labels and duplicate-submission guards.

The UI supports English/French and light/dark themes; authored prompt content is not translated. Permissions, defaults, prompt resolution, token storage and API authentication contracts are unchanged. No routes, schema changes or dependencies were added.

## Verification commands and limits

Use the isolated environment and recorder in the [implementation plan](superpowers/plans/2026-10-28-settings-tools-workspace.md). Never run fixture tests against development or production databases. The `rails_test` and `browser_test` functions below are the plan's isolated wrappers, not generic Rails commands:

```sh
rails_test test test/controllers/prompts_workspace_test.rb test/controllers/account_members_workspace_test.rb test/controllers/api_tokens_workspace_test.rb
browser_test test/system/settings_tools_matrix_test.rb test/system/settings_tools_workflows_test.rb test/system/token_reveal_test.rb test/system/system_prompt_link_hover_test.rb
```

The matrix covers eight variants × two locales × two themes × four actual CSS viewports: **375×812, 768×1024, 1440×1000 and 812×375**, plus additional workflows. Durable ignored evidence records state identities, sampled text/non-text contrast, native focus traversal, pointer hover, screenshots, driver/session cleanup, true command exits and tested source identity. Inspect the resumed execution's `final/resumed/final-verification.md` under `.superpowers/settings-tools-evidence/`, not just planned commands: a planned test is not a passed test, and historical nonzero baselines must not be represented as all green. The earlier `final/final-verification.md` remains the historical stopped attempt, not the resumed result.

Native **200% browser zoom is UNVERIFIED**. Viewport and pointer-capability emulation are not physical-device proof; sampled checks are not an exhaustive accessibility or screen-reader audit. Other browser/platform combinations need their own verification.
