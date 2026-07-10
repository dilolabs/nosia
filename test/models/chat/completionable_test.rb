require "test_helper"
require "turbo/broadcastable/test_helper"

class Chat::CompletionableTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper  # pulls in ActionCable::TestHelper + Turbo::Streams::StreamName

  def setup
    @user = User.create!(email: "cc@example.com", password: "testpassword123")
    @account = Account.create!(name: "CC Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  test "record_completion_usage! creates a TokenUsage for an assistant message with tokens" do
    msg = @chat.messages.create!(role: :assistant, content: "hi",
                                 input_tokens: 120, output_tokens: 30, model: nil)
    assert_difference -> { TokenUsage.where(source: msg).count }, 1 do
      @chat.record_completion_usage!(msg)
    end
    usage = TokenUsage.find_by(source: msg)
    assert_equal "completion", usage.kind
    assert_equal 120, usage.input_tokens
    assert_equal 30, usage.output_tokens
    assert_equal @chat.id, usage.chat_id
  end

  test "record_completion_usage! stores the ruby_llm string model_id via message.model" do
    model = Model.create!(model_id: "glm-5.2", name: "GLM 5.2", provider: "openai")
    msg = @chat.messages.create!(role: :assistant, content: "hi",
                                 input_tokens: 10, output_tokens: 5, model: model)
    @chat.record_completion_usage!(msg)
    assert_equal "glm-5.2", TokenUsage.find_by(source: msg).model_id
  end

  test "record_completion_usage! is idempotent (no dupe on re-run)" do
    msg = @chat.messages.create!(role: :assistant, content: "hi",
                                 input_tokens: 10, output_tokens: 5)
    @chat.record_completion_usage!(msg)
    assert_no_difference -> { TokenUsage.count } do
      @chat.record_completion_usage!(msg)
    end
  end

  test "record_completion_usage! stores nil model_id gracefully when Model is absent" do
    msg = @chat.messages.create!(role: :assistant, content: "hi",
                                 input_tokens: 10, output_tokens: 5, model: nil)
    @chat.record_completion_usage!(msg)
    assert_nil TokenUsage.find_by(source: msg).model_id
  end

  test "record_completion_usage! skips messages without input_tokens" do
    msg = @chat.messages.create!(role: :assistant, content: "hi", input_tokens: nil)
    assert_no_difference -> { TokenUsage.count } do
      @chat.record_completion_usage!(msg)
    end
  end

  def assistant_with_stubbed_update
    msg = @chat.messages.create!(role: :assistant, content: "")
    # Stop the post-loop message.update (similar_chunk_ids) from firing
    # broadcast_updated so broadcast counts reflect only the streaming flushes.
    # complete_with_nosia's tail re-fetches via `self.messages.last`, so stub
    # the association's `last` to return THIS instance whose `update` is a no-op.
    msg.define_singleton_method(:update) { |*| true }
    @chat.messages.define_singleton_method(:last) { msg }
    msg
  end

  test "complete_with_nosia coalesces streamed chunks into a single final flush" do
    assistant_with_stubbed_update
    chunks = %w[a b c d e].map { |s| StreamChunk.new(s) }
    stub_chat_for_streaming(@chat, chunks: chunks)
    buffer = Message::StreamBuffer.new(interval: 1000) # never time-flush mid-stream

    assert_turbo_stream_broadcasts([ @chat, "messages" ], count: 1) do
      @chat.complete_with_nosia("hi", stream_buffer: buffer)
    end
  end

  test "complete_with_nosia flushes per chunk when interval is zero, plus a final flush" do
    assistant_with_stubbed_update
    chunks = %w[a b c].map { |s| StreamChunk.new(s) }
    stub_chat_for_streaming(@chat, chunks: chunks)
    buffer = Message::StreamBuffer.new(interval: 0)

    assert_turbo_stream_broadcasts([ @chat, "messages" ], count: 4) do # 3 mid + 1 final
      @chat.complete_with_nosia("hi", stream_buffer: buffer)
    end
  end

  test "complete_with_nosia broadcasts nothing when the stream yields no content" do
    assistant_with_stubbed_update
    stub_chat_for_streaming(@chat, chunks: [ StreamChunk.new(nil), StreamChunk.new("") ])
    buffer = Message::StreamBuffer.new(interval: 0)

    # count: 0 + block uses the diff-based capture (new_broadcasts_from), so
    # pre-block broadcasts from message creation are excluded — only NEW
    # streaming-loop broadcasts are counted.
    assert_turbo_stream_broadcasts([ @chat, "messages" ], count: 0) do
      @chat.complete_with_nosia("hi", stream_buffer: buffer)
    end
  end

  test "complete_with_nosia yields raw chunks to the block (API path) without turbo broadcasts" do
    assistant_with_stubbed_update
    chunks = %w[a b c].map { |s| StreamChunk.new(s) }
    stub_chat_for_streaming(@chat, chunks: chunks)
    received = []

    assert_turbo_stream_broadcasts([ @chat, "messages" ], count: 0) do
      @chat.complete_with_nosia("hi") { |chunk| received << chunk.content }
    end
    assert_equal %w[a b c], received
  end
end
