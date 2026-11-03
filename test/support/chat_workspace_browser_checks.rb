require "json"
require "tmpdir"
require_relative "orbite_browser_checks"

# Browser measurements deliberately reject effects that computed ancestor colors
# cannot describe. Native dialog backdrops need separate screenshot inspection.
module ChatWorkspaceBrowserChecks
  include OrbiteBrowserChecks

  private
    def chat_viewport(width, height)
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      page.current_window.resize_to(width, height)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      assert_equal [ width, height ], page.evaluate_script("[innerWidth, innerHeight]")
    end

    def chat_theme(dark)
      orbite_theme(dark)
      settle_workspace_layout
    end

    def chat_evidence_directory
      @chat_evidence_directory ||= Dir.mktmpdir("task7-#{name.gsub(/[^a-zA-Z0-9-]/, '-')}-", ENV.fetch("EVIDENCE", Dir.tmpdir))
    end

    def chat_measurement(data)
      context = page.evaluate_script("({ theme: document.documentElement.classList.contains('dark') ? 'dark' : 'light', locale: document.documentElement.lang, viewport: [innerWidth, innerHeight], path: location.pathname })")
      collisions = data.keys.map(&:to_s) & context.keys
      unless collisions.empty?
        raise ArgumentError, "Reserved chat measurement context keys: #{collisions.join(', ')}"
      end
      File.open(File.join(chat_evidence_directory, "measurements.jsonl"), "a") { |file| file.puts(context.merge(data).to_json) }
    end

    def chat_screenshot(state)
      path = File.join(chat_evidence_directory, "#{state}.png")
      page.save_screenshot(path)
      puts "Chat visual evidence: #{path}"
      path
    end

    # Real Tab traversal, not focus(), establishes keyboard modality and reachability.
    def chat_keyboard_focus(selector, reverse: false)
      160.times do
        action = page.driver.browser.action
        reverse ? action.key_down(:shift).send_keys(:tab).key_up(:shift).perform : action.send_keys(:tab).perform
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
        if (element.closest('dialog:modal')) throw new Error('Native top-layer/backdrop requires separate sampling')
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
          surfaces: ['[data-application-scroll]', '.n-chat-main', '.n-chat-workspace', '.n-composer-notice'].map(selector => { const node = document.querySelector(selector); return { selector, geometry: node.getBoundingClientRect().toJSON(), top: node.scrollTop, height: node.scrollHeight, client: node.clientHeight, padding: getComputedStyle(node).paddingBottom } }) }
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
        document.querySelector('[data-application-scroll]').dispatchEvent(new Event('scroll'))
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

    # Only this known stroked X on a uniform, opaque native dialog is supported.
    # Its core intersection and clear interior point are recorded for independent
    # screenshot-pixel sampling; neither point is on the green focus indicator.
    def chat_native_close_contrast(selector, screenshot:, minimum: 3)
      button = find(selector)
      sample = page.evaluate_script(<<~JS, button)
        (() => {
          const button = arguments[0], dialog = button.closest('dialog'), svg = button.querySelector('svg'), path = svg?.querySelector('path')
          if (!dialog?.matches(':modal') || !path || svg.querySelectorAll('path').length !== 1 ||
              path.getAttribute('d') !== 'M6 18L18 6M6 6l12 12' || svg.getAttribute('viewBox') !== '0 0 24 24')
            throw new Error('Native icon measurement requires the known modal close X')
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
          const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
          const rgba = color => {
            if (!CSS.supports('color', color)) throw new Error(`Unparsed native icon color: ${color}`)
            context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data]
          }
          const surface = rgba(getComputedStyle(dialog).backgroundColor)
          if (surface[3] !== 255) throw new Error('Native dialog surface must be opaque')
          for (let node = path; node; node = node.parentElement) {
            const style = getComputedStyle(node)
            if (style.backgroundImage !== 'none' || Number(style.opacity) !== 1 || style.filter !== 'none' ||
                style.backdropFilter !== 'none' || style.mixBlendMode !== 'normal' || style.maskImage !== 'none' ||
                style.boxShadow !== 'none' || style.textShadow !== 'none' || style.clipPath !== 'none')
              throw new Error(`Unmeasured native icon paint effect on ${node.tagName}`)
            if (dialog.contains(node)) {
              const background = rgba(style.backgroundColor)
              if (background[3] !== 0 && background.some((channel, index) => channel !== surface[index]))
                throw new Error('Nonuniform native icon backing surface')
              for (const pseudo of ['::before', '::after']) {
                if (!['none', 'normal'].includes(getComputedStyle(node, pseudo).content))
                  throw new Error('Unmeasured generated native icon paint')
              }
            }
            if (node === dialog) break
          }
          const stroke = getComputedStyle(path), style = getComputedStyle(button)
          const foreground = rgba(stroke.stroke), outline = rgba(style.outlineColor)
          if (stroke.fill !== 'none' || Number(stroke.strokeOpacity) !== 1 || foreground[3] !== 255 || outline[3] !== 255)
            throw new Error('Native close measurement requires an opaque stroke and outline without fill')
          const luminance = color => color.slice(0, 3).map(c => c / 255).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4)
            .reduce((sum, c, index) => sum + c * [.2126, .7152, .0722][index], 0)
          const ratio = color => { const a = luminance(color), b = luminance(surface); return (Math.max(a, b) + .05) / (Math.min(a, b) + .05) }
          const point = (x, y) => { const p = new DOMPoint(x, y).matrixTransform(svg.getScreenCTM()); return [Math.floor(p.x), Math.floor(p.y)] }
          const core = point(12, 12), background = point(12, 4), rect = button.getBoundingClientRect()
          const outset = parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset)
          return { foreground, surface, ratio: ratio(foreground), stroke: stroke.stroke, strokeWidth: parseFloat(stroke.strokeWidth),
            svgPath: path.getAttribute('d'), geometry: rect.toJSON(), svgGeometry: svg.getBoundingClientRect().toJSON(),
            outline, outlineRatio: ratio(outline), outlineWidth: parseFloat(style.outlineWidth), outlineStyle: style.outlineStyle,
            outlineFits: rect.left - outset >= 0 && rect.right + outset <= innerWidth && rect.top - outset >= 0 && rect.bottom + outset <= innerHeight,
            pixelPoints: { coreStroke: core, clearSurface: background }, pixelScale: devicePixelRatio,
            coreHit: button.contains(document.elementFromPoint(...core)), surfaceHit: button.contains(document.elementFromPoint(...background)),
            limitation: 'Only this opaque uniform top-layer surface; backdrop contrast is not inferred' }
        })()
      JS
      chat_measurement(sample.merge("kind" => "native-close-glyph", "selector" => selector, "screenshot" => screenshot, "threshold" => minimum))
      assert_selector "#{selector}:focus-visible"
      assert_equal 1, sample.fetch("pixelScale")
      assert_equal [ 40, 40 ], sample.fetch("geometry").values_at("width", "height")
      assert sample.fetch("coreHit") && sample.fetch("surfaceHit"), sample.to_json
      assert sample.fetch("outlineFits"), sample.to_json
      assert_operator sample.fetch("outlineWidth"), :>=, 2
      refute_equal "none", sample.fetch("outlineStyle")
      assert_operator sample.fetch("outlineRatio"), :>=, 3, sample.to_json
      assert_operator sample.fetch("strokeWidth"), :>=, 2
      assert_operator sample.fetch("ratio"), :>=, minimum, "Native close glyph (not its outline): #{sample.to_json}"
    end
end
