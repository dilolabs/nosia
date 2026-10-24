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
