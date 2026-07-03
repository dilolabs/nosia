class TokenUsagesController < ApplicationController
  def show
    @token_totals = {
      input: Current.account.input_tokens_count,
      output: Current.account.output_tokens_count
    }
    @tokens_by_model = Current.account.token_usages
                              .where.not(model_id: nil)
                              .group(:model_id)
                              .sum("(input_tokens + output_tokens)")
                              .sort_by { |_, v| -v }
                              .first(5)
    @tokens_by_kind = Current.account.token_usages.group(:kind).sum("(input_tokens + output_tokens)")
    @tokens_by_day = Current.account.token_usages
                            .where("created_at > ?", 30.days.ago)
                            .group("DATE(created_at)")
                            .sum("(input_tokens + output_tokens)")
  end
end
