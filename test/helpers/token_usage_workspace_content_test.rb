require "test_helper"

# Verifies report components render exact, escaped content from explicit locals.
class TokenUsageWorkspaceContentTest < ActionView::TestCase
  setup { Current.reset }

  test "estimates localize precision and display their caveat without a fallback" do
    green_summary = { kwh: 0.1234567, co2e_g: 12.345, fallback_used: false }

    %i[en fr].each do |locale|
      html = I18n.with_locale(locale) do
        ApplicationController.render(partial: "token_usages/estimates", locals: { green_summary: green_summary })
      end
      fragment = Nokogiri::HTML.fragment(html)

      assert_nil Current.session
      assert_select fragment, "[data-usage-energy][data-value='0.1234567']", text: locale == :fr ? "0,123457" : "0.123457"
      assert_select fragment, "p", text: locale == :fr ? "kWh · 12,35 gCO₂e" : "kWh · 12.35 gCO₂e"
      assert_select fragment, "[data-usage-fallback]", count: 0
      assert_select fragment, "[data-usage-estimate-caveat]", text: I18n.t("nosia.usage_workspace.estimate_caveat", locale: locale)
    end
  end

  test "breakdowns preserve every supplied row in order with escaped model names and precise fallbacks" do
    models = 5.times.map do |index|
      { model_id: index.zero? ? "<script>Long model</script>" : "model-#{index}",
        tokens: 1234 + index, kwh: 0.1234567 + index, fallback: index == 2 }
    end
    kinds = { "completion" => 1, "embedding" => 2, "agent_skill" => 0 }

    %i[en fr].each do |locale|
      html = I18n.with_locale(locale) do
        ApplicationController.render(partial: "token_usages/breakdowns", locals: {
          green_summary: { models: models }, tokens_by_kind: kinds
        })
      end
      fragment = Nokogiri::HTML.fragment(html)

      assert_nil Current.session
      assert_select fragment, "[data-usage-model]", count: 5
      assert_select fragment, "[data-usage-kind]", count: 3
      assert_select fragment, "[data-usage-model-fallback]", text: I18n.t("nosia.usage_workspace.fallback", locale: locale), count: 1
      assert_select fragment, "script", count: 0
      assert_includes html, "&lt;script&gt;Long model&lt;/script&gt;"
      rows = fragment.css("[data-usage-model]")
      assert_equal models.map { |entry| entry[:model_id] }, rows.map { |row| row["data-usage-model"] }
      models.zip(rows).each do |entry, row|
        assert_equal entry[:tokens].to_s, row["data-value"]
        assert_select row, "span", text: entry[:model_id]
        assert_select row, "span", text: I18n.t("nosia.usage.token_quantity", count: entry[:tokens],
          formatted_count: number_with_delimiter(entry[:tokens], locale: locale), locale: locale)
        assert_equal "#{number_with_precision(entry[:kwh], precision: 6, locale: locale)} kWh#{entry[:fallback] ? '*' : ''}", row.at_css("p").text
        assert_select row, "[data-usage-model-fallback]", count: entry[:fallback] ? 1 : 0
      end
      kind_rows = fragment.css("[data-usage-kind]")
      assert_equal kinds.keys, kind_rows.map { |row| row["data-usage-kind"] }
      kinds.zip(kind_rows).each do |(kind, tokens), row|
        assert_equal tokens.to_s, row["data-value"]
        assert_select row, "span.capitalize", text: I18n.t("nosia.usage.kinds.#{kind}", locale: locale)
        assert_select row, "span", text: I18n.t("nosia.usage.token_quantity", count: tokens,
          formatted_count: number_with_delimiter(tokens, locale: locale), locale: locale)
      end
      fragment.css("[style]").each { |element| assert_match(/\Awidth: \d+%\z/, element["style"]) }
    end
  end

  test "metrics retain full localized integers and native plural units at every count" do
    %i[en fr].each do |locale|
      [ 0, 1, 2, 9_123_456_789_012 ].each do |count|
        html = I18n.with_locale(locale) do
          ApplicationController.render(partial: "token_usages/metrics", locals: {
            totals: { input: count, output: 0, total: count }, prefix: "lifetime"
          })
        end
        fragment = Nokogiri::HTML.fragment(html)

        assert_nil Current.session
        %w[total input].each do |kind|
          assert_select fragment, "[data-lifetime-#{kind}][data-value='#{count}']", text: number_with_delimiter(count, locale: locale), count: 1
        end
        assert_select fragment, "[data-lifetime-output][data-value='0']", text: "0", count: 1
        assert_select fragment, "dd", text: I18n.t("nosia.usage.token_unit", count: count, locale: locale), minimum: 2
      end
    end
  end
end
