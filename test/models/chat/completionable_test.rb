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
    msg = assistant_with_usage
    assert_kind_of RubyLLM::ActiveRecord::Usage, msg.ruby_llm_usages.first
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
    msg = assistant_with_usage(input_tokens: 10, output_tokens: 5)
    @chat.record_completion_usage!(msg)
    assert_equal "glm-5.2", TokenUsage.find_by(source: msg).model_id
  end

  test "record_completion_usage! is idempotent (no dupe on re-run)" do
    msg = assistant_with_usage(input_tokens: 10, output_tokens: 5)
    @chat.record_completion_usage!(msg)
    assert_no_difference -> { TokenUsage.count } do
      @chat.record_completion_usage!(msg)
    end
  end

  test "record_completion_usage! stores nil model_id gracefully when the message model is absent" do
    msg = assistant_with_usage(input_tokens: 10, output_tokens: 5)
    msg.define_singleton_method(:model) { nil }
    @chat.record_completion_usage!(msg)
    assert_nil TokenUsage.find_by(source: msg).model_id
  end

  test "record_completion_usage! skips messages without input_tokens" do
    msg = assistant_with_usage(input_tokens: nil)
    assert_no_difference -> { TokenUsage.count } do
      @chat.record_completion_usage!(msg)
    end
  end

  test "record_completion_usage! records normalized tokens and a string model exactly once" do
    msg = assistant_with_usage(input_tokens: 80, output_tokens: 20)
    tokens = Struct.new(:input, :output, :cache_read, :cache_write, :thinking).new(80, 20, 15, 5, 3)
    msg.define_singleton_method(:tokens) { tokens }
    msg.define_singleton_method(:model) { "glm-5.2" }
    msg.define_singleton_method(:input_tokens) { raise "legacy token reader used" }

    assert_difference({
      -> { TokenUsage.where(source: msg).count } => 1,
      -> { @chat.reload.input_tokens_count } => 80,
      -> { @chat.reload.output_tokens_count } => 20,
      -> { @account.reload.input_tokens_count } => 80,
      -> { @account.reload.output_tokens_count } => 20
    }) do
      @chat.record_completion_usage!(msg)
    end

    usage = TokenUsage.find_by!(source: msg)
    assert_equal "completion", usage.kind
    assert_equal @account.id, usage.account_id
    assert_equal @chat.id, usage.chat_id
    assert_equal msg, usage.source
    assert_equal "glm-5.2", usage.model_id
    assert_equal 80, usage.input_tokens
    assert_equal 20, usage.output_tokens
    assert_equal 15, usage.cached_tokens
    assert_equal 5, usage.cache_creation_tokens
    assert_equal 3, usage.thinking_tokens

    assert_no_difference [
      -> { TokenUsage.count },
      -> { @chat.reload.input_tokens_count },
      -> { @chat.reload.output_tokens_count },
      -> { @account.reload.input_tokens_count },
      -> { @account.reload.output_tokens_count }
    ] do
      @chat.record_completion_usage!(msg)
    end
  end

  test "record_completion_usage! skips nil messages and messages without provider usage" do
    msg = @chat.messages.create!(role: :assistant, content: "unreported")
    assert_no_difference -> { TokenUsage.count } do
      @chat.record_completion_usage!(nil)
      @chat.record_completion_usage!(msg)
    end
  end

  test "record_completion_usage! records zero input and defaults unreported buckets to zero" do
    msg = assistant_with_usage(input_tokens: 0, output_tokens: nil, cache_read_tokens: nil, cache_write_tokens: nil, thinking_tokens: nil)
    assert_difference -> { TokenUsage.where(source: msg).count }, 1 do
      @chat.record_completion_usage!(msg)
    end
    usage = TokenUsage.find_by!(source: msg)
    assert_equal [ 0, 0, 0, 0, 0 ], usage.attributes.values_at("input_tokens", "output_tokens", "cached_tokens", "cache_creation_tokens", "thinking_tokens")
  end

  def assistant_with_usage(**tokens)
    msg = @chat.messages.create!(role: :assistant, content: "hi")
    msg.ruby_llm_usages.create!(chat: @chat, operation: "chat", provider: "openai", model: "glm-5.2", status: "succeeded",
      **{ input_tokens: 120, output_tokens: 30, cache_read_tokens: 15, cache_write_tokens: 5, thinking_tokens: 3 }.merge(tokens))
    msg.reload
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
