require "test_helper"

class TokenUsageTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "tu@example.com", password: "testpassword123")
    @account = Account.create!(name: "TU Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  test "requires a kind" do
    usage = TokenUsage.new(account: @account, chat: @chat, input_tokens: 10, output_tokens: 5)
    assert_not usage.valid?
    assert_includes usage.errors[:kind], "can't be blank"
  end

  test "creates with completion kind and increments chat + account counters" do
    assert_difference -> { @chat.reload.input_tokens_count }, 100 do
      assert_difference -> { @chat.reload.output_tokens_count }, 50 do
        assert_difference -> { @account.reload.input_tokens_count }, 100 do
          TokenUsage.create!(account: @account, chat: @chat, kind: :completion,
                             input_tokens: 100, output_tokens: 50)
        end
      end
    end
  end

  test "embedding usage with nil chat_id does not touch chat counter but does touch account" do
    assert_no_difference -> { @chat.reload.input_tokens_count } do
      assert_difference -> { @account.reload.input_tokens_count }, 30 do
        TokenUsage.create!(account: @account, kind: :embedding, input_tokens: 30, output_tokens: 0)
      end
    end
  end

  test "acts_as_tenant scopes to current account" do
    other_user = User.create!(email: "o@example.com", password: "testpassword123")
    other_account = Account.create!(name: "Other", owner: other_user)
    TokenUsage.create!(account: @account, chat: @chat, kind: :completion, input_tokens: 1, output_tokens: 1)
    ActsAsTenant.current_tenant = other_account
    assert_equal 0, TokenUsage.count
    ActsAsTenant.current_tenant = @account
    assert_equal 1, TokenUsage.count
  end

  test "energy delegates to GreenIt with the stored model_id" do
    usage = TokenUsage.create!(account: @account, chat: @chat, kind: :completion,
                               model_id: "glm-5.2", input_tokens: 1000, output_tokens: 560)
    assert_in_delta 1560 * 4095e-9, usage.energy_kwh, 1e-12
    assert_not usage.used_fallback?
  end

  test "flags fallback when model_id is unknown" do
    usage = TokenUsage.create!(account: @account, chat: @chat, kind: :completion,
                               model_id: "claude-4-6-sonnet", input_tokens: 1000, output_tokens: 0)
    assert usage.used_fallback?
  end
end
