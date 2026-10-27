require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class McpConnectionTestsSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  setup do
    @engines = Engines::Registry.all
    @health_check = ->(auth) { raise "Invalid credentials #{'x' * 160}" if auth[:api_key] == "invalid" }
    Engines::Registry.register(Engines::Registration.new(
      id: "connection-test", name: "Connection test", icon: "test", description: "Connection test",
      required_config: [], tool_classes: [], health_check: ->(auth) { @health_check.call(auth) }
    ))
    @server = mcp_servers(:picker_first_tool)
    ActsAsTenant.with_tenant(@first) do
      @server.update!(status: "disconnected", metadata: { engine: "connection-test" })
    end
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Engines::Registry.clear
    @engines.each { |registration| Engines::Registry.register(registration) }
  end

  test "test button shows a disabled busy state until the connection check finishes" do
    release = Queue.new
    @health_check = ->(_) { release.pop }
    visit mcp_server_url(@server)
    button_width = find_button("Test connection").native.rect.width

    click_button "Test connection"

    assert_selector "button[disabled]", text: "Testing connection…"
    assert_selector "form[aria-busy=true]"
    assert_equal button_width, find_button("Testing connection…", disabled: true).native.rect.width
    release << true
    assert_selector "#connection-test-result[role=status]", text: "Connection established"
    assert_button "Test connection", disabled: false
  ensure
    release << true
  end

  test "results fit small and large screens in both themes and languages" do
    [ "en", "fr" ].each do |locale|
      select(locale.upcase, from: "language_preference_locale")
      assert_selector "html[lang=#{locale}]"

      [ 375, 768, 1400 ].each do |width|
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 844, deviceScaleFactor: 1, mobile: false)
        [ false, true ].each do |failure|
          ActsAsTenant.with_tenant(@first) { @server.update!(api_key: failure ? "invalid" : "valid") }
          visit mcp_server_url(@server)
          click_button(locale == "en" ? "Test connection" : "Tester la connexion")
          assert_selector "#connection-test-result[role=#{failure ? 'alert' : 'status'}]"
          assert_current_path mcp_server_path(@server)
          if failure
            assert_text I18n.t("nosia.mcp.connection_test_failure_help", locale: locale)
            assert_no_text "Invalid credentials"
          else
            assert_text(locale == "en" ? "Response time:" : "Temps de réponse :")
          end

          [ false, true ].each do |dark|
            page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
            assert_test_button_contrast
            assert page.evaluate_script(<<~JS), "The result panel must fit the viewport at #{width}px"
              (() => {
                const panel = document.querySelector('#connection-test-result');
                const rect = panel.getBoundingClientRect();
                return rect.left >= 0 && rect.right <= innerWidth && panel.scrollWidth === panel.clientWidth;
              })()
            JS
          end
        end
      end
    end
  end

  test "testing from edit uses saved configuration without saving incomplete edits" do
    visit edit_mcp_server_url(@server)
    fill_in "mcp_server_name", with: ""

    click_button "Test Connection"

    assert_selector "#connection-test-result[role=status]", text: "Connection established"
    assert_current_path mcp_server_path(@server)
    assert_equal "First tool", @server.reload.name
  end

  private
    def assert_test_button_contrast
      selector = "form[action='#{test_connection_mcp_server_path(@server)}'] button[data-turbo-submits-with]"
      assert_selector selector, text: I18n.t("nosia.mcp.test_connection_short", locale: find("html")[:lang])
      contrast = page.evaluate_script(<<~JS, selector)
        (() => {
          document.getAnimations().forEach(animation => animation.finish());
          const context = document.createElement('canvas').getContext('2d');
          const luminance = color => {
            context.fillStyle = color;
            context.fillRect(0, 0, 1, 1);
            const rgb = [...context.getImageData(0, 0, 1, 1).data].slice(0, 3).map(value => {
              value /= 255;
              return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
            });
            return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
          };
          const button = document.querySelector(arguments[0]);
          const foreground = luminance(getComputedStyle(button).color);
          const background = luminance(getComputedStyle(button).backgroundColor);
          return (Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05);
        })()
      JS
      assert_operator contrast, :>=, 4.5, "Connection test text must remain readable in both themes"
    end
end
