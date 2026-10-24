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
end
