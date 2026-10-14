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
    tokens = Struct.new(:input).new(8)
    fake = Struct.new(:vectors, :tokens, :model).new([ 0.1, 0.2 ], tokens, "text-embedding-3-small")
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
    tokens = Struct.new(:input).new(0)
    fake = Struct.new(:vectors, :tokens, :model).new([ 0.1, 0.2 ], tokens, "text-embedding-3-small")
    assert_no_difference -> { TokenUsage.count } do
      @chunk.send(:record_embedding_usage, fake, chat: nil)
    end
  end

  test "record_embedding_usage is a no-op for unreported input tokens" do
    tokens = Struct.new(:input).new(nil)
    fake = Struct.new(:vectors, :tokens, :model).new([ 0.1, 0.2 ], tokens, "text-embedding-3-small")
    assert_no_difference -> { TokenUsage.count } do
      @chunk.send(:record_embedding_usage, fake, chat: nil)
    end
  end

  test "record_embedding_usage is a no-op without tokens" do
    fake = Struct.new(:vectors, :tokens, :model).new([ 0.1, 0.2 ], nil, "text-embedding-3-small")
    assert_no_difference -> { TokenUsage.count } do
      @chunk.send(:record_embedding_usage, fake, chat: nil)
    end
  end

  test "record_embedding_usage is a no-op without an embedding result" do
    assert_no_difference -> { TokenUsage.count } do
      @chunk.send(:record_embedding_usage, nil, chat: nil)
    end
  end

  test "saving generated embeddings records pending normalized usage only once" do
    website = @account.websites.create!(url: "https://embedding.example")
    @chunk.chunkable = website
    vector = Array.new(Chunk.embedding_dimensions, 0.1)
    result = Struct.new(:vectors, :tokens, :model).new(vector, RubyLLM::Tokens.new(input: 8), "provider-result-model")

    with_embedding_result(result) do
      assert_difference -> { TokenUsage.where(kind: "embedding").count }, 1 do
        @chunk.save!
      end
      usage = TokenUsage.find_by!(kind: "embedding", source: @chunk)
      assert_equal 8, usage.input_tokens
      assert_equal 0, usage.output_tokens
      assert_equal ENV["EMBEDDING_MODEL"], usage.model_id
      assert_equal @account.id, usage.account_id
      assert_nil usage.chat_id
      assert_nil @chunk.instance_variable_get(:@pending_embedding_result)
      assert_equal vector, @chunk.reload.embedding

      assert_no_difference -> { TokenUsage.count } do
        @chunk.save!
      end
    end
  end

  [ 0, nil, :absent_tokens ].each do |input|
    test "saving generated embeddings without reported positive input (#{input.inspect}) keeps pending result without recording" do
      website = @account.websites.create!(url: "https://unreported-embedding.example")
      @chunk.chunkable = website
      tokens = RubyLLM::Tokens.new(input: input) unless input == :absent_tokens
      vector = Array.new(Chunk.embedding_dimensions, 0.1)
      result = Struct.new(:vectors, :tokens, :model).new(vector, tokens, "provider-result-model")

      with_embedding_result(result) do
        assert_no_difference -> { TokenUsage.count } do
          @chunk.save!
        end
      end

      assert_same result, @chunk.instance_variable_get(:@pending_embedding_result)
      assert_equal vector, @chunk.reload.embedding
    end
  end

  private
    def with_embedding_result(result)
      original = RubyLLM.method(:embed)
      RubyLLM.define_singleton_method(:embed) { |*args, **kwargs| result }
      yield
    ensure
      RubyLLM.define_singleton_method(:embed, original)
    end
end
