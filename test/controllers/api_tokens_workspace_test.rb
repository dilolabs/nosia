require "test_helper"
require_relative "../support/settings_tool_fixtures"

class ApiTokensWorkspaceTest < ActionDispatch::IntegrationTest
  include SettingsToolFixtures

  setup { sign_in_overview }

  test "two bilingual shells preserve personal scope and separate management" do
    %i[en fr].each do |locale|
      [ api_tokens_path, account_api_tokens_path(@second) ].each do |path|
        assert_no_difference [ "ApiToken.count", "Prompt.count", "Chat.count", "AccountUser.count" ] do
          get path, headers: { "Accept-Language" => locale.to_s }
        end
        assert_response :success
        assert_select "main h1", text: I18n.t("nosia.tokens.title", locale: locale), count: 1
        assert_equal css_select("main h1").first.text, css_select("head title").first.text
        assert_select "main .n-workspace-header nav", count: 1
        assert_select "main nav [aria-current=page]", count: 1
        assert_select "[data-token-row]", count: path == api_tokens_path ? 2 : 1
        assert_select "[data-token-row] h3", text: @other_token.name, count: 0
        assert_select "#drawer-right, #accordion-right-actions", count: 0
        assert_select "[data-settings-tool] [data-member-row], [data-settings-tool] textarea[name='prompt[content]']", count: 0
        refute_match(/translation missing|missing translation/i, response.body)
        [ @own_token, @other_token ].each { |token| refute_includes response.body, token.token_digest }
      end
    end
    get api_tokens_path
    assert_select "#api_token_account_id option[value=?]", @foreign.id, count: 0
    assert_select ".n-workspace-header a[href=?]", new_chat_path
    get account_api_tokens_path(@second)
    assert_select "select[name='api_token[account_id]']", count: 0
    assert_select "input[type=hidden][name='api_token[account_id]'][value=?]", @second.id
    assert_select ".n-workspace-header a[href=?]", new_chat_path(account_id: @second.id)
    assert_equal @first, @user.reload.first_account
  end

  test "invalid creation retains submitted name and authorized account without output" do
    %i[en fr].each do |locale|
      [ api_tokens_path, account_api_tokens_path(@second) ].each do |path|
        assert_no_difference("ApiToken.count") do
          post path, params: { api_token: { name: " \n ", account_id: @second.id } }, headers: { "Accept-Language" => locale.to_s }
        end
        assert_response :unprocessable_entity
        assert_select "form[action=?]", path
        assert_select "#api_token_name[aria-invalid=true][aria-describedby='api_token_name_help api_token_name_error']" do |fields|
          assert_equal " \n ", fields.first["value"]
        end
        assert_select "[data-form-errors-target=summary][tabindex='-1'] a[href='#api_token_name']"
        if path == api_tokens_path
          assert_select "#api_token_account_id option[selected][value=?]", @second.id
        end
        assert_select "[data-token-reveal]", count: 0
        assert_nil flash[:created_api_token]
      end
    end
  end

  test "successful global and account creation preserves digest and show-once handoff" do
    [ api_tokens_path, account_api_tokens_path(@second) ].each_with_index do |path, index|
      name = "<script>Deploy #{index}</script>"
      assert_difference("ApiToken.count", 1) do
        post path, params: { api_token: { account_id: @second.id, name: name } }
      end
      assert_redirected_to path
      plain = flash[:created_api_token]
      token = @user.api_tokens.find_by!(name: name)
      assert_equal ApiToken.digest(plain), token.token_digest
      assert_equal token, ApiToken.authenticate_token(plain)
      assert_nil token.plain_token
      follow_redirect!
      assert_select "[data-token-reveal] #created_api_token[value=?][readonly]", plain
      assert_select "[data-token-reveal]", text: /#{Regexp.escape(name)}/
      assert_select "[data-token-reveal]", text: /#{Regexp.escape(@second.name)}/
      assert_select "[data-token-reveal] #created_api_token_status", text: ""
      assert_select "main script", count: 0
      assert_select "meta[name=turbo-cache-control][content=no-cache]"
      assert_equal 1, response.body.scan(plain).size
      refute_includes response.body, token.token_digest
      get path
      assert_select "[data-token-reveal]", count: 0
      refute_includes response.body, plain
      refute_includes response.body, token.token_digest
    end
  end

  test "forged accounts foreign tokens and revoked contexts retain fail-closed boundaries" do
    [ @foreign.id, [ @second.id ], { id: @second.id } ].each do |id|
      assert_no_difference("ApiToken.count") do
        post api_tokens_path, params: { api_token: { account_id: id, name: "forged" } }
      end
      assert_response :not_found
    end
    assert_no_difference("ApiToken.count") do
      post account_api_tokens_path(@second), params: { api_token: { account_id: @first.id, name: "mismatch" } }
    end
    assert_response :not_found
    [ api_token_path(@other_token), account_api_token_path(@second, @other_token) ].each do |path|
      assert_no_difference("ApiToken.count") { delete path }
      assert_response :not_found
    end
    get account_api_tokens_path(@foreign), params: { account_id: @second.id }
    assert_response :not_found
    experience(:account_users, :overview_owner_second).destroy!
    get account_api_tokens_path(@second)
    assert_response :not_found
    assert_no_difference("ApiToken.count") do
      post account_api_tokens_path(@second), params: { api_token: { name: "revoked" } }
    end
    assert_response :not_found
    assert_equal @first, @user.reload.first_account
  end

  test "member manages only own tokens and revocation retains context and authentication semantics" do
    sign_in_overview(@member)
    get account_api_tokens_path(@second)
    assert_select "[data-token-row] h3", text: @other_token.name
    assert_select "[data-token-row] h3", text: @own_token.name, count: 0
    assert_select "form[action=?] button[data-turbo-confirm=?]", account_api_token_path(@second, @other_token), I18n.t("nosia.settings_tools.revoke_confirm", name: @other_token.name, account: @second.name)
    assert_difference("ApiToken.count", -1) { delete account_api_token_path(@second, @other_token) }
    assert_redirected_to account_api_tokens_path(@second)
    assert_equal I18n.t("nosia.settings_tools.token_removed"), flash[:notice]
    assert_nil ApiToken.authenticate_token("overview-member-secret")
    assert @user.api_tokens.exists?(@own_token.id)
  end

  test "no available account replaces only generation while owned tokens stay revocable" do
    @user.account_users.destroy_all
    get api_tokens_path
    assert_response :success
    assert_select "[data-token-setup] a[href=?]", new_account_path
    assert_select "form[action=?] input[name='api_token[name]']", api_tokens_path, count: 0
    assert_select "[data-token-row]", count: 2
    assert_difference("ApiToken.count", -1) { delete api_token_path(@own_token) }
    assert_redirected_to api_tokens_path
    sign_in_overview(@no_account)
    get api_tokens_path
    assert_select "[data-token-empty]", text: I18n.t("nosia.settings_tools.tokens_empty")
    sign_in_overview
    @empty.account_users.grant_to(@user)
    get account_api_tokens_path(@empty)
    assert_select "[data-token-empty]", text: I18n.t("nosia.settings_tools.tokens_empty_account")
    assert_equal 0, @no_account.reload.accounts.count
  end
end
