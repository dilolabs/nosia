require "application_system_test_case"
require "json"
require "tmpdir"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/chat_workspace_browser_checks"

class CompactHeadersSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include ChatWorkspaceBrowserChecks

  setup do
    @original_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.current_window.resize_to(*@original_size) if @original_size
  end

  %w[dashboard account sources saved_chat].each do |route|
    test "global and page headers scroll away together on #{route} with synthetic overflow" do
      visit({ "dashboard" => user_root_path, "account" => account_path(@second),
        "sources" => sources_path, "saved_chat" => chat_path(@chat) }.fetch(route))
      assert_selector "main h1"
      assert_selector "lexxy-editor[connected]" if route == "saved_chat"
      settle_workspace_layout
      page.execute_script("(document.querySelector('[data-application-scroll]') || document.querySelector('main')).scrollTop = 0")
      settle_workspace_layout
      header_record("#{route}-before", header_geometry, screenshot: true)

      # Geometry fixture only: this is not a real long-page workflow or provider call.
      page.execute_script(<<~JS)
        const fixture = document.createElement('div')
        fixture.dataset.headerOverflowFixture = ''
        fixture.style.height = '2200px'
        document.querySelector('main').append(fixture)
      JS
      settle_workspace_layout
      page.execute_script(<<~JS)
        const surface = document.querySelector('[data-application-scroll]') || document.querySelector('main')
        surface.scrollTop = 700
        surface.dispatchEvent(new Event('scroll'))
      JS
      settle_workspace_layout
      geometry = header_geometry
      header_record("#{route}-synthetic-overflow-scrolled", geometry, screenshot: true)

      assert_selector "[data-application-scroll]", count: 1
      assert_operator geometry.fetch("surface").fetch("scrollTop"), :>=, 699, geometry.to_json
      assert_operator geometry.fetch("global").fetch("bottom"), :<=, geometry.fetch("surface").fetch("top"), geometry.to_json
      assert_operator geometry.fetch("heading").fetch("bottom"), :<=, geometry.fetch("surface").fetch("top"), geometry.to_json
      assert_equal 0, geometry.fetch("main").fetch("scrollTop"), geometry.to_json
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  private
    def settle_workspace_layout
      page.evaluate_async_script("const done = arguments[arguments.length - 1]; requestAnimationFrame(() => requestAnimationFrame(done))")
    end

    def header_geometry
      page.evaluate_script(<<~JS)
        (() => {
          const sample = element => ({ ...element.getBoundingClientRect().toJSON(),
            id: element.id, scrollTop: element.scrollTop, scrollHeight: element.scrollHeight, clientHeight: element.clientHeight })
          return { global: sample(document.querySelector('[data-application-header]') || document.querySelector('body > nav')),
            heading: sample(document.querySelector('main h1')), main: sample(document.querySelector('main')),
            surface: sample(document.querySelector('[data-application-scroll]') || document.querySelector('main')),
            syntheticOverflow: !!document.querySelector('[data-header-overflow-fixture]') }
        })()
      JS
    end

    def header_record(label, sample, screenshot: false)
      @header_evidence ||= Dir.mktmpdir("compact-headers-", ENV.fetch("EVIDENCE"))
      context = page.evaluate_script("({ path: location.pathname, locale: document.documentElement.lang, dark: document.documentElement.classList.contains('dark'), viewport: [innerWidth, innerHeight] })")
      entry = context.merge(label: label, sample: sample)
      if screenshot
        entry[:screenshot] = File.join(@header_evidence, "#{label}-#{SecureRandom.hex(4)}.png")
        page.save_screenshot(entry[:screenshot])
      end
      File.open(File.join(@header_evidence, "measurements.jsonl"), "a") { |file| file.puts(entry.to_json) }
      puts "Compact header evidence: #{@header_evidence}; #{entry.to_json}"
    end
end
