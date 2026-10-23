require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class AccountExperienceSystemTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    visit root_url
    @original_window_size = page.current_window.size
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  teardown do
    if @account_viewport_override
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
    page.current_window.resize_to(*@original_window_size) if @original_window_size
  end

  test "balanced account layout stacks without overflow and permits browser zoom" do
    visit account_path(@second)
    assert_selector "[data-account-overview='#{@second.id}']"
    viewport = find("meta[name='viewport']", visible: :all)["content"]
    refute_match(/maximum-scale|user-scalable\s*=\s*no/, viewport)
    assert_equal "grid", page.evaluate_script("getComputedStyle(document.querySelector('.n-account-columns')).display")

    [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
      resize_account_viewport(width, height)
      assert_selector "a[href='#{new_chat_path(account_id: @second.id)}']", text: "New conversation"
      assert_equal width >= 1280 ? 2 : 1, account_column_count(".n-account-columns"), "Overview columns at #{width}x#{height}"
      assert_main_without_horizontal_overflow
    end
  end

  test "account directory cards adapt without horizontal overflow" do
    visit accounts_path
    assert_selector ".n-account-cards [data-account-id='#{@second.id}']"
    assert_equal "grid", page.evaluate_script("getComputedStyle(document.querySelector('.n-account-cards')).display")

    [ [ 375, 812, 1 ], [ 768, 1024, 2 ], [ 1440, 1000, 3 ], [ 812, 375, 2 ] ].each do |width, height, columns|
      resize_account_viewport(width, height)
      assert_equal columns, account_column_count(".n-account-cards"), "Directory columns at #{width}x#{height}"
      within "[data-account-id='#{@second.id}']" do
        assert_selector "a[href='#{account_path(@second)}']", text: "View account"
        assert_selector "a[href='#{new_chat_path(account_id: @second.id)}']", text: "New conversation"
      end
      assert_main_without_horizontal_overflow
    end
  end

  private
    def resize_account_viewport(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[window.innerWidth, window.innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @account_viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[window.innerWidth, window.innerHeight]")
    end

    def account_column_count(selector)
      page.evaluate_script("getComputedStyle(document.querySelector(arguments[0])).gridTemplateColumns", selector).split.size
    end

    def assert_main_without_horizontal_overflow
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1"),
        "Account content overflows at #{page.evaluate_script('[window.innerWidth, window.innerHeight]').join('x')}"
    end
end
