require "test_helper"
require_relative "../support/chat_account_fixtures"

class HeaderNavigationTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  %w[en fr].each do |locale|
    test "account headers omit search and preserve controls in #{locale}" do
      sign_in_picker_user

      [ user_root_url, new_chat_url(account_id: @second.id), chat_url(chats(:picker_second_chat)) ].each do |url|
        get url, headers: { "Accept-Language" => locale }

        assert_header_without_search(locale: locale, signed_in: true)
      end
    end

    test "no-account headers omit search and preserve controls in #{locale}" do
      sign_in_picker_user(users(:picker_no_account))

      [ user_root_url, new_chat_url ].each do |url|
        get url, headers: { "Accept-Language" => locale }

        assert_header_without_search(locale: locale, signed_in: true)
      end
    end

    test "anonymous headers omit search and preserve controls in #{locale}" do
      get root_url, headers: { "Accept-Language" => locale }

      assert_header_without_search(locale: locale, signed_in: false)
    end
  end

  test "the application importmap omits the removed search dependency" do
    get root_url

    assert_response :success
    assert_select "script[type=importmap]", count: 1 do |scripts|
      imports = JSON.parse(scripts.first.content).fetch("imports")

      refute imports.key?("@tailwindplus/elements")
      %w[application @hotwired/turbo-rails @hotwired/stimulus flowbite lexxy].each do |name|
        assert imports.key?(name), "Expected shared import #{name} to remain"
      end
    end
  end

  private
    def assert_header_without_search(locale:, signed_in:)
      assert_response :success
      assert_select "html[lang='#{locale}']"
      assert_select "#toggleSidebarMobileSearch", count: 0
      assert_select "[commandfor=dialog]", count: 0
      assert_select "dialog#dialog", count: 0
      assert_select "el-command-palette", count: 0

      assert_select "body > nav", count: 1 do
        assert_select "a[href='#{root_path}'] img", count: 1
        assert_select "form[action='#{language_preference_path}'] select#language_preference_locale", count: 1
        assert_select "#theme-toggle", count: 1
        assert_select "#dropdownUser", count: signed_in ? 1 : 0
        assert_select "#dropdown a[href='#{profile_path}']", count: signed_in ? 1 : 0
        assert_select "#dropdown a[href='#{settings_path}']", count: signed_in ? 1 : 0
        assert_select "#dropdown a[href='#{logout_path}']", count: signed_in ? 1 : 0
      end
    end
end
