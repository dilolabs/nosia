require "application_system_test_case"
require_relative "../support/chat_account_fixtures"
require_relative "../support/orbite_browser_checks"

class LocalizationSystemTest < ApplicationSystemTestCase
  include OrbiteBrowserChecks
  include ChatAccountFixtures
  include ActionCable::TestHelper
  include ActionView::RecordIdentifier

  teardown { Capybara.reset_sessions! }

  test "changing language reloads the current account URL and Turbo history stays French" do
    sign_in_with_language("EN", "en", "Sign in")
    url = new_chat_url(account_id: @second.id, model: "picker-test-model")
    visit url
    assert_selector "lexxy-editor[connected]"
    previous_origin = page.evaluate_script("performance.timeOrigin")

    orbite_select_language("FR")

    assert_selector "html[lang=fr]"
    assert_current_path url
    assert_selector "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
    assert_selector "button[aria-label=Envoyer]"
    french_origin = page.evaluate_script("performance.timeOrigin")
    assert_not_equal previous_origin, french_origin

    page.execute_script("Turbo.visit(arguments[0])", sources_path)
    assert_current_path sources_path
    assert_selector "input[placeholder='Rechercher des sources…']"
    assert_equal french_origin, page.evaluate_script("performance.timeOrigin")
    page.go_back

    assert_current_path url
    assert_selector "html[lang=fr]"
    assert_selector "button[aria-label=Envoyer]"
    assert_no_selector "button[aria-label=Send]"
  end

  test "one live generation event reaches separate English and French Chrome sessions" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    localized_browsers.each do |session, language, locale, sign_in|
      Capybara.using_session(session) do
        sign_in_with_language(language, locale, sign_in)
        visit chat_url(chat)
        assert_selector "html[lang=#{locale}]"
        assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
        assert_selector "#thinking_animation"
      end
    end

    chat.broadcast_thinking_phase("indexing")

    { english: "Indexing your attachments", french: "Indexation de vos pièces jointes" }.each do |session, label|
      Capybara.using_session(session) { assert_selector "#thinking_animation", text: label }
    end

    chat.finish_generation!

    { english: "Send", french: "Envoyer" }.each do |session, label|
      Capybara.using_session(session) do
        assert_selector "button[aria-label='#{label}']:not([disabled])"
        assert_no_selector "#thinking_animation"
      end
    end
  ensure
    Capybara.reset_sessions!
  end

  test "one live source indexing and deletion event updates both browsers in the default account" do
    source = texts(:picker_first_text)
    source.update_columns(index_status: "pending")
    row = "##{dom_id(source, :source_row)}"
    localized_browsers.each do |session, language, locale, sign_in|
      Capybara.using_session(session) do
        sign_in_with_language(language, locale, sign_in)
        visit sources_url
        assert_selector "html[lang=#{locale}]"
        assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
        assert_selector row
        assert_no_selector "##{dom_id(texts(:picker_second_text), :source_row)}"
      end
    end

    source.mark_indexed!

    { english: "Indexed", french: "Indexé" }.each do |session, label|
      Capybara.using_session(session) { assert_selector row, text: label }
    end

    source.destroy!
    remaining = SourceRow.counts_for(@first).fetch(:total)

    localized_browsers.each do |session, *|
      Capybara.using_session(session) do
        assert_no_selector row
        assert_selector "#source_count_all", exact_text: remaining.to_s
      end
    end
  ensure
    Capybara.reset_sessions!
  end

  test "French language switcher remains keyboard accessible at 375px in both themes" do
    sign_in_with_language("FR", "fr", "Se connecter")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 900, deviceScaleFactor: 1, mobile: false)

    [ new_chat_url(account_id: @second.id), sources_url ].each do |url|
      visit url
      assert_selector "html[lang=fr]"
      [ false, true ].each do |dark|
        orbite_theme(dark)
        observe_language_navigation
        opener = open_language_navigation(reverse: dark)
        assert_equal 375, page.evaluate_script("innerWidth")
        assert_selector ".n-language-preference label.sr-only[for=language_preference_locale]", text: "Langue", visible: :all
        assert_selector ".n-language-preference select#language_preference_locale[aria-describedby=language_preference_hint]"
        assert_selector "#language_preference_hint", text: I18n.t("nosia.language.auto_switch_hint", locale: :fr), visible: :all
        assert_equal %w[auto fr en], all("#language_preference_locale option", visible: :all).map(&:value)
        assert_equal "fr", find("#language_preference_locale").value
        assert_selector "#language_preference_locale:focus-visible"
        assert_language_control_geometry
        record_language_navigation("keyboard-select-#{dark}")

        page.driver.browser.action.send_keys(:escape).perform
        assert_no_selector "#chat-history[open]", visible: :all
        assert_no_selector "dialog:modal"
        assert_selector "#{opener}:focus-visible"
        assert_selector "#{opener}[aria-expanded=false]"
        assert_operator orbite_assert_reachable(opener).fetch("outlineWidth"), :>=, 2
        sample = record_language_navigation("keyboard-after-escape-#{dark}")
        refute sample.fetch("active").fetch("inert"), sample.to_json
      end
    end

    open_language_navigation
    record_language_navigation("keyboard-before-end")
    previous_origin = page.evaluate_script("performance.timeOrigin")
    page.driver.browser.action.send_keys(:end).perform

    assert_selector "html[lang=en]"
    assert_current_path sources_path
    assert_not_equal previous_origin, page.evaluate_script("performance.timeOrigin")
    assert_selector "input[placeholder='Search sources…']"
    assert_selector "#language_preference_locale option[value=en][selected]", visible: :all
    orbite_record("language-native-end-reload", { before_origin: previous_origin,
      after_origin: page.evaluate_script("performance.timeOrigin"), url: page.current_url }, screenshot: true)
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "language switcher is a single compact control in both locales and themes" do
    visit root_url
    assert_no_selector "#orbite-shell", visible: :all
    assert_no_selector "#chat-history", visible: :all
    assert_selector "nav form[action='/language_preference']", count: 1
    assert_selector "nav form[action='/language_preference'] select", count: 1
    assert_selector "nav form[action='/language_preference'][method=post][data-turbo=false] input[name='_method'][value=patch]", visible: :all

    { "EN" => "en", "FR" => "fr" }.each do |language, locale|
      select language, from: "language_preference_locale"
      assert_selector "html[lang=#{locale}]"

      [ 320, 375, 1400 ].each do |width|
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 900, deviceScaleFactor: 1, mobile: false)
        [ false, true ].each do |dark|
          page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
          layout = page.evaluate_script(<<~JS)
            (() => {
              const form = document.querySelector('nav form[action="/language_preference"]');
              const select = form.querySelector('select');
              const label = form.querySelector('label');
              const box = element => {
                const { width, height } = element.getBoundingClientRect();
                return { width, height };
              };
              return { select: box(select), form: box(form), label: box(label),
                rootFont: getComputedStyle(document.documentElement).fontSize,
                minHeight: getComputedStyle(select).minHeight,
                overflow: document.documentElement.scrollWidth - innerWidth };
            })()
          JS

          orbite_record("public-language-#{locale}-#{width}-#{dark}", layout, screenshot: true)
          assert_equal "16px", layout.fetch("rootFont")
          assert_in_delta layout.dig("select", "height"), layout.dig("form", "height"), 1
          assert_operator layout.dig("select", "width"), :<=, 80
          assert_operator layout.dig("select", "width"), :>=, 44
          assert_operator layout.dig("select", "height"), :>=, 44
          assert_in_delta 44, layout.dig("select", "height"), 1
          assert_equal 1, layout.dig("label", "width")
          assert_equal 1, layout.dig("label", "height")
          assert_equal 0, layout.fetch("overflow")
          assert_selector "nav form[action='/language_preference'] svg[aria-hidden=true]"
          assert_no_selector "nav form[action='/language_preference'] button"
        end
      end
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "choosing Auto immediately restores the browser language" do
    visit root_url
    find("#language_preference_locale option[value=fr]", visible: :all).select_option
    assert_selector "html[lang=fr]"
    previous_origin = page.evaluate_script("performance.timeOrigin")

    select "Auto", from: "language_preference_locale"

    assert_selector "html[lang=en]"
    assert_selector "select#language_preference_locale option[value=auto][selected]", visible: :all
    assert_not_equal previous_origin, page.evaluate_script("performance.timeOrigin")
  end

  test "French oversized uploads show translated feedback and unblock sending when removed" do
    visit root_url
    select "FR", from: "language_preference_locale"
    assert_button "Se connecter"
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_button "Se connecter"
    assert_selector "select[name='chat[account_id]']"

    visit user_root_url(account_id: @second.id)
    assert_selector "lexxy-editor[connected]"

    filenames = [ "huge.pdf", "cost$&.pdf", "cost$$.pdf", "cost$`.pdf", "cost$'.pdf" ]
    messages = filenames.map do |filename|
      page.execute_script <<~JS, filename
        const root = document.querySelector('[data-controller~="dropzone"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "dropzone")
        controller._processFiles([new File([new Uint8Array(51 * 1024 * 1024)], arguments[0], { type: "application/pdf" })])
      JS

      message = find('[data-dropzone-target="list"] [role="alert"]').text
      assert_button "Retirer le fichier"
      assert_selector "button[aria-label=Envoyer][disabled]"

      click_button "Retirer le fichier"

      assert_no_selector '[data-dropzone-target="list"] [role="alert"]'
      assert_selector "button[aria-label=Envoyer]:not([disabled])"
      message
    end

    assert_equal filenames.map { |filename| "Fichier non valide : #{filename}" }, messages
  end

  test "French composer feedback uses the server dictionary and resets failed sources" do
    visit root_url
    select "FR", from: "language_preference_locale"
    assert_button "Se connecter"
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_button "Se connecter"
    assert_selector "select[name='chat[account_id]']"

    visit new_chat_url(account_id: @second.id)
    assert_selector "lexxy-editor[connected]"
    assert_selector ".n-chat-composer[data-composer-sources-messages-value]"

    page.execute_script <<~JS
      const root = document.querySelector('[data-controller~="composer-sources"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "composer-sources")
      controller.operations.set("localization-failure", {
        payload: { url: "https://example.invalid/" }, failed: true, pending: false,
        message: controller.messagesValue.registration_retry
      })
      controller.renderErrors()
      controller.publishState()
    JS

    assert_button "Réessayer la source"
    assert_button "Réinitialiser le brouillon"
    assert_selector "[data-composer-sources-target=errors]", text: "Échec de l’enregistrement de la source. Réessayez ou réinitialisez le brouillon."
    assert_selector "button[aria-label=Envoyer][disabled]"

    accept_confirm "Réinitialiser ce brouillon non envoyé ? Les sources enregistrées resteront dans leur compte." do
      click_button "Réinitialiser le brouillon"
    end

    assert_no_button "Réessayer la source"
    assert_selector "button[aria-label=Envoyer]:not([disabled])"
  end

  private
    def open_language_navigation(reverse: false)
      opener = page.has_selector?("[data-orbite-composer-navigation]", wait: 0) ? "[data-orbite-composer-navigation]" : "#workspace-mobile-trigger"
      orbite_tab_to(opener, reverse: reverse)
      page.driver.browser.action.send_keys(:enter).perform
      assert_selector "#chat-history:modal"
      assert_selector "dialog:modal", count: 1
      orbite_tab_to("#language_preference_locale")
      assert_selector "#language_preference_locale:focus-visible"
      opener
    end

    # Passive diagnostic only: observes native DOM events, never changes delivery or focus.
    def observe_language_navigation
      page.execute_script(<<~JS)
        if (!window.languageNavigationTrace) {
          window.languageNavigationTrace = []
          window.languageNavigationSnapshot = () => {
            const sample = element => {
              if (!element) return null
              const style = getComputedStyle(element), box = element.getBoundingClientRect()
              const hit = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)
              return { id: element.id, tag: element.tagName, geometry: box.toJSON(),
                focusVisible: element.matches(':focus-visible'), outline: style.outlineStyle, outlineWidth: style.outlineWidth,
                visible: element.checkVisibility(), inert: !!element.closest('[inert]'),
                hit: !!hit && (hit === element || element.contains(hit)), expanded: element.getAttribute('aria-expanded') }
            }
            const panel = document.querySelector('#chat-history')
            return { active: sample(document.activeElement), select: sample(document.querySelector('#language_preference_locale')),
              panel: { open: panel.open, modal: panel.matches(':modal') },
              triggers: [...document.querySelectorAll('[aria-controls="chat-history"]')].map(sample), viewport: [innerWidth, innerHeight] }
          }
          for (const type of ['keydown', 'focusin', 'cancel', 'close']) {
            document.addEventListener(type, event => {
              window.languageNavigationTrace.push({ type, trusted: event.isTrusted, key: event.key || null,
                target: { id: event.target.id, tag: event.target.tagName }, time: performance.now(),
                state: window.languageNavigationSnapshot() })
            }, { capture: true, passive: true })
          }
        }
      JS
    end

    def record_language_navigation(label)
      sample = page.evaluate_script("({ ...window.languageNavigationSnapshot(), events: window.languageNavigationTrace })")
      orbite_record("language-#{label}", sample, screenshot: true)
    end

    def sign_in_with_language(language, locale, sign_in)
      visit root_url
      select language, from: "language_preference_locale"
      assert_selector "html[lang=#{locale}]"
      fill_in "email", with: @user.email
      fill_in "password", with: ChatAccountFixtures::PASSWORD
      click_button sign_in
      assert_selector "select[name='chat[account_id]']"
    end

    def localized_browsers
      [ [ :english, "EN", "en", "Sign in" ], [ :french, "FR", "fr", "Se connecter" ] ]
    end

    def assert_language_control_geometry
      layout = page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector('#chat-history');
          const form = panel.querySelector('.n-language-preference');
          const box = element => {
            const { left, right, top, bottom, width, height } = element.getBoundingClientRect();
            return { left, right, top, bottom, width, height };
          };
          const controls = [...form.querySelectorAll('select')];
          const focus = document.activeElement;
          const style = getComputedStyle(focus);
          const select = form.querySelector('select'), rect = select.getBoundingClientRect();
          const points = [[rect.x + rect.width / 2, rect.y + rect.height / 2], [rect.left + 2, rect.top + 2], [rect.right - 2, rect.bottom - 2]];
          return {
            overflow: document.documentElement.scrollWidth - innerWidth,
            panel: box(panel), form: box(form), controls: controls.map(box), logo: box(panel.querySelector('.n-orbite-logo')),
            wrap: getComputedStyle(form.parentElement).flexWrap,
            hits: points.map(([x, y]) => { const hit = document.elementFromPoint(x, y); return !!hit && (hit === select || select.contains(hit)) }),
            focus: box(focus), outline: style.outlineStyle, outlineWidth: parseFloat(style.outlineWidth), outlineOffset: parseFloat(style.outlineOffset), viewport: [innerWidth, innerHeight]
          };
        })()
      JS
      assert_equal 0, layout.fetch("overflow")
      assert_equal "wrap", layout.fetch("wrap")
      control = layout.fetch("controls").first
      logo = layout.fetch("logo")
      assert control.fetch("left") >= logo.fetch("right") || control.fetch("top") >= logo.fetch("bottom"), "Switcher must not overlap the logo"
      layout.fetch("controls").each do |box|
        assert_operator box.fetch("left"), :>=, 0
        assert_operator box.fetch("right"), :<=, 375
        assert_operator box.fetch("bottom"), :<=, layout.fetch("panel").fetch("bottom")
        assert_operator box.fetch("width"), :>=, 44
        assert_operator box.fetch("height"), :>=, 44
      end
      assert layout.fetch("hits").all?, layout.to_json
      assert_not_equal "none", layout.fetch("outline")
      assert_operator layout.fetch("outlineWidth"), :>=, 2
      focus = layout.fetch("focus")
      outset = [ layout.fetch("outlineWidth") + layout.fetch("outlineOffset"), 0 ].max
      assert_operator focus.fetch("left") - outset, :>=, 0
      assert_operator focus.fetch("right") + outset, :<=, 375
      assert_operator focus.fetch("top") - outset, :>=, 0
      assert_operator focus.fetch("bottom") + outset, :<=, layout.fetch("viewport").last
    end
end
