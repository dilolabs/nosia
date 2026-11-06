# Rails 8.1 upgrade

Nosia now uses Rails **8.1.4.1** with `config.load_defaults 8.1`, upgraded from
Rails 8.0.5.1. The Gemfile permits patched 8.1 releases without allowing 8.2.

## Scope

- All Rails components are locked to 8.1.4.1. Action Text now depends on the
  separate `action_text-trix` gem. The required HTML sanitizer, Loofah, and
  Nokogiri dependencies were updated conservatively.
- Ruby, PostgreSQL/pgvector, RubyLLM, the vendored MCP bridge, Lexxy, Solid Queue,
  and the enhanced PostgreSQL Action Cable adapter are unchanged.
- Keep the JSON `< 3` constraint: RubyLLM 2.0.0 still requires it.
- `config/database.yml` uses `max_connections` instead of its compatible `pool`
  alias. `RAILS_MAX_THREADS` still controls the capacity, defaulting to seven.
- Existing production SSL settings remain unchanged.

## Framework defaults

Rails 8.1 rejects path-relative redirects without a leading slash and requires
order columns for order-dependent finders. It also uses Ruby-based template
dependency tracking, omits hidden-field autocomplete attributes, skips redundant
JSON response escaping, and enables YJIT only outside development and test.

The complete non-browser suite passed first with 8.0 defaults, then with the
stricter finder-order setting alone, and finally with all 8.1 defaults. No
compatibility overrides or transitional initializer remain.

## Deployment

Install the updated lockfile and restart the web and job processes together.
There are no new application migrations, data backfills, or secret rotations
introduced by this upgrade. Existing upload storage is unchanged.

Rails 8.1 alphabetizes columns when dumping `db/schema.rb`; a later schema dump
may therefore reorder columns without changing the database. This upgrade does
not regenerate the schema or alter existing migration versions.

## Verification

The Rails 8.0 baseline and the final Rails 8.1 non-browser suite each passed
**1,377 tests and 28,667 assertions**, with no failures, errors, or skips.
Verification used Ruby 4.0.9 and a dedicated PostgreSQL test database:

```sh
DATABASE_URL=postgresql:///nosia_rails81_test TMPDIR=/tmp/opencode/nosia81 PARALLEL_WORKERS=4 bin/rails test --seed 9831
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_rails81_test bin/rails zeitwerk:check
```

Zeitwerk passed, and RuboCop passed on all nine changed Ruby/Gemfile files.
Production asset precompilation also passed, with generated output directed to
`/tmp/opencode/nosia81/assets` rather than the checkout's `public/assets`.

### Browser-suite limitation

The system suite was attempted with fail-fast enabled. It completed **66 tests
and 16,249 assertions**, with no assertion failures and one setup error:
`SettingsToolsWorkflowsTest` cannot select the hidden
`language_preference_locale` control in
`test/support/settings_tool_browser_checks.rb:48`. That older helper does not
open the current Orbite utilities panel before selecting the language.

The same test and error were reproduced with the original Rails **8.0.5.1**
lockfile and 8.0 framework defaults using a temporary comparison harness. This
is an existing browser-test mismatch, not evidence of an 8.1 regression. The
remaining system tests were not run after the fail-fast stop. Updating that
shared browser helper is a separate follow-up; this upgrade does not change it.

On this ARM64 host, the gem's bundled Selenium Manager is an x86-64 executable.
Browser verification used the installed ARM64 `/usr/bin/chromedriver` through a
temporary preload outside the repository. No platform-specific driver settings
were added to the application's test configuration.

Before upgrading, outdated presentation assertions were aligned with the
existing Orbite shell, phase indicator, and localized message disclosures.
The crawl test now simulates embedding generation locally, while still checking
persisted chunks and vectors. Request-option tests cover augmented context both
enabled and disabled, restoring the original environment value afterward.

Existing MCP metadata tests still emit JSON duplicate-key warnings. They were
already present on Rails 8.0 and are not suppressed by this upgrade.

An independent read-only review found no actionable issues in the upgrade diff.
