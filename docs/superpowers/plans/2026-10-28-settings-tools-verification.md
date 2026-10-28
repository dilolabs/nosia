# Settings Tools Verification and Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify all eight separate page variants and workflows, preserve durable evidence and document the tested result honestly.

**Architecture:** Add a dedicated isolated Selenium session and local sampling probe rather than changing the protected MCP driver/helper. Browser workflows use real application navigation, native keys and controlled local fetch/clipboard promises; request/model tests remain the authorization/storage authority.

**Tech Stack:** Existing Minitest, Capybara/Selenium/Chromium, CDP capability/viewport emulation, Rails fixture adapter and ignored persistent evidence; no new package or CI service.

---

Prerequisites: [shared preparation](2026-10-28-settings-tools-workspace.md),
[prompts](2026-10-28-prompts-workspace.md),
[members](2026-10-28-account-members-workspace.md) and
[tokens](2026-10-28-personal-api-tokens-workspace.md) verified/reviewed in order.
The [specification](../specs/2026-10-28-prompts-members-tokens-ui-ux-design.md)
remains authoritative. Baseline exceptions require this project's actual user
direction; a final accepted nonzero gate is not a green gate.

## Task V1: Isolated browser checks and the exact 128-state matrix

**Create:** `test/support/settings_tool_browser_checks.rb`,
`test/support/settings_tool_browser_probe.js`,
`test/system/settings_tools_matrix_test.rb`.
These files must not change a protected driver's registration or use secret field
values in evidence. The JS probe is test data, not an application asset or package.

- [ ] **Step 1: Write the matrix test first.**

`test/system/settings_tools_matrix_test.rb`:

```ruby
require "application_system_test_case"
require_relative "../support/settings_tool_fixtures"
require_relative "../support/settings_tool_browser_checks"

class SettingsToolsMatrixTest < ApplicationSystemTestCase
  include SettingsToolFixtures
  include SettingsToolBrowserChecks

  setup { tools_sign_in }

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
    states = []
    before = [ Prompt.count, Chat.count, ApiToken.count, AccountUser.count ]
    %w[en fr].each do |locale|
      tools_locale(locale)
      screens.each do |screen, path|
        [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
          %w[light dark].each do |theme|
            visit path
            tools_size(width, height)
            tools_theme(theme)
            assert_selector "[data-settings-screen='#{screen}'] h1", count: 1
            assert_selector "main h1", count: 1
            assert_equal find("main h1").text, page.title
            assert_selector "main header nav", count: 1
            assert_selector "main nav [aria-current=page]", count: 1
            assert_no_selector "#drawer-right, #accordion-right-actions", visible: :all
            assert_no_selector "main svg:not([aria-hidden=true])", visible: :all
            refute_match(/translation missing|missing translation/i, page.html)
            tools_layout
            tools_contrast("normal")
            tools_keyboard_walk
            tools_hover
            tools_screenshot("#{screen}-#{locale}-#{width}-#{height}-#{theme}")
            states << { screen: screen, locale: locale, width: width, height: height, theme: theme }
            File.write(File.join(@tools_evidence, "matrix.json"), { states: states,
              native_200_percent_zoom: "UNVERIFIED", physical_hardware_proof: false,
              input_capability_emulation: SettingsToolBrowserChecks::INPUT_FLAG }.to_json)
          end
        end
      end
    end
    assert_equal 128, states.size
    assert_equal 128, states.uniq.size
    assert_equal before, [ Prompt.count, Chat.count, ApiToken.count, AccountUser.count ]
    assert_equal content, @shared.reload.content
    assert_equal @first, @user.reload.first_account
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    screens.each_value do |path|
      visit path
      assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
      assert page.evaluate_script("Array.from(document.querySelectorAll('[data-settings-tool] a,[data-settings-tool] button')).every(e=>getComputedStyle(e).transitionDuration==='0s')")
      tools_record("reduced-motion", { verified: true })
    end
  end
end
```

- [ ] **Step 2: Record missing-helper RED, then add the helper/probe below.**

```bash
source .superpowers/settings-tools-env.sh
record matrix-red browser_test test/system/settings_tools_matrix_test.rb
```

The first RED is the intentionally absent helper. After adding it, any assertion
failure is a real layout/interaction regression: record it and add a focused
regression before the smallest scoped source fix. Do not force focus/scroll during
keyboard assertions, shrink long text, lower contrast thresholds or exclude states.

`test/support/settings_tool_browser_checks.rb`:

```ruby
require "tmpdir"
require "fileutils"
require "json"

# Samples only these separate tool pages in an isolated capability-emulated session.
module SettingsToolBrowserChecks
  extend ActiveSupport::Concern
  DRIVER = :settings_tools_desktop_input
  INPUT_FLAG = "--blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4".freeze

  included do
    setup do
      root = Rails.root.join(".superpowers/settings-tools-evidence")
      FileUtils.mkdir_p(root)
      @tools_evidence = Dir.mktmpdir("browser-", root.to_s)
      @tools_old_driver, @tools_old_session = Capybara.current_driver, Capybara.session_name
      @tools_old_registration = Capybara.drivers[@tools_old_driver]
      @tools_named_registration = Capybara.drivers[DRIVER]
      options = { name: DRIVER }
      options.merge!(browser: :remote, url: "http://:4444") if ENV["CAPYBARA_SERVER_PORT"]
      ActionDispatch::SystemTesting::Driver.new(:selenium, using: :headless_chrome,
        screen_size: [ 1400, 1400 ], options: options) { |settings| settings.add_argument(INPUT_FLAG) }.use
      Capybara.session_name = "settings_tools_#{object_id}"
      @tools_session = Capybara.current_session
      puts "Settings tools evidence: #{@tools_evidence}"
    end

    teardown do
      begin
        if @tools_session
          page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
          page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
        end
      ensure
        begin
          @tools_session&.quit
        ensure
          Capybara.current_driver = @tools_old_driver
          Capybara.session_name = @tools_old_session
          if @tools_named_registration
            Capybara.register_driver(DRIVER, &@tools_named_registration)
          end
        end
      end
      assert_same @tools_old_registration, Capybara.drivers[@tools_old_driver]
      assert_equal @tools_old_driver, Capybara.current_driver
      assert_equal @tools_old_session, Capybara.session_name
      File.write(File.join(@tools_evidence, "cleanup.json"), { restored: true,
        protected_registration_unchanged: true, input_capability_emulation: INPUT_FLAG,
        native_200_percent_zoom: "UNVERIFIED", physical_hardware_proof: false }.to_json)
    end
  end

  # @param user [User] Fixture identity; no external credentials
  # @return [void]
  def tools_sign_in(user = @user)
    visit root_url
    fill_in "email", with: user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  # @param locale [String] Existing language control option
  # @return [void]
  def tools_locale(locale)
    select locale.upcase, from: "language_preference_locale"
    assert_selector "html[lang=#{locale}]"
  end

  # @param width [Integer] Actual CSS viewport width
  # @param height [Integer] Actual CSS viewport height
  # @return [void]
  def tools_size(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
    assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
  end

  # @param theme [String] Light or dark via the existing real control
  # @return [void]
  def tools_theme(theme)
    find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != (theme == "dark")
    assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
    page.driver.browser.execute_async_script("const done=arguments[0];Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());")
  end

  # @return [void]
  def tools_wait
    page.driver.browser.execute_async_script("const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));")
  end

  # @param selector [String] Target reached using native Tab, not forced focus
  # @return [void]
  def tools_tab_to(selector)
    160.times do
      page.send_keys(:tab)
      if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
        tools_wait
        return
      end
    end
    flunk "Keyboard could not reach #{selector}"
  end

  # @return [void]
  def tools_keyboard_walk
    count = page.evaluate_script(<<~JS)
      Array.from(document.querySelector('[data-settings-tool]').querySelectorAll('a,button,input,select,textarea'))
        .filter(e=>e.checkVisibility()&&!e.disabled&&e.tabIndex>=0)
        .map((e,index)=>{e.dataset.toolsWalk=String(index);return e;}).length
    JS
    assert_operator count, :>, 1
    tools_tab_to("[data-tools-walk='0']")
    count.times do |index|
      page.send_keys(:tab) if index.positive?
      tools_assert_keyboard(index, "forward")
    end
    (count - 2).downto(0) do |index|
      page.send_keys([ :shift, :tab ])
      tools_assert_keyboard(index, "reverse")
    end
  end

  # @param index [Integer] Expected DOM keyboard index
  # @param direction [String] Traversal evidence label
  # @return [void]
  def tools_assert_keyboard(index, direction)
    tools_wait
    assert page.evaluate_script("document.activeElement.dataset.toolsWalk===arguments[0]", index.to_s)
    sample = tools_probe("focus")
    tools_record("keyboard", { index: index, direction: direction, sample: sample })
    assert_operator sample.fetch("width"), :>=, 44, sample.to_json
    assert_operator sample.fetch("height"), :>=, 44, sample.to_json
    assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
    assert sample.fetch("unobscured"), sample.to_json
    tools_contrast("focus-#{direction}-#{index}")
  end

  # @return [void]
  def tools_layout
    sample = tools_probe("layout")
    tools_record("layout", sample)
    assert sample.fetch("pageFits"), sample.to_json
    sample.fetch("rows").each { |row| assert row.fetch("fits"), row.to_json }
  end

  # @param phase [String] Normal, actual hover or keyboard-focus phase
  # @return [void]
  def tools_contrast(phase)
    rows = tools_probe("contrast")
    tools_record("contrast", { phase: phase, samples: rows })
    assert_not_empty rows
    rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.to_json }
  end

  # @return [void]
  def tools_hover
    [ ".n-workspace-link", ".n-workspace-primary", ".n-workspace-danger", "button[data-action='token-reveal#copy']" ].each do |selector|
      target = first("[data-settings-tool] #{selector}")
      next unless target
      target.scroll_to(:center)
      find("#theme-toggle").hover
      tools_wait
      before = page.evaluate_script("({hovered:arguments[0].matches(':hover'),surface:getComputedStyle(arguments[0]).backgroundColor,bounds:arguments[0].getBoundingClientRect().toJSON()})", target)
      refute before.fetch("hovered")
      target.hover
      tools_wait
      after = page.evaluate_script("({hovered:arguments[0].matches(':hover'),surface:getComputedStyle(arguments[0]).backgroundColor,bounds:arguments[0].getBoundingClientRect().toJSON(),capable:matchMedia('(hover:hover)').matches&&matchMedia('(pointer:fine)').matches})", target)
      tools_record("hover", { selector: selector, before: before, after: after, capability_emulation: INPUT_FLAG })
      assert after.fetch("capable") && after.fetch("hovered")
      assert_equal before.fetch("bounds"), after.fetch("bounds")
      refute_equal before.fetch("surface"), after.fetch("surface")
      tools_contrast("hover-#{selector}")
    end
  end

  # @param name [String] Unique base-state image name
  # @return [void]
  def tools_screenshot(name)
    assert_no_selector "[data-token-reveal]", visible: :all
    page.execute_script("document.querySelector('main').scrollTop=0")
    tools_wait
    page.save_screenshot(File.join(@tools_evidence, "#{name}.png"))
  end

  # @param name [String] Evidence stream name
  # @param sample [Hash] No plaintext input values or DOM snapshots
  # @return [void]
  def tools_record(name, sample)
    context = page.evaluate_script("({path:location.pathname,screen:document.querySelector('[data-settings-screen]')?.dataset.settingsScreen,locale:document.documentElement.lang,viewport:[innerWidth,innerHeight],theme:document.documentElement.classList.contains('dark')?'dark':'light'})")
    File.open(File.join(@tools_evidence, "#{name}.jsonl"), "a") { |file| file.puts(context.merge(sample).to_json) }
  end

  private
    def tools_probe(mode)
      script = File.read(Rails.root.join("test/support/settings_tool_browser_probe.js"))
      page.evaluate_script("(#{script})(arguments[0])", mode)
    end
end
```

`test/support/settings_tool_browser_probe.js`:

```javascript
mode => {
  const root = document.querySelector("[data-settings-tool]")
  const main = document.querySelector("main")
  const visible = e => e.checkVisibility() && getComputedStyle(e).visibility === "visible"
  const identify = e => ({ tag: e.tagName, id: e.id, classes: e.className.baseVal ?? e.className })
  if (mode === "focus") {
    const e = document.activeElement, r = e.getBoundingClientRect(), m = main.getBoundingClientRect()
    const top = Math.max(0, m.top), bottom = Math.min(innerHeight, m.bottom)
    const tallField = e.matches("textarea") && r.height > bottom - top
    const y1 = Math.max(r.top + 2, top + 2), y2 = Math.min(r.bottom - 2, bottom - 2)
    const points = [[r.left + 2, (y1+y2)/2], [r.right - 2, (y1+y2)/2], [(r.left+r.right)/2, y1], [(r.left+r.right)/2, y2]]
    return { ...identify(e), width: r.width, height: r.height, outline: parseFloat(getComputedStyle(e).outlineWidth),
      bounds: [r.x,r.y,r.width,r.height], mainBounds: [m.x,m.y,m.width,m.height], tallField,
      unobscured: r.left >= m.left && r.right <= Math.min(m.right,innerWidth) && y2 > y1 &&
        (tallField || (r.top >= top && r.bottom <= bottom)) && points.every(([x,y]) => {
          const hit = document.elementFromPoint(x,y); return hit === e || e.contains(hit)
        }) }
  }
  if (mode === "layout") {
    const canvas = document.createElement("canvas"), ctx = canvas.getContext("2d")
    const rows = Array.from(root.querySelectorAll("h1,h2,h3,p,label,nav,nav li,a,button,input[type=submit]"))
      .filter(visible).map(e => {
        const r=e.getBoundingClientRect(), s=getComputedStyle(e)
        let fits=e.scrollWidth<=e.clientWidth+1 && s.textOverflow!=="ellipsis"
        if (e.matches("input[type=submit]")) {
          ctx.font=[s.fontStyle,s.fontVariant,s.fontWeight,s.fontSize,s.fontFamily].join(" ")
          const width=ctx.measureText(e.value).width+Math.max(0,e.value.length-1)*(parseFloat(s.letterSpacing)||0)
          fits &&= width<=r.width-parseFloat(s.paddingLeft)-parseFloat(s.paddingRight)-parseFloat(s.borderLeftWidth)-parseFloat(s.borderRightWidth)+1
        } else {
          const walker=document.createTreeWalker(e,NodeFilter.SHOW_TEXT); let node
          while ((node=walker.nextNode())) {
            if (!node.textContent.trim()) continue
            const range=document.createRange();range.selectNodeContents(node)
            fits &&= Array.from(range.getClientRects()).every(t=>t.left>=r.left-1&&t.right<=r.right+1)
          }
        }
        return {...identify(e),fits}
      })
    return {pageFits:document.documentElement.scrollWidth<=document.documentElement.clientWidth+1&&main.scrollWidth<=main.clientWidth+1,rows}
  }
  const canvas=document.createElement("canvas");canvas.width=canvas.height=1
  const ctx=canvas.getContext("2d",{willReadFrequently:true})
  const rgba=value=>{ctx.clearRect(0,0,1,1);ctx.fillStyle=value;ctx.fillRect(0,0,1,1);const a=Array.from(ctx.getImageData(0,0,1,1).data);a[3]/=255;return a}
  const blend=(a,b)=>a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]))
  const background=e=>{const ancestors=[];for(;e;e=e.parentElement)ancestors.unshift(e)
    return ancestors.reduce((b,a)=>{const s=getComputedStyle(a);if(s.opacity!=="1"||s.backgroundImage!=="none")throw Error("Unmeasured surface");return blend(rgba(s.backgroundColor),b)},[255,255,255])}
  const luminance=a=>a.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0)
  const row=(e,property,minimum,outside=false)=>{const b=background(outside?e.parentElement:e),f=blend(rgba(getComputedStyle(e)[property]),b),x=luminance(f),y=luminance(b)
    return {...identify(e),property,minimum,outside,background:b,foreground:f,ratio:(Math.max(x,y)+.05)/(Math.min(x,y)+.05)}}
  const elements=Array.from(root.querySelectorAll("h1,h2,h3,p,label,a,button,input:not([type=hidden]),select,textarea,svg,.n-settings-tool-badge")).filter(visible)
  const rows=elements.map(e=>row(e,"color",e.tagName.toLowerCase()==="svg"?3:4.5))
  root.querySelectorAll(".n-workspace-button,.n-settings-tool-input").forEach(e=>{
    if(!visible(e))return
    if(e.classList.contains("n-workspace-primary"))rows.push(row(e,"backgroundColor",3,true))
    else [false,true].forEach(outside=>rows.push(row(e,"borderTopColor",3,outside)))
  })
  if(root.contains(document.activeElement)) {
    const e=document.activeElement
    rows.push(row(e,"outlineColor",3,true))
    if(e.matches("input,select,textarea"))rows.push(row(e,"outlineColor",3))
  }
  return rows
}
```

Probe limitations are explicit: no gradients/opacity guesses, no assumed hover,
no screen-reader or physical-touch claims. Native input horizontal value scrolling
is permitted; page-wide overflow, clipped text and unreadable submit labels are not.
The dedicated test-only registration can remain inert after its first use; it is
never left current. A preexisting named registration is restored through the
registration API, the dedicated session quits and all emulation is cleared. The
protected driver registration is checked by object identity, not overwritten.

- [ ] **Step 3: Run the matrix, inspect representative images and commit the tests.**

```bash
record matrix-build rails_test tailwindcss:build
record matrix-green browser_test test/system/settings_tools_matrix_test.rb
record matrix-lint mise exec ruby@4.0.7 -- bundle exec rubocop test/support/settings_tool_browser_checks.rb test/system/settings_tools_matrix_test.rb
git diff --check
git add test/support/settings_tool_browser_checks.rb test/support/settings_tool_browser_probe.js test/system/settings_tools_matrix_test.rb
git diff --cached --check
git commit -m "test: Verify separate Settings tools across 128 browser states"
```

Expected: 128 unique completed states and persistent JSONL/PNG/cleanup evidence,
not merely 128 attempted visits. Open at least prompt detail/editor, members and
each token variant at 375/light, 1440/dark and 812×375/French; use the actual image
paths from the reported browser evidence directory. Review normal-flow mobile
clearance and text wrapping visually in addition to computed samples. If fixes
are needed, make separate test-first source commits and rerun the matrix.

## Task V2: Genuine workflows beyond the base states

**Create:** `test/system/settings_tools_workflows_test.rb`.
**Reuse:** the dedicated helper/session above and T2's `TokenRevealTest`.

- [ ] **Step 1: Add these complete workflow tests.**

```ruby
require "application_system_test_case"
require_relative "../support/settings_tool_fixtures"
require_relative "../support/settings_tool_browser_checks"

class SettingsToolsWorkflowsTest < ApplicationSystemTestCase
  include SettingsToolFixtures
  include SettingsToolBrowserChecks
  setup { tools_sign_in }

  test "global and account editors retain rejected text focus native errors and save explicitly" do
    [ edit_system_prompt_path(@shared), edit_account_system_prompt_path(@first) ].each do |path|
      visit path
      count = Prompt.count
      fill_in "prompt_content", with: ""
      click_on "Save"
      assert_selector "#prompt_content:invalid:focus"
      assert_no_selector "[data-form-errors-target=summary]"
      assert_equal count, Prompt.count
      fill_in "prompt_content", with: " \n "
      page.execute_script("document.querySelector('form[data-controller~=html-form]').noValidate=true")
      click_on "Save"
      assert_selector "[data-form-errors-target=summary]:focus"
      assert_field "prompt_content", with: " \n "
      assert_equal count, Prompt.count
      tools_tab_to("[data-error-field=prompt_content]")
      page.send_keys(:enter)
      assert_selector "#prompt_content:focus"
      tools_contrast("prompt-error-focus")
      fill_in "prompt_content", with: "Literal instructions\n%{documents}"
      click_on "Save"
      read_path = path == edit_system_prompt_path(@shared) ? system_prompt_path(@shared) : account_system_prompt_path(@first)
      assert_current_path read_path
      assert_selector "[role=status]", text: I18n.t("nosia.prompts.updated")
      assert_selector "[data-prompt-content]", text: "Literal instructions"
      assert_equal count + (path == edit_system_prompt_path(@shared) ? 0 : 1), Prompt.count
      visit path
      fill_in "prompt_content", with: "Unsaved cancellation"
      click_on "Cancel"
      assert_current_path read_path
      assert_no_text "Unsaved cancellation"
    end
    assert_equal "Personal research override", @second.system_prompt(user: @member)
    assert_equal @first, @user.reload.first_account
  end

  test "members retain unknown and duplicate emails and distinguish cancel from removal" do
    visit account_account_users_path(@second)
    click_on "Add member"
    assert_selector "#account_user_email:invalid:focus"
    fill_in "account_user_email", with: "not-an-email"
    click_on "Add member"
    assert_selector "#account_user_email:invalid:focus"
    before = [ User.count, AccountUser.count ]
    [ "unknown@example.invalid", @member.email ].each do |email|
      fill_in "account_user_email", with: email
      click_on "Add member"
      assert_selector "[data-form-errors-target=summary]:focus"
      assert_field "account_user_email", with: email
      tools_tab_to("[data-error-field=account_user_email]")
      page.send_keys(:enter)
      assert_selector "#account_user_email:focus"
      assert_equal before, [ User.count, AccountUser.count ]
      tools_contrast("member-error-focus")
    end
    fill_in "account_user_email", with: @outsider.email
    click_on "Add member"
    assert_selector "[role=status]", text: I18n.t("nosia.accounts.user_added")
    membership = @second.account_users.find_by!(user: @outsider)
    selector = "form[action='#{account_account_user_path(@second, membership)}'] button"
    message = I18n.t("nosia.settings_tools.member_confirm", email: @outsider.email, account: @second.name)
    dismiss_confirm(message) { find(selector).click }
    assert @second.account_users.exists?(membership.id)
    tools_tab_to(selector)
    accept_confirm(message) { page.send_keys(:enter) }
    assert_no_selector selector
    assert_selector "[role=status]", text: I18n.t("nosia.accounts.user_removed")
    assert User.exists?(@outsider.id)
    assert @foreign.account_users.exists?(user: @outsider)
    assert_selector "[data-member-owner=true]", text: I18n.t("nosia.settings_tools.owner_protected")
    assert_no_selector "[data-member-owner=true] form", visible: :all
  end

  test "global and scoped token errors are recoverable and revocation requires confirmation" do
    [ api_tokens_path, account_api_tokens_path(@second) ].each do |path|
      visit path
      click_on "Generate"
      assert_selector "#api_token_name:invalid:focus"
      fill_in "api_token_name", with: "Browser token"
      if path == api_tokens_path
        click_on "Generate"
        assert_selector "#api_token_account_id:invalid:focus"
        select @second.name, from: "api_token_account_id"
      end
      fill_in "api_token_name", with: " "
      count = ApiToken.count
      click_on "Generate"
      assert_selector "[data-form-errors-target=summary]:focus"
      assert_equal count, ApiToken.count
      assert_no_selector "[data-token-reveal]", visible: :all
      tools_tab_to("[data-error-field=api_token_name]")
      page.send_keys(:enter)
      assert_selector "#api_token_name:focus"
      fill_in "api_token_name", with: "Browser token"
      click_on "Generate"
      assert_selector "[data-token-reveal]:focus"
      token = @user.api_tokens.order(:created_at, :id).last
      plain = find("#created_api_token").value
      assert_equal token, ApiToken.authenticate_token(plain)
      delete_path = path == api_tokens_path ? api_token_path(token) : account_api_token_path(@second, token)
      selector = "form[action='#{delete_path}'] button"
      message = I18n.t("nosia.settings_tools.revoke_confirm", name: token.name, account: @second.name)
      dismiss_confirm(message) { find(selector).click }
      assert ApiToken.exists?(token.id)
      accept_confirm(message) { find(selector).click }
      assert_current_path path
      assert_selector "[role=status]", text: I18n.t("nosia.settings_tools.token_removed")
      assert_nil ApiToken.authenticate_token(plain)
      assert_no_selector "[data-token-reveal]", visible: :all
      assert @member.api_tokens.exists?(@other_token.id)
    end
    assert_equal @first, @user.reload.first_account
  end

  test "empty fallback and no-account pages remain truthful without read side effects" do
    @user.accounts.each { |account| account.prompts.destroy_all }
    @user.api_tokens.destroy_all
    before = [ Prompt.count, Chat.count ]
    visit system_prompts_path
    assert_text I18n.t("nosia.settings_tools.prompts_empty")
    visit account_system_prompt_path(@first)
    assert_selector "[data-prompt-state]", text: I18n.t("nosia.settings_tools.prompt_builtin")
    visit edit_account_system_prompt_path(@first)
    assert_selector "[data-prompt-state]", text: I18n.t("nosia.settings_tools.prompt_builtin")
    visit account_account_users_path(@empty)
    assert_selector "[data-members-only-owner]"
    [ api_tokens_path, account_api_tokens_path(@second) ].each do |path|
      visit path
      assert_selector "[data-token-empty]"
    end
    assert_equal before, [ Prompt.count, Chat.count ]
    @user.account_users.destroy_all
    visit api_tokens_path
    assert_selector "[data-token-setup] a[href='#{new_account_path}']"
    assert_no_selector "#api_token_name", visible: :all
    tools_record("empty-workflows", { verified: true })
  end

  test "submissions expose distinct busy text prevent duplicate submit and recover" do
    cases = [
      [ edit_system_prompt_path(@shared), system_prompt_path(@shared), "Save", "Saving…", "patch" ],
      [ account_account_users_path(@second), account_account_users_path(@second), "Add member", "Adding member…", "post" ],
      [ account_api_tokens_path(@second), account_api_tokens_path(@second), "Generate", "Generating…", "post" ]
    ]
    cases.each do |visit_path, request_path, label, busy, method|
      visit visit_path
      fill_in "prompt_content", with: "Busy instructions" if label == "Save"
      fill_in "account_user_email", with: @outsider.email if label == "Add member"
      fill_in "api_token_name", with: "Busy token" if label == "Generate"
      tools_hold_request(request_path, method)
      click_on label
      assert_selector "input[type=submit][disabled][value='#{busy}']"
      assert_equal 1, page.evaluate_script("window.toolsHeldCount")
      tools_record("submit-busy", { label: label, disabled: true, busy: busy })
      tools_contrast("busy-#{label}")
      page.execute_script("window.toolsRelease()")
      if label == "Generate"
        assert_selector "[data-token-reveal]:focus"
      else
        assert_selector "[role=status]"
      end
      assert_no_selector "input[type=submit][disabled]"
      assert_no_selector "[aria-busy=true]"
    end
    token = @user.api_tokens.find_by!(name: "Busy token")
    path = account_api_token_path(@second, token)
    tools_hold_request(path, "delete")
    accept_confirm { find("form[action='#{path}'] button").click }
    assert_selector "button[disabled]", text: "Revoking…"
    tools_record("submit-busy", { label: "Revoke token", disabled: true, busy: "Revoking…" })
    tools_contrast("busy-revoke")
    page.execute_script("window.toolsRelease()")
    assert_no_selector "form[action='#{path}']"
    membership = @second.account_users.find_by!(user: @outsider)
    path = account_account_user_path(@second, membership)
    visit account_account_users_path(@second)
    tools_hold_request(path, "delete")
    accept_confirm { find("form[action='#{path}'] button").click }
    assert_selector "button[disabled]", text: "Removing member…"
    tools_record("submit-busy", { label: "Remove member", disabled: true, busy: "Removing member…" })
    tools_contrast("busy-remove")
    page.execute_script("window.toolsRelease()")
    assert_no_selector "form[action='#{path}']"
  ensure
    page.execute_script("window.toolsRelease?.()")
  end

  private
    def tools_hold_request(path, method)
      page.execute_script(<<~JS, path, method)
        const path=arguments[0], method=arguments[1], original=window.fetch.bind(window);
        window.toolsHeldCount=0;
        window.fetch=(...args)=>{
          const url=new URL(args[0].url||args[0],location.href);
          const options=args[1]||{}, body=options.body;
          const verb=(body?.get?.('_method')||options.method||'get').toLowerCase();
          if(url.pathname===path&&verb===method){
            window.toolsHeldCount++;
            return new Promise(resolve=>{window.toolsRelease=()=>{
              window.fetch=original;delete window.toolsRelease;resolve(original(...args));
            };});
          }
          return original(...args);
        };
      JS
    end
end
```

- [ ] **Step 2: Run the workflow suite with token copy/history and protected cases.**

```bash
record workflows browser_test test/system/settings_tools_workflows_test.rb test/system/token_reveal_test.rb test/system/api_tokens_test.rb test/system/account_experience_test.rb
record workflows-lint mise exec ruby@4.0.7 -- bundle exec rubocop test/system/settings_tools_workflows_test.rb
```

Expected: genuine native invalid focus; genuine submit-driven focused 422 summary;
Enter follows linked error fields; cancel/confirm have distinct DB outcomes; all
five busy labels recover. `TokenRevealTest` separately covers actual promise
completion/rejection/absence/manual selection/refresh/app Back. Any discovered
source regression starts with its failing focused browser assertion, then minimal
fix and repeat both the workflow and matrix gates. No new capability is authorized.

- [ ] **Step 3: Commit the verified workflow coverage.**

```bash
git diff --check
git add test/system/settings_tools_workflows_test.rb
git diff --cached --check
git commit -m "test: Cover Settings tool recovery confirmation and busy workflows"
```

## Task V3: Documentation, final sequential gates and evidence review

**Create:** `docs/settings-tools-workspace.md`.
**Modify:** `docs/README.md` (one entry only).
**Ignored output:** final baseline comparison, tested identity and review reports.

- [ ] **Step 1: Add the following user/developer guide.**

```markdown
# Separate Settings Tools Workspaces

System prompts, account members and personal API tokens use the Balanced workspace
styling on their own pages. Shared presentation does not combine their management.

## System prompts

`/system_prompts` lists existing saved system-prompt records in your authorized
accounts. Account-default and user-specific labels describe record types, not a
new privacy model. Open a record to read literal text or use its permitted Edit
action. Save is explicit; Cancel discards unsaved edits.

`/accounts/:account_id/system_prompt` shows the saved account default or identifies
the built-in fallback. Reading/opening Edit never saves a fallback. Only a valid
explicit Save does. User-specific instructions retain their existing precedence.
There is no prompt runner, autosave, history or new create/delete control.

## Account members

`/accounts/:account_id/account_users` remains owner-only. Add someone who already
has a Nosia user account by email; no invitation, user account or email is created.
Unknown/duplicate failures retain the email with a linked summary and inline error.
The owner cannot be removed. Remove member confirms the email and account; it
removes that membership, not the User record or memberships elsewhere.

## Personal API tokens

`/api_tokens` manages your tokens across existing default accounts.
`/accounts/:account_id/api_tokens` filters your tokens to the authorized URL
account. Owners cannot manage another member's credentials. The default-account
label is not a new API permission scope.

Give a token a name and choose an available default account on the global page;
the account route fixes that context. Invalid creation retains authorized form
values. Without an available account, account setup replaces only generation;
already-owned tokens remain listed and revocable.

After creation, copy the new value before leaving. It is shown once, cannot be
retrieved later and is stored only as a digest. Copy success is announced only
after clipboard completion; failure leaves selectable text and manual-copy help.
Creation-result pages opt out of Turbo snapshots and clear their result before
caching/pagehide. This does not erase an explicitly used clipboard or promise
control over every browser/OS retention mechanism. Revoke confirms name/default
account and invalidates authentication for clients using that token.

## Navigation, validation and compatibility

Global pages retain generic New chat; account pages open the existing composer
with that account preselected. Neither changes the user's default or creates a
chat. Contextual breadcrumbs, one title, localized feedback and normal-flow
actions replace unrelated history drawers only on these tool pages.

Required/email validation stays native. Server validation returns 422 with
retained input, a focused linked summary and connected inline errors. UI copy
supports English/French and light/dark; authored names/emails/content are not
translated. Permissions, account defaults, prompt resolution and API storage/
authentication contracts are unchanged. No route, schema or dependency is added.

## Verification commands and limits

Use the isolated environment/recorder in the implementation plan; never point
these fixture suites at a development or production database:

- `rails_test test test/controllers/prompts_workspace_test.rb test/controllers/account_members_workspace_test.rb test/controllers/api_tokens_workspace_test.rb`
- `browser_test test/system/settings_tools_matrix_test.rb test/system/settings_tools_workflows_test.rb test/system/token_reveal_test.rb`

The matrix requires eight variants × two locales × two themes × four actual CSS
viewports (375×812, 768×1024, 1440×1000, 812×375), with separate workflow cases.
Persistent ignored evidence contains state identities, contrast/focus/hover
samples, images, cleanup, true command exits and source identities. A planned
test is not proof of a passed test; consult the final execution evidence record.

Native 200% browser zoom remains UNVERIFIED without actual browser-zoom evidence.
Dedicated pointer/viewport/reduced-motion emulation is not physical hardware
proof or an exhaustive screen-reader/accessibility audit. Other browsers/platforms
require their own verification.
```

Add this entry immediately before `### [Architecture Documentation]` in `docs/README.md`:

```markdown
### [Separate Settings Tools Workspaces](settings-tools-workspace.md)
Dedicated prompt, member and personal API-token pages, recovery and verification boundaries.

```

- [ ] **Step 2: Capture source identity before the final gates.**

```bash
source .superpowers/settings-tools-env.sh
git diff --check
git rev-parse HEAD > "$EVIDENCE/final-source-head.txt"
git diff --binary "$BASE" > "$EVIDENCE/final-source.diff"
git status --short > "$EVIDENCE/final-status.txt"
git ls-files --others --exclude-standard > "$EVIDENCE/final-untracked.txt"
```

No undocumented untracked application files may escape tested-tree identity.
New guide changes are documentation only; use a source-path SHA256 manifest in
Step 4 to distinguish them from application verification.

- [ ] **Step 3: Run every final gate sequentially and retain all true exits.**

```bash
record final-build rails_test tailwindcss:build
record final-focused rails_test test test/helpers/settings_tools_helper_test.rb test/controllers/prompts_workspace_test.rb test/controllers/account_members_workspace_test.rb test/controllers/api_tokens_workspace_test.rb test/controllers/system_prompts_controller_test.rb test/controllers/accounts/system_prompts_controller_test.rb test/controllers/accounts/administration_test.rb test/controllers/accounts/account_users_authorization_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/api_tokens_controller_test.rb test/models/api_token_test.rb test/integration/system_prompt_materialization_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record final-full rails_test test
record final-new-browser browser_test test/system/settings_tools_matrix_test.rb test/system/settings_tools_workflows_test.rb test/system/token_reveal_test.rb
record final-protected-browser browser_test test/system/api_tokens_test.rb test/system/accounts_settings_workspace_test.rb test/system/account_experience_test.rb test/system/agent_skills_workspace_test.rb test/system/sources_workspace_test.rb test/system/token_usage_workspace_test.rb test/system/dashboard_test.rb test/system/profile_management_test.rb test/system/mcp_workspace_test.rb test/system/mcp_catalog_test.rb test/system/mcp_connection_tests_test.rb
record final-lint mise exec ruby@4.0.7 -- bundle exec rubocop app/helpers/settings_tools_helper.rb app/helpers/system_prompts_helper.rb app/controllers/system_prompts_controller.rb app/controllers/accounts/account_users_controller.rb app/controllers/api_tokens_controller.rb test/support/settings_tool_fixtures.rb test/support/settings_tool_browser_checks.rb test/helpers/settings_tools_helper_test.rb test/controllers/prompts_workspace_test.rb test/controllers/account_members_workspace_test.rb test/controllers/api_tokens_workspace_test.rb test/controllers/system_prompts_controller_test.rb test/controllers/accounts/administration_test.rb test/controllers/accounts/scoped_tokens_usage_test.rb test/controllers/account_experience_test.rb test/controllers/settings_workspace_test.rb test/system/settings_tools_matrix_test.rb test/system/settings_tools_workflows_test.rb test/system/token_reveal_test.rb test/system/api_tokens_test.rb test/system/account_experience_test.rb test/integration/localized_pages_test.rb test/internationalization/catalogs_test.rb
record final-security mise exec ruby@4.0.7 -- bundle exec brakeman --no-pager
```

Do not chain gates or pipe a nonzero command into `tee`/`tail`. Copy any protected
MCP `/tmp/opencode` images/JSON into a separate durable subdirectory without
modifying its helper. New or changed unrelated failures stop delivery for user
direction. Check that the isolated test DB identity still matches Task 0.

- [ ] **Step 4: Preserve manifest, compare gates, inspect scope and review YARD/docs.**

Run this standalone Ruby command (no Rails boot) to preserve tested files:

```bash
mise exec ruby@4.0.7 -- ruby -rdigest -rjson -e 'paths = `git ls-files -z app test config/locales`.split("\0"); added = `git ls-files --others --exclude-standard -z app test config/locales`.split("\0"); files = (paths + added).uniq.sort.select { |p| File.file?(p) }; File.write(File.join(ENV.fetch("EVIDENCE"), "tested-source-manifest.json"), files.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }.to_json)'
git diff --stat "$BASE"
git diff "$BASE" -- app/models config/routes.rb db Gemfile Gemfile.lock config/importmap.rb vendor/javascript app/javascript/controllers/application.js
git diff --check
```

The protected diff above must be empty. Check every new/changed public helper and
browser-helper method for accurate YARD params/returns, including predicate and
optional values; do not add a YARD dependency. Check Markdown links with the
standalone checker in the planning self-review ledger. Compare actual baseline
and final identities/messages in `final-verification.md` with this exact structure:

```markdown
# Settings tools execution verification

## Tested identity
Record actual base/source commit, source manifest path/hash, dirty documentation
paths, runtime/browser versions and isolated DB identity.

## Gate comparison
For each baseline and final command: exact raw log/.exit paths, status, counts,
seed, failure identities/messages and explicit user direction for any nonzero.
Never label an accepted nonzero gate green.

## Browser evidence
Record the actual matrix.json path, 128/128 unique completed states, image paths
visually inspected, measured minimum text/nontext ratios and actual hover changes.
Record keyboard forward/reverse, Enter, native/422 focus, five submit busy labels,
confirmation cancel/accept, clipboard completed/rejected/absent/manual selection,
refresh/app Back and driver cleanup evidence. Describe unverified cases honestly.

## Limits and reviews
Native 200% browser zoom: UNVERIFIED absent actual browser-zoom evidence.
Capability emulation is labeled, not hardware proof. Record spec/quality review
identities, findings/fixes and any unresolved delivery blockers.
```

Fill that evidence record with actual results, not the sample prose. Read matrix
JSON and confirm all Cartesian-product keys exist; counts alone are insufficient.
Use `functions.read` to open representative PNGs, not merely list their paths.

- [ ] **Step 5: Commit only documentation, then obtain final feature reviews.**

```bash
git add docs/settings-tools-workspace.md docs/README.md
git diff --cached --check
git diff --cached --stat
git commit -m "docs: Explain separate Settings tools and verification boundaries"
git status --short
git log -7 --oneline
```

Review the complete feature against `$BASE`: specification first, quality second.
If subagent-driven was selected, use independent reviewers; otherwise perform
the two reviews inline without silently switching execution methods. Any source
fix repeats affected tests and final gates/manifest; a docs-only commit is not a
new application test run. Do not merge, push, open a PR or remove worktrees.

- [ ] **Step 6: Report the outcome with exact exceptions/limits and await direction.**

State that pages remain separate, list verified gates and evidence location,
identify any accepted nonzero results distinctly, and keep native zoom unverified
unless actual proof exists. Preserve the execution worktree and database. No
integration/cleanup action is authorized by this plan.
