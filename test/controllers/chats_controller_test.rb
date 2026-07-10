require "test_helper"
require "active_job/test_helper"

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
