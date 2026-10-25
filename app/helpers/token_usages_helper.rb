module TokenUsagesHelper
  # @return [Boolean] Whether this request renders the Token usage workspace
  def token_usage_workspace_page?
    controller_path == "token_usages"
  end

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
