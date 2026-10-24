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
