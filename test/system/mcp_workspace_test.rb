require "application_system_test_case"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceSystemTest < ApplicationSystemTestCase
  include McpWorkspaceFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  test "management rows reflow and catalog-first action works by keyboard" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: false)
    @second_server.update!(name: "CompteDeRecherche" * 16)
    visit account_mcp_servers_path(@second)
    assert_selector "[data-mcp-workspace] h1", count: 1
    assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
    target = ".n-workspace-primary[href='#{account_mcp_catalog_index_path(@second)}']"
    120.times do
      page.send_keys(:tab)
      break if page.evaluate_script("document.activeElement.matches(arguments[0])", target)
    end
    assert page.evaluate_script("document.activeElement.matches(arguments[0])", target)
    assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.activeElement).outlineWidth)"), :>=, 2
    page.send_keys(:enter)
    assert_current_path account_mcp_catalog_index_path(@second)
    assert_equal @first, @user.reload.first_account
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "mobile New chat opens the scoped account composer by keyboard without creating a chat" do
    before = Chat.count
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: false)
    visit account_mcp_servers_path(@second)
    target = ".lg\\:hidden a.n-nav-bottom[aria-label='#{I18n.t('nosia.nav.new_chat')}']"
    assert_selector target, count: 1
    120.times do
      page.send_keys(:tab)
      break if page.evaluate_script("document.activeElement.matches(arguments[0])", target)
    end
    assert page.evaluate_script("document.activeElement.matches(arguments[0])", target)
    page.send_keys(:enter)

    assert_selector "select[name='chat[account_id]']"
    assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
    assert_current_path new_chat_path(account_id: @second.id)
    assert_equal @first, @user.reload.first_account
    assert_equal before, Chat.count
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
