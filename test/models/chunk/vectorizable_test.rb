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
    vector = Array.new(Chunk.columns_hash.fetch("embedding").limit, 0.1)
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

  test "ordinary source embeddings honor configured HTTP retries and body logging" do
    output = StringIO.new
    request_marker = "source-request-#{SecureRandom.hex}"
    response_marker = "source-response-#{SecureRandom.hex}"
    vector = [ 1.0 ] + Array.new(Chunk.columns_hash.fetch("embedding").limit - 1, 0.0)
    requests = []
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/embeddings") do |request|
        requests << JSON.parse(request.body).fetch("input")
        if requests.one?
          next [ 503, { "Content-Type" => "application/json" }, { error: { message: "Synthetic service outage" } }.to_json ]
        end

        body = { data: [ { embedding: vector } ], diagnostic: response_marker }
        [ 200, { "Content-Type" => "application/json" }, body.to_json ]
      end
    end
    adapter = Class.new(Faraday::Adapter::Test) do
      define_method(:initialize) { |app, **| super(app, stubs, &nil) }
    end
    previous = RubyLLM.config.dup
    RubyLLM.configure do |config|
      config.faraday_adapter = adapter
      config.logger = Logger.new(output, level: :debug)
      config.log_bodies = true
      config.max_retries = 1
      config.retry_interval = 0
    end

    @chunk.chunkable = @account.websites.create!(url: "https://embedding.example")
    @chunk.content = request_marker
    @chunk.save!

    assert_equal [ request_marker, request_marker ], requests
    assert_equal vector, @chunk.reload.embedding
    assert_includes output.string, request_marker
    assert_includes output.string, response_marker
  ensure
    if previous
      RubyLLM.configure do |config|
        config.faraday_adapter = previous.faraday_adapter
        config.logger = previous.logger
        config.log_bodies = previous.log_bodies
        config.max_retries = previous.max_retries
        config.retry_interval = previous.retry_interval
      end
    end
  end

  test "unspecified embedding width preserves the legacy source request but not the note request" do
    old_dimensions = ENV.delete("EMBEDDING_DIMENSIONS")
    sent = []
    original = RubyLLM.method(:embed)
    RubyLLM.define_singleton_method(:embed) { |_, dimensions:, **| sent << dimensions }

    Chunk.embed_text("ordinary")
    Chunk.embed_text("private", private_input: true)

    assert_equal [ 0, Chunk.embedding_dimensions ], sent
  ensure
    ENV["EMBEDDING_DIMENSIONS"] = old_dimensions
    RubyLLM.define_singleton_method(:embed, original)
  end

  [ 0, nil, :absent_tokens ].each do |input|
    test "saving generated embeddings without reported positive input (#{input.inspect}) keeps pending result without recording" do
      website = @account.websites.create!(url: "https://unreported-embedding.example")
      @chunk.chunkable = website
      tokens = RubyLLM::Tokens.new(input: input) unless input == :absent_tokens
      vector = Array.new(Chunk.columns_hash.fetch("embedding").limit, 0.1)
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
