require "json"
require "tmpdir"

module OrbiteBrowserChecks
  private
    def orbite_viewport(width, height)
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      page.current_window.resize_to(width, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
      orbite_settle
    end

    def orbite_settle
      page.evaluate_async_script("const done = arguments[0]; requestAnimationFrame(() => requestAnimationFrame(done))")
    end

    def orbite_record(label, sample, screenshot: false)
      @orbite_evidence ||= Dir.mktmpdir("orbite-", ENV.fetch("EVIDENCE", Dir.tmpdir))
      context = page.evaluate_script("({ path: location.pathname, query: location.search, locale: document.documentElement.lang, theme: document.documentElement.classList.contains('dark') ? 'dark' : 'light', viewport: [innerWidth, innerHeight] })")
      path = File.join(@orbite_evidence, "measurements.jsonl")
      File.open(path, "a") { |file| file.puts(context.merge(sourceCommit: ENV.fetch("ORBITE_SOURCE_SHA", "UNRECORDED"), label: label, sample: sample).to_json) }
      puts "Orbite measurements: #{path}"
      if screenshot
        image = File.join(@orbite_evidence, "#{label.gsub(/[^a-zA-Z0-9-]/, '-')}.png")
        page.save_screenshot(image)
        puts "Orbite screenshot: #{image}"
      end
      sample
    end

    def orbite_open_utilities
      return if page.has_selector?("#theme-toggle", wait: 0)

      selectors = if page.evaluate_script("innerWidth >= 768")
        [ "#workspace-history-rail-trigger", "#workspace-history-trigger" ]
      else
        [ "[data-orbite-composer-navigation]", "#workspace-mobile-trigger", "#workspace-history-trigger" ]
      end
      opener = selectors.filter_map do |selector|
        first(selector, minimum: 0, wait: 0)
      end.first
      assert opener, "No visible navigation utility opener"
      opener.click
      assert_selector "#theme-toggle"
    end

    def orbite_user_menu_trigger
      if page.evaluate_script("innerWidth >= 768")
        "#workspace-utilities-trigger"
      else
        orbite_open_utilities
        "#dropdownUser"
      end
    end

    def orbite_open_user_menu(keyboard: false)
      opener = orbite_user_menu_trigger
      if keyboard
        orbite_tab_to(opener)
        page.driver.browser.action.send_keys(:enter).perform
      else
        find(opener).click
      end
      assert_selector "#dropdown:popover-open"
      assert_selector "#{opener}[aria-expanded=true]"
      opener
    end

    def orbite_close_navigation
      if page.has_selector?("#chat-history:modal", wait: 0)
        find("#chat-history [data-action='workspace-navigation#close']").click
      end
      assert_no_selector "#chat-history:modal"
    end

    def orbite_with_utilities
      initially_hidden = !page.has_selector?("#theme-toggle", wait: 0)
      url = page.current_url
      orbite_open_utilities
      yield
    ensure
      if initially_hidden && page.current_url == url
        if page.has_selector?("#chat-history:modal", wait: 0)
          orbite_close_navigation
        elsif page.has_selector?("#chat-history[data-inline=true][open]", wait: 0)
          find("#workspace-history-rail-trigger").click
          assert_no_selector "#chat-history[open]", visible: :all
        end
      end
    end

    def orbite_select_language(label)
      if page.has_selector?("#orbite-shell", wait: 0)
        orbite_with_utilities { select label, from: "language_preference_locale" }
      else
        select label, from: "language_preference_locale"
      end
    end

    def orbite_theme(dark)
      if page.evaluate_script("document.documentElement.classList.contains('dark')") != dark
        orbite_with_utilities { find("#theme-toggle").click }
      end
      assert_equal dark, page.evaluate_script("document.documentElement.classList.contains('dark')")
      orbite_settle
    end

    def orbite_assert_reachable(selector)
      sample = page.evaluate_script(<<~JS, find(selector))
        (() => {
          const element = arguments[0], rect = element.getBoundingClientRect(), style = getComputedStyle(element)
          const points = [[rect.x + rect.width / 2, rect.y + rect.height / 2], [rect.x + rect.width / 2, rect.top + 2],
            [rect.x + rect.width / 2, rect.bottom - 2], [rect.left + 2, rect.y + rect.height / 2], [rect.right - 2, rect.y + rect.height / 2]]
          const hits = points.map(([x, y]) => { const hit = document.elementFromPoint(x, y); return !!hit && (hit === element || element.contains(hit)) })
          return { ...rect.toJSON(), hits, viewport: [innerWidth, innerHeight], focusVisible: element.matches(':focus-visible'), outlineWidth: parseFloat(style.outlineWidth) }
        })()
      JS
      orbite_record("reachability-#{selector}", sample)
      assert_operator sample.fetch("left"), :>=, 0, sample.to_json
      assert_operator sample.fetch("right"), :<=, sample.fetch("viewport").first, sample.to_json
      assert_operator sample.fetch("top"), :>=, 0, sample.to_json
      assert_operator sample.fetch("bottom"), :<=, sample.fetch("viewport").last, sample.to_json
      assert sample.fetch("hits").all?, sample.to_json
      sample
    end

    def orbite_tab_to(selector, reverse: false)
      160.times do
        action = page.driver.browser.action
        reverse ? action.key_down(:shift).send_keys(:tab).key_up(:shift).perform : action.send_keys(:tab).perform
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          orbite_settle
          sample = orbite_assert_reachable(selector)
          assert sample.fetch("focusVisible"), sample.to_json
          assert_operator sample.fetch("outlineWidth"), :>=, 2, sample.to_json
          return sample
        end
      end
      flunk "Native Tab traversal did not reach #{selector}"
    end
end
