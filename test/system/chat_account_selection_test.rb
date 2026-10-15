require "application_system_test_case"
require_relative "../support/chat_account_fixtures"

class ChatAccountSelectionSystemTest < ApplicationSystemTestCase
  include ChatAccountFixtures

  setup do
    visit root_url
    fill_in "email", with: @user.email
    fill_in "password", with: ChatAccountFixtures::PASSWORD
    click_on "Sign in"
    assert_selector "select[name='chat[account_id]']"
  end

  test "empty switching refreshes account options on both entry points" do
    [ user_root_url(model: "picker-test-model"), new_chat_url(model: "picker-test-model") ].each do |url|
      visit url
      select "Research team", from: "Account"

      assert_selector "select option[selected][value='#{@second.id}']"
      assert_selector "#chat-form input[type=checkbox][value='#{mcp_servers(:picker_second_tool).id}']", visible: :all
      assert_equal [ "second-skill" ], browser_skills
      assert_selector "#chat-form input[name='chat[model]'][value='picker-test-model']", visible: :all
      assert_equal({ "model" => "picker-test-model", "account_id" => @second.id.to_s }, URI.decode_www_form(URI.parse(current_url).query).to_h)
    end
  end

  test "cancel preserves the draft and confirm resets it without moving saved sources" do
    write_draft("Keep this draft")

    dismiss_confirm(/clears your unsent message/) { select "Research team", from: "Account" }

    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
    assert_includes draft_html, "Keep this draft"

    accept_confirm(/clears your unsent message/) { select "Research team", from: "Account" }

    assert_selector "select option[selected][value='#{@second.id}']"
    assert_equal @second.id.to_s, find("select[name='chat[account_id]']").value
    assert_not_includes draft_html, "Keep this draft"
    assert_equal @first.id, websites(:picker_first_website).reload.account_id
  end

  test "Turbo history does not restore unsent text references or tool choices" do
    write_draft("Do not cache this draft")
    find("summary", text: /MCP Tools/).click
    check "First tool"
    page.execute_script(<<~JS, websites(:picker_first_website).id.to_s)
      document.querySelector('[data-composer-sources-target="websiteIds"]').value = arguments[0]
      document.querySelector('[data-composer-sources-target="documentIds"]').value = "draft-document"
      const hiddenTool = document.createElement("input")
      hiddenTool.type = "hidden"
      hiddenTool.name = "mcp_server_ids[]"
      hiddenTool.value = "draft-tool"
      document.querySelector("#mcp-server-hidden-fields").append(hiddenTool)
    JS

    click_link "New Chat"
    assert_current_path new_chat_path
    page.go_back

    assert_current_path user_root_path
    assert_selector "lexxy-editor .lexxy-editor__content"
    assert_not_includes draft_html, "Do not cache this draft"
    assert_no_selector "input[name='mcp_server_ids[]']:checked", visible: :all
    assert_no_selector "#mcp-server-hidden-fields input", visible: :all
    assert_selector "#mcp-selected-count", text: "0", visible: :all
    assert_equal "", find("[data-composer-sources-target='websiteIds']", visible: :all).value
    assert_equal "", find("[data-composer-sources-target='documentIds']", visible: :all).value
    assert_equal @first.id.to_s, find("select[name='chat[account_id]']").value
  end

  private
    def write_draft(text)
      assert_selector "lexxy-editor .lexxy-editor__content"
      editor = find("lexxy-editor")
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new CustomEvent('lexxy:change', { bubbles: true }))", editor, "<p>#{text}</p>")
    end

    def draft_html
      page.evaluate_script("document.querySelector('lexxy-editor').value")
    end

    def browser_skills
      page.evaluate_script("JSON.parse(document.querySelector('[data-composer-skills-value]').dataset.composerSkillsValue).map(skill => skill.name)")
    end
end
