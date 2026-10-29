require "application_system_test_case"
require_relative "../support/settings_tool_fixtures"
require_relative "../support/settings_tool_browser_checks"

# Exercises the eight Settings roots without submitting forms or revealing secrets.
class SettingsToolsMatrixTest < ApplicationSystemTestCase
  include SettingsToolFixtures
  include SettingsToolBrowserChecks

  setup { tools_sign_in }

  %w[prompt account-prompt].each do |screen|
    test "#{screen} probe includes the authored body in layout and contrast" do
      visit_prompt_for_probe(screen)
      layout = tools_probe("layout")
      contrast = tools_probe("contrast")
      tools_record("probe-reliability", { scenario: "body-presence", layout: layout, contrast: contrast })
      assert_equal [ 1, 1 ], [ layout.fetch("rows").count { |row| row["promptBody"] }, contrast.count { |row| row["promptBody"] } ]
      tools_layout
      tools_contrast("probe-readable-body")
    end

    test "#{screen} probe rejects unreadable authored body contrast" do
      visit_prompt_for_probe(screen)
      with_prompt_probe_style("color: rgb(255, 255, 255); background-color: rgb(255, 255, 255)") do
        error = assert_raises(Minitest::Assertion) { tools_contrast("probe-unreadable-body") }
        assert_includes error.message, '"promptBody":true'
        body = tools_probe("contrast").find { |row| row["promptBody"] }
        assert_equal 4.5, body.fetch("minimum")
        assert_equal 1, body.fetch("ratio")
      end
    end

    test "#{screen} probe rejects clipped and ellipsized authored body layout" do
      visit_prompt_for_probe(screen)
      %w[clip ellipsis].each do |overflow|
        with_prompt_probe_style("max-width: 80px; overflow: hidden; white-space: nowrap; text-overflow: #{overflow}") do
          error = assert_raises(Minitest::Assertion) { tools_layout }
          assert_includes error.message, '"promptBody":true'
          body = tools_probe("layout").fetch("rows").find { |row| row["promptBody"] }
          refute body.fetch("fits")
        end
      end
    end
  end

  test "primary submit focus contrasts with both adjacent surfaces" do
    %w[light dark].each do |theme|
      visit edit_system_prompt_path(@shared)
      tools_size(375, 812)
      tools_theme(theme)
      find("#theme-toggle").hover
      tools_tab_to("[data-settings-tool] input[type='submit']")
      tools_contrast("primary-submit-focus")
    end
    assert_no_enqueued_jobs
  end

  test "mobile account editor keyboard focus clears the fixed navigation" do
    @second.update!(name: "ResearchCompteSansTroncature" * 6)
    @shared.update!(content: "Literal <script>not executable</script>\n\n%{documents}\n#{'Long instruction words ' * 80}")
    visit edit_account_system_prompt_path(@second)
    tools_size(375, 812)
    tools_theme("light")
    tools_keyboard_walk
    assert_no_enqueued_jobs
  end

  test "eight page variants satisfy 128 unique locale theme viewport states" do
    @second.update!(name: "ResearchCompteSansTroncature" * 6)
    @member.update!(email: "member.#{'e' * 90}@example.com")
    @own_token.update!(name: "deploy-token-with-a-long-name-" * 7)
    content = "Literal <script>not executable</script>\n\n%{documents}\n#{'Long instruction words ' * 80}"
    @shared.update!(content: content)
    screens = {
      "prompts" => system_prompts_path,
      "prompt" => system_prompt_path(@shared),
      "prompt-edit" => edit_system_prompt_path(@shared),
      "account-prompt" => account_system_prompt_path(@second),
      "account-prompt-edit" => edit_account_system_prompt_path(@second),
      "members" => account_account_users_path(@second),
      "tokens" => api_tokens_path,
      "account-tokens" => account_api_tokens_path(@second)
    }
    viewports = [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ]
    before = [ Prompt.count, Chat.count, ApiToken.count, AccountUser.count ]
    prompt_contents = Prompt.order(:id).pluck(:id, :content)
    default_accounts = ApiToken.order(:id).pluck(:id, :account_id)
    first_account = @user.first_account.id
    states = []

    %w[en fr].each do |locale|
      tools_locale(locale)
      screens.each do |screen, path|
        viewports.each do |width, height|
          %w[light dark].each do |theme|
            visit path
            assert_selector "html[lang='#{locale}']", visible: :all
            tools_size(width, height)
            tools_theme(theme)
            assert_selector "[data-settings-tool][data-settings-screen='#{screen}']", count: 1
            assert_selector "[data-settings-tool] h1", count: 1
            assert_selector "main h1", count: 1
            assert_equal page.title, find("main h1").text
            assert_selector "main header nav", count: 1
            assert_selector "main nav [aria-current='page']", count: 1
            assert_no_selector "#drawer-right, #accordion-right-actions", visible: :all
            assert_no_selector "main svg:not([aria-hidden='true'])", visible: :all
            assert_no_selector ".translation_missing", visible: :all
            refute_match(/translation missing/i, page.text)
            tools_layout
            tools_contrast("normal")
            tools_keyboard_walk
            tools_hover
            key = [ screen, locale, width, height, theme ].join("-")
            tools_screenshot(key)
            states << key
            File.write(File.join(@tools_evidence, "matrix.json"), {
              completed_states: states, native_200_percent_zoom: "UNVERIFIED",
              physical_hardware_proof: false, input_capability_emulation: SettingsToolBrowserChecks::INPUT_FLAG
            }.to_json)
          end
        end
      end
    end

    expected = screens.keys.product(%w[en fr], viewports, %w[light dark]).map do |screen, locale, viewport, theme|
      [ screen, locale, *viewport, theme ].join("-")
    end
    assert_equal 128, states.size
    assert_equal 128, states.uniq.size
    assert_equal expected.sort, states.sort

    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    screens.each do |screen, path|
      visit path
      assert_selector "html[lang='fr']", visible: :all
      assert_selector "[data-settings-screen='#{screen}']"
      tools_wait
      sample = page.evaluate_script(<<~JS)
        ({matches:matchMedia('(prefers-reduced-motion:reduce)').matches,
          durations:Array.from(document.querySelectorAll('[data-settings-tool] a,[data-settings-tool] button')).map(e=>getComputedStyle(e).transitionDuration)})
      JS
      tools_record("reduced-motion", sample)
      assert sample.fetch("matches"), sample.to_json
      assert_not_empty sample.fetch("durations")
      sample.fetch("durations").each { |duration| assert_equal "0s", duration }
    end

    assert_equal before, [ Prompt.count, Chat.count, ApiToken.count, AccountUser.count ]
    assert_equal content, @shared.reload.content
    assert_equal prompt_contents, Prompt.order(:id).pluck(:id, :content)
    assert_equal default_accounts, ApiToken.order(:id).pluck(:id, :account_id)
    assert_equal first_account, @user.reload.first_account.id
    assert_no_enqueued_jobs
    tools_record("invariants", { counts_before: before, counts_after: before,
      prompt_contents_unchanged: true, token_default_accounts_unchanged: true,
      first_account_unchanged: true, no_enqueued_jobs: true })
  end

  private
    def visit_prompt_for_probe(screen)
      @shared.update!(content: "Literal <script>not executable</script>\n\n%{documents}\n#{'Long instruction words ' * 80}")
      visit(screen == "prompt" ? system_prompt_path(@shared) : account_system_prompt_path(@second))
      assert_selector "[data-settings-screen='#{screen}'] [data-prompt-content]", count: 1
      tools_size(375, 812)
      tools_theme("light")
    end

    def with_prompt_probe_style(declarations)
      page.execute_script(<<~JS, declarations)
        const style = document.createElement('style');
        style.id = 'tools-probe-reliability';
        style.textContent = `[data-prompt-content] { ${arguments[0]} }`;
        document.head.append(style);
      JS
      tools_wait
      yield
    ensure
      page.execute_script("document.querySelector('#tools-probe-reliability')?.remove()")
      tools_wait
    end
end
