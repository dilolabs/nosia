require "test_helper"
require_relative "../support/dashboard_fixtures"

class GlobalTokenUsageTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
  end

  teardown { travel_back }

  test "global report and dashboard agree without changing the default account" do
    get user_root_path, params: { account_id: @second.id }
    assert_select "[data-period-total][data-value='1057']"

    get token_usage_path, params: { account_id: @foreign.id }
    assert_response :success
    assert_select "[data-period-total][data-value='1057']"
    assert_select "[data-lifetime-total][data-value='1065']"
    assert_select "#global-lifetime-summary [data-lifetime-input][data-value='959']"
    assert_select "#global-lifetime-summary [data-lifetime-output][data-value='106']"
    assert_select "li", text: /private-model/, count: 0
    assert_select "details table tbody tr[data-usage-day]", count: 30
    assert_equal @first, @user.first_account
  end

  test "account routes retain their own counters and authorization" do
    get account_token_usage_path(@second)
    assert_response :success
    assert_select "[data-lifetime-input][data-value='942']"
    assert_select "[data-lifetime-output][data-value='103']"
    assert_select "[data-period-total]", count: 0

    get account_token_usage_path(@foreign)
    assert_response :not_found
  end

  test "global reads create no usage or jobs and revoked accounts disappear on the next request" do
    counts = [ Chat.count, Prompt.count, TokenUsage.count ]
    clear_enqueued_jobs
    assert_no_enqueued_jobs { get token_usage_path }
    assert_response :success
    assert_equal counts, [ Chat.count, Prompt.count, TokenUsage.count ]

    experience(:account_users, :overview_owner_second).destroy!
    get token_usage_path
    assert_select "[data-period-total][data-value='12']"
    assert_select "[data-lifetime-total][data-value='20']"
  end

  test "global report renders without a default account and restores any ambient tenant" do
    callbacks_before = TokenUsagesController._process_action_callbacks.to_a
    first = @first
    restored_tenant = nil
    # Observe restoration inside Rails' CurrentAttributes request boundary.
    with_ambient_tenant = ->(_controller, action) do
      ActsAsTenant.with_tenant(first) do
        action.call
        restored_tenant = ActsAsTenant.current_tenant
      end
    end
    TokenUsagesController.around_action with_ambient_tenant, only: :show

    get token_usage_path
    assert_response :success
    assert_select "[data-period-total][data-value='1057']"
    assert_equal @first, restored_tenant

    sign_in_overview(experience(:users, :overview_no_account))
    get token_usage_path
    assert_response :success
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='0']"
  ensure
    TokenUsagesController.skip_around_action with_ambient_tenant, raise: false
    assert_equal callbacks_before, TokenUsagesController._process_action_callbacks.to_a
  end
end
