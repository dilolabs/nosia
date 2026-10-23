require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class LocalizationSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures
  include ActionCable::TestHelper
  include ActionView::RecordIdentifier

  teardown { Capybara.reset_sessions! }

  test "changing language reloads the current account URL and Turbo history stays French" do
    sign_in_with_language("English", "en", "Sign in")
    url = new_chat_url(account_id: @second.id, model: "picker-test-model")
    visit url
    assert_selector "lexxy-editor[connected]"
    previous_origin = page.evaluate_script("performance.timeOrigin")

    select "Français", from: "language_preference_locale"
    click_button "Apply"

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

  test "French language controls wrap and remain keyboard accessible at 375px in both themes" do
    sign_in_with_language("Français", "fr", "Se connecter")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 900, deviceScaleFactor: 1, mobile: false)

    [ new_chat_url(account_id: @second.id), sources_url ].each do |url|
      visit url
      assert_selector "html[lang=fr]"
      [ false, true ].each do |dark|
        page.execute_script("document.documentElement.classList.toggle('dark', arguments[0])", dark)
        assert_equal 375, page.evaluate_script("innerWidth")
        assert_selector "nav label[for=language_preference_locale]", text: "Langue"
        assert_selector "nav select#language_preference_locale"
        find("#language_preference_locale").send_keys(:tab)
        assert_selector "nav form button:focus-visible", text: "Appliquer"
        assert_language_control_geometry
      end
    end

    previous_origin = page.evaluate_script("performance.timeOrigin")
    select "English", from: "language_preference_locale"
    find("#language_preference_locale").send_keys(:tab)
    assert_selector "nav form button:focus-visible", text: "Appliquer"
    page.driver.browser.action.send_keys(:enter).perform

    assert_selector "html[lang=en]"
    assert_current_path sources_path
    assert_not_equal previous_origin, page.evaluate_script("performance.timeOrigin")
    assert_selector "input[placeholder='Search sources…']"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "French oversized uploads show translated feedback and unblock sending when removed" do
    visit root_url
    select "Français", from: "language_preference_locale"
    click_button "Apply"
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
    select "Français", from: "language_preference_locale"
    click_button "Apply"
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
    def sign_in_with_language(language, locale, sign_in)
      visit root_url
      select language, from: "language_preference_locale"
      click_button "Apply"
      assert_selector "html[lang=#{locale}]"
      fill_in "email", with: @user.email
      fill_in "password", with: ChatAccountFixtures::PASSWORD
      click_button sign_in
      assert_selector "select[name='chat[account_id]']"
    end

    def localized_browsers
      [ [ :english, "English", "en", "Sign in" ], [ :french, "Français", "fr", "Se connecter" ] ]
    end

    def assert_language_control_geometry
      layout = page.evaluate_script(<<~JS)
        (() => {
          const nav = document.querySelector('nav');
          const form = nav.querySelector('form');
          const box = element => {
            const { left, right, top, bottom, width, height } = element.getBoundingClientRect();
            return { left, right, top, bottom, width, height };
          };
          const controls = [...form.querySelectorAll('label, select, button')];
          const focus = document.activeElement;
          const style = getComputedStyle(focus);
          return {
            overflow: document.documentElement.scrollWidth - innerWidth,
            nav: box(nav), controls: controls.map(box), logo: box(nav.querySelector('a')),
            wrap: getComputedStyle(nav).flexWrap,
            focus: box(focus), outline: style.outlineStyle, outlineWidth: parseFloat(style.outlineWidth)
          };
        })()
      JS
      assert_equal 0, layout.fetch("overflow")
      assert_equal "wrap", layout.fetch("wrap")
      # At this width the selector group must flow below the logo, not overlap it.
      assert_operator layout.fetch("controls").first.fetch("top"), :>=, layout.fetch("logo").fetch("bottom")
      layout.fetch("controls").each do |box|
        assert_operator box.fetch("left"), :>=, 0
        assert_operator box.fetch("right"), :<=, 375
        assert_operator box.fetch("bottom"), :<=, layout.fetch("nav").fetch("bottom")
        assert_operator box.fetch("width"), :>, 0
        assert_operator box.fetch("height"), :>, 0
      end
      assert_not_equal "none", layout.fetch("outline")
      assert_operator layout.fetch("outlineWidth"), :>, 0
      focus = layout.fetch("focus")
      assert_operator focus.fetch("left") - layout.fetch("outlineWidth"), :>=, 0
      assert_operator focus.fetch("right") + layout.fetch("outlineWidth"), :<=, 375
    end
end
