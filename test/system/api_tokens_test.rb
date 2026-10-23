require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class ApiTokensTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  setup do
    fixtures = ActiveRecord::FixtureSet.create_fixtures(
      Rails.root.join("test/support/fixtures/chat_accounts").to_s, %w[api_tokens]
    )
    @token = fixtures.first.fixtures.fetch("picker_api_token").find

    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_button "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  [ 375, 768, 1024, 1400 ].each do |width|
    test "the full security notice fits the token card at #{width}px in both themes" do
      visit api_tokens_url
      resize_viewport(width)

      [ false, true ].each do |dark|
        page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
        layout = token_card_layout
        assert layout.fetch("noticeFits"), "The complete security notice must wrap inside its card: #{layout}"
        assert_operator layout.fetch("card").fetch("right"), :<=, width
      end
    end

    test "delete remains reachable with long token and account names at #{width}px in both themes" do
      @token.update!(name: "deployment-#{'x' * 120}")
      @first.update!(name: "Research team with #{'a long account name ' * 8}")
      visit api_tokens_url
      resize_viewport(width)

      [ false, true ].each do |dark|
        page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
        layout = token_card_layout
        assert layout.fetch("deleteFits"), "The delete button must remain inside its card and viewport: #{layout}"
        assert layout.fetch("titleFits"), "The complete token and account names must wrap: #{layout}"
      end

      accept_confirm I18n.t("nosia.actions.confirm_delete", locale: :en) do
        find("form[action='#{api_token_path(@token)}']").click_button "Delete API token"
      end
      assert_no_selector "form[action='#{api_token_path(@token)}']"
      assert_not ApiToken.exists?(@token.id)
    end
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1400)
  end

  private
    def resize_viewport(width)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 1000, deviceScaleFactor: 1, mobile: false)
      assert_equal width, page.evaluate_script("innerWidth")
    end

    def token_card_layout
      form = find("form[action='#{api_token_path(@token)}']", visible: :all)
      page.evaluate_script(<<~JS, form)
        (form => {
          const card = form.closest('.n-card');
          const bounds = card.getBoundingClientRect();
          const main = document.querySelector('main').getBoundingClientRect();
          const fits = rect => rect.left >= bounds.left && rect.right <= bounds.right &&
            rect.top >= bounds.top && rect.bottom <= bounds.bottom &&
            rect.left >= main.left && rect.right <= Math.min(main.right, innerWidth);
          const textFits = element => {
            const range = document.createRange();
            range.selectNodeContents(element);
            return [...range.getClientRects()].every(fits) && element.scrollWidth <= element.clientWidth;
          };
          const button = form.querySelector('button').getBoundingClientRect();
          return {
            card: { left: bounds.left, right: bounds.right },
            noticeFits: textFits(card.querySelector('p')),
            titleFits: textFits(card.querySelector('h2')),
            deleteFits: fits(button),
            button: { left: button.left, right: button.right }
          };
        })(arguments[0])
      JS
    end
end
