require "test_helper"
require "turbo/broadcastable/test_helper"

class ChatTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper
  include ActionView::RecordIdentifier

  def setup
    @user = User.create!(email: "ct@example.com", password: "testpassword123")
    @account = Account.create!(name: "CT Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @session = Session.create!(user: @user)
    Current.session = @session
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    Current.session = nil
  end

  test "recount! repairs drifted counters" do
    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, input_tokens: 100, output_tokens: 40)
    @chat.update!(input_tokens_count: 0, output_tokens_count: 0) # simulate drift
    @chat.recount!
    assert_equal 100, @chat.reload.input_tokens_count
    assert_equal 40, @chat.reload.output_tokens_count
  end

  test "token_totals_by_kind returns [in, out] per kind" do
    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, input_tokens: 100, output_tokens: 40)
    TokenUsage.create!(account: @account, chat: @chat, kind: :embedding, input_tokens: 12, output_tokens: 0)
    totals = @chat.token_totals_by_kind
    assert_equal [ 100, 40 ], totals["completion"]
    assert_equal [ 12, 0 ], totals["embedding"]
  end

  test "wait_for_attached_sources! broadcasts indexing only when there are sources" do
    # No sources -> early return, no indexing broadcast.
    user_msg = @chat.messages.create!(role: :user, content: "ask")
    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.wait_for_attached_sources!(user_msg, timeout: 1.second, step: 0.1.second)
    end
    assert streams.none? { |s| s.inner_html.include?("Indexing") },
           "expected no indexing phase when there are no attached sources"

    # A pending source -> indexing broadcast fires while the poll waits.
    w = @account.websites.create!(url: "https://i.example", index_status: :pending)
    user_msg2 = @chat.messages.create!(role: :user, content: "ask2", attached_website_ids: [ w.id ])
    t = Thread.new { sleep 0.2; w.reload.update!(index_status: :indexed, indexed_at: Time.current) }
    streams2 = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.wait_for_attached_sources!(user_msg2, timeout: 3.seconds, step: 0.1.second)
    end
    t.value
    assert_includes streams2.map { |s| s.inner_html }.join, "Indexing",
                    "expected an indexing phase when an attachment is pending"
  end

  test "start_generation! sets generating; finish_generation! clears it and broadcasts unlock + cleanup" do
    @chat.start_generation!
    assert @chat.reload.generating, "start_generation! should set generating"

    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.finish_generation!
    end
    assert_not @chat.reload.generating, "finish_generation! should clear generating"

    assert streams.any? { |s| s["action"] == "replace" && s["target"] == "#{dom_id(@chat)}_message_form" },
           "finish_generation! should replace the form frame to unlock the composer"
    assert streams.any? { |s| s["action"] == "remove" && s["target"] == "thinking_animation" },
           "finish_generation! should remove a stuck thinking_animation (error-before-bubble cleanup)"
    assert streams.any? { |s| s["action"] == "refresh" },
           "finish_generation! should broadcast a morph refresh so tabs that missed live broadcasts self-heal"
  end

  # A blank/nil-content assistant message (left by a failed or empty generation)
  # is serialized into the next LLM request by ruby_llm, and the provider rejects
  # the whole request ("invalid message content type: <nil>"), permanently
  # blocking every further response in the chat. Purging them keeps the
  # conversation valid so subsequent turns work.
  test "purge_blank_assistant_messages! removes nil/empty assistant messages that poison the request" do
    @chat.messages.create!(role: :user, content: "Q1")
    @chat.messages.create!(role: :assistant, content: "A1")
    @chat.messages.create!(role: :user, content: "Q2")
    empty = @chat.messages.create!(role: :assistant, content: "")
    nilm  = @chat.messages.create!(role: :assistant, content: nil)

    @chat.purge_blank_assistant_messages!

    assert_not Message.exists?(empty.id), "empty-content assistant message should be purged"
    assert_not Message.exists?(nilm.id), "nil-content assistant message should be purged"
    assert @chat.reload.to_llm.messages.none? { |m| m.content.nil? },
      "no nil-content message should reach the LLM after purging"
  end

  # A blank assistant message that carries tool_calls is a legitimate intermediate
  # step (content lives in the tool calls), not a failed generation — keep it.
  test "purge_blank_assistant_messages! keeps blank assistant messages with tool_calls" do
    keep = @chat.messages.create!(role: :assistant, content: "")
    keep.tool_calls.create!(tool_call_id: "call_1", name: "search", arguments: {})

    @chat.purge_blank_assistant_messages!

    assert Message.exists?(keep.id), "blank assistant with tool_calls must be preserved"
  end

  # finish_generation! runs inside ChatResponseJob, which has no Current.session
  # (and thus no Current.account). The composer-unlock broadcast renders
  # messages/_form, so that form must not depend on request-scoped Current or the
  # render raises, the form is never replaced, and the submit button stays locked
  # after the response completes.
  test "finish_generation! broadcasts the unlocked form even without Current (job context)" do
    Current.session = nil

    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.finish_generation!
    end

    form = streams.find { |s| s["action"] == "replace" && s["target"] == "#{dom_id(@chat)}_message_form" }
    assert form, "finish_generation! must broadcast the composer form replace in the job context"
    assert_not_includes form.inner_html, "disabled",
      "the broadcast form must be unlocked so the submit button is usable again"
  end
end
