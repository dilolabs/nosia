require "test_helper"
require_relative "../support/chat_account_fixtures"

class LocalizationTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  test "anonymous French and English responses identify their locale" do
    [ [ "fr-CA", "fr" ], [ "en-GB", "en" ], [ "de", "en" ] ].each do |header, expected|
      get root_url, headers: { "Accept-Language" => header }

      assert_response :success
      assert_select "html[lang='#{expected}']"
      assert_equal expected, response.headers["Content-Language"]
      vary = response.headers["Vary"].to_s.downcase.split(/,\s*/)
      assert_includes vary, "accept-language"
      assert_includes vary, "cookie"
      assert_equal :en, I18n.locale
    end
  end

  test "API errors remain English for a French browser" do
    post "/api/v1/texts", params: { data: "unchanged" }, headers: {
      "Authorization" => "Bearer not-a-real-token", "Accept-Language" => "fr"
    }, as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
    assert_equal "en", response.headers["Content-Language"]
  end

  test "missing API tokens retain the English plaintext response for a French browser" do
    post "/api/v1/texts", params: { data: "unchanged" }, headers: { "Accept-Language" => "fr" }, as: :json

    assert_response :unauthorized
    assert_equal "HTTP Token: Access denied.\n", response.body
    assert_equal "en", response.headers["Content-Language"]
  end

  test "ordinary query parameters cannot override locale" do
    get root_url, params: { locale: "fr" }, headers: { "Accept-Language" => "en" }

    assert_select "html[lang=en]"
  end
end

class LocaleScopeProbeController < ApplicationController
  allow_unauthenticated_access
  before_action { response.set_header("X-Callback-Locale", I18n.locale.to_s) }

  def index
    response.set_header("Vary", "Accept")
    raise "locale probe" if params[:raise_error]

    render plain: I18n.locale.to_s
  end
end

class LocaleScopeRestorationTest < ActionController::TestCase
  tests LocaleScopeProbeController

  test "scope includes before callbacks and restores after exceptions" do
    with_routing do |routes|
      routes.draw { get "probe" => "locale_scope_probe#index" }
      @request.headers["Accept-Language"] = "fr"
      get :index

      assert_equal "fr", response.body
      assert_equal "fr", response.headers["X-Callback-Locale"]
      assert_includes response.headers["Vary"].downcase.split(/,\s*/), "accept"
      assert_equal :en, I18n.locale
      assert_raises(RuntimeError) { get :index, params: { raise_error: "1" } }
      assert_equal :en, I18n.locale
    end
  end
end
