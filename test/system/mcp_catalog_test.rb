require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class McpCatalogSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  { "en" => "English", "fr" => "Français" }.each do |locale, language|
    [ 375, 768, 1400 ].each do |width|
      test "kChat configuration is fully displayed at #{width}px in #{locale}" do
        if locale == "fr"
          select language, from: "language_preference_locale"
          click_button "Apply"
        end
        assert_selector "html[lang=#{locale}]"
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 844, deviceScaleFactor: 1, mobile: false)
        visit mcp_catalog_url("kchat")
        assert_selector 'input[name="config[kchat_team_name]"]'

        [ false, true ].each do |dark|
          page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
          assert_configuration_fits_card
        end
      end
    end
  end

  test "kChat activation remains reachable above mobile navigation" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false)
    visit mcp_catalog_url("kchat")
    fill_in "config[kchat_token]", with: "test-token"
    fill_in "config[kchat_team_name]", with: "test-team"
    find('input[name="config[kchat_team_name]"]').send_keys(:tab)
    assert_selector ".n-card a:focus", text: "Cancel"
    page.driver.browser.action.send_keys(:tab).perform
    assert_selector '.n-card input[type="submit"]:focus'
    page.execute_script("const main = document.querySelector('main'); main.scrollTop = main.scrollHeight")

    assert page.evaluate_script(<<~JS), "The complete activation button must be visible and unobscured after scrolling"
      (() => {
        const button = document.querySelector('.n-card input[type=submit]');
        const rect = button.getBoundingClientRect();
        return rect.left >= 0 && rect.right <= innerWidth && rect.top >= 0 && rect.bottom <= innerHeight &&
          [rect.top + 2, rect.bottom - 2].every(y => document.elementFromPoint((rect.left + rect.right) / 2, y) === button);
      })()
    JS
  end

  private
    def assert_configuration_fits_card
      layout = page.evaluate_script(<<~JS)
        (() => {
          const card = document.querySelector('.n-card');
          const bounds = card.getBoundingClientRect();
          const box = element => {
            const { left, right } = element.getBoundingClientRect();
            return { left, right };
          };
          return {
            card: box(card), viewport: innerWidth, overflow: card.scrollWidth - card.clientWidth,
            controls: [...card.querySelectorAll('form, input:not([type=hidden]), a')].map(box),
            copyFits: [...card.querySelectorAll('h2, h3, p, label')].every(element => {
              const range = document.createRange();
              range.selectNodeContents(element);
              return [...range.getClientRects()].every(line => line.left >= bounds.left && line.right <= bounds.right);
            })
          };
        })()
      JS

      assert_equal 0, layout.fetch("overflow"), "The card must not clip its contents: #{layout.to_json}"
      assert_operator layout.fetch("card").fetch("left"), :>=, 0
      assert_operator layout.fetch("card").fetch("right"), :<=, layout.fetch("viewport")
      layout.fetch("controls").each do |control|
        assert_operator control.fetch("left"), :>=, layout.fetch("card").fetch("left")
        assert_operator control.fetch("right"), :<=, layout.fetch("card").fetch("right")
      end
      assert layout.fetch("copyFits"), "The complete configuration instructions must wrap inside the card"
    end
end
