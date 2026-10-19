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

  private
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
