require "test_helper"
require_relative "../support/chat_account_fixtures"

class ChatAccountSelectionTest < ActionDispatch::IntegrationTest
  include ChatAccountFixtures

  setup { sign_in_picker_user }

  test "both new-chat entry points show membership-only selected-account controls" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { account_id: @second.id, model: "picker-test-model" }

      assert_response :success
      assert_select "select[name='chat[account_id]'] option", count: 2
      assert_select "select[name='chat[account_id]'] option[selected][value='#{@second.id}']"
      assert_select "select[name='chat[account_id]'] option[value='#{@foreign.id}']", count: 0
      assert_select "#chat-form input[type=hidden][name='chat[model]'][value='picker-test-model']"
      assert_select "#chat-form input[type=checkbox][name='mcp_server_ids[]']", count: 1
      assert_select "#chat-form input[type=checkbox][value='#{mcp_servers(:picker_second_tool).id}']"
      assert_select "#chat-form [data-composer-skills-value]" do |nodes|
        assert_equal [ "second-skill" ], JSON.parse(nodes.first["data-composer-skills-value"]).map { |skill| skill.fetch("name") }
      end
    end
  end

  test "both new-chat entry points default to the first account and preserve the model" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { model: "picker-test-model" }

      assert_response :success
      assert_select "select[name='chat[account_id]'] option[selected][value='#{@first.id}']"
      assert_select "#chat-form input[type=hidden][name='chat[model]'][value='picker-test-model']"
    end
  end

  test "new-chat composers expose explicit account and source lifecycle context" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { account_id: @second.id }

      assert_response :success
      assert_select "[data-controller~=chat-account][data-chat-account-account-id-value='#{@second.id}']" do |roots|
        assert_includes roots.first["data-action"], "turbo:before-cache@document->chat-account#beforeCache:capture"
      end
      assert_select "#chat-form[data-chat-account-target=form][data-generation-busy=false]" do |forms|
        assert_equal "submit->chat-account#guard submit->mcp-fields-sync#copy", forms.first["data-action"]
      end
      assert_select "[data-controller~=composer-sources][data-composer-sources-account-id-value='#{@second.id}'][data-composer-sources-chat-id-value='']"
      assert_select "lexxy-editor[data-composer-target=editor][data-composer-sources-target=editor]"
      assert_select "input[data-composer-sources-target=websiteIds]"
      assert_select "input[data-composer-sources-target=documentIds]"
      assert_select "ul[hidden][role=alert][data-composer-sources-target=errors]"
      assert_select "button[type=submit][aria-label=Send][data-chat-account-target=send]"
      if url == user_root_url
        assert_select "[data-controller~=dropzone][data-dropzone-account-id-value='#{@second.id}'][data-action='chat-account:reset@window->dropzone#resetChatDraft']"
      end
    end
  end

  test "saved chat shows a read-only account and its own MCP options" do
    chat = chats(:picker_second_chat)
    chat.chat_mcp_sessions.create!(mcp_server: mcp_servers(:picker_second_tool))

    get chat_url(chat)

    assert_response :success
    assert_select "[data-chat-account-readonly]", text: /Research team/
    assert_select "select[name='chat[account_id]']", count: 0
    assert_select "#mcp-selector-modal", text: /Second tool/
    assert_select "#mcp-selector-modal", text: /First tool/, count: 0
    assert_select "button", text: /MCP \(1\)/
    assert_select "[data-controller~=chat-reconnect][data-controller~=chat-account][data-chat-account-account-id-value='#{@second.id}']"
    assert_select "[data-controller~=composer-sources][data-composer-sources-account-id-value='#{@second.id}'][data-composer-sources-chat-id-value='#{chat.id}']"
    assert_select "form[data-chat-account-target=form][data-generation-busy=false][data-action='submit->chat-account#guard']"
    assert_select "lexxy-editor[data-composer-target=editor][data-composer-sources-target=editor]"
    assert_select "input[data-composer-sources-target=websiteIds]"
    assert_select "input[data-composer-sources-target=documentIds]"
    assert_select "ul[hidden][role=alert][data-composer-sources-target=errors]"
    assert_select "button[type=submit][aria-label=Send][data-chat-account-target=send]"
    assert_select "[data-composer-skills-value]" do |nodes|
      assert_equal [ "second-skill" ], JSON.parse(nodes.first["data-composer-skills-value"]).map { |skill| skill.fetch("name") }
    end
  end

  test "saved generating chat retains its busy composer state" do
    chat = chats(:picker_second_chat)
    chat.start_generation!

    get chat_url(chat)

    assert_response :success
    assert_select "[data-controller~=chat-reconnect][data-chat-reconnect-generating-value=true]"
    assert_select "form[data-chat-account-target=form][data-generation-busy=true]"
    assert_select "button[type=submit][aria-label=Send][data-chat-account-target=send][disabled]"
    assert_select "[data-chat-account-readonly]", text: /Research team/
  end

  test "new chat rejects an explicit account outside memberships" do
    get new_chat_url, params: { account_id: @foreign.id }
    assert_response :not_found

    get user_root_url, params: { account_id: @foreign.id }
    assert_response :not_found
  end

  test "new chat rejects array account context instead of finding multiple accounts" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { account_id: [ @second.id ] }

      assert_response :not_found
    end
  end

  test "string numeric and blank account contexts preserve new-chat selection" do
    { @second.id => @second, @second.id.to_s => @second, nil => @first, "" => @first }.each do |account_id, account|
      [ user_root_url, new_chat_url ].each do |url|
        get url, params: { account_id: account_id }, as: :json, headers: { "Accept" => "text/html" }

        assert_response :success
        assert_select "select[name='chat[account_id]'] option[selected][value='#{account.id}']"
      end
    end
  end

  test "new chat rejects hash account context" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { account_id: { id: @second.id } }

      assert_response :not_found
    end
  end

  test "empty array account context never falls back to the first account" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { account_id: [] }, as: :json, headers: { "Accept" => "text/html" }

      assert_response :not_found
    end
  end

  test "empty hash account context never falls back to the first account" do
    [ user_root_url, new_chat_url ].each do |url|
      get url, params: { account_id: {} }, as: :json, headers: { "Accept" => "text/html" }

      assert_response :not_found
    end
  end

  test "malformed explicit account context cannot create a default chat" do
    [ [ @second.id ], { id: @second.id }, [], {} ].each do |account_id|
      counts = [ Chat.count, Message.count, ChatMcpSession.count ]

      assert_no_enqueued_jobs only: ChatResponseJob do
        post chats_url, params: { chat: { account_id: account_id,
          prompt: "Malformed selection", model: "picker-test-model" } }, as: :json
      end

      assert_response :not_found
      assert_equal counts, [ Chat.count, Message.count, ChatMcpSession.count ]
    end
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

  test "wrong-account references fail before any chat message or tool linkage" do
    invalid_options = [
      { chat: { attached_website_ids: [ websites(:picker_first_website).id ] } },
      { mcp_server_ids: [ mcp_servers(:picker_first_tool).id ] }
    ]

    invalid_options.each do |options|
      chat_params = { account_id: @second.id, prompt: "Invalid references", model: "picker-test-model" }
      chat_params.merge!(options.fetch(:chat, {}))
      counts = [ Chat.count, Message.count, ChatMcpSession.count ]

      assert_no_enqueued_jobs only: ChatResponseJob do
        post chats_url, params: options.except(:chat).merge(chat: chat_params)
      end

      assert_response :not_found
      assert_equal counts, [ Chat.count, Message.count, ChatMcpSession.count ]
    end
  end

  test "wrong-account documents fail before any chat message or tool linkage" do
    document = @first.documents.create!(title: "First account reference", file: {
      io: StringIO.new("Reference"), filename: "reference.txt", content_type: "text/plain"
    })
    counts = [ Chat.count, Message.count, ChatMcpSession.count ]

    assert_no_enqueued_jobs only: ChatResponseJob do
      post chats_url, params: { chat: { account_id: @second.id,
        prompt: "Invalid document", model: "picker-test-model", attached_document_ids: [ document.id ] } }
    end

    assert_response :not_found
    assert_equal counts, [ Chat.count, Message.count, ChatMcpSession.count ]
  end

  test "missing references fail before any chat message or tool linkage" do
    invalid_options = [
      { chat: { attached_website_ids: [ websites(:picker_second_website).id, "missing" ] } },
      { chat: { attached_document_ids: [ "missing" ] } },
      { mcp_server_ids: [ mcp_servers(:picker_second_tool).id, "missing" ] }
    ]

    invalid_options.each do |options|
      chat_params = { account_id: @second.id, prompt: "Missing references", model: "picker-test-model" }
      chat_params.merge!(options.fetch(:chat, {}))
      counts = [ Chat.count, Message.count, ChatMcpSession.count ]

      assert_no_enqueued_jobs only: ChatResponseJob do
        post chats_url, params: options.except(:chat).merge(chat: chat_params)
      end

      assert_response :not_found
      assert_equal counts, [ Chat.count, Message.count, ChatMcpSession.count ]
    end
  end

  test "create uses normalized sources and tools from the selected account" do
    website_id = websites(:picker_second_website).id
    tool_id = mcp_servers(:picker_second_tool).id

    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { account_id: @second.id,
        prompt: "Valid references", model: "picker-test-model",
        attached_website_ids: [ "", website_id, website_id ] }, mcp_server_ids: [ "", tool_id, tool_id ] }
    end

    chat = @user.chats.order(:id).last
    assert_redirected_to chat_url(chat)
    assert_equal @second.id, chat.account_id
    assert_equal [ website_id.to_s ], chat.messages.user.last.attached_website_ids
    assert_equal [ tool_id ], chat.chat_mcp_sessions.pluck(:mcp_server_id)
    assert_predicate chat, :generating?
    assert_equal @first, @user.first_account
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
