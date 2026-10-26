require "test_helper"
require_relative "../support/dashboard_fixtures"

# Protects the read-only workspace's distinct global and account reporting contracts.
class TokenUsageWorkspaceTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
  end

  teardown { travel_back }

  test "global overview separates recent ledger totals from lifetime counters without writes" do
    counts = record_counts
    counters = member_counters

    assert_no_enqueued_jobs { get token_usage_path, params: { account_id: @foreign.id } }

    assert_response :success
    assert_select "[data-period-total][data-value='1057']", text: "1,057", count: 1
    assert_select "[data-period-input][data-value='952']", text: "952"
    assert_select "[data-period-output][data-value='105']", text: "105"
    assert_select "#global-lifetime-summary" do
      assert_select "[data-lifetime-total][data-value='1065']", text: "1,065", count: 1
      assert_select "[data-lifetime-input][data-value='959']", text: "959"
      assert_select "[data-lifetime-output][data-value='106']", text: "106"
    end
    days = css_select("[data-usage-daily] [data-usage-day]")
    assert_equal 30, days.length
    assert_equal "2026-09-25", days.first["data-usage-day"]
    assert_equal "2026-10-24", days.last["data-usage-day"]
    assert_equal 1057, daily_sum
    assert_global_window
    assert_select "[data-usage-model]", count: 1
    refute_includes response.body, "private-model"
    assert_select "[data-usage-kind='embedding'][data-value='40']"
    assert_select "[data-usage-kind='agent_skill'][data-value='5']"
    assert_select "[data-usage-fallback]", text: I18n.t("nosia.usage.fallback_note"), count: 1
    assert_equal counts, record_counts
    assert_equal counters, member_counters
    assert_equal @first, @user.reload.first_account
  end

  test "account activity retains the exclusive cutoff and future buckets without a period headline" do
    cutoff = 30.days.ago
    member_usage = dashboard_usage(:dashboard_second_member)
    member_usage.update_columns(created_at: cutoff)
    future_date = (@report_time + 40.days).to_date
    dashboard_usage(:dashboard_skill).update_columns(created_at: @report_time + 40.days)

    get account_token_usage_path(@second)

    assert_response :success
    assert_select "[data-period-total]", count: 0
    assert_select "[data-lifetime-total]", count: 1
    assert_select "[data-lifetime-total][data-value='1045']", text: "1,045"
    assert_select "[data-lifetime-input][data-value='942']", text: "942"
    assert_select "[data-lifetime-output][data-value='103']", text: "103"
    assert_select "[data-usage-day='#{cutoff.to_date.iso8601}']", count: 0
    assert_select "[data-usage-day='#{future_date.iso8601}'] td[data-value='5']"
    assert_equal 45, daily_sum
    assert_select "[data-usage-window]", count: 0
    assert_equal [ "2026-10-20", future_date.iso8601 ], css_select("[data-usage-day]").map { |row| row["data-usage-day"] }
    assert_select "[data-usage-bucket-dates]", text: I18n.t("nosia.usage_workspace.bucket_dates",
      start: I18n.l(Date.new(2026, 10, 20), format: :short), end: I18n.l(future_date, format: :short))

    member_usage.update_columns(created_at: cutoff + 1.second)
    get account_token_usage_path(@second)

    assert_response :success
    assert_select "[data-period-total]", count: 0
    assert_select "[data-lifetime-total]", count: 1
    assert_select "[data-lifetime-total][data-value='1045']"
    assert_select "[data-usage-day='#{cutoff.to_date.iso8601}'] td[data-value='1000']"
    assert_equal [ cutoff.to_date.iso8601, "2026-10-20", future_date.iso8601 ], css_select("[data-usage-day]").map { |row| row["data-usage-day"] }
    assert_equal 1045, daily_sum
  end

  test "account report reads leave all records counters and ledger attributes unchanged" do
    counts = record_counts
    account_attributes = @second.reload.attributes
    usage_attributes = ledger_attributes

    assert_no_enqueued_jobs { get account_token_usage_path(@second) }

    assert_response :success
    assert_equal counts, record_counts
    assert_equal account_attributes, @second.reload.attributes
    assert_equal usage_attributes, ledger_attributes
    assert_equal @first, @user.reload.first_account
  end

  test "old usage retains lifetime details while recent global rows are zero and account rows empty" do
    ActsAsTenant.without_tenant do
      TokenUsage.where(account_id: @user.accounts.select(:id)).update_all(created_at: @report_time - 60.days)
    end

    get token_usage_path

    assert_response :success
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='1065']"
    assert_select "[data-usage-model]", count: 1
    assert_select "[data-usage-no-recent]", count: 1
    assert_select "[data-usage-daily] [data-usage-day]", count: 30
    assert_select "[data-usage-daily] [data-usage-day] td[data-value='0']", count: 30
    assert_global_window

    get account_token_usage_path(@second)

    assert_response :success
    assert_select "[data-lifetime-total][data-value='1045']"
    assert_select "[data-usage-no-recent]", count: 1
    assert_select "[data-usage-day]", count: 0
  end

  test "empty account reports retain translated estimates and complete methodology in both locales" do
    %i[en fr].each do |locale|
      get account_token_usage_path(@empty), headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select "[data-lifetime-total][data-value='0']", count: 1
      assert_select "[data-usage-no-recent]", count: 1
      assert_select "[data-usage-fallback], [data-usage-model-fallback]", count: 0
      assert_select "[data-usage-model]", count: 0
      assert_select "[data-usage-models] li, [data-usage-kinds] li", text: I18n.t("nosia.usage.none", locale: locale), count: 2
      assert_select "[data-usage-estimate-caveat]", text: I18n.t("nosia.usage_workspace.estimate_caveat", locale: locale)
      assert_select "[data-usage-methodology] > summary", text: I18n.t("nosia.usage.methodology_question", locale: locale)
      assert_select "[data-usage-methodology] strong", text: "ISO 14044"
      assert_select "[data-usage-methodology] code", text: "N/A"
      methodology = css_select("[data-usage-methodology]").first.text
      assert_includes methodology, "Etalab 2.0"
      assert_includes methodology, I18n.l(Date.new(2026, 7, 2), format: :dataset_snapshot, locale: locale)
      %w[https://ecologits.ai https://comparia.beta.gouv.fr https://comparia.beta.gouv.fr/ranking].each do |url|
        assert_select "[data-usage-methodology] a[href='#{url}'][rel='noopener'][target='_blank']", count: 1
      end
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "malformed and revoked route accounts cannot be replaced by forged query parameters" do
    get "/accounts/not-an-account/token_usage", params: { account_id: @second.id }
    assert_response :not_found

    experience(:account_users, :overview_owner_second).destroy!
    get account_token_usage_path(@second), params: { account_id: @first.id }
    assert_response :not_found

    get token_usage_path
    assert_response :success
    assert_select "[data-period-total][data-value='12']"
    assert_select "[data-lifetime-total][data-value='20']"
  end

  test "ledger query failures never become successful zero reports" do
    failure = ->(*event) do
      sql = event.last.fetch(:sql)
      if sql.match?(/\ASELECT/i) && sql.include?('"token_usages"')
        raise ActiveRecord::StatementInvalid, "Token usage query failure probe"
      end
    end

    [ token_usage_path, account_token_usage_path(@second) ].each do |path|
      error = assert_raises(ActiveRecord::StatementInvalid, ActionView::Template::Error) do
        ActiveSupport::Notifications.subscribed(failure, "sql.active_record") { get path }
      end

      assert_includes error.message, "Token usage query failure probe"
    end
  end

  private
    def record_counts
      ActsAsTenant.without_tenant do
        [ Chat, Message, Prompt, TokenUsage, Document, Text, Qna, Website ].map(&:count)
      end
    end

    def member_counters
      @user.accounts.order(:id).pluck(:id, :input_tokens_count, :output_tokens_count, :updated_at)
    end

    def ledger_attributes
      ActsAsTenant.without_tenant { TokenUsage.order(:id).map(&:attributes) }
    end

    def daily_sum
      css_select("[data-usage-daily] [data-usage-day] td").sum { |cell| cell["data-value"].to_i }
    end

    def assert_global_window
      assert_select "[data-usage-window]", text: "#{I18n.l(Date.new(2026, 9, 25), format: :short)} – #{I18n.l(Date.new(2026, 10, 24), format: :short)}", count: 1
    end
end
