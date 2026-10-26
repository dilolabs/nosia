require "test_helper"
require_relative "../support/dashboard_fixtures"

class TokenUsageWorkspaceCacheTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
    @previous_cache = Rails.cache
    @previous_store = ActionController::Base.cache_store
    @previous_caching = ActionController::Base.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = Rails.cache
    ActionController::Base.perform_caching = true
  end

  teardown do
    Rails.cache = @previous_cache
    ActionController::Base.cache_store = @previous_store
    ActionController::Base.perform_caching = @previous_caching
    travel_back
  end

  test "scoped lifetime fragments hit but activity buckets refresh with unchanged counters" do
    get account_token_usage_path(@second)
    hits = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      hits << payload[:key] if payload[:hit] && payload[:key].to_s.include?("usage-workspace-v1")
    end
    dashboard_usage(:dashboard_indexing).update_columns(created_at: @report_time - 60.days)
    ActiveSupport::Notifications.subscribed(subscriber, "cache_read.active_support") do
      get account_token_usage_path(@second)
    end
    assert_response :success
    assert_operator hits.length, :>=, 3
    assert_select "[data-lifetime-total][data-value='1045']"
    assert_select "[data-usage-kind='embedding'][data-value='40']"
    assert_select "[data-usage-day='2026-10-20']", count: 0
    assert_equal 1005, css_select("[data-usage-day] td").sum { |cell| cell["data-value"].to_i }
  end

  test "rolling activity and global date labels move without counter changes" do
    get account_token_usage_path(@second)
    get token_usage_path
    original_window = css_select("[data-usage-window]").first.text
    travel_to @report_time + 31.days
    get account_token_usage_path(@second)
    assert_select "[data-usage-day]", count: 0
    assert_select "[data-usage-no-recent]"
    assert_select "[data-lifetime-total][data-value='1045']"
    get token_usage_path
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='1065']"
    refute_equal original_window, css_select("[data-usage-window]").first.text
    assert_equal (@report_time + 31.days).to_date.iso8601, css_select("[data-usage-day]").last["data-usage-day"]
  end

  test "account locale and counter identities remain isolated and global reports never use these fragments" do
    [ [ @first, 20 ], [ @second, 1045 ] ].each do |account, total|
      %i[en fr].each do |locale|
        get account_token_usage_path(account), headers: { "Accept-Language" => locale.to_s }
        assert_select "[data-lifetime-total][data-value='#{total}']"
        assert_select "[data-usage-estimate-caveat]", text: I18n.t("nosia.usage_workspace.estimate_caveat", locale: locale)
      end
    end
    before = @second.reload.updated_at
    @second.update_columns(input_tokens_count: 943, output_tokens_count: 104)
    assert_equal before, @second.reload.updated_at
    get account_token_usage_path(@second)
    assert_select "[data-lifetime-total][data-value='1047']"
    reads = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      reads << payload[:key] if payload[:key].to_s.include?("usage-workspace-v1")
    end
    writes = []
    write_subscriber = ->(_name, _start, _finish, _id, payload) do
      writes << payload[:key] if payload[:key].to_s.include?("usage-workspace-v1")
    end
    ActiveSupport::Notifications.subscribed(write_subscriber, "cache_write.active_support") do
      ActiveSupport::Notifications.subscribed(subscriber, "cache_read.active_support") { get token_usage_path }
    end
    assert_empty writes
    assert_empty reads
    assert_select "[data-lifetime-total][data-value='1067']"
    assert_select "[data-period-total][data-value='1057']"
    experience(:account_users, :overview_owner_second).destroy!
    get account_token_usage_path(@second)
    assert_response :not_found
  end
end
