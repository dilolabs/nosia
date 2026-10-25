require "test_helper"
require_relative "../support/dashboard_fixtures"

class TokenUsageWorkspaceShellTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
  end

  teardown { travel_back }

  test "global and scoped reports have one heading and their authorized scope" do
    get token_usage_path, params: { account_id: @foreign.id }
    assert_response :success
    assert_select "main h1", text: I18n.t("nosia.usage.title"), count: 1
    assert_select "[data-usage-workspace] [data-workspace-scope]", text: "All your accounts"
    assert_select "[data-usage-workspace] a[href='#{user_root_path}']"
    assert_select "[data-usage-workspace] a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
    assert_select "#accordion-right-actions, #drawer-right", count: 0

    get account_token_usage_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_select "main h1", count: 1
    assert_select "[data-workspace-scope]", text: "Account: #{@second.name}"
    assert_select "nav[aria-label='Breadcrumb'] a[href='#{account_path(@second)}']"
    assert_select "[data-workspace-back][href='#{account_path(@second)}']"
    assert_select "[data-usage-workspace] a[href='#{new_chat_path}']", count: 0
    assert_select "#accordion-right-actions, #drawer-right", count: 0
    assert_equal @first, @user.reload.first_account
  end

  test "French scope is translated and authored account names are escaped" do
    @second.update_columns(name: "<script>Compte</script>")

    get account_token_usage_path(@second), headers: { "Accept-Language" => "fr" }
    assert_select "[data-workspace-scope]", text: "Compte : #{@second.name}"
    assert_select "main script", count: 0
    refute_match(/translation missing|missing translation/i, response.body)

    get token_usage_path, headers: { "Accept-Language" => "fr" }
    assert_select "[data-workspace-scope]", text: "Tous vos comptes"
  end

  test "no memberships remain a successful zero report rather than a setup replacement" do
    sign_in_overview(experience(:users, :overview_no_account))

    assert_no_enqueued_jobs { get token_usage_path }
    assert_response :success
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='0']"
    assert_select "[data-usage-no-memberships] a[href='#{accounts_path}']"
    assert_select "details", minimum: 1
  end

  test "unrelated tools keep their drawers and Sources keep their existing shell" do
    [ new_chat_path, api_tokens_path ].each do |path|
      get path
      assert_response :success
      assert_select "#accordion-right-actions, #drawer-right", count: 2
    end

    get sources_path
    assert_select "[data-source-workspace]"
    assert_select "#accordion-right-actions, #drawer-right", count: 0
  end
end
