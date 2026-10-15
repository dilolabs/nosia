require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountAccessTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup { sign_in_picker_user }

  test "unowned and revoked chats reject every conversation web operation" do
    own = chats(:picker_second_chat)
    foreign = chats(:picker_foreign_chat)
    sessions = {
      own => own.chat_mcp_sessions.create!(mcp_server: mcp_servers(:picker_second_tool)),
      foreign => foreign.chat_mcp_sessions.create!(mcp_server: mcp_servers(:picker_foreign_tool))
    }
    @user.account_users.find_by!(account: @second).destroy!

    sessions.each do |chat, session|
      requests = [
        [ :get, chat_url(chat), {} ],
        [ :post, stop_chat_url(chat), {} ],
        [ :delete, chat_url(chat), {} ],
        [ :post, chat_messages_url(chat), { message: { content: "Denied" } } ],
        [ :post, chat_sources_url, { chat_id: chat.id, url: "https://denied.example" } ],
        [ :post, chat_mcp_sessions_url(chat), { mcp_server_id: mcp_servers(:picker_second_tool).id } ],
        [ :delete, chat_mcp_session_url(chat, session), {} ]
      ]

      requests.each do |verb, url, values|
        counts = [ Chat.count, Message.count, Website.count, ChatMcpSession.count ]

        assert_no_enqueued_jobs only: ChatResponseJob do
          public_send(verb, url, params: values)
        end

        assert_response :not_found
        assert_equal counts, [ Chat.count, Message.count, Website.count, ChatMcpSession.count ]
        assert chat.chat_mcp_sessions.exists?(session.id)
      end
    end
  end

  test "no-account users cannot create chats or sources" do
    delete logout_url
    sign_in_picker_user(users(:picker_no_account))
    requests = [
      [ chats_url, { chat: { prompt: "No account", model: "picker-test-model" } } ],
      [ chat_sources_url, { url: "https://no-account.example" } ],
      [ sources_documents_url, { document: { title: "No account" } } ]
    ]

    requests.each do |url, values|
      post url, params: values, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body.fetch("error"), "access to an account"
    end
  end
end
