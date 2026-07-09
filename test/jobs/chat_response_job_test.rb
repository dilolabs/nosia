require "test_helper"

class ChatResponseJobTest < ActiveSupport::TestCase
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
end
