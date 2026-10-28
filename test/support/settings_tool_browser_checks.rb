require "tmpdir"
require "fileutils"

# Samples Settings UI in a dedicated session; evidence is not hardware or native zoom proof.
module SettingsToolBrowserChecks
  extend ActiveSupport::Concern

  DRIVER = :settings_tools_desktop_input
  INPUT_FLAG = "--blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4".freeze

  included do
    setup do
      root = Rails.root.join(".superpowers/settings-tools-evidence")
      FileUtils.mkdir_p(root)
      @tools_evidence = Dir.mktmpdir("browser-", root.to_s)
      puts "Settings tools browser evidence: #{@tools_evidence}"
      @tools_previous_driver = Capybara.current_driver
      @tools_previous_session_name = Capybara.session_name
      @tools_previous_session = Capybara.current_session
      @tools_registrations = Capybara.drivers.names.to_h { |name| [ name, Capybara.drivers[name] ] }
      @tools_previous_registration = @tools_registrations[DRIVER]
      options = { name: DRIVER }
      options.merge!(browser: :remote, url: "http://:4444") if ENV["CAPYBARA_SERVER_PORT"]
      ActionDispatch::SystemTesting::Driver.new(:selenium, using: :headless_chrome,
        screen_size: [ 1400, 1400 ], options: options) { |settings| settings.add_argument(INPUT_FLAG) }.use
      Capybara.session_name = "settings_tools_#{File.basename(@tools_evidence)}_#{object_id}"
      @tools_session = Capybara.current_session
    end

    teardown { tools_cleanup }
  end

  # Signs in through the real login form using isolated fixtures.
  # @param user [User] Fixture user to authenticate
  # @return [void]
  def tools_sign_in(user = @user)
    visit root_url
    fill_in "email", with: user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  # Selects the language through the existing language dropdown.
  # @param locale [String] Supported locale code
  # @return [void]
  def tools_locale(locale)
    select locale.upcase, from: "language_preference_locale"
    assert_selector "html[lang='#{locale}']", visible: :all
    tools_wait
  end

  # Emulates and verifies exact CSS viewport dimensions, not physical hardware.
  # @param width [Integer] CSS viewport width
  # @param height [Integer] CSS viewport height
  # @return [void]
  def tools_size(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
    assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
    tools_wait
  end

  # Uses the actual theme toggle and awaits completion of document animations.
  # @param theme [String] Either light or dark
  # @return [void]
  def tools_theme(theme)
    find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != (theme == "dark")
    assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
    page.driver.browser.execute_async_script("const done=arguments[0];Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());")
    tools_wait
  end

  # Waits for two animation frames without arbitrary sleeps or forced rendering.
  # @return [void]
  def tools_wait
    page.driver.browser.execute_async_script("const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));")
  end

  # Reaches an element through native Tab presses, without scripted focus or scroll.
  # @param selector [String] Selector matching the intended keyboard target
  # @return [void]
  # @raise [Minitest::Assertion] If 160 native Tab presses cannot reach the target
  def tools_tab_to(selector)
    160.times do
      page.send_keys(:tab)
      if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
        tools_wait
        return
      end
    end
    flunk "Native Tab could not reach #{selector}"
  end

  # Walks every visible enabled Settings control in DOM order and in reverse.
  # @return [void]
  def tools_keyboard_walk
    count = tools_probe("walk")
    assert_operator count, :>, 0
    find("#theme-toggle").hover
    tools_wait
    tools_tab_to("[data-tools-walk='0']")
    count.times do |index|
      if index.positive?
        page.send_keys(:tab)
        tools_wait
      end
      tools_assert_keyboard(index, "forward")
    end
    tools_assert_keyboard(count - 1, "reverse")
    (count - 2).downto(0) do |index|
      page.send_keys([ :shift, :tab ])
      tools_wait
      tools_assert_keyboard(index, "reverse")
    end
  end

  # Checks the native focus target, visible hit area, outline and sampled contrast.
  # @param index [Integer] Expected DOM-order index
  # @param direction [String] Native traversal direction
  # @return [void]
  def tools_assert_keyboard(index, direction)
    sample = tools_probe("focus")
    tools_record("keyboard", { index: index, direction: direction, sample: sample })
    assert_equal index.to_s, sample.fetch("index"), sample.to_json
    assert_operator sample.fetch("width"), :>=, 44, sample.to_json
    assert_operator sample.fetch("height"), :>=, 44, sample.to_json
    assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
    assert sample.fetch("focusVisible"), sample.to_json
    refute sample.fetch("hovered"), sample.to_json
    assert sample.fetch("unobscured"), sample.to_json
    tools_contrast("focus-#{direction}-#{index}")
  end

  # Rejects page overflow, ellipsis and horizontally clipped labels or text.
  # @return [void]
  def tools_layout
    sample = tools_probe("layout")
    tools_record("layout", sample)
    assert sample.fetch("pageFits"), sample.to_json
    assert_not_empty sample.fetch("rows")
    sample.fetch("rows").each { |row| assert row.fetch("fits"), row.to_json }
  end

  # Records numeric composed-color samples and enforces text/non-text minima.
  # @param phase [String] Interaction phase associated with the samples
  # @return [void]
  def tools_contrast(phase)
    rows = tools_probe("contrast")
    tools_record("contrast", { phase: phase, samples: rows })
    assert_not_empty rows
    rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.to_json }
  end

  # Checks every text link and representative button surfaces under actual pointer hover.
  # Only this interaction may scroll targets into view before sampling.
  # @return [void]
  def tools_hover
    [ ".n-workspace-link", ".n-workspace-primary", ".n-workspace-danger", "button[data-action='token-reveal#copy']" ].each do |selector|
      targets = all("[data-settings-tool] #{selector}")
      targets = targets.first(1) unless selector == ".n-workspace-link"
      targets.each do |target|
        page.execute_script("document.querySelectorAll('[data-tools-hover]').forEach(e=>e.removeAttribute('data-tools-hover'));arguments[0].setAttribute('data-tools-hover','');", target)
        find("main").scroll_to(target, align: :center)
        find("#theme-toggle").hover
        tools_wait
        before = tools_probe("hover")
        refute before.fetch("hovered"), before.to_json
        target.hover
        tools_wait
        after = tools_probe("hover")
        tools_record("hover", { selector: selector, before: before, after: after })
        assert before.fetch("capable"), before.to_json
        assert after.fetch("capable"), after.to_json
        assert after.fetch("hovered"), after.to_json
        assert_equal before.fetch("bounds"), after.fetch("bounds"), after.to_json
        if selector == ".n-workspace-link"
          assert_equal before.fetch("backgroundCSS"), after.fetch("backgroundCSS"), after.to_json
          assert_equal before.fetch("rgba"), after.fetch("rgba"), after.to_json
          assert_equal 0, before.fetch("rgba").last, before.to_json
          assert_equal 0, after.fetch("rgba").last, after.to_json
          assert_includes before.fetch("decoration"), "underline"
          assert_includes after.fetch("decoration"), "underline"
        else
          refute_equal before.fetch("backgroundCSS"), after.fetch("backgroundCSS"), after.to_json
          refute_equal before.fetch("rgba"), after.fetch("rgba"), after.to_json
        end
        tools_contrast("hover-#{selector}")
      end
    end
  end

  # Captures a secret-free base state after interaction checks, resetting only main scroll.
  # @param name [String] Unique screen-locale-viewport-theme key
  # @return [void]
  def tools_screenshot(name)
    assert_no_selector "[data-token-reveal]", visible: :all
    page.execute_script("document.querySelector('main').scrollTop=0")
    tools_wait
    page.save_screenshot(File.join(@tools_evidence, "#{name}.png"))
  end

  # Appends context and measurements, never field values, text or DOM/HTML dumps.
  # @param name [String] Evidence stream name
  # @param sample [Hash] Non-secret numeric/structural measurements
  # @return [void]
  def tools_record(name, sample)
    context = page.evaluate_script("({path:location.pathname,screen:document.querySelector('[data-settings-tool]').dataset.settingsScreen,locale:document.documentElement.lang,viewport:[innerWidth,innerHeight],theme:document.documentElement.classList.contains('dark')?'dark':'light'})")
    File.open(File.join(@tools_evidence, "#{name}.jsonl"), "a") { |file| file.puts(context.merge(sample).to_json) }
  end

  private
    def tools_probe(mode)
      script = Rails.root.join("test/support/settings_tool_browser_probe.js").read
      page.evaluate_script("(#{script})(arguments[0])", mode)
    end

    def tools_cleanup
      audit = { input_capability_emulation: INPUT_FLAG, physical_hardware_proof: false,
        native_200_percent_zoom: "UNVERIFIED", media_cleared: false, metrics_cleared: false,
        dedicated_session_quit: false, assertions_passed: false }
      begin
        begin
          if @tools_session
            @tools_session.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
            audit[:media_cleared] = true
            @tools_session.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
            audit[:metrics_cleared] = true
          end
        ensure
          begin
            if @tools_session
              @tools_session.quit
              audit[:dedicated_session_quit] = true
            end
          ensure
            Capybara.current_driver = @tools_previous_driver
            Capybara.session_name = @tools_previous_session_name
            Capybara.register_driver(DRIVER, &@tools_previous_registration) if @tools_previous_registration
            audit[:driver_restored] = Capybara.current_driver == @tools_previous_driver
            audit[:session_name_restored] = Capybara.session_name == @tools_previous_session_name
            audit[:session_identity_restored] = Capybara.current_session.equal?(@tools_previous_session)
            audit[:protected_registrations] = @tools_registrations.to_h do |name, registration|
              [ name, Capybara.drivers[name].equal?(registration) ]
            end
            audit[:own_registration_restored] = !@tools_previous_registration || Capybara.drivers[DRIVER].equal?(@tools_previous_registration)
          end
        end
        assert audit.fetch(:media_cleared)
        assert audit.fetch(:metrics_cleared)
        assert audit.fetch(:dedicated_session_quit)
        assert_equal @tools_previous_driver, Capybara.current_driver
        assert_equal @tools_previous_session_name, Capybara.session_name
        assert_same @tools_previous_session, Capybara.current_session
        @tools_registrations.each { |name, registration| assert_same registration, Capybara.drivers[name] }
        assert audit.fetch(:own_registration_restored)
        audit[:assertions_passed] = true
      ensure
        File.write(File.join(@tools_evidence, "cleanup.json"), audit.to_json)
      end
    end
end
