# Nosia French and English Internationalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate all Nosia-owned web UI into English and French, select the browser language by default with English fallback, and provide a persistent browser override.

**Architecture:** Use Rails I18n, paired feature catalogs, a request-local locale concern, and an anonymous-accessible cookie-preference resource without changing existing URLs. Supply translated Stimulus messages from ERB and fan out existing Turbo broadcasts to locale-qualified streams, preserving shared account/chat identity and stored content. Keep machine APIs English and third-party UI internals unchanged where upstream localization is unavailable.

**Tech Stack:** Actual checkout: Ruby 4.0.7, Rails 8.0, PostgreSQL/pgvector, Minitest and opt-in fixtures, Turbo 8/turbo-rails 2.0.23, Stimulus, Importmap, Lexxy 0.9.23, Tailwind. Add compatible `rails-i18n` 8.x; no Node, frontend i18n framework, schema migration, or new infrastructure.

---

## Approval, scope, and execution rules

Read `docs/superpowers/specs/2026-10-23-nosia-internationalization-design.md` first. The user approved its three design sections and approved the committed written specification with **"Go"**. That authorizes this plan, not an unreviewed implementation.

- Preserve the spec's Decisions: entire Nosia-owned UI; browser default plus Automatic/Français/English switch; unchanged URLs; French **vous**; localized numbers/dates; request/cache/live-update isolation; bilingual emergency pages.
- Do not translate or rewrite persisted conversation prose, user documents, prompts, AI requests/replies, external tool/provider descriptions, protocol identifiers, enum values, URLs, or API contracts. Stored relevance warnings remain transcript content.
- Do not fork Lexxy or Mission Control. Translate Nosia's controls around them, not unsupported upstream internals.
- No application tests were run while writing this plan. Establish a fresh baseline during execution; historical failures are not current verification.
- Planning found unrelated work in `Procfile.dev`, two untracked upgrade/waiting-UX plans, an untracked upgrade spec, and `test/packaging/embedding_dimensions.rb`. Never stage, modify, or remove these for this feature.
- Use `patch` for edits. Every behavior starts with its test, a real RED run, and only then implementation. Tables below are literal copy/catalog specifications, not permission to skip tests.
- Test processes must run sequentially because they share PostgreSQL. Keep `ChatAccountFixtures` opt-in; do not move those fixtures into global `test/fixtures` or change `test/test_helper.rb` to load them.
- Finish each task with its GREEN run and a focused Conventional Commit. Stage only the task's named files; do not use `git add .`.

## File structure and stable interfaces

| Path | Responsibility |
| --- | --- |
| `app/models/language_preference.rb` (new PORO) | Allowlisted cookie/header negotiation. Public `.resolve(override:, header:)` returns `:en` or `:fr`; `.explicit?(value)` validates a stored string. No persistence. |
| `app/controllers/concerns/localization.rb` (new) | Prepend request locale scope, language response headers, and header-form selection helper. |
| `app/controllers/language_preferences_controller.rb` (new) | REST `update`: validate `locale`, set/delete signed cookie, safe 303 redirect. |
| `app/views/application/_language_preference.html.erb` (new) | Native labeled selector and submit button, `data-turbo=false`, anonymous and signed-in. |
| `app/models/concerns/localized_broadcasting.rb` (new) | `.broadcasts_localized_to` for existing automatic callbacks and `#broadcast_localized_to(action, *streamables, **options)` for explicit events. Appends locale to stream names and scopes each rendering. |
| `config/locales/{en,fr}.nosia_shell.yml` | Navigation, shared actions, authentication, preference form. |
| `config/locales/{en,fr}.nosia_chat.yml` | Chat/composer/messages, transient phases, browser-generated chat copy. |
| `config/locales/{en,fr}.nosia_sources.yml` | Sources, all four forms, metadata, source-browser messages. |
| `config/locales/{en,fr}.nosia_accounts.yml` | Accounts/members/settings, API-token UI, system-prompt UI, model UI. |
| `config/locales/{en,fr}.nosia_mcp.yml` | MCP screen/catalog copy, statuses, presentation-only catalog metadata. |
| `config/locales/{en,fr}.nosia_skills.yml` | Skills UI, enum labels, custom validation messages. |
| `config/locales/{en,fr}.nosia_usage.yml` | Usage/energy copy, explanations, number labels and unit tooltips. |
| `test/models/language_preference_test.rb` (new) | Header parsing/precedence contract without HTTP. |
| `test/controllers/localization_test.rb` (new) | Real request headers, cookie precedence, locale restoration, API isolation. |
| `test/controllers/language_preferences_controller_test.rb` (new) | Preference writes, invalid input, safe redirects, cookie flags, CSRF. |
| `test/support/localized_view_assertions.rb` (new) | Source-level ERB/attribute literal audit; no production dependency. |
| `test/internationalization/view_copy_test.rb` (new) | Grow audited view groups task-by-task, then cover all ERB. |
| `test/internationalization/catalogs_test.rb` (new) | Direct catalogs without fallback: parity, interpolation, plural branches, no empty copy. |
| `test/integration/localized_pages_test.rb` (new) | Real French/English page/form/error rendering across feature areas. |
| `test/integration/localized_broadcasts_test.rb` (new) | Actual French/English payloads, no old streams, Current-free background renders. |
| `test/support/localization_fixtures.rb`, `test/support/fixtures/localization/{messages,token_usages}.yml` (new) | Opt-in saved message and usage events layered over the existing account fixture set; never globally loaded. |
| `test/system/localization_test.rb` (new) | Browser selector, full reload/cache, mobile and real dynamic French messages. |
| `test/packaging/bilingual_error_pages_test.rb` (new) | Static emergency pages with no Rails boot. |
| `docs/internationalization.md` (new), `docs/README.md`, `docs/DEBT.md` | User/developer behavior, translation workflow, scope boundary, verification. |

Root-level locale filenames are intentional: Rails already loads `config/locales/*.{rb,yml}`. Do not introduce nested directories without extending the load path. Keep all application keys under `nosia`, except Rails' normal `activerecord`/`helpers` keys.

### Commands

Run from the feature workspace, without printing `.env` or secrets:

```sh
bundle check
RAILS_ENV=test bin/rails db:test:prepare
RAILS_ENV=test bin/rails tailwindcss:build
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test
RUBOCOP_TARGET_RUBY_VERSION=4.0 bin/rubocop
bin/brakeman --no-pager
bin/importmap audit
```

On the existing ARM64 host, use the installed browser/driver rather than changing global configuration:

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/localization_test.rb
```

There is no checked-in `bin/ci`; use the actual commands above. Do not start real AI, crawling, MCP, or indexing workers for tests.

## Task 0: Establish a safe execution baseline

**Files:** No application edits. Read the spec, `Gemfile`, `.ruby-version`, `config/database.yml`, `.github/workflows/ci.yml`, `test/support/chat_account_fixtures.rb`.

- [ ] Inspect `git status --short --branch` and ensure the approved spec/plan commits are present. Use the `using-git-worktrees` workflow before application implementation; create a feature workspace from these commits, not an old account-selection branch. Preserve unrelated working-tree changes. This repository actually uses PostgreSQL, so do not invoke the SQLite database-copy workflow.
- [ ] Run `bundle check`, prepare the **test** database, and build test Tailwind. Resolve environment failures before interpreting a feature test. Do not reset development databases.
- [ ] Run the focused baseline:

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/authentication_lifecycle_test.rb test/integration/chat_composer_ui_test.rb test/integration/token_summary_cache_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_access_test.rb test/models/sourceable_broadcast_test.rb test/models/message_test.rb test/models/chat/completionable_test.rb test/jobs/chat_response_job_test.rb
```

Expected: all selected tests pass or failures are recorded before changes. Prior documentation mentions a `Chat::RequestOptionsTest` chunk double missing `augmented_context`; verify rather than assuming it still fails. Capture a full-suite baseline too. Save the execution log under `/tmp/opencode`, not in a locale catalog.

- [ ] Record HEAD, commands, and baseline counts in the execution session. No feature commit is needed for this read-only task.

## Task 1: Configure locales and deterministic browser negotiation

**Files:** Create `app/models/language_preference.rb`, `test/models/language_preference_test.rb`, `config/locales/en.nosia_shell.yml`, `config/locales/fr.nosia_shell.yml`; modify `Gemfile`, `Gemfile.lock`, `config/application.rb`.

- [ ] Write the negotiation test first:

```ruby
require "test_helper"

class LanguagePreferenceTest < ActiveSupport::TestCase
  test "explicit supported overrides beat the browser" do
    assert_equal :fr, LanguagePreference.resolve(override: "fr", header: "en-US")
    assert_equal :en, LanguagePreference.resolve(override: "en", header: "fr-FR")
  end

  test "invalid overrides use browser negotiation" do
    [ nil, "auto", "de", "FR", [ "fr" ], { locale: "fr" } ].each do |value|
      assert_equal :fr, LanguagePreference.resolve(override: value, header: "fr-CA")
    end
  end

  test "concrete ranges respect quality order case and regions" do
    {
      "fr-FR" => :fr, "fr-CA" => :fr, "FR-ca" => :fr,
      "en-US" => :en, "en-GB" => :en,
      "en;q=0.2,fr;q=0.9" => :fr,
      "fr;q=0.5,en;q=0.5" => :fr,
      "en;q=0.5,fr;q=0.5" => :en,
      "de,fr-CA;q=0.8,en;q=0.7" => :fr,
      "fr;q=0,en;q=0.2" => :en,
      "fr;q=bogus,en;q=0.1" => :en,
      "fr;q=1.1,en" => :en,
      "fr;q=-1,en" => :en,
      "fr;q=0.1234,en" => :en,
      "*;q=1,fr;q=0.5" => :fr,
      "fr_CA,en" => :en
    }.each do |header, expected|
      assert_equal expected, LanguagePreference.resolve(override: nil, header: header), header
    end
  end

  test "English is the unconditional final fallback" do
    [ nil, "", "de-DE,es;q=0.8", "*", "???", "fr;q=0,en;q=0" ].each do |header|
      assert_equal :en, LanguagePreference.resolve(override: nil, header: header)
    end
  end

  test "framework locales are available and fallback is English" do
    assert_equal [ :en, :fr ], I18n.available_locales.sort
    assert_equal :en, I18n.default_locale
    assert_includes I18n.fallbacks[:fr], :en
    assert_equal "janvier", I18n.t("date.month_names", locale: :fr).fetch(1)
  end
end
```

- [ ] Run `AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/models/language_preference_test.rb`. Expected RED: `LanguagePreference` is missing and French locale configuration is unavailable. Do not treat a database/boot error as RED.
- [ ] Add `gem "rails-i18n", "~> 8.0"` to `Gemfile`, run `bundle install`, and preserve existing locked dependencies except changes the resolver requires. Inside `Nosia::Application`, add:

```ruby
config.i18n.available_locales = [ :en, :fr ]
config.i18n.default_locale = :en
config.i18n.fallbacks = [ :en ]
```

- [ ] Implement the PORO; no `ApplicationRecord` inheritance or database table:

```ruby
class LanguagePreference
  SUPPORTED = %w[en fr].freeze
  RANGE = /\A\s*([a-z]{1,8}(?:-[a-z0-9]{1,8})*)(?:\s*;\s*q=(0(?:\.\d{0,3})?|1(?:\.0{0,3})?))?\s*\z/i

  class << self
    # @param override [Object] Value read from the signed preference cookie
    # @param header [String, nil] Accept-Language header
    # @return [Symbol] :en or :fr
    def resolve(override:, header:)
      explicit?(override) ? override.to_sym : browser_locale(header)
    end

    # @param value [Object]
    # @return [Boolean] Whether value is an explicit supported locale string
    def explicit?(value)
      SUPPORTED.include?(value)
    end

    private
      def browser_locale(header)
        candidates = header.to_s.split(",").each_with_index.filter_map do |range, index|
          match = RANGE.match(range)
          next unless match

          language = match[1].downcase.split("-").first
          quality = match[2] ? match[2].to_f : 1.0
          [ -quality, index, language.to_sym ] if SUPPORTED.include?(language) && quality.positive?
        end
        candidates.min_by { |quality, index, _language| [ quality, index ] }&.last || :en
      end
  end
end
```

- [ ] Start the shell catalogs with these complete YAML documents; later tasks add keys to them without duplicate `nosia` roots:

```yaml
# config/locales/en.nosia_shell.yml
en:
  nosia:
    language:
      label: Language
      automatic: Automatic
      english: English
      french: Français
      apply: Apply
      invalid: Invalid language preference.
```

```yaml
# config/locales/fr.nosia_shell.yml
fr:
  nosia:
    language:
      label: Langue
      automatic: Automatique
      english: English
      french: Français
      apply: Appliquer
      invalid: Préférence de langue non valide.
```

- [ ] Re-run the exact test command. Expected GREEN: all cases pass. Do not enable every locale bundled by `rails-i18n`.
- [ ] Commit the seven named files with `feat(i18n): configure English and French browser negotiation`.

## Task 2: Scope web requests and freeze API responses to English

**Files:** Create `app/controllers/concerns/localization.rb`, `test/controllers/localization_test.rb`; modify `app/controllers/application_controller.rb`, `app/controllers/api/v1/application_controller.rb`, `app/views/layouts/application.html.erb`, `test/controllers/api/v1/completions_controller_test.rb`.

- [ ] Write HTTP tests before including a concern:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class LocalizationTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  test "anonymous French and English responses identify their locale" do
    [ [ "fr-CA", "fr" ], [ "en-GB", "en" ], [ "de", "en" ] ].each do |header, expected|
      get root_url, headers: { "Accept-Language" => header }
      assert_response :success
      assert_select "html[lang='#{expected}']"
      assert_equal expected, response.headers["Content-Language"]
      vary = response.headers["Vary"].to_s.downcase.split(/,\s*/)
      assert_includes vary, "accept-language"
      assert_includes vary, "cookie"
      assert_equal :en, I18n.locale
    end
  end

  test "API errors remain English for a French browser" do
    post "/api/v1/texts", params: { data: "unchanged" },
      headers: { "Accept-Language" => "fr" }, as: :json
    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
    assert_equal "en", response.headers["Content-Language"]
  end

  test "ordinary query parameters cannot override locale" do
    get root_url, params: { locale: "fr" }, headers: { "Accept-Language" => "en" }
    assert_select "html[lang=en]"
  end
end
```

Also add the explicit exception/callback test in this file:

```ruby
class LocaleScopeProbeController < ApplicationController
  allow_unauthenticated_access
  before_action { response.set_header("X-Callback-Locale", I18n.locale.to_s) }

  def index
    response.set_header("Vary", "Accept")
    raise "locale probe" if params[:raise_error]
    render plain: I18n.locale.to_s
  end
end

class LocaleScopeRestorationTest < ActionController::TestCase
  tests LocaleScopeProbeController

  test "scope includes before callbacks and restores after exceptions" do
    with_routing do |routes|
      routes.draw { get "probe" => "locale_scope_probe#index" }
      @request.headers["Accept-Language"] = "fr"
      get :index
      assert_equal "fr", response.body
      assert_equal "fr", response.headers["X-Callback-Locale"]
      assert_includes response.headers["Vary"].downcase.split(/,\s*/), "accept"
      assert_equal :en, I18n.locale
      assert_raises(RuntimeError) { get :index, params: { raise_error: "1" } }
      assert_equal :en, I18n.locale
    end
  end
end
```

- [ ] Run `AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/controllers/localization_test.rb`. Expected RED: absent document/header localization and callbacks still English.
- [ ] Add this regression to the existing `Api::V1::CompletionsControllerTest`, using its already-defined local Faraday harness and request helpers:

```ruby
test "French browser preferences cannot alter or break committed SSE responses" do
  with_local_completion do |requests|
    post "/v1/chat/completions", params: completion_params.merge(stream: true),
      headers: auth_headers.merge("Accept-Language" => "fr"), as: :json
    assert_response :success
    assert_equal "en", response.headers["Content-Language"]
    assert_includes response.body, "data: [DONE]"
    assert_includes response.body, "**Hello**"
    assert_provider_request(requests)
  end
end
```

Run that file RED too. `ActionController::Live` commits/finalizes headers before the around-action returns; headers must be prepared **before** yielding to the action, not only in an `ensure` after streaming.
- [ ] Implement the concern:

```ruby
module Localization
  extend ActiveSupport::Concern

  included do
    prepend_around_action :with_request_locale
    helper_method :language_preference_value
  end

  private
    def with_request_locale(&operation)
      I18n.with_locale(request_locale) do
        set_locale_response_headers
        operation.call
      ensure
        set_locale_response_headers unless response.committed?
      end
    end

    def set_locale_response_headers
      response.set_header("Content-Language", I18n.locale.to_s)
      if locale_varies_by_request?
        vary = response.get_header("Vary").to_s.split(",").map(&:strip)
        unless vary.include?("*")
          response.set_header("Vary", (vary + %w[Accept-Language Cookie]).uniq(&:downcase).join(", "))
        end
      end
    end

    def request_locale
      LanguagePreference.resolve(override: cookies.signed[:locale], header: request.headers["Accept-Language"])
    end

    def language_preference_value
      value = cookies.signed[:locale]
      LanguagePreference.explicit?(value) ? value : "auto"
    end

    def locale_varies_by_request?
      true
    end
end
```

Include `Localization` in `ApplicationController`. `prepend_around_action` must wrap inherited authentication/rate-limit callbacks, not run only around the action body. Add these private overrides to `Api::V1::ApplicationController`:

```ruby
def request_locale
  :en
end

def locale_varies_by_request?
  false
end
```

Change the application layout's `<html>` to `<html lang="<%= I18n.locale %>">`. Keep existing meta tags, CSP, Turbo refresh settings, and layout geometry unchanged.

- [ ] Run the Task 2 tests plus `test/controllers/api/v1/api_authentication_test.rb`, `test/controllers/api/v1/completions_controller_test.rb`, and `test/integration/authentication_lifecycle_test.rb`. Expected GREEN: no locale leak, no post-commit header mutation, and unchanged JSON/SSE/statuses. Do not alter authentication or invent missing session GET routes while doing localization.
- [ ] Commit named files with `feat(i18n): scope web rendering without changing API language`.

## Task 3: Add the browser preference resource and shared header form

**Files:** Create `app/controllers/language_preferences_controller.rb`, `app/views/application/_language_preference.html.erb`, `test/controllers/language_preferences_controller_test.rb`; modify `config/routes.rb`, `app/views/application/_header.html.erb`.

- [ ] Write the real request tests:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class LanguagePreferencesControllerTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  test "anonymous override survives navigation and Automatic removes it" do
    patch "/language_preference", params: { locale: "fr", return_to: "/?source=header" }
    assert_response :see_other
    assert_redirected_to "/?source=header"
    follow_redirect!
    assert_select "html[lang=fr]"
    assert_select "select[name=locale] option[value=fr][selected]"
    get root_url, headers: { "Accept-Language" => "en" }
    assert_select "html[lang=fr]"

    patch "/language_preference", params: { locale: "auto", return_to: "/" }
    assert_response :see_other
    get root_url, headers: { "Accept-Language" => "en" }
    assert_select "html[lang=en]"
    assert_select "select[name=locale] option[value=auto][selected]"
    get root_url, headers: { "Accept-Language" => "fr" }
    assert_select "html[lang=fr]"
  end

  test "invalid writes and external return paths are safe" do
    patch "/language_preference", params: { locale: "xx", return_to: "/" }
    assert_response :unprocessable_entity
    get root_url, headers: { "Accept-Language" => "fr" }
    assert_select "html[lang=fr]"

    [ "https://evil.example/", "//evil.example/", "https://www.example.com:8443/", [ "/" ], { path: "/" } ].each do |target|
      patch "/language_preference", params: { locale: "en", return_to: target }
      assert_response :see_other
      assert_redirected_to root_url
    end
  end

  test "tampered cookies are ignored and the selector uses full navigation" do
    cookies[:locale] = "not-a-valid-signed-cookie"
    get root_url, headers: { "Accept-Language" => "fr" }
    assert_select "html[lang=fr]"
    assert_select "form[action='/language_preference'][data-turbo=false]" do
      assert_select "label[for=language_preference_locale]", text: "Langue"
      assert_select "select#language_preference_locale[name=locale]", count: 1
      assert_select "button[type=submit]", text: "Appliquer"
    end
    assert_select "form form", count: 0
  end

  test "an override is independent of login" do
    patch "/language_preference", params: { locale: "fr" }
    sign_in_picker_user
    get settings_url
    assert_select "html[lang=fr]"
    delete logout_url
    get root_url
    assert_select "html[lang=fr]"
    post "/api/v1/texts", params: { data: "unchanged" }, as: :json
    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
    assert_equal "en", response.headers["Content-Language"]
  end

  test "HTTPS cookie has the required security flags and expiry" do
    https!
    patch "/language_preference", params: { locale: "fr" }
    header = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/locale=/, header)
    assert_match(/httponly/i, header)
    assert_match(/samesite=lax/i, header)
    assert_match(/secure/i, header)
    assert_match(/expires=/i, header)
    assert_match(/path=\//i, header)
  end

  test "preference writes do not bypass CSRF protection" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    patch "/language_preference", params: { locale: "fr" }
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
```

- [ ] Run `AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/controllers/language_preferences_controller_test.rb`. Expected RED: endpoint/form missing, not a route helper typo.
- [ ] Add the singular resource outside authenticated constraints:

```ruby
resource :language_preference, only: :update
```

Implement the controller:

```ruby
class LanguagePreferencesController < ApplicationController
  allow_unauthenticated_access only: :update

  def update
    if %w[en fr auto].include?(params[:locale])
      if params[:locale] == "auto"
        cookies.delete(:locale, path: "/")
      else
        cookies.signed[:locale] = {
          value: params[:locale], expires: 1.year.from_now, path: "/",
          httponly: true, same_site: :lax, secure: request.ssl?
        }
      end
      redirect_to return_path, status: :see_other
    else
      render plain: I18n.t("nosia.language.invalid"), status: :unprocessable_entity
    end
  end

  private
    def return_path
      value = params[:return_to]
      if value.is_a?(String) && value.start_with?("/") && !value.start_with?("//", "/\\")
        url_from(value) || root_path
      else
        root_path
      end
    end
end
```

Do not use `params[:locale]` to select the language of ordinary GET/API requests. It is only the submitted preference value here.

- [ ] Add the complete header partial:

```erb
<%= form_with url: language_preference_path, method: :patch,
      data: { turbo: false }, class: "flex flex-wrap items-center gap-1 text-xs" do %>
  <%= label_tag :language_preference_locale, t("nosia.language.label"), class: "font-medium" %>
  <%= select_tag :locale,
        options_for_select([
          [t("nosia.language.automatic"), "auto"],
          [t("nosia.language.french"), "fr"],
          [t("nosia.language.english"), "en"]
        ], language_preference_value),
        id: "language_preference_locale", class: "n-select w-auto text-xs" %>
  <%= hidden_field_tag :return_to, request.fullpath %>
  <%= button_tag t("nosia.language.apply"), type: :submit, class: "n-btn n-main-focus text-xs" %>
<% end %>
```

Render it in `_header` outside `Current.user` guards. Make room for wrapping without a hard-coded one-row height: change the nav's sizing classes from `h-16` to `min-h-16 shrink-0 flex-wrap gap-2`; let its right-hand action group wrap too. In `app/views/layouts/application.html.erb`, change the body sizing classes to `h-dvh flex flex-col overflow-hidden` and replace the inner `h-[calc(100dvh-4rem)]` with `min-h-0 flex-1`. Keep all theme/width classes, the logo, and existing controls. This is a targeted height correction so two header rows cannot overlap content, not a navigation redesign. Add this layout file to Task 3's modified files.

Native navigation discards the old JavaScript heap/Turbo snapshots; do not add another client locale store or cookie reader. The 375px browser check in Task 13 verifies the final translated labels rather than assuming they fit.

- [ ] Re-run Task 2 and Task 3 tests. Expected GREEN: anonymous/authenticated, reset, invalid/tampered input, security and redirects. If CSRF raises instead of returning 422 in this test environment, assert `ActionController::InvalidAuthenticityToken` at the same request boundary; do not disable protection in production.
- [ ] Commit named files with `feat(i18n): add persistent browser language selector`.

## Copy-extraction rules for Tasks 4–10

For each feature task, add the supplied behavioral tests **and** its source-audit test, run them RED, then extract its copy. Catalog tables specify the full `nosia` suffix, English, and French. Encode them in that task's paired YAML files; quote strings containing colons, `#`, quotes, or interpolation. Every referenced key must exist in both languages before GREEN.

Use these concrete transformations, retaining all other attributes/markup:

```erb
<h2 class="n-main-title"><%= t("nosia.nav.settings") %></h2>
<%= form.label :name, t("nosia.accounts.name"), class: "n-label" %>
<%= form.submit t("nosia.actions.save"), class: "n-btn-primary" %>
<%= link_to t("nosia.actions.cancel"), accounts_path, class: "n-btn" %>
<%= link_to path, title: t("nosia.actions.delete"),
      aria: { label: t("nosia.actions.delete") },
      data: { turbo_method: :delete, turbo_confirm: t("nosia.actions.confirm_delete") } do %>
  <%= inline_svg "svg/trash-bin.svg", aria: { hidden: true }, class: "h-5 w-5" %>
<% end %>
```

Translate human text, including existing isolated French literals (`Extrait`, `Retour`, `Retirer`, and French energy tooltips). Do not translate CSS classes, `data-action`/targets, DOM IDs, enum/input values, SVG names, example command/package identifiers, human-authored names, or raw tool metadata. Icons adjacent to an accessible translated label are decorative: remove redundant hard-coded `title`/`alt` and mark them `aria-hidden`, rather than cataloging meaningless "Pencil"/"Trash bin" descriptions. Icon-only controls must retain an explicit translated accessible name.

Where a view currently builds a sentence using interpolation outside I18n, translate the **whole** sentence:

```erb
<%= t("nosia.accounts.settings_for", name: @account.name) %>
<%= t("nosia.sources.empty_query", query: query) %>
<%= t("nosia.chat.sources", count: message.similar_chunks.count,
      formatted_count: number_with_delimiter(message.similar_chunks.count)) %>
```

Only use `_html` translation keys for controlled markup in the methodology/skill-help text, with links constructed by `link_to` and normal interpolation escaping. Never call `html_safe` on user/provider text or assemble HTML in Stimulus from translated content.

## Task 4: Translate the shell and authentication; establish the literal audit

**Files:** Modify `app/views/application/_header.html.erb`, `_menu.html.erb`, `_search.html.erb`, `_flash.html.erb`, `_sidebar.html.erb`, `app/views/layouts/application.html.erb`, `app/views/static/index.html.erb`, `app/views/sessions/{new.html.erb,_form.html.erb}`, `app/views/users/_form.html.erb`, `app/views/first_runs/show.html.erb`, `app/controllers/sessions_controller.rb`, `app/controllers/users_controller.rb`, both shell catalogs. Create `test/support/localized_view_assertions.rb`, `test/internationalization/view_copy_test.rb`, `test/integration/localized_pages_test.rb`.

- [ ] Create the test-only source-audit helper:

```ruby
module LocalizedViewAssertions
  TECHNICAL_TEXT = [
    "Nosia", "NOSIA", "BETA", "AI", "PDF", "MCP", "LLM:", "Ruby:",
    "Ecologits", "compar:IA", "ISO 14044", "N/A", "kWh", "gCO2e", "gCO₂e",
    "kWh ·", "kWh · gCO₂e"
  ].freeze
  TECHNICAL_ATTRIBUTES = [
    "https://your-mcp-server.com/mcp", "your-bearer-token", "your-api-key",
    "@modelcontextprotocol/server-filesystem\n/path/to/directory", "/path/to/directory"
  ].freeze

  def assert_localized_view_sources(paths)
    failures = paths.flat_map do |path|
      source = File.read(path).gsub(/<%.*?%>/m, "")
      fragment = Nokogiri::HTML.fragment(source)
      text = fragment.xpath(".//text()[not(ancestor::script) and not(ancestor::style)]").filter_map do |node|
        value = node.text.gsub(/\s+/, " ").strip
        "#{path}: #{value}" if value.match?(/[[:alpha:]]/) && !TECHNICAL_TEXT.include?(value)
      end
      attributes = fragment.css("*").flat_map do |node|
        %w[title alt placeholder aria-label].filter_map do |name|
          value = node[name].to_s.strip
          "#{path}: #{name}=#{value}" if value.match?(/[[:alpha:]]/) &&
            !TECHNICAL_TEXT.include?(value) && !TECHNICAL_ATTRIBUTES.include?(value)
        end
      end
      text + attributes
    end
    assert_empty failures, failures.join("\n")
  end
end
```

This checks source literals, not dynamic/persisted content. Technical exceptions must remain finite, reviewed values, never entire feature directories. Include only genuine protocol/package/example values, not an English UI sentence to make a test pass.

```ruby
# test/internationalization/view_copy_test.rb
require "test_helper"
require_relative "../support/localized_view_assertions"

class ViewCopyTest < ActiveSupport::TestCase
  include LocalizedViewAssertions

  test "shell and authentication have no uncatalogued UI literals" do
    paths = Dir.glob(Rails.root.join("app/views/{application,layouts,static,sessions,users,first_runs}/**/*.erb"))
    assert_localized_view_sources(paths)
  end
end
```

```ruby
# test/integration/localized_pages_test.rb
require "test_helper"
require_relative "../support/chat_account_fixtures"

class LocalizedPagesTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  test "French sign-in and rejection are translated" do
    get root_url, headers: { "Accept-Language" => "fr" }
    assert_select "input[name=email][placeholder='Saisissez votre adresse e-mail']"
    assert_select "input[name=password][placeholder='Saisissez votre mot de passe']"
    assert_select "input[type=submit][value='Se connecter']"

    post login_url, params: { email: @user.email, password: "wrong" },
      headers: { "Accept-Language" => "fr" }
    assert_response :unauthorized
    assert_includes response.body, "Trop de demandes ou accès non autorisé."
  end

  test "English shell remains English" do
    get root_url, headers: { "Accept-Language" => "en" }
    assert_select "input[type=submit][value='Sign in']"
  end
end
```

- [ ] Run `AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/internationalization/view_copy_test.rb test/integration/localized_pages_test.rb`. Expected RED: literal audit and French text assertions fail.
- [ ] Add these shell catalog entries; replace corresponding literals throughout the named files with these exact keys:

| Key suffix | English | French |
| --- | --- | --- |
| `actions.save` | Save | Enregistrer |
| `actions.cancel` | Cancel | Annuler |
| `actions.close` | Close | Fermer |
| `actions.back` | Back | Retour |
| `actions.edit` | Edit | Modifier |
| `actions.delete` | Delete | Supprimer |
| `actions.show` | Show | Afficher |
| `actions.add` | Add | Ajouter |
| `actions.remove` | Remove | Retirer |
| `actions.retry` | Retry | Réessayer |
| `actions.reset` | Reset | Réinitialiser |
| `actions.filter` | Filter | Filtrer |
| `actions.confirm_delete` | Are you sure? | Voulez-vous vraiment supprimer cet élément ? |
| `actions.edit_named` | Edit %{name} | Modifier %{name} |
| `nav.home` | Home | Accueil |
| `nav.home_page` | Home page | Page d’accueil |
| `nav.view_menu` | View menu | Afficher le menu |
| `nav.close_menu` | Close menu | Fermer le menu |
| `nav.accounts` | Accounts | Comptes |
| `nav.sources` | Sources | Sources |
| `nav.token_usage` | Token usage | Utilisation des jetons |
| `nav.settings` | Settings | Paramètres |
| `nav.new_chat` | New chat | Nouvelle conversation |
| `nav.delete_chat` | Delete chat | Supprimer la conversation |
| `nav.search` | Search | Rechercher |
| `nav.search_placeholder` | Search... | Rechercher… |
| `nav.recent_chats` | Recent chats | Conversations récentes |
| `nav.quick_actions` | Quick actions | Actions rapides |
| `nav.ask_question` | Ask any question... | Posez votre question… |
| `nav.jump_to` | Jump to... | Accéder à… |
| `nav.no_search_results` | We couldn’t find any projects with that term. Please try again. | Aucun projet ne correspond à ce terme. Veuillez réessayer. |
| `nav.dark_mode` | Dark mode | Mode sombre |
| `nav.light_mode` | Light mode | Mode clair |
| `nav.toggle_dark_mode` | Toggle dark mode | Activer ou désactiver le mode sombre |
| `nav.toggle_light_mode` | Toggle light mode | Activer ou désactiver le mode clair |
| `nav.open_user_menu` | Open user menu | Ouvrir le menu utilisateur |
| `nav.user_info` | User info | Informations utilisateur |
| `nav.sign_out` | Sign out | Se déconnecter |
| `flash.error_icon` | Error icon | Erreur |
| `flash.check_icon` | Check icon | Confirmation |
| `auth.email_placeholder` | Enter your email address | Saisissez votre adresse e-mail |
| `auth.password_placeholder` | Enter your password | Saisissez votre mot de passe |
| `auth.confirmation_placeholder` | Enter your password confirmation | Confirmez votre mot de passe |
| `auth.sign_in` | Sign in | Se connecter |
| `auth.sign_up` | Sign up | S’inscrire |
| `auth.or_sign_up` | or sign up | ou inscrivez-vous |
| `auth.try_later` | Try again later. | Veuillez réessayer plus tard. |
| `auth.rejected` | Too many requests or unauthorized. | Trop de demandes ou accès non autorisé. |
| `auth.registrations_closed` | Registrations are closed. | Les inscriptions sont fermées. |

Replace controller literals with `I18n.t("nosia.auth.try_later")`, `I18n.t("nosia.auth.rejected")`, and `I18n.t("nosia.auth.registrations_closed")` at their existing flash/rate-limit sites. Leave rate limits, status codes, redirect targets, and authentication unchanged.

- [ ] Apply the markup transformation rules to `_header` and `_menu`, using the same key for title/accessible name/visible label when they describe the same action. Keep the Task 3 selector and wrapping behavior.
- [ ] Translate `_search`; keep escaped result names and chat titles as data.
- [ ] Translate `_flash`, `_sidebar`, and the layout's close-menu label, retaining all targets and dismiss actions.
- [ ] Translate the session and registration form placeholders/buttons plus `static/index` and `sessions/new` captions.
- [ ] Translate the first-run form without changing setup authorization. Add no new account/profile behavior.
- [ ] Run the Task 4 command plus Tasks 2–3 and `test/integration/content_security_policy_test.rb`. Expected GREEN with the source audit still strict.
- [ ] Commit the named files with `feat(i18n): translate navigation and authentication`.

## Task 5: Translate chat, messages, and browser-generated composer feedback

**Files:** Modify ERB under `app/views/chats/`, `app/views/messages/`, `app/views/chat_mcp_sessions/` except the two usage-owned partials `_token_totals` and `_token_footer` (Task 10), plus `app/views/dashboards/show.html.erb`, `app/views/chunks/show.html.erb`, `app/controllers/concerns/chat_account_scoped.rb`, `app/controllers/chat_mcp_sessions_controller.rb`, `app/controllers/chat_sources_controller.rb`, `app/javascript/controllers/composer_sources_controller.js`, `app/javascript/controllers/chat_account_controller.js`; create both chat catalogs and seed the MCP catalog keys `mcp.title`/`mcp.latency` used by the chat selector; extend `test/integration/localized_pages_test.rb`, `test/internationalization/view_copy_test.rb`; create `test/system/localization_test.rb`.

- [ ] Add these tests to the existing test classes before changing chat copy:

```ruby
# LocalizedPagesTest
test "French composer preserves account form contracts" do
  sign_in_picker_user
  get new_chat_url(account_id: @second.id), headers: { "Accept-Language" => "fr" }
  assert_response :success
  assert_select "button[aria-label=Envoyer]"
  assert_select "lexxy-editor[name='chat[prompt]'][placeholder='Posez votre question…']"
  assert_select "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
  assert_select "[data-composer-sources-messages-value]"
  assert_includes response.body, "Les recherches et les pièces jointes utilisent ce compte."
  assert_select "form form", count: 0

  chat = chats(:picker_second_chat)
  chat.start_generation!
  get chat_url(chat), headers: { "Accept-Language" => "fr" }
  assert_select "button[aria-label='Arrêter la génération'][form='#{ActionView::RecordIdentifier.dom_id(chat, :composer_stop)}']"
  assert_select "lexxy-editor[name='message[content]'][disabled]"
  assert_select "[data-chat-account-readonly]", text: /Research team/
end

test "changing UI locale leaves persisted messages unchanged" do
  sign_in_picker_user
  chat = chats(:picker_second_chat)
  before = chat.messages.order(:id).pluck(:id, :content)
  get chat_url(chat), headers: { "Accept-Language" => "fr" }
  assert_response :success
  assert_equal before, chat.messages.order(:id).pluck(:id, :content)
end

# ViewCopyTest
test "chat and message copy is catalogued" do
  paths = Dir.glob(Rails.root.join("app/views/{chats,messages,chat_mcp_sessions,dashboards,chunks}/**/*.erb"))
  usage_partials = %w[chats/_token_totals.html.erb messages/_token_footer.html.erb].map { |path| Rails.root.join("app/views", path).to_s }
  assert_localized_view_sources(paths - usage_partials)
end
```

- [ ] Run the two test files, plus a browser test that drives translated error buttons (complete test below). Expected RED: French composer attributes/buttons and catalogued literals are missing.
- [ ] Add these chat translations:

| Key suffix | English | French |
| --- | --- | --- |
| `chat.title` | AI Chat | Conversation avec l’IA |
| `chat.new` | New chat | Nouvelle conversation |
| `chat.message` | Message | Message |
| `chat.ask` | Ask anything… | Posez votre question… |
| `chat.generating` | Generating… | Génération en cours… |
| `chat.available_skills` | Available skills | Compétences disponibles |
| `chat.message_errors` | Message errors | Erreurs du message |
| `chat.editor_actions` | Editor actions | Actions de l’éditeur |
| `chat.attach_pdf` | Attach PDF | Joindre un PDF |
| `chat.formatting` | Formatting | Mise en forme |
| `chat.formatting_help` | Text formatting controls appear above the message. | Les commandes de mise en forme s’affichent au-dessus du message. |
| `chat.stop` | Stop generating | Arrêter la génération |
| `chat.send` | Send | Envoyer |
| `chat.account` | Account | Compte |
| `chat.account_named` | Account: %{name} | Compte : %{name} |
| `chat.account_help` | Searches and attachments use this account. | Les recherches et les pièces jointes utilisent ce compte. |
| `chat.keyboard` | Enter to send · Shift+Enter for a line break | Entrée pour envoyer · Maj+Entrée pour un saut de ligne |
| `chat.keyboard_with_skills` | Enter to send · Shift+Enter for a line break · / for skills | Entrée pour envoyer · Maj+Entrée pour un saut de ligne · / pour les compétences |
| `chat.disclaimer` | NOSIA can make mistakes. Check important information. | NOSIA peut faire des erreurs. Vérifiez les informations importantes. |
| `chat.tools` | Tools | Outils |
| `chat.connected_tools` | Connected tools | Outils connectés |
| `chat.no_ready_servers` | No ready MCP servers | Aucun serveur MCP prêt |
| `chat.configure_server` | Configure an MCP Server | Configurer un serveur MCP |
| `chat.no_account` | You need access to an account to start a chat. | Vous devez avoir accès à un compte pour démarrer une conversation. |
| `chat.server_added` | MCP server added to the chat. | Serveur MCP ajouté à la conversation. |
| `chat.server_removed` | MCP server removed from the chat. | Serveur MCP retiré de la conversation. |
| `chat.model` | Model: | Modèle : |
| `chat.messages` | Messages: | Messages : |
| `chat.created` | Created: | Création : |
| `chat.excerpt` | Excerpt | Extrait |
| `chat.assistant` | Assistant | Assistant |
| `chat.using_tool` | Using tool... | Utilisation d’un outil… |
| `chat.reasoning` | View reasoning | Afficher le raisonnement |
| `chat.retry` | 🔄 Retry | 🔄 Réessayer |
| `chat.upload_title` | Add any document | Ajoutez un document |
| `chat.upload_help` | Click or drag’n’drop files here to upload | Cliquez ou déposez vos fichiers ici pour les importer |
| `chat.upload_types` | PDF, PNG, JPG, DOCX · max 50 MB | PDF, PNG, JPG, DOCX · 50 Mo maximum |
| `chat.change_account` | Change account? This clears your unsent message, attachment references, and tool choices. Saved sources remain in the previous account. | Changer de compte ? Votre message non envoyé, ses pièces jointes et les outils sélectionnés seront effacés. Les sources enregistrées restent dans le compte précédent. |
| `chat.source_messages.untracked_pdf` | The PDF upload could not be tracked. Reset the draft and attach it again. | L’importation du PDF n’a pas pu être suivie. Réinitialisez le brouillon et joignez-le à nouveau. |
| `chat.source_messages.upload_failed` | PDF upload failed. Reset the draft and attach it again. | Échec de l’importation du PDF. Réinitialisez le brouillon et joignez-le à nouveau. |
| `chat.source_messages.unregistered_pdf` | The PDF could not be registered. Reset the draft and attach it again. | Le PDF n’a pas pu être enregistré. Réinitialisez le brouillon et joignez-le à nouveau. |
| `chat.source_messages.registration_retry` | Source registration failed. Retry or reset the draft. | Échec de l’enregistrement de la source. Réessayez ou réinitialisez le brouillon. |
| `chat.source_messages.registration_failed` | Source registration failed. | Échec de l’enregistrement de la source. |
| `chat.source_messages.form_unavailable` | Attachment form is unavailable. Reset the draft. | Le formulaire de pièce jointe est indisponible. Réinitialisez le brouillon. |
| `chat.source_messages.retry` | Retry source | Réessayer la source |
| `chat.source_messages.reset` | Reset draft | Réinitialiser le brouillon |
| `chat.source_messages.confirm_reset` | Reset this unsent draft? Saved sources will remain in their account. | Réinitialiser ce brouillon non envoyé ? Les sources enregistrées resteront dans leur compte. |
| `chat.source_request_missing` | url or attachable_sgid is required | Une URL ou un identifiant de pièce jointe est requis |
| `chat.source_request_invalid` | invalid attachable sgid | Identifiant de pièce jointe non valide |

Define `chat.sources` with `one`/`other` values `%{formatted_count} source`/`%{formatted_count} sources` in both languages. Use numeric `count` for plural selection, not its formatted string.

Define `chat.phases.<phase>.title/subtitle` from this table:

| Phase | English title / subtitle | French title / subtitle |
| --- | --- | --- |
| `preparing` | Preparing / Starting up... | Préparation / Démarrage… |
| `indexing` | Indexing / Indexing your attachments... | Indexation / Indexation de vos pièces jointes… |
| `searching` | Searching / Looking through your documents... | Recherche / Recherche dans vos documents… |
| `retrieving` | Retrieving / Retrieving relevant context... | Récupération / Récupération du contexte pertinent… |
| `generating` | Generating / Crafting the response... | Génération / Rédaction de la réponse… |
| `using_tool` | Using tool / Executing action... | Utilisation d’un outil / Exécution de l’action… |
| `thinking` | Thinking / Processing... | Réflexion / Traitement… |

- [ ] Translate every literal in the task's ERB files using the catalog keys; preserve form namespaces, Stop form ownership, validation associations, upload/skill/tool controls, and current disabled/inert state. Use whole keyboard sentences, not a translated fragment appended to another sentence. For `_thinking_animation`, retain icons and replace title/subtitle selection with:

```erb
<%
  icons = { "preparing" => "💭", "indexing" => "📥", "searching" => "🔍",
            "retrieving" => "📚", "generating" => "✨", "using_tool" => "🔧", "thinking" => "💭" }
  phase_key = icons.key?(phase) ? phase : "thinking"
%>
<%# In the existing title and subtitle elements: %>
<%= icons.fetch(phase_key) %> <%= t("nosia.chat.phases.#{phase_key}.title") %>
<%= t("nosia.chat.phases.#{phase_key}.subtitle") %>
```

Remove English `message:` overrides from `_thinking`, `_content`, and page-level calls. They must not override the localized phase. Task 11 changes the worker phase API too.

Seed the chat selector's shared MCP keys in its paired catalog files now: `nosia.mcp.title` = `MCP Servers` / `Serveurs MCP`, and `nosia.mcp.latency` = `%{milliseconds}ms` / `%{milliseconds} ms`. Render its latency with `t("nosia.mcp.latency", milliseconds: number_with_delimiter(server.latency_ms))`. Task 8 extends those same files without duplicate roots/keys. Keep the two usage-owned partials unchanged until their atomic copy/cache task; the final audit includes them.

- [ ] Supply the composer dictionary and account confirmation through explicit server attributes:

```erb
<%# Add to the existing root .n-chat-composer element: %>
data-composer-sources-messages-value="<%= t('nosia.chat.source_messages').to_json %>"

<%# Add to each data-controller="chat-account" wrapper in dashboard/new/show: %>
data-chat-account-confirm-message-value="<%= t('nosia.chat.change_account') %>"
```

Extend `composer_sources_controller.js` values with `messages: Object`. Replace every English source-feedback literal with the matching `this.messagesValue` property: `untracked_pdf`, `upload_failed`, `unregistered_pdf`, `registration_retry`, `registration_failed`, `form_unavailable`, `retry`, `reset`, `confirm_reset`. For example, these are the exact changed statements:

```javascript
if (error) throw new Error(this.messagesValue.upload_failed)
if (!sgid) throw new Error(this.messagesValue.unregistered_pdf)
if (!response.ok || !data.id) throw new Error(data.error || this.messagesValue.registration_retry)
operation.message = failure.message || this.messagesValue.registration_failed
if (!target.name) throw new Error(this.messagesValue.form_unavailable)
retry.textContent = this.messagesValue.retry
reset.textContent = this.messagesValue.reset
if (window.confirm(this.messagesValue.confirm_reset)) this.reset()
```

Keep the failed/pending state transitions and `textContent`/`createTextNode`. Do not move upload logic or start translating arbitrary server diagnostics. Extend `chat_account_controller.js` values with `confirmMessage: String` and use `window.confirm(this.confirmMessageValue)` at its existing dirty-draft check.

No current template mounts `thinking_animation_controller.js`; do not refactor that dormant module or add a competing animation loop. The actual progress UI is server-rendered by `_thinking_animation` and updated by worker events; localize that active path. Unused source literals that cannot appear in any current interface are not runtime UI fallback strings.

Replace the two `ChatAccountScoped::NO_ACCOUNT_MESSAGE` usages in its rescue handler with request-time `I18n.t("nosia.chat.no_account")`. Retain the English constant because existing access/selection tests reference it as their English expected value; do not use that constant for runtime localized responses. The browser JSON endpoints `/chat_sources` and chat MCP actions are **web UI endpoints**, not `/api/v1`; localize their human error/flash strings without changing their JSON keys, error statuses, or authorization. In `_chat`, format the displayed timestamp with `l(chat.created_at, format: :short)`; the ISO timestamps used for ordering remain unchanged.

- [ ] Create the initial real-browser test file:

```ruby
require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class LocalizationSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  test "French source feedback uses server supplied messages" do
    visit root_url
    select "Français", from: "language_preference_locale"
    find("form[action='/language_preference'] button[type=submit]").click
    assert_selector "html[lang=fr]"
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Se connecter"
    visit new_chat_url(account_id: @second.id)
    assert_selector "lexxy-editor[connected]"
    page.execute_script(<<~JS)
      const root = document.querySelector('[data-controller~="composer-sources"]')
      const controller = Stimulus.getControllerForElementAndIdentifier(root, "composer-sources")
      controller.operations.set("failure", {
        failed: true, pending: false,
        payload: { url: "https://example.invalid/" },
        message: controller.messagesValue.registration_retry
      })
      controller.renderErrors()
      controller.publishState()
    JS
    assert_button "Réessayer la source"
    assert_button "Réinitialiser le brouillon"
    assert_text "Échec de l’enregistrement de la source."
    assert_button "Envoyer", disabled: true, enable_aria_label: true
    accept_confirm do
      click_on "Réinitialiser le brouillon"
    end
    assert_no_button "Réessayer la source"
    assert_button "Envoyer", disabled: false, enable_aria_label: true
  end
end
```

The application exports its Stimulus instance on `window.Stimulus`; verify that existing `controllers/application.js` contract before running the browser test. This drives the existing state machine without a real external request; Task 13 adds navigation and actual Cable delivery checks.

- [ ] Run Task 5 tests, its system file, `test/integration/chat_composer_ui_test.rb`, and the existing chat/account controller regressions. Expected GREEN: English assertions remain valid; French UI is complete; forms and safety behavior are unchanged.
- [ ] Commit named files with `feat(i18n): translate chat and composer feedback`.

## Task 6: Translate sources and source-upload feedback

**Files:** Modify every ERB under `app/views/sources/`, `app/helpers/sources_helper.rb`, `app/models/{document,text,qna}.rb`, `app/controllers/sources/{documents,qnas,texts,websites}_controller.rb`, `app/javascript/controllers/dropzone_controller.js`, `app/views/dashboards/show.html.erb`; create both sources catalogs; extend the two copy/page test files and `test/system/localization_test.rb`.

- [ ] Add these tests first:

```ruby
# LocalizedPagesTest
test "French sources preserve stable filter and form values" do
  sign_in_picker_user
  get sources_url, headers: { "Accept-Language" => "fr" }
  assert_response :success
  assert_select "input[name=q][placeholder='Rechercher des sources…']"
  assert_select "select[name=sort] option[value=recent]", text: "Ajout récent"
  assert_select "a[href='#{sources_path(type: 'document')}']", text: /Documents/
  assert_select "[data-dropzone-messages-value]"

  get new_sources_qna_url, headers: { "Accept-Language" => "fr" }
  assert_select "h2", text: "Nouvelle question-réponse"
  assert_select "label", text: "Réponse"
  assert_select "textarea[name='qna[answer]']", count: 0
  assert_select "lexxy-editor[name='qna[answer]']"
  assert_select "input[type=submit][value=Enregistrer]"
end

test "French pasted-text metadata pluralizes without changing data" do
  text = texts(:picker_second_text)
  text.data = "bonjour"
  assert_equal "Texte collé · 1 mot", I18n.with_locale(:fr) { text.source_subtitle }
  text.data = "bonjour monde"
  assert_equal "Texte collé · 2 mots", I18n.with_locale(:fr) { text.source_subtitle }
  assert_equal "bonjour monde", text.data
end

# ViewCopyTest
test "source copy is catalogued" do
  assert_localized_view_sources(Dir.glob(Rails.root.join("app/views/sources/**/*.erb")))
end
```

Use the actual fixture label in `test/support/fixtures/chat_accounts/texts.yml` (`picker_second_text` at plan-writing time); verify it rather than introducing a create/factory fallback.

- [ ] Run the copy/page tests RED. Add the sources catalog from the following table and translate the named files:

| Key suffix | English | French |
| --- | --- | --- |
| `sources.title` | Sources | Sources |
| `sources.add` | + Add source | + Ajouter une source |
| `sources.upload_documents` | 📄 Upload documents | 📄 Importer des documents |
| `sources.add_website` | 🌐 Add website | 🌐 Ajouter un site web |
| `sources.paste_text` | 📝 Paste text | 📝 Coller du texte |
| `sources.add_qna` | ❓ Add Q&A | ❓ Ajouter une question-réponse |
| `sources.filters` | Source filters | Filtres des sources |
| `sources.all` | All | Toutes |
| `sources.by_type` | By type | Par type |
| `sources.needs_attention` | Needs attention | À vérifier |
| `sources.failed_filter` | ⚠️ Failed | ⚠️ En échec |
| `sources.pending_filter` | ⏳ Processing | ⏳ En cours de traitement |
| `sources.search` | Search sources… | Rechercher des sources… |
| `sources.sort.recent` | Recently added | Ajout récent |
| `sources.sort.title` | Title | Titre |
| `sources.sort.status` | Status | État |
| `sources.sort.chunks` | Chunk count | Nombre d’extraits |
| `sources.empty_query` | No sources match "%{query}". | Aucune source ne correspond à « %{query} ». |
| `sources.empty_failed` | Nothing failed — all good ✅ | Aucun échec — tout va bien ✅ |
| `sources.empty_pending` | Nothing is processing right now. | Aucun traitement en cours. |
| `sources.first` | Add your first source | Ajoutez votre première source |
| `sources.first_help` | Drop files above, or use "Add source" for websites, text, and Q&As. | Déposez des fichiers ci-dessus ou utilisez « Ajouter une source » pour les sites web, les textes et les questions-réponses. |
| `sources.drop_hint` | Drop files anywhere to add documents | Déposez vos fichiers pour ajouter des documents |
| `sources.title_label` | Title | Titre |
| `sources.file_label` | File | Fichier |
| `sources.account_label` | Account | Compte |
| `sources.text_label` | Text | Texte |
| `sources.url_label` | URL | URL |
| `sources.data_label` | Data | Données |
| `sources.question_label` | Question | Question |
| `sources.answer_label` | Answer | Réponse |
| `sources.no_content` | No content yet. | Aucun contenu pour le moment. |
| `sources.untitled_document` | Untitled document | Document sans titre |
| `sources.file_type` | FILE | FICHIER |
| `sources.answer_preview` | A: %{answer} | R : %{answer} |
| `sources.status.indexed` | Indexed | Indexé |
| `sources.status.failed` | Failed | En échec |
| `sources.status.crawling` | Crawling… | Exploration… |
| `sources.status.processing` | Processing… | Traitement… |
| `sources.upload_messages.failed` | Upload failed. Retry or remove. | Échec de l’importation. Réessayez ou retirez le fichier. |
| `sources.upload_messages.remove` | Remove upload | Retirer le fichier |
| `sources.upload_messages.retry` | Retry | Réessayer |
| `sources.upload_messages.invalid` | Invalid file: %{name} | Fichier non valide : %{name} |
| `time.ago` | %{duration} ago | il y a %{duration} |

Use these **complete per-type keys**, not English `pluralize` or concatenated grammatical fragments:

| Type | `types.<type>.one` EN / FR | `types.<type>.other` EN / FR | `empty.<type>` EN / FR | `add_type.<type>` EN / FR |
| --- | --- | --- | --- | --- |
| document | Document / Document | Documents / Documents | No documents yet / Aucun document pour le moment | Add document / Ajouter un document |
| text | Text / Texte | Texts / Textes | No texts yet / Aucun texte pour le moment | Add text / Ajouter un texte |
| qna | Q&A / Question-réponse | Q&As / Questions-réponses | No Q&As yet / Aucune question-réponse pour le moment | Add Q&A / Ajouter une question-réponse |
| website | Website / Site web | Websites / Sites web | No websites yet / Aucun site web pour le moment | Add website / Ajouter un site web |

All four columns live below `nosia.sources`. Headings/action labels live below `nosia.sources.<plural_resource>`:

| Resource | `new` EN / FR | `show` EN / FR | `edit` EN / FR | `edit_action` EN / FR | `delete_action` EN / FR |
| --- | --- | --- | --- | --- | --- |
| documents | New Document / Nouveau document | Document #%{id} / Document n° %{id} | Edit document #%{id} / Modifier le document n° %{id} | Edit document / Modifier le document | Delete document / Supprimer le document |
| texts | New Text / Nouveau texte | Text #%{id} / Texte n° %{id} | Edit Text #%{id} / Modifier le texte n° %{id} | Edit text / Modifier le texte | Delete text / Supprimer le texte |
| qnas | New Q&A / Nouvelle question-réponse | Q&A #%{id} / Question-réponse n° %{id} | Edit Q&A #%{id} / Modifier la question-réponse n° %{id} | Edit qna / Modifier la question-réponse | Delete qna / Supprimer la question-réponse |
| websites | New Website / Nouveau site web | Website #%{id} / Site web n° %{id} | Edit website #%{id} / Modifier le site web n° %{id} | Edit website / Modifier le site web | Delete website / Supprimer le site web |

For each controller, its four flash keys `created`, `updated`, `destroyed`, `retrying` live in that same resource namespace. Encode these exact translations:

| Resource | Created EN / FR | Updated EN / FR | Destroyed EN / FR | Retrying EN / FR |
| --- | --- | --- | --- | --- |
| documents | Document was successfully created. / Le document a été créé. | Document was successfully updated. / Le document a été mis à jour. | Document was successfully destroyed. / Le document a été supprimé. | Re-indexing document. / Nouvelle indexation du document. |
| texts | Text was successfully created. / Le texte a été créé. | Text was successfully updated. / Le texte a été mis à jour. | Text was successfully destroyed. / Le texte a été supprimé. | Re-indexing text. / Nouvelle indexation du texte. |
| qnas | Q&A was successfully created. / La question-réponse a été créée. | Q&A was successfully updated. / La question-réponse a été mise à jour. | Q&A was successfully destroyed. / La question-réponse a été supprimée. | Re-indexing Q&A. / Nouvelle indexation de la question-réponse. |
| websites | Website was successfully created. / Le site web a été créé. | Website was successfully updated. / Le site web a été mis à jour. | Website was successfully destroyed. / Le site web a été supprimé. | Re-crawling website. / Nouvelle exploration du site web. |

Define `sources.pasted_words.one` as `Pasted text · %{formatted_count} word` / `Texte collé · %{formatted_count} mot` and `.other` as the plural forms `words` / `mots`.

- [ ] Change the source display methods and status helper at presentation time:

```ruby
# Text#source_subtitle
count = data.to_s.split.size
I18n.t("nosia.sources.pasted_words", count: count,
  formatted_count: ActiveSupport::NumberHelper.number_to_delimited(count))

# Qna#source_type_label
I18n.t("nosia.sources.types.qna", count: 1)

# Qna#source_subtitle
I18n.t("nosia.sources.answer_preview", answer: answer.to_s.strip.first(60))

# Document#display_title
title.presence || file.filename.to_s.presence || I18n.t("nosia.sources.untitled_document")

# Document#source_subtitle, after its existing early return
extension = file.filename.extension.to_s.upcase.presence || I18n.t("nosia.sources.file_type")
"#{ActiveSupport::NumberHelper.number_to_human_size(file.byte_size)} · #{extension}"
```

In `source_status_display`, retain its existing CSS branches and replace labels with `t("nosia.sources.status.indexed")`, `.failed`, `.crawling`, and `.processing`. In `Sourceable#source_type_label`, use `I18n.t("nosia.sources.types.#{source_type_key}", count: 1)` so all four types are covered without changing their machine keys. Add `app/models/concerns/sourceable.rb` to this task's files.

In `_source_filters`, rename loop local `t` to `source_type`, then render `t("nosia.sources.types.#{source_type}", count: 2)` while retaining raw `type` query values. In `_empty`, use `t("nosia.sources.empty.#{type}")` and `t("nosia.sources.add_type.#{type}")`. Use the whole `nosia.time.ago` sentence around `time_ago_in_words`, including on MCP's last-connected display later. Format count badges with `number_with_delimiter(value)`; leave their DOM IDs untouched.

- [ ] Supply `data-dropzone-messages-value` from `t('nosia.sources.upload_messages').to_json` on **both** existing dropzone roots: Sources index and dashboard. Extend its Stimulus values with `messages: Object`; change the five generated labels to:

```javascript
alert.textContent = this.messagesValue.failed;
removeBtn.setAttribute("aria-label", this.messagesValue.remove);
retryBtn.textContent = this.messagesValue.retry;
message.textContent = this.messagesValue.invalid.replaceAll("%{name}", file.name);
removeBtn.textContent = this.messagesValue.remove;
```

Keep the uploader's file-name deduplication, upload IDs, queue, failures, retries, and account parameters exactly as they are. Use text nodes, never interpolate filenames into `innerHTML`.

- [ ] Add this browser-generated validation test before changing the uploader's generated messages, run it RED, then re-run GREEN after the dictionary wiring:

```ruby
test "French oversized uploads expose translated errors without sending" do
  visit root_url
  select "Français", from: "language_preference_locale"
  find("form[action='/language_preference'] button[type=submit]").click
  fill_in "email", with: @user.email
  fill_in "password", with: ChatAccountFixtures::PASSWORD
  click_on "Se connecter"
  visit user_root_url
  assert_selector "lexxy-editor[connected]"
  page.execute_script(<<~JS)
    const root = document.querySelector('[data-controller~="dropzone"]')
    const controller = Stimulus.getControllerForElementAndIdentifier(root, "dropzone")
    controller._processFiles([
      new File([new Uint8Array(51 * 1024 * 1024)], "huge.pdf", {type: "application/pdf"})
    ])
  JS
  assert_text "Fichier non valide : huge.pdf"
  assert_button "Retirer le fichier"
  assert_button "Envoyer", disabled: true, enable_aria_label: true
  click_on "Retirer le fichier"
  assert_no_text "Fichier non valide : huge.pdf"
  assert_button "Envoyer", disabled: false, enable_aria_label: true
end
```

No network upload or worker is needed. Run the copy/page tests, the existing `test/controllers/sources/` directory, `test/models/sourceable_test.rb`, `test/models/source_row_test.rb`, `test/system/sources_dropzone_test.rb`, and `test/system/localization_test.rb`. Expected GREEN.
- [ ] Commit named files with `feat(i18n): translate source workflows and upload feedback`.

## Task 7: Translate accounts, settings, token management, prompts, and models

**Files:** Modify every ERB under `app/views/accounts/`, `app/views/settings/`, `app/views/api_tokens/`, `app/views/system_prompts/`, `app/views/models/`; modify `app/controllers/accounts_controller.rb`, `app/controllers/accounts/account_users_controller.rb`, `app/controllers/accounts/system_prompts_controller.rb`, `app/controllers/api_tokens_controller.rb`, `app/controllers/system_prompts_controller.rb`, `app/controllers/models_controller.rb`; create both accounts catalogs; extend the page/copy tests.

- [ ] Add these tests:

```ruby
# LocalizedPagesTest
test "French administration pages translate UI without changing identifiers" do
  sign_in_picker_user
  {
    accounts_url => "Comptes",
    new_account_url => "Nouveau compte",
    settings_url => "Paramètres",
    api_tokens_url => "Jetons API",
    system_prompts_url => "Instructions système",
    models_url => "Modèles"
  }.each do |url, title|
    get url, headers: { "Accept-Language" => "fr" }
    assert_response :success
    assert_select "h1, h2", text: title
  end
  get account_account_users_url(@second), headers: { "Accept-Language" => "fr" }
  assert_response :success
  assert_select "input[type=submit][value='Ajouter un utilisateur']"
  assert_select "form[action='#{account_account_users_path(@second)}']"
  assert_includes response.body, @user.email
end

test "French UI does not rewrite prompt content" do
  sign_in_picker_user
  get account_system_prompt_url(@second), headers: { "Accept-Language" => "en" }
  before = @second.prompts.order(:id).pluck(:id, :content)
  get account_system_prompt_url(@second), headers: { "Accept-Language" => "fr" }
  assert_response :success
  assert_equal before, @second.prompts.order(:id).pluck(:id, :content)
end

# ViewCopyTest
test "account settings token prompt and model UI is catalogued" do
  paths = Dir.glob(Rails.root.join("app/views/{accounts,settings,api_tokens,system_prompts,models}/**/*.erb"))
  assert_localized_view_sources(paths)
end
```

`Account` exposes `prompts`, while `system_prompt` returns content; the test intentionally reads the same persisted `Prompt` records before/after. Do not change prompt storage to satisfy this test.

- [ ] Run the copy/page test command RED. Encode these entries in the accounts catalogs:

| Key suffix | English | French |
| --- | --- | --- |
| `accounts.add` | Add account | Ajouter un compte |
| `accounts.new` | New Account | Nouveau compte |
| `accounts.edit` | Edit Account %{name} | Modifier le compte %{name} |
| `accounts.name` | Account name | Nom du compte |
| `accounts.uid` | UID | UID |
| `accounts.rename` | Rename | Renommer |
| `accounts.settings_for` | %{name} settings | Paramètres de %{name} |
| `accounts.account_settings` | %{name} Account Settings | Paramètres du compte %{name} |
| `accounts.users` | Users | Utilisateurs |
| `accounts.account_users` | Account Users | Utilisateurs du compte |
| `accounts.email` | Email | E-mail |
| `accounts.add_user` | Add User | Ajouter un utilisateur |
| `accounts.current_user` | Current user | Utilisateur actuel |
| `accounts.updated` | Account was successfully updated. | Le compte a été mis à jour. |
| `accounts.user_added` | User was successfully added. | L’utilisateur a été ajouté. |
| `accounts.user_add_failed` | Failed to add user. | Impossible d’ajouter l’utilisateur. |
| `accounts.owner_cannot_remove` | The account owner cannot be removed. | Le propriétaire du compte ne peut pas être retiré. |
| `accounts.user_removed` | User was successfully removed. | L’utilisateur a été retiré. |
| `accounts.owner_only` | Only the account owner can manage members. | Seul le propriétaire du compte peut gérer les membres. |
| `accounts.user_not_found` | User not found. | Utilisateur introuvable. |
| `tokens.title` | API Tokens | Jetons API |
| `tokens.new` | New API token | Nouveau jeton API |
| `tokens.your_new` | Your new API token | Votre nouveau jeton API |
| `tokens.copy_now` | Copy it now — it won't be shown again. | Copiez-le maintenant : il ne sera plus affiché. |
| `tokens.copy` | Copy API token | Copier le jeton API |
| `tokens.delete` | Delete API token | Supprimer le jeton API |
| `tokens.security_help` | For security, this token is shown only once, right after creation. | Pour votre sécurité, ce jeton n’est affiché qu’une seule fois, juste après sa création. |
| `tokens.name` | Name of your API token | Nom de votre jeton API |
| `tokens.default_account` | Default account | Compte par défaut |
| `tokens.generate` | Generate | Générer |
| `tokens.error` | An error occured. | Une erreur est survenue. |
| `prompts.title` | System Prompts | Instructions système |
| `prompts.label` | System prompt | Instructions système |
| `prompts.tab` | System Prompt | Instructions système |
| `prompts.updated` | System prompt was successfully updated. | Les instructions système ont été mises à jour. |
| `prompts.deleted` | System prompt was successfully deleted. | Les instructions système ont été supprimées. |
| `models.title` | Models | Modèles |
| `models.refresh` | Refresh Models | Actualiser les modèles |
| `models.refreshed` | Models refreshed successfully | Les modèles ont été actualisés |
| `models.id` | ID: | ID : |
| `models.provider` | Provider | Fournisseur |
| `models.model` | Model | Modèle |
| `models.context` | Context Window | Fenêtre de contexte |
| `models.max_output` | Max Output: | Sortie maximale : |
| `models.price` | $/1M tokens (In/Out) | $/1 M de jetons (entrée/sortie) |
| `models.consumption` | Average consumption (1000 tokens) | Consommation moyenne (1 000 jetons) |
| `models.capabilities` | Capabilities: | Capacités : |
| `models.start_chat` | Start chat | Démarrer une conversation |
| `models.start_chat_named` | Start chat with this model | Démarrer une conversation avec ce modèle |
| `models.all` | All models | Tous les modèles |
| `models.provider_label` | Provider: | Fournisseur : |
| `models.context_label` | Context Window: | Fenêtre de contexte : |
| `models.price_label` | $/1M tokens (In/Out): | $/1 M de jetons (entrée/sortie) : |
| `models.consumption_label` | Average consumption (1000 tokens): | Consommation moyenne (1 000 jetons) : |

Use `nosia.nav.accounts/settings` and shared actions for repeated navigation/buttons. Settings' Agent Skills/MCP labels use the dedicated keys from Tasks 8–9; introduce those small entries now in their eventual paired files if needed, never an inline English fallback.

- [ ] Translate all named ERB and controller flash sites. Convert dynamic headings to whole-sentence interpolation. Keep token plaintext and clipboard targets untouched; do not expose secrets in new labels or logs. Show prompt `full_name`/`content` verbatim. Keep API-token generation/revocation, account membership checks, and model refresh requests unchanged.

For the existing English-mode consumption-column test, replace its old French literal expectation with `Average consumption (1000 tokens)` and add a French-mode expectation for `Consommation moyenne (1 000 jetons)`. This is an intentional correction of previously mixed-language UI, not a calculation change. Add `test/integration/models_consumption_column_test.rb` to the modified files.

For model prices, preserve USD and two decimal places but use locale-aware formatting in both `_model` and `show`:

```erb
<%= input.nil? ? "—" : number_to_currency(input, unit: "$", precision: 2) %>
/
<%= output.nil? ? "—" : number_to_currency(output, unit: "$", precision: 2) %>
```

Do not localize `provider`, model IDs, capability protocol values, or the `model_id`/`provider` query parameters. Seed `nosia.usage.token_quantity.one/other` in both usage catalogs now: `%{formatted_count} token` / `%{formatted_count} tokens` for English and `%{formatted_count} jeton` / `%{formatted_count} jetons` for French. Render the model context/output quantities with `t("nosia.usage.token_quantity", count: @model.context_window, formatted_count: number_with_delimiter(@model.context_window))` and the equivalent `@model.max_output_tokens` call. Task 10 extends these catalogs; it does not redefine the same keys in a second file.

- [ ] Run the copy/page tests and `test/controllers/accounts_controller_test.rb`, `test/controllers/accounts/account_users_authorization_test.rb`, `test/controllers/accounts/system_prompts_controller_test.rb`, `test/controllers/api_tokens_controller_test.rb`, `test/controllers/system_prompts_controller_test.rb`, `test/integration/models_consumption_column_test.rb`. Expected GREEN with cross-account denials intact.
- [ ] Commit named files with `feat(i18n): translate account and administration screens`.

## Task 8: Translate MCP management and presentation-only catalog metadata

**Files:** Modify all ERB under `app/views/mcp_servers/`, `app/views/mcp_catalog/`, `app/controllers/mcp_servers_controller.rb`, `app/controllers/mcp_catalog_controller.rb`, `app/models/mcp_server.rb`; create `app/helpers/mcp_catalog_helper.rb` and both MCP catalogs; extend page/copy tests; create `test/helpers/mcp_catalog_helper_test.rb`.

- [ ] Add the page/copy tests and helper isolation test before translating:

```ruby
# LocalizedPagesTest
test "French MCP pages preserve transport values" do
  sign_in_picker_user
  get new_mcp_server_url, headers: { "Accept-Language" => "fr" }
  assert_response :success
  assert_select "h2", text: "Nouveau serveur MCP"
  assert_select "select[name='mcp_server[transport_type]'] option[value=stdio]", text: "STDIO (processus local)"
  assert_select "[data-mcp-form-target=httpFields]"
  assert_select "[data-mcp-form-target=stdioFields]"

  get mcp_catalog_index_url, headers: { "Accept-Language" => "fr" }
  assert_select "h2", text: "Catalogue MCP"
  assert_includes response.body, "Activez des serveurs MCP prédéfinis en un clic."
end

# ViewCopyTest
test "MCP screen copy is catalogued" do
  assert_localized_view_sources(Dir.glob(Rails.root.join("app/views/{mcp_servers,mcp_catalog}/**/*.erb")))
end
```

```ruby
# test/helpers/mcp_catalog_helper_test.rb
require "test_helper"

class McpCatalogHelperTest < ActionView::TestCase
  include McpCatalogHelper

  test "presentation translation never mutates cached activation metadata" do
    entry = McpCatalog.find("kchat")
    original = Marshal.dump(entry)
    french = I18n.with_locale(:fr) { catalog_entry_description(entry) }
    assert_equal "Consultez les messages récents de kChat et publiez des messages.", french
    assert_equal original, Marshal.dump(entry)
    assert_equal entry[:description], I18n.with_locale(:en) { catalog_entry_description(entry) }
  end

  test "unknown extension metadata stays unchanged" do
    external = { id: "external", description: "Unmodified external description" }
    assert_equal external[:description], I18n.with_locale(:fr) { catalog_entry_description(external) }
  end
end
```

- [ ] Run these tests RED. Add the following MCP copy, using existing action/nav keys for back/edit/delete/filter/reset/save/close:

| Key suffix | English | French |
| --- | --- | --- |
| `mcp.title` | MCP Servers | Serveurs MCP |
| `mcp.new` | New MCP Server | Nouveau serveur MCP |
| `mcp.add` | Add server | Ajouter un serveur |
| `mcp.show` | Show server | Afficher le serveur |
| `mcp.edit` | Edit server | Modifier le serveur |
| `mcp.delete` | Delete server | Supprimer le serveur |
| `mcp.connect_server` | Connect server | Connecter le serveur |
| `mcp.disconnect_server` | Disconnect server | Déconnecter le serveur |
| `mcp.connect` | Connect | Connecter |
| `mcp.disconnect` | Disconnect | Déconnecter |
| `mcp.tags_label` | Tags: | Étiquettes : |
| `mcp.all_statuses` | All statuses | Tous les états |
| `mcp.all_types` | All types | Tous les types |
| `mcp.status.ready` | Ready | Prêt |
| `mcp.status.error` | Error | Erreur |
| `mcp.status.connecting` | Connecting | Connexion en cours |
| `mcp.status.disconnected` | Disconnected | Déconnecté |
| `mcp.status.disabled` | Disabled | Désactivé |
| `mcp.none` | No MCP servers found | Aucun serveur MCP trouvé |
| `mcp.none_help` | Connect a Model Context Protocol server or activate one from the catalog. | Connectez un serveur Model Context Protocol ou activez-en un depuis le catalogue. |
| `mcp.last_error` | Last error: | Dernière erreur : |
| `mcp.overview` | Overview | Vue d’ensemble |
| `mcp.tools` | Tools | Outils |
| `mcp.prompts` | Prompts | Instructions |
| `mcp.resources` | Resources | Ressources |
| `mcp.configuration` | Configuration | Configuration |
| `mcp.transport_type` | Transport Type | Type de transport |
| `mcp.endpoint` | Endpoint | Adresse du serveur |
| `mcp.last_connected` | Last Connected | Dernière connexion |
| `mcp.tags` | Tags | Étiquettes |
| `mcp.notes` | Notes | Notes |
| `mcp.parameters` | Parameters: | Paramètres : |
| `mcp.variables` | Variables: | Variables : |
| `mcp.test` | Test | Tester |
| `mcp.no_tools` | No tools available | Aucun outil disponible |
| `mcp.no_prompts` | No prompts available | Aucune instruction disponible |
| `mcp.no_resources` | No resources available | Aucune ressource disponible |
| `mcp.mime_type` | Type: %{type} | Type : %{type} |
| `mcp.latency` | %{milliseconds}ms | %{milliseconds} ms |
| `mcp.basic` | Basic Information | Informations générales |
| `mcp.name` | Name * | Nom * |
| `mcp.name_help` | Unique name to identify this MCP server | Nom unique pour identifier ce serveur MCP |
| `mcp.connection_type` | Connection Type * | Type de connexion * |
| `mcp.transport.streamable` | Streamable HTTP (recommended) | HTTP en flux (recommandé) |
| `mcp.transport.sse` | Server-Sent Events (SSE) | Événements envoyés par le serveur (SSE) |
| `mcp.transport.stdio` | STDIO (local process) | STDIO (processus local) |
| `mcp.transport.streamable_short` | Streamable HTTP | HTTP en flux |
| `mcp.transport.sse_short` | SSE | SSE |
| `mcp.transport.stdio_short` | STDIO | STDIO |
| `mcp.url` | Server URL * | URL du serveur * |
| `mcp.command` | Command * | Commande * |
| `mcp.command_hint` | bunx or python | bunx ou python |
| `mcp.arguments` | Arguments (one per line) | Arguments (un par ligne) |
| `mcp.enabled` | Server enabled | Serveur activé |
| `mcp.authentication` | Authentication (optional) | Authentification (facultative) |
| `mcp.bearer_token` | Bearer Token | Jeton Bearer |
| `mcp.bearer_help` | Will be used as "Authorization: Bearer token" | Utilisé sous la forme « Authorization: Bearer token » |
| `mcp.api_key` | API Key | Clé API |
| `mcp.api_key_help` | Will be used as "X-API-Key: key" | Utilisée sous la forme « X-API-Key: key » |
| `mcp.metadata` | Metadata | Métadonnées |
| `mcp.tags_input` | Tags (comma separated) | Étiquettes (séparées par des virgules) |
| `mcp.tags_hint` | production, filesystem, important | production, fichiers, important |
| `mcp.notes_hint` | Notes about this MCP server... | Notes sur ce serveur MCP… |
| `mcp.test_connection` | Test Connection | Tester la connexion |
| `mcp.created` | MCP server created successfully. | Le serveur MCP a été créé. |
| `mcp.updated` | MCP server updated. | Le serveur MCP a été mis à jour. |
| `mcp.deleted` | MCP server deleted. | Le serveur MCP a été supprimé. |
| `mcp.connection_established` | Connection established | Connexion établie |
| `mcp.connection_failed` | Connection failed | Échec de la connexion |
| `mcp.connected` | Connected to MCP server. | Connecté au serveur MCP. |
| `mcp.connection_error` | Connection failed: %{error}. | Échec de la connexion : %{error}. |
| `mcp.disconnected` | Disconnected from MCP server. | Déconnecté du serveur MCP. |
| `mcp.arguments_invalid` | Tool arguments must be a JSON object | Les arguments de l’outil doivent être un objet JSON |
| `mcp.not_ready` | Server not ready | Le serveur n’est pas prêt |
| `mcp.tool_not_found` | Tool not found: %{name} | Outil introuvable : %{name} |
| `mcp.catalog` | Catalog | Catalogue |
| `mcp.catalog_title` | MCP Catalog | Catalogue MCP |
| `mcp.catalog_help` | Activate predefined MCP servers with one click. | Activez des serveurs MCP prédéfinis en un clic. |
| `mcp.my_servers` | My servers | Mes serveurs |
| `mcp.activated` | Activated | Activé |
| `mcp.already_activated` | Already activated | Déjà activé |
| `mcp.configure_activate` | Configure and activate | Configurer et activer |
| `mcp.activate` | Activate | Activer |
| `mcp.activate_named` | Activate %{name} | Activer %{name} |
| `mcp.catalog_empty` | No servers available in the catalog | Aucun serveur disponible dans le catalogue |
| `mcp.back_catalog` | Back to catalog | Retour au catalogue |
| `mcp.config_required` | Configuration required | Configuration requise |
| `mcp.config_required_help` | This server requires configuration before activation. | Ce serveur doit être configuré avant son activation. |
| `mcp.ready_activate` | Ready to activate | Prêt à être activé |
| `mcp.no_config` | This server does not require any additional configuration. | Ce serveur ne nécessite aucune configuration supplémentaire. |
| `mcp.capabilities` | Available capabilities | Capacités disponibles |
| `mcp.server_not_found` | Server not found. | Serveur introuvable. |
| `mcp.activated_named` | %{name} activated successfully. | %{name} a été activé. |
| `mcp.activation_error` | Activation error: %{error}. | Erreur d’activation : %{error}. |

Define `mcp.errors.one/other` as `%{count} error:` / `%{count} errors:` and `%{count} erreur :` / `%{count} erreurs :`. Replace `pluralize(..., "error")` with this translated whole heading.

- [ ] Implement this complete presentation helper; leave cached `McpCatalog.all/categories` and activation metadata language-neutral:

```ruby
module McpCatalogHelper
  OWNED_ENTRIES = %w[infomaniak-calender kchat kdrive open_alex].freeze
  OWNED_CATEGORIES = %w[communication productivity development database search utility automation engines].freeze

  def catalog_entry_description(entry)
    if OWNED_ENTRIES.include?(entry[:id].to_s)
      t("nosia.mcp.catalog_entries.#{entry[:id]}.description")
    else
      entry[:description]
    end
  end

  def catalog_category_name(category)
    if OWNED_CATEGORIES.include?(category[:id].to_s)
      t("nosia.mcp.categories.#{category[:id]}")
    else
      category[:name]
    end
  end

  def catalog_category_description(category)
    category[:id].to_s == "engines" ? t("nosia.mcp.engines_description") : category[:description]
  end

  def catalog_capability_label(value)
    %w[tools prompts resources].include?(value) ? t("nosia.mcp.#{value}") : value
  end

  def catalog_field_text(entry, field, kind)
    if OWNED_ENTRIES.include?(entry[:id].to_s) && field[kind].present?
      t("nosia.mcp.catalog_entries.#{entry[:id]}.fields.#{field[:name]}.#{kind}")
    else
      field[kind]
    end
  end
end
```

Use `catalog_entry_description(server/@template)`, `catalog_category_name(category)`, and `catalog_category_description(category)` in catalog views. Use `catalog_field_text(@template, config_field, :label/:description/:placeholder/:help_text)` for displayed field metadata. Do not replace hidden IDs, field names, command/env values, config option values, or `McpCatalog.activate_for_account`'s raw notes/name source.

Use `catalog_capability_label(capability)` for the catalog's known capability badges; unknown extension values remain literal external metadata. Use `nosia.mcp.latency` with a formatted number for displayed latency, not a raw English suffix.

The helper's complete managed metadata catalog is:

| Key below `mcp` | English | French |
| --- | --- | --- |
| `categories.communication` | Communication | Communication |
| `categories.productivity` | Productivity | Productivité |
| `categories.development` | Development | Développement |
| `categories.database` | Database | Bases de données |
| `categories.search` | Search | Recherche |
| `categories.utility` | Utility | Utilitaires |
| `categories.automation` | Automation | Automatisation |
| `categories.engines` | Built-in engines | Intégrations natives |
| `engines_description` | Native integrations bundled with Nosia. | Intégrations natives incluses dans Nosia. |
| `catalog_entries.infomaniak-calender.description` | Search and create events in your calendar | Recherchez et créez des événements dans votre calendrier |
| `catalog_entries.kchat.description` | Get recent messages from kChat and post messages. | Consultez les messages récents de kChat et publiez des messages. |
| `catalog_entries.kdrive.description` | Search, browse and read files from your Infomaniak kDrive. | Recherchez, parcourez et lisez les fichiers de votre kDrive Infomaniak. |
| `catalog_entries.open_alex.description` | Search scholarly works, authors, institutions, sources, topics, publishers and funders. | Recherchez des publications scientifiques, des auteurs, des établissements, des sources, des sujets, des éditeurs et des financeurs. |
| `catalog_entries.infomaniak-calender.fields.calendar_token.label` | Infomaniak Calendar Token | Jeton Infomaniak Calendar |
| `catalog_entries.infomaniak-calender.fields.calendar_token.description` | Your Infomaniak calendar token. | Votre jeton de calendrier Infomaniak. |
| `catalog_entries.kchat.fields.kchat_token.label` | kChat Token | Jeton kChat |
| `catalog_entries.kchat.fields.kchat_token.description` | Your kChat token. | Votre jeton kChat. |
| `catalog_entries.kchat.fields.kchat_team_name.label` | Your kChat team unique name. | Nom unique de votre équipe kChat. |
| `catalog_entries.kchat.fields.kchat_team_name.description` | Get your kChat team name from your kChat url (eg. https://your-team.kchat.infomaniak.com/your-team/channels/town-square url have your-team team). | Le nom de l’équipe figure dans votre URL kChat. Par exemple, pour https://your-team.kchat.infomaniak.com/your-team/channels/town-square, le nom est your-team. |
| `catalog_entries.kdrive.fields.token.label` | kDrive Token | Jeton kDrive |
| `catalog_entries.kdrive.fields.drive_id.label` | kDrive ID | Identifiant kDrive |
| `catalog_entries.open_alex.fields.api_key.label` | OpenAlex API key (optional, for the polite pool) | Clé API OpenAlex (facultative, pour le « polite pool ») |

These are presentation copies of Nosia-owned catalog descriptions, not translations of runtime MCP tool descriptions. Unknown extension metadata is returned unchanged and normally escaped.

- [ ] Translate the task's controller flashes/browser-JSON `message`/owned `error` strings using the MCP table; keep raw provider `last_error` untouched inside the translated explanation. In `McpServer#execute_tool`, localize only the owned not-ready/not-found wrappers. Keep arbitrary results and caught provider diagnostics unchanged. The catalog's custom validation error changes atomically with its paired Rails keys in Task 9, not in this task.

For finite status/transport/capability labels, use localized display labels but preserve underlying `ready/error/connecting/disconnected/disabled`, `streamable/sse/stdio/local`, `tools/prompts/resources` values. Use the whole `nosia.time.ago` key for last-connected. Do not refactor the existing custom MCP routes/actions as part of translation.

- [ ] Run the page/copy/helper tests plus `test/controllers/mcp_servers_controller_test.rb`, `test/models/mcp_server_test.rb`, `test/models/mcp_server_local_test.rb`, `test/lib/mcp_catalog_registry_test.rb`, and `test/integration/ported_script_pages_render_test.rb`. Expected GREEN; no real server connection or activation side effects in rendering tests.
- [ ] Commit named files with `feat(i18n): translate MCP management without localizing stored metadata`.

## Task 9: Translate skills and model validation/attribute names

**Files:** Modify all ERB under `app/views/agent_skills/`, `app/controllers/agent_skills_controller.rb`, `app/models/agent_skill.rb`, `app/models/mcp_server.rb`, `app/models/chat/account_scoped.rb`, `lib/mcp_catalog.rb`; create both skills catalogs; extend the page/copy tests. Add shared model attribute keys to the catalog belonging to that feature, and missing-config error keys to the MCP catalogs.

- [ ] Add these behavioral tests first:

```ruby
# LocalizedPagesTest
test "French skill forms keep machine enum values" do
  sign_in_picker_user
  get new_agent_skill_url, headers: { "Accept-Language" => "fr" }
  assert_response :success
  assert_select "h2", text: "Créer une compétence d’agent"
  assert_select "select[name='agent_skill[trigger_mode]'] option[value=explicit]", text: "Explicite"
  assert_select "select[name='agent_skill[execution_mode]'] option[value=llm]", text: "LLM"
  assert_select "textarea[name='agent_skill[skill_content]']"
end

test "French custom validation translates but does not change validation rules" do
  skill = agent_skills(:picker_second_skill)
  skill.skill_content = "---\nname: 1bad\ndescription: Sample\nexecution_mode: llm\ntrigger_mode: explicit\n---\nKeep these instructions."
  I18n.with_locale(:fr) do
    refute skill.valid?
    assert_includes skill.errors[:name], "doit commencer par une lettre et ne contenir que des lettres, des chiffres, des tirets et des traits de soulignement"
  end
  assert_includes skill.skill_content, "Keep these instructions."
end

# ViewCopyTest
test "skill UI is catalogued" do
  assert_localized_view_sources(Dir.glob(Rails.root.join("app/views/agent_skills/**/*.erb")))
end
```

Use `picker_second_skill` from the existing opt-in YAML; keep its content changes in memory for validation. Add equivalent French error checks to the existing account-immutability and MCP endpoint/stdio tests, preserving their original English cases and error statuses.

- [ ] Run the page/copy tests RED. Add these skills entries:

| Key suffix | English | French |
| --- | --- | --- |
| `skills.title` | Agent Skills | Compétences d’agent |
| `skills.manage` | Manage agent skills | Gérer les compétences d’agent |
| `skills.create` | Create skill | Créer une compétence |
| `skills.new` | Create Agent Skill | Créer une compétence d’agent |
| `skills.edit_title` | Edit Agent Skill | Modifier la compétence d’agent |
| `skills.edit` | Edit skill | Modifier la compétence |
| `skills.show` | Show skill | Afficher la compétence |
| `skills.delete` | Delete skill | Supprimer la compétence |
| `skills.enable` | Enable skill | Activer la compétence |
| `skills.disable` | Disable skill | Désactiver la compétence |
| `skills.enabled` | Enabled | Activée |
| `skills.disabled` | Disabled | Désactivée |
| `skills.none` | No agent skills yet | Aucune compétence d’agent pour le moment |
| `skills.none_help` | Create your first skill to extend what your assistant can do. | Créez votre première compétence pour enrichir les possibilités de votre assistant. |
| `skills.requires_rag` | Requires RAG context | Nécessite le contexte RAG |
| `skills.description` | Description | Description |
| `skills.execution_mode` | Execution mode | Mode d’exécution |
| `skills.trigger_mode` | Trigger mode | Mode de déclenchement |
| `skills.rag_context` | RAG context | Contexte RAG |
| `skills.priority` | Priority | Priorité |
| `skills.content` | SKILL.md content | Contenu SKILL.md |
| `skills.required_content` | SKILL.md content (required) | Contenu SKILL.md (obligatoire) |
| `skills.content_help` | Enter SKILL.md content with YAML frontmatter (name, description, execution_mode, trigger_mode, requires_rag_context) | Saisissez le contenu SKILL.md avec son en-tête YAML (name, description, execution_mode, trigger_mode, requires_rag_context) |
| `skills.execution_help_html` | <strong>LLM:</strong> Prompt injection. <strong>Ruby:</strong> Requires class in app/models/agent_skills/ | <strong>LLM :</strong> Injection d’instructions. <strong>Ruby :</strong> Nécessite une classe dans app/models/agent_skills/ |
| `skills.priority_help` | Higher priority = tried first (0-100) | Une priorité élevée est essayée en premier (0–100) |
| `skills.rag_help` | — enable if skill needs document/chunk access | — activez si la compétence doit accéder aux documents ou aux extraits |
| `skills.update` | Update skill | Mettre à jour la compétence |
| `skills.tags` | Tags: | Étiquettes : |
| `skills.yes` | Yes | Oui |
| `skills.no` | No | Non |
| `skills.execution.llm` | LLM | LLM |
| `skills.execution.ruby` | Ruby | Ruby |
| `skills.trigger.explicit` | Explicit | Explicite |
| `skills.trigger.auto` | Auto | Automatique |
| `skills.trigger.combined` | Combined | Combiné |
| `skills.created` | Agent skill created successfully | La compétence d’agent a été créée |
| `skills.updated` | Agent skill updated | La compétence d’agent a été mise à jour |
| `skills.deleted` | Agent skill deleted | La compétence d’agent a été supprimée |
| `skills.now_enabled` | Agent skill enabled | La compétence d’agent est activée |
| `skills.now_disabled` | Agent skill disabled | La compétence d’agent est désactivée |

Define `skills.errors.one/other` as `%{count} error prevented this skill from being saved:` / `%{count} errors prevented this skill from being saved:` and `%{count} erreur empêche l’enregistrement de cette compétence :` / `%{count} erreurs empêchent l’enregistrement de cette compétence :`.

Define `skills.content_placeholder` with the following paired multi-line values; the field remains a placeholder, never translated/saved instructions:

```yaml
# English value
content_placeholder: |-
  ---
  name: my_skill
  description: My skill description
  execution_mode: llm
  trigger_mode: explicit
  ---

  # Instructions
  Your skill instructions here...

# French value
content_placeholder: |-
  ---
  name: my_skill
  description: Description de ma compétence
  execution_mode: llm
  trigger_mode: explicit
  ---

  # Instructions
  Saisissez ici les instructions de votre compétence…
```

- [ ] Replace `.humanize` enum displays and options with these exact lookups:

```erb
<%= t("nosia.skills.execution.#{skill.execution_mode}") %>
<%= t("nosia.skills.trigger.#{skill.trigger_mode}") %>
<%= f.select :trigger_mode,
      options_for_select(AgentSkill.trigger_modes.keys.map { |value|
        [t("nosia.skills.trigger.#{value}"), value]
      }, agent_skill.trigger_mode), { include_blank: false }, class: "n-select" %>
<%= f.select :execution_mode,
      options_for_select(AgentSkill.execution_modes.keys.map { |value|
        [t("nosia.skills.execution.#{value}"), value]
      }, agent_skill.execution_mode), { include_blank: false }, class: "n-select" %>
```

Use explicit translated labels for `execution_mode`, `trigger_mode`, `priority`, and `enabled`; do not leave implicit English label humanization. Translate whole enable/disable action labels and success messages, not ternary fragments plus the word "skill". Keep skill descriptions, tags, names, Ruby class names, content, triggers, and execution behavior unchanged.

- [ ] Convert custom validation messages to symbol codes at their existing sites:

```ruby
# AgentSkill format validator
format: { with: /\A[a-zA-Z][a-zA-Z0-9_-]*\z/, message: :invalid_skill_name }

# AgentSkill#validate_metadata_present
errors.add(:skill_content, :missing_skill_metadata)

# McpServer endpoint/stdio checks
errors.add(:endpoint, :public_host_required) unless UrlGuard.safe?(candidate)
errors.add(:transport_type, :stdio_disabled)

# Chat::AccountScoped
errors.add(:account, :immutable_chat_account)

# McpCatalog#validate_required, preserving its existing names collection
record.errors.add(:base, :missing_required_config, fields: missing.map { |field| field[:name] }.join(", "))
```

Under the standard `errors.messages` root in the owning feature catalogs, define:

| Error key | English | French |
| --- | --- | --- |
| `invalid_skill_name` | must start with a letter and contain only alphanumeric, underscore, and hyphen | doit commencer par une lettre et ne contenir que des lettres, des chiffres, des tirets et des traits de soulignement |
| `missing_skill_metadata` | must contain valid YAML frontmatter with at least 'name' field | doit contenir un en-tête YAML valide avec au moins le champ 'name' |
| `public_host_required` | must point to a publicly routable host | doit désigner un hôte accessible publiquement |
| `stdio_disabled` | stdio requires MCP_STDIO_ENABLED on this deployment | stdio nécessite MCP_STDIO_ENABLED sur ce déploiement |
| `immutable_chat_account` | cannot be changed after creation | ne peut pas être modifié après la création |
| `missing_required_config` | Missing required config: %{fields} | Configuration requise manquante : %{fields} |

Store English attribute labels as their current Rails humanized spelling, with these French equivalents under `activerecord.attributes.<model>`. This translates **errors and implicit helper labels**, not schema names:

| Model | Attribute = English / French |
| --- | --- |
| user | email = Email / E-mail; password = Password / Mot de passe; password_confirmation = Password confirmation / Confirmation du mot de passe |
| account | name = Name / Nom; uid = Uid / UID; owner = Owner / Propriétaire |
| account_user | user = User / Utilisateur; account = Account / Compte |
| api_token | name = Name / Nom; account = Account / Compte |
| chat | account = Account / Compte; prompt = Prompt / Message |
| message | content = Content / Contenu; chat = Chat / Conversation |
| document | title = Title / Titre; file = File / Fichier; account = Account / Compte |
| text | title = Title / Titre; data = Data / Texte; account = Account / Compte |
| qna | question = Question / Question; answer = Answer / Réponse; account = Account / Compte |
| website | url = Url / URL; data = Data / Données; account = Account / Compte |
| mcp_server | name = Name / Nom; endpoint = Endpoint / Adresse du serveur; transport_type = Transport type / Type de transport; account = Account / Compte |
| agent_skill | name = Name / Nom; skill_content = Skill content / Contenu de la compétence; execution_mode = Execution mode / Mode d’exécution; trigger_mode = Trigger mode / Mode de déclenchement; priority = Priority / Priorité; enabled = Enabled / Activée; account = Account / Compte |
| prompt | content = Content / Instructions; name = Name / Nom |

Use Rails' standard French validation/error/date translations from `rails-i18n`; do not duplicate all framework locale data in application catalogs.

- [ ] Run copy/page tests, `test/models/agent_skill_test.rb`, `test/controllers/chat_account_selection_test.rb`, `test/models/chat_account_test.rb`, and existing MCP security/validation tests. Run API authentication/completion tests under a French header/cookie to confirm error text/status contracts stay English. Expected GREEN, with the English custom-message wording preserved.
- [ ] Commit named files with `feat(i18n): translate skills and validation messages`.

## Task 10: Localize usage, energy explanations, numbers, dates, and cache keys

**Files:** Modify all three ERB files under `app/views/token_usages/`, `app/views/chats/_token_totals.html.erb`, `app/views/messages/_token_footer.html.erb`, `app/views/models/show.html.erb`; create both usage catalogs and `test/integration/localized_cache_test.rb`; extend the copy/page tests.

- [ ] Write the cache-isolation test first:

```ruby
require "test_helper"
require_relative "../support/chat_account_fixtures"

class LocalizedCacheTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup do
    sign_in_picker_user
    @previous_cache = Rails.cache
    @previous_store = ActionController::Base.cache_store
    @previous_caching = ActionController::Base.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = Rails.cache
    ActionController::Base.perform_caching = true
    @first.update_columns(input_tokens_count: 1234)
  end

  teardown do
    Rails.cache = @previous_cache
    ActionController::Base.cache_store = @previous_store
    ActionController::Base.perform_caching = @previous_caching
  end

  test "French and English fragments do not contaminate each other" do
    get token_usage_url, headers: { "Accept-Language" => "en" }
    assert_response :success
    assert_includes response.body, "1,234"
    assert_includes response.body, "Energy"

    get token_usage_url, headers: { "Accept-Language" => "fr" }
    assert_response :success
    assert_select "h2", text: "Utilisation des jetons et impact environnemental"
    assert_includes response.body, "Énergie"
    refute_includes response.body, "1,234"
    assert_equal 1234, @first.reload.input_tokens_count

    get token_usage_url, headers: { "Accept-Language" => "en" }
    assert_includes response.body, "1,234"
    assert_includes response.body, "Energy"
  end
end
```

Add to `ViewCopyTest`:

```ruby
test "usage text and methodology are catalogued" do
  paths = Dir.glob(Rails.root.join("app/views/token_usages/**/*.erb"))
  paths += %w[chats/_token_totals.html.erb messages/_token_footer.html.erb].map { |path| Rails.root.join("app/views", path).to_s }
  assert_localized_view_sources(paths)
end
```

- [ ] Run the copy/cache tests RED. Use this usage catalog:

| Key suffix | English | French |
| --- | --- | --- |
| `usage.title` | Token usage & environmental impact | Utilisation des jetons et impact environnemental |
| `usage.input` | Input | Entrée |
| `usage.output` | Output | Sortie |
| `usage.total` | Total | Total |
| `usage.energy` | Energy | Énergie |
| `usage.tokens_title` | Tokens | Jetons |
| `usage.short_tokens` | tok | jetons |
| `usage.per_model` | Per model (top 5) | Par modèle (les 5 premiers) |
| `usage.per_kind` | Per kind | Par type |
| `usage.none` | No usage yet. | Aucune utilisation pour le moment. |
| `usage.last_30_days` | Last 30 days | Les 30 derniers jours |
| `usage.fallback_note` | * estimated using a fallback energy coefficient (model not in the Comparia dataset). | * estimation à l’aide d’un coefficient énergétique de repli (modèle absent du jeu de données Comparia). |
| `usage.kinds.completion` | completion | génération |
| `usage.kinds.embedding` | embedding | vectorisation |
| `usage.kinds.agent_skill` | agent_skill | compétence d’agent |
| `usage.input_output_tooltip` | Input / output tokens | Jetons d’entrée et de sortie |
| `usage.energy_tooltip` | Energy estimate (kWh) | Estimation de l’énergie (kWh) |
| `usage.co2_tooltip` | CO2e estimate | Estimation du CO2e |
| `usage.fallback_tooltip` | estimate — model absent from the Comparia benchmark | estimation — modèle absent du benchmark Comparia |
| `usage.total_tooltip` | Total energy & CO₂e — Ecologits methodology | Énergie et CO₂e totaux — méthode Ecologits |
| `usage.total_fallback_tooltip` | Total energy & CO₂e — Ecologits methodology (incl. fallback estimate) | Énergie et CO₂e totaux — méthode Ecologits (avec estimation de repli) |
| `usage.methodology` | Methodology | Méthode de calcul |
| `usage.expand` | Expand | Développer |
| `usage.methodology_question` | How is the energy impact of models calculated? | Comment l’impact énergétique des modèles est-il calculé ? |
| `usage.methodology_caveat` | Methodologies for assessing the environmental impact of AI are still under development. | Les méthodes d’évaluation de l’impact environnemental de l’IA sont encore en cours de développement. |
| `usage.data_source` | Data source | Source des données |
| `usage.dataset_name` | Comparia model-energy dataset | Jeu de données Comparia sur l’énergie des modèles |

Define `usage.token_unit.one/other` as `token`/`tokens` and `jeton`/`jetons`; define `usage.token_quantity.one/other` as `%{formatted_count} token`/`%{formatted_count} tokens` and `%{formatted_count} jeton`/`%{formatted_count} jetons`.

Use the following complete paragraph values (YAML block scalars). They replace the entire corresponding methodology paragraphs, not isolated sentence fragments:

```yaml
# English values below nosia.usage
methodology_intro_html: >-
  Nosia uses the methodology developed by %{ecologits} (GenAI Impact) — the same one powering %{comparia} — to estimate the energy balance of generative-AI model inference. This lets you compare the environmental impact of different models for the same request. Transparency is essential to encourage the development and adoption of more eco-responsible AI models.
methodology_lifecycle_html: >-
  Ecologits applies life-cycle assessment (LCA) principles following the <strong>ISO 14044</strong> standard, focusing for now on the impact of <em>inference</em> (using models to answer requests) and the manufacturing of graphics cards (resource extraction, manufacturing, and transport).
methodology_measurement_html: >-
  The model's electricity consumption is estimated from parameters such as the size and architecture of the model, the location of the servers where the models are deployed, and the number of output tokens. The climate-change potential indicator, expressed in <strong>CO₂-equivalent</strong>, is derived from the electricity-consumption measurement.
dataset_source_html: >-
  Per-model consumption (mWh per 1000 tokens) from the %{dataset} — <span class="font-medium">licence Etalab 2.0</span>, snapshot dated <span class="font-medium">%{date}</span>.
dataset_fallback_html: >-
  Models absent from the dataset (notably most API-only models, whose consumption is reported as <code>N/A</code>) use a fallback coefficient — marked with <strong>*</strong> in the breakdowns above.
```

```yaml
# French values below nosia.usage
methodology_intro_html: >-
  Nosia utilise la méthode développée par %{ecologits} (GenAI Impact), également utilisée par %{comparia}, pour estimer le bilan énergétique de l’inférence des modèles d’IA générative. Vous pouvez ainsi comparer l’impact environnemental de différents modèles pour une même demande. La transparence est essentielle pour encourager le développement et l’adoption de modèles d’IA plus écoresponsables.
methodology_lifecycle_html: >-
  Ecologits applique les principes de l’analyse du cycle de vie (ACV) selon la norme <strong>ISO 14044</strong>, en se concentrant actuellement sur l’impact de l’<em>inférence</em> (l’utilisation des modèles pour répondre aux demandes) et de la fabrication des cartes graphiques (extraction des ressources, fabrication et transport).
methodology_measurement_html: >-
  La consommation d’électricité du modèle est estimée à partir de paramètres tels que sa taille et son architecture, l’emplacement des serveurs où il est déployé et le nombre de jetons de sortie. L’indicateur de potentiel de changement climatique, exprimé en <strong>équivalent CO₂</strong>, est dérivé de la mesure de consommation d’électricité.
dataset_source_html: >-
  Consommation par modèle (mWh pour 1 000 jetons) issue du %{dataset}, sous <span class="font-medium">licence Etalab 2.0</span>, version du <span class="font-medium">%{date}</span>.
dataset_fallback_html: >-
  Les modèles absents du jeu de données (notamment la plupart des modèles accessibles uniquement par API, dont la consommation est indiquée comme <code>N/A</code>) utilisent un coefficient de repli, signalé par <strong>*</strong> dans les détails ci-dessus.
```

- [ ] Change the fragment key without dropping its counter invalidation:

```erb
<% cache [I18n.locale, Current.account, Current.account.input_tokens_count,
          Current.account.output_tokens_count, "token-usage-summary"] do %>
```

Replace usage kind display with `t("nosia.usage.kinds.#{kind}")`, not `.humanize`. Rename the local token-count variable `t` to `token_count` to avoid confusing it with the translation helper; keep all arithmetic, chart SVG coordinate formatting, and counter values locale-neutral. Use existing Rails number helpers for visible counts/precision only; do not apply locale delimiters to SVG `points`, style widths, ISO timestamps, or hidden inputs.

Translate `_token_footer`'s tooltip ternary and `_token_totals`' whole tooltip using `usage.total_tooltip` or `usage.total_fallback_tooltip`. Render formatted token amounts with numeric `count` and separate `formatted_count`. Add the corresponding `usage.token_quantity` call to model context-window/max-output display rather than a hard-coded `tokens` suffix.

- [ ] Render methodology paragraphs using safe link interpolation and the existing external URLs/rel attributes:

```erb
<p><%= t("nosia.usage.methodology_intro_html",
  ecologits: link_to("Ecologits", "https://ecologits.ai", target: "_blank", rel: "noopener", class: "underline"),
  comparia: link_to("compar:IA", "https://comparia.beta.gouv.fr", target: "_blank", rel: "noopener", class: "underline")) %></p>
<p><%= t("nosia.usage.methodology_lifecycle_html") %></p>
<p><%= t("nosia.usage.methodology_measurement_html") %></p>
<p><%= t("nosia.usage.methodology_caveat") %></p>
<p><%= t("nosia.usage.data_source") %></p>
<p><%= t("nosia.usage.dataset_source_html",
  dataset: link_to(t("nosia.usage.dataset_name"), "https://comparia.beta.gouv.fr/ranking", target: "_blank", rel: "noopener", class: "underline"),
  date: l(Date.new(2026, 7, 2), format: :dataset_snapshot)) %></p>
<p><%= t("nosia.usage.dataset_fallback_html") %></p>
```

Under `date.formats.dataset_snapshot` add `"%-d %B %Y"` in both locale files; month names come from Rails locale data. Keep the real dataset snapshot date and license, not the feature date. Preserve the surrounding disclosure, typography, themes, links, and scope.

- [ ] In `test/integration/token_footer_test.rb`, replace the English-mode fallback-tooltip assertion `absent du benchmark Comparia` with `model absent from the Comparia benchmark`, and add a French `I18n.with_locale(:fr)` rendering assertion retaining `absent du benchmark Comparia`. Preserve every existing energy/precision/token assertion. Add this test file to Task 10's modifications.
- [ ] Run Task 10 tests, `test/integration/token_usages_test.rb`, `test/integration/token_summary_cache_test.rb`, `test/integration/token_footer_test.rb`, `test/models/token_usage_test.rb`, `test/integration/models_consumption_column_test.rb`. Expected GREEN; old English precision/counter assertions remain meaningful. Only intentionally changed French/English human labels may change rendering assertions.
- [ ] Commit named files with `feat(i18n): localize usage formatting and isolate translated caches`.

## Task 11: Localize every broadcast path without changing event semantics

**Files:** Create `app/models/concerns/localized_broadcasting.rb`, `test/integration/localized_broadcasts_test.rb`, `test/support/localization_fixtures.rb`, `test/support/fixtures/localization/messages.yml`, `test/support/fixtures/localization/token_usages.yml`; modify `app/models/chat.rb`, `app/models/message.rb`, `app/models/token_usage.rb`, `app/models/concerns/sourceable.rb`, `app/models/chat/completionable.rb`, `app/models/chat/similarity_search.rb`, `app/views/chats/show.html.erb`, `app/views/sources/index.html.erb`. Update affected stream assertions in existing tests listed below.

- [ ] Add these **opt-in** fixture files and helper before the new test. They load only for localization live-update tests and do not change existing `ChatAccountFixtures` consumers:

```yaml
# test/support/fixtures/localization/messages.yml
localized_assistant:
  chat: picker_second_chat
  role: 10
  content: Shared fixture answer
  response_number: 1
  done: false
```

```yaml
# test/support/fixtures/localization/token_usages.yml
localized_chat_usage:
  account: picker_second
  chat: picker_second_chat
  kind: completion
  model_id: picker-test-model
  input_tokens: 1234
  output_tokens: 12
```

```ruby
# test/support/localization_fixtures.rb
require_relative "chat_account_fixtures"

module LocalizationFixtures
  extend ActiveSupport::Concern
  include ChatAccountFixtures

  included do
    setup do
      @localization_fixtures = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/localization").to_s,
        %w[messages token_usages]
      ).index_by(&:name)
    end
  end

  %w[messages token_usages].each do |table|
    define_method(table) do |name|
      @localization_fixtures.fetch(table).fixtures.fetch(name.to_s).find
    end
  end
end
```

`messages` has no `account_id` in the actual schema; its tenant comes through the chat. The token ledger's `model_id` is a string. Do not add schema fields to make fixtures match generic repository instructions.

- [ ] First add a test capturing **both languages from the same event**, not two isolated renders:

```ruby
require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/localization_fixtures"

class LocalizedBroadcastsTest < ActiveSupport::TestCase
  include LocalizationFixtures
  include Turbo::Broadcastable::TestHelper
  include ActionView::RecordIdentifier

  def capture_languages(parts, &operation)
    payloads = {}
    payloads[:en] = capture_turbo_stream_broadcasts([ *parts, :en ]) do
      payloads[:fr] = capture_turbo_stream_broadcasts([ *parts, :fr ], &operation)
    end
    payloads
  end

  test "one background unlock serves French and English without Current" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    Current.reset
    payloads = capture_languages([ chat, :messages ]) { chat.finish_generation! }
    { en: "Send", fr: "Envoyer" }.each do |locale, label|
      forms = payloads.fetch(locale).select { |event| event["target"] == "#{dom_id(chat)}_message_form" }
      assert_equal 1, forms.size
      assert_includes forms.first.to_html, "aria-label=\"#{label}\""
      assert_equal 1, payloads.fetch(locale).count { |event| event["action"] == "refresh" }
      assert payloads.fetch(locale).any? { |event| event["action"] == "remove" && event["target"] == "thinking_animation" }
    end
    assert_equal :en, I18n.locale
  end

  test "progress is translated per recipient rather than the job locale" do
    chat = chats(:picker_second_chat)
    payloads = capture_languages([ chat, :messages ]) do
      I18n.with_locale(:en) { chat.broadcast_thinking_phase("indexing") }
    end
    assert_includes payloads.fetch(:en).first.to_html, "Indexing your attachments"
    assert_includes payloads.fetch(:fr).first.to_html, "Indexation de vos pièces jointes"
  end

  test "source rows and counts fan out without losing filter identity" do
    text = texts(:picker_second_text)
    text.update_columns(index_status: "pending")
    payloads = capture_languages([ @second, "sources" ]) { text.mark_indexed! }
    { en: "Indexed", fr: "Indexé" }.each do |locale, label|
      row = payloads.fetch(locale).find { |event| event["target"] == dom_id(text, :source_row) }
      assert row
      assert_includes row.to_html, label
      assert_equal 8, payloads.fetch(locale).size
    end
    prepends = capture_languages([ @second, "sources", "list:text:all" ]) { text.broadcast_source_created }
    assert prepends.values.all? { |events| events.one? { |event| event["action"] == "prepend" && event["target"] == "sources_list" } }
  end

  test "old unqualified streams receive no updates" do
    chat = chats(:picker_second_chat)
    events = capture_turbo_stream_broadcasts([ chat, :messages ]) { chat.finish_generation! }
    assert_empty events
    text = texts(:picker_second_text)
    events = capture_turbo_stream_broadcasts([ @second, "sources" ]) { text.broadcast_source_status_change }
    assert_empty events
  end
end
```

- [ ] Run this new file RED before touching broadcast code. Expected RED: no locale-qualified events and the phase method still requires an English message argument. Keep the existing unqualified regressions passing until the deliberate stream migration below.
- [ ] Implement the focused concern:

```ruby
module LocalizedBroadcasting
  extend ActiveSupport::Concern

  class_methods do
    # Locale-aware counterpart of the existing broadcasts_to lifecycle macro.
    # @param stream [Proc] Resolves the unchanged resource stream parts
    # @return [void]
    def broadcasts_localized_to(stream)
      after_create_commit do
        broadcast_localized_to(:append_later, stream.call(self), target: self.class.broadcast_target_default)
      end
      after_update_commit { broadcast_localized_to(:replace_later, stream.call(self)) }
      after_destroy_commit { broadcast_localized_to(:remove, stream.call(self)) }
    end
  end

  # Publish the same logical event in both supported UI languages.
  # @param action [Symbol] Existing Turbo action, optionally ending in _later
  # @param streamables [Array<Object>] Unchanged account/chat/filter stream parts
  # @param options [Hash] Existing Turbo target/rendering options
  # @return [void]
  def broadcast_localized_to(action, *streamables, **options)
    I18n.available_locales.each do |locale|
      I18n.with_locale(locale) do
        public_send("broadcast_#{action}_to", *streamables.flatten, locale, **options)
      end
    end
  end
end
```

This uses actual Turbo public broadcasting methods; do not wrap/override both `broadcast_append_to` and `broadcast_action_to`, which would nest fan-out and duplicate events. Only internal static action symbols call this helper; do not pass an action from user input. Async Turbo jobs capture their locale when enqueued; verify payloads after `perform_enqueued_jobs`, not only at enqueue time.

- [ ] Include the concern in `Chat`, `Message`, `TokenUsage`, and as a concern dependency in `Sourceable`. Replace each existing `broadcasts_to` declaration in Chat/Message with `broadcasts_localized_to` using its unchanged lambda. Do **not** retain both macros or silently remove lifecycle callbacks. Replace each explicit call's method token using this exact mapping, keeping its complete argument list, target, partial, and locals unchanged:

| Existing method token | Replacement method/action prefix |
| --- | --- |
| `broadcast_append_to` | `broadcast_localized_to :append,` |
| `broadcast_update_to` | `broadcast_localized_to :update,` |
| `broadcast_replace_to` | `broadcast_localized_to :replace,` |
| `broadcast_remove_to` | `broadcast_localized_to :remove,` |
| `broadcast_refresh_to` | `broadcast_localized_to :refresh,` |
| `broadcast_prepend_to` | `broadcast_localized_to :prepend,` |

This is a mechanical prefix replacement; nested stream arrays still work because the helper flattens them before adding the locale. The complete composer-unlock calls, including their real arguments, become:

```ruby
broadcast_localized_to :replace, self, "messages",
  target: "#{dom_id(self)}_message_form",
  partial: "messages/form",
  locals: { chat: self }
broadcast_localized_to :remove, self, :messages, target: "thinking_animation"
broadcast_localized_to :refresh, self, :messages
```

`Message#broadcast_streamed_content` still computes `html = self.class.render_markdown_content(text)` **once before** fan-out. Reuse `content_html: html` for both locales; do not run the markdown renderer once per locale/delta. Keep all stream buffering, duplicate-message guards, intermediate tool/system filtering, ordering, retry/stop paths, and message content unchanged.

- [ ] Replace worker phase APIs with the complete localized render boundary:

```ruby
def broadcast_thinking_phase(phase)
  broadcast_localized_to :update, self, :messages,
    target: "thinking_animation_content",
    partial: "messages/thinking_animation",
    locals: { phase: phase }
end
```

The four call sites become `broadcast_thinking_phase("indexing")` in Chat, `broadcast_thinking_phase("searching")` and `broadcast_thinking_phase("retrieving")` in SimilaritySearch, and `broadcast_thinking_phase("generating")` in Completionable. Do not translate the actual relevance warning appended to persisted `message.content`, prompt instructions, excluded-source notes, or LLM chunks.

- [ ] Change all four subscription declarations exactly:

```erb
<%# chats/show %>
<%= turbo_stream_from @chat, :messages, I18n.locale %>
<%= turbo_stream_from @chat, :token_totals, I18n.locale %>

<%# sources/index %>
<%= turbo_stream_from Current.account, "sources", I18n.locale %>
<%= turbo_stream_from Current.account, "sources", "list:#{@type}:#{@status}", I18n.locale %>
```

Keep the filtered-list subscription's existing `@query.blank?` guard. Keep signed stream generation and existing account/chat authorization; no unqualified compatibility subscription or subscriber registry.

- [ ] Update **only intentional stream identity** in existing assertions: append `:en` to stream arrays in `test/models/sourceable_broadcast_test.rb`, `test/models/message_test.rb`, `test/models/message_placeholder_test.rb`, `test/models/chat_test.rb`, `test/models/chat/completionable_test.rb`, `test/models/chat/similarity_search_test.rb`, `test/models/chat_account_test.rb`, `test/jobs/chat_response_job_test.rb`, `test/integration/chat_composer_ui_test.rb`. Filter-list arrays put `:en` after `list:...`. Preserve existing per-language counts (eight source replaces; one/four coalesced content flushes) and content/ordering assertions. Add equivalent assertions for `:fr` in the new test file rather than weakening old tests to ignore missing broadcasts.

- [ ] Extend `LocalizedBroadcastsTest` with these independent behavior tests before their final adjustments:

```ruby
test "streamed content is identical in both languages and remains stored verbatim" do
  message = messages(:localized_assistant)
  original = message.content
  payloads = capture_languages([ message.chat, :messages ]) do
    message.broadcast_streamed_content("# Shared\n\n**answer**")
  end
  assert_equal 1, payloads.fetch(:en).size
  assert_equal payloads.fetch(:en).first.to_html, payloads.fetch(:fr).first.to_html
  assert_includes payloads.fetch(:fr).first.to_html, "<strong>answer</strong>"
  assert_equal original, message.reload.content
end

test "automatic lifecycle callbacks preserve locale through Turbo jobs" do
  chat = chats(:picker_second_chat)
  payloads = capture_languages([ chat, :messages ]) do
    perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
      chat.touch
    end
  end
  assert payloads.fetch(:en).any?
  assert payloads.fetch(:fr).any?
  assert_equal :en, I18n.locale
end

test "source removal reaches both locales but not a foreign account" do
  text = texts(:picker_second_text)
  foreign = capture_languages([ @foreign, "sources" ]) do
    @removals = capture_languages([ @second, "sources" ]) { text.broadcast_source_removed }
  end
  assert foreign.values.all?(&:empty?)
  @removals.each_value do |events|
    assert events.any? { |event| event["action"] == "remove" && event["target"] == dom_id(text, :source_row) }
  end
end
```

Exercise token totals through a new ledger event copied from a fixture, never by calling its private callback:

```ruby
test "a real usage event refreshes localized totals without foreign delivery" do
  chat = chats(:picker_second_chat)
  foreign_chat = chats(:picker_foreign_chat)
  Current.reset
  foreign = capture_languages([ foreign_chat, :token_totals ]) do
    @totals = capture_languages([ chat, :token_totals ]) do
      token_usages(:localized_chat_usage).dup.save!
    end
  end
  assert foreign.values.all?(&:empty?)
  assert_equal 1, @totals.fetch(:en).size
  assert_equal 1, @totals.fetch(:fr).size
  assert_includes @totals.fetch(:en).first.to_html, "Tokens"
  assert_includes @totals.fetch(:fr).first.to_html, "Jetons"
  assert_includes @totals.fetch(:en).first.to_html, "1,234"
  refute_includes @totals.fetch(:fr).first.to_html, "1,234"
  assert_equal dom_id(chat, :token_totals), @totals.fetch(:fr).first["target"]
end
```

The fixture's direct insertion deliberately does not simulate callbacks; saving its duplicate is the new public event that increments counters and broadcasts. No factories, global fixture registration, or private callback invocation are needed.

- [ ] Run `AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/integration/localized_broadcasts_test.rb test/models/sourceable_broadcast_test.rb test/models/message_test.rb test/models/message_placeholder_test.rb test/models/chat_test.rb test/models/chat/completionable_test.rb test/models/chat/similarity_search_test.rb test/models/chat_account_test.rb test/jobs/chat_response_job_test.rb test/integration/chat_composer_ui_test.rb`. Expected GREEN with unchanged per-viewer coalescing counts and no fallback stream deliveries. Re-run chat/source authorization tests as well.
- [ ] Commit named files with `feat(i18n): isolate localized Turbo streams and background rendering`.

## Task 12: Enforce complete catalogs and bilingual static recovery pages

**Files:** Create `test/internationalization/catalogs_test.rb`, `test/packaging/bilingual_error_pages_test.rb`; extend `test/internationalization/view_copy_test.rb`; modify `public/404.html`, `public/406-unsupported-browser.html`, `public/422.html`, `public/500.html`; finish missing copy in the feature catalogs/templates identified by the strict audit.

- [ ] Write the catalog contract test before final catalog cleanup:

```ruby
require "test_helper"
require "yaml"

class CatalogsTest < ActiveSupport::TestCase
  def application_catalog(locale)
    Dir.glob(Rails.root.join("config/locales/#{locale}.nosia_*.yml")).sort.each_with_object({}) do |path, data|
      root = YAML.safe_load_file(path, aliases: false).fetch(locale.to_s)
      data.deep_merge!(root)
    end
  end

  def leaves(value, prefix = [])
    value.each_with_object({}) do |(key, entry), result|
      path = prefix + [ key.to_s ]
      if entry.is_a?(Hash)
        result.merge!(leaves(entry, path))
      else
        result[path.join(".")] = entry
      end
    end
  end

  test "application locales have the same complete leaves and interpolation" do
    english = leaves(application_catalog(:en))
    french = leaves(application_catalog(:fr))
    assert english.keys.any? { |key| key.start_with?("nosia.chat.") }
    assert_equal english.keys.sort, french.keys.sort
    english.each do |key, value|
      assert_kind_of String, value, key
      assert_kind_of String, french.fetch(key), key
      refute_empty value.strip, key
      refute_empty french.fetch(key).strip, key
      assert_equal value.scan(/%\{([^}]+)\}/).flatten.sort,
        french.fetch(key).scan(/%\{([^}]+)\}/).flatten.sort, key
    end
  end

  test "English fallback works independently of catalog completeness" do
    backend = Class.new(I18n::Backend::Simple) { include I18n::Backend::Fallbacks }.new
    backend.store_translations(:en, nosia_fallback_probe: "English fallback")
    assert_equal "English fallback", backend.translate(:fr, :nosia_fallback_probe)
  end

  test "every application plural works with fallback disabled" do
    %w[nosia.chat.sources nosia.sources.pasted_words nosia.sources.types.document
       nosia.sources.types.text nosia.sources.types.qna nosia.sources.types.website
       nosia.mcp.errors nosia.skills.errors nosia.usage.token_unit
       nosia.usage.token_quantity].each do |key|
      [ :en, :fr ].each do |locale|
        [ 0, 1, 2, 1000000 ].each do |count|
          text = I18n.t(key, locale: locale, count: count, formatted_count: count.to_s, fallback: false, raise: true)
          assert_kind_of String, text, "#{locale}.#{key}:#{count}"
        end
      end
    end
  end
end
```

Do not compare against the merged runtime backend alone: that would let fallback disguise missing French. Also detect duplicate leaves across files before deep-merging, and duplicate mapping keys within each YAML file, using the following test:

```ruby
def assert_unique_yaml_mappings(node, path)
  if node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map { |key, _value| key.value }
    assert_equal keys.uniq, keys, "duplicate YAML key in #{path}"
  end
  node.children&.each { |child| assert_unique_yaml_mappings(child, path) }
end

test "catalog files do not silently overwrite translation leaves" do
  [ :en, :fr ].each do |locale|
    seen = []
    Dir.glob(Rails.root.join("config/locales/#{locale}.nosia_*.yml")).sort.each do |path|
      assert_unique_yaml_mappings(Psych.parse_stream(File.read(path)), path)
      keys = leaves(YAML.safe_load_file(path).fetch(locale.to_s)).keys
      assert_empty seen & keys, "duplicate translation leaves in #{path}"
      seen.concat(keys)
    end
  end
end
```

- [ ] Add a final full-tree source-audit test, covering even legacy/non-navigation-linked partials:

```ruby
test "all application ERB visible copy and accessibility text is catalogued" do
  paths = Dir.glob(Rails.root.join("app/views/**/*.erb"))
  manifest = Rails.root.join("app/views/pwa/manifest.json.erb").to_s
  assert_localized_view_sources(paths - [ manifest ])
end
```

`app/views/pwa/manifest.json.erb` is explicitly excluded from the HTML-source parser because it is a JSON machine artifact containing only product name `Nosia`, not translatable human copy. Keep its URL, scope, icons, and identity unchanged. Plain document/text/Q&A/website render partials should continue to output authored content without translation.

- [ ] Write the static recovery-page test as a standalone Minitest test:

```ruby
require "minitest/autorun"
require "nokogiri"

class BilingualErrorPagesTest < Minitest::Test
  FILES = %w[404.html 406-unsupported-browser.html 422.html 500.html].freeze

  def test_all_recovery_pages_work_without_Rails_or_JavaScript
    FILES.each do |name|
      path = File.expand_path("../../public/#{name}", __dir__)
      document = Nokogiri::HTML(File.read(path))
      %w[en fr].each do |locale|
        section = document.at_css("body [lang='#{locale}']")
        refute_nil section, "#{name}: #{locale} section"
        refute_empty section.at_css("h1").text.strip
      end
      assert_empty document.css("script, link[href^='http'], script[src]")
      assert_includes document.at_css("title").text, name.split("-").first.split(".").first
    end
  end
end
```

The path from `test/packaging` is `../../public`; verify it with the standalone command, without loading Rails. Do not rely on `Rails.root` in this recovery test.

- [ ] Run `AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/internationalization` and `bundle exec ruby test/packaging/bilingual_error_pages_test.rb`. Expected RED on any incomplete copy and missing bilingual page sections.
- [ ] Retain each page's embedded styles, viewport/meta tags, filename, HTTP purpose, and standalone operation. Set document `lang=en` and these exact title elements:

```html
<!-- 404.html -->
<title>404 — Page not found / Page introuvable</title>
<!-- 406-unsupported-browser.html -->
<title>406 — Unsupported browser / Navigateur non pris en charge</title>
<!-- 422.html -->
<title>422 — Change rejected / Modification refusée</title>
<!-- 500.html -->
<title>500 — Application error / Erreur de l’application</title>
```

Replace each body dialog with these explicit sections:

```html
<div class="dialog">
  <div lang="en">
    <h1>The page you were looking for doesn't exist.</h1>
    <p>You may have mistyped the address or the page may have moved.</p>
  </div>
  <div lang="fr">
    <h1>La page que vous cherchez n’existe pas.</h1>
    <p>L’adresse est peut-être incorrecte ou la page a été déplacée.</p>
  </div>
  <p lang="en">If you are the application owner check the logs for more information.</p>
  <p lang="fr">Si vous gérez cette application, consultez les journaux pour plus d’informations.</p>
</div>
```

The block above is the complete 404 dialog. The other three complete dialogs are:

```html
<!-- public/406-unsupported-browser.html -->
<div class="dialog">
  <div lang="en">
    <h1>Your browser is not supported.</h1>
    <p>Please upgrade your browser to continue.</p>
  </div>
  <div lang="fr">
    <h1>Votre navigateur n’est pas pris en charge.</h1>
    <p>Veuillez mettre à jour votre navigateur pour continuer.</p>
  </div>
</div>
```

```html
<!-- public/422.html -->
<div class="dialog">
  <div lang="en">
    <h1>The change you wanted was rejected.</h1>
    <p>Maybe you tried to change something you didn't have access to.</p>
  </div>
  <div lang="fr">
    <h1>La modification demandée a été refusée.</h1>
    <p>Vous avez peut-être essayé de modifier un élément auquel vous n’avez pas accès.</p>
  </div>
  <p lang="en">If you are the application owner check the logs for more information.</p>
  <p lang="fr">Si vous gérez cette application, consultez les journaux pour plus d’informations.</p>
</div>
```

```html
<!-- public/500.html -->
<div class="dialog">
  <div lang="en"><h1>We're sorry, but something went wrong.</h1></div>
  <div lang="fr"><h1>Une erreur est survenue. Veuillez nous en excuser.</h1></div>
  <p lang="en">If you are the application owner check the logs for more information.</p>
  <p lang="fr">Si vous gérez cette application, consultez les journaux pour plus d’informations.</p>
</div>
```

The standalone safety net intentionally contains literal bilingual text; do not make it depend on I18n, cookies, an asset server, or dynamic error controllers.

- [ ] Resolve audit findings by adding genuine paired translations and replacing their literals. Examples of easily missed surfaces: SVG accessible names, native form prompts, `_chat` dates, `models/show` links and colon-suffixed labels, source empty-state messages, both assistant/message partials, browser upload errors, and all method-specific flash strings. Use the feature's catalog, not an unrelated catch-all dictionary. Never exempt a missing English/French sentence from the audit.
- [ ] Run all i18n tests and the standalone packaging test GREEN. Inspect both languages manually for fluency; key parity alone cannot prove the French is correct. No `translation missing` markers, raw interpolation tokens, or duplicate catalog keys may remain.
- [ ] Commit named files with `feat(i18n): complete translation coverage and bilingual recovery pages`.

## Task 13: Verify real browser navigation/live delivery, document, and review

**Files:** Extend `test/system/localization_test.rb`; create `docs/internationalization.md`; modify `docs/README.md`, `docs/DEBT.md`, and only intentional locale-sensitive assertions in existing tests. Do not modify unrelated baseline failures.

- [ ] Add this browser navigation test before the final layout/navigation adjustments:

```ruby
test "language switching fully reloads the current page and survives Turbo navigation" do
  visit root_url
  select "English", from: "language_preference_locale"
  find("form[action='/language_preference'] button[type=submit]").click
  fill_in "email", with: @user.email
  fill_in "password", with: ChatAccountFixtures::PASSWORD
  click_on "Sign in"
  visit new_chat_url(account_id: @second.id, model: "picker-test-model")
  previous_origin = page.evaluate_script("performance.timeOrigin")
  select "Français", from: "language_preference_locale"
  find("form[action='/language_preference'] button[type=submit]").click
  assert_selector "html[lang=fr]"
  refute_equal previous_origin, page.evaluate_script("performance.timeOrigin")
  assert_current_path new_chat_path(account_id: @second.id, model: "picker-test-model")
  assert_selector "button[aria-label=Envoyer]"
  assert_selector "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
  page.execute_script("Turbo.visit(arguments[0])", sources_path)
  assert_selector "input[placeholder='Rechercher des sources…']"
  page.go_back
  assert_selector "html[lang=fr] button[aria-label=Envoyer]"
end
```

- [ ] Add an actual two-browser-session Cable test, not only a snapshot rendering assertion:

```ruby
test "French and English browsers receive the same chat event in their own language" do
  chat = chats(:picker_second_chat)
  chat.start_generation!
  { english: [ "English", "Sign in", "en" ], french: [ "Français", "Se connecter", "fr" ] }.each do |name, values|
    Capybara.using_session(name) do
      visit root_url
      select values[0], from: "language_preference_locale"
      find("form[action='/language_preference'] button[type=submit]").click
      fill_in "email", with: @user.email
      fill_in "password", with: ChatAccountFixtures::PASSWORD
      click_on values[1]
      visit chat_url(chat)
      assert_selector "html[lang='#{values[2]}']"
      assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
      assert_selector "#thinking_animation"
    end
  end

  chat.broadcast_thinking_phase("indexing")
  Capybara.using_session(:english) { assert_text "Indexing your attachments" }
  Capybara.using_session(:french) { assert_text "Indexation de vos pièces jointes" }
  chat.finish_generation!
  Capybara.using_session(:english) do
    assert_button "Send", disabled: false, enable_aria_label: true
    assert_no_selector "#thinking_animation"
  end
  Capybara.using_session(:french) do
    assert_button "Envoyer", disabled: false, enable_aria_label: true
    assert_no_selector "#thinking_animation"
  end
ensure
  Capybara.reset_sessions!
end
```

Do not run two browsers against a stubbed Cable subscription. Wait for the real `[connected]` attributes before broadcasting. Use the existing test adapter in-process; do not start workers or call an AI provider.

- [ ] Add this complete source Cable test. Both browsers' Sources page uses the user's existing first account; do not invent an account-switch API:

```ruby
test "source status counts and removal stay localized in both browsers" do
  text = texts(:picker_first_text)
  text.update_columns(index_status: "pending")
  other_account_source = texts(:picker_second_text)
  { english_sources: [ "English", "Sign in" ], french_sources: [ "Français", "Se connecter" ] }.each do |name, values|
    Capybara.using_session(name) do
      visit root_url
      select values[0], from: "language_preference_locale"
      find("form[action='/language_preference'] button[type=submit]").click
      fill_in "email", with: @user.email
      fill_in "password", with: ChatAccountFixtures::PASSWORD
      click_on values[1]
      visit sources_url
      assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
      assert_selector "##{ActionView::RecordIdentifier.dom_id(text, :source_row)}"
      assert_no_selector "##{ActionView::RecordIdentifier.dom_id(other_account_source, :source_row)}"
    end
  end
  text.mark_indexed!
  Capybara.using_session(:english_sources) do
    assert_selector "##{ActionView::RecordIdentifier.dom_id(text, :source_row)}", text: "Indexed"
  end
  Capybara.using_session(:french_sources) do
    assert_selector "##{ActionView::RecordIdentifier.dom_id(text, :source_row)}", text: "Indexé"
  end
  target = ActionView::RecordIdentifier.dom_id(text, :source_row)
  text.destroy!
  remaining = SourceRow.counts_for(@first).fetch(:total)
  [ :english_sources, :french_sources ].each do |name|
    Capybara.using_session(name) do
      assert_no_selector "##{target}"
      assert_selector "#source_count_all", text: remaining.to_s
    end
  end
ensure
  Capybara.reset_sessions!
end
```

- [ ] Add the 375px/theme overflow assertion around the selector, source list, and composer. Use CDP device metrics where the local Chromium window has a minimum width:

```ruby
test "French header and workflows fit 375px in both themes" do
  visit root_url
  select "English", from: "language_preference_locale"
  find("form[action='/language_preference'] button[type=submit]").send_keys(:enter)
  fill_in "email", with: @user.email
  fill_in "password", with: ChatAccountFixtures::PASSWORD
  click_on "Sign in"
  page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
    width: 375, height: 900, deviceScaleFactor: 1, mobile: false)
  [ new_chat_url(account_id: @second.id), sources_url ].each do |url|
    visit url
    select "Français", from: "language_preference_locale"
    find("form[action='/language_preference'] button[type=submit]").send_keys(:enter)
    assert_selector "html[lang=fr]"
    [ false, true ].each do |dark|
      page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
      assert_selector "label[for=language_preference_locale]"
      refute page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
      assert_selector "select#language_preference_locale"
    end
  end
ensure
  page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
end
```

Inspect visible focus and French text wrapping, not just `scrollWidth`. Confirm that normal Send/Stop, real PDF selection, pasted links, source registration failures/reset/retry, account-switch confirmation, and MCP selection retain their safeguards in French as well as English. Reuse existing browser regression flows; do not add a parallel source or generation state machine.

- [ ] Run the new browser file RED for genuinely missing behavior. If a browser/driver is unavailable, report that blocker; do not convert it into a skipped "passing" feature check. Adjust only localized presentation/navigation bugs revealed by these tests, then run GREEN.
- [ ] Document the following exact user-facing behavior in `docs/internationalization.md`:

```markdown
# Internationalization

Nosia supports English and French. By default it uses the best supported
language in the browser's Accept-Language preferences, with English as the
fallback. Regional French/English preferences map to their base language.

The header's Language selector offers Automatic, Français, and English.
Explicit choices are remembered for one year in that browser, including before
sign-in. Automatic removes the override. Preferences are not account settings
and do not sync across browsers or devices. Switching reloads the current page;
save unfinished form work first. It does not stop background generation/indexing.

The interface language does not change user content, saved conversations,
system prompts, AI response language, or API contracts. Machine API responses
remain English. Unsupported upstream Lexxy dialogs and the Mission Control
Jobs interface remain as supplied. Static emergency pages show both languages.

## Adding or changing UI copy

Keep paired English/French feature files in config/locales, under nosia keys.
Use Rails t/l/number helpers, numeric count for plurals, and whole-sentence
interpolation. French copy uses vous. Model validation text uses symbol codes
and normal Rails error/attribute keys. Keep machine identifiers unchanged.

Supply Stimulus messages through server-rendered data values. Do not maintain a
second JavaScript catalog or use English default strings to conceal missing
translations. Interpolate untrusted values as escaped data or text nodes.

Translated Turbo Streams append the locale after the unchanged resource/filter
parts. Publish each event through LocalizedBroadcasting; do not add an unqualified
compatibility subscription. Background renderers use explicit record/account
locals, not Current. Include I18n.locale in translated cache keys.

Run the internationalization tests, localized page/cache/broadcast tests, and
the localization system test before shipping copy changes. Catalog parity does
not replace a human review of French or a narrow-screen/keyboard check.
```

Link this document from `docs/README.md`. In `docs/DEBT.md` mark the English/French UI debt resolved only after verification; explicitly retain additional languages/RTL and unsupported upstream UI as outside this release. Do not claim that all languages or third-party internals are translated.

- [ ] Review the public Ruby interfaces' YARD comments in `LanguagePreference` and `LocalizedBroadcasting`. Check route/action scope, cookie/redirect/CSRF safety, output escaping, API locale pinning, authorization, request restoration, and the lack of database/AI-content changes. Use `rails-code-review` plus security review for the final self-review; do not fix unrelated architecture or route conventions.
- [ ] Run the final focused suite, then full project checks, sequentially:

```sh
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test test/models/language_preference_test.rb test/controllers/localization_test.rb test/controllers/language_preferences_controller_test.rb test/internationalization test/integration/localized_pages_test.rb test/integration/localized_cache_test.rb test/integration/localized_broadcasts_test.rb test/helpers/mcp_catalog_helper_test.rb
bundle exec ruby test/packaging/bilingual_error_pages_test.rb
RAILS_ENV=test bin/rails tailwindcss:build
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bin/rails test
AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec ruby -rselenium-webdriver -e 'Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"; load "bin/rails"' -- test test/system/localization_test.rb test/system/chat_account_selection_test.rb test/system/chat_composer_ui_test.rb test/system/sources_dropzone_test.rb
RUBOCOP_TARGET_RUBY_VERSION=4.0 bin/rubocop
bin/brakeman --no-pager
bin/importmap audit
git diff --check
```

Expected: no feature failures/errors, no translation markers, no new warnings, and unchanged API/account/content semantics. Report baseline full-suite failures or unavailable network audits explicitly with command/output; do not claim those checks passed. Keep screenshots/logs under `/tmp/opencode` or existing ignored screenshot locations, never include credentials.

- [ ] Commit the final test/docs/intentional presentation adjustments with `docs(i18n): document and verify bilingual interface behavior`. Do not merge, push, open a PR, or discard the worktree unless the user chooses that next step.

## Spec-to-plan coverage and planning self-review

| Approved requirement | Tasks |
| --- | --- |
| French/English only, browser weighting/regions and English fallback | 1, 2, 12 |
| Browser override/reset, pre-sign-in, persistent signed cookie, safe CSRF/redirects | 3, 13 |
| Entire Nosia-owned UI and accessible labels, French vous | 4–10, 12 |
| No URL, schema, stored-content, prompt, AI-language, or API-contract changes | 1–3, 5, 7–9, 11, 13 |
| Standard locale data, dates/numbers/plurals; unchanged precision/calculations | 1, 6, 7, 10, 12 |
| Server-supplied JavaScript feedback, no second catalog | 5, 6 |
| Locale-qualified chat/source/token/automatic/background events | 11, 13 |
| Cache isolation, Content-Language/Vary, request/exception restoration | 2, 10, 11, 13 |
| Unchanged external metadata/upstream internals; cached catalog presentation only | 7–9, 13 |
| Bilingual static recovery without Rails/JavaScript | 12 |
| Minitest/fixtures, account isolation, browser/mobile/keyboard/theme checks | Every task, especially 11–13 |
| Documentation and code/security review | 13 |

Planning self-review must check the final file, not just this table: no unspecified implementation steps, undefined test fixtures/methods, contradictory task dependencies, or unpaired catalog keys. The execution record must distinguish RED, GREEN, baseline failures, and checks not run. This plan itself is not implementation evidence.

**Planning review completed:** All spec sections map to tasks above. The review
corrected post-commit SSE header mutation, fixture/association names, staged
translation dependencies, safe return-path validation, and the JSON-manifest
audit boundary. The placeholder/checkbox/fence scan is clear, and all 18 complete
Ruby class/module examples pass syntax parsing. Application code, tests, and
dependencies remain unchanged; application verification belongs to execution.
