require "test_helper"

class Api::V1::CompletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "api-completion@example.com", password: "testpassword123")
    @account = Account.create!(name: "API Completion", owner: @user)
    @account.account_users.grant_to(@user)
    @token = ApiToken.create!(account: @account, user: @user, name: "completion")
    ActsAsTenant.current_tenant = @account
    @account.prompts.create!(name: "system_prompt", content: "API_SYSTEM_SECRET %{documents}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "JSON completion retains request options through the real completion preamble" do
    with_local_completion do |requests|
      post "/v1/chat/completions", params: completion_params, headers: auth_headers, as: :json

      assert_response :success
      assert_equal "**Hello** world", response.parsed_body.dig("choices", 0, "message", "content")
      assert_provider_request(requests)
      assert_equal [ "question" ], Chat.last.messages.where(role: :user).pluck(:content)
      assert_not_includes response.body, "API_SYSTEM_SECRET"
      assert_not_includes response.body, "API_RAG_SECRET"
    end
  end

  test "SSE completion preserves raw chunks and the DONE marker" do
    with_local_completion do |requests|
      post "/v1/chat/completions", params: completion_params.merge(stream: true), headers: auth_headers, as: :json

      assert_response :success
      events = response.body.split("\n\n").map { |event| event.delete_prefix("data: ") }
      assert_equal "[DONE]", events.pop
      chunks = events.map { |event| JSON.parse(event) }
      assert_equal [ "**Hello**", " world" ], chunks.map { |chunk| chunk.dig("choices", 0, "delta", "content") }
      assert chunks.all? { |chunk| chunk["object"] == "chat.completion.chunk" && chunk["model"] == "nosia:private/api.v2" }
      assert_provider_request(requests)
      assert_not_includes response.body, "API_SYSTEM_SECRET"
      assert_not_includes response.body, "API_RAG_SECRET"
    end
  end

  test "French browser preferences cannot alter or break committed SSE responses" do
    with_local_completion do |requests|
      post "/v1/chat/completions", params: completion_params.merge(stream: true), headers: auth_headers.merge("Accept-Language" => "fr"), as: :json

      assert_response :success
      assert_equal "en", response.headers["Content-Language"]
      assert_includes response.body, "data: [DONE]"
      assert_includes response.body, "**Hello**"
      assert_provider_request(requests)
    end
  end

  %w[/v1/completions /v1/chat/completions].each do |path|
    test "#{path} prompt-only JSON generates from the user prompt without exposing system instructions" do
      with_local_completion do |requests|
        post path, params: completion_params.except(:messages).merge(prompt: "question"), headers: auth_headers, as: :json

        assert_response :success
        assert_not_includes response.body, "API_SYSTEM_SECRET"
        assert_not_includes response.body, "API_RAG_SECRET"
        assert_equal "**Hello** world", response.parsed_body.dig("choices", 0, "message", "content")
        assert_provider_request(requests)
        assert_equal [ "question" ], Chat.last.messages.where(role: :user).pluck(:content)
        assert_equal "**Hello** world", Chat.last.messages.assistant.last.content
      end
    end

    test "#{path} prompt-only SSE generates raw chunks before DONE" do
      with_local_completion do |requests|
        post path, params: completion_params.except(:messages).merge(prompt: "question", stream: true), headers: auth_headers, as: :json

        assert_response :success
        assert_provider_request(requests)
        events = response.body.split("\n\n").map { |event| event.delete_prefix("data: ") }
        assert_equal "[DONE]", events.pop
        assert_equal [ "**Hello**", " world" ], events.map { |event| JSON.parse(event).dig("choices", 0, "delta", "content") }
        assert_not_includes response.body, "API_SYSTEM_SECRET"
        assert_not_includes response.body, "API_RAG_SECRET"
        assert_equal [ "question" ], Chat.last.messages.where(role: :user).pluck(:content)
        assert_equal "**Hello** world", Chat.last.messages.assistant.last.content
      end
    end
  end

  test "messages history stages its existing users once and generates for the final user" do
    history = [ { role: "user", content: "earlier question" }, { role: "assistant", content: "earlier answer" }, { role: "user", content: "question" } ]
    with_local_completion do |requests|
      post "/v1/chat/completions", params: completion_params.merge(messages: history), headers: auth_headers, as: :json

      assert_response :success
      assert_equal "**Hello** world", response.parsed_body.dig("choices", 0, "message", "content")
      assert_provider_request(requests)
      assert_equal history.map(&:stringify_keys), requests.first.fetch("messages").reject { |message| message["role"] == "system" }
      assert_equal [ "earlier question", "question" ], Chat.last.messages.where(role: :user).pluck(:content)
      assert_not_includes response.body, "API_SYSTEM_SECRET"
      assert_not_includes response.body, "API_RAG_SECRET"
    end
  end

  {
    "missing input" => {},
    "completed assistant history" => {
      messages: [ { role: "user", content: "earlier question" }, { role: "assistant", content: "earlier answer" } ]
    }
  }.each do |name, input|
    [ false, true ].each do |stream|
      test "#{name} fails closed without exposing system instructions (stream: #{stream})" do
        with_local_completion do |requests|
          post "/v1/completions", params: completion_params.except(:messages).merge(input).merge(stream: stream), headers: auth_headers, as: :json

          assert_not_includes response.body, "API_SYSTEM_SECRET"
          assert_not_includes response.body, "API_RAG_SECRET"
          assert_response :unprocessable_entity
          assert_equal "A user prompt or final user message is required", response.parsed_body["error"]
          assert_empty requests
        end
      end
    end
  end

  private
    def completion_params
      { model: "private/api.v2", messages: [ { role: "user", content: "question" } ], max_tokens: 123, top_p: 0.75, top_k: 12, temperature: 0.4 }
    end

    def auth_headers
      { "Authorization" => "Bearer #{@token.plain_token}" }
    end

    def with_local_completion
      requests = []
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/v1/chat/completions") do |env|
        request = JSON.parse(env.body)
        requests << request
        env.status = 200
        frames = [
          { choices: [ { delta: { role: "assistant", content: "**Hello**" }, index: 0 } ], model: "private/api.v2" },
          { choices: [ { delta: { content: " world" }, index: 0 } ], model: "private/api.v2" },
          { choices: [ { delta: {}, finish_reason: "stop", index: 0 } ], model: "private/api.v2", usage: { prompt_tokens: 7, completion_tokens: 4 } }
        ]
        frames.each do |frame|
          data = "data: #{frame.to_json}\n\n"
          env.request.on_data.call(data, data.bytesize, env)
        end
        env.request.on_data.call("data: [DONE]\n\n", 14, env)
        [ 200, { "content-type" => "text/event-stream" }, "" ]
      end
      connection_class = RubyLLM::Transport::Connection
      original_connection = connection_class.method(:new)
      connection_class.define_singleton_method(:new) do |*args, **kwargs|
        connection = original_connection.call(*args, **kwargs)
        connection.connection.builder.adapter(:test, stubs)
        connection
      end

      chunk = Struct.new(:id, :title, :context, :augmented_context, :source).new(1, "Private document", "API_RAG_SECRET", "API_RAG_SECRET", "private")
      original = Chat.method(:new)
      Chat.define_singleton_method(:new) do |*args, **kwargs, &block|
        chat = original.call(*args, **kwargs, &block)
        chat.define_singleton_method(:mcp_tools) { [] }
        chat.define_singleton_method(:similarity_search) { |_| [ chunk ] }
        chat.define_singleton_method(:answer_relevance) { |*args, **options| true }
        chat.define_singleton_method(:broadcast_thinking_phase) { |*| }
        chat
      end
      yield requests
    ensure
      Chat.define_singleton_method(:new, original) if original
      connection_class.define_singleton_method(:new, original_connection) if original_connection
    end

    def assert_provider_request(requests)
      assert_equal 1, requests.size, "a user prompt must cause one real-loop provider request"
      request = requests.first
      assert_equal "private/api.v2", request["model"]
      assert_equal 123, request["max_tokens"]
      assert_equal 0.75, request["top_p"]
      assert_equal 12.0, request["top_k"]
      assert_equal 0.4, request["temperature"]
      assert_not request.key?("provider_options")
      assert_not request.key?("max_completion_tokens")
      assert_equal({ "role" => "user", "content" => "question" }, request.fetch("messages").reject { |message| message["role"] == "system" }.last)
      system = request.fetch("messages").select { |message| message["role"] == "system" }.map { |message| message["content"] }.join("\n")
      assert_includes system, "API_SYSTEM_SECRET"
      assert_includes system, "API_RAG_SECRET"
    end
end
