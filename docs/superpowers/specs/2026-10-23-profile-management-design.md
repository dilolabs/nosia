# Profile email and password management

**Date:** 2026-10-23

**Status:** Implemented on `feature/profile-management`; source/spec/quality reviews approved. Focused verification passes. All broader-suite failing cases were independently reproduced on the pre-feature base; global checks remain red. Not merged.

## Goal

Allow signed-in users to manage their own login email and password at `/profile`, with a polished, accessible interface consistent with Nosia.

## Decisions

- “permit profile management in /profile : email and password management, with a great UI/UX” — scope the feature to the signed-in user's login credentials rather than account administration or a broader settings redesign.
- “Yes” to browser-based mockups — compare visual directions with the visual companion before finalizing the interface.
- “Immediate (Recommended)” for email changes — require the current password and update the login email immediately, avoiding an outbound-mail dependency or pending-verification workflow.
- “Sign out others (Recommended)” after password changes — require the current password, preserve the current browser session, and revoke other browser sessions to limit continued access with old credentials.
- “A” for the page layout — use two visible, stacked cards with independent email and password forms; prefer discoverability and predictable saves over tabs or expand-to-edit state.
- “Good” for Design 1/2 (page and behavior) — approve the stacked cards, immediate password-authorized email updates with sessions unchanged, password confirmation and minimum length, revocation of other browsers after password changes, accessible feedback, and the stated scope exclusions.
- “Good” for Design 2/2 (architecture and verification) — approve separate REST update endpoints scoped to `Current.user`, model-owned credential changes, transactional password/session updates, safe responses, existing Rails/Hotwire components, and the stated test coverage.
- “Go” after the committed specification was presented for review — approve this written specification and authorize the implementation-plan step.
- “1” for the implementation-plan execution choice — use fresh implementation agents with separate spec-compliance and code-quality reviews for each task.

## Existing context and boundaries

- `/profile` already has an authenticated show route and controller, but its view is empty. The header already links to it.
- The actual application uses `User.has_secure_password` and email/password login, not the passwordless architecture described in generic repository guidance. Do not replace its authentication mechanism.
- Email is deterministically encrypted and has presence, format, and uniqueness validations. Preserve these rules and encrypted storage; do not introduce a global email-casing migration or change unrelated login behavior.
- The existing 12-character password minimum applies only at creation; password changes must enforce that minimum as well as the existing bcrypt limit of 72 bytes.
- Browser sessions are database records identified by a signed cookie. `Current.user` comes from `Current.session` and is a global identity shared across the user's account memberships.
- Profile changes therefore target `Current.user`, not an account-scoped user lookup. They never change memberships, account ownership, roles, or another user's credentials.
- Reuse Rails/ERB, Hotwire, Tailwind, existing SVGs, neutral/green components, and English/French localization. No new dependency, build pipeline, or database migration is expected.

## Selected presentation

- Keep existing application navigation and provide a Settings / Profile breadcrumb, a clear page heading, and short introductory text.
- Use one column with a maximum width around 42rem, fitting its available container. Stack the Email address and Password cards on both desktop and mobile.
- Each card has a heading, concise explanation, permanently visible labels, independent fields, and its own explicit save action. Do not add tabs, dialogs, autosave, or a combined Save all action.
- Reuse the application's rounded surfaces, borders, green actions, fonts, and icon vocabulary. Do not introduce glassmorphism, marketing sections, remote fonts, or a product-wide redesign.

### Email address card

- Prefill **Email address** from the persisted user. Require **Current password** and provide **Update email**.
- Explain that the new address becomes the login email immediately, without a confirmation link.
- A correct current password plus a valid, available email changes only the signed-in user's email. Existing browser sessions and API tokens remain unchanged.
- Once saved, the old email no longer authenticates that user and the new email works with the unchanged password. The page/header reflect the saved address.
- Submitting the unchanged email with a correct current password is a harmless no-op, without session revocation.

### Password card

- Require **Current password**, **New password**, and **Confirm new password**, followed by **Update password**. Confirmation is required, not optional.
- Show the 12-character minimum near the new-password field. Enforce the existing bcrypt maximum of 72 bytes; describe any maximum-length error accurately for multibyte input.
- Do not impose additional composition rules, introduce a strength-scoring library, or block password-manager-generated values.
- Explain before submission: other browsers will be signed out; the current browser stays signed in.
- A successful update to a different password makes the old password fail and the new password work. No password-history/reuse rule is added: an otherwise valid replacement equal to the current password is accepted and follows the same session-revocation policy. API tokens are not revoked by this browser-session policy.

## Architecture and component responsibilities

| Unit | Responsibility | Boundary |
| --- | --- | --- |
| `ProfilesController#show` / profile page | Render both cards and saved identity. | Authenticated `GET /profile`; never select a user from request parameters. |
| `Profiles::EmailsController#update` | Accept the email form and render/redirect its result. | Authenticated `PATCH /profile/email`; allowlist email and current-password input only. |
| `Profiles::PasswordsController#update` | Accept the password form and render/redirect its result. | Authenticated `PATCH /profile/password`; allowlist current password, new password, and confirmation only. |
| User credential-change methods | Authorize using the stored current password, validate, and persist the intended credential. | Explicit model methods returning a result usable by the controllers; no service/form/policy layer. |
| Password/session transaction | Persist the new password and revoke the same user's other browser sessions together. | Exclude the authenticated submitting session; never revoke another user's sessions. |
| Card partials and small Stimulus enhancements | Render fields/feedback and enhance visibility/focus/privacy. | Distinct form/input IDs; no client-side credential persistence or separate validation authority. |

Use only standard REST actions with nested singular email/password resources. Keep credential changes separate so an email request cannot change a password or vice versa, even if extra fields are forged. Ignore/reject submitted user/account IDs and role attributes.

## Submission, errors, and privacy

1. Render both forms with the saved email and empty password fields. Include normal CSRF protection and appropriate password-manager username/current-password/new-password autocomplete semantics.
2. Submit only the chosen card. Authenticate the supplied current password against the persisted user before changing any credential; missing or wrong values produce a field error without any save or revocation.
3. Run the relevant model validations. An email-only request must not trigger a new-password requirement or mutate the password digest. Password updates must reject blank, short, oversized, or mismatched values.
4. Persist successful password changes and revoke the user's other existing session records in one database transaction. Validation or persistence failure must leave both credentials and sessions unchanged.
5. Redirect successful requests back to the relevant section of `/profile` with a clear, localized success confirmation. Use post/redirect/get so refresh does not repeat the change.
6. On validation failure, render the profile with HTTP 422. Preserve the attempted email only for the failed email form; render the unrelated card from saved state. Never render password values back into any input, hidden field, error, or flash.
7. A storage-level duplicate-email conflict is shown as a normal email validation error rather than an unhandled exception. Do not expose the owner of an existing email address.

- Show specific inline errors associated through `aria-describedby` and `aria-invalid`; include a linked error summary at the top of the failed card and focus it after submission. Do not rely on a toast or red border alone.
- Use the existing submit lifecycle to show pending feedback and prevent duplicate submission of that form. Native server-side submission remains usable without optional Stimulus behavior.
- Rate-limit credential update attempts using the existing Rails infrastructure: a shared allowance of 10 attempts per signed-in user per 3 minutes across both endpoints. On exhaustion, return HTTP 429 with a localized retry message and no credential/session changes. Anonymous access must be denied before any credential lookup/write.
- Continue filtering password-like parameters from logs. Never put credentials in URLs, session/flash storage, analytics, or browser storage.
- Exclude the profile's sensitive forms from Turbo snapshots and clear secret fields/re-mask revealed passwords before caching or leaving. Send `Cache-Control: no-store` for profile HTML, including failed-submission responses. Browser Back must not restore a submitted/revealed password.
- Do not add error-state snapshots or client-side drafts containing passwords. Success navigation clears all credential inputs rather than preserving a second card's unsaved secret values.

## Accessibility and responsive behavior

- Supply descriptive show/hide buttons for each password input, with correct state and no form submission side effect. Revealing one field must not reveal another. Hide again on navigation/reset.
- Allow paste and password managers. Use `autocomplete="current-password"` for current-password inputs and `autocomplete="new-password"` for new/confirmation inputs, with username context for the password form.
- Keep visible keyboard focus, logical heading/tab order, unique input IDs across cards, and decorative SVGs hidden from assistive technology.
- Fit a 375px viewport and 200% browser zoom without horizontal scrolling, clipped controls, or focus hidden by application chrome. Permit long email addresses, errors, and French labels to wrap.
- Keep normal/help text at least 4.5:1 against its actual background and meaningful control boundaries/focus indicators at least 3:1 where applicable, checked independently in both themes.
- Make input/primary action hit areas at least 44 CSS pixels high, with comfortably operable visibility controls. Avoid layout-shifting feedback; respect reduced motion for any optional transition.
- Add English and French strings for headings, hints, actions, model/form errors, pending states, and confirmations. Do not change unrelated localization or globally restyle forms.

## Verification

Write and run failing Minitest tests before application implementation; use fixtures and existing authentication helpers/patterns.

- **Access/isolation:** anonymous GET/PATCH denial, requests target only `Current.user`, forged user/account/admin inputs cannot mutate another identity, and another user's credentials/sessions remain unchanged.
- **Email:** valid change; missing/wrong current password; missing/malformed/duplicate email; storage uniqueness conflict handling; unchanged-email no-op; encrypted persistence; unchanged password/session/API-token state; old/new email login behavior.
- **Password:** valid change; missing/wrong current password; missing new password; fewer than 12 characters; more than 72 bytes including multibyte input; missing/mismatched confirmation; valid same-password replacement; unchanged email; old/new password login behavior for a different replacement.
- **Sessions/atomicity:** preserve the submitting session; remove all of that user's other existing sessions only after success; other-user sessions survive; invalid updates and a persistence/revocation failure roll back all changes; revoked cookies no longer grant access.
- **Responses/privacy:** success redirects and localization; HTTP 422 errors preserve only permitted non-secret input; HTTP 429 shared-user rate limiting; strong-parameter separation; no password values in response HTML/flash; no-store responses and Turbo-cache protection.
- **Browser/system:** render both independent forms; show/hide one field; submit by keyboard; focus the linked error summary; perform each successful change; confirm responsive/zoom behavior, English/French wrapping, light/dark contrast, reduced motion, password-manager semantics, and navigation/back clearing of revealed values.
- Run the focused tests, relevant authentication/localization regressions, and project lint checks. Record environmental or pre-existing failures rather than altering unrelated work to make checks pass.

## Out of scope

Email verification/delivery, forgotten-password recovery, passkeys/magic links, profile photos/names, account deletion, session-management screens, API-token revocation, membership/admin management, authentication replacement, global email normalization/data backfills, and unrelated navigation/form redesigns.

## Approaches considered

1. **A — Two focused cards (selected):** email and password forms stay visible, with separate authorization fields and save actions. Most discoverable, least interaction complexity; a longer page on mobile.
2. **B — Email / Security tabs:** one form visible at a time. Reduces scrolling but hides the second task and adds navigation state.
3. **C — Summary + expand to edit:** read-only credential summary with on-demand editing. Quiet initial view, but adds a disclosure/cancel state and an extra click per task.

## Visual reference and design guidance

- Session directory: `.superpowers/brainstorm/269235-1792767654/` (ignored by git).
- Selected mockup: **A — Two focused cards**, in `profile-layout-directions.html`, with light and dark preview modes. Mockup text illustrates hierarchy; actual sizes and feedback must meet this specification.
- Verified UI/UX guidance: focused Minimalism & Swiss Style recommendations for functional hierarchy, accessible authentication guidance for paste/password managers/visibility, and web form guidance for inline errors plus a focusable linked summary. Apply these inside the existing Nosia design language, not as a new product-wide design system.

## Workflow status

The user approved both design sections, the committed written specification, and subagent-driven execution. Implementation and source reviews are complete. Keep the feature branch/worktree intact; broader verification must not be described as passing while unrelated suite failures remain, and no merge or PR is authorized automatically.
