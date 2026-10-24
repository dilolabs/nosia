require "application_system_test_case"
require_relative "../support/dashboard_fixtures"

class DashboardSystemTest < ApplicationSystemTestCase
  include DashboardFixtures

  setup do
    travel_to @report_time
    @original_window_size = page.current_window.size
    @evidence_dir = "/tmp/opencode/dashboard-#{Process.pid}"
    FileUtils.mkdir_p(@evidence_dir)
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
    assert_selector "lexxy-editor[connected]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    page.current_window.resize_to(*@original_window_size) if @original_window_size
    travel_back
  end

  test "root composer sends in the selected account through the existing job flow" do
    visit user_root_url(account_id: @second.id, model: "overview-test-model")
    assert_selector "lexxy-editor[connected]"
    find("lexxy-editor .lexxy-editor__content").send_keys("Question from the dashboard")

    assert_enqueued_jobs 1, only: ChatResponseJob do
      find("button[aria-label='Send']").click
      assert_selector "[data-chat-account-readonly]", text: @second.name
    end

    chat = @user.chats.order(:id).last
    assert_current_path chat_path(chat)
    assert_equal @second.id, chat.account_id
    assert_equal "Question from the dashboard", chat.messages.user.last.content.strip
    assert_equal @first, @user.first_account
  end

  test "draft switching confirms reset but never changes aggregate scope or default tool labels" do
    find("lexxy-editor .lexxy-editor__content").send_keys("Keep my draft")
    dismiss_confirm(/clears your unsent message/) { select @second.name, from: "Account" }
    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
    assert_text "Keep my draft"

    accept_confirm(/clears your unsent message/) { select @second.name, from: "Account" }
    assert_selector "select option[selected][value='#{@second.id}']"
    assert_no_text "Keep my draft"
    assert_selector "[data-period-total][data-value='1057']"
    assert_selector "[data-dashboard-destination='sources']", text: @first.name
    assert_selector "[data-dropzone-account-id-value='#{@second.id}']"
  end

  test "all eight shortcuts open their existing tools and usage details match the dashboard" do
    paths = { accounts: accounts_path, sources: sources_path, usage: token_usage_path,
      profile: profile_path, skills: agent_skills_path, tokens: api_tokens_path,
      mcp: mcp_servers_path, prompts: system_prompts_path }

    assert_no_enqueued_jobs do
      paths.each do |key, path|
        visit user_root_path
        find("[data-dashboard-destination='#{key}']").click
        assert_current_path path
      end
    end

    visit user_root_path
    within(".n-usage-overview") { click_on "Usage details" }
    assert_current_path token_usage_path
    assert_selector "[data-period-total][data-value='1057']"
    assert_selector "[data-lifetime-total][data-value='1065']"
    visit token_usage_path(account_id: @second.id)
    assert_selector "[data-period-total][data-value='1057']"
    assert_selector "[data-lifetime-total][data-value='1065']"
    find(".n-dashboard-daily-data summary").click
    assert_selector ".n-dashboard-daily-data tbody tr", count: 30
    assert_equal 1057, all(".n-dashboard-daily-data tbody td").sum { |cell| cell["data-value"].to_i }
  end

  test "French long labels fit responsive layouts in both themes with visible keyboard actions" do
    @first.update_columns(name: "CompteDeRecherche" * 12)
    select "FR", from: "language_preference_locale"
    assert_selector "html[lang='fr']"
    surfaces = []

    [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
      resize_dashboard(width, height)
      %w[light dark].each do |theme|
        set_dashboard_theme(theme)
        assert_selector "h1", text: "Heureux de vous retrouver."
        assert_no_text(/translation missing|missing translation/i)
        assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
        columns = page.evaluate_script("getComputedStyle(document.querySelector('.n-dashboard-top')).gridTemplateColumns").split.length
        assert_equal width >= 1280 ? 2 : 1, columns
        if [ 375, 1440 ].include?(width)
          verify_dashboard_keyboard
          verify_dashboard_contrast
        end
        surfaces << page.evaluate_script("getComputedStyle(document.querySelector('.n-dashboard-panel')).backgroundColor")
        page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
        save_dashboard_screenshot("#{width}-#{height}-#{theme}")
        if width == 375
          page.execute_script("document.querySelector('.n-dashboard-upload').scrollIntoView({block:'center',behavior:'instant'})")
          save_dashboard_screenshot("375-#{theme}-upload")
          page.execute_script("document.querySelector('.n-dashboard-shortcuts').scrollIntoView({block:'start',behavior:'instant'})")
          save_dashboard_screenshot("375-#{theme}-shortcuts")
        end
      end
    end

    assert_operator surfaces.uniq.length, :>=, 2
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    assert page.evaluate_script("Array.from(document.querySelectorAll('.n-dashboard-shortcut')).every(e => getComputedStyle(e).transitionDuration === '0s')")
  end

  test "no-account setup guidance remains readable in both themes" do
    page.driver.browser.manage.delete_all_cookies
    visit root_url
    fill_in "email", with: experience(:users, :overview_no_account).email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
    assert_selector "[data-chat-no-account]"
    assert_no_selector "lexxy-editor"
    assert_selector "[data-period-total][data-value='0']"
    resize_dashboard(375, 812)

    %w[light dark].each do |theme|
      set_dashboard_theme(theme)
      100.times do
        page.send_keys(:tab)
        break if page.evaluate_script("document.activeElement.matches('.n-dashboard-shortcut')")
      end
      assert_selector ".n-dashboard-shortcut:focus"
      verify_dashboard_contrast
      page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
      save_dashboard_screenshot("375-no-account-#{theme}")
    end
  end

  private
    def resize_dashboard(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth,innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
    end

    def set_dashboard_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script(<<~JS)
        const done=arguments[0];
        Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());
      JS
    end

    def verify_dashboard_keyboard
      find("lexxy-editor .lexxy-editor__content").click
      seen = []
      120.times do
        page.send_keys(:tab)
        state = page.evaluate_script(<<~JS)
          (()=>{
            const e=document.activeElement;
            if(!e.matches('.n-dashboard-shortcut')) return null;
            const r=e.getBoundingClientRect(),s=getComputedStyle(e),main=document.querySelector('main').getBoundingClientRect();
            const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
            return {key:e.dataset.dashboardDestination,outline:parseFloat(s.outlineWidth),
              visible:r.top>=Math.max(0,main.top)&&r.bottom<=Math.min(innerHeight,main.bottom)&&points.every(([x,y])=>{
                const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));
              })};
          })()
        JS
        next unless state

        assert_operator state.fetch("outline"), :>=, 2
        assert state.fetch("visible"), "Focused shortcut is obscured: #{state.fetch('key')}"
        seen << state.fetch("key")
        break if seen.uniq.length == 8
      end
      assert_equal %w[accounts sources usage profile skills tokens mcp prompts], seen.uniq
      page.send_keys([ :shift, :tab ])
      assert_equal "mcp", page.evaluate_script("document.activeElement.dataset.dashboardDestination")
    end

    def verify_dashboard_contrast
      rows = page.evaluate_script(<<~JS)
        (()=>{
          const canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const ancestors=[];for(let a=e;a;a=a.parentElement)ancestors.unshift(a);return ancestors.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured gradient/opacity');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          function measure(selector,focus,minimum){
            const e=Array.from(document.querySelectorAll(selector)).find(candidate=>candidate.getClientRects().length>0&&getComputedStyle(candidate).visibility==='visible');
            if(!e)throw new Error(`No rendered visible contrast sample for ${selector}`);
            const s=getComputedStyle(e),bg=background(focus?e.parentElement:e);
            const fg=blend(rgba(focus?s.outlineColor:s.color),bg),a=luminance(fg),b=luminance(bg);
            return {selector,minimum,text:e.textContent.trim(),visibility:s.visibility,rect_count:e.getClientRects().length,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};
          }
          const samples=[...['.n-dashboard-heading h1','.n-dashboard-help','.n-dashboard-panel .n-dashboard-help','.n-dashboard-shortcut strong','.n-dashboard-shortcut .n-dashboard-help','.n-dashboard-link'].map(s=>measure(s,false,4.5)),measure('.n-dashboard-shortcut svg',false,3),measure('.n-dashboard-shortcut:focus',true,3)];
          if(document.querySelector('[data-chat-no-account]'))samples.push(measure('[data-chat-no-account]',false,4.5));
          return samples;
        })()
      JS
      rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.fetch("selector") }
      File.open("#{@evidence_dir}/contrast.jsonl", "a") do |file|
        file.puts({ viewport: page.evaluate_script("[innerWidth,innerHeight]"), dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: rows }.to_json)
      end
    end

    def save_dashboard_screenshot(name)
      page.driver.browser.execute_async_script(<<~JS)
        const done=arguments[0];
        requestAnimationFrame(()=>requestAnimationFrame(done));
      JS
      page.save_screenshot("#{@evidence_dir}/#{name}.png")
    end
end
