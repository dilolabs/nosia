require "application_system_test_case"
require_relative "../support/chat_workspace_fixtures"
require_relative "../support/orbite_browser_checks"

class OrbiteHistoryDensitySystemTest < ApplicationSystemTestCase
  include ChatWorkspaceFixtures
  include OrbiteBrowserChecks

  setup do
    @original_size = page.current_window.size
    density_seed
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

  test "density characterization records ordinary complete rows" do
    %w[en fr].product([ false, true ], [ [ 1400, 1000 ], [ 375, 812 ] ]).each do |locale, dark, (width, height)|
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      density_open(width, dark)
      sample = density_characterization
      orbite_record("history-density-characterization-#{locale}-#{dark}-#{width}x#{height}", sample, screenshot: true)
      assert_equal 1, sample.fetch("version")
      assert_equal width >= 1280 ? "inline" : "modal", sample.fetch("mode")
      assert_equal [ width, height ], sample.fetch("viewport")
      assert_equal density_expected(locale), sample.fetch("rows").map { |row| row.fetch("semantic") }
      assert_equal 14, sample.fetch("rows").size
      assert_equal 0, sample.fetch("scrollTop")
      assert_operator sample.fetch("fullyVisible"), :>, 0, sample.to_json
      assert_operator sample.fetch("fullyVisible"), :<, 14, sample.to_json
      sample.fetch("overflow").each_value { |value| assert_operator value, :<=, 0, sample.to_json }
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "native design removes only redundant History chrome" do
    orbite_viewport(375, 812)
    density_open(375, false)
    assert_selector "#chat-history[aria-labelledby=chat-history-title]:modal"
    assert_selector "#chat-history h2#chat-history-title.sr-only", text: I18n.t("nosia.orbite.navigation"), visible: :all
    assert_selector "#chat-history [data-orbite-history][aria-label='#{I18n.t('nosia.chat_workspace.history_title')}']"
    assert_no_selector "#chat-history h3, #chat-history .n-orbite-history-heading"
    assert_no_selector "#chat-history [data-orbite-history] p:not([data-history-empty])"
    assert_selector "#chat-history .n-orbite-panel-links a", minimum: 1
    close = orbite_tab_to("#workspace-navigation-close")
    assert_operator close.fetch("width"), :>=, 44
    assert_operator close.fetch("height"), :>=, 44
    orbite_record("history-density-chrome-close", close, screenshot: true)
    page.driver.browser.action.send_keys(:enter).perform
    assert_no_selector "#chat-history[open]", visible: :all
    assert_selector "#{orbite_navigation_trigger}:focus"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "native design gives compact navigation labels the full row" do
    @second.update_columns(name: "CompteDeRecherche" * 12)
    orbite_viewport(1400, 1000)
    density_open(1400, false)
    sample = density_rows
    row = sample.fetch("rows").find { |item| item.fetch("id") == @chat.id.to_s }
    refute_nil row, sample.to_json
    orbite_record("history-density-native-design-placement", row, screenshot: true)
    assert_no_selector "#chat-history [data-history-chat] form, #chat-history [data-history-chat] button, #chat-history [data-history-chat] [data-turbo-confirm]", visible: :all
    assert_in_delta row.fetch("row").fetch("width"), row.fetch("link").fetch("width"), 1, row.to_json
    %w[title account].each { |name| density_assert_label(row.fetch(name)) }
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  %w[en fr].product([ false, true ], [ [ 375, 812 ], [ 768, 1024 ], [ 1400, 1000 ], [ 812, 375 ] ], %w[spaced unspaced]).each do |locale, dark, (width, height), labels|
    test "compact History labels preserve native access in #{locale} #{dark ? 'dark' : 'light'} #{width}x#{height} #{labels}" do
      long_title = labels == "spaced" ? ("Long conversation labels " * 8).strip : "UnbrokenConversation" * 10
      long_account = labels == "spaced" ? ("Long research account " * 9).strip : "CompteDeRecherche" * 12
      @first.update_columns(name: "Lab")
      @second.update_columns(name: long_account)
      Message.where(id: @density_message_ids.first).update_all(content: "OK")
      Message.where(id: @density_message_ids.second).update_all(content: long_title)
      @density_titles[@density_chat_ids.first] = "OK"
      @density_titles[@density_chat_ids.second] = long_title.first(119) + "…"
      orbite_viewport(width, height)
      orbite_select_language(locale.upcase)
      density_open(width, dark)
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      assert page.evaluate_script("[...document.querySelectorAll('#chat-history button, #chat-history a')].every(node => getComputedStyle(node).transitionDuration.split(',').every(value => parseFloat(value) === 0))")
      label = "history-density-matrix-#{locale}-#{dark}-#{width}x#{height}-#{labels}"
      sample = density_rows
      orbite_record(label, sample, screenshot: true)
      sample.fetch("overflow").each_value { |value| assert_operator value, :<=, 0, sample.to_json }
      assert_equal 14, sample.fetch("rows").size
      assert_equal density_expected(locale), sample.fetch("rows").map { |row| row.fetch("semantic") }
      sample.fetch("rows").each do |row|
        density_assert_row(row)
        assert_equal row.fetch("semantic").fetch("title"), row.fetch("nativeTitle")
        assert_equal row.fetch("semantic").fetch("account"), row.fetch("nativeAccount")
        assert_includes row.fetch("linkText"), row.fetch("semantic").fetch("title")
        assert_includes row.fetch("linkText"), row.fetch("semantic").fetch("account")
        selector = "[data-history-chat='#{row.fetch('id')}']"
        assert_no_selector "#{selector} form, #{selector} button, #{selector} [data-turbo-method=delete], #{selector} [data-method=delete], #{selector} [data-turbo-confirm]", visible: :all
      end
      short, long = @density_chat_ids.first(2).map { |id| sample.fetch("rows").find { |row| row.fetch("id") == id.to_s } }
      %w[title account].each do |name|
        assert_operator short.fetch(name).fetch("scrollWidth"), :<=, short.fetch(name).fetch("clientWidth"), short.to_json
        assert_operator long.fetch(name).fetch("scrollWidth"), :>, long.fetch(name).fetch("clientWidth"), long.to_json
      end
      controls = @density_chat_ids.first(2).map { |id| "[data-history-chat='#{id}'] > div > a" }
      controls.each { |selector| density_tab_to(selector, label: label) }
      controls.reverse_each { |selector| density_tab_to(selector, reverse: true, label: label) }
      close = density_tab_to("#workspace-navigation-close", label: label, in_content: false)
      assert_operator close.fetch("width"), :>=, 44
      assert_operator close.fetch("height"), :>=, 44
      if width < 1280
        opener = orbite_navigation_trigger
        page.driver.browser.action.send_keys(:escape).perform
        assert_no_selector "#chat-history:modal"
        assert_selector "#{opener}:focus"
        orbite_assert_reachable(opener)
        page.driver.browser.action.send_keys(:enter).perform
        assert_selector "#chat-history:modal"
      end
      target = @density_chat_ids.second
      density_tab_to("[data-history-chat='#{target}'] > div > a", label: label)
      page.driver.browser.action.send_keys(:enter).perform
      assert_current_path chat_path(target)
      assert_selector "lexxy-editor[connected]"
      assert_selector ".n-chat-header h1", text: @density_titles.fetch(target), exact_text: true
      assert_selector "#chat-usage-details > p[data-chat-account-label]", text: long_account, exact_text: true
      header = density_header
      orbite_record("#{label}-opened-header", header, screenshot: true)
      assert_equal 1, header.fetch("previews").size
      header.fetch("previews").each do |item|
        assert item.fetch("visible"), item.to_json
        assert_equal "nowrap", item.fetch("whiteSpace"), item.to_json
        assert_equal "ellipsis", item.fetch("textOverflow"), item.to_json
        assert_equal "hidden", item.fetch("overflowX"), item.to_json
      end
      assert_selector ".n-chat-transcript .n-chat-user-body", text: long_title, exact_text: true
      assert_selector "#chat-usage-details > p", text: long_account, exact_text: true
      assert_equal 2, header.fetch("reading").size
      assert_equal [ long_title, long_account ], header.fetch("reading").map { |item| item.fetch("text") }
      header.fetch("reading").each do |item|
        assert item.fetch("visible"), item.to_json
        refute_equal "nowrap", item.fetch("whiteSpace"), item.to_json
        refute_equal "ellipsis", item.fetch("textOverflow"), item.to_json
        refute_includes %w[hidden clip], item.fetch("overflowX"), item.to_json
        assert item.fetch("glyphsFit"), item.to_json
      end
      # Native wheel navigation recovers the ordinary reader start without a new focus owner.
      orbite_read_start
      orbite_record("#{label}-recovered-account", density_header, screenshot: true)
      assert_equal 0, page.evaluate_script("document.scrollingElement.scrollTop")
      assert_no_enqueued_jobs only: ChatResponseJob
    ensure
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    end
  end

  test "rail opener return stays inside its client scrollport" do
    %w[en fr].product([ false, true ], %w[escape close]).each do |locale, dark, closure|
      orbite_viewport(812, 375)
      orbite_select_language(locale.upcase)
      density_open(812, dark)
      orbite_tab_to("#workspace-navigation-close")
      before = density_rail_return_geometry
      page.driver.browser.action.send_keys(closure == "escape" ? :escape : :enter).perform
      assert_no_selector "#chat-history[open]", visible: :all
      assert_selector "#workspace-history-rail-trigger:focus"
      sample = density_rail_return_geometry
      orbite_record("rail-return-#{locale}-#{dark}-#{closure}", sample, screenshot: true)
      assert_equal before.fetch("readerScroll"), sample.fetch("readerScroll"), sample.to_json
      assert_equal before.fetch("rootScroll"), sample.fetch("rootScroll"), sample.to_json
      assert_equal before.fetch("railLeft"), sample.fetch("railLeft"), sample.to_json
      %w[width height].each { |dimension| assert_operator sample.fetch("button").fetch(dimension), :>=, 44, sample.to_json }
      %w[top left].each { |edge| assert_operator sample.fetch("button").fetch(edge), :>=, sample.fetch("port").fetch(edge), sample.to_json }
      %w[bottom right].each { |edge| assert_operator sample.fetch("button").fetch(edge), :<=, sample.fetch("port").fetch(edge), sample.to_json }
      orbite_assert_reachable("#workspace-history-rail-trigger")
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-history:modal"
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  private
    def density_seed
      @first.update_columns(name: "Lab")
      @second.update_columns(name: "Research")
      @first_chat = workspace(:chats, :workspace_first_chat)
      @first_chat.update_columns(updated_at: Time.utc(2026, 10, 19, 10))
      @chat.update_columns(updated_at: Time.utc(2026, 10, 20, 10))
      @density_chat_ids = 12.times.map { |i| ActiveRecord::FixtureSet.identify("orbite_density_chat_#{i}") }
      @density_message_ids = 12.times.map { |i| ActiveRecord::FixtureSet.identify("orbite_density_message_#{i}") }
      assert_equal 12, @density_chat_ids.uniq.size
      assert_equal 12, @density_message_ids.uniq.size
      refute Chat.where(id: @density_chat_ids).exists?
      refute Message.where(id: @density_message_ids).exists?
      @density_titles = { @first_chat.id => "First account question", @chat.id => "What are the key findings in this report?" }
      rows = @density_chat_ids.each_with_index.map do |id, i|
        timestamp = Time.utc(2026, 10, 31, 10) - i.minutes
        @density_titles[id] = format("History sample %02d", i)
        { id: id, user_id: @user.id, account_id: i.even? ? @first.id : @second.id,
          ruby_llm_model_id: @chat.ruby_llm_model_id, chat_id: nil, created_at: timestamp, updated_at: timestamp }
      end
      Chat.insert_all!(rows)
      Message.insert_all!(rows.each_with_index.map do |row, i|
        { id: @density_message_ids.fetch(i), chat_id: row.fetch(:id), role: 20, response_number: 0,
          content: @density_titles.fetch(row.fetch(:id)), created_at: row.fetch(:created_at), updated_at: row.fetch(:updated_at) }
      end)
      assert_equal 14, @user.recent_conversations.count
    end

    def density_expected(locale)
      @user.recent_conversations.map do |conversation|
        { "id" => conversation.id.to_s, "title" => @density_titles.fetch(conversation.id),
          "account" => conversation.account.name, "datetime" => conversation.updated_at.iso8601,
          "date" => I18n.l(conversation.updated_at, format: :short, locale: locale), "href" => chat_path(conversation) }
      end
    end

    def density_open(width, dark)
      visit chat_path(@chat)
      assert_selector "lexxy-editor[connected]"
      orbite_theme(dark)
      if width < 1280
        find(orbite_navigation_trigger).click
        assert_selector "#chat-history:modal"
      else
        assert_selector "#chat-history[data-inline=true][open]"
      end
      orbite_settle
    end

    def density_characterization
      page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector('#chat-history'), content = panel.querySelector('.n-orbite-panel-content')
          const list = panel.querySelector('.n-chat-history-list'), rect = node => node.getBoundingClientRect().toJSON(), bounds = rect(content)
          const rows = [...panel.querySelectorAll('[data-history-chat]')].map(row => {
            const link = row.querySelector(':scope > div > a'), title = link.querySelector('.n-chat-history-title') || link
            const account = link.querySelector('.n-chat-history-account') || row.querySelector(':scope > div > p'), time = row.querySelector('time'), box = rect(row)
            return { semantic: { id: row.dataset.historyChat, title: title.textContent.trim(), account: account.textContent.trim(),
              datetime: time.getAttribute('datetime'), date: time.textContent.trim(), href: link.getAttribute('href') }, box,
              complete: box.top >= bounds.top && box.bottom <= bounds.bottom && box.left >= bounds.left && box.right <= bounds.right }
          })
          return { version: 1, viewport: [innerWidth, innerHeight], mode: panel.matches(':modal') ? 'modal' : 'inline',
            panel: rect(panel), content: bounds, list: rect(list), scrollTop: content.scrollTop,
            overflow: { root: document.documentElement.scrollWidth - innerWidth, content: content.scrollWidth - content.clientWidth },
            rows, fullyVisible: rows.filter(row => row.complete).length }
        })()
      JS
    end

    def density_rows
      page.evaluate_script(<<~JS)
        (() => {
          #{density_paint_functions}
          const panel = document.querySelector('#chat-history'), content = panel.querySelector('.n-orbite-panel-content')
          const rect = node => node.getBoundingClientRect().toJSON()
          const inside = (a, b) => a.left >= b.left - 1 && a.right <= b.right + 1 && a.top >= b.top - 1 && a.bottom <= b.bottom + 1
          const label = node => { const style = getComputedStyle(node); return { box: rect(node), whiteSpace: style.whiteSpace,
            overflowX: style.overflowX, textOverflow: style.textOverflow, lineHeight: parseFloat(style.lineHeight),
            fontSize: parseFloat(style.fontSize), clientWidth: node.clientWidth, scrollWidth: node.scrollWidth, contrast: paint(node, 'color') } }
          return { panel: rect(panel), content: rect(content), overflow: { root: document.documentElement.scrollWidth - innerWidth,
            content: content.scrollWidth - content.clientWidth },
            rows: [...panel.querySelectorAll('[data-history-chat]')].map(row => {
              const body = row.querySelector(':scope > div'), link = body.querySelector('a')
              const title = link.querySelector('.n-chat-history-title') || link, account = link.querySelector('.n-chat-history-account') || body.querySelector('p')
              const time = row.querySelector('time'), b = rect(body), l = rect(link), t = rect(time)
              const range = document.createRange(); range.selectNodeContents(time)
              return { id: row.dataset.historyChat, row: rect(row), body: b, link: l,
                semantic: { id: row.dataset.historyChat, title: title.textContent.trim(), account: account.textContent.trim(),
                  datetime: time.getAttribute('datetime'), date: time.textContent.trim(), href: link.getAttribute('href') },
                nativeTitle: link.getAttribute('title'), nativeAccount: account.getAttribute('title'), linkText: link.textContent,
                title: label(title), account: label(account), date: label(time),
                labelsFit: [title, account].every(node => inside(rect(node), l)),
                dateFits: t.width > 0 && t.height > 0 && range.getClientRects().length > 0 && inside(t, l) && [...range.getClientRects()].every(glyph => inside(glyph, t) && inside(glyph, l)) }
            }) }
        })()
      JS
    end

    def density_assert_label(label)
      assert_equal "nowrap", label.fetch("whiteSpace"), label.to_json
      assert_equal "hidden", label.fetch("overflowX"), label.to_json
      assert_equal "ellipsis", label.fetch("textOverflow"), label.to_json
      assert_operator label.fetch("box").fetch("width"), :>, 0, label.to_json
      assert_operator label.fetch("box").fetch("height"), :>, 0, label.to_json
      assert_operator label.fetch("box").fetch("height"), :<=, label.fetch("lineHeight") + 1, label.to_json
      assert_operator label.fetch("contrast").fetch("ratio"), :>=, 4.5, label.to_json
    end

    def density_assert_row(row)
      %w[title account].each { |name| density_assert_label(row.fetch(name)) }
      assert row.fetch("labelsFit"), row.to_json
      assert row.fetch("dateFits"), row.to_json
      refute_equal "ellipsis", row.fetch("date").fetch("textOverflow"), row.to_json
      assert_operator row.fetch("date").fetch("contrast").fetch("ratio"), :>=, 4.5, row.to_json
      assert_in_delta 14, row.fetch("title").fetch("fontSize"), 0.1, row.to_json
      %w[account date].each { |name| assert_in_delta 12, row.fetch(name).fetch("fontSize"), 0.1, row.to_json }
      minimum = row.fetch("title").fetch("fontSize") * 8
      %w[body link].each { |name| assert_operator row.fetch(name).fetch("width"), :>=, minimum, row.to_json }
      assert_operator row.fetch("account").fetch("box").fetch("width"), :>=,
        [ row.fetch("title").fetch("box").fetch("width"), 4 * row.fetch("account").fetch("fontSize") ].min, row.to_json
      %w[width height].each { |dimension| assert_operator row.fetch("link").fetch(dimension), :>=, 44, row.to_json }
      assert_in_delta row.fetch("row").fetch("width"), row.fetch("link").fetch("width"), 1, row.to_json
      assert_operator row.fetch("link").fetch("left"), :>=, row.fetch("row").fetch("left"), row.to_json
      assert_operator row.fetch("link").fetch("right"), :<=, row.fetch("row").fetch("right"), row.to_json
    end

    def density_tab_to(selector, label:, reverse: false, in_content: true)
      sample = orbite_tab_to(selector, reverse: reverse)
      if in_content
        content = page.evaluate_script("document.querySelector('#chat-history .n-orbite-panel-content').getBoundingClientRect().toJSON()")
        %w[top left].each { |edge| assert_operator sample.fetch(edge), :>=, content.fetch(edge), sample.to_json }
        %w[bottom right].each { |edge| assert_operator sample.fetch(edge), :<=, content.fetch(edge), sample.to_json }
      end
      contrast = page.evaluate_script("(() => { #{density_paint_functions}; return paint(document.activeElement, 'outlineColor') })()")
      assert_operator contrast.fetch("ratio"), :>=, 3, contrast.to_json
      orbite_record("#{label}-focus-#{selector}-#{reverse}", sample.merge(contrast: contrast), screenshot: true)
      sample
    end

    def density_header
      page.evaluate_script(<<~JS)
        (() => {
          const sample = selector => {
            const node = document.querySelector(selector), style = getComputedStyle(node), box = node.getBoundingClientRect()
            const range = document.createRange(); range.selectNodeContents(node)
            const glyphs = [...range.getClientRects()].map(rect => rect.toJSON())
            return { selector, text: node.textContent.trim(), visible: node.checkVisibility(), box: box.toJSON(),
              whiteSpace: style.whiteSpace, overflowX: style.overflowX, textOverflow: style.textOverflow, glyphs,
              glyphsFit: glyphs.length > 0 && glyphs.every(glyph => glyph.left >= box.left - 1 && glyph.right <= box.right + 1 && glyph.top >= box.top - 1 && glyph.bottom <= box.bottom + 1) }
          }
          return { previews: ['.n-chat-header .n-chat-heading h1'].map(sample),
            reading: ['.n-chat-transcript .n-chat-user-body', '#chat-usage-details > p'].map(sample),
            reader: document.querySelector('[data-application-scroll]').getBoundingClientRect().toJSON(),
            readerScrollTop: document.querySelector('[data-application-scroll]').scrollTop }
        })()
      JS
    end

    def density_rail_return_geometry
      page.evaluate_script(<<~JS)
        (() => {
          const button = document.querySelector('#workspace-history-rail-trigger')
          const rail = button.closest('.n-orbite-rail'), box = rail.getBoundingClientRect()
          const reader = document.querySelector('[data-application-scroll]'), root = document.scrollingElement
          return { button: button.getBoundingClientRect().toJSON(), railTop: rail.scrollTop, railLeft: rail.scrollLeft,
            port: { top: box.top + rail.clientTop, left: box.left + rail.clientLeft,
              bottom: box.top + rail.clientTop + rail.clientHeight, right: box.left + rail.clientLeft + rail.clientWidth },
            readerScroll: [reader.scrollLeft, reader.scrollTop], rootScroll: [root.scrollLeft, root.scrollTop] }
        })()
      JS
    end

    # Measure actual computed ancestor paint, not palette constants or screenshots.
    def density_paint_functions
      <<~JS
        const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1
        const context = canvas.getContext('2d', { willReadFrequently: true, colorSpace: 'srgb' })
        const rgba = color => {
          if (!CSS.supports('color', color)) throw new Error(`Unparsed History color: ${color}`)
          context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1)
          return [...context.getImageData(0, 0, 1, 1).data].map(channel => channel / 255)
        }
        const over = (fg, bg) => [...fg.slice(0, 3).map((channel, i) => channel * fg[3] + bg[i] * (1 - fg[3])), 1]
        const luminance = color => color.slice(0, 3).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4)
          .reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0)
        const paint = (element, property) => {
          const modal = element.closest('dialog:modal'), chain = []
          for (let node = element; node; node = node.parentElement) { chain.unshift(node); if (node === modal) break }
          if (modal && rgba(getComputedStyle(modal).backgroundColor)[3] !== 1) throw new Error('History modal must have opaque paint')
          const backgrounds = chain.map(node => {
            const style = getComputedStyle(node)
            if (style.backgroundImage !== 'none' || Number(style.opacity) !== 1 || style.filter !== 'none' || style.backdropFilter !== 'none' || style.mixBlendMode !== 'normal')
              throw new Error(`Unmeasured History paint effect on ${node.tagName}`)
            return style.backgroundColor
          })
          if (!backgrounds.some(color => rgba(color)[3] === 1)) throw new Error('History has no opaque backing')
          const background = backgrounds.reduce((bg, color) => over(rgba(color), bg), [1, 1, 1, 1])
          const color = getComputedStyle(element)[property], foreground = over(rgba(color), background)
          const a = luminance(foreground), b = luminance(background)
          return { property, color, foreground, background, backgrounds, ratio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05) }
        }
      JS
    end
end
