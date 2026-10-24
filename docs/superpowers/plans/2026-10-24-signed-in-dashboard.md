# Signed-in Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved balanced dashboard at authenticated `/`, with an inline composer, cross-account usage, eight tool shortcuts, and five private recent conversations.

**Architecture:** Reuse the existing chat composer and creation workflow. A read-only `TokenUsage::Report` owns authorized aggregate reads; small ERB partials render the dashboard and shared 30-day summary. Global reporting gains the same membership scope while explicit account reports preserve their current behavior.

**Tech Stack:** Actual checkout: Ruby 4, Rails 8.0, PostgreSQL/pgvector, ERB, Turbo, Stimulus/importmap, Lexxy, Tailwind 4, Minitest/fixtures, Selenium/Chrome. No schema, dependency, authentication, or ID-format migration.

---

## Scope, workspace, and execution rules

- Approved specification: `docs/superpowers/specs/2026-10-24-signed-in-dashboard-design.md`; written-spec approval: **“Go”**.
- Branch: `feat/signed-in-dashboard`.
- Worktree: `/home/cbldev/gitd/dilolabs/nosia/.worktrees/signed-in-dashboard`.
- Application base: `68b15a1`. The original worktree's unrelated changes are not copied, staged, reset, or overwritten.
- Planning check: `bundle check` passed. No application code or databases were changed, and no test baseline is claimed during planning. Task 0 establishes it before implementation.
- This is one dashboard/reporting feature over existing workflows, not a source-ingestion, authentication, or billing redesign.
- Perform **test → run intended failure → minimal implementation → rerun → commit** for each behavior. Environment failures do not count as the required red test. Run database-sharing commands sequentially.
- Keep the uploader's existing controller, retry/removal state, and account guards. Replace its large standalone presentation with a compact source-upload button/list **inside the composer panel**. This implements removal of the oversized area without deleting the many existing upload safety tests.
- Do not add HTTP freshness caching around the composer/CSRF form, new polling, a global account switcher, provider calls on GET, or shared caching of private dashboard content.
- Each Ruby public interface added below needs the shown YARD contract; controller/private helpers do not need noisy comments explaining obvious operations.

## File map and responsibility boundaries

| Paths | Responsibility |
| --- | --- |
| `app/models/token_usage/report.rb` | Membership-restricted period/lifetime aggregates and detailed report data; read-only. |
| `app/models/user.rb` | Private ordered recent-conversation relation. |
| `app/controllers/dashboards_controller.rb` | Select composer/default context and assemble authorized dashboard data. |
| `app/controllers/token_usages_controller.rb` | Preserve explicit account branch; add aggregate global branch. |
| `app/helpers/token_usages_helper.rb` | Numeric SVG geometry only. |
| `app/helpers/dashboards_helper.rb` | Dashboard layout predicate and fixed destination metadata. |
| `app/views/token_usages/_overview.html.erb` | Shared 30-day totals, trend, accessible data table, lifetime footer. |
| `app/views/token_usages/_summary.html.erb`, `_summary_content.html.erb`, `show.html.erb` | Extract existing lifetime markup without changing scoped behavior; render aggregate content uncached. |
| `app/views/dashboards/show.html.erb`, `_composer.html.erb`, `_source_upload.html.erb`, `_shortcuts.html.erb`, `_recent.html.erb` | Balanced shell, existing composer, compact existing upload flow, eight labeled links, bounded private recents. |
| `app/views/layouts/application.html.erb` | Suppress right conversation sidebar/drawer on dashboard only. |
| `app/assets/stylesheets/nosia/dashboard.css`, `app/assets/tailwind/application.css` | Dashboard/report-overview responsive styling and import. |
| `config/locales/en.nosia_dashboard.yml`, `fr.nosia_dashboard.yml` | Complete paired dashboard copy; reuse existing token-unit plurals. |
| `test/support/dashboard_fixtures.rb`, `test/support/fixtures/dashboard/token_usages.yml` | Opt-in reporting fixture ledger layered on existing account-experience fixtures. |
| `test/models/token_usage/report_test.rb`, `test/models/dashboard_recents_test.rb` | Aggregation/date/tenant/performance and private-recent contracts. |
| `test/helpers/token_usages_helper_test.rb`, `test/controllers/dashboards_controller_test.rb`, `test/controllers/global_token_usage_test.rb` | Geometry, server-rendered dashboard, isolation, empty states, consistent reports. |
| `test/controllers/accounts/scoped_tokens_usage_test.rb` | Replace only the intentionally obsolete global-first-account expectations. |
| `test/system/dashboard_test.rb` | Real browser layout, navigation, sending, theme/language, keyboard and visibility checks. |
| `docs/dashboard.md`, `docs/account-experience.md`, `docs/README.md`, `docs/DIAGRAMS.md` | User scope/navigation contracts, corrected global report description, diagram, and verification procedure. |

## Task 0: Establish a safe execution baseline

- [x] **Step 1: Verify workspace and available tooling.**

```bash
git status --short
bundle check
ruby --version
command -v chromium
command -v chromedriver
```

Expect only this plan/spec documentation change and installed dependencies. Do not install browser/system packages or update the lockfile for this task. The worktree uses PostgreSQL; do not apply SQLite database-copy instructions.

- [x] **Step 2: Prepare a feature-specific test database, not shared `nosia_test`.**

The original ignored `.env` is loaded without copying or displaying its secrets. Set the explicit test environment/database/dummy provider key on **every** Rails command. Never run a development reset or background worker. Build the existing ignored Tailwind output before rendering tests: a fresh worktree does not contain `app/assets/builds/tailwind.css`. The user approved this setup correction after the first focused attempt exposed missing-asset errors; no application-source change is needed.

```bash
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails db:prepare
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails tailwindcss:build
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test test/controllers/chat_account_selection_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/integration/token_usages_test.rb test/integration/chat_composer_ui_test.rb test/internationalization/catalogs_test.rb
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails test > /tmp/opencode/signed-in-dashboard-baseline.log 2>&1
```

Expect database preparation and focused regressions to succeed. Record the full-suite exit, counts, and exact failures. Historical documentation mentions an unrelated `Chat::RequestOptionsTest` error, but that is not fresh evidence or automatic permission to ignore it. If any baseline fails, stop and obtain an explicit decision before application changes.

**Execution baseline and explicit user acceptance:** On 2026-10-24, database preparation, existing Tailwind build, and tooling checks passed. After resolving missing generated CSS and disk exhaustion, the fresh focused run passed with 54 runs / 9,726 assertions / no failures, errors, or skips (seed 64245, exit 0). The full run had 1,042 runs / 18,215 assertions / 0 failures / 1 error / 0 skips (seed 38278, exit 1). Its sole error is the preexisting `Chat::RequestOptionsTest#test_completion_replaces_augmented_instructions_and_keeps_environment_option_defaults`: missing `augmented_context` on its test double, at `app/models/chat/completionable.rb:39`, called from `test/models/chat/request_options_test.rb:32` (test begins at line 29). The user explicitly answered **“Proceed with the dashboard”** when asked to leave this test unchanged and accept that exact baseline. This is not a passing full suite; no additional failure/error is accepted. Complete current evidence is `/tmp/opencode/signed-in-dashboard-baseline{,-focused,-audit,-error-index}.log`; earlier missing-asset and disk-full attempts are retained separately.

For subsequent commands, `rails_test` below denotes this **exact shell function**, defined once in the execution shell; it does not go in the repository:

```bash
rails_test() {
  RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bin/rails "$@"
}
```

## Task 1: Add opt-in fixtures and the lightweight reporting model

**Create:** `test/support/dashboard_fixtures.rb`, `test/support/fixtures/dashboard/token_usages.yml`, `test/models/token_usage/report_test.rb`, `app/models/token_usage/report.rb`.

- [x] **Step 1: Add the opt-in fixture support and tests.** Do not change global fixtures or existing account fixture files. Reset the fixture cache before loading the replacement ledger, because the parent loader has already loaded a fixture set named `token_usages`.

```ruby
# test/support/dashboard_fixtures.rb
require_relative "account_experience_fixtures"

module DashboardFixtures
  extend ActiveSupport::Concern
  include AccountExperienceFixtures

  included do
    setup do
      @report_time = Time.utc(2026, 10, 24, 12)
      ActiveRecord::FixtureSet.reset_cache
      @dashboard_sets = ActiveRecord::FixtureSet.create_fixtures(
        Rails.root.join("test/support/fixtures/dashboard").to_s, [ "token_usages" ]
      ).index_by(&:name)
      @first.update_columns(input_tokens_count: 17, output_tokens_count: 3)
      @second.update_columns(input_tokens_count: 942, output_tokens_count: 103)
      clear_enqueued_jobs
    end
  end

  def dashboard_usage(name)
    @dashboard_sets.fetch("token_usages").fixtures.fetch(name.to_s).find
  end
end
```

```yaml
# test/support/fixtures/dashboard/token_usages.yml
dashboard_first:
  account: overview_first
  kind: completion
  model_id: overview-test-model
  input_tokens: 10
  output_tokens: 2
  created_at: 2026-10-24 08:00:00
dashboard_second_member:
  account: overview_second
  chat: overview_member_chat
  kind: completion
  model_id: overview-test-model
  input_tokens: 900
  output_tokens: 100
  created_at: 2026-10-24 09:00:00
dashboard_indexing:
  account: overview_second
  kind: embedding
  input_tokens: 40
  output_tokens: 0
  created_at: 2026-10-20 10:00:00
dashboard_skill:
  account: overview_second
  kind: agent_skill
  model_id: overview-test-model
  input_tokens: 2
  output_tokens: 3
  created_at: 2026-10-23 10:00:00
dashboard_old:
  account: overview_first
  kind: completion
  model_id: overview-test-model
  input_tokens: 7
  output_tokens: 1
  created_at: 2026-09-24 23:59:59
dashboard_outsider:
  account: overview_foreign
  kind: completion
  model_id: private-model
  input_tokens: 9000
  output_tokens: 900
  created_at: 2026-10-24 09:00:00
```

```ruby
# test/models/token_usage/report_test.rb
require "test_helper"
require_relative "../../support/dashboard_fixtures"

class TokenUsage::ReportTest < ActiveSupport::TestCase
  include DashboardFixtures

  test "period includes member activity and chatless indexing but excludes outsiders and old events" do
    report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
    assert_equal({ input: 952, output: 105, total: 1057 }, report.period_totals)
    assert_equal({ input: 959, output: 106, total: 1065 }, report.lifetime_totals)
    assert_equal 30, report.daily_totals.length
    assert_equal 1057, report.daily_totals.values.sum
    assert_equal 0, report.daily_totals.fetch(Date.new(2026, 9, 25))
  end

  test "calendar window includes both endpoints but no future event" do
    old = dashboard_usage(:dashboard_old)
    old.update_columns(created_at: Time.utc(2026, 9, 25))
    assert_equal 1065, TokenUsage::Report.new(accounts: @user.accounts, now: @report_time).period_totals[:total]
    old.update_columns(created_at: @report_time)
    assert_equal 1065, TokenUsage::Report.new(accounts: @user.accounts, now: @report_time).period_totals[:total]
    old.update_columns(created_at: @report_time + 1.second)
    assert_equal 1057, TokenUsage::Report.new(accounts: @user.accounts, now: @report_time).period_totals[:total]
  end

  test "local calendar boundaries and buckets use the captured application zone" do
    Time.use_zone("Europe/Paris") do
      now = Time.zone.local(2026, 10, 26, 12)
      old = dashboard_usage(:dashboard_old)
      old.update_columns(created_at: Time.zone.local(2026, 9, 27))
      dashboard_usage(:dashboard_indexing).update_columns(created_at: Time.zone.local(2026, 10, 25, 0, 30))
      report = TokenUsage::Report.new(accounts: @user.accounts, now: now)
      assert_equal Time.zone.local(2026, 9, 27), report.starts_at
      assert_equal 8, report.daily_totals.fetch(Date.new(2026, 9, 27))
      assert_equal 40, report.daily_totals.fetch(Date.new(2026, 10, 25))
      assert_equal 1065, report.period_totals[:total]
      old.update_columns(created_at: report.starts_at - Rational(1, 1_000_000))
      assert_equal 1057, TokenUsage::Report.new(accounts: @user.accounts, now: now).period_totals[:total]
    end
  end

  test "empty membership returns zero counters and thirty zero days" do
    report = TokenUsage::Report.new(accounts: @user.accounts.none, now: @report_time)
    assert_equal({ input: 0, output: 0, total: 0 }, report.period_totals)
    assert_equal({ input: 0, output: 0, total: 0 }, report.lifetime_totals)
    assert_equal [ 0 ], report.daily_totals.values.uniq
  end

  test "aggregate reads restore an ambient tenant and do not narrow to it" do
    ActsAsTenant.with_tenant(@first) do
      report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
      assert_equal 1057, report.period_totals[:total]
      assert_equal @first, ActsAsTenant.current_tenant
    end
  end

  test "membership subquery does not multiply counters through repeated joins" do
    accounts = @user.accounts.joins(:account_users)
    report = TokenUsage::Report.new(accounts: accounts, now: @report_time)
    assert_equal 1065, report.lifetime_totals[:total]
    assert_equal 1057, report.period_totals[:total]
  end

  test "lightweight reads use bounded aggregate queries instead of loading accounts or events" do
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
        report.period_totals
        report.daily_totals
        report.lifetime_totals
      end
    end
    assert_operator queries.length, :<=, 3
    refute queries.any? { |sql| sql.match?(/SELECT\s+"(?:accounts|token_usages)"\.\*/i) }
  end
end
```

- [x] **Step 2: Run the new model tests.**

```bash
rails_test test test/models/token_usage/report_test.rb
```

Expect an undefined `TokenUsage::Report` failure, not a fixture, connection, or encryption error.

- [x] **Step 3: Add the minimal read-only reporting model.** PostgreSQL stores Rails timestamps as UTC without time zone in this checkout. Quote the captured IANA zone, convert UTC to that zone before grouping, and materialize every tenant-relaxed query inside its block.

```ruby
# app/models/token_usage/report.rb
# Read-only token statistics for an already-authorized set of accounts.
class TokenUsage::Report
  # @return [ActiveSupport::TimeWithZone] Inclusive local window endpoints
  attr_reader :starts_at, :ends_at

  # @param accounts [ActiveRecord::Relation<Account>] Membership-authorized accounts
  # @param now [Time, ActiveSupport::TimeWithZone] Reference time, inclusive
  def initialize(accounts:, now: Time.current)
    @accounts = accounts
    @zone = Time.zone
    @ends_at = now.in_time_zone(@zone)
    @starts_at = (@ends_at.to_date - 29).in_time_zone(@zone)
  end

  # @return [Hash{Symbol => Integer}] Input, output, and total in the 30-day window
  def period_totals
    @period_totals ||= totals(period_rows.sum { |row| row[1] }, period_rows.sum { |row| row[2] })
  end

  # @return [Hash{Symbol => Integer}] Existing lifetime account counters, not a recount
  def lifetime_totals
    @lifetime_totals ||= begin
      accounts = Account.where(id: account_ids)
      totals(accounts.sum(:input_tokens_count), accounts.sum(:output_tokens_count))
    end
  end

  # @return [Hash{Date => Integer}] Thirty chronological local dates, zero-filled
  def daily_totals
    @daily_totals ||= begin
      measured = period_rows.to_h { |date, input, output| [ date.to_date, input + output ] }
      (@starts_at.to_date..@ends_at.to_date).to_h { |date| [ date, measured.fetch(date, 0) ] }
    end
  end

  private
    def totals(input, output)
      { input: input.to_i, output: output.to_i, total: input.to_i + output.to_i }
    end

    def period_rows
      @period_rows ||= read_usage do |usage|
        date = local_date_expression
        usage.where(created_at: starts_at..ends_at).group(date).pluck(date,
          Arel.sql("COALESCE(SUM(token_usages.input_tokens), 0)"),
          Arel.sql("COALESCE(SUM(token_usages.output_tokens), 0)"))
      end
    end

    def local_date_expression
      zone = TokenUsage.connection.quote(@zone.tzinfo.identifier)
      Arel.sql("DATE((token_usages.created_at AT TIME ZONE 'UTC') AT TIME ZONE #{zone})")
    end

    def read_usage
      ActsAsTenant.without_tenant do
        yield TokenUsage.where(account_id: account_ids)
      end
    end

    def account_ids
      @accounts.reorder(nil).reselect(:id).distinct
    end
end
```

- [x] **Step 4: Rerun the model tests and existing account model tests.**

```bash
rails_test test test/models/token_usage/report_test.rb test/models/account_overview_test.rb
```

Expect all new period/lifetime tests to pass. The actual ledger has NOT NULL input/output columns, so fixtures use zero, not an invalid null. Defensive aggregate coercion does not authorize a schema change.

- [x] **Step 5: Commit these explicit files.**

```bash
git add app/models/token_usage/report.rb test/models/token_usage/report_test.rb test/support/dashboard_fixtures.rb test/support/fixtures/dashboard/token_usages.yml
git commit -m "feat(usage): add authorized cross-account token report"
```

**Task 1 execution:** Implemented in `8fa6855`. RED: 7 undefined-report errors before application code, exit 1. GREEN: new report and existing account overview tests, 17 runs / 72 assertions / no failures/errors, exit 0. Changed Ruby lint and whitespace passed. Independent spec and quality reviews approved. Replaced the unsupported test shorthand `1.microsecond` with an exact Rational; the initial attempt is retained. Logs: `/tmp/opencode/dashboard-task1-{red,green,green-initial}.log`. Quality review suggested nonblocking cached-counter/ledger divergence coverage; Task 2 adds it below.

## Task 2: Add detailed aggregate reporting and private recent-chat selection

**Modify:** `app/models/token_usage/report.rb`, `app/models/user.rb`, `test/models/token_usage/report_test.rb`.
**Create:** `test/models/dashboard_recents_test.rb`.

- [x] **Step 1: Append these public-behavior tests to `TokenUsage::ReportTest` and create the recents tests.**

```ruby
test "detailed breakdowns use the same authorized lifetime ledger and current estimation rules" do
  report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
  assert_equal({ "completion" => 1020, "embedding" => 40, "agent_skill" => 5 }, report.tokens_by_kind)
  assert_equal({ "overview-test-model" => 1025 }, report.tokens_by_model)
  summary = report.green_summary
  assert_equal [ "overview-test-model" ], summary[:models].map { |entry| entry[:model_id] }
  expected = GreenIt.energy_kwh(tokens: 1025, model_id: "overview-test-model", kind: :completion)[:kwh] +
    GreenIt.energy_kwh(tokens: 40, model_id: nil, kind: :embedding)[:kwh]
  assert_in_delta expected, summary[:kwh], 1e-12
  assert_in_delta GreenIt.co2e_g(kwh: expected), summary[:co2e_g], 1e-12
  assert summary[:fallback_used]
end

test "new reports reflect revoked memberships and empty detailed summaries" do
  experience(:account_users, :overview_owner_second).destroy!
  report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
  assert_equal 12, report.period_totals[:total]
  assert_equal 20, report.lifetime_totals[:total]
  assert_equal({ "completion" => 20 }, report.tokens_by_kind)
  empty = TokenUsage::Report.new(accounts: @user.accounts.none, now: @report_time)
  assert_empty empty.tokens_by_model
  assert_equal 0, empty.green_summary[:kwh]
end

test "lifetime uses cached counters even when they differ from the ledger" do
  @first.update_columns(input_tokens_count: 100, output_tokens_count: 20)
  @second.update_columns(input_tokens_count: 200, output_tokens_count: 30)
  report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
  assert_equal({ input: 300, output: 50, total: 350 }, report.lifetime_totals)
  assert_equal({ input: 952, output: 105, total: 1057 }, report.period_totals)
  assert_equal 1057, report.daily_totals.values.sum
end
```

```ruby
# test/models/dashboard_recents_test.rb
require "test_helper"
require_relative "../support/account_experience_fixtures"

class DashboardRecentsTest < ActiveSupport::TestCase
  include AccountExperienceFixtures

  test "recents select only personal root chats in current memberships in stable activity order" do
    first = experience(:chats, :overview_first_chat)
    first.update_columns(updated_at: Time.utc(2026, 1, 10))
    expected = [ first ] + 4.times.map { |index| experience(:chats, "overview_second_chat_#{27 - index}") }
    rows = @user.recent_conversations.limit(5).to_a
    assert_equal expected.map(&:id), rows.map(&:id)
    assert rows.all? { |chat| chat.association(:account).loaded? }
    refute_includes rows, experience(:chats, :overview_member_chat)
    refute_includes rows, experience(:chats, :overview_child_chat)
    experience(:account_users, :overview_owner_second).destroy!
    assert_equal [ first.id ], @user.recent_conversations.limit(5).pluck(:id)
  end

  test "equal activity timestamps use descending IDs and no-account users have no recents" do
    first = experience(:chats, :overview_first_chat)
    second = experience(:chats, :overview_second_chat_27)
    [ first, second ].each { |chat| chat.update_columns(updated_at: Time.utc(2026, 2, 1)) }
    assert_equal [ first.id, second.id ].sort.reverse, @user.recent_conversations.limit(2).pluck(:id)
    assert_empty experience(:users, :overview_no_account).recent_conversations
  end
end
```

- [x] **Step 2: Run the new tests before adding the methods.**

```bash
rails_test test test/models/token_usage/report_test.rb test/models/dashboard_recents_test.rb
```

Expect failures for missing `tokens_by_kind`, `tokens_by_model`, `green_summary`, and `recent_conversations`.

- [x] **Step 3: Add these public methods before `private` in `TokenUsage::Report`.** Preserve the existing top-five-model/embedding estimation rules; do not fix unrelated estimator limitations in this feature.

```ruby
# @return [Hash{String => Integer}] Lifetime tokens grouped by existing usage kind
def tokens_by_kind
  @tokens_by_kind ||= read_usage { |usage| usage.group(:kind).sum(total_expression) }
end

# @return [Hash{String => Integer}] Lifetime tokens grouped by reported model string
def tokens_by_model
  @tokens_by_model ||= read_usage { |usage| usage.where.not(model_id: nil).group(:model_id).sum(total_expression) }
end

# @return [Hash] Existing top-five model/embedding energy estimate and fallback flags
def green_summary
  @green_summary ||= begin
    models = tokens_by_model.sort_by { |model, tokens| [ -tokens, model ] }.first(5).map do |model_id, tokens|
      impact = GreenIt.energy_kwh(tokens: tokens, model_id: model_id, kind: :completion)
      { model_id: model_id, tokens: tokens, kwh: impact[:kwh], fallback: impact[:fallback] }
    end
    embedding = GreenIt.energy_kwh(tokens: tokens_by_kind.fetch("embedding", 0), model_id: nil, kind: :embedding)
    kwh = models.sum { |entry| entry[:kwh] } + embedding[:kwh]
    { models: models, kwh: kwh, co2e_g: GreenIt.co2e_g(kwh: kwh), fallback_used: models.any? { |entry| entry[:fallback] } }
  end
end
```

Add this private method before `read_usage`:

```ruby
def total_expression
  Arel.sql("COALESCE(token_usages.input_tokens, 0) + COALESCE(token_usages.output_tokens, 0)")
end
```

Add this method to `User` before `first_account`:

```ruby
# @return [ActiveRecord::Relation<Chat>] Personal root chats in current memberships, newest first
def recent_conversations
  chats.root.where(account: accounts).includes(:account).order(updated_at: :desc, id: :desc)
end
```

- [x] **Step 4: Rerun the domain tests.**

```bash
rails_test test test/models/token_usage/report_test.rb test/models/dashboard_recents_test.rb test/models/account_overview_test.rb
```

Expect correct sums and empty/revoked/ordered/private behavior, with no provider requests.

- [x] **Step 5: Commit domain changes.**

```bash
git add app/models/token_usage/report.rb app/models/user.rb test/models/token_usage/report_test.rb test/models/dashboard_recents_test.rb
git commit -m "feat(dashboard): add private recents and detailed usage aggregates"
```

**Task 2 execution:** Implemented in `b8c23fc`. RED: 12 runs / 28 assertions / four expected missing-method errors, seed 49252, exit 1. GREEN: 22 runs / 97 assertions / no failures, errors, or skips, seed 59503, exit 0. Changed Ruby lint and whitespace passed; independent spec and quality reviews approved. Logs: `/tmp/opencode/dashboard-task2-{red,green}.log`. Quality review noted optional extra coverage for the preserved five-model cutoff; no functional or blocking issue was found.

## Task 3: Build the shared accessible usage overview

**Create:** `app/helpers/token_usages_helper.rb`, `app/views/token_usages/_overview.html.erb`, `app/assets/stylesheets/nosia/dashboard.css`, `config/locales/en.nosia_dashboard.yml`, `config/locales/fr.nosia_dashboard.yml`, `test/helpers/token_usages_helper_test.rb`.
**Modify:** `app/assets/tailwind/application.css`.

- [x] **Step 1: Write geometry and rendered-component tests.**

```ruby
# test/helpers/token_usages_helper_test.rb
require "test_helper"
require_relative "../support/dashboard_fixtures"

class TokenUsagesHelperTest < ActionView::TestCase
  include TokenUsagesHelper
  include DashboardFixtures

  test "sparkline points are finite numeric pairs including a flat zero series" do
    assert_equal "", usage_trend_points({})
    assert_equal "0.0,36.0 300.0,4.0", usage_trend_points({ Date.new(2026, 10, 23) => 0, Date.new(2026, 10, 24) => 10 })
    report = TokenUsage::Report.new(accounts: @user.accounts.none, now: @report_time)
    points = usage_trend_points(report.daily_totals).split(" ")
    assert_equal 30, points.length
    assert points.all? { |point| point.match?(/\A\d+\.\d,36\.0\z/) }
  end

  test "overview exposes the same localized numbers in text and its daily data table" do
    report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
    %i[en fr].each do |locale|
      html = I18n.with_locale(locale) do
        ApplicationController.render(partial: "token_usages/overview", locals: {
          report: report, title_id: "test-usage", show_report_link: true
        })
      end
      fragment = Nokogiri::HTML.fragment(html)
      assert_select fragment, "[data-period-total][data-value='1057']"
      assert_select fragment, "[data-period-input][data-value='952']"
      assert_select fragment, "[data-period-output][data-value='105']"
      assert_select fragment, "[data-lifetime-total][data-value='1065']"
      assert_select fragment, "details table tbody tr[data-usage-day]", count: 30
      assert_select fragment, "svg[role='img'][aria-labelledby='test-usage-trend-title test-usage-trend-description']"
      assert_select fragment, "a[href='#{token_usage_path}']"
      fragment.css("dl > div").each do |group|
        assert_equal %w[dt dd], group.element_children.map(&:name)
      end
      values = fragment.css("[data-usage-day] td").map { |cell| cell["data-value"].to_i }
      assert_equal report.period_totals[:total], values.sum
      refute_match(/translation missing|missing translation/i, html)
    end
  end
end
```

- [x] **Step 2: Run and observe the missing helper/component failure.**

```bash
rails_test test test/helpers/token_usages_helper_test.rb
```

- [x] **Step 3: Add numeric-only geometry and the shared overview partial.**

```ruby
# app/helpers/token_usages_helper.rb
module TokenUsagesHelper
  # @param daily_totals [Hash{Date => Integer}] Ordered daily token totals
  # @return [String] Numeric SVG coordinate pairs, never user-authored markup
  def usage_trend_points(daily_totals)
    values = daily_totals.values
    maximum = [ values.max.to_f, 1.0 ].max
    denominator = [ values.length - 1, 1 ].max
    values.each_with_index.map do |value, index|
      format("%.1f,%.1f", index * 300.0 / denominator, 36.0 - value.to_f / maximum * 32.0)
    end.join(" ")
  end
end
```

```erb
<%# app/views/token_usages/_overview.html.erb %>
<%# locals: (report:, title_id:, show_report_link: true) %>
<section class="n-dashboard-panel n-usage-overview" aria-labelledby="<%= title_id %>">
  <div class="n-dashboard-section-heading">
    <h2 id="<%= title_id %>"><%= t("nosia.dashboard.usage_title") %></h2>
    <span class="n-dashboard-help"><%= t("nosia.usage.last_30_days") %></span>
  </div>
  <p class="n-dashboard-help"><%= t("nosia.dashboard.usage_scope") %></p>
  <p class="n-dashboard-help" data-usage-window>
    <%= l(report.starts_at.to_date, format: :short) %> – <%= l(report.ends_at.to_date, format: :short) %>
  </p>
  <dl>
    <div class="n-dashboard-primary-stat">
      <dt class="n-dashboard-help"><%= t("nosia.usage.total") %></dt>
      <dd class="n-dashboard-number" data-period-total data-value="<%= report.period_totals[:total] %>"><%= number_with_delimiter(report.period_totals[:total]) %></dd>
    </div>
  </dl>
  <dl class="n-dashboard-stat-pair">
      <div><dt class="n-dashboard-help"><%= t("nosia.usage.input") %></dt><dd data-period-input data-value="<%= report.period_totals[:input] %>"><%= number_with_delimiter(report.period_totals[:input]) %></dd></div>
      <div><dt class="n-dashboard-help"><%= t("nosia.usage.output") %></dt><dd data-period-output data-value="<%= report.period_totals[:output] %>"><%= number_with_delimiter(report.period_totals[:output]) %></dd></div>
  </dl>
  <p class="n-dashboard-help"><%= t("nosia.usage.token_unit", count: report.period_totals[:total]) %></p>
  <% if report.period_totals[:total].zero? %>
    <p class="n-dashboard-help"><%= t("nosia.usage.none") %></p>
  <% end %>
  <svg viewBox="0 0 300 40" class="n-dashboard-chart" preserveAspectRatio="none" role="img" aria-labelledby="<%= title_id %>-trend-title <%= title_id %>-trend-description">
    <title id="<%= title_id %>-trend-title"><%= t("nosia.dashboard.trend_title") %></title>
    <desc id="<%= title_id %>-trend-description"><%= t("nosia.dashboard.trend_description") %></desc>
    <polyline fill="none" stroke="currentColor" stroke-width="2" vector-effect="non-scaling-stroke" points="<%= usage_trend_points(report.daily_totals) %>"></polyline>
  </svg>
  <details class="n-dashboard-daily-data">
    <summary><%= t("nosia.dashboard.daily_data") %></summary>
    <table>
      <caption class="sr-only"><%= t("nosia.dashboard.daily_data") %></caption>
      <thead><tr><th scope="col"><%= t("nosia.dashboard.date") %></th><th scope="col"><%= t("nosia.usage.tokens_title") %></th></tr></thead>
      <tbody>
        <% report.daily_totals.each do |date, tokens| %>
          <tr data-usage-day="<%= date.iso8601 %>"><th scope="row"><%= l(date, format: :short) %></th><td data-value="<%= tokens %>"><%= number_with_delimiter(tokens) %></td></tr>
        <% end %>
      </tbody>
    </table>
  </details>
  <div class="n-dashboard-usage-footer">
    <p class="n-dashboard-help"><%= t("nosia.dashboard.lifetime") %>: <span data-lifetime-total data-value="<%= report.lifetime_totals[:total] %>"><%= number_with_delimiter(report.lifetime_totals[:total]) %></span></p>
    <% if show_report_link %>
      <%= link_to t("nosia.dashboard.usage_details"), token_usage_path, class: "n-dashboard-link" %>
    <% end %>
  </div>
</section>
```

- [x] **Step 4: Add the paired catalogs and focused styling.** These catalogs have no new plural branches; keep the existing `CatalogsTest::PLURAL_PATHS` unchanged.

```yaml
# config/locales/en.nosia_dashboard.yml
en:
  nosia:
    dashboard:
      title: "Your workspace"
      welcome: "Welcome back."
      introduction: "Start a conversation or pick up where you left off."
      composer_title: "What would you like to work on?"
      composer_help: "Choose an account, then ask anything."
      no_account: "Create or join an account to start a conversation."
      setup_account: "Set up an account"
      upload_sources: "Upload knowledge sources"
      upload_help: "Uploads are saved to the conversation’s selected account."
      usage_title: "Token usage"
      usage_scope: "All your accounts, including other members’ usage."
      usage_details: "Usage details"
      lifetime: "Lifetime"
      lifetime_details: "Lifetime breakdown and environmental impact"
      trend_title: "Daily token usage over the last 30 days"
      trend_description: "The daily token values are available in the expandable table below."
      daily_data: "Daily token values"
      date: "Date"
      shortcuts_title: "Explore your workspace"
      default_account: "Account: %{name}"
      your_accounts: "Your accounts"
      your_profile: "Your profile and security"
      your_tokens: "Your personal access tokens"
      prompts_scope: "Your existing system prompt directory"
      choose_account: "Set up an account to use this tool"
      recents_title: "Your recent conversations"
      recents_help: "Only your conversations, across accounts you can access."
      no_conversations: "Your conversations will appear here. Start one above."
      history_by_account: "Browse conversation history by account"
      destinations:
        accounts: "Accounts"
        sources: "Sources"
        usage: "Token usage"
        profile: "User profile"
        skills: "Agent skills"
        tokens: "API tokens"
        mcp: "MCP servers"
        prompts: "System prompts"
```

```yaml
# config/locales/fr.nosia_dashboard.yml
fr:
  nosia:
    dashboard:
      title: "Votre espace de travail"
      welcome: "Heureux de vous retrouver."
      introduction: "Commencez une conversation ou reprenez votre travail."
      composer_title: "Sur quoi souhaitez-vous travailler ?"
      composer_help: "Choisissez un compte, puis posez votre question."
      no_account: "Créez ou rejoignez un compte pour commencer une conversation."
      setup_account: "Configurer un compte"
      upload_sources: "Importer des sources de connaissances"
      upload_help: "Les fichiers sont enregistrés dans le compte sélectionné pour la conversation."
      usage_title: "Utilisation des jetons"
      usage_scope: "Tous vos comptes, y compris l’utilisation des autres membres."
      usage_details: "Détails de l’utilisation"
      lifetime: "Depuis le début"
      lifetime_details: "Répartition depuis le début et impact environnemental"
      trend_title: "Utilisation quotidienne des jetons sur les 30 derniers jours"
      trend_description: "Les valeurs quotidiennes sont disponibles dans le tableau dépliable ci-dessous."
      daily_data: "Valeurs quotidiennes des jetons"
      date: "Date"
      shortcuts_title: "Explorez votre espace de travail"
      default_account: "Compte : %{name}"
      your_accounts: "Vos comptes"
      your_profile: "Votre profil et votre sécurité"
      your_tokens: "Vos jetons d’accès personnels"
      prompts_scope: "Votre répertoire actuel de prompts système"
      choose_account: "Configurez un compte pour utiliser cet outil"
      recents_title: "Vos conversations récentes"
      recents_help: "Uniquement vos conversations, dans les comptes auxquels vous avez accès."
      no_conversations: "Vos conversations apparaîtront ici. Commencez-en une ci-dessus."
      history_by_account: "Parcourir l’historique des conversations par compte"
      destinations:
        accounts: "Comptes"
        sources: "Sources"
        usage: "Utilisation des jetons"
        profile: "Profil utilisateur"
        skills: "Compétences d’agent"
        tokens: "Jetons API"
        mcp: "Serveurs MCP"
        prompts: "Prompts système"
```

```css
/* app/assets/stylesheets/nosia/dashboard.css */
.n-dashboard {
  @apply mx-auto w-full min-w-0 max-w-7xl space-y-6 pb-24 lg:pb-8;
}
.n-dashboard-heading h1 {
  @apply text-3xl font-semibold tracking-tight text-neutral-900 dark:text-neutral-100;
}
.n-dashboard-top {
  @apply grid min-w-0 grid-cols-1 items-start gap-6 xl:grid-cols-[minmax(0,1.6fr)_minmax(20rem,1fr)];
}
.n-dashboard-panel {
  @apply min-w-0 rounded-xl border border-neutral-400 bg-white p-5 text-neutral-900 dark:border-neutral-500 dark:bg-neutral-800 dark:text-neutral-100 sm:p-6;
}
.n-dashboard-panel h2, .n-dashboard-section-heading h2 {
  @apply text-base font-semibold;
}
.n-dashboard-help {
  overflow-wrap: anywhere;
  @apply text-sm leading-relaxed text-neutral-600 dark:text-neutral-300;
}
.n-dashboard-section-heading, .n-dashboard-usage-footer {
  @apply flex min-w-0 flex-wrap items-center justify-between gap-3;
}
.n-dashboard-primary-stat { @apply mt-4; }
.n-dashboard-number { @apply text-4xl font-semibold tracking-tight tabular-nums; }
.n-dashboard-stat-pair { @apply mt-4 grid grid-cols-2 gap-4; }
.n-dashboard-stat-pair dd { @apply text-xl font-semibold tabular-nums; }
.n-dashboard-chart { @apply mt-4 h-12 w-full text-green-800 dark:text-green-300; }
.n-dashboard-daily-data { @apply mt-3 text-sm; }
.n-dashboard-daily-data summary {
  @apply min-h-11 cursor-pointer py-3 font-medium underline underline-offset-4 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:focus:outline-green-300;
}
.n-dashboard-daily-data table { @apply w-full text-left tabular-nums; }
.n-dashboard-daily-data th, .n-dashboard-daily-data td { @apply border-b border-neutral-300 py-2 dark:border-neutral-600; }
.n-dashboard-daily-data td { @apply text-right; }
.n-dashboard-usage-footer { @apply mt-3 border-t border-neutral-300 pt-3 dark:border-neutral-600; }
.n-dashboard-link {
  @apply inline-flex min-h-11 max-w-full items-center rounded-sm text-sm font-medium text-green-800 underline underline-offset-4 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:text-green-200 dark:focus:outline-green-300;
}
.n-dashboard-compose > .n-dashboard-help { @apply mb-4 mt-1; }
.n-dashboard-upload { @apply mt-4 space-y-2; }
.n-dashboard-shortcuts { @apply mt-3 grid min-w-0 grid-cols-2 gap-3 xl:grid-cols-4; }
.n-dashboard-shortcut {
  overflow-wrap: anywhere;
  @apply flex min-h-28 min-w-0 flex-col items-start gap-2 rounded-xl border border-neutral-400 bg-white p-4 text-sm text-neutral-900 hover:bg-green-50 focus:outline-2 focus:outline-offset-2 focus:outline-green-700 dark:border-neutral-500 dark:bg-neutral-800 dark:text-neutral-100 dark:hover:bg-green-950 dark:focus:outline-green-300;
}
.n-dashboard-shortcut svg { @apply h-5 w-5 text-green-800 dark:text-green-200; }
.n-dashboard-recent-list { @apply mt-3 list-none; }
.n-dashboard-recent-row { @apply flex min-w-0 flex-wrap items-center justify-between gap-3 border-b border-neutral-300 py-3 last:border-0 dark:border-neutral-600; }
.n-dashboard-recent-row > div { @apply min-w-0 flex-1 basis-48; }
.n-dashboard-recent-row a { overflow-wrap: anywhere; }
.n-global-usage { @apply mx-auto max-w-4xl space-y-6 pb-24 lg:pb-8; }
main:has(.n-dashboard), main:has(.n-global-usage) {
  min-width: 0;
  scroll-padding-block-end: 6rem;
}
@media (max-width: 360px) {
  .n-dashboard-shortcuts { grid-template-columns: minmax(0, 1fr); }
}
@media (prefers-reduced-motion: reduce) {
  .n-dashboard a, .n-dashboard button, .n-usage-overview summary { transition: none; }
}
```

Add this import after `accounts.css` in `app/assets/tailwind/application.css`:

```css
@import "../stylesheets/nosia/dashboard.css" layer(utilities);
```

- [x] **Step 5: Run component, catalog, and CSS checks.**

```bash
rails_test test test/helpers/token_usages_helper_test.rb test/internationalization/catalogs_test.rb
rails_test tailwindcss:build
```

Expect 30 table rows, matching numeric totals, finite zero-series geometry, paired translations, and a successful Tailwind build. Do not commit generated ignored CSS builds.

- [x] **Step 6: Commit the shared overview and its assets/tests.**

```bash
git add app/helpers/token_usages_helper.rb app/views/token_usages/_overview.html.erb app/assets/stylesheets/nosia/dashboard.css app/assets/tailwind/application.css config/locales/en.nosia_dashboard.yml config/locales/fr.nosia_dashboard.yml test/helpers/token_usages_helper_test.rb
git commit -m "feat(usage): add accessible thirty-day usage overview"
```

**Task 3 execution:** Implemented in `4ec1810`. Missing-helper RED preceded implementation; semantic RED (2 tests / 19 assertions / 1 failure, seed 61147) exposed invalid nested definition-list grouping and was corrected to two valid lists. GREEN component/catalog run: 6 tests / 9,614 assertions / no failures/errors, seed 39440, exit 0. Tailwind build, changed Ruby lint, and whitespace checks passed. Independent spec and quality reviews approved. Logs: `/tmp/opencode/dashboard-task3-{red,semantics-red,green,build,lint}.log`. Quality suggested stronger visible-number/date-mapping coverage; Task 4 adds those request assertions below.

## Task 4: Assemble the balanced root dashboard without changing chat workflows

**Create:** `test/controllers/dashboards_controller_test.rb`, `app/helpers/dashboards_helper.rb`, `app/views/dashboards/_composer.html.erb`, `_source_upload.html.erb`, `_shortcuts.html.erb`, `_recent.html.erb`.
**Modify:** `app/controllers/dashboards_controller.rb`, `app/views/dashboards/show.html.erb`, `app/views/layouts/application.html.erb`.

- [x] **Step 1: Add request regressions for the new page.**

```ruby
# test/controllers/dashboards_controller_test.rb
require "test_helper"
require_relative "../support/dashboard_fixtures"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
  end

  teardown { travel_back }

  test "authenticated root renders four panels and reads without creating records or jobs" do
    counts = [ Chat.count, Message.count, Document.count, Prompt.count, TokenUsage.count ]
    clear_enqueued_jobs
    assert_no_enqueued_jobs do
      get user_root_path
    end
    assert_response :success
    assert_select "[data-dashboard]", count: 1
    assert_select ".n-dashboard-compose #chat-form[action='#{chats_path}']", count: 1
    assert_select ".n-dashboard-shortcuts a", count: 8
    assert_select ".n-dashboard-recent-list [data-conversation-id]", count: 5
    assert_select "[data-period-total][data-value='1057']"
    assert_select "[data-lifetime-total][data-value='1065']"
    report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
    days = css_select("details table tbody tr[data-usage-day]")
    assert_equal report.daily_totals.keys, days.map { |row| Date.iso8601(row["data-usage-day"]) }
    assert_equal report.daily_totals, days.to_h { |row| [ Date.iso8601(row["data-usage-day"]), row.at_css("td")["data-value"].to_i ] }
    assert_select "#accordion-right-actions, #drawer-right", count: 0
    assert_equal counts, [ Chat.count, Message.count, Document.count, Prompt.count, TokenUsage.count ]
  end

  test "explicit composer selection preserves global totals and default-account tool destinations" do
    get user_root_path, params: { account_id: @second.id, model: "overview-test-model" }
    assert_response :success
    assert_select "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
    assert_select "input[name='chat[model]'][value='overview-test-model']"
    assert_select "[data-period-total][data-value='1057']"
    expected = { accounts: accounts_path, sources: sources_path, usage: token_usage_path,
      profile: profile_path, skills: agent_skills_path, tokens: api_tokens_path,
      mcp: mcp_servers_path, prompts: system_prompts_path }
    expected.each do |key, path|
      assert_select ".n-dashboard-shortcuts a[data-dashboard-destination='#{key}'][href='#{path}']", count: 1
    end
    %w[sources skills mcp].each do |key|
      assert_select "[data-dashboard-destination='#{key}']", text: /#{Regexp.escape(@first.name)}/
    end
    assert_equal @first, @user.first_account
    assert_select ".n-dashboard-compose [data-controller=dropzone][data-dropzone-account-id-value='#{@second.id}']"
    assert_select ".n-dashboard-compose [data-dropzone-target=container]", text: "Upload knowledge sources"
  end

  test "recent previews are personal escaped bounded and unchanged in storage" do
    chat = experience(:chats, :overview_first_chat)
    message = experience(:messages, :overview_first_question)
    content = "Résumé détaillé " * 30
    message.update_columns(content: content)
    chat.update_columns(updated_at: @report_time)
    @first.update_columns(name: "<script>Research</script>")
    get user_root_path
    assert_select "[data-conversation-id='#{chat.id}'] a", text: "#{content.strip[0, 119]}…"
    assert_select "main script", count: 0
    assert_select "[data-conversation-id='#{experience(:chats, :overview_member_chat).id}']", count: 0
    assert_select "[data-conversation-id='#{experience(:chats, :overview_foreign_chat).id}']", count: 0
    assert_select "[data-conversation-id='#{experience(:chats, :overview_child_chat).id}']", count: 0
    assert_equal content, message.reload.content
    experience(:account_users, :overview_owner_second).destroy!
    get user_root_path
    assert_select ".n-dashboard-recent-list [data-conversation-id]", count: 1
    assert_select "[data-period-total][data-value='12']"
  end

  test "no-account users can use the dashboard and all shortcut tiles remain actionable" do
    sign_in_overview(experience(:users, :overview_no_account))
    get user_root_path
    assert_response :success
    assert_select "[data-chat-no-account]", count: 1
    assert_select "lexxy-editor, [data-controller=dropzone]", count: 0
    assert_select "[data-period-total][data-value='0']"
    assert_select ".n-dashboard-shortcuts a", count: 8
    %w[sources skills mcp].each do |key|
      assert_select "[data-dashboard-destination='#{key}'][href='#{accounts_path}']"
    end
    assert_select "[data-dashboard-destination='profile'][href='#{profile_path}']"
    assert_select ".n-dashboard-recent-list [data-conversation-id]", count: 0
  end

  test "both locales render dashboard labels without missing translations" do
    %i[en fr].each do |locale|
      get user_root_path, headers: { "Accept-Language" => locale.to_s }
      assert_response :success
      assert_select "h1", text: I18n.t("nosia.dashboard.welcome", locale: locale)
      assert_select "a[data-dashboard-destination='mcp']", text: /#{Regexp.escape(I18n.t("nosia.dashboard.destinations.mcp", locale: locale))}/
      { "period-total" => 1057, "period-input" => 952, "period-output" => 105, "lifetime-total" => 1065 }.each do |attribute, value|
        assert_select "[data-#{attribute}]", text: ActiveSupport::NumberHelper.number_to_delimited(value, locale: locale)
      end
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "members with no usage or conversations still have a composer and useful empty panels" do
    user = experience(:users, :overview_no_account)
    experience(:account_users, :overview_member_second).update_columns(user_id: user.id, account_id: @empty.id)
    sign_in_overview(user)
    get user_root_path
    assert_response :success
    assert_select "lexxy-editor", count: 1
    assert_select "[data-chat-no-account]", count: 0
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='0']"
    assert_select ".n-dashboard-recent-list [data-conversation-id]", count: 0
    assert_select "p", text: I18n.t("nosia.dashboard.no_conversations")
    assert_select "[data-dashboard-destination='sources'][href='#{sources_path}']"
  end

  test "signed-out root and non-dashboard conversation drawers remain unchanged" do
    get new_chat_path
    assert_select "#accordion-right-actions, #drawer-right", count: 2
    delete logout_path
    get root_path
    assert_response :success
    assert_select "[data-dashboard]", count: 0
    assert_select "form[action='#{login_path}']", count: 1
  end
end
```

- [x] **Step 2: Run the new dashboard tests against the old page.**

```bash
rails_test test test/controllers/dashboards_controller_test.rb
```

Expect missing dashboard panels/shortcuts/aggregate assertions. Preserve existing access-rejection tests; a chart/report error is not a reason to weaken authentication.

- [x] **Step 3: Add the helper and controller orchestration.**

```ruby
# app/helpers/dashboards_helper.rb
module DashboardsHelper
  # @return [Boolean] Whether the dashboard replaces the global history drawers
  def dashboard_page?
    controller_path == "dashboards" && action_name == "show"
  end

  # @param account [Account, nil] The user's existing default account, not the draft selection
  # @return [Array<Hash>] Fixed, labeled navigation destinations
  def dashboard_shortcuts(account:)
    scope = account ? t("nosia.dashboard.default_account", name: account.name) : t("nosia.dashboard.choose_account")
    [
      { key: "accounts", path: accounts_path, icon: "folders", scope: t("nosia.dashboard.your_accounts") },
      { key: "sources", path: account ? sources_path : accounts_path, icon: "file-search", scope: scope },
      { key: "usage", path: token_usage_path, icon: "chart-bar", scope: t("nosia.dashboard.usage_scope") },
      { key: "profile", path: profile_path, icon: "identification", scope: t("nosia.dashboard.your_profile") },
      { key: "skills", path: account ? agent_skills_path : accounts_path, icon: "code-bracket", scope: scope },
      { key: "tokens", path: api_tokens_path, icon: "clipboard", scope: t("nosia.dashboard.your_tokens") },
      { key: "mcp", path: account ? mcp_servers_path : accounts_path, icon: "window", scope: scope },
      { key: "prompts", path: system_prompts_path, icon: "chats", scope: t("nosia.dashboard.prompts_scope") }
    ]
  end
end
```

```ruby
# app/controllers/dashboards_controller.rb
class DashboardsController < ApplicationController
  include ChatAccountScoped

  def show
    @chat = Current.user.chats.new(account: selected_chat_account(params[:account_id]))
    @selected_model = params[:model]
    @default_account = Current.user.first_account
    @report = TokenUsage::Report.new(accounts: Current.user.accounts)
    @conversations = Current.user.recent_conversations.limit(5).to_a
    @titles = Chat.first_questions_for(@conversations)
  end
end
```

- [x] **Step 4: Replace the dashboard view and add its focused partials.** Keep only the composer panel inside the `chat-account` controller, so account-switch locking does not make unrelated dashboard navigation inert. The compact uploader remains a sibling of the form so form replacement and publisher-disconnect protections retain their existing contracts.

```erb
<%# app/views/dashboards/show.html.erb %>
<% content_for :title, t("nosia.dashboard.title") %>
<div class="n-dashboard" data-dashboard>
  <header class="n-dashboard-heading">
    <p class="n-dashboard-help"><%= t("nosia.dashboard.title") %></p>
    <h1><%= t("nosia.dashboard.welcome") %></h1>
    <p class="n-dashboard-help"><%= t("nosia.dashboard.introduction") %></p>
  </header>
  <div class="n-dashboard-top">
    <%= render "composer", chat: @chat %>
    <%= render "token_usages/overview", report: @report, title_id: "dashboard-usage-title" %>
  </div>
  <%= render "shortcuts", shortcuts: dashboard_shortcuts(account: @default_account) %>
  <%= render "recent", conversations: @conversations, titles: @titles %>
</div>
```

```erb
<%# app/views/dashboards/_composer.html.erb %>
<%# locals: (chat:) %>
<section class="n-dashboard-panel n-dashboard-compose" aria-labelledby="dashboard-composer-title"
         data-controller="chat-account"
         data-chat-account-account-id-value="<%= chat.account_id %>"
         data-chat-account-confirm-message-value="<%= t('nosia.chat.change_account') %>"
         data-action="composer-sources:state->chat-account#sourceState dropzone:state->chat-account#sourceState turbo:submit-start->chat-account#submitStarted turbo:submit-end->chat-account#submitEnded turbo:before-cache@document->chat-account#beforeCache:capture">
  <h2 id="dashboard-composer-title"><%= t("nosia.dashboard.composer_title") %></h2>
  <% if chat.account %><p class="n-dashboard-help"><%= t("nosia.dashboard.composer_help") %></p><% end %>
  <%= render "chats/form", chat: chat %>
  <% if chat.account %>
    <%= render "source_upload", chat: chat %>
  <% else %>
    <p class="n-dashboard-help"><%= t("nosia.dashboard.no_account") %></p>
    <%= link_to t("nosia.dashboard.setup_account"), accounts_path, class: "n-dashboard-link" %>
  <% end %>
</section>
```

```erb
<%# app/views/dashboards/_source_upload.html.erb %>
<%# locals: (chat:) %>
<div class="n-dashboard-upload" data-controller="dropzone" data-variant="dashboard"
     data-dropzone-messages-value="<%= t('nosia.sources.upload_messages').to_json %>"
     data-dropzone-account-id-value="<%= chat.account_id %>"
     data-dropzone-url-value="<%= sources_documents_path %>"
     data-dropzone-max-file-size-value="50"
     data-dropzone-accepted-files-value="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/*,image/png,image/jpeg"
     data-action="chat-account:reset@window->dropzone#resetChatDraft">
  <input type="file" multiple accept="application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/*,image/png,image/jpeg" class="hidden" data-dropzone-target="input">
  <button type="button" class="n-account-secondary" data-dropzone-target="container" data-active="false" aria-describedby="dashboard-upload-help">
    <%= inline_svg "svg/download.svg", aria_hidden: true, class: "mr-2 h-4 w-4" %>
    <%= t("nosia.dashboard.upload_sources") %>
  </button>
  <p id="dashboard-upload-help" class="n-dashboard-help"><%= t("nosia.dashboard.upload_help") %></p>
  <ul class="hidden !list-none space-y-2" data-dropzone-target="list"></ul>
</div>
```

```erb
<%# app/views/dashboards/_shortcuts.html.erb %>
<%# locals: (shortcuts:) %>
<section aria-labelledby="dashboard-shortcuts-title">
  <h2 id="dashboard-shortcuts-title" class="text-base font-semibold"><%= t("nosia.dashboard.shortcuts_title") %></h2>
  <nav class="n-dashboard-shortcuts" aria-labelledby="dashboard-shortcuts-title">
    <% shortcuts.each do |shortcut| %>
      <%= link_to shortcut.fetch(:path), class: "n-dashboard-shortcut", data: { dashboard_destination: shortcut.fetch(:key) } do %>
        <%= inline_svg "svg/#{shortcut.fetch(:icon)}.svg", aria_hidden: true %>
        <strong><%= t("nosia.dashboard.destinations.#{shortcut.fetch(:key)}") %></strong>
        <span class="n-dashboard-help"><%= shortcut.fetch(:scope) %></span>
      <% end %>
    <% end %>
  </nav>
</section>
```

```erb
<%# app/views/dashboards/_recent.html.erb %>
<%# locals: (conversations:, titles:) %>
<section class="n-dashboard-panel" aria-labelledby="dashboard-recents-title">
  <h2 id="dashboard-recents-title"><%= t("nosia.dashboard.recents_title") %></h2>
  <p class="n-dashboard-help"><%= t("nosia.dashboard.recents_help") %></p>
  <ul class="n-dashboard-recent-list !list-none">
    <% conversations.each do |chat| %>
      <li class="n-dashboard-recent-row" data-conversation-id="<%= chat.id %>">
        <div>
          <%= link_to truncate(account_conversation_title(chat, titles: titles), length: 120, omission: "…"), chat_path(chat), class: "n-dashboard-link" %>
          <p class="n-dashboard-help"><%= chat.account.name %></p>
        </div>
        <time class="n-dashboard-help" datetime="<%= chat.updated_at.iso8601 %>"><%= l(chat.updated_at, format: :short) %></time>
      </li>
    <% end %>
  </ul>
  <% if conversations.empty? %><p class="n-dashboard-help"><%= t("nosia.dashboard.no_conversations") %></p><% end %>
  <%= link_to t("nosia.dashboard.history_by_account"), accounts_path, class: "n-dashboard-link" %>
</section>
```

In `app/views/layouts/application.html.erb`, replace the right-drawer condition only:

```diff
-      <% if Current.user && !account_page? %>
+      <% if Current.user && !account_page? && !dashboard_page? %>
```

- [x] **Step 5: Build CSS and run the new requests plus existing composer/navigation contracts.**

```bash
rails_test tailwindcss:build
rails_test test test/controllers/dashboards_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_sources_test.rb test/integration/chat_composer_ui_test.rb test/integration/header_navigation_test.rb test/integration/content_security_policy_test.rb test/integration/ported_script_pages_render_test.rb test/internationalization/catalogs_test.rb
```

Expect the compact uploader's existing request assertions to remain green without deletion. Root query-account validation, the no-account marker, hidden model field, and composer action strings remain unchanged. Do not edit shared composer JavaScript merely to accommodate page markup.

- [x] **Step 6: Commit the composed dashboard.**

```bash
git add app/helpers/dashboards_helper.rb app/controllers/dashboards_controller.rb app/views/dashboards app/views/layouts/application.html.erb test/controllers/dashboards_controller_test.rb
git commit -m "feat(dashboard): add balanced signed-in workspace"
```

**Task 4 execution:** Implemented in `9ad3375`, exactly nine paths. RED: 7 runs / 39 assertions / six expected failures / no errors, seed 12236, exit 1. GREEN: 130 runs / 10,916 assertions / no failures, errors, or skips, seed 5901, exit 0. Tailwind build, changed Ruby lint, and whitespace passed. Independent spec and quality reviews approved; Task 3 visible-localized-number/date-mapping followups are covered. Logs: `/tmp/opencode/dashboard-task4-{red,green,build,lint,whitespace}.log`. Browser verification and global report integration remain pending.

## Task 5: Make global Token usage agree with the dashboard

**Create:** `test/controllers/global_token_usage_test.rb`, `app/views/token_usages/_summary_content.html.erb`.
**Modify:** `app/controllers/token_usages_controller.rb`, `app/views/token_usages/_summary.html.erb`, `app/views/token_usages/show.html.erb`, `test/controllers/accounts/scoped_tokens_usage_test.rb`.

- [x] **Step 1: Add global-report request tests.**

```ruby
# test/controllers/global_token_usage_test.rb
require "test_helper"
require_relative "../support/dashboard_fixtures"

class GlobalTokenUsageTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
  end

  teardown { travel_back }

  test "global report and dashboard agree without changing the default account" do
    get user_root_path, params: { account_id: @second.id }
    assert_select "[data-period-total][data-value='1057']"
    get token_usage_path, params: { account_id: @foreign.id }
    assert_response :success
    assert_select "[data-period-total][data-value='1057']"
    assert_select "[data-lifetime-total][data-value='1065']"
    assert_select "#global-lifetime-summary section p", text: "959"
    assert_select "#global-lifetime-summary section p", text: "106"
    assert_select "li", text: /private-model/, count: 0
    assert_select "details table tbody tr[data-usage-day]", count: 30
    assert_equal @first, @user.first_account
  end

  test "account routes retain their own counters and authorization" do
    get account_token_usage_path(@second)
    assert_response :success
    assert_select "section p", text: "942"
    assert_select "section p", text: "103"
    assert_select "[data-period-total]", count: 0
    get account_token_usage_path(@foreign)
    assert_response :not_found
  end

  test "global reads create no usage or jobs and revoked accounts disappear on the next request" do
    counts = [ Chat.count, Prompt.count, TokenUsage.count ]
    clear_enqueued_jobs
    assert_no_enqueued_jobs { get token_usage_path }
    assert_response :success
    assert_equal counts, [ Chat.count, Prompt.count, TokenUsage.count ]
    experience(:account_users, :overview_owner_second).destroy!
    get token_usage_path
    assert_select "[data-period-total][data-value='12']"
    assert_select "[data-lifetime-total][data-value='20']"
  end

  test "global report renders without a default account and restores any ambient tenant" do
    callbacks_before = TokenUsagesController._process_action_callbacks.to_a
    first = @first
    restored_tenant = nil
    with_ambient_tenant = ->(_controller, action) do
      ActsAsTenant.with_tenant(first) do
        action.call
        restored_tenant = ActsAsTenant.current_tenant
      end
    end
    TokenUsagesController.around_action with_ambient_tenant, only: :show
    get token_usage_path
    assert_response :success
    assert_select "[data-period-total][data-value='1057']"
    assert_equal @first, restored_tenant
    sign_in_overview(experience(:users, :overview_no_account))
    get token_usage_path
    assert_response :success
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='0']"
  ensure
    TokenUsagesController.skip_around_action with_ambient_tenant, raise: false
    assert_equal callbacks_before, TokenUsagesController._process_action_callbacks.to_a
  end
end
```

Replace the two obsolete global-default tests in `test/controllers/accounts/scoped_tokens_usage_test.rb` with the following complete methods. Keep every other test, especially explicit-account and no-Current fragment cases.

```ruby
test "global usage aggregates memberships after viewing a scoped account" do
  get account_token_usage_path(@second)
  assert_response :success
  assert_select "section p", text: "900"

  get token_usage_path
  assert_response :success
  assert_select "#global-lifetime-summary section p", text: "910"
  assert_select "#global-lifetime-summary section p", text: "102"
  assert_select "[data-lifetime-total][data-value='1012']"
end

test "cached account fragments remain isolated and global aggregation does not reuse their keys" do
  previous_cache = Rails.cache
  previous_controller_store = ActionController::Base.cache_store
  previous_perform_caching = ActionController::Base.perform_caching
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
  ActionController::Base.cache_store = Rails.cache
  ActionController::Base.perform_caching = true

  [ [ account_token_usage_path(@first), "10", "2" ],
    [ account_token_usage_path(@second), "900", "100" ],
    [ token_usage_path, "910", "102" ] ].each do |path, input, output|
    get path
    assert_response :success
    assert_select "section p", text: input
    assert_select "section p", text: output
  end
  @second.update_columns(input_tokens_count: 901, output_tokens_count: 101)
  get account_token_usage_path(@second)
  assert_select "section p", text: "901"
  assert_select "section p", text: "101"
  get token_usage_path
  assert_select "#global-lifetime-summary section p", text: "911"
  assert_select "#global-lifetime-summary section p", text: "103"
ensure
  Rails.cache = previous_cache
  ActionController::Base.cache_store = previous_controller_store
  ActionController::Base.perform_caching = previous_perform_caching
end
```

- [x] **Step 2: Run both request files and observe the intended old-scope failures.**

```bash
rails_test test test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb
```

- [x] **Step 3: Preserve the scoped branch and add the global report branch.**

```ruby
# app/controllers/token_usages_controller.rb
class TokenUsagesController < ApplicationController
  include AccountScoped

  def show
    if request.path_parameters.key?(:account_id)
      @usage_account = @account = member_account(request.path_parameters.fetch(:account_id))
      ActsAsTenant.with_tenant(@usage_account) do
        @green_summary = @usage_account.green_it_summary
        @token_totals = { input: @usage_account.input_tokens_count, output: @usage_account.output_tokens_count }
        @tokens_by_kind = @usage_account.token_usages.group(:kind).sum("(input_tokens + output_tokens)")
        @tokens_by_day = @usage_account.token_usages.where("created_at > ?", 30.days.ago)
          .group("DATE(created_at)").sum("(input_tokens + output_tokens)")
      end
    else
      @report = TokenUsage::Report.new(accounts: Current.user.accounts)
    end
  end
end
```

- [x] **Step 4: Extract existing summary markup unchanged, retaining its account-specific cache wrapper.** Use this read-only script to derive the new file contents once before replacing `_summary.html.erb`, then apply the printed result with the patch tool. This preserves the existing body rather than hand-recreating 134 lines and accidentally changing scoped markup or localization selectors; all file edits still use the patch tool.

```python
from pathlib import Path

source = Path("app/views/token_usages/_summary.html.erb")
target = Path("app/views/token_usages/_summary_content.html.erb")
lines = source.read_text().splitlines(keepends=True)
assert not target.exists(), "Inspect existing target instead of overwriting it"
assert lines[3].startswith("<% cache [")
assert lines[-1].strip() == "<% end %>"
body = "".join(line[2:] if line.startswith("  ") else line for line in lines[4:-1])
print("<%# locals: (token_totals:, green_summary:, tokens_by_kind:, tokens_by_day:) %>\n" + body, end="")
```

Replace `_summary.html.erb` with:

```erb
<%# Account counters change without touching the row; retain counter-based cache identity. %>
<% summary_account = local_assigns.fetch(:account) { Current.account } %>
<% cache [ I18n.locale, summary_account, summary_account.input_tokens_count, summary_account.output_tokens_count, "token-usage-summary" ] do %>
  <%= render "token_usages/summary_content", token_totals: token_totals, green_summary: green_summary, tokens_by_kind: tokens_by_kind, tokens_by_day: tokens_by_day %>
<% end %>
```

Replace `app/views/token_usages/show.html.erb` with:

```erb
<% content_for :account_tool_title, t("nosia.usage.title") if @account %>
<% content_for :title, t("nosia.usage.title") %>
<div class="n-title-container">
  <h2 class="n-main-title mt-0.5"><%= t("nosia.usage.title") %></h2>
</div>

<% if @report %>
  <div class="n-global-usage">
    <%= render "overview", report: @report, title_id: "global-usage-title", show_report_link: false %>
    <section id="global-lifetime-summary" aria-labelledby="global-lifetime-title">
      <h3 id="global-lifetime-title" class="mb-3 text-base font-semibold"><%= t("nosia.dashboard.lifetime_details") %></h3>
      <%= render "summary_content", token_totals: @report.lifetime_totals, green_summary: @report.green_summary, tokens_by_kind: @report.tokens_by_kind, tokens_by_day: {} %>
    </section>
    <%= render "transparency" %>
  </div>
<% else %>
  <%= render "summary", account: @usage_account, token_totals: @token_totals, green_summary: @green_summary, tokens_by_kind: @tokens_by_kind, tokens_by_day: @tokens_by_day %>
  <%= render "transparency" %>
<% end %>
```

The global branch deliberately renders uncached content. Its exact 30-day chart comes from `_overview`; passing an empty `tokens_by_day` to lifetime content prevents the legacy scoped chart's older date arithmetic from being used for aggregate reporting. The scoped branch remains unchanged.

- [x] **Step 5: Run reporting, locale, and dashboard regressions together.**

```bash
rails_test test test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/dashboards_controller_test.rb test/integration/token_usages_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb test/controllers/account_experience_test.rb
```

The old `TokenUsagesTest` root assertion excludes the **detailed** environmental heading and per-model rows; it remains valid because the dashboard adds only the compact overview. Do not remove it or weaken the methodology/model-XSS tests.

- [x] **Step 6: Commit the reporting integration.**

```bash
git add app/controllers/token_usages_controller.rb app/views/token_usages/_summary.html.erb app/views/token_usages/_summary_content.html.erb app/views/token_usages/show.html.erb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb
git commit -m "feat(usage): align global reporting with dashboard memberships"
```

**Task 5 execution:** Implemented in `f0e6bb3`, exactly six paths. RED: 19 runs / 279 assertions / five expected failures, seed 50520, exit 1. Initial GREEN exposed a test observing tenant state outside Rails' CurrentAttributes request boundary; observation now runs in a temporary `around_action`, with exact callback-chain cleanup asserted in `ensure`. Final GREEN: 112 runs / 11,512 assertions / no failures/errors, seed 38482, exit 0. Independent spec and quality reviews approved; the quality reviewer also ran an expanded 124-test / 11,592-assertion regression set successfully. Lint and whitespace passed. Logs: `/tmp/opencode/dashboard-task5-{red,green,lint,whitespace}.log`. Optional valid-member query-parameter scope coverage is included in Task 6's navigation test.

## Task 6: Verify the dashboard in a real browser and retain upload/composer coverage

**Create:** `test/system/dashboard_test.rb`.
**Conditional correction:** Modify `app/assets/stylesheets/nosia/dashboard.css` only if a failing browser assertion establishes a dashboard presentation defect. Keep any correction dashboard-scoped; do not alter shared composer behavior or unrelated page styling.
**Browser-discovered navigation correction:** The retained `chat_account_selection` and `chat_composer_ui` suites fail because suppressing the dashboard history drawer also removed its desktop “New chat” link. Restore the existing localized `new_chat_path` link in the dashboard composer heading, desktop-only (mobile already has this link). Allow `app/views/dashboards/_composer.html.erb` and focused request coverage in `test/controllers/dashboards_controller_test.rb` for this correction. Keep the duplicate drawer suppressed and preserve the existing browser tests unchanged.
**Retain unchanged:** `test/system/chat_account_selection_test.rb`, `test/system/chat_composer_ui_test.rb`, `test/system/localization_test.rb`, `test/system/sources_dropzone_test.rb`. These already cover PDF/source registration, retry/idempotency, upload removal, pending-upload submission guards, skill selection, draft reset, and French upload feedback on the root page.

- [x] **Step 1: Add browser tests for the new page-level behavior.** These supplement the earlier red request/model tests. They may pass immediately if those changes already implement the behavior. A newly discovered presentation defect must be reproduced by a failing browser assertion before a corrective application edit; do not weaken assertions or delete existing uploader tests to make the redesign pass.

```ruby
# test/system/dashboard_test.rb
require "application_system_test_case"
require_relative "../support/dashboard_fixtures"

class DashboardSystemTest < ApplicationSystemTestCase
  include DashboardFixtures

  setup do
    travel_to @report_time
    @original_window_size = page.current_window.size
    @evidence_dir = "/tmp/opencode/dashboard-#{Process.pid}"
    FileUtils.mkdir_p(@evidence_dir)
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
    assert_selector "lexxy-editor[connected]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    page.current_window.resize_to(*@original_window_size) if @original_window_size
    travel_back
  end

  test "root composer sends in the selected account through the existing job flow" do
    visit user_root_url(account_id: @second.id, model: "overview-test-model")
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Question from the dashboard")
    assert_enqueued_jobs 1, only: ChatResponseJob do
      find("button[aria-label='Send']").click
      assert_selector "[data-chat-account-readonly]", text: @second.name
    end
    chat = @user.chats.order(:id).last
    assert_current_path chat_path(chat)
    assert_equal @second.id, chat.account_id
    assert_equal "Question from the dashboard", chat.messages.user.last.content.strip
    assert_equal @first, @user.first_account
  end

  test "draft switching confirms reset but never changes aggregate scope or default tool labels" do
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep my draft")
    dismiss_confirm(/clears your unsent message/) { select @second.name, from: "Account" }
    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
    assert_text "Keep my draft"
    accept_confirm(/clears your unsent message/) { select @second.name, from: "Account" }
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_no_text "Keep my draft"
    assert_selector "[data-period-total][data-value='1057']"
    assert_selector "[data-dashboard-destination='sources']", text: @first.name
    assert_selector "[data-dropzone-account-id-value='#{@second.id}']"
  end

  test "all eight shortcuts open their existing tools and usage details match the dashboard" do
    paths = { accounts: accounts_path, sources: sources_path, usage: token_usage_path,
      profile: profile_path, skills: agent_skills_path, tokens: api_tokens_path,
      mcp: mcp_servers_path, prompts: system_prompts_path }
    assert_no_enqueued_jobs do
      paths.each do |key, path|
        visit user_root_path
        find("[data-dashboard-destination='#{key}']").click
        assert_current_path path
      end
    end
    visit user_root_path
    within ".n-usage-overview" do
      click_on "Usage details"
    end
    assert_current_path token_usage_path
    assert_selector "[data-period-total][data-value='1057']"
    assert_selector "[data-lifetime-total][data-value='1065']"
    visit token_usage_path(account_id: @second.id)
    assert_selector "[data-period-total][data-value='1057']"
    assert_selector "[data-lifetime-total][data-value='1065']"
    find(".n-dashboard-daily-data summary").click
    assert_selector ".n-dashboard-daily-data tbody tr", count: 30
    assert_equal 1057, all(".n-dashboard-daily-data tbody td").sum { |cell| cell["data-value"].to_i }
  end

  test "French long labels fit responsive layouts in both themes with visible keyboard actions" do
    @first.update_columns(name: "CompteDeRecherche" * 12)
    select "FR", from: "language_preference_locale"
    assert_selector "html[lang='fr']"
    surfaces = []
    [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
      resize_dashboard(width, height)
      %w[light dark].each do |theme|
        set_dashboard_theme(theme)
        assert_selector "h1", text: "Heureux de vous retrouver."
        assert_no_text(/translation missing|missing translation/i)
        assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
        columns = page.evaluate_script("getComputedStyle(document.querySelector('.n-dashboard-top')).gridTemplateColumns").split.length
        assert_equal width >= 1280 ? 2 : 1, columns
        if [ 375, 1440 ].include?(width)
          verify_dashboard_keyboard
          verify_dashboard_contrast
        end
        surfaces << page.evaluate_script("getComputedStyle(document.querySelector('.n-dashboard-panel')).backgroundColor")
        page.execute_script("document.querySelector('main').scrollTop = 0")
        page.save_screenshot("#{@evidence_dir}/#{width}-#{height}-#{theme}.png")
        if width == 375
          page.execute_script("document.querySelector('.n-dashboard-shortcuts').scrollIntoView({block:'start'})")
          page.save_screenshot("#{@evidence_dir}/375-#{theme}-shortcuts.png")
        end
      end
    end
    assert_operator surfaces.uniq.length, :>=, 2
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    assert page.evaluate_script("Array.from(document.querySelectorAll('.n-dashboard-shortcut')).every(e => getComputedStyle(e).transitionDuration === '0s')")
  end

  test "no-account setup guidance remains readable in both themes" do
    page.driver.browser.manage.delete_all_cookies
    visit root_url
    fill_in "email", with: experience(:users, :overview_no_account).email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
    assert_selector "[data-chat-no-account]"
    assert_no_selector "lexxy-editor"
    assert_selector "[data-period-total][data-value='0']"
    resize_dashboard(375, 812)
    %w[light dark].each do |theme|
      set_dashboard_theme(theme)
      100.times do
        page.send_keys(:tab)
        break if page.evaluate_script("document.activeElement.matches('.n-dashboard-shortcut')")
      end
      assert_selector ".n-dashboard-shortcut:focus"
      verify_dashboard_contrast
      page.execute_script("document.querySelector('main').scrollTop = 0")
      page.save_screenshot("#{@evidence_dir}/375-no-account-#{theme}.png")
    end
  end

  private
    def resize_dashboard(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth, innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
    end

    def set_dashboard_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script(<<~JS)
        const done = arguments[0];
        Promise.all(document.getAnimations().map(a => a.finished.catch(() => {}))).then(() => done());
      JS
    end

    def verify_dashboard_keyboard
      find("lexxy-editor .lexxy-editor__content").click
      seen = []
      120.times do
        page.send_keys(:tab)
        state = page.evaluate_script(<<~JS)
          (() => {
            const e = document.activeElement;
            if (!e.matches('.n-dashboard-shortcut')) return null;
            const r = e.getBoundingClientRect(), s = getComputedStyle(e);
            const main = document.querySelector('main').getBoundingClientRect();
            const points = [[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
            return {key:e.dataset.dashboardDestination, outline:parseFloat(s.outlineWidth),
              visible:r.top >= Math.max(0,main.top) && r.bottom <= Math.min(innerHeight,main.bottom) && points.every(([x,y]) => {
                const hit=document.elementFromPoint(x,y); return !!hit && (hit===e || e.contains(hit));
              })};
          })()
        JS
        next unless state

        assert_operator state.fetch("outline"), :>=, 2
        assert state.fetch("visible"), "Focused shortcut is obscured: #{state.fetch('key')}"
        seen << state.fetch("key")
        break if seen.uniq.length == 8
      end
      assert_equal %w[accounts sources usage profile skills tokens mcp prompts], seen.uniq
      page.send_keys([ :shift, :tab ])
      assert_equal "mcp", page.evaluate_script("document.activeElement.dataset.dashboardDestination")
    end

    def verify_dashboard_contrast
      rows = page.evaluate_script(<<~JS)
        (() => {
          const canvas=document.createElement('canvas'); canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color) {
            ctx.clearRect(0,0,1,1); ctx.fillStyle=color; ctx.fillRect(0,0,1,1);
            const p=Array.from(ctx.getImageData(0,0,1,1).data); p[3]/=255; return p;
          }
          function blend(a,b) { return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3])); }
          function background(e) {
            const ancestors=[]; for(let a=e;a;a=a.parentElement) ancestors.unshift(a);
            return ancestors.reduce((bg,a)=>{
              const s=getComputedStyle(a);
              if(s.backgroundImage!=='none'||s.opacity!=='1') throw new Error('Unmeasured gradient/opacity');
              return blend(rgba(s.backgroundColor),bg);
            },[255,255,255]);
          }
          function luminance(rgb) {
            return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;})
              .reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);
          }
          function measure(selector,focus,minimum) {
            const e=document.querySelector(selector),s=getComputedStyle(e),bg=background(focus?e.parentElement:e);
            const fg=blend(rgba(focus?s.outlineColor:s.color),bg),a=luminance(fg),b=luminance(bg);
            return {selector,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};
          }
          const samples = [
            ...['.n-dashboard-heading h1','.n-dashboard-help','.n-dashboard-panel .n-dashboard-help',
              '.n-dashboard-shortcut strong','.n-dashboard-shortcut .n-dashboard-help','.n-dashboard-link'].map(s=>measure(s,false,4.5)),
            measure('.n-dashboard-shortcut svg',false,3),measure('.n-dashboard-shortcut:focus',true,3)
          ];
          if (document.querySelector('[data-chat-no-account]')) samples.push(measure('[data-chat-no-account]',false,4.5));
          return samples;
        })()
      JS
      rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.fetch("selector") }
      File.open("#{@evidence_dir}/contrast.jsonl", "a") do |file|
        file.puts({ viewport: page.evaluate_script("[innerWidth,innerHeight]"), dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: rows }.to_json)
      end
    end
end
```

- [x] **Step 2: Build assets, then run the new browser file with the installed local browser/driver.** This bootstrap unsets the broken remote-browser switch from the ignored environment without editing shared test configuration.

```bash
rails_test tailwindcss:build
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test test/system/dashboard_test.rb
```

Expect correct root submission and redirect, stable tool/report context after switching, eight working destinations, 30 visible table rows after expansion, responsive column changes, distinct themes, visible keyboard focus, and passing sampled contrast checks. If Task 0 found different browser binary paths, use those observed paths rather than installing anything.

- [x] **Step 3: Run the existing browser regressions sequentially.**

```bash
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test test/system/chat_account_selection_test.rb
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test test/system/chat_composer_ui_test.rb
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test test/system/localization_test.rb
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test test/system/sources_dropzone_test.rb
RAILS_ENV=test DATABASE_URL=postgresql:///nosia_signed_in_dashboard_test AI_API_KEY=nosia-test-key PARALLEL_WORKERS=1 bundle exec dotenv -f ../../.env -- bundle exec ruby -rselenium-webdriver -e 'ENV.delete("CAPYBARA_SERVER_PORT"); Selenium::WebDriver::Chrome::Service.driver_path="/usr/bin/chromedriver"; Selenium::WebDriver::Chrome.path="/usr/bin/chromium"; load "bin/rails"' -- test test/system/account_experience_test.rb
```

Expected: compact/root/saved/new composer interactions and generic/scoped sources continue working. Existing test names may still say “dashboard uploads”; the feature remains present as a compact control, so no mass test renaming/deletion is necessary.

- [x] **Step 4: Read the screenshots produced in the test's `@evidence_dir` (`"/tmp/opencode/dashboard-#{Process.pid}"`) with the image-reading tool.** Inspect desktop balance, narrow/landscape wrapping, both themes, the compact uploader, and shortcuts below the fold. Retain actual screenshot paths and contrast records in the verification notes; do not claim a screenshot was reviewed without opening it.
- [x] **Step 5: Perform a separate native-browser 200% zoom check if a headed browser is available.** In that browser set native zoom to 200%, revisit signed-in `/`, and Tab through the composer and shortcuts; verify reflow and unobscured controls. If no headed session can establish native zoom, explicitly record it as unverified. CDP viewport/device-scale or CSS zoom is not equivalent evidence.
- [x] **Step 6: Commit browser coverage once all new targeted tests pass.**

```bash
git add test/system/dashboard_test.rb app/assets/stylesheets/nosia/dashboard.css
git commit -m "test(dashboard): cover browser navigation and responsive accessibility"
```

**Task 6 execution:** Browser coverage and scoped CSS corrections in `373d595`; desktop navigation regression corrected in `3146187`; visible-link contrast sampling hardened in `2b5440f`. Browser-proven corrections address dark no-account text contrast and Formatting toolbar movement without changing shared composer code. The missing desktop New chat link was reproduced by the retained suites and a new failing request assertion, then restored without bringing back the history drawer. The existing five browser files remain unchanged.

Final sequential browser results: dashboard 5 / 304 (seed 39133), selection 44 / 681 (14055), composer 29 / 2,765 (47619), localization 8 / 337 (55800), dropzone 1 / 2 (65319), account experience 13 / 632 (24210): **100 tests / 4,721 assertions, zero failures/errors/skips, all exit 0**. New request coverage: 8 / 130, seed 36181, exit 0. The test-only contrast refinement reran the dashboard suite: 5 / 304, seed 39133, exit 0; production remained unchanged. All build/lint/whitespace checks passed. Failed attempts are preserved in `/tmp/opencode/dashboard-task6-01*` through `-28*`; final checks are `-29*` through `-45*`.

The implementer, reviewers, and coordinator opened actual final screenshots. Latest 14 images and contrast records are in `/tmp/opencode/dashboard-530817/`: `{375-812,768-1024,1440-1000,812-375}-{light,dark}.png`, `375-{light,dark}-{upload,shortcuts}.png`, `375-no-account-{light,dark}.png`, and `contrast.jsonl`. Minimum sampled text/icon contrast is 7.13:1; focus is 4.54:1. Extreme account names create tall cards but wrap without horizontal overflow. Visible-link sampling now records actual visible matches rather than the hidden mobile desktop-only link.

**Native 200% browser zoom remains UNVERIFIED:** no headed display was available and headless zoom did not apply (`/tmp/opencode/dashboard-task6-26-native-zoom.log`). Step 5 is recorded as attempted/limitation documented, not as a passing native-zoom check. Independent spec and quality reviews approved Task 6; no blocking or remaining minor finding. No full server-suite claim is made here.

## Task 7: Document the dashboard and review public Ruby interfaces

**Create:** `docs/dashboard.md`.
**Modify:** `docs/account-experience.md`, `docs/README.md`, `docs/DIAGRAMS.md`.

- [ ] **Step 1: Add this user/developer guide.** It describes behavior and verification procedure, not unrun success claims.

```markdown
# Signed-in dashboard

When signed in, `/` opens your workspace dashboard. The public signed-out root
is unchanged. Start a conversation directly in the existing composer, choose
its account, and use its PDF, source, skill, and tool controls normally.
The compact knowledge-source upload control retains upload/retry/removal and
account-switch safeguards without the former oversized upload area.

## Usage scope and dates

The overview combines account-wide usage across every account you currently
belong to, including other members' usage and source-indexing embeddings.
It is not a personal-only activity report. Accounts outside current membership
are excluded; revoked memberships disappear on the next request.

Input, output, total, and the daily line cover 30 calendar dates in the Rails
application time zone: midnight 29 dates before today through the request's
reference time, including both endpoints and excluding future events. Missing
days are zero-filled. Expand Daily token values for the same values in a table.
The footer's lifetime total comes from the existing account counters.

The global `/token_usage` page uses the same account set and period definition.
Lifetime breakdowns/environmental estimates are labeled separately. Explicit
`/accounts/:account_id/token_usage` pages remain account-specific; their existing
authorization, reporting semantics, and cache isolation remain intact.
No new token tracking, billing calculation, counter repair, or polling is added.

## Navigation and privacy

All eight destinations are visible: Accounts, Sources, Token usage, User profile,
Agent skills, API tokens, MCP servers, and System prompts. Sources, Agent skills,
and MCP servers retain their existing default-account behavior; the tiles name
that account. Selecting another account in the composer changes only the draft,
not global usage or those tool destinations. Other directories keep their
existing ownership and permission rules.

The recent panel shows at most five of your root conversations in accessible
accounts, with account names and activity times. Other members' conversations
are private even when you own the account. Previews are plain text and at most
120 characters; opening a conversation shows its full saved content. Browse
Accounts for complete per-account history. The dashboard replaces its duplicate
right history drawer; other pages keep their existing navigation.

Without memberships, the dashboard shows account-setup guidance and zero usage.
Default-account tool tiles lead to Accounts instead of broken destinations;
Profile and existing directory links remain reachable.

## Verification procedure

Use the dedicated test-only database and explicit environment commands in
`superpowers/plans/2026-10-24-signed-in-dashboard.md`. Run database-sharing suites
sequentially and never start live providers/ingestion workers for browser tests.
Inspect the produced root screenshots and contrast records in both themes,
verify keyboard order/unobscured controls and the daily table, and report actual
suite exits and any preexisting failures separately.

Native 200% browser zoom requires a separate headed/manual check. A small
viewport, device-scale override, or CSS zoom does not establish native zoom.
Record any unavailable manual check explicitly rather than implying coverage.
```

- [ ] **Step 2: Correct the account guide's usage description without rewriting historical evidence.** Replace its current “Usage is lifetime account-wide input/output” bullet with this exact Markdown paragraph:

```markdown
- Usage on the hub and explicit account report is lifetime account-wide
  input/output. The signed-in dashboard and global `/token_usage` page aggregate
  all current membership accounts, including other members' usage; dashboard
  period totals and lifetime totals are labeled separately. Hub summaries refresh
  on navigation/reload. This is usage reporting, not a new billing system.
```

Leave historical test logs and past native-zoom limitations intact; those are evidence from earlier revisions, not current dashboard results.

- [ ] **Step 3: Add the guide link and entrypoint diagram.** Add this line after the Account experience link in `docs/README.md`:

```markdown
- [Signed-in dashboard](dashboard.md) — inline conversations, cross-account token statistics, explicit tool shortcuts, and private recents.
```

Add this section before `## Account Experience Entry Points` in `docs/DIAGRAMS.md`:

````markdown
## Signed-in Dashboard Entry Points

```text
Authenticated /
  ├─ Inline composer → existing chat create → saved conversation
  ├─ Usage overview → global /token_usage (current memberships)
  ├─ Eight labeled shortcuts → existing tool/directory routes
  └─ Your five recent root chats → your saved conversation

Composer account selection ≠ default tool account ≠ aggregate report scope
```

Recent conversation content remains personal. Usage is account-wide across
current memberships. Explicit account reports stay scoped to their URL account.
See [Signed-in dashboard](dashboard.md) for dates, empty states, and verification.
````

- [ ] **Step 4: Review YARD and boundaries inline against the code.** Check the documented authorized-relation precondition and time endpoints on `TokenUsage::Report`, hash/Date return types, recent-conversation relation, numeric SVG helper, and shortcut helper. Ensure each public method's actual signature matches this plan and its callers. Do not add a services layer, global account mutation, or comments on every ERB/controller line.
- [ ] **Step 5: Check documentation whitespace and commit explicit paths.**

```bash
git diff --check
git add docs/dashboard.md docs/account-experience.md docs/README.md docs/DIAGRAMS.md
git commit -m "docs(dashboard): explain aggregate scope and navigation"
```

## Task 8: Run the final verification and review gates

- [ ] **Step 1: Rerun all focused server regressions after the final application change.**

```bash
rails_test test test/models/token_usage/report_test.rb test/models/dashboard_recents_test.rb test/models/account_overview_test.rb test/helpers/token_usages_helper_test.rb test/controllers/dashboards_controller_test.rb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/account_experience_test.rb test/controllers/accounts_controller_test.rb test/controllers/chat_account_selection_test.rb test/controllers/chat_account_access_test.rb test/controllers/chat_account_sources_test.rb test/integration/chat_composer_ui_test.rb test/integration/header_navigation_test.rb test/integration/token_usages_test.rb test/integration/localized_pages_test.rb test/integration/content_security_policy_test.rb test/integration/ported_script_pages_render_test.rb test/internationalization/catalogs_test.rb
```

Expected: zero new failures/errors. Preserve actual counts, seed, command, and exit. If a new failure is discovered, use systematic debugging; do not silently skip it or change unrelated code.

- [ ] **Step 2: Run the full server suite and retain the log.**

```bash
rails_test test > /tmp/opencode/signed-in-dashboard-final-suite.log 2>&1
```

Compare with the explicitly accepted Task 0 baseline. A failing command remains failing even if its only error was accepted earlier; report both facts. Never label historical account-experience results as a fresh dashboard full-suite run.

- [ ] **Step 3: Run changed-file lint, security scanning, and diff checks.**

```bash
RUBOCOP_TARGET_RUBY_VERSION=4.0 bundle exec rubocop app/models/token_usage/report.rb app/models/user.rb app/controllers/dashboards_controller.rb app/controllers/token_usages_controller.rb app/helpers/dashboards_helper.rb app/helpers/token_usages_helper.rb test/support/dashboard_fixtures.rb test/models/token_usage/report_test.rb test/models/dashboard_recents_test.rb test/helpers/token_usages_helper_test.rb test/controllers/dashboards_controller_test.rb test/controllers/global_token_usage_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/system/dashboard_test.rb
bundle exec brakeman --no-pager
git diff --check 68b15a1
git diff --stat 68b15a1
git status --short
```

Expect clean changed-file lint and whitespace. Record Brakeman's actual exit/warnings; existing Rails end-of-support or API-token warnings are not a clean security pass and must not be silently suppressed or fixed as unrelated dashboard work.

- [ ] **Step 4: Rerun the browser commands in Task 6 after any corrective UI change.** Read the new screenshots and contrast records, not stale earlier artifacts. Record which native-zoom/manual checks remain unverified.
- [ ] **Step 5: Perform specification-fidelity and Rails/security self-review.** Verify every row below, inspect the complete diff, and resolve new blocking findings through a failing test first. Use `requesting-code-review` when execution reaches this gate; subagent review is allowed only when the chosen execution workflow explicitly authorizes it.

| Approved requirement | Implementation / evidence |
| --- | --- |
| Authenticated root only; public root unchanged | Task 4 request tests and existing root route constraints. |
| Inline existing composer with selection/model/reset/upload/skill/tool semantics | Task 4 partial reuse; Task 6 new sending/switching tests and unchanged composer/upload browser suites. |
| All membership accounts, other members' usage, chatless indexing, no outsiders | Task 1 fixture/model tests; Tasks 4–5 requests. |
| Thirty local calendar days, inclusive endpoints, no future events, zero-filled chart/table | Tasks 1 and 3 model/helper/component tests; Task 6 expanded table. |
| Distinct lifetime counters and period ledger; matching global report | Tasks 1 and 5. No recount or estimator rewrite. |
| Eight visible named links; default-account labels independent of draft | Tasks 4 and 6 requests/browser navigation; no-account fallbacks. |
| Five private root recents, stable order, batched titles/account loads, 120-character escaped previews | Tasks 2 and 4 model/request tests. |
| No-account/no-usage/no-chat states; read-only GETs and tenant restoration | Tasks 1, 4, and 5; review aggregate branches for unexpected provider calls. |
| Existing explicit account report/cache semantics and other page drawers | Tasks 4–5 requests plus account/browser regressions. |
| Light/dark, responsive/long French text, keyboard order, contrast, reduced motion, chart fallback | Tasks 3 and 6; inspect generated screenshot and contrast artifacts. |
| No new schema/packages/tracking/polling/global switch/CSRF cache | Diff and architecture/security review. |
| Test-first, public-method docs, user docs, accurate verification reporting | Tasks 0–8, YARD tags, documentation, final evidence. |

- [ ] **Step 6: Hand off the outcome without merging or discarding work.** Report the branch/worktree, feature behavior, actual checks and warnings, any accepted baseline failures, and the separate native-zoom status. Do not merge, push, open a PR, or remove this worktree without user direction; use `finishing-a-development-branch` to offer integration choices once its prerequisites are satisfied.

## Plan self-review record

Completed inline during planning:

- Every approved specification section maps to the Task 8 fidelity table.
- Method names, partial locals, translation keys, fixture identities, date windows,
  counter totals, default-account tools, and no-account/no-chat states were checked.
- Global-first-account tests are intentionally replaced; source/composer browser
  safety tests are retained through the compact uploader.
- Static checks passed for all 17 Ruby blocks, all 3 YAML blocks, the Python
  extraction script, and balanced Markdown fences. The 37 English/French strings
  have identical keys and interpolation parameters. No unresolved placeholders
  remain.
- `bundle check` passed. No application code or database was changed during
  planning. These static checks are not execution of the planned Rails tests,
  browser checks, lint, security scan, or native-zoom verification.

This is the planner's own review, not a subagent review. Execution starts only
after the user selects its workflow and Task 0's baseline gate is satisfied.
