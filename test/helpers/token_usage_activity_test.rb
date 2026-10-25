require "test_helper"

class TokenUsageActivityTest < ActionView::TestCase
  include TokenUsagesHelper

  test "date normalization preserves every returned bucket and quantity" do
    supplied = { "2026-11-30" => 71, Date.new(2026, 9, 24) => 9, "2026-10-24" => 12 }
    original = supplied.dup
    days = usage_display_days(supplied)

    assert_equal [ Date.new(2026, 9, 24), Date.new(2026, 10, 24), Date.new(2026, 11, 30) ], days.keys
    assert_equal [ 9, 12, 71 ], days.values
    assert_equal original, supplied
    assert_equal({}, usage_display_days({}))
  end

  test "chart and accessible table use exactly the same ordered values in both locales" do
    days = { Date.new(2026, 9, 24) => 9, Date.new(2026, 10, 24) => 1234, Date.new(2026, 11, 30) => 71 }

    %i[en fr].each do |locale|
      html = I18n.with_locale(locale) do
        ApplicationController.render(partial: "token_usages/activity", locals: { daily_totals: days, scoped: true })
      end
      fragment = Nokogiri::HTML.fragment(html)

      assert_select fragment, "svg[role='img'][aria-labelledby='usage-trend-title usage-trend-description']"
      assert_select fragment, "svg title#usage-trend-title", count: 1
      assert_select fragment, "svg title#usage-trend-title", text: I18n.t("nosia.usage_workspace.trend_title", locale: locale)
      assert_select fragment, "svg desc#usage-trend-description", count: 1
      assert_select fragment, "polyline[points='#{usage_trend_points(days)}']"
      assert_equal days.keys.map(&:iso8601), fragment.css("[data-usage-day]").map { |row| row["data-usage-day"] }
      assert_equal days.values, fragment.css("[data-usage-day] td").map { |cell| cell["data-value"].to_i }
      days.each do |date, tokens|
        row = fragment.at_css("[data-usage-day='#{date.iso8601}']")

        assert_equal I18n.l(date, format: :short, locale: locale), row.at_css("th[scope='row']").text
        assert_equal number_with_delimiter(tokens, locale: locale), row.at_css("td").text
      end
      assert_select fragment, "details[data-usage-daily] > summary", count: 1
      assert_select fragment, "th[scope='col']", count: 2
      assert_select fragment, "th[scope='row']", count: 3
      assert_equal I18n.t("nosia.usage_workspace.bucket_dates",
        start: I18n.l(days.keys.first, format: :short, locale: locale),
        end: I18n.l(days.keys.last, format: :short, locale: locale),
        locale: locale), fragment.at_css("[data-usage-bucket-dates]").text
      refute_match(/translation missing|missing translation|NaN|Infinity/i, html)
    end
  end

  test "empty and single point series remain honest and finite" do
    [ {}, { Date.new(2026, 10, 24) => 8 } ].each do |days|
      html = ApplicationController.render(partial: "token_usages/activity", locals: { daily_totals: days, scoped: true })
      fragment = Nokogiri::HTML.fragment(html)

      assert_select fragment, "[data-usage-day]", count: days.length
      assert_select fragment, "[data-usage-no-recent]", count: days.empty? ? 1 : 0
      assert_select fragment, "polyline[points='#{usage_trend_points(days)}']"
      assert_select fragment, "svg circle", count: days.length
      if days.one?
        assert_select fragment, "svg circle[cx='0'][cy='4.0'][r='2'][fill='currentColor']", count: 1
      end
      assert_select fragment, "[data-usage-window]", count: 0
      refute_match(/NaN|Infinity/, html)
    end
  end

  test "activity rejects omission of each required local with a meaningful contract error" do
    locals = { daily_totals: {}, scoped: true }

    %i[daily_totals scoped].each do |missing_local|
      error = assert_raises(ActionView::Template::Error) do
        ApplicationController.render(partial: "token_usages/activity", locals: locals.except(missing_local))
      end

      assert_instance_of ActionView::StrictLocalsError, error.cause
      assert_match(/missing local: :#{missing_local}\b/, error.message)
      assert_match(%r{token_usages/_activity\.html\.erb}, error.message)
    end
  end

  test "activity rejects unknown locals with a meaningful contract error" do
    error = assert_raises(ActionView::Template::Error) do
      ApplicationController.render(partial: "token_usages/activity", locals: { daily_totals: {}, scoped: true, unexpected: true })
    end

    assert_instance_of ActionView::StrictLocalsError, error.cause
    assert_match(/unknown local: :unexpected\b/, error.message)
    assert_match(%r{token_usages/_activity\.html\.erb}, error.message)
  end
end
