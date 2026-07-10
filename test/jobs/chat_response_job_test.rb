require "test_helper"
require "turbo/broadcastable/test_helper"

class ChatResponseJobTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper  # ActionCable::TestHelper + Turbo stream helpers
  include ActionView::RecordIdentifier      # for dom_id in the target assertion

  def setup
    @user = User.create!(email: "cr@example.com", password: "testpassword123")
    @account = Account.create!(name: "CR Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
    @captured = []
    # Bound the indexing wait so a dead indexer thread fails the test fast instead
    # of hanging for the 120s production default.
    @original_timeout = ENV["CHAT_INDEXING_TIMEOUT"]
    ENV["CHAT_INDEXING_TIMEOUT"] = "2"
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ENV["CHAT_INDEXING_TIMEOUT"] = @original_timeout
    remove_completion_stub
    Chat.singleton_class.remove_method(:find) if Chat.singleton_class.instance_methods(false).include?(:find)
  end

  # Stub both completion entry points so no real LLM/HTTP call fires, regardless
  # of the agent_skills config. When `capture:` is true, record the
  # excluded_sources kwarg so the test can assert on it.
  def stub_completion(capture: false)
    chat_ref = @chat
    captured_ref = @captured
    do_capture = capture
    Chat.define_method(:complete_with_nosia) do |question, **opts, &blk|
      captured_ref << opts[:excluded_sources] if do_capture
      chat_ref.messages.create!(role: :assistant, content: "ok")
    end
    Chat.define_method(:complete_with_agent_skills) do |question, **opts, &blk|
      captured_ref << opts[:excluded_sources] if do_capture
      chat_ref.messages.create!(role: :assistant, content: "ok")
    end
  end

  def remove_completion_stub
    Chat.remove_method(:complete_with_nosia) if Chat.instance_methods(false).include?(:complete_with_nosia)
    Chat.remove_method(:complete_with_agent_skills) if Chat.instance_methods(false).include?(:complete_with_agent_skills)
  end

  test "waits for an attached website to index, then completes" do
    w = @account.websites.create!(url: "https://j.example", index_status: :pending)
    user_message = @chat.messages.create!(role: "user", content: "ask",
      attached_website_ids: [ w.id ])

    t = Thread.new { sleep 0.1; w.reload.update!(index_status: :indexed, indexed_at: Time.current) }

    stub_completion
    ChatResponseJob.perform_now(@chat.id, user_message.content, user_message.id)
    t.value # join the indexer thread; re-raises any error it hit so failures surface

    assert w.reload.indexed?
  end

  test "a failed attached source is excluded and the prompt includes a warn note" do
    w = @account.websites.create!(url: "https://f.example", index_status: :failed, data: "# Failed Title")
    user_message = @chat.messages.create!(role: "user", content: "ask",
      attached_website_ids: [ w.id ])

    stub_completion(capture: true)
    ChatResponseJob.perform_now(@chat.id, user_message.content, user_message.id)

    excluded = @captured.first
    assert excluded
    assert_includes excluded.map { |s| s.respond_to?(:title) ? s.title : s.to_s }, w.title
  end

  test "no attached sources -> behaves as today (no wait)" do
    user_message = @chat.messages.create!(role: "user", content: "ask")
    stub_completion
    assert_nothing_raised { ChatResponseJob.perform_now(@chat.id, user_message.content, user_message.id) }
  end

  test "the job streams rendered markdown (not raw text) through coalesced broadcasts" do
    # A user message with no attached sources -> wait_for_attached_sources! is a no-op.
    user_msg = @chat.messages.create!(role: "user", content: "draw me a heading and code")
    assistant = @chat.messages.create!(role: :assistant, content: "")
    # Stop the post-loop message.update (similar_chunk_ids) from firing broadcast_updated
    # so broadcast counts reflect only the streaming flushes. complete_with_nosia's tail
    # re-fetches via `self.messages.last`, so stub the association's `last` to return THIS
    # instance whose `update` is a no-op.
    assistant.define_singleton_method(:update) { |*| true }
    @chat.messages.define_singleton_method(:last) { assistant }

    markdown = "## Heading\n\n**bold** and *italic*\n\n```\ncode\n```\n"
    chunks = markdown.chars.each_slice(6).map { |s| StreamChunk.new(s.join) }
    stub_chat_for_streaming(@chat, chunks: chunks)
    # Force the streaming path regardless of agent_skills config / matched skills:
    # complete_with_agent_skills otherwise calls AgentSkill::Detector.detect, which
    # may branch away from complete_with_nosia. Delegate so the real coalescing loop runs.
    @chat.define_singleton_method(:complete_with_agent_skills) do |question, **opts, &blk|
      complete_with_nosia(question, **opts, &blk)
    end
    # The job re-fetches the chat via Chat.find(chat_id), which returns a fresh
    # instance that lacks the singleton stubs above. Route Chat.find to the
    # stubbed @chat so the job runs the real coalescing loop against it.
    chat_ref = @chat
    original_find = Chat.method(:find)
    Chat.define_singleton_method(:find) { |*args| args.first == chat_ref.id ? chat_ref : original_find.call(*args) }

    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      ChatResponseJob.perform_now(@chat.id, user_msg.content, user_msg.id)
    end

    # Isolate the streaming flushes: finish_generation! (in the job's ensure) also
    # broadcasts on this stream (the composer-unlock form replace + a thinking
    # animation remove), so scope to the assistant content-div target.
    content_streams = streams.select { |s| s["target"] == dom_id(assistant, :content) }

    # Coalesced: fewer broadcasts than chunks. Under perform_now the monotonic
    # clock barely advances, so typically only the guaranteed final flush fires
    # (1 broadcast for 8 chunks). The bound is deliberately loose (< chunks.size)
    # so a stray mid-stream flush on a slow box still passes -- what matters is
    # that broadcasts were coalesced, not emitted one-per-chunk.
    assert content_streams.size < chunks.size, "expected coalesced broadcasts (fewer than #{chunks.size} chunks), got #{content_streams.size}"

    # Every streaming broadcast is a replace of the content div (not a raw append).
    assert content_streams.all? { |s| s["action"] == "replace" }, "expected only replace broadcasts"
    last = content_streams.last
    assert_equal dom_id(assistant, :content), last["target"]

    # The final flush carries the fully rendered markdown — real tags, not literal #/**/``` .
    html = last.inner_html
    assert_includes html, "<h2"
    assert_includes html, "<strong>"
    assert_includes html, "<pre"
    assert_not_includes html, "## Heading"
  end

  test "finish_generation! runs even when completion raises, clearing generating" do
    user_msg = @chat.messages.create!(role: :user, content: "ask")
    @chat.start_generation!
    assert @chat.reload.generating

    raising = -> { raise Faraday::TimeoutError, "boom" }
    Chat.define_method(:complete_with_nosia) { |*| raising.call }
    Chat.define_method(:complete_with_agent_skills) { |*| raising.call }

    begin
      assert_nothing_raised { ChatResponseJob.perform_now(@chat.id, user_msg.content, user_msg.id) }
      assert_not @chat.reload.generating, "generating must be cleared by the ensure even on error"
    ensure
      Chat.remove_method(:complete_with_nosia) if Chat.instance_methods(false).include?(:complete_with_nosia)
      Chat.remove_method(:complete_with_agent_skills) if Chat.instance_methods(false).include?(:complete_with_agent_skills)
    end
  end

  test "finish_generation! clears generating on successful completion" do
    user_msg = @chat.messages.create!(role: :user, content: "ask")
    @chat.start_generation!
    stub_completion
    ChatResponseJob.perform_now(@chat.id, user_msg.content, user_msg.id)
    assert_not @chat.reload.generating, "generating must be cleared after a successful completion"
  end
end
