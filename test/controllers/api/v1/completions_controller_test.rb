require "test_helper"

class Api::V1::CompletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "api-completion@example.com", password: "testpassword123")
    @account = Account.create!(name: "API Completion", owner: @user)
    @account.account_users.grant_to(@user)
    @token = ApiToken.create!(account: @account, user: @user, name: "completion")
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "JSON completion retains request options through the real completion preamble" do
    with_local_completion do |calls|
      post "/v1/chat/completions", params: completion_params, headers: auth_headers, as: :json

      assert_response :success
      assert_equal "**Hello** world", response.parsed_body.dig("choices", 0, "message", "content")
      assert_equal [ { max_tokens: 123, top_p: 0.75, top_k: 12.0 } ], calls
    end
  end

  test "SSE completion preserves raw chunks and the DONE marker" do
    with_local_completion do |calls|
      post "/v1/chat/completions", params: completion_params.merge(stream: true), headers: auth_headers, as: :json

      assert_response :success
      events = response.body.split("\n\n").map { |event| event.delete_prefix("data: ") }
      assert_equal "[DONE]", events.pop
      chunks = events.map { |event| JSON.parse(event) }
      assert_equal [ "**Hello**", " world" ], chunks.map { |chunk| chunk.dig("choices", 0, "delta", "content") }
      assert chunks.all? { |chunk| chunk["object"] == "chat.completion.chunk" && chunk["model"] == "nosia:private/api.v2" }
      assert_equal [ { max_tokens: 123, top_p: 0.75, top_k: 12.0 } ], calls
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
      calls = []
      original = Chat.method(:new)
      Chat.define_singleton_method(:new) do |*args, **kwargs, &block|
        chat = original.call(*args, **kwargs, &block)
        options_method = chat.method(:with_provider_options)
        chat.define_singleton_method(:with_provider_options) { |**options| calls << options; options_method.call(options) }
        chat.define_singleton_method(:mcp_tools) { [] }
        chat.define_singleton_method(:similarity_search) { |_| [] }
        chat.define_singleton_method(:system_prompt) { "API baseline" }
        chat.define_singleton_method(:answer_relevance) { |*args, **options| true }
        chat.define_singleton_method(:broadcast_thinking_phase) { |*| }
        chat.define_singleton_method(:complete) do |&stream|
          message = messages.create!(role: :assistant, content: "**Hello** world", done: true)
          [ "**Hello**", " world" ].each { |content| stream.call(StreamChunk.new(content)) } if stream
          message
        end
        chat
      end
      yield calls
    ensure
      Chat.define_singleton_method(:new, original) if original
    end
end
