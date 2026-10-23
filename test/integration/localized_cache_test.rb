require "test_helper"
require_relative "../support/chat_account_fixtures"

class LocalizedCacheTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup do
    sign_in_picker_user
    @previous_cache = Rails.cache
    @previous_controller_store = ActionController::Base.cache_store
    @previous_perform_caching = ActionController::Base.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = Rails.cache
    ActionController::Base.perform_caching = true
    @first.update_columns(input_tokens_count: 1234)
  end

  teardown do
    Rails.cache = @previous_cache
    ActionController::Base.cache_store = @previous_controller_store
    ActionController::Base.perform_caching = @previous_perform_caching
  end

  test "usage fragments isolate translated labels and numbers by locale" do
    get token_usage_url, headers: { "Accept-Language" => "en" }
    assert_response :success
    assert_select "section", text: /1,234/
    assert_select "section", text: /Energy/

    get token_usage_url, headers: { "Accept-Language" => "fr" }
    assert_response :success
    assert_select "h2", text: "Utilisation des jetons et impact environnemental"
    assert_select "section", text: /Énergie/
    assert_select "section", text: /1[ \u00a0\u202f]234/
    refute_includes response.body, "1,234"
    assert_equal 1234, @first.reload.input_tokens_count

    get token_usage_url, headers: { "Accept-Language" => "en" }
    assert_response :success
    assert_select "section", text: /1,234/
    assert_select "section", text: /Energy/
    assert_equal 1234, @first.reload.input_tokens_count
  end
end
