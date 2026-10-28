# Profile management

Open **User info** in the header menu to visit `/profile`. The page has two
independent cards: updating your email never submits the password-change card,
and updating your password never submits the email-change card. Both actions
require your current password.

The **Home / Settings / Your profile** breadcrumb uses the same shared workspace
header and navigation styling as `/accounts`.

## Email changes

- The new address takes effect immediately, without a confirmation email.
- Existing browser sessions and API tokens remain valid.
- Check the address carefully: a typo affects later sign-ins. Email recovery and
  password reset are not included in this feature.
- The existing email validation, uniqueness constraint, and deterministic
  encryption remain in use; there is no schema migration.

## Password changes

- A replacement must contain at least **12 characters**, fit within **72 UTF-8
  bytes**, and have a required, matching confirmation. Bytes and characters are
  different for non-ASCII text.
- Only a successful change signs out the user's other browser sessions. The
  submitting browser stays signed in; other users' sessions are untouched.
- API tokens remain valid. Changing a password is not token revocation.
- Reusing the current password is allowed when it meets the same validation
  rules, and still signs out the other browser sessions.
- Saving the password and deleting the other sessions are atomic. A failed
  change cannot partially save the password or revoke sessions.

## Developer contract

| Request | Accepted credential fields |
| --- | --- |
| `PATCH /profile/email` | `email_change[email]`, `email_change[current_password]` |
| `PATCH /profile/password` | `password_change[password]`, `password_change[password_confirmation]`, `password_change[current_password]` |

The password form also sends `password_change[email]` as a hidden native
`autocomplete="username"` hint. It is named `email` so existing parameter
filtering covers it; it cannot change the email through the password endpoint.

Only `Current.user` and `Current.session` determine whose credentials change and
which browser session is retained. Submitted user, account, or session IDs are
not authoritative. `User#change_email` and `User#change_password` own current
password verification, validation, locking, and transactions. Their public
contracts are documented with YARD in `app/models/user.rb`. A storage-level email
uniqueness race becomes an email validation error after savepoint rollback,
leaving the surrounding PostgreSQL transaction usable.

### Responses and throttling

- **303** redirects to the relevant profile card after success. Refreshing the
  resulting GET does not repeat a credential update or session revocation.
- **422** shows inline errors and a focusable summary linked to the affected
  fields. Only the submitted card shows errors; with JavaScript, the summary
  receives focus.
- **429** rejects attempts after ten shared credential-update attempts per user
  within three minutes. The email and password endpoints share that allowance,
  even across browsers; another user has a separate allowance.
- **400** rejects missing or malformed parameter roots. Invalid CSRF tokens fail
  closed with **422**, without changing credentials or sessions.

The limiter uses a **process-local `ActiveSupport::Cache::MemoryStore`**, matching
the existing registration approach. Its counters are **not shared across worker
processes or hosts**. A global ceiling would need separately reviewed shared
infrastructure; this feature adds no Redis dependency or shared limiter store.

### Privacy and browser behavior

- Existing Rails parameter filters redact every credential field, including the
  hidden email context, from parameter logs.
- Responses and flash messages never echo submitted passwords, even escaped.
  Password inputs render empty; no password drafts are stored in browser storage.
- Profile HTML uses `Cache-Control: no-store` and Turbo's `no-cache` directive.
- Visibility controls act independently on each native input. Secrets are
  cleared and masked before Turbo navigation/caching and on page departure.
  Reconnecting a visibility control masks an existing autofill value without
  clearing it. Native autocomplete and paste remain available.
- Both forms work without JavaScript. JavaScript enhances visibility, error
  focus, and lifecycle clearing; it does not define credential policy.

## Verification

Regression coverage lives in:

- `test/models/user_credentials_test.rb`: verification, validation boundaries,
  encryption, real PostgreSQL uniqueness recovery, and atomic session revocation.
- `test/controllers/profiles_controller_test.rb` and
  `test/controllers/profiles/credential_updates_test.rb`: authentication,
  tampering, CSRF, malformed requests, shared throttling, token preservation,
  parameter filtering, localization, and secret-free error responses.
- `test/system/profile_management_test.rb`: keyboard focus and linked errors,
  independent visibility controls, navigation/back clearing, autocomplete/paste,
  native no-JavaScript submission, and English/French layouts in light/dark themes
  at a 375px mobile viewport, including computed text/control/focus contrast.
  Breadcrumb styles are compared with `/accounts` on desktop and mobile in both
  languages and themes.

For UI review, also check desktop and **200% browser zoom**, long email addresses
and French errors, reduced motion, and full keyboard traversal. Controls and
focused errors must stay inside the scrolling main area, above bottom navigation,
without horizontal overflow. Browser automation verifies native input semantics,
not integration with a third-party password manager; no such integration is
claimed as tested.

This feature adds no email delivery, recovery/reset, passkey, account-admin, or
API-token revocation flows.
