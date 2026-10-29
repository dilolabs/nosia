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

  test "global bar is compact without shrinking its usable controls" do
    samples = [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ].map do |width, height|
      header_viewport(width, height)
      visit accounts_path
      assert_selector "[data-application-header]"
      header_settle
      sample = page.evaluate_script(<<~JS)
        (() => {
          const nav = document.querySelector('[data-application-header]')
          return { bar: nav.getBoundingClientRect().toJSON(),
            controls: ['a', '#theme-toggle', '#dropdownUser', '#language_preference_locale'].map(selector =>
              ({ selector, geometry: nav.querySelector(selector).getBoundingClientRect().toJSON() })) }
        })()
      JS
      header_record("normal-bar-#{width}x#{height}", sample, screenshot: true)
      sample
    end

    samples.each do |sample|
      assert_operator sample.fetch("bar").fetch("height"), :>=, 48, sample.to_json
      assert_operator sample.fetch("bar").fetch("height"), :<=, 52, sample.to_json
      sample.fetch("controls").each do |control|
        assert_operator control.fetch("geometry").fetch("height"), :>=, 44, control.to_json
        assert_operator control.fetch("geometry").fetch("width"), :>=, 44, control.to_json
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "bar controls retain native language theme and profile navigation" do
    [ [ 375, 812 ], [ 812, 375 ], [ 1400, 375 ] ].each do |width, height|
      header_viewport(width, height)
      %w[en fr].each do |locale|
        visit accounts_path
        select locale.upcase, from: "language_preference_locale"
        assert_selector "html[lang='#{locale}']"

        [ false, true ].each do |dark|
          visit accounts_path
          assert_selector "html[lang='#{locale}']"
          header_theme(dark)
          [ "[data-application-header] a", "#language_preference_locale", "#theme-toggle", "#dropdownUser" ].each do |selector|
            header_tab_to(selector)
          end
          page.driver.browser.action.send_keys(:enter).perform
          assert_selector "#dropdown:not(.hidden)"
          header_tab_to("#dropdown a[href='#{profile_path}']")
          header_record("native-dropdown", {
            menu: find("#dropdown").text,
            controls: page.evaluate_script(<<~JS)
              [...document.querySelectorAll('[data-application-header] a, [data-application-header] button, [data-application-header] select')].map(element =>
                ({ id: element.id, name: element.getAttribute('aria-label') || element.textContent.trim(), value: element.value }))
            JS
          }, screenshot: true)
          page.driver.browser.action.send_keys(:enter).perform
          assert_current_path profile_path
          assert_selector ".n-profile"
          assert_selector "html[lang='#{locale}']"
          assert_equal dark, page.evaluate_script("document.documentElement.classList.contains('dark')")
          assert_selector "main h1", text: I18n.t("nosia.profile.title", locale: locale)
          header_record("native-profile", { heading: find("main h1").text }, screenshot: true)
        end
      end
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  private
    def header_viewport(width, height)
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      page.current_window.resize_to(width, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
    end

    def header_settle
      page.evaluate_async_script("const done = arguments[arguments.length - 1]; requestAnimationFrame(() => requestAnimationFrame(done))")
    end

    def header_top
      page.execute_script(<<~JS)
        const surface = document.querySelector('[data-application-scroll]')
        surface.scrollTop = 0
        surface.dispatchEvent(new Event('scroll'))
      JS
      header_settle
    end

    def header_theme(dark)
      header_top
      find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != dark
      assert_equal dark, page.evaluate_script("document.documentElement.classList.contains('dark')")
      header_settle
    end

    def header_tab_to(selector)
      160.times do
        page.driver.browser.action.send_keys(:tab).perform
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          assert_selector "#{selector}:focus"
          header_settle
          header_hit(selector)
          return
        end
      end
      flunk "Keyboard traversal did not reach #{selector}"
    end

    def header_hit(selector)
      element = find(selector)
      # Measure settled native focus paint, not a transient transition color.
      page.evaluate_async_script(<<~JS, element)
        const element = arguments[0], done = arguments[arguments.length - 1]
        Promise.all(element.getAnimations().map(animation => animation.finished.catch(() => {}))).then(done)
      JS
      sample = page.evaluate_script(<<~JS, element)
        (() => {
          const element = arguments[0], rect = element.getBoundingClientRect(), style = getComputedStyle(element)
          const points = [[rect.x + rect.width / 2, rect.y + rect.height / 2], [rect.left + 2, rect.top + 2], [rect.right - 2, rect.bottom - 2]]
          const hits = points.map(([x, y]) => { const hit = document.elementFromPoint(x, y); return !!hit && (hit === element || element.contains(hit)) })
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
          const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
          const rgba = color => {
            context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data].map(channel => channel / 255)
          }
          const over = (fg, bg) => [...fg.slice(0, 3).map((channel, i) => channel * fg[3] + bg[i] * (1 - fg[3])), 1]
          const chain = []; for (let node = element; node; node = node.parentElement) chain.unshift(node)
          for (const node of chain) {
            const paint = getComputedStyle(node)
            if (paint.backgroundImage !== 'none' || Number(paint.opacity) !== 1 || paint.filter !== 'none' || paint.backdropFilter !== 'none' || paint.mixBlendMode !== 'normal')
              throw new Error('Unmeasured header paint effect')
          }
          const background = chain.map(node => getComputedStyle(node).backgroundColor).reduce((bg, color) => over(rgba(color), bg), [1, 1, 1, 1])
          const foreground = over(rgba(style.outlineColor), background)
          const luminance = color => color.slice(0, 3).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4)
            .reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0)
          const a = luminance(foreground), b = luminance(background)
          const outset = Math.max(0, parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset))
          return { geometry: rect.toJSON(), hits, viewport: [innerWidth, innerHeight],
            focusVisible: element.matches(':focus-visible'), outlineWidth: parseFloat(style.outlineWidth), outlineOffset: parseFloat(style.outlineOffset),
            outlineStyle: style.outlineStyle, borderRadius: style.borderRadius,
            outlineColor: style.outlineColor, background, outlineRatio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05),
            indicatorFits: rect.left - outset >= 0 && rect.right + outset <= innerWidth && rect.top - outset >= 0 && rect.bottom + outset <= innerHeight }
        })()
      JS
      header_record("keyboard-control", { selector: selector, measurement: sample })
      geometry = sample.fetch("geometry")
      assert_operator geometry.fetch("left"), :>=, 0, sample.to_json
      assert_operator geometry.fetch("right"), :<=, sample.fetch("viewport").first + 1, sample.to_json
      assert_operator geometry.fetch("top"), :>=, 0, sample.to_json
      assert_operator geometry.fetch("bottom"), :<=, sample.fetch("viewport").last + 1, sample.to_json
      assert sample.fetch("hits").all?, "Covered header control: #{selector}: #{sample.to_json}"
      assert sample.fetch("focusVisible"), sample.to_json
      assert_operator sample.fetch("outlineWidth"), :>=, 2, sample.to_json
      refute_equal "none", sample.fetch("outlineStyle"), sample.to_json
      assert_operator sample.fetch("outlineRatio"), :>=, 3, sample.to_json
      assert sample.fetch("indicatorFits"), "Clipped header focus: #{sample.to_json}"
      sample
    end

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
      @header_evidence ||= Dir.mktmpdir("compact-headers-", ENV.fetch("EVIDENCE", Dir.tmpdir))
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
