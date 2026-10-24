require "test_helper"
require_relative "../support/dashboard_fixtures"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  include DashboardFixtures

  setup do
    travel_to @report_time
    sign_in_overview
  end

  teardown { travel_back }

  test "authenticated root renders four panels and reads without creating records or jobs" do
    counts = [ Chat.count, Message.count, Document.count, Prompt.count, TokenUsage.count ]
    clear_enqueued_jobs
    assert_no_enqueued_jobs { get user_root_path }

    assert_response :success
    assert_select "[data-dashboard]", count: 1
    assert_select ".n-dashboard-compose #chat-form[action='#{chats_path}']", count: 1
    assert_select ".n-dashboard-shortcuts a", count: 8
    assert_select ".n-dashboard-recent-list [data-conversation-id]", count: 5
    assert_select "[data-period-total][data-value='1057']"
    assert_select "[data-lifetime-total][data-value='1065']"

    report = TokenUsage::Report.new(accounts: @user.accounts, now: @report_time)
    days = css_select("details table tbody tr[data-usage-day]")
    assert_equal report.daily_totals.keys, days.map { |row| Date.iso8601(row["data-usage-day"]) }
    assert_equal report.daily_totals, days.to_h { |row| [ Date.iso8601(row["data-usage-day"]), row.at_css("td")["data-value"].to_i ] }
    assert_select "#accordion-right-actions, #drawer-right", count: 0
    assert_equal counts, [ Chat.count, Message.count, Document.count, Prompt.count, TokenUsage.count ]
  end

  test "explicit composer selection preserves global totals and default-account tool destinations" do
    get user_root_path, params: { account_id: @second.id, model: "overview-test-model" }

    assert_response :success
    assert_select "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
    assert_select "input[name='chat[model]'][value='overview-test-model']"
    assert_select "[data-period-total][data-value='1057']"
    expected = { accounts: accounts_path, sources: sources_path, usage: token_usage_path,
      profile: profile_path, skills: agent_skills_path, tokens: api_tokens_path,
      mcp: mcp_servers_path, prompts: system_prompts_path }
    expected.each do |key, path|
      assert_select ".n-dashboard-shortcuts a[data-dashboard-destination='#{key}'][href='#{path}']", count: 1
    end
    %w[sources skills mcp].each do |key|
      assert_select "[data-dashboard-destination='#{key}']", text: /#{Regexp.escape(@first.name)}/
    end
    assert_equal @first, @user.first_account
    assert_select ".n-dashboard-compose [data-controller=dropzone][data-dropzone-account-id-value='#{@second.id}']"
    assert_select ".n-dashboard-compose [data-dropzone-target=container]", text: "Upload knowledge sources"
  end

  test "recent previews are personal escaped bounded and unchanged in storage" do
    chat = experience(:chats, :overview_first_chat)
    message = experience(:messages, :overview_first_question)
    content = "Résumé détaillé " * 30
    message.update_columns(content: content)
    chat.update_columns(updated_at: @report_time)
    @first.update_columns(name: "<script>Research</script>")

    get user_root_path

    assert_select "[data-conversation-id='#{chat.id}'] a", text: "#{content.strip[0, 119]}…"
    assert_select "main script", count: 0
    assert_select "[data-conversation-id='#{experience(:chats, :overview_member_chat).id}']", count: 0
    assert_select "[data-conversation-id='#{experience(:chats, :overview_foreign_chat).id}']", count: 0
    assert_select "[data-conversation-id='#{experience(:chats, :overview_child_chat).id}']", count: 0
    assert_equal content, message.reload.content

    experience(:account_users, :overview_owner_second).destroy!
    get user_root_path

    assert_select ".n-dashboard-recent-list [data-conversation-id]", count: 1
    assert_select "[data-period-total][data-value='12']"
  end

  test "no-account users can use the dashboard and all shortcut tiles remain actionable" do
    sign_in_overview(experience(:users, :overview_no_account))

    get user_root_path

    assert_response :success
    assert_select "[data-chat-no-account]", count: 1
    assert_select "lexxy-editor, [data-controller=dropzone]", count: 0
    assert_select "[data-period-total][data-value='0']"
    assert_select ".n-dashboard-shortcuts a", count: 8
    %w[sources skills mcp].each do |key|
      assert_select "[data-dashboard-destination='#{key}'][href='#{accounts_path}']"
    end
    assert_select "[data-dashboard-destination='profile'][href='#{profile_path}']"
    assert_select ".n-dashboard-recent-list [data-conversation-id]", count: 0
  end

  test "both locales render dashboard labels without missing translations" do
    %i[en fr].each do |locale|
      get user_root_path, headers: { "Accept-Language" => locale.to_s }

      assert_response :success
      assert_select "h1", text: I18n.t("nosia.dashboard.welcome", locale: locale)
      assert_select "a[data-dashboard-destination='mcp']", text: /#{Regexp.escape(I18n.t("nosia.dashboard.destinations.mcp", locale: locale))}/
      { "period-total" => 1057, "period-input" => 952, "period-output" => 105, "lifetime-total" => 1065 }.each do |attribute, value|
        assert_select "[data-#{attribute}]", text: ActiveSupport::NumberHelper.number_to_delimited(value, locale: locale)
      end
      refute_match(/translation missing|missing translation/i, response.body)
    end
  end

  test "members with no usage or conversations still have a composer and useful empty panels" do
    user = experience(:users, :overview_no_account)
    experience(:account_users, :overview_member_second).update_columns(user_id: user.id, account_id: @empty.id)
    sign_in_overview(user)

    get user_root_path

    assert_response :success
    assert_select "lexxy-editor", count: 1
    assert_select "[data-chat-no-account]", count: 0
    assert_select "[data-period-total][data-value='0']"
    assert_select "[data-lifetime-total][data-value='0']"
    assert_select ".n-dashboard-recent-list [data-conversation-id]", count: 0
    assert_select "p", text: I18n.t("nosia.dashboard.no_conversations")
    assert_select "[data-dashboard-destination='sources'][href='#{sources_path}']"
  end

  test "signed-out root and non-dashboard conversation drawers remain unchanged" do
    get new_chat_path
    assert_select "#accordion-right-actions, #drawer-right", count: 2

    delete logout_path
    get root_path

    assert_response :success
    assert_select "[data-dashboard]", count: 0
    assert_select "form[action='#{login_path}']", count: 1
  end
end
