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

    def total_expression
      Arel.sql("COALESCE(token_usages.input_tokens, 0) + COALESCE(token_usages.output_tokens, 0)")
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
