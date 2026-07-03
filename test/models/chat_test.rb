require "test_helper"

class ChatTest < ActiveSupport::TestCase
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
end
