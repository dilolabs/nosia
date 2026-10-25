require "test_helper"
require_relative "../support/account_experience_fixtures"

class SourcesWorkspaceShellTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "legacy and scoped lists identify their real account without GET writes" do
    counts = [ Document.count, Text.count, Qna.count, Website.count, TokenUsage.count ]
    assert_no_enqueued_jobs { get sources_path, params: { account_id: @second.id } }
    assert_response :success
    assert_select "[data-source-workspace] h1", text: I18n.t("nosia.sources.title")
    assert_select "[data-workspace-scope]", text: "Default account: #{@first.name}"
    assert_select "#accordion-right-actions, #drawer-right", count: 0
    assert_select "[data-source-workspace] a[href='#{new_chat_path}']", text: I18n.t("nosia.nav.new_chat")
    assert_equal counts, [ Document.count, Text.count, Qna.count, Website.count, TokenUsage.count ]
    get account_sources_path(@second), params: { account_id: @foreign.id }
    assert_response :success
    assert_select "[data-workspace-scope]", text: "Account: #{@second.name}"
    assert_select "[data-source-workspace] a[href='#{new_chat_path}']", count: 0
    assert_equal @first, @user.first_account
  end

  test "no-membership list and legacy new forms show setup rather than controls" do
    sign_in_overview(experience(:users, :overview_no_account))
    paths = [ sources_path ] + SourceRow::TYPES.map { |type| public_send("new_sources_#{type}_path") }
    paths.each do |path|
      assert_no_enqueued_jobs { get path }
      assert_response :success
      assert_select "[data-source-setup]", count: 1
      assert_select "[data-source-workspace] a[href='#{accounts_path}']"
      assert_select "[data-source-workspace] form, [data-source-workspace] [data-controller~='dropzone']", count: 0
    end
    get account_sources_path(@first)
    assert_response :not_found
    get sources_text_path(experience(:texts, :overview_first_text))
    assert_response :not_found
    get edit_sources_text_path(experience(:texts, :overview_first_text))
    assert_response :not_found
  end

  test "shell is localized and drawer suppression does not affect chat pages" do
    get sources_path, headers: { "Accept-Language" => "fr" }
    assert_select "[data-workspace-scope]", text: "Compte par défaut : #{@first.name}"
    refute_match(/translation missing|missing translation/i, response.body)
    get new_chat_path
    assert_response :success
    assert_select "#accordion-right-actions, #drawer-right", count: 2
  end
end
