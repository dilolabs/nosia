require "application_system_test_case"

class ColorThemeTest < ApplicationSystemTestCase
  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "first visit follows the dark system theme and shows the light mode button" do
    visit_with_theme "dark"

    assert_theme "dark"
    assert_nil page.evaluate_script("localStorage.getItem('color-theme')")
  end

  test "first visit follows the light system theme and shows the dark mode button" do
    visit_with_theme "light"

    assert_theme "light"
    assert_nil page.evaluate_script("localStorage.getItem('color-theme')")
  end

  test "the theme button switches modes and remembers the choice on reload" do
    visit_with_theme "dark"

    assert_theme "dark"
    click_button "theme-toggle"
    assert_theme "light"
    assert_equal "light", page.evaluate_script("localStorage.getItem('color-theme')")

    page.refresh

    assert_theme "light"
    click_button "theme-toggle"
    assert_theme "dark"
    assert_equal "dark", page.evaluate_script("localStorage.getItem('color-theme')")
  end

  private
    def visit_with_theme(theme)
      browser = page.driver.browser
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      injected = browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: "localStorage.removeItem('color-theme')")
      visit root_url
      assert_selector "#theme-toggle"
    ensure
      browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: injected.fetch("identifier")) if injected
    end

    def assert_theme(theme)
      if theme == "dark"
        assert_selector "html.dark"
        assert_selector "#theme-toggle-light-icon"
        assert_no_selector "#theme-toggle-dark-icon"
      else
        assert_no_selector "html.dark"
        assert_selector "#theme-toggle-dark-icon"
        assert_no_selector "#theme-toggle-light-icon"
      end
    end
end
