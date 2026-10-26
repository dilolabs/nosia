require "tmpdir"
require "application_system_test_case"
require_relative "../support/account_experience_fixtures"

class AccountsSettingsWorkspaceSystemTest < ApplicationSystemTestCase
  include AccountExperienceFixtures

  setup do
    @original_window_size = page.current_window.size
    @evidence_dir = Dir.mktmpdir("accounts-settings-browser-", "/tmp/opencode")
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: AccountExperienceFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "[data-dashboard]"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if @viewport_override
    page.current_window.resize_to(*@original_window_size) if @original_window_size
    if page.current_url.start_with?("http")
      page.driver.browser.manage.delete_cookie("locale")
      page.execute_script("localStorage.removeItem('color-theme')")
    end
    Capybara.reset_sessions!
  end

  test "header creation actions work by keyboard without starting generation" do
    resize_workspace(1440, 1000)
    before = [ Chat.count, Prompt.count ]
    assert_no_enqueued_jobs do
      visit accounts_path
      focus_by_tab(".n-workspace-header a[href='#{new_account_path}']")
      assert_focused_action
      page.send_keys(:enter)
      assert_current_path new_account_path
      assert_selector "#account_name"
      visit account_path(@second)
      focus_by_tab(".n-workspace-header a[href='#{new_chat_path(account_id: @second.id)}']")
      assert_focused_action
      page.send_keys(:enter)
      assert_current_path new_chat_path(account_id: @second.id)
      assert_selector "select[name='chat[account_id]'] option[value='#{@second.id}']:checked"
    end
    assert_equal before, [ Chat.count, Prompt.count ]
    assert_equal @first, @user.reload.first_account
  end

  test "all Settings cards navigate and generic New chat remains accessible" do
    resize_workspace(1440, 1000)
    [ agent_skills_path, api_tokens_path, mcp_servers_path, system_prompts_path ].each do |path|
      visit settings_path
      focus_by_tab("[data-settings-card][href='#{path}']")
      assert_focused_action
      page.send_keys(:enter)
      assert_current_path path
    end
    visit settings_path
    focus_by_tab(".n-workspace-header a[href='#{new_chat_path}']")
    page.send_keys(:enter)
    assert_current_path new_chat_path
    assert_equal @first, @user.reload.first_account
    assert_no_enqueued_jobs
  end

  test "three pages reflow with readable focus across locales viewports and themes" do
    @second.update_columns(name: "CompteDeRecherche" * 12, uid: "identifiant-sans-espace-" * 7)
    states = []
    %w[en fr].each do |locale|
      select locale.upcase, from: "language_preference_locale"
      assert_selector "html[lang='#{locale}']", visible: :all
      [ [ :directory, accounts_path ], [ :account, account_path(@second) ], [ :settings, settings_path ] ].each do |name, path|
        [ [ 375, 812 ], [ 768, 1024 ], [ 1440, 1000 ], [ 812, 375 ] ].each do |width, height|
          resize_workspace(width, height)
          %w[light dark].each do |theme|
            visit path
            set_workspace_theme(theme)
            assert_selector "main h1", count: 1
            assert_selector "main .n-workspace-header nav", count: 1
            assert_no_text(/translation missing|missing translation/i)
            assert_workspace_layout
            if name == :settings
              columns = page.evaluate_script("getComputedStyle(document.querySelector('.n-settings-grid')).gridTemplateColumns").split.length
              assert_equal width >= 768 ? 2 : 1, columns
              assert_selector "[data-settings-card]", count: 4
              assert_no_selector "#drawer-right, #accordion-right-actions", visible: :all
              assert_equal width >= 1024 ? 1 : 0, all(".n-workspace-header a[href='#{new_chat_path}']").length
            end
            if name == :account
              assert_selector "h1", text: @second.name
              assert_selector ".n-workspace-header .n-workspace-help", text: @second.uid
            end
            root = name == :settings ? "[data-settings-workspace]" : ".n-accounts > .n-workspace-header"
            selectors = all("#{root} a").map { |link| "#{root} a[href='#{URI(link[:href]).request_uri}']" }
            focus_by_tab(selectors.first)
            assert_focused_action
            selectors.drop(1).each do |selector|
              page.send_keys(:tab)
              wait_for_keyboard_scroll
              assert page.evaluate_script("document.activeElement.matches(arguments[0])", selector), "Tab order differs from visible link order"
              assert_focused_action
            end
            page.send_keys([ :shift, :tab ])
            wait_for_keyboard_scroll
            assert page.evaluate_script("document.activeElement.matches(arguments[0])", selectors[-2])
            assert_focused_action
            assert_text_unclipped(root)
            measure_workspace_contrast(root)
            if name == :settings
              card = first("[data-settings-card]")
              page.execute_script("arguments[0].scrollIntoView({block:'center'})", card)
              wait_for_keyboard_scroll
              before_hover = page.evaluate_script("(()=>{const r=arguments[0].getBoundingClientRect();return [r.x,r.y,r.width,r.height];})()", card)
              card.hover
              wait_for_keyboard_scroll
              assert_equal before_hover, page.evaluate_script("(()=>{const r=arguments[0].getBoundingClientRect();return [r.x,r.y,r.width,r.height];})()", card)
              measure_workspace_contrast(root)
            end
            page.execute_script("document.querySelector('main').scrollTo({top:0,behavior:'instant'})")
            image = "#{name}-#{locale}-#{width}-#{height}-#{theme}.png"
            page.save_screenshot(File.join(@evidence_dir, image)) if [ 375, 1440 ].include?(width)
            states << { page: name, locale: locale, viewport: [ width, height ], theme: theme }
            File.write(File.join(@evidence_dir, "matrix.json"), { states: states, native_200_percent_zoom: "UNVERIFIED" }.to_json)
          end
        end
      end
    end
    assert_equal 48, states.size
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    [ accounts_path, account_path(@second), settings_path ].each do |path|
      visit path
      assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
      assert page.evaluate_script("Array.from(document.querySelectorAll('main .n-workspace-header a, [data-settings-card]')).every(e=>getComputedStyle(e).transitionDuration==='0s')")
    end
    assert_equal @first, @user.reload.first_account
    puts "Accounts/Settings browser evidence: #{@evidence_dir}"
  end

  private
    def resize_workspace(width, height)
      page.current_window.resize_to(width, height)
      if page.evaluate_script("[innerWidth,innerHeight]") != [ width, height ]
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
        @viewport_override = true
      end
      assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
    end

    def set_workspace_theme(theme)
      dark = page.evaluate_script("document.documentElement.classList.contains('dark')")
      find("#theme-toggle").click if dark != (theme == "dark")
      assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
      page.driver.browser.execute_async_script("const done=arguments[0]; Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());")
    end

    def assert_workspace_layout
      assert page.evaluate_script("document.querySelector('main').scrollWidth <= document.querySelector('main').clientWidth + 1")
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1")
    end

    def focus_by_tab(selector)
      200.times do
        page.send_keys(:tab)
        if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
          wait_for_keyboard_scroll
          return
        end
      end
      flunk "Keyboard could not reach #{selector}"
    end

    def wait_for_keyboard_scroll
      page.driver.browser.execute_async_script("const done=arguments[0]; requestAnimationFrame(()=>requestAnimationFrame(done));")
    end

    def assert_focused_action
      sample = page.evaluate_script(<<~JS)
        (()=>{
          const e=document.activeElement,r=e.getBoundingClientRect(),s=getComputedStyle(e),m=document.querySelector('main').getBoundingClientRect();
          const points=[[r.x+r.width/2,r.y+1],[r.x+r.width/2,r.bottom-1],[r.x+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
          return {text:e.textContent.trim(),height:r.height,outline:parseFloat(s.outlineWidth),visible:r.top>=Math.max(0,m.top)&&r.bottom<=Math.min(innerHeight,m.bottom)&&points.every(([x,y])=>{const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));})};
        })()
      JS
      assert_operator sample.fetch("height"), :>=, 44, sample.to_json
      assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
      assert sample.fetch("visible"), sample.to_json
    end

    def assert_text_unclipped(root)
      samples = page.evaluate_script(<<~JS, root)
        Array.from(document.querySelector(arguments[0]).querySelectorAll('h1,h2,p,a span')).filter(e=>e.getClientRects().length).map(e=>{
          const s=getComputedStyle(e),r=e.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(e);
          return {text:e.textContent,ellipsis:s.textOverflow==='ellipsis',fits:e.scrollWidth<=e.clientWidth+1&&Array.from(range.getClientRects()).every(t=>t.left>=r.left-1&&t.right<=r.right+1)};
        })
      JS
      assert_not_empty samples
      samples.each do |sample|
        refute sample.fetch("ellipsis"), sample.to_json
        assert sample.fetch("fits"), sample.to_json
      end
    end

    def measure_workspace_contrast(root)
      rows = page.evaluate_script(<<~JS, root)
        (()=>{
          const root=document.querySelector(arguments[0]),canvas=document.createElement('canvas');canvas.width=canvas.height=1;
          const ctx=canvas.getContext('2d',{willReadFrequently:true});
          function rgba(color){ctx.clearRect(0,0,1,1);ctx.fillStyle=color;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
          function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
          function background(e){const ancestors=[];for(let a=e;a;a=a.parentElement)ancestors.unshift(a);return ancestors.reduce((bg,a)=>{const s=getComputedStyle(a);if(s.backgroundImage!=='none'||s.opacity!=='1')throw new Error('Unmeasured surface');return blend(rgba(s.backgroundColor),bg);},[255,255,255]);}
          function luminance(rgb){return rgb.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);}
          function measure(e,property,minimum,parent=false){const s=getComputedStyle(e),bg=background(parent?e.parentElement:e),fg=blend(rgba(s[property]),bg),a=luminance(fg),b=luminance(bg);return {text:e.textContent.trim().slice(0,100),property,minimum,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};}
          const visible=e=>e.getClientRects().length>0&&getComputedStyle(e).visibility==='visible';
          const rows=Array.from(root.querySelectorAll('h1,h2,p,a,svg')).filter(visible).map(e=>measure(e,'color',e.tagName.toLowerCase()==='svg'?3:4.5));
          root.querySelectorAll('[data-settings-card]').forEach(e=>{rows.push(measure(e,'borderTopColor',3,true));rows.push(measure(e,'borderTopColor',3));});
          if(!root.contains(document.activeElement))throw new Error('Missing focused workspace link');
          rows.push(measure(document.activeElement,'outlineColor',3,true));return rows;
        })()
      JS
      assert_not_empty rows
      rows.each { |row| assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.to_json }
      File.open(File.join(@evidence_dir, "contrast.jsonl"), "a") do |file|
        file.puts({ path: URI(page.current_url).path, viewport: page.evaluate_script("[innerWidth,innerHeight]"), locale: find("html", visible: :all)["lang"], dark: page.evaluate_script("document.documentElement.classList.contains('dark')"), samples: rows }.to_json)
      end
    end
end
