require "test_helper"
require_relative "../../support/account_experience_fixtures"

class Accounts::ScopedTokensUsageTest < ActionDispatch::IntegrationTest
  include AccountExperienceFixtures

  setup { sign_in_overview }

  test "token list is both personal and account-specific" do
    get "/accounts/#{@second.id}/api_tokens"
    assert_response :success
    assert_select "h2", text: /second token/
    refute_includes response.body, "member token"
    refute_includes response.body, "first token"
    assert_select "form[action='#{account_api_tokens_path(@second)}']" do
      assert_select "input[type='hidden'][name='api_token[account_id]'][value='#{@second.id}']"
      assert_select "p", text: @second.name
      assert_select "label[for='api_token_account_id']", count: 0
    end
    assert_select "select[name='api_token[account_id]']", count: 0
    token = experience(:api_tokens, :overview_second_token)
    assert_select "form[action='#{account_api_token_path(@second, token)}'] input[value='delete']"
    refute_includes response.body, token.token_digest
  end

  test "token creation fixes the account, preserves invalid values, and reveals the secret once" do
    assert_no_difference "ApiToken.count" do
      post account_api_tokens_path(@second), params: { api_token: { name: "Rejected", account_id: @first.id } }
      assert_response :not_found
    end
    assert_no_difference "ApiToken.count" do
      post account_api_tokens_path(@second), params: { api_token: { name: "" } }
      assert_response :unprocessable_entity
    end
    assert_difference "ApiToken.count", 1 do
      post account_api_tokens_path(@second), params: { api_token: { name: "Research deployment" } }
    end
    assert_redirected_to account_api_tokens_path(@second)
    follow_redirect!
    plain = response.body[%r{value="([A-Za-z0-9]{24})"}, 1]
    assert plain
    token = @user.api_tokens.find_by!(name: "Research deployment", account: @second)
    assert_equal ApiToken.digest(plain), token.token_digest
    assert_select "input[readonly][data-clipboard-target='source'][value='#{plain}']"
    get account_api_tokens_path(@second)
    refute_includes response.body, plain
    refute_includes response.body, token.token_digest
  end

  test "invalid scoped creation preserves the submitted name and fixed account with announced errors" do
    assert_no_difference "ApiToken.count" do
      post account_api_tokens_path(@second), params: { api_token: { name: "  ", account_id: @second.id } }
      assert_response :unprocessable_entity
    end
    assert_select "[role='alert'] li", text: /Name/
    assert_select "form[action='#{account_api_tokens_path(@second)}']" do
      assert_select "input[name='api_token[name]'][value='  ']"
      assert_select "input[type='hidden'][name='api_token[account_id]'][value='#{@second.id}']"
      assert_select "p", text: @second.name
      assert_select "label[for='api_token_account_id']", count: 0
    end
    assert_select "h2", text: /second token/
    refute_includes response.body, "first token"
    refute_includes response.body, "member token"
    assert_select "input[data-clipboard-target='source']", count: 0
  end

  test "owners cannot revoke other members' tokens or tokens from another account" do
    [ experience(:api_tokens, :overview_member_token), experience(:api_tokens, :overview_first_token) ].each do |token|
      assert_no_difference "ApiToken.count" do
        delete account_api_token_path(@second, token)
        assert_response :not_found
      end
    end
    token = experience(:api_tokens, :overview_second_token)
    assert_difference "ApiToken.count", -1 do
      delete account_api_token_path(@second, token)
      assert_redirected_to account_api_tokens_path(@second)
    end
  end

  test "second-account usage is account-wide even with an unrelated ambient tenant" do
    callbacks_before = TokenUsagesController._process_action_callbacks.to_a
    first = @first
    restored_tenant = nil
    # Rails resets CurrentAttributes around requests, so install the ambient
    # tenant inside that boundary and observe it before the executor clears it.
    with_ambient_tenant = ->(_controller, action) do
      ActsAsTenant.with_tenant(first) do
        action.call
        restored_tenant = ActsAsTenant.current_tenant
      end
    end
    TokenUsagesController.around_action with_ambient_tenant, only: :show

    get "/accounts/#{@second.id}/token_usage"
    assert_response :success
    assert_select "section p", text: "900"
    assert_select "section p", text: "100"
    assert_select "section li", text: /1,000/
    assert_equal @first, restored_tenant
    sign_in_overview(@member)
    get account_token_usage_path(@second)
    assert_response :success
    assert_select "section p", text: "900"
    assert_select "section p", text: "100"
    get account_token_usage_path(@foreign)
    assert_response :not_found
  ensure
    TokenUsagesController.skip_around_action with_ambient_tenant, raise: false
    callbacks_after = TokenUsagesController._process_action_callbacks.to_a
    assert_equal callbacks_before, callbacks_after,
      "Callback chain must be restored exactly (#{callbacks_before.size} before, #{callbacks_after.size} after)"
  end

  test "malformed raw scoped filing accounts are rejected before token writes" do
    [ [], {}, [ @second.id ], { id: @second.id }, true, false, "", " " ].each do |bad|
      assert_no_difference "ApiToken.count" do
        post account_api_tokens_path(@second), params: { api_token: { name: "Rejected", account_id: bad } }, as: :json
        assert_response :not_found
      end
    end
  end

  test "malformed raw global filing accounts are rejected before token writes" do
    [ [], {}, [ @second.id ], { id: @second.id }, true, false, "", " " ].each do |bad|
      assert_no_difference "ApiToken.count" do
        post api_tokens_path, params: { api_token: { name: "Rejected", account_id: bad } }, as: :json
        assert_response :not_found
      end
    end
  end

  test "ordinary members may manage only their own scoped tokens" do
    sign_in_overview(@member)
    token = experience(:api_tokens, :overview_member_token)
    owner_token = experience(:api_tokens, :overview_second_token)

    get account_api_tokens_path(@second)
    assert_response :success
    assert_select "h2", text: /member token/
    refute_includes response.body, "second token"
    refute_includes response.body, "first token"
    assert_select "form[action='#{account_api_token_path(@second, token)}']"

    assert_difference "ApiToken.count", 1 do
      post account_api_tokens_path(@second), params: {
        api_token: { name: "Member deployment", account_id: @second.id, user_id: @user.id }
      }
      assert_redirected_to account_api_tokens_path(@second)
    end
    assert @member.api_tokens.exists?(name: "Member deployment", account: @second)
    refute @user.api_tokens.exists?(name: "Member deployment")

    assert_no_difference "ApiToken.count" do
      delete account_api_token_path(@second, owner_token)
      assert_response :not_found
    end
    assert_difference "ApiToken.count", -1 do
      delete account_api_token_path(@second, token)
      assert_redirected_to account_api_tokens_path(@second)
    end
  end

  { owner: :overview_owner_second, member: :overview_member_second }.each do |role, membership|
    test "#{role} membership revoked after login blocks token index creation revocation and usage" do
      sign_in_overview(@member) if role == :member
      token = experience(:api_tokens, role == :owner ? :overview_second_token : :overview_member_token)
      experience(:account_users, membership).destroy!
      assert_equal @user.id, @second.reload.owner_id

      get account_api_tokens_path(@second)
      assert_response :not_found
      refute_includes response.body, token.token_digest
      assert_no_difference "ApiToken.count" do
        post account_api_tokens_path(@second), params: { api_token: { name: "Revoked deployment", account_id: @second.id } }
        assert_response :not_found
        delete account_api_token_path(@second, token)
        assert_response :not_found
      end
      get account_token_usage_path(@second)
      assert_response :not_found
    end
  end

  test "request parameters cannot replace the route account for tokens or usage" do
    token = experience(:api_tokens, :overview_second_token)

    get account_api_tokens_path(@foreign), params: { account_id: @second.id }
    assert_response :not_found
    assert_no_difference "ApiToken.count" do
      post account_api_tokens_path(@foreign), params: {
        account_id: @second.id, api_token: { name: "Foreign deployment", account_id: @second.id }
      }
      assert_response :not_found
      delete account_api_token_path(@foreign, token), params: { account_id: @second.id }
      assert_response :not_found
    end
    get account_token_usage_path(@foreign), params: { account_id: @second.id }
    assert_response :not_found

    get account_api_tokens_path(@second), params: { account_id: @first.id }
    assert_response :success
    assert_select "h2", text: /second token/
    refute_includes response.body, "first token"
  end

  test "global token routes retain the personal account picker and invalid redirect" do
    get api_tokens_path
    assert_response :success
    assert_select "h2", text: /first token/
    assert_select "h2", text: /second token/
    refute_includes response.body, "member token"
    assert_select "form[action='#{api_tokens_path}'] select[name='api_token[account_id]']" do
      assert_select "option[value='#{@first.id}']"
      assert_select "option[value='#{@second.id}']"
      assert_select "option[value='#{@foreign.id}']", count: 0
    end
    assert_select "label[for='api_token_account_id']"

    assert_no_difference "ApiToken.count" do
      post api_tokens_path, params: { api_token: { name: "", account_id: @second.id } }
      assert_redirected_to api_tokens_path
      assert_equal I18n.t("nosia.tokens.error"), flash[:alert]
    end
    token = experience(:api_tokens, :overview_second_token)
    assert_difference "ApiToken.count", -1 do
      delete api_token_path(token)
      assert_redirected_to api_tokens_path
    end
  end

  test "global usage aggregates memberships after viewing a scoped account" do
    get account_token_usage_path(@second)
    assert_response :success
    assert_select "section p", text: "900"

    get token_usage_path
    assert_response :success
    assert_select "#global-lifetime-summary section p", text: "910"
    assert_select "#global-lifetime-summary section p", text: "102"
    assert_select "[data-lifetime-total][data-value='1012']"
  end

  test "cached account fragments remain isolated and global aggregation does not reuse their keys" do
    previous_cache = Rails.cache
    previous_controller_store = ActionController::Base.cache_store
    previous_perform_caching = ActionController::Base.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = Rails.cache
    ActionController::Base.perform_caching = true

    [ [ account_token_usage_path(@first), "10", "2" ],
      [ account_token_usage_path(@second), "900", "100" ],
      [ token_usage_path, "910", "102" ] ].each do |path, input, output|
      get path
      assert_response :success
      assert_select "section p", text: input
      assert_select "section p", text: output
    end

    @second.update_columns(input_tokens_count: 901, output_tokens_count: 101)
    get account_token_usage_path(@second)
    assert_response :success
    assert_select "section p", text: "901"
    assert_select "section p", text: "101"
    get token_usage_path
    assert_response :success
    assert_select "#global-lifetime-summary section p", text: "911"
    assert_select "#global-lifetime-summary section p", text: "103"
  ensure
    Rails.cache = previous_cache
    ActionController::Base.cache_store = previous_controller_store
    ActionController::Base.perform_caching = previous_perform_caching
  end

  test "explicit account summary renders without Current or a session" do
    Current.reset

    html = ApplicationController.render(partial: "token_usages/summary", locals: {
      account: @second,
      token_totals: { input: @second.input_tokens_count, output: @second.output_tokens_count },
      green_summary: { models: [], kwh: 0, co2e_g: 0, fallback_used: false },
      tokens_by_kind: {}, tokens_by_day: {}
    })

    assert_nil Current.session
    fragment = Nokogiri::HTML.fragment(html)
    assert_select fragment, "section p", text: "900"
    assert_select fragment, "section p", text: "100"
  end
end
