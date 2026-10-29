require "tmpdir"
require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"

# Checks saved-composer clearance above the shared tablet navigation in both themes.
class ChatWorkspaceLayoutTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures

  setup do
    @layout_evidence = Dir.mktmpdir("chat-layout-", ENV.fetch("EVIDENCE", "/tmp/opencode"))
    @original_window_size = page.current_window.size
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"

    page.current_window.resize_to(768, 1024)
    @window_viewport = page.evaluate_script("[innerWidth, innerHeight]")
    if @window_viewport != [ 768, 1024 ]
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: 768, height: 1024, deviceScaleFactor: 1, mobile: false)
      @viewport_override = true
    end
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    page.current_window.resize_to(*@original_window_size) if @original_window_size
    page.execute_script("localStorage.removeItem('color-theme')") if page.current_url.start_with?("http")
    Capybara.reset_sessions!
  end

  %w[light dark].each do |theme|
    test "saved composer help and disclaimer clear tablet navigation in #{theme} theme" do
      visit chat_path(@chat)
      assert_selector ".n-chat-dock .lexxy-editor__content"
      find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script("const done=arguments[0]; requestAnimationFrame(()=>requestAnimationFrame(done));")
      page.execute_script("const surface = document.querySelector('[data-application-scroll]'); surface.scrollTop = surface.scrollHeight; surface.dispatchEvent(new Event('scroll'))")
      page.driver.browser.execute_async_script("const done=arguments[0]; requestAnimationFrame(()=>requestAnimationFrame(done));")

      geometry = composer_geometry
      File.write(File.join(@layout_evidence, "#{theme}-geometry.json"), JSON.pretty_generate(geometry))
      page.save_screenshot(File.join(@layout_evidence, "saved-#{theme}-768x1024.png"))
      puts "Chat layout evidence: #{@layout_evidence}; #{geometry.to_json}"

      assert_equal [ 768, 1024 ], geometry.fetch("viewport")
      assert_equal "application-scroll", geometry.fetch("surface").fetch("id")
      assert_equal 0, geometry.fetch("main").fetch("scrollTop")
      assert_equal 0, geometry.fetch("transcriptScrollTop")
      assert_equal "fixed", geometry.fetch("nav").fetch("position")
      assert geometry.fetch("nav").fetch("visible"), geometry.to_json
      geometry.fetch("composer").each do |sample|
        assert_operator sample.fetch("bounds").fetch("bottom"), :<=, geometry.fetch("nav").fetch("bounds").fetch("top"), sample.to_json
        assert sample.fetch("unobscured"), "Composer text is clipped or covered: #{sample.to_json}"
      end
    end
  end

  private
    def screenshots_dir
      @layout_evidence
    end

    def composer_geometry
      page.evaluate_script(<<~JS, @window_viewport)
        (() => {
          const main = document.querySelector('.n-chat-main'), mainBounds = main.getBoundingClientRect();
          const surface = document.querySelector('[data-application-scroll]');
          const nav = document.querySelector('.n-nav-bottom').closest('.fixed');
          const navBounds = nav.getBoundingClientRect(), navStyle = getComputedStyle(nav);
          const composer = ['.n-composer-meta', '.n-composer-notice'].map(selector => {
            const element = document.querySelector(`.n-chat-dock ${selector}`), bounds = element.getBoundingClientRect();
            const points = [bounds.left + 1, bounds.left + bounds.width / 2, bounds.right - 1].flatMap(x =>
              [bounds.top + 1, bounds.top + bounds.height / 2, bounds.bottom - 1].map(y => {
                const hit = document.elementFromPoint(x, y);
                return {x, y, hit: hit?.outerHTML.slice(0, 200), clear: !!hit && (hit === element || element.contains(hit))};
              }));
            return {selector, bounds: bounds.toJSON(), points,
              unobscured: element.checkVisibility() && bounds.width > 0 && bounds.height > 0 &&
                bounds.left >= Math.max(0, mainBounds.left) && bounds.right <= Math.min(innerWidth, mainBounds.right) &&
                bounds.top >= Math.max(0, mainBounds.top) && bounds.bottom <= Math.min(innerHeight, mainBounds.bottom) &&
                points.every(point => point.clear)};
          });
          return {viewport: [innerWidth, innerHeight], windowResizeViewport: arguments[0],
            dark: document.documentElement.classList.contains('dark'),
            flowMode: matchMedia('(max-width: 639px), (max-height: 700px)').matches,
            surface: {id: surface.id, top: surface.scrollTop, bounds: surface.getBoundingClientRect().toJSON(),
              scrollHeight: surface.scrollHeight, clientHeight: surface.clientHeight},
            transcriptScrollTop: document.querySelector('.n-chat-transcript').scrollTop,
            main: {bounds: mainBounds.toJSON(), paddingBottom: getComputedStyle(main).paddingBottom,
              overflowY: getComputedStyle(main).overflowY, scrollTop: main.scrollTop},
            nav: {bounds: navBounds.toJSON(), position: navStyle.position,
              visible: nav.checkVisibility() && navBounds.width > 0 && navBounds.height > 0}, composer};
        })()
      JS
    end
end
