require "test_helper"

class Chunk::VectorizableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "cv@example.com", password: "testpassword123")
    @account = Account.create!(name: "CV Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    # Unsaved chunk: record_embedding_usage only reads account_id + self, so a
    # chunkable/file is not needed (avoids the ActiveStorage Document setup and
    # avoids triggering the real RubyLLM.embed before_save).
    @chunk = Chunk.new(account: @account, content: "hello world")
  end

  test "indexing embedding records a TokenUsage with chat_id nil" do
    fake = Struct.new(:vectors, :input_tokens, :model).new([ 0.1, 0.2 ], 8, "text-embedding-3-small")
    assert_difference -> { TokenUsage.where(kind: "embedding", account: @account).count }, 1 do
      @chunk.send(:record_embedding_usage, fake, chat: nil)
    end
    usage = TokenUsage.find_by(kind: "embedding", account: @account, input_tokens: 8)
    assert_nil usage.chat_id
    assert_equal 8, usage.input_tokens
    assert_equal ENV["EMBEDDING_MODEL"], usage.model_id
    assert_equal "Chunk", usage.source_type
  end

  test "record_embedding_usage is a no-op for zero input_tokens" do
    fake = Struct.new(:vectors, :input_tokens, :model).new([ 0.1, 0.2 ], 0, "text-embedding-3-small")
    assert_no_difference -> { TokenUsage.count } do
      @chunk.send(:record_embedding_usage, fake, chat: nil)
    end
  end
end
