require "test_helper"

class FirstVisitContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "first launch authorizes the theme bootstrap and importmap scripts" do
    get_landing_page

    nonce = response_nonce
    assert_select "meta[name=csp-nonce][content=?]", nonce
    assert_select "script:not([src])", minimum: 3 do |scripts|
      scripts.each { |script| assert_equal nonce, script["nonce"] }
    end
    assert_not_includes response.headers["Content-Security-Policy"][/script-src [^;]+/], "unsafe-inline"
  end

  test "the nonce is stable across requests in the same browser session" do
    get_landing_page
    nonce = response_nonce

    get_landing_page

    assert_equal nonce, response_nonce
  end

  test "new browser sessions receive different nonces" do
    get_landing_page
    nonce = response_nonce
    other_browser = open_session

    other_browser.get root_url

    other_nonce = other_browser.response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]
    assert other_nonce.present?
    assert_not_equal nonce, other_nonce
  end

  private
    def get_landing_page
      get root_url
      follow_redirect! if response.redirect?
      assert_response :success
    end

    def response_nonce
      nonce = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]
      assert nonce.present?, "expected a non-empty nonce, including before a session cookie exists"
      nonce
    end
end
