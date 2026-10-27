require "application_system_test_case"
require_relative "../support/mcp_workspace_fixtures"
require_relative "../support/mcp_browser_checks"

# Exercises account-scoped MCP management with local integrations only.
class McpWorkspaceSystemTest < ApplicationSystemTestCase
  include McpWorkspaceFixtures
  include McpBrowserChecks

  setup do
    assert_equal McpBrowserChecks::DRIVER, Capybara.current_driver
    assert_same @mcp_session, page
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  test "all six pages meet the 96-state base layout matrix" do
    @second_server.update!(status: "ready", name: "CompteDeRecherche" * 12)
    screens = {
      servers: account_mcp_servers_path(@second),
      catalog: account_mcp_catalog_index_path(@second),
      setup: account_mcp_catalog_path(@second, "kdrive"),
      detail: account_mcp_server_path(@second, @second_server),
      new: new_account_mcp_server_path(@second),
      edit: edit_account_mcp_server_path(@second, @second_server)
    }
    states = []
    puts "MCP matrix evidence: #{@mcp_evidence}"
    [ "en", "fr" ].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang=#{locale}]"
      screens.each do |screen, path|
        [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
          [ "light", "dark" ].each do |theme|
            visit path
            mcp_size(width, height)
            mcp_theme(theme)
            assert_selector "[data-mcp-workspace] h1", count: 1
            assert_selector "[data-mcp-workspace] > header.n-workspace-header", count: 1
            assert_selector "[data-mcp-workspace] > header nav", count: 1
            assert_no_selector "[data-mcp-workspace] [data-controller~='drawer']", visible: :all
            assert_no_selector ".translation_missing", visible: :all
            refute_match(/translation missing/i, page.html)
            refute_includes page.html, "saved-secret"
            mcp_layout
            mcp_keyboard_walk
            mcp_contrast("keyboard")
            mcp_hover
            page.execute_script("document.querySelector('main').scrollTop = 0")
            mcp_wait
            if [ 375, 1440 ].include?(width)
              page.save_screenshot(File.join(@mcp_evidence, "#{screen}-#{locale}-#{width}-#{height}-#{theme}.png"))
            end
            states << { screen: screen, locale: locale, width: width, height: height, theme: theme }
            File.write(File.join(@mcp_evidence, "matrix.json"), { states: states, native_200_percent_zoom: "UNVERIFIED",
              input_capability_emulation: McpBrowserChecks::INPUT_FLAG, physical_hardware_proof: false }.to_json)
          end
        end
      end
    end
    assert_equal 96, states.size
    assert_equal 96, states.uniq.size
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit screens.fetch(:detail)
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    assert page.evaluate_script("Array.from(document.querySelectorAll('[data-mcp-workspace] a,[data-mcp-workspace] button')).every(e=>getComputedStyle(e).transitionDuration==='0s')")
    assert_equal @first, @user.reload.first_account
  end

  test "manual tabs preserve keyboard hash history without executing capabilities" do
    @second_server.update!(status: "ready")
    before = [ Chat.count, Prompt.count ]
    @health_check = ->(_) { flunk "Capability browsing must not test a connection" }
    assert_no_enqueued_jobs do
      with_singleton_replacement(McpWorkspaceFixtures::EchoTool, :call, ->(**) { flunk "Capability browsing must not execute tools" }) do
        path = account_mcp_server_path(@second, @second_server)
        visit path
        mcp_tab_to("#mcp-tab-overview")
        mcp_assert_focus
        page.send_keys(:right)
        assert_selector "#mcp-tab-tools:focus[aria-selected=false]"
        assert_selector "#mcp-tab-overview[aria-selected=true]"
        page.send_keys(:enter)
        assert_selector "#mcp-tab-tools[aria-selected=true]"
        assert_selector "#tools[role=tabpanel]", text: "workspace_echo"
        assert_equal "tools", URI(page.current_url).fragment
        page.refresh
        assert_selector "#mcp-tab-tools[aria-selected=true]"
        mcp_tab_to("#mcp-tab-tools")
        page.send_keys(:end)
        assert_selector "#mcp-tab-resources:focus[aria-selected=false]"
        page.send_keys(:space)
        assert_selector "#resources[role=tabpanel]"
        assert_equal "resources", URI(page.current_url).fragment
        page.send_keys(:home)
        assert_selector "#mcp-tab-overview:focus[aria-selected=false]"
        page.send_keys(:enter)
        assert_selector "#overview[role=tabpanel]"
        page.send_keys(:tab)
        assert_selector "#overview:focus"
        page.send_keys([ :shift, :tab ])
        assert_selector "#mcp-tab-overview:focus"
        page.go_back
        assert_current_path path, ignore_query: true
        assert_equal "resources", URI(page.current_url).fragment
        assert_selector "#mcp-tab-resources[aria-selected=true]"
        assert_selector "#resources[role=tabpanel]"
        page.go_forward
        assert_current_path path, ignore_query: true
        assert_equal "overview", URI(page.current_url).fragment
        assert_selector "#mcp-tab-overview[aria-selected=true]"
        assert_selector "#overview[role=tabpanel]"
        visit "#{path}#unknown"
        assert_selector "#mcp-tab-overview[aria-selected=true]"
        assert_selector "#overview[role=tabpanel]"
      end
    end
    assert_equal before, [ Chat.count, Prompt.count ]
  end

  test "invalid edits focus linked server errors and never echo replacement secrets" do
    visit edit_account_mcp_server_path(@second, @second_server)
    fill_in "mcp_server_name", with: ""
    fill_in "mcp_server_configuration_values_api_key", with: "never-echo-replacement"
    page.execute_script("document.querySelector('[data-mcp-form]').noValidate = true")
    click_button "Save"
    assert_selector "[data-form-errors-target=summary]:focus[role=alert]"
    assert page.evaluate_script("performance.getEntriesByType('resource').some(e=>e.responseStatus===422)")
    assert_no_text "never-echo-replacement"
    refute_includes page.html, "never-echo-replacement"
    assert_field "mcp_server_configuration_values_api_key", with: ""
    mcp_tab_to("[data-error-field=mcp_server_name]")
    mcp_assert_focus
    page.send_keys(:enter)
    assert_selector "#mcp_server_name:focus"
    mcp_assert_focus
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")

    visit new_account_mcp_server_path(@second)
    click_button "Save"
    assert_selector "#mcp_server_name:invalid:focus"
    assert_no_selector "[data-form-errors-target=summary]"
  end

  test "saved configuration busy feedback ignores incomplete unsaved edits" do
    release = Queue.new
    observed = Queue.new
    @health_check = ->(auth) { observed << auth; release.pop }
    visit edit_account_mcp_server_path(@second, @second_server)
    fill_in "mcp_server_name", with: ""
    button_width = find_button("Test saved configuration").native.rect.width
    click_button "Test saved configuration"
    assert_selector "button[disabled]", text: "Testing connection…"
    assert_equal button_width, find_button("Testing connection…", disabled: true).native.rect.width
    release << true
    assert_selector "#connection-test-result[role=status]", text: "Connection established"
    assert_current_path account_mcp_server_path(@second, @second_server)
    assert_selector "[data-workspace-scope]", text: @second.name
    assert_equal "Second tool", @second_server.reload.name
    assert_equal "saved-secret", observed.pop.fetch(:api_key)
  ensure
    release << true
  end

  test "all capability sections remain readable without JavaScript" do
    @second_server.update!(status: "ready")
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit account_mcp_server_path(@second, @second_server)
    %w[overview tools prompts resources].each { |kind| assert_selector "##{kind}" }
    assert_selector "#tools", text: "workspace_echo"
    assert_no_selector "[role=tablist]", visible: :all
  ensure
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
  end

  test "custom create edit delete and catalog add retain explicit account without probes" do
    before = [ Chat.count, Prompt.count ]
    @health_check = ->(_) { flunk "Saving must not test a connection" }
    assert_no_enqueued_jobs do
      with_singleton_replacement(RubyLLM::MCP, :client, ->(**) { flunk "Saving must not create an MCP client" }) do
        visit new_account_mcp_server_path(@second)
        fill_in "mcp_server_name", with: "Browser custom"
        fill_in "mcp_server_endpoint", with: "https://mcp.example.org/mcp"
        mcp_tab_to("[data-mcp-form] input[type=submit]")
        mcp_assert_focus
        page.send_keys(:enter)
        assert_selector "[data-mcp-screen=detail] h1", text: "Browser custom"
        server = @second.mcp_servers.find_by!(name: "Browser custom")
        assert_current_path account_mcp_server_path(@second, server)
        assert_selector "[data-workspace-scope]", text: @second.name
        assert_equal "disconnected", server.status
        visit edit_account_mcp_server_path(@second, server)
        find("summary", text: I18n.t("nosia.mcp_workspace.organization")).click
        fill_in "mcp_server_notes", with: "Public note"
        click_button "Save"
        assert_current_path account_mcp_server_path(@second, server)
        assert_equal "Public note", server.reload.notes
        mcp_tab_to("[data-mcp-danger] button")
        mcp_assert_focus
        accept_confirm { page.send_keys(:enter) }
        assert_current_path account_mcp_servers_path(@second)
        assert_not McpServer.exists?(server.id)

        visit account_mcp_catalog_path(@second, "open_alex")
        mcp_tab_to("[data-mcp-screen=catalog-setup] input[type=submit]")
        mcp_assert_focus
        page.send_keys(:enter)
        assert_selector "[data-mcp-screen=detail] h1", text: "OpenAlex"
        added = @second.mcp_servers.find_by!(name: "OpenAlex")
        assert_current_path account_mcp_server_path(@second, added)
        assert_equal "disconnected", added.status
      end
    end
    assert_equal before, [ Chat.count, Prompt.count ]
    assert_equal @first, @user.reload.first_account
  end

  test "catalog server errors retain public fields while snapshot and history clear secrets" do
    @second_server.update!(metadata: { engine: "workspace-demo" })
    path = account_mcp_catalog_path(@second, "workspace-demo")
    visit path
    fill_in "config_team", with: "Retained team"
    page.execute_script("document.querySelector('[data-mcp-screen=catalog-setup] form').noValidate = true")
    click_button "Add to account"
    assert_selector "[data-form-errors-target=summary]:focus[role=alert]"
    assert page.evaluate_script("performance.getEntriesByType('resource').some(e=>e.responseStatus===422)")
    assert_field "config_team", with: "Retained team"
    assert_field "config_api_key", with: ""
    mcp_tab_to("[data-error-field=config_api_key]")
    mcp_assert_focus
    page.send_keys(:enter)
    assert_selector "#config_api_key:focus"
    mcp_assert_focus
    fill_in "config_api_key", with: "snapshot-only-fixture-secret"
    # Lifecycle-unit evidence: dispatch the actual Turbo snapshot-cleanup event.
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_field "config_api_key", with: ""
    refute_includes page.html, "snapshot-only-fixture-secret"
    File.write(File.join(@mcp_evidence, "snapshot-lifecycle.json"), { event: "turbo:before-cache", dispatched: true, secret_cleared: true, native_zoom_proof: false }.to_json)
    fill_in "config_api_key", with: "history-only-fixture-secret"
    mcp_tab_to("[data-mcp-screen=catalog-setup] form a[href='#{account_mcp_catalog_index_path(@second)}']")
    page.send_keys(:enter)
    assert_current_path account_mcp_catalog_index_path(@second)
    assert_selector "[data-mcp-screen=catalog]"
    page.go_back
    assert_current_path path
    assert_selector "[data-mcp-screen=catalog-setup]"
    assert_field "config_api_key", with: ""
    refute_includes page.html, "history-only-fixture-secret"
    assert_selector "meta[name=turbo-cache-control][content=no-cache]", visible: :all
  end

  test "filtered empty and account empty states retain scoped recovery links" do
    count = @second.mcp_servers.count
    visit account_mcp_servers_path(@second)
    assert_selector ".n-mcp-rows > li", count: count
    select I18n.t("nosia.mcp.status.ready"), from: "status"
    click_button "Apply filters"
    assert_selector "[data-mcp-filtered-empty]"
    assert_no_selector ".n-mcp-rows > li"
    within("[data-mcp-filtered-empty]") { click_link "Reset filters" }
    assert_current_path account_mcp_servers_path(@second)
    assert_selector ".n-mcp-rows > li", count: count
    assert_equal count, @second.mcp_servers.count
    ActsAsTenant.with_tenant(@second) { @second_server.destroy! }
    visit account_mcp_servers_path(@second)
    assert_text "No MCP servers yet"
    assert_no_selector "[data-mcp-filtered-empty]"
    assert_link "Browse catalog", href: account_mcp_catalog_index_path(@second)
    assert_link "Add custom server", href: new_account_mcp_server_path(@second)
  end

  test "desktop New chat opens the explicit account composer without creating a chat" do
    before = Chat.count
    mcp_size(1440, 1000)
    visit account_mcp_servers_path(@second)
    mcp_tab_to("[data-mcp-workspace] header a[href='#{new_chat_path(account_id: @second.id)}']")
    mcp_assert_focus
    page.send_keys(:enter)
    assert_current_path new_chat_path(account_id: @second.id)
    assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
    assert_equal before, Chat.count
    assert_equal @first, @user.reload.first_account
  end

  test "every catalog title opens its exact setup by keyboard without side effects" do
    before = [ McpServer.count, Chat.count, Prompt.count ]
    @health_check = ->(_) { flunk "Catalog GET must not test a connection" }
    assert_no_enqueued_jobs do
      with_singleton_replacement(RubyLLM::MCP, :client, ->(**) { flunk "Catalog GET must not create an MCP client" }) do
        McpCatalog.all.each do |entry|
          visit account_mcp_catalog_index_path(@second)
          mcp_tab_to("[data-mcp-entry='#{entry.fetch(:id)}'] h3 a")
          mcp_assert_focus
          page.send_keys(:enter)
          assert_current_path account_mcp_catalog_path(@second, entry.fetch(:id))
          assert_selector "[data-mcp-screen=catalog-setup] h1", text: entry.fetch(:name)
        end
      end
    end
    assert_equal before, [ McpServer.count, Chat.count, Prompt.count ]
  end

  test "new transport selection retains command text without submitting or executing" do
    previous_stdio = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    visit new_account_mcp_server_path(@second)
    select I18n.t("nosia.mcp.transport.stdio"), from: "mcp_server_transport_type"
    assert_field "mcp_server_command", disabled: false
    assert_no_selector "#mcp_server_endpoint"
    assert_selector "#mcp_server_endpoint[disabled]", visible: :all
    fill_in "mcp_server_command", with: "must-not-execute"
    fill_in "mcp_server_args", with: "--one\ntwo words"
    select I18n.t("nosia.mcp.transport.sse"), from: "mcp_server_transport_type"
    assert_field "mcp_server_endpoint", disabled: false
    assert_no_selector "#mcp_server_command"
    assert_selector "#mcp_server_command[disabled]", visible: :all
    assert_equal "must-not-execute", find("#mcp_server_command", visible: :all).value
    assert_equal "--one\ntwo words", find("#mcp_server_args", visible: :all).value
  ensure
    previous_stdio.nil? ? ENV.delete("MCP_STDIO_ENABLED") : ENV["MCP_STDIO_ENABLED"] = previous_stdio
  end

  test "empty capability lists and unavailable discovery have different counts and copy" do
    Engines::Registry.register(Engines::Registration.new(id: "workspace-empty", name: "Workspace empty", icon: "test",
      description: "Local empty fixture", required_config: [], tool_classes: [], capabilities: [ "tools" ], health_check: ->(_) { }))
    @second_server.update!(status: "ready", metadata: { engine: "workspace-empty" })
    visit "#{account_mcp_server_path(@second, @second_server)}#tools"
    assert_selector "#mcp-tab-tools", exact_text: "Tools · 0"
    assert_selector "#tools", text: I18n.t("nosia.mcp_workspace.no_items")
    assert_no_text I18n.t("nosia.mcp_workspace.unavailable")
    @second_server.update!(metadata: { engine: "workspace-unknown" })
    page.refresh
    assert_selector "#mcp-tab-tools", exact_text: "Tools · #{I18n.t('nosia.mcp_workspace.count_unavailable')}"
    assert_selector "#tools", text: I18n.t("nosia.mcp_workspace.unavailable")
    assert_no_text I18n.t("nosia.mcp_workspace.no_items")
  end

  test "connection checks disable conflicting actions and restore enhanced tabs" do
    release = Queue.new
    @health_check = ->(_) { release.pop }
    @second_server.update!(status: "ready")
    visit account_mcp_server_path(@second, @second_server)
    click_button "Test connection"
    assert_selector "[data-mcp-busy-group][aria-busy=true]"
    assert_button "Disconnect", disabled: true
    release << true
    assert_selector "#connection-test-result[role=status]", text: "Connection established"
    assert_button "Disconnect", disabled: false
    assert_no_selector "[data-mcp-busy-group][aria-busy=true]"
    assert_selector "[role=tablist]"
    assert_selector "#mcp-tab-overview[role=tab][aria-selected=true]"
  ensure
    release << true
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

  test "local edit keeps credential controls active and forms fit phone and desktop" do
    [ "en", "fr" ].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang=#{locale}]"
      [ 375, 1400 ].each do |width|
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 844, deviceScaleFactor: 1, mobile: false)
        [ new_account_mcp_server_path(@second), edit_account_mcp_server_path(@second, @second_server) ].each do |path|
          visit path
          assert_selector "[data-mcp-workspace] h1", count: 1
          assert_equal find("main h1").text, page.title
          if path == edit_account_mcp_server_path(@second, @second_server)
            assert_field "mcp_server_configuration_values_team", with: "Research", disabled: false
            assert_field "mcp_server_configuration_values_api_key", with: "", disabled: false
            assert_no_selector "select[name='mcp_server[transport_type]']"
            assert_button I18n.t("nosia.mcp_workspace.saved_test", locale: locale)
          end

          [ false, true ].each do |dark|
            page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
            page.execute_script("document.querySelector('main').scrollTop = 0")
            assert page.evaluate_script(<<~JS), "Form controls and help rail must fit at #{width}px in #{locale}"
              (() => {
                const main = document.querySelector('main');
                return main.scrollWidth <= main.clientWidth + 1 &&
                  [...document.querySelectorAll('[data-mcp-workspace] input:not([type=hidden]), [data-mcp-workspace] select, [data-mcp-workspace] textarea, .n-mcp-form-layout > aside')]
                    .filter(element => element.getClientRects().length)
                    .every(element => {
                      const rect = element.getBoundingClientRect();
                      return rect.left >= 0 && rect.right <= innerWidth && element.scrollWidth <= element.clientWidth + 1;
                    });
              })()
            JS
            page.save_screenshot(Rails.root.join("tmp/screenshots/mcp-form-#{path.include?('edit') ? 'edit' : 'new'}-#{locale}-#{width}-#{dark ? 'dark' : 'light'}.png"))
            page.execute_script("const main = document.querySelector('main'); main.scrollTop = main.scrollHeight")
            assert page.evaluate_script(<<~JS), "The complete Save control must remain reachable after scrolling"
              (() => {
                const button = document.querySelector('[data-mcp-form] input[type=submit]');
                const rect = button.getBoundingClientRect();
                return rect.left >= 0 && rect.right <= innerWidth && rect.top >= 0 && rect.bottom <= innerHeight &&
                  [rect.top + 2, rect.bottom - 2].every(y => document.elementFromPoint((rect.left + rect.right) / 2, y) === button);
              })()
            JS
            page.save_screenshot(Rails.root.join("tmp/screenshots/mcp-form-#{path.include?('edit') ? 'edit' : 'new'}-#{locale}-#{width}-#{dark ? 'dark' : 'light'}-bottom.png"))
          end
        end
      end
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "transport changes disable irrelevant controls and retain unsaved HTTP credentials" do
    previous_stdio = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp", args: [ "--flag", "value with spaces" ])
    visit edit_account_mcp_server_path(@second, @second_server)
    assert_field "mcp_server_endpoint", disabled: false
    assert page.evaluate_script("document.querySelector('#mcp_server_endpoint').required")
    assert_no_selector "[data-mcp-form-target=stdioFields]"
    assert_selector "#mcp_server_args[disabled]", visible: :all
    fill_in "mcp_server_configuration_values_token", with: "unsaved-http-secret"

    select I18n.t("nosia.mcp.transport.stdio"), from: "mcp_server_transport_type"
    assert_field "mcp_server_args", with: "--flag\nvalue with spaces", disabled: false
    assert_selector "#mcp_server_endpoint[disabled]", visible: :all
    assert_selector "#mcp_server_configuration_values_token[disabled]", visible: :all
    refute page.evaluate_script("document.querySelector('#mcp_server_endpoint').required")

    select I18n.t("nosia.mcp.transport.sse"), from: "mcp_server_transport_type"
    assert_field "mcp_server_configuration_values_token", with: "unsaved-http-secret", disabled: false
    assert_field "mcp_server_endpoint", disabled: false
    assert_selector "#mcp_server_args[disabled]", visible: :all
    assert_equal [ "--flag", "value with spaces" ], @second_server.reload.args
    refute_includes @second_server.auth_config.values, "unsaved-http-secret"
  ensure
    previous_stdio.nil? ? ENV.delete("MCP_STDIO_ENABLED") : ENV["MCP_STDIO_ENABLED"] = previous_stdio
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
