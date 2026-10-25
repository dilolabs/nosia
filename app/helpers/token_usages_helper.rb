module TokenUsagesHelper
  # @return [Boolean] Whether this request renders the Token usage workspace
  def token_usage_workspace_page?
    controller_path == "token_usages"
  end

  # @param buckets [Hash{Date, String => Integer}] Existing SQL/report date buckets
  # @return [Hash{Date => Integer}] Chronological buckets with quantities unchanged
  def usage_display_days(buckets)
    buckets.map { |date, tokens| [ date.to_date, tokens ] }.sort_by(&:first).to_h
  end

  # @param account [Account, nil] Already-authorized scoped account; nil is uncached global
  # @param section [String] Headline, estimates or breakdowns presentation identity
  # @return [Array] Locale/account/counter/version identity, never a recent-window key
  def usage_lifetime_cache_key(account, section)
    [ "usage-workspace-v1", I18n.locale, account, account&.input_tokens_count,
      account&.output_tokens_count, section ]
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
