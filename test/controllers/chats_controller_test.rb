require "test_helper"
require "active_job/test_helper"
require_relative "../support/mcp_oauth_fixtures"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionView::RecordIdentifier

  def setup
    @user = User.create!(email: "cc@example.com", password: "testpassword123")
    @account = Account.create!(name: "CC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "create stamps attached source ids on the user message" do
    w = @account.websites.create!(url: "https://c.example", index_status: :indexed)
    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { prompt: "<p>hello</p>", model: "test-model", attached_website_ids: [ w.id ] } }
    end
    message = Chat.last.messages.where(role: :user).last
    assert_equal [ w.id.to_s ], message.attached_website_ids
    assert_equal "hello", message.content.strip # HTML converted to markdown

    @chat = Chat.last
  end

  # The composer renders a stop button while generating. Stop raises the
  # stopped_at flag the streaming loop checks between chunks and unlocks the
  # composer; partial output received so far is kept.
  test "stop flags cancellation, clears generating and redirects back to the chat" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    chat.start_generation!

    post stop_chat_url(chat)

    assert_redirected_to chat_path(chat)
    reloaded = chat.reload
    assert_not reloaded.generating
    assert_predicate reloaded, :generation_stopped?
  end

  # A TYPED url (Lexxy emits lexxy:insert-link only on paste) still becomes a
  # crawled Website source: the server extracts it from the message content.
  test "create turns a typed url in the prompt into a crawled Website source" do
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      assert_enqueued_with(job: ChatResponseJob) do
        post chats_url, params: { chat: { prompt: "<p>https://typed.example/page</p>", model: "test-model" } }
      end
    end

    website = @account.websites.find_by!(url: "https://typed.example/page")
    assert website.pending?
    message = Chat.last.messages.where(role: :user).last
    assert_includes message.attached_website_ids, website.id.to_s
  end

  test "create sets generating before enqueuing the job" do
    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { prompt: "<p>hello</p>", model: "test-model" } }
    end
    assert Chat.last.reload.generating, "create should set generating before enqueuing"
  end

  # A mid-stream refresh must not lose the response. ruby_llm persists the
  # assistant message blank (content: "") for the whole stream, so it is excluded
  # from `for_user` and never re-rendered — leaving streamed deltas and the final
  # broadcast_updated aiming at DOM nodes that don't exist. Reconstruct the bubble
  # from the `generating` flag so those broadcasts have live targets.
  test "show renders the in-progress assistant bubble while generating" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    chat.messages.create!(role: :user, content: "hi")
    assistant = chat.messages.create!(role: :assistant, content: "")
    chat.update_column(:generating, true)

    get chat_url(chat)
    assert_response :success

    assert_select "##{dom_id(assistant, :content)}", { count: 1 },
      "streamed deltas target dom_id(message, :content); it must exist on a mid-stream reload"
    assert_select "##{dom_id(assistant, :messages)}", { count: 1 },
      "the final broadcast_updated targets the bubble; it must exist on a mid-stream reload"
    assert_select "#thinking_animation", { count: 0 },
      "no standalone thinking animation once the assistant bubble exists (broadcast_created already removed it)"
  end

  # Before the assistant message exists (retrieval phases), the standalone thinking
  # animation must render so phase updates land and broadcast_created can remove it.
  test "show renders standalone thinking animation while generating before the assistant bubble exists" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    chat.messages.create!(role: :user, content: "hi")
    chat.update_column(:generating, true)

    get chat_url(chat)
    assert_response :success
    assert_select "#thinking_animation", count: 1
  end

  # A finished (or errored) chat clears `generating`, so no spinner should linger.
  test "show does not render a thinking animation when not generating" do
    chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    chat.messages.create!(role: :user, content: "hi")

    get chat_url(chat)
    assert_response :success
    assert_select "#thinking_animation", count: 0
  end
end

class ChatMcpOauthSelectionTest < ActionDispatch::IntegrationTest
  include McpOauthFixtures
  include ActiveJob::TestHelper
  include ActionView::RecordIdentifier

  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    @server.update!(auth_mode: "oauth", status: "error")
    @static = oauth_fixture("mcp_servers", :oauth_team_duplicate)
    @static.update!(status: "ready")
    @chat = @team.chats.create!(user: @alice, model: ENV.fetch("LLM_MODEL"), provider: :openai, assume_model_exists: true)
    post login_url, params: { email: @alice.email, password: "fixture-password" }
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "new and saved adds reject grants belonging to the wrong owner or account without a partial write" do
    @wire.install(self) do
      @wire.authorize(@server.begin_oauth_grant_for!(@bob))
      foreign = oauth_fixture("mcp_servers", :oauth_other)
      foreign.update!(auth_mode: "oauth")
      @wire.authorize(foreign.begin_oauth_grant_for!(@alice))

      assert_no_mcp_requests do
        [ @server, foreign ].each do |ineligible|
          assert_no_difference([ "Chat.count", "ChatMcpSession.count" ]) do
            post chats_url, params: { chat: { account_id: @team.id, prompt: "Hello" }, mcp_server_ids: [ @static.id, ineligible.id ] }
            assert_response :not_found

            post chat_mcp_sessions_url(@chat), params: { mcp_server_id: ineligible.id }, as: :turbo_stream
            assert_response :not_found
          end
        end
      end
    end
  end

  test "eligible OAuth is selectable with no shared readiness and a preserved revoked link is removable" do
    @wire.install(self) do
      grant = @server.begin_oauth_grant_for!(@alice)
      @wire.authorize(grant)
      @chat.chat_mcp_sessions.create!(mcp_server: @static)

      assert_no_mcp_requests do
        get new_chat_url(account_id: @team.id)
        assert_response :success
        assert_select "input[type=checkbox][value=?]", @server.id
        assert_select "#mcp-selected-count", text: "0"

        assert_enqueued_with(job: ChatResponseJob) do
          post chats_url, params: { chat: { account_id: @team.id, prompt: "Hello" }, mcp_server_ids: [ @server.id ] }
        end
        created = @alice.chats.find_by!(id: URI(response.location).path.split("/").last)
        assert_equal @team, created.account
        assert_equal [ @server.id ], created.chat_mcp_sessions.pluck(:mcp_server_id)

        post chat_mcp_sessions_url(@chat), params: { mcp_server_id: @server.id }, as: :turbo_stream
        assert_response :success
        assert_select "turbo-stream[target=mcp-selected-count] template", text: "2"
        get chat_url(@chat)
        assert_select "#mcp-selected-count", text: "2"
      end

      grant.retire!
      assert_no_mcp_requests do
        link = @chat.chat_mcp_sessions.find_by!(mcp_server: @server)
        get chat_url(@chat)
        assert_select "#mcp-selected-count", text: "1"
        assert_select "input[type=checkbox][value=?]", @server.id, count: 0
        assert_select "button[form=?]", dom_id(@server, :chat_mcp_form), text: /Remove/

        delete chat_mcp_session_url(@chat, link), as: :turbo_stream
        assert_response :success
        assert_select "turbo-stream[target=mcp-selected-count] template", text: "1"
        assert_not @chat.chat_mcp_sessions.exists?(link.id)
      end
    end
  end

  test "Turbo updates the other saved controls when an authorization changes after the page was loaded" do
    @wire.install(self) do
      grant = @server.begin_oauth_grant_for!(@alice)
      @wire.authorize(grant)
      link = @chat.chat_mcp_sessions.create!(mcp_server: @server)
      get chat_url(@chat)
      assert_select "input[value=?][checked]", @server.id

      grant.retire!
      assert_no_mcp_requests do
        post chat_mcp_sessions_url(@chat), params: { mcp_server_id: @static.id }, as: :turbo_stream
        assert_response :success
        assert_select "turbo-stream[target=chat-mcp-selector] template #chat-mcp-unavailable button", text: "Remove"
        assert_select "turbo-stream[target=mcp-selected-count] template", text: "1"
        assert_select "template input[type=checkbox][value=?]", @server.id, count: 0

        delete chat_mcp_session_url(@chat, link)
        assert_redirected_to chat_url(@chat)
        follow_redirect!
        assert_select "#mcp-selected-count", text: "1"
        assert_select "#chat-mcp-unavailable", count: 0
      end
    end
  end

  private
    def assert_no_mcp_requests
      before = [ @wire.requests.size, @wire.oauth_requests.size ]
      yield
      assert_equal before, [ @wire.requests.size, @wire.oauth_requests.size ]
    end
end
