require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountToolsTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup { sign_in_picker_user }

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

  test "removing a saved tool renders its own actions" do
    chat = chats(:picker_second_chat)
    tool = mcp_servers(:picker_second_tool)
    session = chat.chat_mcp_sessions.create!(mcp_server: tool)

    delete chat_mcp_session_url(chat, session), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=?]", "mcp_server_#{tool.id}_actions"
    assert_not chat.chat_mcp_sessions.exists?(session.id)
  end
end
