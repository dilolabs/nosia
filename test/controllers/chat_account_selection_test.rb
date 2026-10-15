require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountSelectionTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup { sign_in_picker_user }

  test "new chat rejects an explicit account outside memberships" do
    get new_chat_url, params: { account_id: @foreign.id }
    assert_response :not_found

    get user_root_url, params: { account_id: @foreign.id }
    assert_response :not_found
  end

  test "create uses the second account without changing the default" do
    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { account_id: @second.id,
        prompt: "Research question", model: "picker-test-model" } }
    end

    chat = @user.chats.order(:id).last
    assert_redirected_to chat_url(chat)
    assert_equal @second.id, chat.account_id
    assert_equal @first, @user.first_account
  end

  test "missing and blank account context preserve the first account" do
    [ {}, { account_id: "" } ].each do |selection|
      post chats_url, params: { chat: selection.merge(prompt: "Default question",
        model: "picker-test-model") }
      assert_equal @first.id, @user.chats.order(:id).last.account_id
    end
  end

  test "invalid selection creates no chat message or generation job" do
    before_counts = [ Chat.count, Message.count, ChatMcpSession.count ]

    assert_no_enqueued_jobs only: ChatResponseJob do
      post chats_url, params: { chat: { account_id: @foreign.id,
        prompt: "Forbidden", model: "picker-test-model" } }
    end

    assert_response :not_found
    assert_equal before_counts, [ Chat.count, Message.count, ChatMcpSession.count ]
  end

  test "owned chat in the second account remains accessible" do
    get chat_url(chats(:picker_second_chat))

    assert_response :success
  end

  test "chat actions require ownership even with account membership" do
    chat = chats(:picker_second_chat)
    chat.update!(user: users(:picker_outsider))
    chat.start_generation!

    get chat_url(chat)
    assert_response :not_found

    delete chat_url(chat)
    assert_response :not_found

    post stop_chat_url(chat)
    assert_response :not_found
    assert_predicate chat.reload, :generating?
  end

  test "chat actions reject a revoked account membership" do
    chat = chats(:picker_second_chat)
    chat.start_generation!
    @user.account_users.find_by!(account: @second).destroy!

    get chat_url(chat)
    assert_response :not_found

    delete chat_url(chat)
    assert_response :not_found

    post stop_chat_url(chat)
    assert_response :not_found
    assert_predicate chat.reload, :generating?
  end

  test "create without account access returns a plain unprocessable response" do
    sign_in_picker_user(users(:picker_no_account))
    before_counts = [ Chat.count, Message.count, ChatMcpSession.count ]

    assert_no_enqueued_jobs only: ChatResponseJob do
      post chats_url, params: { chat: { prompt: "No account", model: "picker-test-model" } }
    end

    assert_response :unprocessable_entity
    assert_equal "You need access to an account to start a chat.", response.body
    assert_equal before_counts, [ Chat.count, Message.count, ChatMcpSession.count ]
  end

  test "create without account access returns a JSON unprocessable response" do
    sign_in_picker_user(users(:picker_no_account))
    before_counts = [ Chat.count, Message.count, ChatMcpSession.count ]

    assert_no_enqueued_jobs only: ChatResponseJob do
      post chats_url, params: { chat: { prompt: "No account", model: "picker-test-model" } }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal({ "error" => "You need access to an account to start a chat." }, response.parsed_body)
    assert_equal before_counts, [ Chat.count, Message.count, ChatMcpSession.count ]
  end
end
