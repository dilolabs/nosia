require "test_helper"
require_relative "../support/chat_account_fixtures"

class LanguagePreferencesControllerTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  test "anonymous override survives navigation and Automatic removes it" do
    patch "/language_preference", params: { locale: "fr", return_to: "/?source=header" }

    assert_response :see_other
    assert_redirected_to "/?source=header"
    follow_redirect!
    assert_select "html[lang=fr]"
    assert_select "select[name=locale] option[value=fr][selected]"

    get root_url, headers: { "Accept-Language" => "en" }
    assert_select "html[lang=fr]"

    patch "/language_preference", params: { locale: "auto", return_to: "/" }
    assert_response :see_other
    get root_url, headers: { "Accept-Language" => "en" }
    assert_select "html[lang=en]"
    assert_select "select[name=locale] option[value=auto][selected]"

    get root_url, headers: { "Accept-Language" => "fr" }
    assert_select "html[lang=fr]"
  end

  test "invalid writes and external return paths are safe" do
    patch "/language_preference", params: { locale: "xx", return_to: "/" }

    assert_response :unprocessable_entity
    get root_url, headers: { "Accept-Language" => "fr" }
    assert_select "html[lang=fr]"

    [ "https://evil.example/", "//evil.example/", "/\\evil.example/", "https://www.example.com:8443/", [ "/" ], { path: "/" } ].each do |target|
      patch "/language_preference", params: { locale: "en", return_to: target }

      assert_response :see_other
      assert_redirected_to root_url
    end
  end

  test "invalid choices preserve a valid override and return a localized message" do
    patch "/language_preference", params: { locale: "fr" }
    original_cookie = cookies[:locale]

    [ "xx", "FR", "en-US", "", nil, [ "en" ], { value: "en" } ].each do |locale|
      patch "/language_preference", params: { locale: locale }, headers: { "Accept-Language" => "en" }

      assert_response :unprocessable_entity
      assert_equal "Préférence de langue non valide.", response.body
      assert_equal original_cookie, cookies[:locale]
    end

    get root_url, headers: { "Accept-Language" => "en" }
    assert_select "html[lang=fr]"
    assert_select "select[name=locale] option[value=fr][selected]"
  end

  test "tampered cookies are ignored and selector uses full navigation" do
    cookies[:locale] = "not-a-valid-signed-cookie"
    get root_url, headers: { "Accept-Language" => "fr" }

    assert_select "html[lang=fr]"
    assert_select "form[action='/language_preference'][data-turbo=false]" do
      assert_select "label[for=language_preference_locale]", text: "Langue"
      assert_select "select#language_preference_locale[name=locale]", count: 1
      assert_select "option[value=auto][selected]", text: "Automatique"
      assert_select "option[value=fr]", text: "Français"
      assert_select "option[value=en]", text: "English"
      assert_select "button[type=submit]", text: "Appliquer"
    end
    assert_select "form form", count: 0
    assert_select "body.h-dvh.flex.flex-col"
    assert_select "nav.min-h-16.shrink-0.flex-wrap.gap-2"
    assert_select "body > div.min-h-0.flex-1"
  end

  test "selector preserves the current query and account context" do
    sign_in_picker_user
    path = new_chat_path(account_id: @second.id, source: "header")
    get path

    assert_select "form[action='/language_preference']" do
      assert_select "input[type=hidden][name=return_to][value=?]", path
    end

    patch "/language_preference", params: { locale: "fr", return_to: path }

    assert_response :see_other
    assert_redirected_to path
    follow_redirect!
    assert_select "html[lang=fr]"
    assert_select "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
    assert_select "form form", count: 0
  end

  test "override is independent of login and does not alter API locale" do
    patch "/language_preference", params: { locale: "fr" }
    sign_in_picker_user
    get settings_url
    assert_select "html[lang=fr]"

    delete logout_url
    get root_url
    assert_select "html[lang=fr]"

    post "/api/v1/texts", params: { data: "unchanged" }, headers: { "Authorization" => "Bearer not-a-real-token" }, as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
    assert_equal "en", response.headers["Content-Language"]
  end

  test "HTTPS cookie has required security flags and expiry" do
    https!
    patch "/language_preference", params: { locale: "fr" }
    header = Array(response.headers["Set-Cookie"]).join("\n")

    assert_match(/locale=/, header)
    assert_match(/httponly/i, header)
    assert_match(/samesite=lax/i, header)
    assert_match(/secure/i, header)
    assert_match(/expires=/i, header)
    assert_match(/path=\//i, header)
  end

  test "preference writes do not bypass CSRF protection" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    patch "/language_preference", params: { locale: "fr" }

    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
