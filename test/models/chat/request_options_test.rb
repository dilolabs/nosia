require "test_helper"

class Chat::RequestOptionsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "request-options@example.com", password: "testpassword123")
    @account = Account.create!(name: "Request Options", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "completion preserves provider option names and replaces baseline instructions before appending attachment warnings" do
    calls = capture_completion
    source = Struct.new(:title).new("Missing PDF")

    @chat.complete_with_nosia("question", model: "private/model.v2", temperature: 0.4,
      max_tokens: 123, top_p: 0.75, top_k: 12, excluded_sources: [ source ]) { |_| }

    assert_equal [ [ "private/model.v2", { provider: :openai, assume_model_exists: true } ] ], calls[:models]
    assert_equal [ { max_tokens: 123, top_p: 0.75, top_k: 12 } ], calls[:options]
    assert_equal [ 0.4 ], calls[:temperatures]
    assert_equal [ [ "Baseline %{documents}", {} ],
      [ "Note: the following attachments could not be retrieved and were excluded: Missing PDF.", { append: true } ] ], calls[:instructions]
  end

  test "completion replaces augmented instructions and keeps environment option defaults" do
    chunk = Struct.new(:id, :title, :context, :source).new(1, "Title", "Context", "Source")
    calls = capture_completion(chunks: [ chunk ])
    @chat.complete_with_nosia("question") { |_| }

    assert_equal [ { max_tokens: ENV["LLM_MAX_TOKENS"].to_i, top_p: ENV["LLM_TOP_P"].to_f, top_k: ENV["LLM_TOP_K"].to_f } ], calls[:options]
    documents = [ { doc_id: 1, title: "Title", text: "Context", source: "Source" } ]
    assert_equal [ [ "Baseline #{documents.to_json}", {} ] ], calls[:instructions]
  end

  test "completion uses the real 2.0 model switch for an unregistered OpenAI-compatible model" do
    capture_completion
    @chat.singleton_class.remove_method(:with_model)

    @chat.complete_with_nosia("question", model: "private/unknown.v2") { |_| }

    assert_equal "private/unknown.v2", @chat.model.model_id
    assert_equal "openai", @chat.model.provider
  end

  test "real 2.0 request rendering retains flat OpenAI-compatible fields and replaces then appends instructions" do
    capture_completion
    %i[with_model with_provider_options with_temperature with_instructions].each do |method|
      @chat.singleton_class.remove_method(method)
    end
    @chat.with_instructions("Obsolete baseline")

    @chat.complete_with_nosia("question", model: "private/request.v2", max_tokens: 123,
      top_p: 0.75, top_k: 12, temperature: 0.4, excluded_sources: [ Struct.new(:title).new("Missing PDF") ]) { |_| }

    payload = @chat.render
    assert_equal "private/request.v2", payload[:model]
    assert_equal 123, payload[:max_tokens]
    assert_equal 0.75, payload[:top_p]
    assert_equal 12, payload[:top_k]
    assert_equal 0.4, payload[:temperature]
    assert_not payload.key?(:provider_options)
    assert_not payload.key?(:max_completion_tokens)
    instructions = @chat.messages.where(role: :system).map(&:content)
    assert_equal "Baseline %{documents}", instructions.first
    assert_equal 2, instructions.size
    assert_includes instructions.last, "Missing PDF"
    assert_not_includes payload.to_json, "Obsolete baseline"
  end

  %i[answer context].each do |kind|
    test "#{kind} relevance replaces guard instructions using the 2.0 keywords" do
      calls = []
      guard = Object.new
      guard.define_singleton_method(:assume_model_exists=) { |value| }
      guard.define_singleton_method(:with_model) { |model, **options| calls << [ :model, model, options ]; self }
      guard.define_singleton_method(:with_temperature) { |value| calls << [ :temperature, value ]; self }
      guard.define_singleton_method(:with_instructions) { |text, **options| calls << [ :instructions, text, options ]; self }
      guard.define_singleton_method(:ask) { |prompt| calls << [ :ask, prompt ]; Struct.new(:content).new("0") }
      @chat.chats.define_singleton_method(:create!) { |**attributes| guard }
      previous = ENV["GUARD_MODEL"]
      ENV["GUARD_MODEL"] = "private/guard.v2"

      assert @chat.public_send("#{kind}_relevance", "candidate", question: "question")
      assert_includes calls, [ :instructions, Prompts.public_send("#{kind}_relevance_guard"), {} ]
      assert_includes calls, [ :model, "private/guard.v2", { provider: :openai, assume_model_exists: true } ]
      assert_includes calls, [ :temperature, 0.0 ]
      assert_equal :ask, calls.last.first
    ensure
      ENV["GUARD_MODEL"] = previous
    end
  end

  private
    def capture_completion(chunks: [])
      calls = { models: [], options: [], temperatures: [], instructions: [] }
      message = @chat.messages.create!(role: :assistant, content: "answer")
      @chat.messages.define_singleton_method(:last) { message }
      @chat.define_singleton_method(:with_model) { |model, **options| calls[:models] << [ model, options ]; self }
      @chat.define_singleton_method(:with_provider_options) { |**options| calls[:options] << options; self }
      @chat.define_singleton_method(:with_temperature) { |value| calls[:temperatures] << value; self }
      @chat.define_singleton_method(:with_instructions) { |text, **options| calls[:instructions] << [ text, options ]; self }
      @chat.define_singleton_method(:system_prompt) { "Baseline %{documents}" }
      @chat.define_singleton_method(:mcp_tools) { [] }
      @chat.define_singleton_method(:similarity_search) { |_| chunks }
      @chat.define_singleton_method(:broadcast_thinking_phase) { |*| }
      @chat.define_singleton_method(:answer_relevance) { |*args, **options| true }
      @chat.define_singleton_method(:complete) { |&block| message }
      calls
    end
end
