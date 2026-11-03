require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountToolsTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures
  include ActionView::RecordIdentifier

  setup { sign_in_picker_user }

  test "saved chat uses the composer checkbox dropdown with its persisted selection" do
    chat = chats(:picker_second_chat)
    tool = mcp_servers(:picker_second_tool)
    session = chat.chat_mcp_sessions.create!(mcp_server: tool)

    get chat_url(chat)

    assert_response :success
    assert_select "details[data-composer-tools]" do
      assert_select "summary.n-composer-control", text: /Tools\s+1/
      assert_select ".n-composer-tools-heading", text: "Connected tools"
      assert_select "label.n-composer-tool-option" do
        assert_select "input[type=checkbox][checked][form=?]", dom_id(tool, :chat_mcp_form)
        assert_select "span", text: "Second tool"
      end
      assert_select "input[value=?]", mcp_servers(:picker_first_tool).id, count: 0
    end
    assert_select "form[id=?][action=?]", dom_id(tool, :chat_mcp_form), chat_mcp_session_path(chat, session) do
      assert_select "input[name=_method][value=delete]"
    end
    assert_select "dialog#mcp-selector-modal", count: 0
    assert_select "form form", count: 0
  end

  test "saved chat keeps an account-specific empty tools dropdown" do
    @second.mcp_servers.update_all(enabled: false)

    get chat_url(chats(:picker_second_chat))

    assert_select "details[data-composer-tools]" do
      assert_select "summary", text: /Tools\s+0/
      assert_select "a[href=?]", account_mcp_servers_path(@second)
      assert_select "input[type=checkbox]", count: 0
    end
  end

  test "saved chat accepts only its own tools" do
    chat = chats(:picker_second_chat)
    tool = mcp_servers(:picker_second_tool)

    post chat_mcp_sessions_url(chat), params: { mcp_server_id: tool.id }
    assert_response :redirect
    session = chat.chat_mcp_sessions.find_by!(mcp_server: tool)

    delete chat_mcp_session_url(chat, session)
    assert_response :redirect
    assert_not chat.chat_mcp_sessions.exists?(session.id)

    assert_no_difference "ChatMcpSession.count" do
      post chat_mcp_sessions_url(chat), params: { mcp_server_id: mcp_servers(:picker_first_tool).id }
    end
    assert_response :not_found
  end

  test "missing or blank tool references fail closed" do
    chat = chats(:picker_second_chat)

    [ nil, "", " " ].each do |id|
      assert_no_difference "ChatMcpSession.count" do
        post chat_mcp_sessions_url(chat), params: { mcp_server_id: id }
      end
      assert_response :not_found
    end
  end

  test "adding a saved tool updates its checkbox form and server-confirmed count" do
    chat = chats(:picker_second_chat)
    tool = mcp_servers(:picker_second_tool)

    post chat_mcp_sessions_url(chat), params: { mcp_server_id: tool.id }, as: :turbo_stream

    assert_response :success
    session = chat.chat_mcp_sessions.find_by!(mcp_server: tool)
    assert_select "turbo-stream[action=replace][method=morph][target=?]", dom_id(tool, :chat_mcp_option) do
      assert_select "template input[type=checkbox][checked]"
    end
    assert_select "turbo-stream[target=?] template form[action=?]", dom_id(tool, :chat_mcp_form), chat_mcp_session_path(chat, session)
    assert_select "turbo-stream[action=update][target=mcp-selected-count] template", text: "1"
  end

  test "removing a saved tool updates its checkbox form and server-confirmed count" do
    chat = chats(:picker_second_chat)
    tool = mcp_servers(:picker_second_tool)
    session = chat.chat_mcp_sessions.create!(mcp_server: tool)

    delete chat_mcp_session_url(chat, session), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][method=morph][target=?]", dom_id(tool, :chat_mcp_option) do
      assert_select "template input[type=checkbox]:not([checked])"
    end
    assert_select "turbo-stream[target=?] template form[action=?]", dom_id(tool, :chat_mcp_form), chat_mcp_sessions_path(chat, mcp_server_id: tool.id)
    assert_select "turbo-stream[action=update][target=mcp-selected-count] template", text: "0"
    assert_not chat.chat_mcp_sessions.exists?(session.id)
  end
end
