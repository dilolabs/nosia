require "application_system_test_case"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/chat_workspace_browser_checks"

class PremiumChatHeaderSystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include ChatWorkspaceBrowserChecks
  include Turbo::Broadcastable::TestHelper

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
    page.current_window.resize_to(*@original_size)
  end

  test "records real header density without changing application geometry" do
    premium_contexts do |locale, width, height, dark|
      premium_top
      sample = premium_geometry
      phase = ENV.fetch("PREMIUM_HEADER_PHASE", "candidate")
      orbite_record("premium-density-#{phase}-#{locale}-#{width}x#{height}-#{dark}", sample, screenshot: true)
      assert_equal [ 125, 24 ], sample.fetch("counts")
      assert_equal @second.name, sample.fetch("account")
      assert sample.fetch("insideReader")
      refute_includes %w[fixed sticky], sample.fetch("position")
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "single distribution replaces the table without hiding values" do
    premium_contexts do |locale, width, height, dark|
      assert_selector "#chat-usage-details [data-chat-token-bar][aria-hidden=true]", count: 1
      assert_no_selector "#chat-usage-details table, #chat-usage-details details, #chat-usage-details [role=progressbar], .n-chat-toolbar [data-chat-account-label]", visible: :all
      assert_selector ".n-chat-header [data-chat-account-label]", text: @second.name, exact_text: true, count: 1
      assert_selector "[data-chat-total-tokens]", text: "149", exact_text: true
      %w[completion embedding].each do |kind|
        assert_selector "li[data-usage-kind='#{kind}'] [data-usage-input]"
        assert_selector "li[data-usage-kind='#{kind}'] [data-usage-output]"
      end
      assert_selector "[data-estimate-note]", text: I18n.t("nosia.usage.total_fallback_tooltip", locale: locale)
      premium_top
      bar = page.evaluate_script(<<~JS)
        (() => {
          const bar = document.querySelector('[data-chat-token-bar]'), style = getComputedStyle(bar)
          const parts = [...bar.querySelectorAll('[data-chat-token-part]')]
          return { width: bar.getBoundingClientRect().width, gap: parseFloat(style.columnGap),
            parts: parts.map(part => ({ name: part.dataset.chatTokenPart, width: part.getBoundingClientRect().width })),
            focusables: bar.querySelectorAll('a,button,input,select,summary,[tabindex]').length }
        })()
      JS
      available = bar.fetch("width") - bar.fetch("gap")
      assert_in_delta available * 125.0 / 149, bar.fetch("parts").first.fetch("width"), 1, bar.to_json
      assert_in_delta available * 24.0 / 149, bar.fetch("parts").last.fetch("width"), 1, bar.to_json
      assert_equal 0, bar.fetch("focusables")
      chat_contrast "#chat-usage-summary"
      chat_contrast "[data-chat-account-label]"
      chat_contrast "[data-chat-total-input]"
      chat_contrast "[data-chat-total-output]"
      chat_contrast "[data-estimate-note]"
      %w[input output].each { |part| premium_segment_contrast(part) }
      orbite_read_start
      assert page.evaluate_script("document.scrollingElement.scrollWidth <= innerWidth")
      assert_no_enqueued_jobs only: ChatResponseJob
      orbite_record("premium-bar-#{locale}-#{width}x#{height}-#{dark}", bar, screenshot: true)
      if locale == "fr" && width == 812 && dark
        page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
        assert page.evaluate_script("[...document.querySelectorAll('[data-chat-token-bar], [data-chat-token-part]')].every(node => getComputedStyle(node).animationName === 'none' && getComputedStyle(node).transitionDuration.split(',').every(value => parseFloat(value) === 0))")
      end
    end
  end

  { zero: [ 0, 0 ], input_only: [ 17, 0 ], output_only: [ 0, 19 ], large: [ 1_234_567_890, 987_654_321 ] }.each do |state, values|
    test "#{state} bar and long account keep exact visible information" do
      chat = workspace(:chats, :workspace_first_chat)
      assert_empty chat.token_usages
      chat.update_columns(input_tokens_count: 0, output_tokens_count: 0)
      @first.update_columns(name: "CompteDeRecherche" * 12)
      input, output = values
      if input.positive? || output.positive?
        TokenUsage.create!(account: @first, chat: chat, kind: :completion,
          model_id: "picker-test-model", input_tokens: input, output_tokens: output)
      end
      %w[en fr].product([ [ 375, 812 ], [ 1400, 1000 ] ], [ false, true ]).each do |locale, (width, height), dark|
        orbite_viewport(width, height)
        orbite_select_language(locale.upcase)
        visit chat_path(chat)
        assert_selector "lexxy-editor[connected]"
        orbite_theme(dark)
        premium_top
        assert_selector ".n-chat-header [data-chat-account-label]", text: @first.name, exact_text: true, count: 1
        { input: input, output: output, tokens: input + output }.each do |name, value|
          expected = I18n.with_locale(locale) { ApplicationController.helpers.number_with_delimiter(value) }
          assert_selector "[data-chat-total-#{name}]", text: expected, exact_text: true
        end
        assert_selector "[data-chat-token-bar][data-empty='#{(input + output).zero?}']"
        assert_selector "[data-chat-token-part]", count: values.count(&:positive?)
        assert_selector "[data-estimate-note]", count: 1
        assert_no_selector "#chat-usage-details table, #chat-usage-details details", visible: :all
        sample = page.evaluate_script(<<~JS)
          (() => {
            const node = document.querySelector('[data-chat-account-label]'), range = document.createRange()
            range.selectNodeContents(node)
            const box = node.getBoundingClientRect(), style = getComputedStyle(node)
            const bar = document.querySelector('[data-chat-token-bar]'), barStyle = getComputedStyle(bar)
            return { box: box.toJSON(), whiteSpace: style.whiteSpace, textOverflow: style.textOverflow,
              fits: node.scrollWidth <= node.clientWidth && [...range.getClientRects()].every(line => line.left >= box.left - 1 && line.right <= box.right + 1 && line.top >= box.top - 1 && line.bottom <= box.bottom + 1),
              pageWidth: document.scrollingElement.scrollWidth, viewportWidth: innerWidth,
              barWidth: bar.getBoundingClientRect().width, gap: parseFloat(barStyle.columnGap),
              parts: [...bar.querySelectorAll('[data-chat-token-part]')].map(part => ({ name: part.dataset.chatTokenPart, width: part.getBoundingClientRect().width })) }
          })()
        JS
        refute_equal "nowrap", sample.fetch("whiteSpace")
        refute_equal "ellipsis", sample.fetch("textOverflow")
        assert sample.fetch("fits"), sample.to_json
        assert_operator sample.fetch("pageWidth"), :<=, sample.fetch("viewportWidth"), sample.to_json
        parts = sample.fetch("parts")
        if input + output > 0
          available = sample.fetch("barWidth") - [ parts.size - 1, 0 ].max * sample.fetch("gap")
          parts.each do |part|
            count = part.fetch("name") == "input" ? input : output
            assert_in_delta available * count.fdiv(input + output), part.fetch("width"), 1, sample.to_json
          end
        else
          assert_empty parts
        end
        orbite_record("premium-#{state}-#{locale}-#{width}-#{dark}", sample, screenshot: true)
      end
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "actual localized replacement preserves the draft and updates the passive bar" do
    %w[en fr].each do |locale|
      orbite_viewport(375, 812)
      orbite_select_language(locale.upcase)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      find("lexxy-editor .lexxy-editor__content").send_keys("Keep this native premium draft")
      page.execute_script("window.premiumDraft = document.querySelector('lexxy-editor'); window.premiumFocus = document.activeElement")
      before = @chat.reload
      input, output = before.input_tokens_count + 2, before.output_tokens_count + 3
      kind_output = before.token_totals_by_kind.fetch("agent_skill", [ 0, 0 ]).last + 3
      Current.reset
      streams = capture_turbo_stream_broadcasts([ @chat, :token_totals, locale ]) do
        TokenUsage.create!(account: @second, chat_id: @chat.id, kind: :agent_skill,
          model_id: "picker-test-model", input_tokens: 2, output_tokens: 3)
      end
      replacement = streams.find { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(@chat, :token_totals) }
      assert replacement
      assert_equal "replace", replacement["action"]
      page.execute_script("Turbo.renderStreamMessage(arguments[0])", replacement.to_html)
      { input: input, output: output, tokens: input + output }.each do |name, value|
        expected = I18n.with_locale(locale) { ApplicationController.helpers.number_with_delimiter(value) }
        assert_selector "[data-chat-total-#{name}]", text: expected, exact_text: true, visible: :all
      end
      expected_kind = I18n.with_locale(locale) { ApplicationController.helpers.number_with_delimiter(kind_output) }
      assert_selector "li[data-usage-kind=agent_skill] [data-usage-output]", text: expected_kind, exact_text: true, visible: :all
      assert_equal input.to_f, page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('[data-chat-token-part=input]')).flexGrow)")
      assert_equal output.to_f, page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('[data-chat-token-part=output]')).flexGrow)")
      assert page.evaluate_script("window.premiumDraft === document.querySelector('lexxy-editor') && window.premiumFocus === document.activeElement")
      assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this native premium draft"
      orbite_record("premium-live-#{locale}", { target: replacement["target"], payload: replacement.to_html }, screenshot: true)
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "History top row keeps the moved action accessible without disturbing the draft" do
    premium_contexts do |locale, width, height, dark|
      link = "#chat-history > .n-orbite-navigation-actions > a[href='#{new_chat_path}']"
      assert_selector link, text: I18n.t("nosia.chat_workspace.new_chat", locale: locale), exact_text: true, count: 1, visible: :all
      assert_no_selector ".n-chat-header a, .n-chat-header button:not(#chat-delete-trigger), .n-chat-header .n-workspace-actions", visible: :all
      assert_selector ".n-chat-header #chat-delete-trigger", count: 1
      find("lexxy-editor .lexxy-editor__content").send_keys("Keep this History action draft")
      page.execute_script("window.historyActionEditor = document.querySelector('lexxy-editor')")
      find("#workspace-navigation-close").click if page.has_selector?("#chat-history[open]", wait: 0)
      opener = orbite_navigation_trigger
      orbite_tab_to(opener)
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector width >= 1280 ? "#chat-history[data-inline=true][open]" : "#chat-history:modal"
      assert_selector "#workspace-navigation-close:focus" if width < 1280
      orbite_tab_to(link, reverse: true)
      premium_history_contrast link
      premium_history_contrast link, minimum: 3, outline: true
      sample = premium_history_actions
      assert_in_delta sample.fetch("link").fetch("top"), sample.fetch("close").fetch("top"), 1, sample.to_json
      assert_operator sample.fetch("link").fetch("right"), :<=, sample.fetch("close").fetch("left"), sample.to_json
      %w[link close].each do |name|
        %w[width height].each { |axis| assert_operator sample.fetch(name).fetch(axis), :>=, 44, sample.to_json }
      end
      assert sample.fetch("outsideContent"), sample.to_json
      assert sample.fetch("labelFits"), sample.to_json
      assert_operator sample.fetch("panelScrollWidth"), :<=, sample.fetch("panelClientWidth"), sample.to_json
      assert_operator sample.fetch("pageWidth"), :<=, sample.fetch("viewportWidth"), sample.to_json
      orbite_assert_reachable(link)
      orbite_tab_to("#workspace-navigation-close")
      orbite_record("history-action-row-#{locale}-#{width}x#{height}-#{dark}", sample, screenshot: true)
      page.driver.browser.action.send_keys(:enter).perform
      assert_no_selector "#chat-history[open]", visible: :all
      assert_selector "#{opener}:focus"
      orbite_assert_reachable(opener)
      if width < 1280
        page.driver.browser.action.send_keys(:enter).perform
        assert_selector "#chat-history:modal"
        page.driver.browser.action.send_keys(:escape).perform
        assert_no_selector "#chat-history[open]", visible: :all
        assert_selector "#{opener}:focus"
        orbite_assert_reachable(opener)
      end
      assert page.evaluate_script("window.historyActionEditor === document.querySelector('lexxy-editor')")
      assert_selector "lexxy-editor .lexxy-editor__content", text: "Keep this History action draft", exact_text: true
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  test "History New chat retains native keyboard and pointer navigation" do
    %w[en fr].product([ [ 375, 812 ], [ 1400, 1000 ] ], %w[keyboard pointer]).each do |locale, (width, height), input|
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      orbite_theme(input == "pointer")
      find("#workspace-navigation-close").click if page.has_selector?("#chat-history[open]", wait: 0)
      opener = orbite_navigation_trigger
      orbite_tab_to(opener)
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-history[open]"
      link = "#chat-history > .n-orbite-navigation-actions > a[href='#{new_chat_path}']"
      counts = [ Chat.count, Message.count ]
      if input == "keyboard"
        orbite_tab_to(link, reverse: true)
        page.driver.browser.action.send_keys(:enter).perform
      else
        orbite_assert_reachable(link)
        find(link).click
      end
      assert_current_path new_chat_path
      assert_selector "lexxy-editor[connected]"
      assert_selector "html[lang='#{locale}']"
      assert_no_selector "#chat-history > .n-orbite-navigation-actions > a", visible: :all
      assert_equal counts, [ Chat.count, Message.count ]
      orbite_record("history-new-chat-#{locale}-#{width}-#{input}", { input: input, counts: counts }, screenshot: true)
      assert_no_enqueued_jobs only: ChatResponseJob
    end
  end

  private
    def premium_history_actions
      page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector('#chat-history'), row = panel.querySelector('.n-orbite-navigation-actions')
          const link = row.querySelector('a'), close = row.querySelector('#workspace-navigation-close')
          const rect = link.getBoundingClientRect(), range = document.createRange()
          range.selectNodeContents(link)
          return { link: rect.toJSON(), close: close.getBoundingClientRect().toJSON(),
            outsideContent: row.parentElement === panel && !panel.querySelector('.n-orbite-panel-content').contains(row),
            labelFits: link.scrollWidth <= link.clientWidth && [...range.getClientRects()].every(line => line.left >= rect.left - 1 && line.right <= rect.right + 1 && line.top >= rect.top - 1 && line.bottom <= rect.bottom + 1),
            panelScrollWidth: panel.scrollWidth, panelClientWidth: panel.clientWidth,
            pageWidth: document.scrollingElement.scrollWidth, viewportWidth: innerWidth }
        })()
      JS
    end

    def premium_history_contrast(selector, minimum: 4.5, outline: false)
      element = find(selector)
      page.evaluate_async_script(<<~JS, element)
        const element = arguments[0], done = arguments[arguments.length - 1]
        Promise.all(element.getAnimations().map(animation => animation.finished.catch(() => {}))).then(done)
      JS
      sample = page.evaluate_script(<<~JS, element, outline)
        (() => {
          const element = arguments[0], outline = arguments[1]
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
          const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
          const rgba = color => {
            if (!CSS.supports('color', color)) throw new Error(`Unparsed History color: ${color}`)
            context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data].map(channel => channel / 255)
          }
          const over = (fg, bg) => [...fg.slice(0, 3).map((channel, i) => channel * fg[3] + bg[i] * (1 - fg[3])), 1]
          const modal = element.closest('dialog:modal'), chain = []
          for (let node = element; node; node = node.parentElement) { chain.unshift(node); if (node === modal) break }
          if (modal && rgba(getComputedStyle(modal).backgroundColor)[3] !== 1) throw new Error('History modal interior must be opaque')
          const backgrounds = chain.map(node => {
            const style = getComputedStyle(node)
            if (style.backgroundImage !== 'none' || Number(style.opacity) !== 1 || style.filter !== 'none' || style.backdropFilter !== 'none' || style.mixBlendMode !== 'normal')
              throw new Error(`Unmeasured History paint effect on ${node.tagName}`)
            return style.backgroundColor
          })
          if (!backgrounds.some(color => rgba(color)[3] === 1)) throw new Error('No measured opaque History backing surface')
          const background = backgrounds.reduce((bg, color) => over(rgba(color), bg), [1, 1, 1, 1])
          const style = getComputedStyle(element), color = outline ? style.outlineColor : style.color
          const foreground = over(rgba(color), background)
          const luminance = color => color.slice(0, 3).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4)
            .reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0)
          const a = luminance(foreground), b = luminance(background), rect = element.getBoundingClientRect()
          const hit = document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2)
          const outset = outline ? Math.max(0, parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset)) : 0
          return { color, foreground, background, backgrounds, modalInterior: !!modal, geometry: rect.toJSON(),
            ratio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05), hit: !!hit && (hit === element || element.contains(hit)),
            outlineWidth: parseFloat(style.outlineWidth), outlineStyle: style.outlineStyle,
            indicatorFits: rect.left - outset >= 0 && rect.right + outset <= innerWidth && rect.top - outset >= 0 && rect.bottom + outset <= innerHeight,
            limitation: 'Opaque interior only; native backdrop contrast is not inferred' }
        })()
      JS
      orbite_record("history-action-contrast", { selector: selector, minimum: minimum, outline: outline, measurement: sample })
      assert sample.fetch("hit"), sample.to_json
      assert_operator sample.fetch("ratio"), :>=, minimum, sample.to_json
      if outline
        assert_selector "#{selector}:focus-visible"
        assert_operator sample.fetch("outlineWidth"), :>=, 2, sample.to_json
        refute_equal "none", sample.fetch("outlineStyle"), sample.to_json
        assert sample.fetch("indicatorFits"), sample.to_json
      end
    end

    def premium_contexts
      %w[en fr].product([ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ], [ false, true ]).each do |locale, (width, height), dark|
        orbite_viewport(width, height)
        orbite_select_language(locale.upcase)
        visit chat_path(@chat)
        assert_selector "lexxy-editor[connected]"
        page.evaluate_async_script(<<~JS)
          const done = arguments[arguments.length - 1]
          Promise.all(document.getAnimations().filter(animation => Number.isFinite(animation.effect.getComputedTiming().endTime))
            .map(animation => animation.finished.catch(() => {}))).then(done)
        JS
        orbite_theme(dark)
        yield locale, width, height, dark
      end
    end

    def settle_workspace_layout
      orbite_settle
    end

    def premium_top
      page.execute_script(<<~JS)
        const reader = document.querySelector('[data-application-scroll]')
        reader.scrollTop = 0
        reader.dispatchEvent(new Event('scroll'))
      JS
      orbite_settle
    end

    def premium_geometry
      page.evaluate_script(<<~JS, @chat.id)
        (() => {
          const header = document.querySelector('.n-chat-header'), reader = document.querySelector('[data-application-scroll]')
          const kinds = [...document.querySelectorAll('#chat-usage-details [data-usage-kind]')].map(row => ({
            kind: row.dataset.usageKind,
            values: [...row.querySelectorAll('td,[data-usage-input],[data-usage-output]')].map(node => node.textContent.trim())
          }))
          return { chat: arguments[0], account: document.querySelector('#chat-usage-details > p').textContent.trim(), kinds,
            counts: ['input','output'].map(part => Number(document.querySelector(`[data-chat-total-${part}]`).textContent.replace(/[^0-9]/g, ''))),
            headerHeight: header.getBoundingClientRect().height, position: getComputedStyle(header).position,
            insideReader: reader.contains(header), reader: reader.getBoundingClientRect().toJSON(),
            transcriptTop: document.querySelector('.n-chat-transcript').getBoundingClientRect().top,
            viewport: [innerWidth, innerHeight], dockTop: document.querySelector('.n-chat-dock').getBoundingClientRect().top }
        })()
      JS
    end

    def premium_segment_contrast(part)
      node = find("[data-chat-token-part='#{part}']")
      chat_scroll_to(node)
      sample = page.evaluate_script(<<~JS, node)
        (() => {
          const node = arguments[0], band = node.closest('#chat-usage-details')
          const parse = color => {
            const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
            const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
            if (!CSS.supports('color', color)) throw new Error(`Unparsed segment color ${color}`)
            context.fillStyle = color; context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data].map(value => value / 255)
          }
          const foreground = parse(getComputedStyle(node).backgroundColor), background = parse(getComputedStyle(band).backgroundColor)
          if (foreground[3] !== 1 || background[3] !== 1) throw new Error('Segment sampling requires opaque fills')
          for (let element = node; element; element = element.parentElement) {
            const style = getComputedStyle(element)
            if (style.backgroundImage !== 'none' || Number(style.opacity) !== 1 || style.filter !== 'none' || style.backdropFilter !== 'none' || style.mixBlendMode !== 'normal') throw new Error('Unmeasured segment paint effect')
          }
          const luminance = rgba => rgba.slice(0,3).map(value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4)
            .reduce((sum,value,index) => sum + value * [.2126,.7152,.0722][index],0)
          const a = luminance(foreground), b = luminance(background)
          return { foreground, background, ratio: (Math.max(a,b)+.05)/(Math.min(a,b)+.05),
            marker: getComputedStyle(node, '::after').borderTopStyle }
        })()
      JS
      assert_operator sample.fetch("ratio"), :>=, 3, sample.to_json
      assert_equal "dashed", sample.fetch("marker") if part == "output"
      orbite_record("premium-segment-#{part}", sample)
    end
end
