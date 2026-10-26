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

  test "state actions and cancelled or confirmed deletion preserve both route families" do
    [ [ workspace_skill(:skills_first), @first, agent_skills_path ],
      [ workspace_skill(:skills_second), @second, account_agent_skills_path(@second) ] ].each do |skill, account, index|
      detail = account == @first ? agent_skill_path(skill) : account_agent_skill_path(account, skill)
      source = skill.skill_content
      visit index
      within("[data-skill-id='#{skill.id}']") { find("[data-skill-state-action]").click }
      assert_current_path index
      assert_selector "[data-skill-id='#{skill.id}'] [data-skill-enabled='false']"
      visit detail
      find("[data-skill-state-action]").click
      assert_current_path index
      assert skill.reload.enabled?
      assert_equal source, skill.skill_content
      visit detail
      page.execute_script(<<~JS)
        window.skillsDeleteRequests=[];
        window.skillsDeleteObserver=new AbortController();
        document.addEventListener('turbo:before-fetch-request',event=>{
          if(event.target.matches('form[data-skill-delete]'))window.skillsDeleteRequests.push(event.detail.url.toString());
        },{signal:window.skillsDeleteObserver.signal});
      JS
      confirmation = /#{Regexp.escape(skill.name)}.*#{Regexp.escape(account.name)}/
      before = skill.attributes
      dismiss_confirm(confirmation) { find("button[data-skill-delete]").click }
      assert_equal before, skill.reload.attributes
      assert_empty page.evaluate_script("window.skillsDeleteRequests")
      accept_confirm(confirmation) { find("button[data-skill-delete]").click }
      assert_current_path index
      assert_equal 1, page.evaluate_script("window.skillsDeleteRequests.length")
      assert_not AgentSkill.exists?(skill.id)
      page.execute_script("window.skillsDeleteObserver.abort()")
    end
    assert_equal @first, @user.reload.first_account
    assert_no_enqueued_jobs
  ensure
    page.execute_script("window.skillsDeleteObserver?.abort()") if page.current_url.start_with?("http")
  end

  test "pending form submission has one disabled progress control until response confirmation" do
    skill = workspace_skill(:skills_second)
    visit edit_account_agent_skill_path(@second, skill)
    page.execute_script(<<~JS)
      const original=window.fetch;
      window.skillsOriginalFetch=original;
      window.fetch=async(...args)=>{
        window.fetch=original;
        const response=await original(...args);
        await new Promise(resolve=>{window.skillsRelease=resolve;document.documentElement.dataset.skillsHeld='true';});
        return response;
      };
    JS
    find("[data-skill-save]").click
    assert_selector "[data-skill-save][disabled][value='Updating…']"
    assert_selector "html[data-skills-held='true']", visible: :all
    assert_selector "form[data-skill-form]", count: 1
    page.execute_script("window.skillsRelease()")
    assert_current_path account_agent_skills_path(@second)
    assert_selector "[data-skills-feedback][role='status']"
  ensure
    if page.current_url.start_with?("http")
      page.execute_script("window.skillsRelease?.();if(window.skillsOriginalFetch)window.fetch=window.skillsOriginalFetch;delete document.documentElement.dataset.skillsHeld")
    end
  end

  test "details keep exact source whitespace as escaped browser text in both route families" do
    body = "</pre><script>window.skillsSourceExecuted=true</script><em>literal & source</em>  \n\t "
    [ [ workspace_skill(:skills_first), :legacy ], [ workspace_skill(:skills_second), :scoped ] ].each do |skill, family|
      path = family == :legacy ? agent_skill_path(skill) : account_agent_skill_path(@second, skill)
      [ body, "\n#{body}", "\n\n\n#{body}", "" ].each do |source|
        skill.update_columns(skill_content: source)
        assert_equal source, skill.reload.skill_content
        before = workspace_records.deep_dup
        assert_no_enqueued_jobs { visit path }
        assert_selector "pre[data-skill-source]", visible: :all
        assert_equal source, page.evaluate_script("document.querySelector('[data-skill-source]').textContent")
        assert_no_selector "[data-skills-workspace] script, [data-skill-source] *", visible: :all
        assert_nil page.evaluate_script("window.skillsSourceExecuted")
        assert_equal before, workspace_records
        assert_equal @first, @user.reload.first_account
      end
    end
  end

  test "all Skills page kinds fit locales themes long content and responsive viewports" do
    first = workspace_skill(:skills_first)
    second = workspace_skill(:skills_second)
    [ first, second ].each do |skill|
      name = "SkillIdentifier" * 12
      skill.update_columns(name: name, description: "Detailed authored description. " * 40,
        metadata: { "tags" => [ "LongAuthoredTag" * 30, "English" ] },
        skill_content: workspace_source(name) + "\n" + "unbrokensourcetext" * 80)
    end
    @second.update_columns(name: "CompteDeRecherche" * 12)
    before = workspace_records
    states = []
    paths = {
      legacy_list: agent_skills_path, legacy_new: new_agent_skill_path,
      legacy_detail: agent_skill_path(first), legacy_edit: edit_agent_skill_path(first),
      scoped_list: account_agent_skills_path(@second), scoped_new: new_account_agent_skill_path(@second),
      scoped_detail: account_agent_skill_path(@second, second), scoped_edit: edit_account_agent_skill_path(@second, second)
    }
    assert_no_enqueued_jobs do
      %w[en fr].each do |locale|
        select locale.upcase, from: "language_preference_locale"
        paths.each do |kind, path|
          [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ] ].each do |width, height|
            resize_skills_viewport(width, height)
            %w[light dark].each do |theme|
              visit path
              set_skills_theme(theme)
              assert_selector "html[lang='#{locale}']", visible: :all
              assert_skills_layout
              selector = if page.has_selector?("[data-skill-advanced] summary", wait: 0)
                "[data-skill-advanced] summary"
              else
                "[data-skills-workspace] a.n-workspace-link"
              end
              focus_skill_by_tab(selector)
              if selector.include?("summary")
                page.send_keys(:enter)
                assert_selector "[data-skill-advanced][open]"
              end
              assert_skills_focus
              measure_skills_contrast
              name = "#{kind}-#{locale}-#{width}-#{theme}"
              page.save_screenshot("#{@evidence_dir}/#{name}.png")
              states << { page: kind, locale: locale, theme: theme, viewport: [ width, height ], screenshot: "#{name}.png" }
              File.write("#{@evidence_dir}/matrix.json", { states: states, native_200_percent_zoom: "UNVERIFIED" }.to_json)
            end
          end
        end
      end
      assert_equal 96, states.length
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
      transitions = page.evaluate_script("Array.from(document.querySelectorAll('[data-skills-workspace] a,[data-skills-workspace] button,[data-skills-workspace] summary')).map(e=>getComputedStyle(e).transitionDuration)")
      assert transitions.all? { |duration| duration == "0s" }
    end
    assert_equal before, workspace_records
    assert_equal @first, @user.reload.first_account
  end

  test "empty setup and validation feedback stay readable in both locales and themes" do
    resize_skills_viewport(375, 812)
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      %w[light dark].each do |theme|
        visit account_agent_skills_path(@empty)
        set_skills_theme(theme)
        assert_selector "[data-skills-empty]"
        assert_skills_layout
        focus_skill_by_tab("[data-skills-empty] a")
        assert_skills_focus
        measure_skills_contrast
        page.save_screenshot("#{@evidence_dir}/empty-#{locale}-#{theme}.png")
        visit edit_account_agent_skill_path(@second, workspace_skill(:skills_second))
        find("[data-skill-advanced] summary").click
        fill_in "agent_skill_priority", with: 101
        page.execute_script("document.querySelector('form[data-skill-form]').noValidate=true")
        find("[data-skill-save]").click
        assert_selector "[data-form-errors-target='summary']"
        assert_skills_layout
        assert_selector "[data-form-errors-target='summary']:focus"
        measure_skills_contrast
        page.save_screenshot("#{@evidence_dir}/errors-#{locale}-#{theme}.png")
      end
    end
    Capybara.reset_sessions!
    visit root_url
    fill_in "email", with: experience(:users, :overview_no_account).email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      %w[light dark].each do |theme|
        visit agent_skills_path
        set_skills_theme(theme)
        assert_selector "[data-skills-setup]"
        assert_skills_layout
        focus_skill_by_tab("[data-skills-setup] a[href='#{accounts_path}']")
        assert_skills_focus
        measure_skills_contrast
        page.save_screenshot("#{@evidence_dir}/setup-#{locale}-#{theme}.png")
      end
    end
  end

  test "empty new form placeholders retain contrast in both route families and themes" do
    before = workspace_records
    resize_skills_viewport(1440, 1200)
    assert_no_enqueued_jobs do
      { legacy: new_agent_skill_path, scoped: new_account_agent_skill_path(@second) }.each do |family, path|
        %w[light dark].each do |theme|
          visit path
          set_skills_theme(theme)
          editor = find("textarea#agent_skill_skill_content:placeholder-shown", visible: true)
          assert_field "agent_skill_skill_content", with: ""
          assert editor[:placeholder].present?
          focus_skill_by_tab("#agent_skill_skill_content")
          assert_skills_focus
          measure_skills_contrast
          page.save_screenshot("#{@evidence_dir}/placeholder-#{family}-#{theme}.png")
          File.write("#{@evidence_dir}/placeholder-#{family}-#{theme}.json", {
            path: page.current_path, theme: theme,
            color: page.evaluate_script("getComputedStyle(document.querySelector('#agent_skill_skill_content'),'::placeholder').color"),
            background: page.evaluate_script("getComputedStyle(document.querySelector('#agent_skill_skill_content')).backgroundColor")
          }.to_json)
        end
      end
    end
    assert_equal before, workspace_records
    assert_equal @first, @user.reload.first_account
  end

  private
    def measure_skills_contrast
      samples = page.evaluate_script(<<~JS)
        (()=>{
          const root=document.querySelector('[data-skills-workspace]'),canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const chain=[];for(let a=e;a;a=a.parentElement)chain.unshift(a);return chain.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured gradient/opacity');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          function visible(e){return e.getClientRects().length>0&&getComputedStyle(e).visibility==='visible';}
          function measure(e,property,minimum,parent=false,pseudo=null){const s=getComputedStyle(e,pseudo),bg=background(parent?e.parentElement:e),fg=blend(rgba(s[property]),bg),a=luminance(fg),b=luminance(bg);return {tag:e.tagName,id:e.id,property,pseudo,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};}
          const text=Array.from(root.querySelectorAll('h1,h2,p,dt,dd,label,summary,a,button,input:not([type=hidden]):not([type=checkbox]),textarea,select,.n-skills-badge')).filter(visible);
          if(!text.length)throw new Error('No visible text samples');
          const rows=text.map(e=>measure(e,'color',4.5));
          root.querySelectorAll('textarea[placeholder]').forEach(e=>{if(visible(e)&&!e.value)rows.push(measure(e,'color',4.5,false,'::placeholder'));});
          root.querySelectorAll('.n-workspace-button,.n-skills-input').forEach(e=>{if(visible(e))rows.push(measure(e,'borderTopColor',3,true));});
          if(!root.contains(document.activeElement))throw new Error('Missing focused workspace action');
          rows.push(measure(document.activeElement,'outlineColor',3,true));
          return rows;
        })()
      JS
      samples.each { |sample| assert_operator sample.fetch("ratio"), :>=, sample.fetch("minimum"), sample.to_json }
      File.open("#{@evidence_dir}/contrast.jsonl", "a") do |file|
        file.puts({ path: page.current_path, viewport: page.evaluate_script("[innerWidth,innerHeight]"),
          locale: find("html", visible: :all)["lang"],
          dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: samples }.to_json)
      end
    end

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
