require "test_helper"

class Chat::CompletionableTest < ActiveSupport::TestCase
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
end
