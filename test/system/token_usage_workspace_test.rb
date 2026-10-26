require "application_system_test_case"
require_relative "../support/dashboard_fixtures"

class TokenUsageWorkspaceSystemTest < ApplicationSystemTestCase
  include DashboardFixtures

  setup do
    travel_to @report_time
    @original_window_size = page.current_window.size
    @evidence_dir = "/tmp/opencode/token-usage-workspace-#{Process.pid}"
    FileUtils.mkdir_p(@evidence_dir)
    puts "Token usage workspace evidence: #{@evidence_dir}"
    sign_in_usage_browser(@user)
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
    Capybara.reset_sessions!
  end

  test "dashboard details and keyboard disclosures preserve global and account report semantics" do
    assert_no_enqueued_jobs do
      within(".n-usage-overview") { click_on "Usage details" }
      assert_current_path token_usage_path
      assert_selector "[data-workspace-scope]", text: "All your accounts"
      assert_selector "[data-period-total][data-value='1057']", count: 1
      assert_selector "[data-lifetime-total][data-value='1065']", count: 1
      assert_no_selector "#drawer-right, #accordion-right-actions, [data-drawer-target]", visible: :all

      focus_usage_by_tab("[data-usage-daily] summary")
      page.send_keys(:enter)
      assert_selector "[data-usage-daily][open] tbody tr", count: 30
      assert_equal 1057, all("[data-usage-daily] tbody td").sum { |cell| cell["data-value"].to_i }
      page.send_keys(:space)
      assert_no_selector "[data-usage-daily][open]"
      focus_usage_by_tab("[data-usage-methodology] summary")
      page.send_keys(:enter)
      assert_selector "[data-usage-methodology][open] a[href='https://ecologits.ai']", text: "Ecologits"

      visit account_token_usage_path(@second)
      assert_selector "[data-workspace-scope]", text: "Account: #{@second.name}"
      assert_selector "[data-lifetime-total][data-value='1045']", count: 1
      assert_no_selector "[data-period-total]", visible: :all
      assert_no_selector "#drawer-right, #accordion-right-actions, [data-drawer-target]", visible: :all
      find("[data-workspace-back]").click
      assert_current_path account_path(@second)

      resize_usage_viewport(1440, 1000)
      visit token_usage_path
      within(".n-workspace-header") { click_on "New chat" }
      assert_current_path new_chat_path
      assert_equal @first, @user.reload.first_account
    end
  end

  test "both report scopes fit the locale viewport theme matrix with real keyboard focus and measured contrast" do
    long_model = "long-model-identifier/" * 12
    @second.update_columns(name: "CompteDeRecherche" * 12,
      input_tokens_count: 2_123_456_789, output_tokens_count: 1_234_567_890)
    ActsAsTenant.without_tenant { @second.token_usages.update_all(model_id: long_model) }
    states = []

    assert_no_enqueued_jobs do
      %w[en fr].each do |locale|
        select locale.upcase, from: "language_preference_locale"
        assert_selector "html[lang='#{locale}']", visible: :all
        { global: token_usage_path, account: account_token_usage_path(@second) }.each do |scope, path|
          [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
            resize_usage_viewport(width, height)
            %w[light dark].each do |theme|
              visit path
              assert_selector "[data-usage-workspace]"
              set_usage_theme(theme)
              assert_selector "html[lang='#{locale}']", visible: :all
              assert_usage_layout(width)
              lifetime = scope == :global ? 3_358_024_699 : 3_358_024_679
              expected = {
                "en" => { global: "3,358,024,699", account: "3,358,024,679" },
                "fr" => { global: "3 358 024 699", account: "3 358 024 679" }
              }.fetch(locale).fetch(scope)
              assert_selector "[data-lifetime-total][data-value='#{lifetime}']", count: 1
              assert_equal expected, find("[data-lifetime-total]").text
              assert_selector "[data-usage-model] .n-usage-row span", text: long_model, exact_text: true
              assert_usage_text_unclipped

              # Turbo may restore native details state; close it only to establish the keyboard scenario.
              page.execute_script("document.querySelectorAll('[data-usage-workspace] details').forEach(e=>e.open=false)")
              page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
              name = "#{scope}-#{locale}-#{width}-#{height}-#{theme}"
              save_usage_screenshot("#{name}-overview")
              focus_usage_by_tab("[data-usage-daily] summary")
              assert_usage_focus_visible
              page.send_keys(:enter)
              assert_selector "[data-usage-daily][open] tbody tr"
              focus_usage_by_tab("[data-usage-methodology] summary")
              assert_usage_focus_visible
              page.send_keys(:enter)
              assert_selector "[data-usage-methodology][open] code", text: "N/A"
              assert_usage_focus_visible
              measure_usage_contrast
              focus_usage_by_tab("[data-usage-methodology] a[href='https://comparia.beta.gouv.fr/ranking']")
              assert_usage_focus_visible
              save_usage_screenshot("#{name}-methodology")
              assert_usage_layout(width)
              states << { scope: scope, locale: locale, viewport: [ width, height ], theme: theme,
                lifetime: lifetime, overview: "#{name}-overview.png", methodology: "#{name}-methodology.png" }
              File.write("#{@evidence_dir}/matrix.json", { states: states, native_200_percent_zoom: "UNVERIFIED" }.to_json)
            end
          end
        end
      end
      assert_equal 32, states.size
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
      transitions = page.evaluate_script("Array.from(document.querySelectorAll('[data-usage-workspace] a, [data-usage-workspace] summary')).map(e=>getComputedStyle(e).transitionDuration)")
      assert transitions.all? { |duration| duration == "0s" }, transitions.to_json
      assert_equal @first, @user.reload.first_account
    end
  end

  test "empty old-only and no-membership reports remain honest and readable on mobile in both themes" do
    ActsAsTenant.without_tenant do
      TokenUsage.where(account_id: @user.accounts.select(:id)).update_all(created_at: @report_time - 60.days)
    end
    resize_usage_viewport(375, 812)

    assert_no_enqueued_jobs do
      { empty: [ account_token_usage_path(@empty), 0 ],
        global_old: [ token_usage_path, 1065 ], account_old: [ account_token_usage_path(@second), 1045 ] }.each do |state, (path, lifetime)|
        %w[light dark].each do |theme|
          visit path
          set_usage_theme(theme)
          assert_usage_layout(375)
          assert_selector "[data-lifetime-total][data-value='#{lifetime}']", count: 1
          assert_selector "[data-usage-no-recent]"
          assert_selector "[data-period-total][data-value='0']" if state == :global_old
          assert_no_selector "[data-period-total]", visible: :all unless state == :global_old
          if state == :empty
            assert_no_selector "[data-usage-model], [data-usage-fallback], [data-usage-model-fallback]", visible: :all
          else
            assert_selector "[data-usage-model]"
          end
          focus_usage_by_tab("[data-usage-daily] summary")
          assert_usage_focus_visible
          page.send_keys(:enter)
          if state == :global_old
            assert_selector "[data-usage-daily] tbody td[data-value='0']", count: 30
          else
            assert_no_selector "[data-usage-day]", visible: :all
          end
          page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
          save_usage_screenshot("375-#{state}-#{theme}")
        end
      end

      Capybara.reset_sessions!
      sign_in_usage_browser(experience(:users, :overview_no_account))
      resize_usage_viewport(375, 812)
      %w[light dark].each do |theme|
        visit token_usage_path
        set_usage_theme(theme)
        assert_usage_layout(375)
        assert_selector "[data-period-total][data-value='0']", count: 1
        assert_selector "[data-lifetime-total][data-value='0']", count: 1
        assert_selector "[data-usage-no-recent]"
        assert_no_selector "[data-usage-model], [data-usage-fallback], [data-usage-model-fallback]", visible: :all
        assert_selector "[data-usage-no-memberships] a[href='#{accounts_path}']", text: "Accounts"
        focus_usage_by_tab("[data-usage-no-memberships] a")
        assert_usage_focus_visible
        page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
        save_usage_screenshot("375-no-memberships-#{theme}")
      end
    end
  end

  private
    def screenshots_dir
      @evidence_dir
    end

    def sign_in_usage_browser(user)
      visit root_url
      fill_in "email", with: user.email
      fill_in "password", with: AccountExperienceFixtures::PASSWORD
      click_on "Sign in"
      assert_selector "[data-dashboard]"
    end

    def resize_usage_viewport(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth,innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
    end

    def set_usage_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script(<<~JS)
        const done=arguments[0];
        Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());
      JS
    end

    def assert_usage_layout(width)
      assert_selector "h1", count: 1
      assert_no_text(/translation missing|missing translation/i)
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1"), "Main overflows horizontally"
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1"), "Document overflows horizontally"
      columns = page.evaluate_script("getComputedStyle(document.querySelector('.n-usage-top')).gridTemplateColumns").split.length
      assert_equal width >= 1280 ? 2 : 1, columns
    end

    def assert_usage_text_unclipped
      samples = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('.n-usage-number,[data-usage-model] .n-usage-row span:first-child')).map(e=>{
          const s=getComputedStyle(e),r=e.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(e);
          const rects=Array.from(range.getClientRects());
          return {text:e.textContent.trim(),ellipsis:s.textOverflow==='ellipsis',
            fits:e.scrollWidth<=e.clientWidth+1&&e.scrollHeight<=e.clientHeight+1&&rects.every(t=>t.left>=r.left-1&&t.right<=r.right+1&&t.top>=r.top-1&&t.bottom<=r.bottom+1)};
        })
      JS
      assert_not_empty samples
      samples.each do |sample|
        refute sample.fetch("ellipsis"), sample.to_json
        assert sample.fetch("fits"), sample.to_json
      end
    end

    def focus_usage_by_tab(selector)
      200.times do
        page.send_keys(:tab)
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          # Let native keyboard autoscroll reach the compositor before hit-testing its edges.
          page.driver.browser.execute_async_script(<<~JS)
            const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));
          JS
          return
        end
      end
      flunk "Keyboard could not reach #{selector}"
    end

    def assert_usage_focus_visible
      sample = page.evaluate_script(<<~JS)
        (()=>{
          const e=document.activeElement,r=e.getBoundingClientRect(),s=getComputedStyle(e),main=document.querySelector('main').getBoundingClientRect();
          const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
          return {text:e.textContent.trim(),height:r.height,outline:parseFloat(s.outlineWidth),bounds:r.toJSON(),main:main.toJSON(),viewport:[innerWidth,innerHeight],hits:points.map(([x,y])=>document.elementFromPoint(x,y)?.outerHTML.slice(0,240)),visible:r.top>=Math.max(0,main.top)&&r.bottom<=Math.min(innerHeight,main.bottom)&&points.every(([x,y])=>{const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));})};
        })()
      JS
      unless sample.fetch("visible")
        fragments = page.evaluate_script(<<~JS)
          (()=>{
            const e=document.activeElement,r=e.getBoundingClientRect(),x=r.right-1,y=r.y+r.height/2;
            return {point:[x,y],edgeHits:[0,0.1,0.5,1,2,3,4,8].map(d=>({inset:d,hit:document.elementFromPoint(r.right-d,y)?.tagName})),stack:document.elementsFromPoint(x,y).map(n=>({tag:n.tagName,classes:n.className})),fragments:Array.from(e.parentNode.childNodes).map(n=>{
              const range=document.createRange();range.selectNode(n);
              return {text:n.textContent,rects:Array.from(range.getClientRects()).map(r=>r.toJSON())};
            })};
          })()
        JS
        File.write("#{@evidence_dir}/obscured-focus.json", { sample: sample, fragments: fragments }.to_json)
      end
      assert_operator sample.fetch("height"), :>=, 44, sample.to_json
      assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
      assert sample.fetch("visible"), "Focused action is obscured: #{sample}"
    end

    def measure_usage_contrast
      rows = page.evaluate_script(<<~JS)
        (()=>{
          const root=document.querySelector('[data-usage-workspace]'),canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const ancestors=[];for(let a=e;a;a=a.parentElement)ancestors.unshift(a);return ancestors.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured gradient/opacity');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          function visible(e){return e.getClientRects().length>0&&getComputedStyle(e).visibility==='visible';}
          function measure(e,property,minimum,parent=false){const s=getComputedStyle(e),bg=background(parent?e.parentElement:e),fg=blend(rgba(s[property]),bg),a=luminance(fg),b=luminance(bg);return {element:e.tagName,text:e.textContent.trim().slice(0,160),property,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};}
          const selectors=['h1','h2','h3','.n-workspace-help','.n-workspace-scope','.n-usage-number','.n-workspace-link','.n-usage-row span','.n-usage-disclosure summary','.n-usage-disclosure th','.n-usage-disclosure td','.n-usage-methodology-content p','.n-usage-methodology-content strong','.n-usage-methodology-content em','.n-usage-methodology-content code'];
          const rows=selectors.flatMap(selector=>{const elements=Array.from(root.querySelectorAll(selector)).filter(visible);if(!elements.length)throw new Error(`No visible contrast sample: ${selector}`);return elements.map(e=>measure(e,'color',4.5));});
          rows.push(measure(root.querySelector('.n-usage-chart'),'color',3));
          root.querySelectorAll('summary').forEach(e=>rows.push(measure(e,'borderTopColor',3)));
          if(!root.contains(document.activeElement))throw new Error('Missing focused workspace action');
          rows.push(measure(document.activeElement,'outlineColor',3,true));
          return rows;
        })()
      JS
      rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.to_json }
      File.open("#{@evidence_dir}/contrast.jsonl", "a") do |file|
        file.puts({ viewport: page.evaluate_script("[innerWidth,innerHeight]"), locale: page.find("html", visible: :all)["lang"], dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: rows }.to_json)
      end
    end

    def save_usage_screenshot(name)
      page.driver.browser.execute_async_script(<<~JS)
        const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));
      JS
      page.save_screenshot("#{@evidence_dir}/#{name}.png")
    end
end
