require "test_helper"
require "turbo/broadcastable/test_helper"

class ChatTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper
  include ActionView::RecordIdentifier

  def setup
    @user = User.create!(email: "ct@example.com", password: "testpassword123")
    @account = Account.create!(name: "CT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
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
end
