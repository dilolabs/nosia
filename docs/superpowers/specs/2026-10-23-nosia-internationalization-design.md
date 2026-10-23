# Nosia French and English internationalization

**Date:** 2026-10-23

**Status:** Design and written specification approved; authorized implementation
and independent reviews complete. Tasks 0–13 passed their review gates through code HEAD
`cb2c557` on `feat/nosia-internationalization`; the final whole-feature review
approved `4480db3..cb2c557` with no findings. Full-project checks are **not all
green**. The branch remains unmerged/unpushed pending a separate integration choice.

## Goal

Make Nosia's web interface available in French and English, using browser
language by default and falling back to English.

## Confirmed scope

- Translate the entire Nosia-owned web UI, including onboarding/sign-in,
  chat, sources, accounts, administration/settings, validation and flash
  messages, accessibility labels, and live UI updates.
- Preserve API contracts, user-authored content, AI-generated responses,
  and external tool content. A French interface must not implicitly change
  model prompts or force AI response language.
- No unrelated redesign or refactoring.

## Project context at design time

This section records the pre-implementation inspection, not the current code.

- The checked-in application uses Rails 8.0, PostgreSQL, ERB,
  Hotwire/Stimulus, Importmap, and Minitest with fixtures.
- `config/locales/en.yml` contains only the generated example translation.
- Templates, controllers, helpers, models, and JavaScript mostly contain
  hard-coded English. The HTML document has no language attribute.
- Chat/message/token-total and source-status/count updates render shared Turbo
  Streams from model callbacks and background jobs. Request-only locale
  selection would not keep live UI consistently localized.
- `Message` and `Chat` also declare automatic `broadcasts_to` callbacks;
  these must be considered alongside their explicit broadcasts.
- `token_usages/_summary` has a locale-sensitive fragment cache without a
  locale component today.
- Lexxy 0.9.23 is pinned. Its bundled JavaScript exposes no translation
  catalog/locale configuration identified in the project inspection.
- The existing Jobs dashboard is a mounted Mission Control engine, not a
  Nosia-owned view layer.

## Language preference

- Precedence: valid explicit browser override, then the best supported browser
  language, then English. Respect `Accept-Language` quality weights and order;
  normalize regional variants such as `fr-CA` to `fr` and `en-GB` to `en`.
- Provide an Automatic / Français / English selector, available before and
  after sign-in, in the shared header. Remember explicit overrides in a browser
  cookie rather than storing them on a user/account record.
- Automatic removes the explicit override so future requests follow the
  browser again. English remains the fallback.
- Switching reloads the current page in the selected language.
- Keep existing URLs unchanged; do not introduce locale URL prefixes or
  locale query-parameter overrides. No database migration is required.

### Negotiation and persistence rules

- The supported application locales are exactly `en` and `fr`; the default
  locale and translation fallback are English.
- Match language ranges case-insensitively. Among valid, positive-quality
  concrete supported ranges, choose the highest quality, preserving header
  order for ties. Regional variants map to their supported base language.
- Ignore malformed ranges, unsupported languages, zero-quality entries, and
  wildcard entries during concrete matching. If none remains, use English.
  English remains the final fallback even if the header excludes it.
- An absent, invalid, or tampered preference cookie is ignored, allowing normal
  browser negotiation rather than raising an unsupported-locale error.
- Store an explicit `en` or `fr` override in a signed, one-year cookie available
  throughout the site, with HttpOnly, SameSite=Lax, and Secure on HTTPS.
  Do not persist Automatic as a fixed locale: remove the override instead.
- The preference belongs to the browser, not an account or individual tab.
  Changing it affects subsequent requests in that browser; it does not update
  other browsers/devices or require cross-tab synchronization.
- Browser settings are evaluated on subsequent requests in Automatic mode;
  do not continually poll for changes while a page is open.

### Selector interaction

- Place a compact, visibly labeled native select and submit control in the
  shared header. It is available on anonymous and authenticated pages, supports
  keyboard use, and fits mobile layouts in both light and dark themes.
- The choices are localized Automatic, `Français`, and `English`. Keep the
  two language names recognizable in their own languages; show Automatic as
  selected whenever no valid explicit override exists.
- Submit through a normal CSRF-protected, unauthenticated-accessible singular
  language-preference resource using a standard REST `update` action.
- Only accept `en`, `fr`, or `auto`. An invalid submitted choice returns 422
  without changing the preference. Invalid cookies/headers still degrade
  gracefully as described above.
- On success, return a 303 redirect to a validated same-origin return path,
  falling back to the home page. Never accept an external redirect target.
- Use a full-page navigation for switching, not a partial replacement. This
  replaces old localized DOM, clears the old in-memory Turbo snapshot cache,
  and reconnects subscriptions in the chosen language. Existing URL paths,
  queries, account context, and authorization remain intact.
- Switching is ordinary page navigation: this feature does not introduce
  unsaved-draft persistence. It must not cancel or restart background chat
  generation, indexing, or other existing operations.

## Approaches considered

1. **Rails I18n with unchanged URLs (selected).** Use the browser preference
   cookie and browser headers for request locale; render localized live UI
   separately per supported language. Fits the existing server-rendered app
   without changing links or API routes.
2. **Locale-prefixed URLs.** `/fr/...` and `/en/...` make language-specific
   links shareable but require broader routing/link changes that do not serve
   this mostly signed-in interface's current needs.

## Translation coverage and conventions

- Translate all Nosia-owned screens, form labels/help, validation and flash
  messages, confirmations, tooltips, accessibility labels, and JavaScript UI
  messages, including live states.
- Use clear French with "vous", standard French date/number formats, and
  locale-appropriate pluralization. Do not change stored values or time zones.
- Maintain complete, namespaced English and French YAML catalogs. English is
  the fallback for missing French keys; missing-key checks must still detect
  incomplete French coverage during tests.
- Saved content, prompts, AI replies, and external tool descriptions remain
  unchanged. Do not rewrite existing persisted prose.
- Translate Nosia-owned editor controls. Upstream-only editor dialogs and the
  mounted third-party Jobs dashboard remain as supplied when no supported
  localization hook exists. No dependency forks are part of this release.
- Keep product names, protocol identifiers such as MCP/PDF, model identifiers,
  enum values, field names, URLs, and API error codes stable. Translate their
  human-readable labels, not their stored or machine-readable values.
- Preserve persisted conversation text verbatim, including application prose
  already embedded in message content, such as answer-relevance warnings.
  Do not parse or migrate transcripts to translate these passages. New display
  labels and transient status notices use presentation-layer translations.
- Keep developer/operator diagnostics and repository documentation in English.
  External exception/provider text is diagnostic content, not a translation
  catalog: localize Nosia's surrounding explanation, not arbitrary raw text.
- Static emergency pages in `public/` show concise English and French text,
  with language annotations, without depending on Rails or JavaScript. This is
  the explicit bilingual exception to request-based language selection.

## Architecture and component boundaries

| Component | Responsibility | Boundary |
| --- | --- | --- |
| Rails I18n configuration/catalogs | Declare `en`/`fr`, English default/fallback, application copy, and standard locale formats. | Use Rails I18n and compatible `rails-i18n` French locale data; no frontend translation framework. |
| Controller localization concern | Resolve the validated cookie/header preference and scope rendering/callbacks with `I18n.with_locale`. | No globally sticky locale, database preference, locale URL routing, or changes to authentication. |
| Language-preference resource/header form | Set or clear the browser preference and navigate back safely. | Standard REST action, CSRF protection, allowlisted values, safe local redirects. |
| ERB/helpers/model display methods | Render localized text, validation messages, plurals, dates, and numbers. | Preserve stored data, stable identifiers, HTML escaping, and account scoping. |
| Existing Stimulus controllers | Consume translated UI strings supplied by server-rendered data attributes/values. | No duplicated client catalog, DOM-wide text replacement, or hard-coded English UI fallbacks. |
| Focused localized broadcasting concern | Apply the same locale-qualified stream convention to translated live HTML. | Small model concern shared by existing broadcasters; preserve event semantics and explicit record/account locals. |
| Existing API base controller | Keep machine-facing responses in English regardless of browser cookies/headers. | Same routes, response shapes, status codes, identifiers, and prompt/model behavior. |

Organize application translations by feature and use interpolation and
pluralization rather than concatenating sentence fragments. Supply translations
to Stimulus from the same catalogs used by views, including dynamically created
buttons, error text, announcements, and account-switch confirmations. Set
`<html lang>` to the resolved locale and use that same locale for any browser-side
number/date formatting, rather than independently consulting `navigator.language`.

Use standard locale date/number helpers for displayed values, including source
metadata and token/energy summaries. Preserve numeric precision, calculations,
ISO/machine values, and the existing time zone. Any translated HTML must retain
normal Rails escaping; interpolate untrusted names/content as data.

## Live updates and background rendering

1. A request resolves its locale and renders both the page and its Turbo Stream
   subscriptions with that locale.
2. Qualify the existing chat-message, token-total, source-status/count, and
   filtered source-list streams by locale, preserving their account/chat/filter
   identity. DOM target IDs do not change.
3. For each logical broadcast, publish to both supported locale variants.
   Render translated HTML separately under `I18n.with_locale(:en)` and
   `I18n.with_locale(:fr)`, independent of whichever locale enqueued the job.
4. Cover progress phases, thinking placeholders, message wrappers, source rows
   and metadata, counts, token totals, and regenerated composer forms. Translate
   phase keys in the render context rather than passing pretranslated English
   phase messages from a worker into all recipients' HTML.
5. Route removal, completion/unlock, reconnect-refresh, and automatic
   `broadcasts_to` events consistently as well. Do not leave a fallback
   unqualified subscription that can inject English HTML or duplicate events.
6. A French viewer and an English viewer of the same authorized resource each
   receive only their localized UI. LLM/user content is identical for both;
   compute expensive locale-independent markdown once where it can safely be
   reused by both renderings.

This uses a fixed two-language fan-out, not a per-user subscription registry or
a locale stored on Chat/Account. Keep existing stream coalescing, event order,
retry/stop behavior, filter matching, and source/account isolation. Broadcast
rendering must work without request-scoped `Current.user` or `Current.account`;
use the existing explicit chat/account/record context.

## Caching, fallback, and error handling

- Include locale in translated fragment/cache keys, particularly the token
  usage summary. Localized web responses identify their UI language with
  `Content-Language` and merge `Accept-Language` and `Cookie` into `Vary` where
  representation varies on those inputs. Preserve existing private/no-store
  restrictions; do not introduce public caching of authenticated pages.
- Scope locale for the entire web request, including authentication callbacks
  and flash creation, and restore it on completion/errors. API requests use an
  explicit English scope so shared model validation translations cannot make
  API responses browser-dependent.
- Enable the English translation fallback in runtime configuration. Test both
  that fallback works and that complete French coverage does not depend on it.
- Test application catalogs directly with fallback disabled for completeness,
  placeholder compatibility, and plural coverage; do not hide missing keys with
  inline English `default:` strings or rescuing translation errors broadly.
- Missing/unsupported browser preferences are normal inputs, not 500 errors.
  Invalid preference submissions and unsafe return paths follow the defined
  validation/fallback behavior without weakening CSRF or redirect protection.

## Verification and acceptance criteria

- **Locale negotiation:** absent/unsupported/malformed/wildcard-only headers
  yield English; `fr-FR`/`fr-CA` yield French; `en-US`/`en-GB` yield English;
  preference weights, ties, case, and zero-quality exclusions follow the rules.
- **Overrides:** explicit French wins over an English browser and vice versa;
  Automatic deletes the override; persistence works before and after sign-in;
  invalid/tampered cookies are ignored, invalid form values do not persist, and
  external return URLs cannot cause an open redirect.
- **Request isolation:** alternating French/English requests, exceptions, and
  background renders do not leak locale. API behavior stays English even with
  a French cookie/header.
- **Coverage:** every application translation has French and English text with
  compatible placeholders/plurals. Render representative pages and errors from
  each feature area in both languages, including anonymous/onboarding, chat,
  sources, accounts/settings, MCP, skills, models/prompts, and usage summaries.
- **Live behavior:** exercise actual broadcasts with simultaneous French and
  English subscriptions for one account/chat; verify localized progress,
  message/form replacement, token totals, source creation/status/removal/counts,
  and refresh/reconnect events without duplicate/unqualified updates.
- **Cache separation:** rendering a fragment in one locale must not contaminate
  the other locale. Locale switching must replace old DOM/subscriptions instead
  of reusing old-language Turbo snapshots.
- **Preservation:** assert that saved content, prompts, AI requests/replies,
  machine identifiers, API schemas/statuses, generation/stop behavior, and
  account isolation have not changed.
- **Browser checks:** cover the selector and representative dynamic workflows
  in both languages; test French text wrapping at 375px, keyboard/focus access,
  correct accessible labels/document language, light/dark themes, validation,
  upload/source errors, and chat generation/reconnect.
- **Emergency pages:** verify both languages remain readable without Rails or
  JavaScript, while preserving their existing HTTP/error-page purpose.

Use Minitest and fixtures, with failing tests before implementation. Re-run
the relevant existing controller/model/job/integration/system regressions,
then the full test suite and project lint/security checks. Report unrelated
baseline failures rather than changing unrelated code or weakening assertions.

## Non-goals

- Additional languages, RTL layout, translated URLs, or language-specific SEO.
- User/account language columns, cross-device preferences, or cross-tab sync.
- AI response-language instructions, translated prompts, transcript rewriting,
  translated user documents, or changes to retrieval/model behavior.
- Forking/upgrading Lexxy or Mission Control solely to translate unsupported
  internal UI, or translating external MCP/tool/provider content.
- New email/notification localization flows, documentation translation, a
  frontend i18n framework, a build pipeline, or an unrelated UI redesign.

## Decisions

- "Internationalize Nosia in French and English, using browser language by
  default and fall back to English." — support `fr` and `en`; browser preference
  drives the default and English is the safe fallback.
- "Entire web UI (Recommended)" — translate all Nosia-owned UI in one release;
  keep API contracts, user content, AI output, and external tool content unchanged.
- "Browser + switch (Recommended)" — add an Automatic / Français / English
  override remembered in that browser, including before sign-in; no user/profile
  persistence is required.
- "Approve unchanged URLs" — approve design section 1: Rails translations,
  saved browser override → supported browser preference → English precedence,
  regional/weighted matching, shared-header selector, reload on switch, and
  unchanged URLs with no database migration.
- "Approve coverage" — approve design section 2: all Nosia-owned UI and
  locale-specific formats, French "vous", complete catalogs with English
  fallback, preservation of saved content, and no forks for unsupported
  third-party UI internals.
- "Approve final section" — approve design section 3: locale-qualified live
  updates, request/cache isolation, full navigation on language switch,
  bilingual static emergency pages, Rails locale data rather than a JavaScript
  i18n framework, and the stated verification scope.
- "Go" after the committed specification was presented for review — approve
  the written specification and authorize the implementation-plan step.
- Execution option "1" after the plan — authorize subagent-driven implementation.
- "Proceed unchanged (Recommended)" after Task 0 — continue implementation
  while preserving/reporting the existing `Chat::RequestOptionsTest` baseline
  error rather than fixing unrelated code.

## Completed execution

The [plan's execution summary](../plans/2026-10-23-nosia-internationalization.md#execution-summary)
records Task 0–13 commits, approved review gates, verification scope, and baseline
exceptions. Latest reviewed code HEAD is `cb2c557`; the fresh whole-feature
review (`ses_e96fd672effeDK3BL8x7G64fY7`) approved `4480db3..cb2c557` with no
findings: 156 focused tests / 9670 assertions, 6 Chromium localization tests /
272 assertions, 12 standalone tests / 98 assertions, 72 changed Ruby files
lint-clean, and a clean range diff check. The earlier focused follow-up was
also green (135 tests / 9446 assertions).

This does not make the full-project baseline green. The coordinator's final
full Rails run at `cb2c557` completed with 787 tests / 13085 assertions,
0 failures, and 1 known `RequestOptionsTest` missing-`augmented_context` error
(exit 1). Earlier Task 13 checks at `3f7b209` recorded the requested combined
browser group (80 tests / 3716 assertions, 0 failures, 1 existing
`SourcesDropzoneTest` `GET /login` error). Full RuboCop recorded 234 offenses in
9 files byte-unchanged from `4480db3`. The Brakeman wrapper exited 5 before
scanning (installed 8.0.4 versus latest 8.1.0); the supplemental scan exited 3
with 0 errors and 3 existing warnings. Tailwind and importmap checks passed.
Except for the final Rails rerun, these project-wide results remain the earlier
evidence, not fresh reruns at `cb2c557`. The coordinator also freshly verified
73 changed files (72 Ruby files plus `Gemfile`) lint-clean and the range diff
check clean. The final metadata update changes no runtime code.

The implementation preserves the design boundaries. Review corrections cover
invalid-Bearer JSON versus unchanged missing-Bearer plaintext responses, Ruby-helper
literal auditing and portable `Tempfile` use, callback-based filename replacement
to preserve dollar tokens, explicit request locale in rescue handlers, and actual
deferred-job plus synchronous render-error locale-restoration tests.

See [the internationalization guide](../../internationalization.md) for behavior,
translation workflow, and rollout. **Pre-deployment tabs require a full reload**
for locale-qualified live subscriptions; no unqualified compatibility stream is
provided. Additional languages/RTL, unsupported upstream editor UI, and Mission
Control Jobs internals remain excluded. No all-green or readiness-to-merge claim
is made.

## Review and implementation gate

The user approved the design in three sections, then the committed specification
and planning step. No application code or tests changed during brainstorming.
Execution option "1" and the subsequent baseline choice authorized implementation;
the task-by-task failing-test workflow and independent specification/quality
reviews are now complete, including Task 13 follow-up `cb2c557`. The final
whole-feature review is approved with no findings. This implementation gate is
complete with the recorded baseline exceptions, not an all-green project gate.
Integration remains a separate user decision; the branch is unmerged and unpushed.
