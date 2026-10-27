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

  test "detail tabs support manual keyboard activation and ordinary focus traversal" do
    visit "#{account_mcp_server_path(@second, @second_server)}#tools"
    assert_selector "#mcp-tab-tools[role=tab][aria-selected=true]"
    assert_selector "#tools[role=tabpanel]"
    assert_no_selector "#overview[role=tabpanel]"

    find("#mcp-tab-tools").click
    page.send_keys(:right)
    assert page.evaluate_script("document.activeElement.id === 'mcp-tab-prompts'")
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    page.send_keys(:space)
    assert_selector "#mcp-tab-prompts[aria-selected=true]"
    assert_equal "#prompts", URI.parse(page.current_url).fragment.prepend("#")

    page.send_keys(:end)
    assert page.evaluate_script("document.activeElement.id === 'mcp-tab-resources'")
    page.send_keys(:right)
    assert page.evaluate_script("document.activeElement.id === 'mcp-tab-overview'")
    page.send_keys(:left)
    assert page.evaluate_script("document.activeElement.id === 'mcp-tab-resources'")
    page.send_keys(:home)
    assert page.evaluate_script("document.activeElement.id === 'mcp-tab-overview'")
    page.send_keys(:enter)
    assert_selector "#mcp-tab-overview[aria-selected=true]"
    page.send_keys(:right)
    page.send_keys(:tab)
    assert page.evaluate_script("document.activeElement.id === 'overview'")
    page.send_keys([ :shift, :tab ])
    assert page.evaluate_script("document.activeElement.id === 'mcp-tab-overview'")

    page.save_screenshot(Rails.root.join("tmp/screenshots/mcp-detail-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: false)
    assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
    page.save_screenshot(Rails.root.join("tmp/screenshots/mcp-detail-mobile.png"))
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "detail tab history restores detail and edit DOM across browser navigation" do
    detail_path = account_mcp_server_path(@second, @second_server)
    edit_path = edit_account_mcp_server_path(@second, @second_server)
    visit detail_path
    assert_selector "#mcp-tab-overview[aria-selected=true]"
    page.execute_script("window.mcpTabRequests = 0; document.addEventListener('turbo:before-fetch-request', () => window.mcpTabRequests += 1)")

    find("#mcp-tab-tools").click
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    assert_selector "#tools[role=tabpanel]"
    assert_equal 0, page.evaluate_script("window.mcpTabRequests")

    page.go_back
    assert_current_path detail_path
    assert_selector "#mcp-tab-overview[aria-selected=true]"
    assert_selector "#overview[role=tabpanel]"
    page.go_forward
    assert_current_path detail_path, ignore_query: true
    assert_equal "tools", URI.parse(page.current_url).fragment
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    assert_selector "#tools[role=tabpanel]"
    assert_equal 0, page.evaluate_script("window.mcpTabRequests")

    within "[data-mcp-screen=detail]" do
      find("a[href='#{edit_path}']").click
    end
    assert_current_path edit_path
    assert_field "mcp_server_name", with: @second_server.name
    assert_no_selector "[data-mcp-screen=detail]"

    page.go_back
    assert_current_path detail_path, ignore_query: true
    assert_equal "tools", URI.parse(page.current_url).fragment
    assert_selector "[data-mcp-screen=detail] h1", text: @second_server.name
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    assert_selector "#tools[role=tabpanel]"
    assert_no_selector "input#mcp_server_name"

    page.go_forward
    assert_current_path edit_path
    assert_field "mcp_server_name", with: @second_server.name
    assert_no_selector "[data-mcp-screen=detail]"

    page.go_back
    assert_current_path detail_path, ignore_query: true
    assert_equal "tools", URI.parse(page.current_url).fragment
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    page.refresh
    assert_current_path detail_path, ignore_query: true
    assert_equal "tools", URI.parse(page.current_url).fragment
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    assert_selector "#tools[role=tabpanel]"

    page.execute_script("location.hash = 'unknown'")
    assert_selector "#mcp-tab-overview[aria-selected=true]"
    assert_selector "#overview[role=tabpanel]"
    page.go_back
    assert_equal "tools", URI.parse(page.current_url).fragment
    assert_selector "#mcp-tab-tools[aria-selected=true]"
    assert_selector "#tools[role=tabpanel]"
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
