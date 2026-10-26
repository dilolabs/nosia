require "application_system_test_case"
require_relative "../support/agent_skills_workspace_fixtures"

# Exercises responsive Skills rows and fully visible keyboard focus in a browser.
class AgentSkillsWorkspaceSystemTest < ApplicationSystemTestCase
  include AgentSkillsWorkspaceFixtures

  setup do
    @original_window_size = page.current_window.size
    @evidence_dir = "/tmp/opencode/agent-skills-workspace-#{Process.pid}"
    FileUtils.mkdir_p(@evidence_dir)
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    page.current_window.resize_to(*@original_window_size)
    Capybara.reset_sessions!
  end

  test "structured rows reflow and expose keyboard reachable text actions" do
    [ 375, 1440 ].each do |width|
      resize_skills_viewport(width, 900)
      %w[light dark].each do |theme|
        visit account_agent_skills_path(@second)
        set_skills_theme(theme)
        assert_selector "[data-skill-id]", count: 3
        assert_skills_layout
        focus_skill_by_tab("[data-skill-id] [data-skill-state-action]")
        assert_skills_focus
        page.save_screenshot("#{@evidence_dir}/rows-#{width}-#{theme}.png")
      end
    end
  end

  test "create and edit stay in both route families without changing stored identity" do
    [ [ @first, agent_skills_path, new_agent_skill_path ],
      [ @second, account_agent_skills_path(@second), new_account_agent_skill_path(@second) ] ].each do |account, index, new_path|
      name = "browser-#{account.id}"
      source = workspace_source(name)
      visit new_path
      fill_in "agent_skill_skill_content", with: source
      focus_skill_by_tab("[data-skill-advanced] summary")
      page.send_keys(:enter)
      assert_selector "[data-skill-advanced][open]"
      fill_in "agent_skill_priority", with: 42
      find("[data-skill-save]").click
      assert_current_path index
      record = account.agent_skills.find_by!(name: name)
      assert_equal source, record.skill_content
      assert_equal 42, record.priority
      row = "[data-skill-id='#{record.id}']"
      within(row) { find("a[href$='/edit']").click }
      assert_field "agent_skill_skill_content", with: source
      assert_selector "[data-skill-saved-identity]", text: name
      fill_in "agent_skill_skill_content", with: workspace_source("new-frontmatter-name")
      find("[data-skill-save]").click
      assert_current_path index
      assert_equal name, record.reload.name
      assert_equal "Keep this description", record.description
      assert_equal workspace_source("new-frontmatter-name"), record.skill_content
    end
    assert_equal @first, @user.reload.first_account
    assert_no_enqueued_jobs
  end

  test "server errors focus the summary retain input and reopen a manually closed advanced field" do
    record = workspace_skill(:skills_second)
    before = record.attributes
    source = "---\nname: new-frontmatter-name\nrequires_rag_context: true\n---\nKeep the edited source."
    visit edit_account_agent_skill_path(@second, record)
    fill_in "agent_skill_skill_content", with: source
    find("[data-skill-advanced] summary").click
    fill_in "agent_skill_priority", with: 101
    uncheck "agent_skill_requires_rag_context"
    page.execute_script("document.querySelector('form[data-skill-form]').noValidate=true")
    find("[data-skill-save]").click
    assert_selector "[data-form-errors-target='summary']"
    assert_selector "[data-form-errors-target='summary']:focus"
    assert_field "agent_skill_skill_content", with: source
    assert_field "agent_skill_priority", with: "101"
    assert_unchecked_field "agent_skill_requires_rag_context"
    assert_selector "[data-skill-advanced][open]"
    find("[data-skill-advanced] summary").click
    assert_no_selector "[data-skill-advanced][open]"
    focus_skill_by_tab("[data-form-errors-target='summary'] a[href='#agent_skill_priority']")
    page.send_keys(:enter)
    assert_selector "[data-skill-advanced][open]"
    assert_selector "#agent_skill_priority:focus"
    assert_skills_focus
    page.save_screenshot("#{@evidence_dir}/advanced-validation.png")
    assert_equal before, record.reload.attributes
  end

  test "native validation reveals a closed invalid advanced field before focusing it" do
    before = workspace_records
    visit new_account_agent_skill_path(@second)
    fill_in "agent_skill_skill_content", with: workspace_source("native-validation")
    find("[data-skill-advanced] summary").click
    fill_in "agent_skill_priority", with: 101
    find("[data-skill-advanced] summary").click
    page.execute_script("window.skillsNativeRequests=[];document.addEventListener('turbo:before-fetch-request',e=>{if(e.target.matches('form[data-skill-form]'))window.skillsNativeRequests.push(e.detail.url.toString());})")
    find("[data-skill-save]").click
    assert_selector "[data-skill-advanced][open]"
    assert_selector "#agent_skill_priority:focus"
    assert_empty page.evaluate_script("window.skillsNativeRequests")
    assert_no_selector "[data-form-errors-target='summary']"
    assert_equal before, workspace_records
  end

  private
    def resize_skills_viewport(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth, innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
    end

    def set_skills_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
    end

    def assert_skills_layout
      assert_selector "main h1", count: 1
      assert_no_text(/translation missing|missing translation/i)
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1")
      assert_no_selector "#drawer-right, #accordion-right-actions, [data-drawer-target]", visible: :all
    end

    def focus_skill_by_tab(selector)
      200.times do
        page.send_keys(:tab)
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          page.driver.browser.execute_async_script("const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));")
          return
        end
      end
      flunk "Keyboard could not reach #{selector}"
    end

    def assert_skills_focus
      result = page.evaluate_script(<<~JS)
        (()=>{const e=document.activeElement,r=e.getBoundingClientRect(),s=getComputedStyle(e),m=document.querySelector('main').getBoundingClientRect();
        const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
        return {height:r.height,outline:parseFloat(s.outlineWidth),visible:r.top>=Math.max(0,m.top)&&r.bottom<=Math.min(innerHeight,m.bottom)&&points.every(([x,y])=>{const h=document.elementFromPoint(x,y);return h&&(h===e||e.contains(h));})};})()
      JS
      assert_operator result.fetch("height"), :>=, 44
      assert_operator result.fetch("outline"), :>=, 2
      assert result.fetch("visible"), result.to_json
    end
end
