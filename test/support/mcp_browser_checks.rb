require "tmpdir"
require "fileutils"

# Samples workspace layout, keyboard access and contrast in an isolated browser session.
# Desktop input capability emulation is not physical hardware or native zoom proof.
module McpBrowserChecks
  extend ActiveSupport::Concern

  DRIVER = :mcp_workspace_desktop_input
  INPUT_FLAG = "--blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4".freeze

  included do
    setup do
      FileUtils.mkdir_p("/tmp/opencode")
      @mcp_evidence = Dir.mktmpdir("mcp-browser-", "/tmp/opencode")
      @old_driver, @old_session = Capybara.current_driver, Capybara.session_name
      @old_registration = Capybara.drivers[@old_driver]
      options = { name: DRIVER }
      options.merge!(browser: :remote, url: "http://:4444") if ENV["CAPYBARA_SERVER_PORT"]
      ActionDispatch::SystemTesting::Driver.new(:selenium, using: :headless_chrome,
        screen_size: [ 1400, 1400 ], options: options) { |settings| settings.add_argument(INPUT_FLAG) }.use
      Capybara.session_name = "mcp_workspace_#{object_id}"
      @mcp_session = Capybara.current_session
    end

    teardown do
      begin
        if @mcp_session
          page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
          page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
          page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
        end
      ensure
        begin
          @mcp_session&.quit
        ensure
          Capybara.current_driver = @old_driver
          Capybara.session_name = @old_session
        end
      end
      assert_same @old_registration, Capybara.drivers[@old_driver]
      assert_equal @old_driver, Capybara.current_driver
      assert_equal @old_session, Capybara.session_name
      File.write(File.join(@mcp_evidence, "cleanup.json"), { driver_restored: true, session_restored: true,
        original_registration_unchanged: true, input_capability_emulation: INPUT_FLAG, physical_hardware_proof: false }.to_json)
    end
  end

  # Emulates viewport dimensions and verifies the actual CSS viewport.
  # @param width [Integer] CSS viewport width
  # @param height [Integer] CSS viewport height
  # @return [void]
  def mcp_size(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
    assert_equal [ width, height ], page.evaluate_script("[innerWidth,innerHeight]")
  end

  # Waits for two browser animation frames without changing animation state.
  # @return [void]
  def mcp_wait
    page.driver.browser.execute_async_script("const done=arguments[0];requestAnimationFrame(()=>requestAnimationFrame(done));")
  end

  # Selects a theme using the real theme control and waits for animations.
  # @param theme [String] Either light or dark
  # @return [void]
  def mcp_theme(theme)
    find("#theme-toggle").click if page.evaluate_script("document.documentElement.classList.contains('dark')") != (theme == "dark")
    assert_equal theme == "dark", page.evaluate_script("document.documentElement.classList.contains('dark')")
    page.driver.browser.execute_async_script("const done=arguments[0];Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))).then(()=>done());")
  end

  # Reaches a control through native Tab presses, never forced focus.
  # @param selector [String] CSS selector matching the desired focused element
  # @return [void]
  def mcp_tab_to(selector)
    160.times do
      page.send_keys(:tab)
      if page.evaluate_script("document.activeElement.matches(arguments[0])", selector)
        mcp_wait
        return
      end
    end
    flunk "Keyboard could not reach #{selector}"
  end

  # Checks target size, focus outline and unobscured control edges.
  # @param direction [String, nil] Native traversal direction, when walking the matrix
  # @param index [Integer, nil] Recorded DOM-order index, when walking the matrix
  # @return [void]
  def mcp_assert_focus(direction: nil, index: nil)
    sample = page.evaluate_script(<<~JS)
      (()=>{const active=document.activeElement,e=active.matches('input[type=checkbox]')?active.closest('label'):active;
        const r=e.getBoundingClientRect(),s=getComputedStyle(e),main=document.querySelector('main'),m=main.getBoundingClientRect(),ms=getComputedStyle(main);
        const points=[[r.x+r.width/2,r.top+1],[r.x+r.width/2,r.bottom-1],[r.left+1,r.y+r.height/2],[r.right-1,r.y+r.height/2]];
        return {tag:active.tagName,id:active.id,role:active.getAttribute('role'),text:e.textContent.trim(),width:r.width,height:r.height,outline:parseFloat(s.outlineWidth),
          bounds:[r.x,r.y,r.width,r.height],mainBounds:[m.x,m.y,m.width,m.height],hitPoints:points.map(([x,y])=>({x,y,hit:document.elementFromPoint(x,y)?.outerHTML.slice(0,200)})),
          nativeScroll:{top:main.scrollTop,paddingStart:ms.scrollPaddingBlockStart,paddingEnd:ms.scrollPaddingBlockEnd,overflow:ms.overflowY},
          visible:r.top>=Math.max(0,m.top)&&r.bottom<=Math.min(innerHeight,m.bottom)&&points.every(([x,y])=>{const hit=document.elementFromPoint(x,y);return !!hit&&(hit===e||e.contains(hit));})};})()
    JS
    mcp_record_check("focus", { direction: direction, index: index, sample: sample })
    assert_operator sample.fetch("height"), :>=, 44, sample.to_json
    assert_operator sample.fetch("width"), :>=, 44, sample.to_json
    assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
    assert sample.fetch("visible"), sample.to_json
  end

  # Checks every visible workspace Tab stop in DOM order and reverse traversal.
  # Tall tab panels require intersection, not an impossible full-height control fit.
  # @return [void]
  def mcp_keyboard_walk
    count = page.evaluate_script(<<~JS)
      Array.from(document.querySelector('[data-mcp-workspace]').querySelectorAll('a,button,input,select,textarea,summary,[role=tabpanel]'))
        .filter(e=>e.getClientRects().length&&e.checkVisibility()&&getComputedStyle(e).visibility==='visible'&&!e.disabled&&e.tabIndex>=0)
        .map((e,index)=>{e.dataset.mcpWalk=String(index);return e;}).length
    JS
    assert_operator count, :>, 1
    mcp_tab_to("[data-mcp-walk='0']")
    count.times do |index|
      if index.positive?
        page.send_keys(:tab)
        mcp_wait
      end
      mcp_assert_keyboard_stop(index, "forward")
    end
    mcp_assert_keyboard_stop(count - 1, "reverse")
    page.send_keys([ :shift, :tab ])
    mcp_wait
    assert page.evaluate_script("document.activeElement.dataset.mcpWalk===arguments[0]", (count - 2).to_s)
    mcp_assert_keyboard_stop(count - 2, "reverse")
    (count - 3).downto(0) do |index|
      page.send_keys([ :shift, :tab ])
      mcp_wait
      mcp_assert_keyboard_stop(index, "reverse")
    end
  end

  # Checks and records the actual keyboard target without changing focus or scroll.
  # @param index [Integer] Expected recorded DOM-order index
  # @param direction [String] Native traversal direction
  # @return [void]
  def mcp_assert_keyboard_stop(index, direction)
    order = page.evaluate_script(<<~JS, index.to_s)
      (()=>{const expected=document.querySelector(`[data-mcp-walk='${arguments[0]}']`),actual=document.activeElement;
        const describe=e=>({tag:e.tagName,id:e.id,walk:e.dataset.mcpWalk,closedDetails:!!e.closest('details:not([open])'),visible:e.checkVisibility(),html:e.outerHTML.slice(0,300)});
        return {matches:actual.dataset.mcpWalk===arguments[0],expected:describe(expected),actual:describe(actual)};})()
    JS
    mcp_record_check("keyboard", { direction: direction, index: index, order: order })
    assert order.fetch("matches"), "Visible DOM/keyboard order diverged at #{index} (#{direction}): #{order.to_json}"
    if page.evaluate_script("document.activeElement.getAttribute('role')==='tabpanel'")
      sample = page.evaluate_script(<<~JS)
        (()=>{const e=document.activeElement,r=e.getBoundingClientRect(),m=document.querySelector('main').getBoundingClientRect();
          return {id:e.id,role:e.getAttribute('role'),outline:parseFloat(getComputedStyle(e).outlineWidth),visible:r.bottom>m.top&&r.top<m.bottom};})()
      JS
      mcp_record_check("focus", { direction: direction, index: index, sample: sample })
      assert_operator sample.fetch("outline"), :>=, 2, sample.to_json
      assert sample.fetch("visible"), sample.to_json
    else
      mcp_assert_focus(direction: direction, index: index)
    end
  end

  # Rejects horizontal overflow, ellipsis and clipped workspace text.
  # @return [void]
  def mcp_layout
    assert page.evaluate_script("document.documentElement.scrollWidth<=document.documentElement.clientWidth+1&&document.querySelector('main').scrollWidth<=document.querySelector('main').clientWidth+1")
    rows = page.evaluate_script(<<~JS)
      Array.from(document.querySelector('[data-mcp-workspace]').querySelectorAll('h1,h2,h3,p,dt,dd,label,summary,pre')).filter(e=>e.getClientRects().length&&e.checkVisibility()).map(e=>{
        const r=e.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(e);
        return {text:e.textContent.slice(0,80),ellipsis:getComputedStyle(e).textOverflow==='ellipsis',fits:e.scrollWidth<=e.clientWidth+1&&Array.from(range.getClientRects()).every(t=>t.left>=r.left-1&&t.right<=r.right+1)};
      })
    JS
    action_rows = page.evaluate_script(<<~JS)
      (()=>{const root=document.querySelector('[data-mcp-workspace]'),ctx=document.createElement('canvas').getContext('2d');
        return Array.from(root.querySelectorAll('a,button,input[type=submit],header nav,header nav li,header nav span'))
          .filter(e=>e.getClientRects().length&&e.checkVisibility()&&getComputedStyle(e).visibility==='visible').map(e=>{
            const r=e.getBoundingClientRect(),s=getComputedStyle(e),submit=e.matches('input[type=submit]');
            let fits=e.scrollWidth<=e.clientWidth+1,measurement;
            if(submit){
              const text=s.textTransform==='uppercase'?e.value.toUpperCase():s.textTransform==='lowercase'?e.value.toLowerCase():e.value;
              ctx.font=[s.fontStyle,s.fontVariant,s.fontWeight,s.fontSize,s.fontFamily].join(' ');
              const metrics=ctx.measureText(text),width=metrics.width+Math.max(0,text.length-1)*(parseFloat(s.letterSpacing)||0);
              const availableWidth=r.width-parseFloat(s.paddingLeft)-parseFloat(s.paddingRight)-parseFloat(s.borderLeftWidth)-parseFloat(s.borderRightWidth);
              const height=metrics.actualBoundingBoxAscent+metrics.actualBoundingBoxDescent;
              const availableHeight=r.height-parseFloat(s.paddingTop)-parseFloat(s.paddingBottom)-parseFloat(s.borderTopWidth)-parseFloat(s.borderBottomWidth);
              measurement={method:'computed-submit-value',width,availableWidth,height,availableHeight};
              fits=fits&&text.length>0&&width<=availableWidth+1&&height<=availableHeight+1;
            }else{
              const walker=document.createTreeWalker(e,NodeFilter.SHOW_TEXT),rects=[];let text;
              while(text=walker.nextNode()){if(!text.textContent.trim())continue;const range=document.createRange();range.selectNodeContents(text);rects.push(...range.getClientRects());}
              measurement={method:'text-node-ranges',rects:rects.map(t=>({left:t.left,right:t.right,top:t.top,bottom:t.bottom}))};
              fits=fits&&rects.length>0&&rects.every(t=>t.left>=r.left-1&&t.right<=r.right+1&&t.top>=r.top-1&&t.bottom<=r.bottom+1);
            }
            return {kind:e.closest('header nav')?'breadcrumb':'action-label',tag:e.tagName,text:(submit?e.value:e.textContent).trim().slice(0,200),
              ellipsis:s.textOverflow==='ellipsis',fits,measurement};
          });})()
    JS
    rows.concat(action_rows)
    mcp_record_check("layout", { samples: rows })
    assert_not_empty rows
    rows.each do |row|
      refute row.fetch("ellipsis"), row.to_json
      assert row.fetch("fits"), row.to_json
    end
  end

  # Samples composed foreground/background contrast and records all ratios.
  # @param phase [String] Interaction state recorded with the samples
  # @return [void]
  def mcp_contrast(phase)
    rows = page.evaluate_script(<<~JS)
      (()=>{const root=document.querySelector('[data-mcp-workspace]'),c=document.createElement('canvas');c.width=c.height=1;
        const ctx=c.getContext('2d',{willReadFrequently:true});
        function rgba(v){ctx.clearRect(0,0,1,1);ctx.fillStyle=v;ctx.fillRect(0,0,1,1);const p=Array.from(ctx.getImageData(0,0,1,1).data);p[3]/=255;return p;}
        function blend(a,b){return a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3]));}
        function bg(e){const a=[];for(;e;e=e.parentElement)a.unshift(e);return a.reduce((b,e)=>{const s=getComputedStyle(e);if(s.opacity!=='1'||s.backgroundImage!=='none')throw Error('Unmeasured surface');return blend(rgba(s.backgroundColor),b);},[255,255,255]);}
        function lum(a){return a.map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4}).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0);}
        function row(e,property,minimum,outside=false){const b=bg(outside?e.parentElement:e),f=blend(rgba(getComputedStyle(e)[property]),b),x=lum(f),y=lum(b);return {tag:e.tagName,id:e.id,kind:e.matches('.n-mcp-status')?'status-text':'ordinary',text:e.textContent.trim().slice(0,70),property,minimum,outside,background:b,foreground:f,ratio:(Math.max(x,y)+.05)/(Math.min(x,y)+.05)};}
        const visible=e=>e.getClientRects().length&&e.checkVisibility()&&getComputedStyle(e).visibility==='visible'&&!e.disabled;
        const rows=Array.from(root.querySelectorAll('h1,h2,h3,p,dt,dd,label,summary,pre,a,button,input,select,textarea,svg,.n-mcp-status')).filter(visible).map(e=>row(e,'color',e.tagName.toLowerCase()==='svg'?3:4.5));
        root.querySelectorAll('.n-workspace-button,.n-mcp-input').forEach(e=>{if(!visible(e))return;if(e.classList.contains('n-workspace-primary'))rows.push(row(e,'backgroundColor',3,true));else{rows.push(row(e,'borderTopColor',3));rows.push(row(e,'borderTopColor',3,true));}});
        root.querySelectorAll('.n-mcp-tabs [aria-selected=true]').forEach(e=>{if(!visible(e))return;[false,true].forEach(outside=>rows.push({...row(e,'borderBottomColor',3,outside),kind:'selected-tab-indicator',width:parseFloat(getComputedStyle(e).borderBottomWidth),adjacent:outside?'tablist-surface':'tab-surface'}));});
        const active=document.activeElement;if(root.contains(active)){const e=active.matches('input[type=checkbox]')?active.closest('label'):active;rows.push(row(e,'outlineColor',3,true));}return rows;})()
    JS
    File.open(File.join(@mcp_evidence, "contrast.jsonl"), "a") { |file| file.puts({ path: URI(page.current_url).path, phase: phase, locale: find("html", visible: :all)["lang"], viewport: page.evaluate_script("[innerWidth,innerHeight]"), samples: rows }.to_json) }
    rows.each do |row|
      assert_operator row.fetch("ratio"), :>=, row.fetch("minimum"), row.to_json
      assert_operator row.fetch("width"), :>=, 2, row.to_json if row.fetch("kind") == "selected-tab-indicator"
    end
  end

  # Verifies an unrelated control remains interactable without activating it.
  # @param selector [String] Exact unrelated control selector
  # @param phase [String] Connection-operation phase recorded with the sample
  # @return [void]
  def mcp_assert_available_control(selector, phase)
    element = find(selector)
    sample = page.evaluate_script(<<~JS, element)
      (()=>{const e=arguments[0],r=e.getBoundingClientRect(),s=getComputedStyle(e),hit=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);
        return {text:e.textContent.trim(),disabled:e.matches(':disabled'),ariaDisabled:e.closest('[aria-disabled=true]')!==null,inert:e.closest('[inert]')!==null,
          pointerEvents:s.pointerEvents,width:r.width,height:r.height,visible:r.top>=0&&r.bottom<=innerHeight&&r.left>=0&&r.right<=innerWidth&&!!hit&&(hit===e||e.contains(hit))};})()
    JS
    mcp_record_check("busy-availability", { selector: selector, phase: phase, sample: sample })
    refute sample.fetch("disabled"), sample.to_json
    refute sample.fetch("ariaDisabled"), sample.to_json
    refute sample.fetch("inert"), sample.to_json
    refute_equal "none", sample.fetch("pointerEvents"), sample.to_json
    assert_operator sample.fetch("width"), :>=, 44, sample.to_json
    assert_operator sample.fetch("height"), :>=, 44, sample.to_json
    assert sample.fetch("visible"), sample.to_json
  end

  # Verifies genuine pointer hover changes the primary surface without shifting it.
  # @return [void]
  def mcp_hover
    target = first("[data-mcp-workspace] .n-workspace-primary")
    page.execute_script("arguments[0].scrollIntoView({block:'center',behavior:'instant'})", target)
    mcp_wait
    find("#theme-toggle").hover
    before = mcp_hover_sample(target)
    refute before.fetch("hovered")
    assert_equal before.fetch("expected"), before.fetch("background")
    mcp_contrast("unhovered")
    target.hover
    mcp_wait
    after = mcp_hover_sample(target)
    assert before.fetch("capable") && after.fetch("capable"), after.to_json
    assert after.fetch("hovered")
    assert_equal before.fetch("bounds"), after.fetch("bounds")
    refute_equal before.fetch("background"), after.fetch("background")
    assert_equal after.fetch("expected"), after.fetch("background")
    mcp_contrast("hovered")
    File.open(File.join(@mcp_evidence, "hover.jsonl"), "a") { |file| file.puts({ before: before, after: after, input_capability_emulation: INPUT_FLAG }.to_json) }
  end

  # Resolves the primary control's actual surface and expected theme/hover token.
  # @param element [Capybara::Node::Element] Primary workspace control
  # @return [Hash] Hover, input capability, bounds and RGBA color evidence
  def mcp_hover_sample(element)
    page.evaluate_script(<<~JS, element)
      (()=>{const e=arguments[0],r=e.getBoundingClientRect(),dark=document.documentElement.classList.contains('dark'),hovered=e.matches(':hover');
        const token=dark?(hovered?'--color-green-200':'--color-green-300'):(hovered?'--color-green-800':'--color-green-700');
        const c=document.createElement('canvas');c.width=c.height=1;const x=c.getContext('2d');function rgba(v){x.clearRect(0,0,1,1);x.fillStyle=v;x.fillRect(0,0,1,1);return Array.from(x.getImageData(0,0,1,1).data)};
        return {hovered,capable:matchMedia('(hover:hover)').matches&&matchMedia('(pointer:fine)').matches,bounds:[r.x,r.y,r.width,r.height],background:rgba(getComputedStyle(e).backgroundColor),expected:rgba(getComputedStyle(document.documentElement).getPropertyValue(token)),token};})()
    JS
  end

  private
    def mcp_record_check(name, sample)
      context = page.evaluate_script("({path:location.pathname,screen:document.querySelector('[data-mcp-screen]')?.dataset.mcpScreen,locale:document.documentElement.lang,viewport:[innerWidth,innerHeight],theme:document.documentElement.classList.contains('dark')?'dark':'light'})")
      File.open(File.join(@mcp_evidence, "#{name}.jsonl"), "a") { |file| file.puts(context.merge(sample).to_json) }
    end
end
