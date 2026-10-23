# English and French interface

Nosia-owned interface text supports English (`en`) and French (`fr`), including
forms, validation messages, source feedback, and live chat/indexing updates.
Static recovery/error pages present both languages without requiring Rails.

## Choosing a language

The header's **Language / Langue** selector is available before and after login:

- **Automatic / Automatique** uses the browser's `Accept-Language` header. Nosia
  chooses the supported concrete language range with the highest positive
  quality weight, preserving header order for ties. Regional ranges such as
  `fr-CA` and `en-GB` resolve to `fr` and `en`. Wildcards, unsupported languages,
  malformed ranges, and zero-weight ranges are ignored; English is the fallback.
- **Français** or **English** sets a signed, browser-level cookie for one year.
  It overrides the browser header and survives login/logout. Automatic deletes
  that override. This is not an account preference and does not sync across
  devices or automatically update already-open tabs.

Press **Apply / Appliquer** to change language. This performs a **full page
reload of the current URL**, preserving its path, query, and selected account.
**Save unsent work first:** the reload can discard a draft. It does not stop
generation or indexing already running in the background. Other open tabs need
their own reload to pick up the preference.

### Scope and exclusions

Language selection changes presentation, not authored data: document contents,
transcripts, names, prompts, messages, and AI responses are not translated or
rewritten. It does not instruct the AI to answer in the interface language.
External MCP/tool content stays as supplied by its provider. Machine API
contracts, including JSON/SSE responses, remain English regardless of browser
headers or the preference cookie.

Upstream Lexxy dialogs and Mission Control internals remain upstream-owned and
are not guaranteed translated. Additional languages and RTL layouts are outside
the verified English/French scope.

## Rollout note

**All tabs opened before deployment must reload.** Live stream subscriptions now
end in a locale, and publishers no longer send to the old unqualified stream
names. An old tab may otherwise miss generation/indexing updates until reloaded.
There is no unqualified-stream compatibility bridge.

## Developer workflow

1. Add paired feature catalogs in `config/locales/en.nosia_<feature>.yml` and
   `fr.nosia_<feature>.yml`. Put application messages under `nosia`; use standard
   Rails `errors.messages` and `activerecord.attributes` keys for validation and
   attribute names. Keep keys, interpolation variables, and plural branches
   paired and nonempty. Do not hide missing keys with English `default:` text.
2. Use Rails `t`, `l`, and number helpers for visible labels, dates, and counts.
   Translate complete sentences rather than joining translated fragments. Pass
   numeric `count` for plural selection and a separately formatted
   `formatted_count` for display where the catalog expects it. Use formal French
   **vous**. Automated checks complement, not replace, human French review.
3. Pass translated feedback from the server through Stimulus values, not a
   second JavaScript catalog. Let ERB escape attribute values and interpolated
   untrusted content; use `textContent` for client-side text. Do not use
   `html_safe` or `innerHTML` to render filenames, URLs, or external tool text.
4. Include `I18n.locale` in translated fragment-cache keys. Keep account/record
   identity and invalidation inputs intact.
5. Use `LocalizedBroadcasting#broadcast_localized_to` for localized broadcasts
   and `broadcasts_localized_to` for lifecycle macros. The helper appends the
   locale **last**, after unchanged resource/account/filter stream parts. Match
   that ordering in `turbo_stream_from` subscriptions. Supply explicit record
   and account locals for background rendering; do not depend on request-only
   `Current` state. Untranslated authored content can still be computed once.
6. Deferred Turbo jobs serialize their publishing locale. Scope work with
   `I18n.with_locale` so the worker's locale is restored on success and failure.
   Web request locale scoping must cover callbacks and restore after exceptions;
   rescues executed outside that scope must explicitly use the resolved request
   locale. Keep machine API/SSE handling scoped to English.
7. Run strict catalog/view checks, request/cache/broadcast checks, and real
   browser interactions. Catalog parity alone does not prove live delivery,
   native full reload, Turbo history, mobile wrapping, or keyboard focus.

`LanguagePreference` and `LocalizedBroadcasting` document their public Ruby
arguments and results with YARD comments. Extend those contracts when changing
locale resolution or broadcast APIs; no schema or persisted-content migration is
needed for a presentation-only translation.

## Verification

Run test processes sequentially, using isolated fixture data and no real AI,
MCP connections, or external indexing workers. The focused coverage uses opt-in
localization/chat-account fixtures:

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 TMPDIR=/tmp/opencode bin/rails test test/models/language_preference_test.rb test/controllers/language_preferences_controller_test.rb test/controllers/localization_test.rb test/internationalization test/integration/localized_pages_test.rb test/integration/localized_cache_test.rb test/integration/localized_broadcasts_test.rb test/helpers/mcp_catalog_helper_test.rb
bundle exec ruby test/packaging/bilingual_error_pages_test.rb
RAILS_ENV=test AI_API_KEY=nosia-test-key bin/rails tailwindcss:build
```

With Chromium and ChromeDriver installed at the paths below, bypass Selenium
Manager's architecture detection explicitly (adjust paths for another host):

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 TMPDIR=/tmp/opencode bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/localization_test.rb test/system/chat_account_selection_test.rb test/system/chat_composer_ui_test.rb test/system/sources_dropzone_test.rb
```

The localization system tests use separate English/French Chrome sessions and
real WebSocket subscriptions through Rails' in-process Cable test adapter. They
wait for connected subscriptions before publishing one shared operation. The
375px check uses Chrome device metrics, both themes, wrapping geometry, and
visible keyboard focus; the composer regression also uploads real PDFs in both
languages without performing indexing jobs.

Also run the full Rails suite, RuboCop, Brakeman, importmap audit, and
`git diff --check`. Do not interpret focused localization success as a clean
full-project baseline. Known pre-existing verification failures are
`RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults`
(its test double lacks `augmented_context`) and the legacy sources-dropzone
system test visiting `GET /login` when the login route is POST-only. Investigate
any other failure separately; do not skip these tests or weaken their assertions.
