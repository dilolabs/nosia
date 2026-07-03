require "test_helper"

class Chunk::SearchableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "cs@example.com", password: "testpassword123")
    @account = Account.create!(name: "CS Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  test "query embedding records a TokenUsage with chat_id set and chat as source" do
    fake = Struct.new(:vectors, :input_tokens, :model).new([ 0.1, 0.2 ], 6, "text-embedding-3-small")
    assert_difference -> { TokenUsage.where(kind: "embedding", chat_id: @chat.id).count }, 1 do
      Chunk::Searchable.record_query_embedding_usage(fake, chat: @chat)
    end
    usage = TokenUsage.find_by(kind: "embedding", chat_id: @chat.id)
    assert_equal 6, usage.input_tokens
    assert_equal @chat, usage.source
  end

  test "query embedding recording is a no-op without a chat" do
    fake = Struct.new(:vectors, :input_tokens, :model).new([ 0.1, 0.2 ], 6, "text-embedding-3-small")
    assert_no_difference -> { TokenUsage.count } do
      Chunk::Searchable.record_query_embedding_usage(fake, chat: nil)
    end
  end
end
