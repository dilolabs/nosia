require "application_system_test_case"
require "tempfile"
require_relative "../support/chat_account_fixtures"

class ChatComposerUiSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures
  include ActionView::RecordIdentifier

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
    visit new_chat_url(model: "picker-test-model")
    assert_current_path new_chat_path, ignore_query: true
    assert_selector "lexxy-editor[connected]"
  end

  test "compact PDF action uses the native uploader in both new-chat entry points" do
    [ user_root_url(account_id: @second.id), new_chat_url(account_id: @second.id) ].each do |url|
      visit url
      assert_selector "lexxy-editor[connected]"
      with_pdf do |path|
        assert_enqueued_jobs 1, only: AddDocumentJob do
          attach_file(path) { click_button "Attach PDF", enable_aria_label: true }
          assert_selector "input[name='chat[attached_document_ids][]']", count: 2, visible: :all
        end
        document = @second.documents.joins(file_attachment: :blob).find_by!(active_storage_blobs: { filename: File.basename(path) })
        assert_equal File.binread(path), document.file.download
        assert_not @first.documents.joins(file_attachment: :blob).exists?(active_storage_blobs: { filename: File.basename(path) })
      end
    end
  end

  test "formatting opens by keyboard and still runs native bold and link commands" do
    content = find("lexxy-editor .lexxy-editor__content")
    content.send_keys("Format this")
    content.send_keys([ :control, "a" ])
    find("summary[aria-label=Formatting]").send_keys(:enter)
    assert_selector ".n-chat-composer[data-formatting-open] lexxy-toolbar"
    find("lexxy-toolbar button[name=bold]").click
    assert_selector "lexxy-editor strong", text: "Format this"
    find("lexxy-editor .lexxy-editor__content").send_keys([ :control, "k" ])
    assert_selector "lexxy-link-dropdown [data-dropdown-panel]:not([hidden]) input[type=url]"
    find("lexxy-link-dropdown input[type=url]").send_keys(:escape)
    find("lexxy-editor .lexxy-editor__content").send_keys(:escape)
    assert_no_selector ".n-chat-composer[data-formatting-open]"
    assert_selector "summary[aria-label=Formatting]:focus"
  end

  test "keyboard Enter on the native Bold button formats without sending" do
    counts = [ Chat.count, Message.count ]
    content = find("lexxy-editor .lexxy-editor__content")
    content.send_keys("Keyboard bold", [ :control, "a" ])
    find("summary[aria-label=Formatting]").send_keys(:enter)
    assert_selector "lexxy-toolbar button[data-command=uploadFile]:focus"

    page.driver.browser.action.send_keys(:arrow_right).perform
    assert_selector "lexxy-toolbar button[name=bold]:focus"
    page.driver.browser.action.send_keys(:enter).perform

    assert_selector "lexxy-editor strong", text: "Keyboard bold"
    assert_current_path new_chat_path, ignore_query: true
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "keyboard Enter in the native link URL field inserts a link without sending" do
    counts = [ Chat.count, Message.count ]
    content = find("lexxy-editor .lexxy-editor__content")
    content.send_keys("Keyboard link", [ :control, "a" ], [ :control, "k" ])
    assert_selector "lexxy-link-dropdown [data-dropdown-panel]:not([hidden]) input[type=url]:focus"

    find("lexxy-link-dropdown input[type=url]").send_keys("https://keyboard-link.example/reference", :enter)

    assert_selector "lexxy-editor .lexxy-editor__content a[href='https://keyboard-link.example/reference']", text: "Keyboard link"
    assert_no_selector "lexxy-link-dropdown [data-dropdown-panel]:not([hidden])"
    assert_current_path new_chat_path, ignore_query: true
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "plain Enter in editable content still sends a real message" do
    counts = [ Chat.count, Message.count ]
    content = find("lexxy-editor .lexxy-editor__content")
    content.send_keys("Send from editable content")

    assert_enqueued_jobs 1, only: ChatResponseJob do
      content.send_keys(:enter)
      assert_selector "form[data-generation-busy=true] lexxy-editor[disabled]"
    end

    chat = @user.chats.order(:id).last
    assert_current_path chat_path(chat)
    assert_equal [ counts.first + 1, counts.last + 1 ], [ Chat.count, Message.count ]
    assert_equal "Send from editable content", chat.messages.user.last.content.strip
    assert_predicate chat, :generating?
  end

  test "modified Enter in editable content keeps editing without sending" do
    counts = [ Chat.count, Message.count ]
    content = find("lexxy-editor .lexxy-editor__content")
    content.send_keys("First line", [ :shift, :enter ], "Second line")
    assert_selector "lexxy-editor .lexxy-editor__content br", visible: :all
    assert_equal [ "First line", "Second line" ], content.text.lines.map(&:strip)

    [ :control, :meta ].each do |modifier|
      content.send_keys([ modifier, :enter ], "More text")
      assert_selector "lexxy-editor:not([disabled]) .lexxy-editor__content", text: "More text"
    end

    assert_current_path new_chat_path, ignore_query: true
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "palette arrow keys and Enter select a skill without sending" do
    counts = [ Chat.count, Message.count ]
    content = find("lexxy-editor .lexxy-editor__content")
    content.send_keys("/")
    assert_selector "[role=listbox] [role=option][aria-selected=true]", text: "/first-skill", visible: :all

    [ :arrow_down, :arrow_up ].each do |key|
      content.send_keys(key)
      assert_selector "[role=listbox] [role=option][aria-selected=true]", text: "/first-skill", visible: :all
    end
    content.send_keys(:enter)

    assert_selector "lexxy-editor .lexxy-editor__content", text: "/first-skill"
    assert_no_selector "[role=listbox]:not(.hidden)"
    assert_current_path new_chat_path, ignore_query: true
    assert_equal counts, [ Chat.count, Message.count ]
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "submission locks the compact actions and restores real formatting afterwards" do
    form = find("#chat-form")
    page.execute_script("arguments[0].dispatchEvent(new CustomEvent('turbo:submit-start', { bubbles: true }))", form)
    assert_selector "[data-chat-account-target=editingTools][inert][aria-disabled=true]"
    assert_button "Attach PDF", disabled: true, enable_aria_label: true
    assert_selector "lexxy-editor[inert][disabled]"
    page.execute_script("document.querySelector('[data-action=\"composer-chrome#upload\"]').click()")
    assert_no_selector "lexxy-editor input[type=file]", visible: :all
    page.execute_script("arguments[0].dispatchEvent(new CustomEvent('turbo:submit-end', { bubbles: true }))", form)
    assert_button "Attach PDF", disabled: false, enable_aria_label: true
    assert_no_selector "[data-chat-account-target=editingTools][inert]"
    find("summary[aria-label=Formatting]").send_keys(:enter)
    assert_selector ".n-chat-composer[data-formatting-open] lexxy-toolbar"
  end

  test "saved generation has a reachable Stop and returns to the same enabled composer" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    visit chat_url(chat)
    assert_selector "lexxy-editor[inert][disabled]"
    assert_selector "[data-chat-account-readonly]", text: /Research team/
    assert_button "Attach PDF", disabled: true, enable_aria_label: true
    counts = [ Chat.count, Message.count ]
    click_button "Stop generating", enable_aria_label: true
    assert_selector "button[aria-label=Send]:not([disabled])"
    assert_no_selector "button[aria-label='Stop generating']"
    assert_selector ".n-chat-composer lexxy-editor:not([inert]):not([disabled])"
    assert_equal counts, [ Chat.count, Message.count ]
    assert chat.reload.generation_stopped?
    assert_not chat.generating?
    assert_no_enqueued_jobs only: ChatResponseJob
  end

  test "the shared surface fits narrow screens with long account names in both themes" do
    @second.update!(name: "Research team with a deliberately long account name")
    [ false, true ].each do |dark|
      [ new_chat_url(account_id: @second.id), chat_url(chats(:picker_second_chat)) ].each do |url|
        visit url
        page.current_window.resize_to(375, 844)
        if page.evaluate_script("window.innerWidth") != 375
          page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 844, deviceScaleFactor: 1, mobile: false)
        end
        assert_equal 375, page.evaluate_script("window.innerWidth")
        set_theme(dark)
        assert_selector ".n-chat-composer"
        bounds = page.evaluate_script(<<~JS)
          (() => {
            const selectors = ['.n-composer-surface', '.n-composer-account', '.n-composer-send'];
            return selectors.map(selector => {
              const rect = document.querySelector(selector).getBoundingClientRect();
              return { left: rect.left, right: rect.right, width: rect.width, height: rect.height };
            });
          })()
        JS
        bounds.each do |rect|
          assert_operator rect.fetch("left"), :>=, 0
          assert_operator rect.fetch("right"), :<=, page.evaluate_script("window.innerWidth")
        end
        assert_operator bounds.last.fetch("width"), :>=, 40
        assert_operator bounds.last.fetch("height"), :>=, 40
        assert_no_selector "lexxy-editor lexxy-toolbar"
        assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.n-composer-editor')).boxShadow")
        assert_equal 0, page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.n-composer-editor')).borderTopWidth)")
      end
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1400)
  end

  [ 375, 640, 768, 820, 1024, 1400 ].each do |width|
    test "Tools stays contained and keyboard accessible at #{width}px in both themes" do
      @first.update!(name: "Research team with a deliberately long account name")
      @second.update!(name: "Research team with a deliberately long account name")
      mcp_servers(:picker_first_tool).update!(name: "Alpha research sources #{'with detailed document references ' * 16}")
      mcp_servers(:picker_second_tool).update!(name: "Zebra research sources #{'long-unbroken-reference-' * 24}")

      [ false, true ].each do |dark|
        [ user_root_url(account_id: @first.id), new_chat_url(account_id: @second.id) ].each do |url|
          visit url
          assert_selector "lexxy-editor[connected]"
          page.current_window.resize_to(width, 844)
          if page.evaluate_script("window.innerWidth") != width
            page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 844, deviceScaleFactor: 1, mobile: false)
          end
          assert_equal width, page.evaluate_script("window.innerWidth")
          set_theme(dark)
          assert_no_selector ".n-composer-tools-panel"

          find("[data-composer-tools] summary").send_keys(:enter)
          assert_selector "[data-composer-tools][open] summary:focus-visible"
          page.driver.browser.action.send_keys(:tab).perform
          assert_selector ".n-composer-tools-panel input:focus-visible"
          assert_tools_panel_geometry

          page.driver.browser.action.send_keys(:space).perform
          assert_selector ".n-composer-tools-panel input:checked:focus-visible"
          assert_selector "#mcp-selected-count", text: "1"
          find("[data-composer-tools] summary").send_keys(:enter)
          assert_no_selector ".n-composer-tools-panel"
        end
      end
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
      page.current_window.resize_to(1400, 1400)
    end
  end

  test "normal help and primary controls meet text contrast in both themes" do
    [ false, true ].each do |dark|
      set_theme(dark)
      ratios = page.evaluate_script(<<~JS)
        (() => {
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
          const context = canvas.getContext('2d', { willReadFrequently: true });
          const rgb = color => { context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1); return [...context.getImageData(0, 0, 1, 1).data].slice(0, 3); };
          const luminance = values => values.map(value => { const v = value / 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }).reduce((sum, value, i) => sum + value * [.2126, .7152, .0722][i], 0);
          const ratio = (a, b) => { const x = luminance(rgb(a)); const y = luminance(rgb(b)); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };
          const surface = getComputedStyle(document.querySelector('.n-composer-surface')).backgroundColor;
          const help = getComputedStyle(document.querySelector('.n-composer-meta'));
          const pageBackground = getComputedStyle(document.body).backgroundColor;
          const send = getComputedStyle(document.querySelector('.n-composer-send'));
          return { help: ratio(help.color, pageBackground), send: ratio(send.color, send.backgroundColor), control: ratio(getComputedStyle(document.querySelector('.n-composer-control')).color, surface) };
        })()
      JS
      ratios.each_value { |value| assert_operator value, :>=, 4.5 }
    end
  end

  test "reduced motion and hovering Send do not rotate the primary action" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    find("button[aria-label=Send]").hover
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.n-composer-send')).transform")
    assert_equal "0s", page.evaluate_script("getComputedStyle(document.querySelector('.n-composer-send')).transitionDuration")
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "tools remain account-specific and their panel fits a narrow viewport" do
    page.current_window.resize_to(375, 844)
    if page.evaluate_script("window.innerWidth") != 375
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 844, deviceScaleFactor: 1, mobile: false)
    end
    assert_equal 375, page.evaluate_script("window.innerWidth")
    find("[data-composer-tools] summary").send_keys(:enter)
    assert_selector "[data-composer-tools][open]"
    assert_text "First tool"
    assert_no_text "Second tool"
    find("input[name='mcp_server_ids[]']").check
    assert_selector "#mcp-selected-count", text: "1"
    rect = page.evaluate_script("(() => { const r = document.querySelector('.n-composer-tools-panel').getBoundingClientRect(); return [r.left, r.right, innerWidth]; })()")
    assert_operator rect[0], :>=, 0
    assert_operator rect[1], :<=, rect[2]
    find("[data-composer-tools] summary").send_keys(:escape)
    assert_no_selector "[data-composer-tools][open]"
    assert_selector "[data-composer-tools] summary:focus"
    find("lexxy-editor .lexxy-editor__content").send_keys("Tools question")
    assert_enqueued_jobs 1, only: ChatResponseJob do
      click_button "Send", enable_aria_label: true
      assert_selector "[data-chat-account-readonly]"
    end
    chat = @user.chats.order(:id).last
    assert_equal [ mcp_servers(:picker_first_tool).id ], chat.chat_mcp_sessions.pluck(:mcp_server_id)
    click_button "Stop generating", enable_aria_label: true
    assert_selector "button[aria-label=Send]:not([disabled])"
    assert_no_selector "button[aria-label='Stop generating']"
    assert_selector "form[data-generation-busy=false]"
    assert_selector "[data-chat-account-readonly]", text: "Account: #{@first.name}"
    find(".n-composer-tools-trigger").click
    assert_selector "#mcp-selector-modal:not(.hidden)", text: "First tool"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(1400, 1400)
  end

  test "skill selection retains priority over sending and pasted URLs keep chat context" do
    find("lexxy-editor .lexxy-editor__content").send_keys("/first")
    assert_selector ".n-skill-item-active", text: "/first-skill"
    count = @user.chats.count
    find("lexxy-editor .lexxy-editor__content").send_keys(:enter)
    assert_no_selector ".n-skill-menu:not(.hidden)"
    assert_includes page.evaluate_script("document.querySelector('lexxy-editor').value"), "/first-skill"
    assert_equal count, @user.chats.count
    assert_no_enqueued_jobs only: ChatResponseJob
    visit chat_url(chats(:picker_second_chat))
    assert_selector "lexxy-editor[connected]"
    page.execute_script("document.querySelector('lexxy-editor').dispatchEvent(new CustomEvent('lexxy:insert-link', { detail: { url: 'https://composer-saved.example/reference' }, bubbles: true }))")
    assert_selector "input[name='message[attached_website_ids][]']", count: 2, visible: :all
    assert @second.websites.exists?(url: "https://composer-saved.example/reference")
    assert_not @first.websites.exists?(url: "https://composer-saved.example/reference")
  end

  test "saved PDF action registers a real native upload in the stored account" do
    visit chat_url(chats(:picker_second_chat))
    assert_selector "lexxy-editor[connected]"
    with_pdf do |path|
      assert_enqueued_jobs 1, only: AddDocumentJob do
        attach_file(path) { click_button "Attach PDF", enable_aria_label: true }
        assert_selector "input[name='message[attached_document_ids][]']", count: 2, visible: :all
      end
      document = @second.documents.joins(file_attachment: :blob).find_by!(active_storage_blobs: { filename: File.basename(path) })
      assert_equal File.binread(path), document.file.download
      assert_not @first.documents.joins(file_attachment: :blob).exists?(active_storage_blobs: { filename: File.basename(path) })
    end
  end

  test "an unlock replacement keeps the same shared surface without a request session" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    visit chat_url(chat)
    assert_selector "button[aria-label='Stop generating']"
    Current.reset
    chat.finish_generation!
    # Visit verifies recovery if cable delivery is missed; the integration test captures the actual broadcast.
    visit chat_url(chat)
    assert_selector "turbo-frame##{dom_id(chat)}_message_form .n-chat-composer", count: 1
    assert_selector "button[aria-label=Send]:not([disabled])"
    assert_selector "[data-chat-account-readonly]", text: /Research team/
    assert_no_selector "form form"
  end

  private
    def assert_tools_panel_geometry
      layout = page.evaluate_script(<<~JS)
        (() => {
          const panel = document.querySelector('.n-composer-tools-panel');
          const bounds = panel.getBoundingClientRect();
          const focus = document.activeElement;
          const focusStyle = getComputedStyle(focus);
          const outline = parseFloat(focusStyle.outlineWidth) + Math.max(0, parseFloat(focusStyle.outlineOffset));
          const rect = focus.getBoundingClientRect();
          const box = element => {
            const { left, right, width, height } = element.getBoundingClientRect();
            return { left, right, width, height };
          };
          return {
            panel: box(panel), surface: box(document.querySelector('.n-composer-surface')),
            trigger: box(document.querySelector('[data-composer-tools] summary')), focus: box(focus),
            viewportWidth: window.innerWidth, overflowY: getComputedStyle(panel).overflowY,
            horizontalOverflow: panel.scrollWidth - panel.clientWidth,
            verticalOverflow: panel.scrollHeight - panel.clientHeight,
            outlineWidth: parseFloat(focusStyle.outlineWidth),
            focusFits: rect.left - outline >= bounds.left + panel.clientLeft && rect.right + outline <= bounds.left + panel.clientLeft + panel.clientWidth && rect.top - outline >= bounds.top + panel.clientTop && rect.bottom + outline <= bounds.top + panel.clientTop + panel.clientHeight,
            focusInViewport: rect.left - outline >= 0 && rect.right + outline <= window.innerWidth && rect.top - outline >= 0 && rect.bottom + outline <= window.innerHeight,
            labels: Array.from(panel.querySelectorAll('.n-composer-tool-option span'), label => {
              const range = document.createRange();
              range.selectNodeContents(label);
              const lines = Array.from(range.getClientRects());
              return { lines: lines.length, fits: label.scrollWidth <= label.clientWidth && label.scrollHeight <= label.clientHeight && lines.every(line => line.left >= bounds.left + panel.clientLeft && line.right <= bounds.left + panel.clientLeft + panel.clientWidth) };
            })
          };
        })()
      JS
      assert_operator layout.fetch("panel").fetch("left"), :>=, layout.fetch("surface").fetch("left")
      assert_operator layout.fetch("panel").fetch("right"), :<=, layout.fetch("surface").fetch("right")
      assert_operator layout.fetch("panel").fetch("left"), :>=, 0
      assert_operator layout.fetch("panel").fetch("right"), :<=, layout.fetch("viewportWidth")
      assert_equal 0, layout.fetch("horizontalOverflow")
      assert_operator layout.fetch("verticalOverflow"), :>, 0
      assert_includes [ "auto", "scroll" ], layout.fetch("overflowY")
      assert_operator layout.fetch("trigger").fetch("width"), :>=, 40
      assert_operator layout.fetch("trigger").fetch("height"), :>=, 36
      assert_operator layout.fetch("focus").fetch("width"), :>, 0
      assert_operator layout.fetch("focus").fetch("height"), :>, 0
      assert_operator layout.fetch("outlineWidth"), :>, 0
      assert layout.fetch("focusFits"), "The focused checkbox and its outline must fit inside the menu scrollport"
      assert layout.fetch("focusInViewport"), "The focused checkbox and its outline must remain in the viewport"
      layout.fetch("labels").each do |label|
        assert_operator label.fetch("lines"), :>, 1
        assert label.fetch("fits"), "The complete tool name must wrap without horizontal clipping"
      end
    end

    def set_theme(dark)
      page.evaluate_async_script(<<~JS, dark)
        const done = arguments[arguments.length - 1];
        document.documentElement.classList.toggle('dark', arguments[0]);
        getComputedStyle(document.body).backgroundColor;
        const transitions = document.getAnimations().filter(animation => animation instanceof CSSTransition);
        Promise.all(transitions.map(animation => animation.finished.catch(() => {}))).then(done);
      JS
    end

    def with_pdf
      stream = "BT /F1 12 Tf 40 100 Td (Composer PDF) Tj ET\n"
      objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Length #{stream.bytesize} >>\nstream\n#{stream}endstream"
      ]
      pdf = +"%PDF-1.4\n"
      offsets = objects.each_with_index.map do |object, index|
        offset = pdf.bytesize
        pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
        offset
      end
      start = pdf.bytesize
      pdf << "xref\n0 6\n0000000000 65535 f \n"
      offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
      pdf << "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n#{start}\n%%EOF\n"
      Tempfile.create([ "composer-ui", ".pdf" ]) do |file|
        file.binmode
        file.write(pdf)
        file.flush
        yield file.path
      end
    end
end
