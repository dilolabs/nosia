require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class ProfileManagementTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  setup do
    Profiles::BaseController::CREDENTIAL_RATE_LIMIT_STORE.clear
    visit root_path
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_button "Sign in"
    assert_selector "#dropdownUser"
    visit profile_path
    assert_selector "#profile-email-form"
  end

  teardown do
    Capybara.reset_sessions!
  end

  test "visibility is independent and keyboard submission focuses linked errors without retaining secrets" do
    fill_in "profile_email_current_password", with: "wrong-password-123"

    within "#profile-email-form" do
      click_button "Show Current password", enable_aria_label: true
      assert_selector "#profile_email_current_password[type=text]"
      assert_selector "button[aria-label='Hide Current password'][aria-pressed=true]"
    end
    assert_selector "#profile_password_current_password[type=password]"
    assert_no_selector "#profile_email_errors"
    assert_equal "wrong-password-123", find("#profile_email_current_password").value

    within "#profile-password-form" do
      click_button "Show Current password", enable_aria_label: true
      assert_selector "#profile_password_current_password[type=text]"
      click_button "Hide Current password", enable_aria_label: true
      assert_selector "#profile_password_current_password[type=password]"
      assert_selector "button[aria-label='Show Current password'][aria-pressed=false]"
    end
    assert_selector "#profile_email_current_password[type=text]"

    find("#profile-email-form button[type=submit]").send_keys(:enter)

    assert_selector "#profile_email_errors:focus"
    assert_selector "#profile_email_current_password_error", text: "is incorrect"
    assert_empty find("#profile_email_current_password").value
    assert_selector "#profile_email_current_password[type=password]"
    assert_selector "#profile-email-form button[aria-pressed=false]"
    assert_focused_in_main

    find("#profile_email_errors a[href='#profile_email_current_password']").click
    assert_selector "#profile_email_current_password:focus"
    assert_focused_in_main
  end

  test "failed submission moves focus to the summary without requiring a visibility toggle" do
    fill_in "profile_email_current_password", with: "wrong-password-123"
    find("#profile-email-form button[type=submit]").click

    assert_selector "#profile_email_errors:focus"
    assert_selector "#profile_email_current_password[aria-invalid=true]"
    assert_empty find("#profile_email_current_password").value

    fill_in "profile_email_current_password", with: "another-wrong-password"
    find("#profile-email-form button[type=submit]").click

    assert_selector "#profile_email_errors:focus"
    assert_empty find("#profile_email_current_password").value
  end

  test "successful independent updates clear the other card and keep this browser authenticated" do
    fill_in "profile_password_password", with: "unsaved-unrelated-secret"
    fill_in "profile_email_email", with: "browser-profile@example.com"
    fill_in "profile_email_current_password", with: ChatAccountFixtures::PASSWORD
    find("#profile-email-form button[type=submit]").click

    assert_text "Your email address has been updated."
    assert_field "profile_email_email", with: "browser-profile@example.com"
    assert_empty find("#profile_password_password").value

    fill_in "profile_password_current_password", with: ChatAccountFixtures::PASSWORD
    fill_in "profile_password_password", with: "browser-replacement-456"
    fill_in "profile_password_password_confirmation", with: "browser-replacement-456"
    find("#profile-password-form button[type=submit]").click

    assert_text "Your password has been updated. Other browsers have been signed out."
    assert_current_path profile_path
    assert_selector "#profile-password-form"
    assert @user.reload.authenticate("browser-replacement-456")
    assert_empty find("#profile_password_current_password").value
  end

  test "cache and page lifecycle events clear and mask secrets before history restoration" do
    fill_in "profile_email_current_password", with: "temporary-revealed-secret"
    within("#profile-email-form") { click_button "Show Current password", enable_aria_label: true }
    assert_selector "#profile_email_current_password[type=text]"
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_empty find("#profile_email_current_password").value
    assert_selector "#profile_email_current_password[type=password]"
    assert_selector "#profile-email-form button[aria-pressed=false]"

    fill_in "profile_password_password", with: "another-temporary-secret"
    within("#profile-password-form") { click_button "Show New password", exact: true, enable_aria_label: true }
    page.execute_script("window.dispatchEvent(new Event('pagehide'))")
    assert_empty find("#profile_password_password").value
    assert_selector "#profile_password_password[type=password]"

    fill_in "profile_email_current_password", with: "history-temporary-secret"
    within("#profile-email-form") { click_button "Show Current password", enable_aria_label: true }
    page.execute_script(<<~JS)
      document.addEventListener('turbo:before-visit', () => {
        window.profileSecretsClearedBeforeVisit = [...document.querySelectorAll('[data-credential-secret]')].every(input => input.value === '' && input.type === 'password')
      }, { once: true })
    JS
    page.execute_script("Turbo.visit('/settings')")
    assert_current_path settings_path
    assert page.evaluate_script("window.profileSecretsClearedBeforeVisit"), "Secrets must be cleared before Turbo leaves the page"
    page.go_back
    assert_selector "#profile-email-form"
    assert_empty find("#profile_email_current_password").value
    assert_selector "#profile_email_current_password[type=password]"
    assert_selector "#profile-email-form button[aria-pressed=false]"
  end

  test "signed language preferences keep mobile profile controls contained and keyboard accessible in both themes" do
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 900, deviceScaleFactor: 1, mobile: true)

    %w[en fr].each do |locale|
      switch_language(locale)
      %w[light dark].each do |theme|
        set_theme(theme)
        assert_mobile_geometry
        find("#profile_email_email").click
        find("#profile_email_email").send_keys(:tab)
        assert_selector "#profile_email_current_password:focus-visible"
        assert_focused_in_main
        assert page.evaluate_script("parseFloat(getComputedStyle(document.activeElement).outlineWidth) >= 2")
        assert_profile_contrast
      end
    end
  ensure
    browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "password fields support native autocomplete and clipboard paste without JavaScript validation" do
    assert_selector "#profile_email_current_password[autocomplete=current-password]"
    assert_selector "#profile_password_password[autocomplete=new-password]"
    assert_selector "#profile_password_password_confirmation[autocomplete=new-password]"
    browser.execute_cdp("Browser.grantPermissions", origin: page.evaluate_script("location.origin"), permissions: [ "clipboardReadWrite", "clipboardSanitizedWrite" ])
    page.evaluate_async_script("navigator.clipboard.writeText('clipboard-password-123').then(arguments[0])")
    find("#profile_password_password").click
    find("#profile_password_password").send_keys([ :control, "v" ])
    assert_equal "clipboard-password-123", find("#profile_password_password").value
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_empty find("#profile_password_password").value
  end

  test "long email and French validation errors stay contained in the mobile scrolling region" do
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 900, deviceScaleFactor: 1, mobile: true)
    switch_language("fr")
    set_theme("dark")
    long_email = "a" * 64 + "@" + "verylongdomain" * 4 + ".example.com"
    fill_in "profile_email_email", with: long_email
    fill_in "profile_email_current_password", with: "wrong-password-123"
    find("#profile-email-form button[type=submit]").click
    assert_selector "#profile_email_errors:focus"
    assert_field "profile_email_email", with: long_email
    assert_focused_in_main

    fill_in "profile_password_current_password", with: ChatAccountFixtures::PASSWORD
    fill_in "profile_password_password", with: "x" * 73
    fill_in "profile_password_password_confirmation", with: "different-password-123"
    find("#profile-password-form button[type=submit]").click

    assert_selector "#profile_password_errors:focus"
    assert_text "Mot de passe doit contenir au maximum 72 octets"
    assert_focused_in_main
    assert_profile_contrast
    assert page.evaluate_script(<<~JS), "Long French errors must wrap within the summary"
      (() => {
        const summary = document.querySelector('#profile_password_errors')
        const link = summary.querySelector('a[href="#profile_password_password"]')
        const range = document.createRange()
        range.selectNodeContents(link)
        return summary.scrollWidth <= summary.clientWidth + 1 && range.getClientRects().length > 1
      })()
    JS
    find("#profile_password_errors a[href='#profile_password_password']").click
    assert_selector "#profile_password_password:focus"
    assert_focused_in_main
    assert_empty find("#profile_password_password").value
  ensure
    browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "reconnecting visibility masks autofilled values without clearing or copying them" do
    field = "profile_password_password"
    within("#profile-password-form") { click_button "Show New password", exact: true, enable_aria_label: true }
    page.execute_script("document.getElementById(arguments[0]).closest('[data-controller]').removeAttribute('data-controller')", field)
    fill_in field, with: "manager-autofilled-password"
    page.execute_script("document.getElementById(arguments[0]).parentElement.setAttribute('data-controller', 'password-visibility')", field)

    assert_selector "##{field}[type=password]"
    assert_equal "manager-autofilled-password", find("##{field}").value
    assert_selector "button[aria-controls='#{field}'][aria-pressed=false]"
    refute page.evaluate_script(<<~JS), "Secret values must exist only in the native input value"
      document.documentElement.outerHTML.includes('manager-autofilled-password') ||
        JSON.stringify(localStorage).includes('manager-autofilled-password') ||
        JSON.stringify(sessionStorage).includes('manager-autofilled-password')
    JS
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_empty find("##{field}").value
  end

  test "native forms save each card without JavaScript and refreshing success never repeats revocation" do
    browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    page.refresh
    assert_selector "#profile-email-form"

    fill_in "profile_email_email", with: "native-profile@example.com"
    fill_in "profile_email_current_password", with: ChatAccountFixtures::PASSWORD
    find("#profile-email-form button[type=submit]").click
    assert_text "Your email address has been updated."
    assert_current_path profile_path
    assert_equal "native-profile@example.com", @user.reload.email
    page.refresh
    assert_selector "#profile-email-form"
    assert_no_selector "#profile_email_errors"

    fill_in "profile_password_current_password", with: ChatAccountFixtures::PASSWORD
    fill_in "profile_password_password", with: "native-replacement-456"
    fill_in "profile_password_password_confirmation", with: "native-replacement-456"
    find("#profile-password-form button[type=submit]").click
    assert_text "Your password has been updated. Other browsers have been signed out."
    assert_current_path profile_path
    assert @user.reload.authenticate("native-replacement-456")
    digest = @user.password_digest
    later_session = @user.sessions.create!

    page.refresh

    assert_selector "#profile-password-form"
    assert_no_selector "#profile_password_errors"
    assert_equal digest, @user.reload.password_digest
    assert Session.exists?(later_session.id), "Refreshing the successful GET must not revoke sessions again"
  ensure
    browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
  end

  private
    def browser
      page.driver.browser
    end

    def switch_language(locale)
      form = find("#language_preference_locale").find(:xpath, "ancestor::form")
      within form do
        find("option[value='#{locale}']").select_option
        find("button[type=submit]").click
      end
      assert_selector "html[lang='#{locale}']"
      assert_selector "#profile-email-form"
    end

    def set_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      settle_transitions
    end

    def settle_transitions
      page.evaluate_async_script(<<~JS)
        const done = arguments[0]
        requestAnimationFrame(() => Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {}))).then(() => requestAnimationFrame(done)))
      JS
    end

    def assert_profile_contrast
      settle_transitions
      ratios = page.evaluate_script(<<~JS)
        (() => {
          const canvas = document.createElement('canvas')
          canvas.width = canvas.height = 1
          const context = canvas.getContext('2d', { willReadFrequently: true })
          const rgba = color => {
            context.clearRect(0, 0, 1, 1)
            context.fillStyle = color
            context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data].map((value, i) => i === 3 ? value / 255 : value)
          }
          const composite = (front, back) => front.slice(0, 3).map((value, i) => value * front[3] + back[i] * (1 - front[3])).concat(1)
          const background = element => {
            const ancestors = []
            for (let node = element; node; node = node.parentElement) ancestors.unshift(node)
            return ancestors.reduce((color, node) => composite(rgba(getComputedStyle(node).backgroundColor), color), [255, 255, 255, 1])
          }
          const luminance = color => color.slice(0, 3).map(value => {
            value /= 255
            return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
          }).reduce((sum, value, i) => sum + value * [0.2126, 0.7152, 0.0722][i], 0)
          const contrast = (first, second) => {
            const values = [luminance(first), luminance(second)].sort((a, b) => a - b)
            return (values[1] + 0.05) / (values[0] + 0.05)
          }
          const elements = [...document.querySelectorAll('.n-profile *')].filter(element => element.getClientRects().length)
          const text = elements.filter(element => element.matches('input:not([type=hidden])') || [...element.childNodes].some(node => node.nodeType === Node.TEXT_NODE && node.textContent.trim()))
          const borders = elements.filter(element => element.matches('.n-field')).flatMap(element => {
            const color = rgba(getComputedStyle(element).borderTopColor)
            return [contrast(color, background(element)), contrast(color, background(element.parentElement))]
          })
          const focused = document.activeElement
          return {
            text: Math.min(...text.map(element => {
              const back = background(element)
              return contrast(composite(rgba(getComputedStyle(element).color), back), back)
            })),
            boundary: Math.min(...borders),
            focus: contrast(rgba(getComputedStyle(focused).outlineColor), background(focused.parentElement))
          }
        })()
      JS
      assert_operator ratios.fetch("text"), :>=, 4.5, "Computed profile text contrast: #{ratios}"
      assert_operator ratios.fetch("boundary"), :>=, 3, "Computed input boundary contrast: #{ratios}"
      assert_operator ratios.fetch("focus"), :>=, 3, "Computed keyboard focus contrast: #{ratios}"
    end

    def assert_mobile_geometry
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const profile = document.querySelector('.n-profile').getBoundingClientRect()
          const controls = [...document.querySelectorAll('.n-profile input:not([type=hidden]), .n-profile button')]
          const labels = [...document.querySelectorAll('.n-profile label')]
          return {
            viewport: innerWidth,
            overflow: document.documentElement.scrollWidth - innerWidth,
            undersized: controls.filter(el => el.getBoundingClientRect().height < 44 || el.getBoundingClientRect().width < 44).map(el => el.id || el.textContent),
            escaped: [...controls, ...labels].filter(el => {
              const rect = el.getBoundingClientRect()
              return rect.left < profile.left - 1 || rect.right > profile.right + 1 || el.scrollWidth > el.clientWidth + 1
            }).map(el => el.id || el.textContent)
          }
        })()
      JS
      assert_equal 375, geometry.fetch("viewport")
      assert_operator geometry.fetch("overflow"), :<=, 1
      assert_empty geometry.fetch("undersized")
      assert_empty geometry.fetch("escaped")
    end

    def assert_focused_in_main
      assert page.evaluate_script(<<~JS), "Keyboard focus must remain visible inside the scrolling main region"
        (() => {
          const target = document.activeElement.getBoundingClientRect()
          const main = document.querySelector('main').getBoundingClientRect()
          const hit = document.elementFromPoint(target.left + target.width / 2, target.top + target.height / 2)
          return document.activeElement.contains(hit) && target.top >= main.top - 1 && target.bottom <= main.bottom + 1 && target.left >= main.left - 1 && target.right <= main.right + 1
        })()
      JS
    end
end
