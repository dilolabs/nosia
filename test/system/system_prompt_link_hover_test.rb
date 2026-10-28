require "tmpdir"
require "application_system_test_case"
require_relative "../support/settings_tool_fixtures"

class SystemPromptLinkHoverTest < ApplicationSystemTestCase
  include SettingsToolFixtures

  DRIVER = :system_prompt_link_hover_desktop_input
  INPUT_FLAG = "--blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4".freeze

  setup do
    root = Rails.root.join(".superpowers/settings-tools-evidence/prompt-link-hover")
    FileUtils.mkdir_p(root)
    @hover_evidence = Dir.mktmpdir("browser-", root.to_s)
    @old_driver, @old_session = Capybara.current_driver, Capybara.session_name
    @protected_registrations = Capybara.drivers.names.to_h { |name| [ name, Capybara.drivers[name] ] }
    options = { name: DRIVER }
    options.merge!(browser: :remote, url: "http://:4444") if ENV["CAPYBARA_SERVER_PORT"]
    ActionDispatch::SystemTesting::Driver.new(:selenium, using: :headless_chrome,
      screen_size: [ 1400, 1400 ], options: options) { |settings| settings.add_argument(INPUT_FLAG) }.use
    Capybara.session_name = "system_prompt_link_hover_#{object_id}"
    @hover_session = Capybara.current_session
    puts "Prompt link hover evidence: #{@hover_evidence} (desktop-input capability emulation, not hardware/zoom proof)"
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    begin
      @hover_session&.quit
    ensure
      Capybara.current_driver = @old_driver
      Capybara.session_name = @old_session
      if (registration = @protected_registrations[DRIVER])
        Capybara.register_driver(DRIVER, &registration)
      end
    end
    assert_equal @old_driver, Capybara.current_driver
    assert_equal @old_session, Capybara.session_name
    @protected_registrations.each { |name, registration| assert_same registration, Capybara.drivers[name] }
    File.write(File.join(@hover_evidence, "cleanup.json"), {
      dedicated_session_quit: true, restored_driver: Capybara.current_driver,
      restored_session: Capybara.session_name, protected_registrations_unchanged: true,
      input_capability_emulation: INPUT_FLAG, physical_hardware_proof: false,
      native_200_percent_zoom: "UNVERIFIED"
    }.to_json)
  end

  test "all five prompt variants keep text links transparent under real hover and keyboard focus" do
    screens = {
      "prompts" => system_prompts_path,
      "prompt" => system_prompt_path(@shared),
      "prompt-edit" => edit_system_prompt_path(@shared),
      "account-prompt" => account_system_prompt_path(@second),
      "account-prompt-edit" => edit_account_system_prompt_path(@second)
    }
    states = []
    each_locale_theme do |locale, theme|
      screens.each do |screen, path|
        visit path
        set_theme(theme)
        assert_selector "[data-settings-screen='#{screen}']"
        links = all("[data-settings-tool] .n-workspace-link")
        assert_not_empty links
        links.each do |link|
          before, after = hover_samples(link)
          assert_equal 0, before.fetch("rgba").last, before.to_json
          assert_equal before.fetch("background"), after.fetch("background"), after.to_json
          assert_equal 0, after.fetch("rgba").last, after.to_json
          assert_includes before.fetch("decoration"), "underline"
          assert_includes after.fetch("decoration"), "underline"
          assert_keyboard_focus(link)
        end
        states << { screen: screen, locale: locale, theme: theme, links: links.size }
        File.write(File.join(@hover_evidence, "states.json"), states.to_json)
      end
    end
    assert_equal 20, states.size
    assert_equal 20, states.map { |state| state.values_at(:screen, :locale, :theme) }.uniq.size
    assert_no_enqueued_jobs
  end

  test "both token variants and members keep text links transparent under real hover and keyboard focus" do
    screens = {
      "tokens" => api_tokens_path,
      "account-tokens" => account_api_tokens_path(@second),
      "members" => account_account_users_path(@second)
    }
    states = []
    each_locale_theme do |locale, theme|
      screens.each do |screen, path|
        visit path
        set_theme(theme)
        assert_selector "[data-settings-screen='#{screen}']"
        links = all("[data-settings-tool] .n-workspace-link")
        assert_not_empty links
        links.each do |link|
          before, after = hover_samples(link)
          assert_equal 0, before.fetch("rgba").last, before.to_json
          assert_equal before.fetch("background"), after.fetch("background"), after.to_json
          assert_equal 0, after.fetch("rgba").last, after.to_json
          assert_includes before.fetch("decoration"), "underline"
          assert_includes after.fetch("decoration"), "underline"
          assert_keyboard_focus(link)
        end
        states << { screen: screen, locale: locale, theme: theme, links: links.size }
        File.write(File.join(@hover_evidence, "states.json"), states.to_json)
      end
    end
    assert_equal 12, states.size
    assert_equal 12, states.map { |state| state.values_at(:screen, :locale, :theme) }.uniq.size
    assert_no_enqueued_jobs
  end

  test "member primary and secondary buttons plus prompt and token buttons retain real hover surfaces" do
    each_locale_theme do |_locale, theme|
      [
        [ account_account_users_path(@second), ".n-workspace-primary" ],
        [ account_account_users_path(@second), ".n-workspace-button:not(.n-workspace-primary)" ],
        [ system_prompt_path(@shared), ".n-workspace-primary" ],
        [ edit_system_prompt_path(@shared), ".n-workspace-primary" ],
        [ api_tokens_path, ".n-workspace-primary" ],
        [ api_tokens_path, ".n-workspace-danger" ],
        [ account_api_tokens_path(@second), ".n-workspace-primary" ],
        [ account_api_tokens_path(@second), ".n-workspace-danger" ]
      ].each do |path, selector|
        visit path
        set_theme(theme)
        targets = all("[data-settings-tool] #{selector}")
        assert_not_empty targets
        targets.each do |target|
          before, after = hover_samples(target)
          refute_equal before.fetch("background"), after.fetch("background"), after.to_json
          assert_operator after.fetch("rgba").last, :>, 0, after.to_json
        end
      end
    end
    assert_no_enqueued_jobs
  end

  private
    def each_locale_theme
      %w[en fr].each do |locale|
        select locale.upcase, from: "language_preference_locale"
        assert_selector "html[lang='#{locale}']", visible: :all
        %w[light dark].each { |theme| yield locale, theme }
      end
    end

    def set_theme(theme)
      find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script("const done=arguments[0];Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());")
    end

    def hover_samples(target)
      target.scroll_to(:center)
      find("#theme-toggle").hover
      wait_for_frames
      before = sample(target)
      refute before.fetch("hovered"), before.to_json
      target.hover
      wait_for_frames
      after = sample(target)
      record_sample("hover", { before: before, after: after })
      assert before.fetch("capable"), before.to_json
      assert after.fetch("capable"), after.to_json
      assert after.fetch("hovered"), after.to_json
      assert_equal before.fetch("size"), after.fetch("size"), after.to_json
      [ before, after ]
    end

    def assert_keyboard_focus(target)
      find("#theme-toggle").hover
      wait_for_frames
      160.times do
        page.send_keys(:tab)
        if page.evaluate_script("document.activeElement===arguments[0]", target)
          wait_for_frames
          focused = sample(target)
          record_sample("focus", focused)
          refute focused.fetch("hovered"), focused.to_json
          assert focused.fetch("focus_visible"), focused.to_json
          assert_operator focused.fetch("outline"), :>=, 2, focused.to_json
          focused.fetch("size").each { |dimension| assert_operator dimension, :>=, 44, focused.to_json }
          assert_includes focused.fetch("decoration"), "underline"
          return
        end
      end
      flunk "Native Tab could not reach #{target.text}"
    end

    def sample(target)
      page.evaluate_script(<<~JS, target)
        (()=>{
          const e=arguments[0],s=getComputedStyle(e),r=e.getBoundingClientRect();
          const canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d');ctx.fillStyle=s.backgroundColor;ctx.fillRect(0,0,1,1);
          return {text:e.textContent.trim()||e.value,background:s.backgroundColor,
            rgba:Array.from(ctx.getImageData(0,0,1,1).data),hovered:e.matches(':hover'),
            capable:matchMedia('(hover:hover)').matches&&matchMedia('(pointer:fine)').matches,
            decoration:s.textDecorationLine,focus_visible:e.matches(':focus-visible'),
            outline:parseFloat(s.outlineWidth),size:[r.width,r.height]};
        })()
      JS
    end

    def wait_for_frames
      page.driver.browser.execute_async_script("const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));")
    end

    def record_sample(name, data)
      context = page.evaluate_script("({path:location.pathname,screen:document.querySelector('[data-settings-screen]').dataset.settingsScreen,locale:document.documentElement.lang,theme:document.documentElement.classList.contains('dark')?'dark':'light',viewport:[innerWidth,innerHeight]})")
      File.open(File.join(@hover_evidence, "#{name}.jsonl"), "a") do |file|
        file.puts(context.merge(data).merge(input_capability_emulation: INPUT_FLAG, physical_hardware_proof: false).to_json)
      end
    end
end
