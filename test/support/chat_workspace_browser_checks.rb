require "json"
require "tmpdir"

# Browser measurements deliberately reject effects that computed ancestor colors
# cannot describe. Native dialog backdrops need separate screenshot inspection.
module ChatWorkspaceBrowserChecks
  private
    def chat_viewport(width, height)
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      page.current_window.resize_to(width, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
    end

    def chat_theme(dark)
      find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != dark
      assert_equal dark, page.evaluate_script("document.documentElement.classList.contains('dark')")
      settle_workspace_layout
    end

    def chat_evidence_directory
      @chat_evidence_directory ||= Dir.mktmpdir("task7-#{name.gsub(/[^a-zA-Z0-9-]/, '-')}-", ENV.fetch("EVIDENCE", "/tmp/opencode"))
    end

    def chat_measurement(data)
      context = page.evaluate_script("({ theme: document.documentElement.classList.contains('dark') ? 'dark' : 'light', locale: document.documentElement.lang, viewport: [innerWidth, innerHeight], path: location.pathname })")
      File.open(File.join(chat_evidence_directory, "measurements.jsonl"), "a") { |file| file.puts(context.merge(data).to_json) }
    end

    def chat_screenshot(state)
      path = File.join(chat_evidence_directory, "#{state}.png")
      page.save_screenshot(path)
      puts "Chat visual evidence: #{path}"
    end

    # Real Tab traversal, not focus(), establishes keyboard modality and reachability.
    def chat_keyboard_focus(selector, reverse: false)
      160.times do
        page.driver.browser.action.send_keys(*(reverse ? [ [ :shift, :tab ] ] : [ :tab ])).perform
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          assert_selector "#{selector}:focus"
          settle_workspace_layout
          chat_reachable selector, scroll: false
          return
        end
      end
      flunk "Keyboard traversal did not reach #{selector}"
    end

    def chat_reachable(selector, scroll: true)
      element = find(selector)
      chat_scroll_to(element) if scroll
      geometry = page.evaluate_script(<<~JS, element)
        (() => {
        const element = arguments[0], rect = element.getBoundingClientRect()
        const points = [[rect.x + rect.width / 2, rect.y + rect.height / 2], [rect.x + rect.width / 2, rect.top + 2],
          [rect.x + rect.width / 2, rect.bottom - 2], [rect.left + 2, rect.y + rect.height / 2], [rect.right - 2, rect.y + rect.height / 2]]
        const hits = points.map(([x, y]) => { const hit = document.elementFromPoint(x, y); return !!hit && (hit === element || element.contains(hit)) })
        return { ...rect.toJSON(), hit: hits.every(Boolean), hits, viewport: [innerWidth, innerHeight] }
        })()
      JS
      chat_measurement("kind" => "reachability", "selector" => selector, "geometry" => geometry)
      assert_operator geometry.fetch("left"), :>=, 0, geometry.to_json
      assert_operator geometry.fetch("right"), :<=, geometry.fetch("viewport").first + 1, geometry.to_json
      assert_operator geometry.fetch("top"), :>=, 0, geometry.to_json
      assert_operator geometry.fetch("bottom"), :<=, geometry.fetch("viewport").last + 1, geometry.to_json
      assert geometry.fetch("hit"), "Covered control: #{selector}: #{geometry.to_json}"
      geometry
    end

    def assert_chat_bounds
      width = page.evaluate_script("innerWidth")
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      assert page.evaluate_script("document.querySelector('.n-chat-main').scrollWidth <= document.querySelector('.n-chat-main').clientWidth"), "Main has horizontal overflow"
      [ ".n-composer-surface", ".n-composer-account", ".n-composer-send" ].each do |selector|
        element = find(selector)
        rect = element.native.rect
        chat_measurement("kind" => "native-bounds", "selector" => selector, "geometry" => { x: rect.x, y: rect.y, width: rect.width, height: rect.height })
        assert_operator rect.x, :>=, 0
        assert_operator rect.x + rect.width, :<=, width + 1
      end
      chat_reachable ".n-composer-account"
      chat_reachable ".n-composer-send"
    end

    def chat_contrast(selector, minimum: 4.5, outline: false, border: false)
      element = find(selector)
      chat_scroll_to(element)
      sample = page.evaluate_script(<<~JS, element, outline, border)
        (() => {
        const element = arguments[0], outline = arguments[1], border = arguments[2]
        if (element.closest('dialog')) throw new Error('Native top-layer/backdrop requires separate sampling')
        const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
        const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
        const rgba = color => {
          if (!CSS.supports('color', color)) throw new Error(`Unparsed color: ${color}`)
          context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1)
          const value = [...context.getImageData(0, 0, 1, 1).data]
          return [value[0] / 255, value[1] / 255, value[2] / 255, value[3] / 255]
        }
        const over = (fg, bg) => [...fg.slice(0, 3).map((channel, i) => channel * fg[3] + bg[i] * (1 - fg[3])), 1]
        const chain = []; for (let node = element; node; node = node.parentElement) chain.unshift(node)
        for (const node of chain) {
          const style = getComputedStyle(node)
          if (style.backgroundImage !== 'none' || Number(style.opacity) !== 1 || style.filter !== 'none' || style.backdropFilter !== 'none' || style.mixBlendMode !== 'normal')
            throw new Error(`Unmeasured paint effect on ${node.tagName}.${node.className}`)
        }
        const backgrounds = chain.map(node => getComputedStyle(node).backgroundColor)
        const background = backgrounds.slice(0, outline || border ? -1 : undefined).reduce((bg, color) => over(rgba(color), bg), [1, 1, 1, 1])
        const style = getComputedStyle(element)
        const color = outline ? style.outlineColor : border ? style.borderTopColor : style.color
        const foreground = over(rgba(color), background)
        const luminance = color => color.slice(0, 3).map(c => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4).reduce((sum, c, i) => sum + c * [0.2126, 0.7152, 0.0722][i], 0)
        const a = luminance(foreground), b = luminance(background), rect = element.getBoundingClientRect()
        const hit = document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2)
        const outset = outline ? parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset) : 0
        return { color, backgrounds, foreground, background, ratio: (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05),
          outlineWidth: parseFloat(style.outlineWidth), outlineStyle: style.outlineStyle, borderWidth: parseFloat(style.borderTopWidth),
          geometry: rect.toJSON(), hit: !!hit && (hit === element || element.contains(hit)),
          indicatorFits: rect.left - outset >= 0 && rect.right + outset <= innerWidth && rect.top - outset >= 0 && rect.bottom + outset <= innerHeight,
          surfaces: ['.n-chat-main', '.n-chat-workspace', '.n-composer-notice'].map(selector => { const node = document.querySelector(selector); return { selector, geometry: node.getBoundingClientRect().toJSON(), top: node.scrollTop, height: node.scrollHeight, client: node.clientHeight, padding: getComputedStyle(node).paddingBottom } }) }
        })()
      JS
      chat_measurement(sample.merge("kind" => border ? "border" : outline ? "outline" : "text", "selector" => selector, "threshold" => minimum))
      assert sample.fetch("hit"), "Contrast sample is obscured: #{selector}: #{sample.to_json}"
      assert_operator sample.fetch("ratio"), :>=, minimum, "#{selector}: #{sample.to_json}"
      if outline
        assert_selector "#{selector}:focus-visible"
        assert_operator sample.fetch("outlineWidth"), :>=, 2
        refute_equal "none", sample.fetch("outlineStyle")
        assert sample.fetch("indicatorFits"), "Focus outline clipped by viewport: #{sample.to_json}"
      end
      assert_operator sample.fetch("borderWidth"), :>=, 1 if border
      sample
    end

    def chat_scroll_to(element)
      settle_workspace_layout
      page.execute_script(<<~JS, element)
        arguments[0].scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' })
        // Explicitly deliver this measurement's intentional scroll before any
        // already queued reader reconciliation. Do not change reader state.
        document.querySelector('.n-chat-main').dispatchEvent(new Event('scroll'))
        document.querySelector('.n-chat-transcript')?.dispatchEvent(new Event('scroll'))
      JS
      settle_workspace_layout
    end

    def chat_dialog_sample(id)
      # The opaque dialog and its .6 black native backdrop are recorded separately;
      # ordinary ancestor composition must never pretend to measure the top layer.
      chat_measurement(page.evaluate_script(<<~JS, id).merge("kind" => "native-dialog-manual-sample"))
        (() => {
        const dialog = document.getElementById(arguments[0])
        return { selector: `#${dialog.id}`, modal: dialog.matches(':modal'), surface: getComputedStyle(dialog).backgroundColor,
          border: getComputedStyle(dialog).borderTopColor, backdrop: getComputedStyle(dialog, '::backdrop').backgroundColor,
          geometry: dialog.getBoundingClientRect().toJSON(), limitation: 'Backdrop composition requires screenshot inspection; no automated contrast claim' }
        })()
      JS
    end
end
