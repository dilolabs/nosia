require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class AccountExperienceSystemTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    FileUtils.mkdir_p("/tmp/opencode")
    visit root_url
    @original_window_size = page.current_window.size
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    if @account_viewport_override
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
    page.current_window.resize_to(*@original_window_size) if @original_window_size
  end

  test "balanced account layout stacks without overflow and does not restrict viewport zoom" do
    visit account_path(@second)
    assert_selector "[data-account-overview='#{@second.id}']"
    viewport = find("meta[name='viewport']", visible: :all)["content"]
    assert_match(/\bwidth\s*=\s*device-width\b/, viewport)
    assert_match(/\binitial-scale\s*=\s*1\.0\b/, viewport)
    refute_match(/maximum-scale|user-scalable\s*=\s*no/, viewport)
    assert_equal "grid", page.evaluate_script("getComputedStyle(document.querySelector('.n-account-columns')).display")

    [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
      resize_account_viewport(width, height)
      assert_selector "a[href='#{new_chat_path(account_id: @second.id)}']", text: "New conversation"
      assert_equal width >= 1280 ? 2 : 1, account_column_count(".n-account-columns"), "Overview columns at #{width}x#{height}"
      assert_main_without_horizontal_overflow
    end
  end

  test "account directory cards adapt without horizontal overflow" do
    visit accounts_path
    assert_selector ".n-account-cards [data-account-id='#{@second.id}']"
    assert_equal "grid", page.evaluate_script("getComputedStyle(document.querySelector('.n-account-cards')).display")

    [ [ 375, 812, 1 ], [ 768, 1024, 2 ], [ 1440, 1000, 3 ], [ 812, 375, 2 ] ].each do |width, height, columns|
      resize_account_viewport(width, height)
      assert_equal columns, account_column_count(".n-account-cards"), "Directory columns at #{width}x#{height}"
      within "[data-account-id='#{@second.id}']" do
        assert_selector "a[href='#{account_path(@second)}']", text: "View account"
        assert_selector "a[href='#{new_chat_path(account_id: @second.id)}']", text: "New conversation"
      end
      assert_main_without_horizontal_overflow
    end
  end

  test "directory and keyboard navigation open the second account composer without changing the default" do
    visit accounts_path
    verify_account_keyboard_actions
    within "[data-account-id='#{@second.id}']" do
      click_on "View account"
    end
    assert_current_path account_path(@second)
    tab_to_account_action(new_chat_path(account_id: @second.id))
    assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.activeElement).outlineWidth)"), :>=, 2
    page.send_keys(:enter)

    assert_current_path new_chat_path(account_id: @second.id)
    assert_selector "select[name='chat[account_id]'] option[value='#{@second.id}']:checked"
    assert_equal @first, @user.first_account
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "hub source and private history links retain the second account" do
    resize_account_viewport(1440, 1000)
    visit account_path(@second)
    find("[data-source-type='document']").click
    assert_current_path account_sources_path(@second, type: "document")
    assert_selector "[data-source-id='#{experience(:documents, :overview_second_document).id}']"
    assert_selector "[data-source-id]", count: 1
    assert_no_selector "[data-source-id='#{experience(:documents, :overview_first_document).id}']"

    visit account_path(@second)
    click_on "Research question 27"
    assert_current_path chat_path(experience(:chats, :overview_second_chat_27))
    assert_text "Research question 27"
    assert_no_text "Member private question"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "history previews shorten long prompts but open the full saved conversation" do
    chat = experience(:chats, :overview_second_chat_27)
    message = experience(:messages, :overview_second_question_27)
    prompt = "Résumé détaillé " * 30
    message.update_columns(content: prompt)
    expected = "#{prompt[0, 119]}…"

    visit account_chats_path(@second)

    assert_selector "[data-conversation-id]", count: 25
    within "[data-conversation-id='#{chat.id}']" do
      assert_equal expected, find("a").text
      assert_selector "a[href='#{chat_path(chat)}']"
      assert_selector "time[datetime='#{chat.updated_at.iso8601}']"
      click_on expected
    end
    assert_current_path chat_path(chat)
    assert_selector "#messages_message_#{message.id}", text: prompt.strip, exact_text: true
    assert_equal prompt, message.reload.content

    visit account_chats_path(@second)
    assert_selector "[data-conversation-id] a", text: "Research question 26", exact_text: true
    assert_no_text "Member private question"
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "history wraps long unbroken account names at 375 pixels" do
    @second.update_columns(name: "ResearchAccount" * 12)
    resize_account_viewport(375, 812)
    visit account_chats_path(@second)

    assert_current_path account_chats_path(@second)
    assert_selector "h1", text: @second.name
    assert_no_text "Member private question"
    assert_no_selector "[data-conversation-id='#{experience(:chats, :overview_first_chat).id}']"
    assert_no_selector "[data-conversation-id='#{experience(:chats, :overview_foreign_chat).id}']"
    metrics = page.evaluate_script(<<~JS)
      (() => {
        const main = document.querySelector('main');
        return {viewport: [innerWidth, innerHeight], scroll_width: main.scrollWidth, client_width: main.clientWidth,
          heading_wrap: getComputedStyle(document.querySelector('h1')).overflowWrap};
      })()
    JS
    record_account_evidence("history-long-name-375", metrics)
    assert_main_without_horizontal_overflow
    save_account_evidence("history-long-name-375")

    [ "nav a[href='#{account_path(@second)}']", ".n-account-primary", "a[rel='next']" ].each do |selector|
      action = find(selector)
      page.execute_script("arguments[0].scrollIntoView({block: 'center'})", action)
      assert action.visible?
      assert page.evaluate_script(<<~JS, action), "History action must fit the viewport: #{selector}"
        (() => {
          const e = arguments[0], r = e.getBoundingClientRect();
          const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
          return r.left >= 0 && r.right <= innerWidth && !!hit && (hit === e || e.contains(hit));
        })()
      JS
    end
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "owner saves account details and creates a personal token in the same account" do
    visit account_path(@second)
    click_on "Edit account"
    fill_in "account_name", with: "Browser research"
    click_on "Save"
    assert_current_path account_path(@second)
    assert_selector "h1", text: "Browser research"
    click_on "Manage your tokens"
    assert_current_path account_api_tokens_path(@second)
    fill_in "api_token_name", with: "Browser deployment"
    click_on "Generate"
    assert_current_path account_api_tokens_path(@second)
    assert_text "Copy it now"
    assert_selector "input[readonly][data-clipboard-target='source']"
    assert_selector "button[data-action='clipboard#copy']"
    token = ApiToken.find_by!(name: "Browser deployment")
    assert_equal [ @user.id, @second.id ], [ token.user_id, token.account_id ]
    visit account_api_tokens_path(@second)
    assert_no_text "Copy it now"
    assert_no_selector "input[data-clipboard-target='source']"
    assert_equal @first, @user.first_account
  end

  test "long French account content remains accessible in distinct light and dark surfaces" do
    @second.update_columns(name: "Un compte de recherche avec un nom très long " * 4, uid: "unbroken-identifiant-" * 8)
    visit account_path(@second)
    select "FR", from: "language_preference_locale"
    assert_selector "html[lang='fr']"
    assert_selector "h2", text: "Vos conversations récentes"
    resize_account_viewport(375, 812)
    surfaces = []

    %w[light dark].each do |theme|
      set_account_theme(theme)
      assert_selector "h1", text: @second.name.strip
      assert_selector "a", text: "Nouvelle conversation"
      assert_no_text(/translation missing|missing translation/i)
      assert_main_without_horizontal_overflow
      surfaces << page.evaluate_script("getComputedStyle(document.querySelector('.n-account-panel')).backgroundColor")
      verify_account_keyboard_actions
      record_account_contrast("375-#{theme}")
      page.execute_script("document.querySelector('main').scrollTop = 0")
      save_account_evidence("375-#{theme}")
      page.execute_script("document.querySelector('.n-account-columns').scrollIntoView({block: 'start'})")
      save_account_evidence("375-#{theme}-content")
    end
    refute_equal surfaces.first, surfaces.last
    assert_equal @first, @user.first_account
  end

  test "desktop member empty and invalid source states have browser evidence" do
    visit account_path(@second)
    set_account_theme("light")
    resize_account_viewport(1440, 1000)
    verify_account_keyboard_actions
    record_account_contrast("1440-light")
    page.execute_script("document.querySelector('main').scrollTop = 0")
    save_account_evidence("1440-light")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    assert page.evaluate_script("Array.from(document.querySelectorAll('.n-accounts a')).every(e => getComputedStyle(e).transitionDuration === '0s')")
    record_account_evidence("reduced-motion", { effective: true, account_link_transitions: "0s" })

    visit account_path(@empty)
    assert_text "Your private conversation history will appear here."
    assert_no_selector "[data-conversation-id]"
    save_account_evidence("empty-hub")

    visit new_account_sources_document_path(@second)
    fill_in "document_title", with: "Keep browser title"
    assert_no_difference [ "Document.count", "ActiveStorage::Blob.count" ] do
      click_on "Save"
      assert_selector "[role='alert'] li", text: /File/
    end
    assert_selector "input[name='document[title]'][value='Keep browser title']"
    assert_no_enqueued_jobs only: [ AddDocumentJob, ChatResponseJob ]
    save_account_evidence("source-validation-error")

    find("#dropdownUser").click
    click_on "Sign out"
    fill_in "email", with: @member.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
    visit account_path(@second)
    assert_text "Member private question"
    assert_no_text "Research question 27"
    assert_no_link "Edit account"
    assert_no_link "Manage users"
    save_account_evidence("member")
  end

  test "native browser zoom is attempted separately from viewport emulation" do
    visit account_path(@second)
    before = page.evaluate_script("({innerWidth, outerWidth, devicePixelRatio})")
    5.times { page.driver.browser.action.key_down(:control).send_keys(:add).key_up(:control).perform }
    after = page.evaluate_script("({innerWidth, outerWidth, devicePixelRatio})")
    verified = after["outerWidth"] == before["outerWidth"] && after["devicePixelRatio"] == before["devicePixelRatio"] * 2 && (after["innerWidth"] * 2 - before["innerWidth"]).abs <= 2
    record_account_evidence("native-zoom", { before: before, after: after, status: verified ? "VERIFIED 200% native browser zoom" : "UNVERIFIED: headless Chrome did not apply native Ctrl+Add zoom; viewport/CDP/CSS simulations are not zoom evidence" })
  ensure
    page.driver.browser.action.key_down(:control).send_keys("0").key_up(:control).perform
  end

  private
    def take_failed_screenshot
      # Failure artifacts must never disclose a newly generated bearer token.
      page.execute_script("document.querySelectorAll('[data-clipboard-target=source]').forEach(e => { e.value = '[REDACTED]'; e.setAttribute('value', '[REDACTED]'); })")
      super
    end

    def tab_to_account_action(path)
      80.times do
        page.send_keys(:tab)
        return if page.evaluate_script("document.activeElement.getAttribute('href')") == path
      end
      flunk "Account action was not reachable by Tab: #{path}"
    end

    def set_account_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      if page.evaluate_script("localStorage.getItem('color-theme')").nil?
        2.times { find("#theme-toggle").click }
      end
      assert_equal theme, page.evaluate_script("localStorage.getItem('color-theme')")
    end

    def verify_account_keyboard_actions
      expected = page.all(".n-accounts a").map { |link| link[:href] }.uniq
      seen = []
      order = []
      100.times do
        page.send_keys(:tab)
        state = page.evaluate_script(<<~JS)
          (() => {
            const e = document.activeElement;
            if (!e.matches('.n-accounts a')) return null;
            const r = e.getBoundingClientRect(), s = getComputedStyle(e);
            // Edge midpoints avoid the intentionally empty corners of rounded buttons.
            const points = [[r.x + r.width / 2, r.y + 1], [r.x + r.width / 2, r.bottom - 1],
              [r.x + 1, r.y + r.height / 2], [r.right - 1, r.y + r.height / 2]];
            const main = document.querySelector('main').getBoundingClientRect();
            const unobscured = points.every(([x, y]) => {
              const hit = document.elementFromPoint(x, y);
              return !!hit && (hit === e || e.contains(hit));
            });
            return {href: e.href, text: e.textContent.trim(), outline: parseFloat(s.outlineWidth),
              unobscured: unobscured && r.top >= Math.max(0, main.top) && r.bottom <= Math.min(innerHeight, main.bottom),
              top: r.top, bottom: r.bottom};
          })()
        JS
        next unless state

        assert_operator state.fetch("outline"), :>=, 2
        assert state.fetch("unobscured"), "Focused account action is obscured: #{state.fetch('text')}"
        seen << state.fetch("href")
        order << state.fetch("text")
        break if (expected - seen).empty?
      end
      assert_empty expected - seen, "Every account action must be reachable by real Tab navigation"
      assert_equal expected, seen.uniq, "Tab follows account actions in DOM reading order"
      page.send_keys([ :shift, :tab ])
      assert_equal seen[-2], page.evaluate_script("document.activeElement.href")
      record_account_evidence("keyboard", { viewport: page.evaluate_script("[innerWidth, innerHeight]"), order: order, shift_tab_returned_to_previous: true, unobscured_edge_midpoints_and_main_bounds: true, outline_min_px: 2 })
    end

    def save_account_evidence(name)
      page.save_screenshot("/tmp/opencode/account-experience-#{name}.png")
    end

    def record_account_evidence(name, data)
      File.open("/tmp/opencode/account-experience-task10-evidence.jsonl", "a") { |file| file.puts({ check: name, data: data }.to_json) }
    end

    def record_account_contrast(name)
      tab_to_account_action(URI(find(".n-account-primary", match: :first)[:href]).request_uri)
      rows = page.evaluate_script(<<~JS)
        (() => {
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
          const ctx = canvas.getContext('2d', {willReadFrequently: true});
          function rgba(color) {
            ctx.clearRect(0, 0, 1, 1); ctx.fillStyle = color; ctx.fillRect(0, 0, 1, 1);
            const p = Array.from(ctx.getImageData(0, 0, 1, 1).data); p[3] /= 255; return p;
          }
          function blend(front, back) { return front.slice(0, 3).map((v, i) => v * front[3] + back[i] * (1 - front[3])); }
          function background(e) {
            const ancestors = []; for (let a = e; a; a = a.parentElement) ancestors.unshift(a);
            return ancestors.reduce((bg, a) => {
              const s = getComputedStyle(a);
              if (s.backgroundImage !== 'none' || s.opacity !== '1') throw new Error('Unmeasured gradient/opacity surface');
              return blend(rgba(s.backgroundColor), bg);
            }, [255, 255, 255]);
          }
          function luminance(rgb) { return rgb.map(v => { v /= 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0); }
          function measure(selector, kind, minimum) {
            const e = document.querySelector(selector), s = getComputedStyle(e);
            const bg = background(kind === 'focus' ? e.parentElement : e);
            const fg = blend(rgba(kind === 'focus' ? s.outlineColor : s.color), bg);
            const a = luminance(fg), b = luminance(bg);
            return {selector, kind, foreground: fg, composed_background: bg,
              ratio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05), minimum};
          }
          return [
            ...['.n-accounts h1', '.n-account-panel h2', '.n-account-help', '.n-account-panel .n-account-help', '.n-account-prompt',
              '.n-account-primary', '.n-account-secondary', '.n-accounts .n-account-link', '.n-account-source span'].map(s => measure(s, 'text', 4.5)),
            measure('.n-account-source svg', 'icon', 3), measure('.n-accounts a:focus', 'focus', 3)
          ];
        })()
      JS
      record_account_evidence("contrast-#{name}", rows)
      rows.each do |row|
        assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), "#{name} #{row.fetch('selector')} #{row.fetch('kind')} contrast"
      end
    end

    def resize_account_viewport(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[window.innerWidth, window.innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @account_viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[window.innerWidth, window.innerHeight]")
    end

    def account_column_count(selector)
      page.evaluate_script("getComputedStyle(document.querySelector(arguments[0])).gridTemplateColumns", selector).split.size
    end

    def assert_main_without_horizontal_overflow
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1"),
        "Account content overflows at #{page.evaluate_script('[window.innerWidth, window.innerHeight]').join('x')}"
    end
end
