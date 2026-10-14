require "test_helper"
require "base64"
require "faraday/adapter/test"

class RubyLlmMcpGenerationTest < ActiveSupport::TestCase
  MODEL = "gpt-4o-mini"
  IMAGE_BYTES = Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=").freeze
  AUDIO_BYTES = ("RIFF".b + [ 36 ].pack("V") + "WAVEfmt ".b + [ 16, 1, 1, 8000, 16000, 2, 16 ].pack("VvvVVvv") + "data".b + [ 0 ].pack("V")).freeze

  class PromptAdapter
    def initialize(messages)
      @messages = messages
    end

    def execute_prompt(**)
      RubyLLM::MCP::Result.new({ "result" => { "messages" => @messages } })
    end
  end

  class Coordinator
    attr_accessor :sampling_callback
    attr_reader :responses, :errors

    def initialize(callback)
      @sampling_callback = callback
      @responses = []
      @errors = []
    end

    def sampling_callback_enabled?
      true
    end

    def sampling_create_message_response(**response)
      @responses << response
    end

    def error_response(**error)
      @errors << error
    end
  end

  class SamplingHandler < RubyLLM::MCP::Handlers::SamplingHandler
    def execute
      accept(default_chat_completion(MODEL))
    end
  end

  class EchoTool < RubyLLM::Tool
    description "Echo a query for MCP generation-loop tests"
    attr_reader :calls

    def initialize
      @calls = []
    end

    def name
      "mcp_generation_echo"
    end

    def execute(query:)
      @calls << query
      "tool answer: #{query}"
    end
  end

  class ApprovalTool < EchoTool
    requires_approval
  end

  setup do
    @previous_model = RubyLLM::MCP.config.sampling.preferred_model
    RubyLLM::MCP.config.sampling.preferred_model = MODEL
  end

  teardown do
    RubyLLM::MCP.config.sampling.preferred_model = @previous_model
  end

  %w[block handler].each do |mode|
    %w[assistant user system].each do |ending|
      test "#{mode} sampling generates once from #{ending} history and retains converted media" do
        callback = mode == "handler" ? SamplingHandler : ->(_) { true }
        coordinator = Coordinator.new(callback)
        messages = if ending == "system"
          []
        else
          [ mcp_message("user", text_block("sample text")),
            mcp_message("user", media_block("image", "image/png", IMAGE_BYTES)),
            mcp_message(ending, media_block("audio", "audio/wav", AUDIO_BYTES)) ]
        end
        request = RubyLLM::MCP::Result.new({ "id" => "sample", "method" => "sampling/createMessage", "params" => {
          "systemPrompt" => "system instructions", "messages" => messages, "maxTokens" => 100,
          "modelPreferences" => { "hints" => [ { "name" => MODEL } ] }
        } })

        with_provider_replies([ answer ]) do |requests|
          RubyLLM::MCP::Sample.new(request, coordinator).execute
          assert_empty coordinator.errors
          assert_equal 1, requests.size, "explicit sampling must generate, not return supplied history"
          response = coordinator.responses.fetch(0).fetch(:message)
          assert_generated(response)
          assert_equal MODEL, coordinator.responses.fetch(0).fetch(:model)
          history = response.conversation.messages[0...-1]
          assert_equal [ :system, *messages.map { |item| item.fetch("role").to_sym } ], history.map(&:role)
          assert_equal "system instructions", history.first.content
          if ending != "system"
            assert_equal [ "system instructions", "sample text", nil, nil ], history.map(&:content)
            assert_equal [ IMAGE_BYTES, AUDIO_BYTES ], history.flat_map(&:attachments).map(&:content)
            assert_wire_media(requests.first)
          end
          assert_equal history.map { |item| item.role.to_s }, requests.first.fetch("messages").map { |item| item.fetch("role") }
        end
      end
    end
  end

  %w[plain persisted].each do |kind|
    %w[assistant user system].each do |ending|
      test "#{kind} prompt ask generates once from #{ending} history without synthetic users" do
        with_provider_replies([ answer ]) do |requests|
          with_chat(kind) do |chat|
            input = prompt_messages(ending)
            response = prompt(input).ask(chat)
            assert_equal 1, requests.size
            assert_generated(response)
            assert_equal [ "system", *input.map { |item| item.fetch("role") } ], requests.first.fetch("messages").map { |item| item.fetch("role") }
            assert_equal [ "question" ], requests.first.fetch("messages").select { |item| item["role"] == "user" && item["content"].is_a?(String) }.map { |item| item["content"] } unless ending == "system"
            assert_wire_media(requests.first) unless ending == "system"
            if kind == "persisted"
              records = chat.messages.reload.to_a
              assert_equal input.size + 2, records.size
              assert_equal "generated response", records.last.content
              expected_files = ending == "system" ? [] : [ IMAGE_BYTES, AUDIO_BYTES ]
              assert_equal expected_files, records.flat_map { |record| record.attachments.map(&:download) }
            end
          end
        end
      end
    end

    %w[assistant user].each do |ending|
      test "#{kind} prompt ask completes new tools after #{ending} history without double generation" do
        with_provider_replies([ tool_request, answer ]) do |requests|
          with_chat(kind) do |chat|
            tool = EchoTool.new
            chat.with_tools(tool)
            response = prompt(prompt_messages(ending)).ask(chat)
            assert_equal 2, requests.size
            assert_generated(response)
            assert_equal [ "question" ], tool.calls
            assert_equal [ "tool answer: question" ], requests.last.fetch("messages").select { |item| item["role"] == "tool" }.map { |item| item["content"] }
            assert_equal 1, requests.last.fetch("messages").count { |item| item["tool_calls"] }
            assert chat.complete?
          end
        end
      end
    end

    test "#{kind} prompt ask preserves approval pauses after explicit generation" do
      with_provider_replies([ tool_request, answer ]) do |requests|
        with_chat(kind) do |chat|
          tool = ApprovalTool.new
          chat.with_tools(tool)
          response = prompt(prompt_messages("assistant")).ask(chat)
          assert_equal 1, requests.size
          assert response.tool_call?
          assert chat.awaiting_approval?
          assert_empty tool.calls
          chat.approve(response.tool_calls.fetch("call-1"))
          final = chat.complete
          assert_generated(final)
          assert_equal 2, requests.size
          assert_equal [ "question" ], tool.calls
          assert_not chat.awaiting_approval?
        end
      end
    end

    test "#{kind} prompt ask streams only the generated response after assistant prefill" do
      with_provider_replies([ answer ]) do |requests|
        with_chat(kind) do |chat|
          chunks = []
          response = prompt(prompt_messages("assistant")).ask(chat) { |chunk| chunks << chunk.content if chunk.content }
          assert_equal 1, requests.size
          assert_equal [ "generated", " response" ], chunks
          assert_generated(response)
          assert_equal true, requests.first.fetch("stream")
        end
      end
    end

    test "#{kind} explicit prompt generation honors cancellation rather than echoing prefill" do
      with_provider_replies([]) do |requests|
        with_chat(kind) do |chat|
          chat.cancel
          assert_raises(RubyLLM::CancelledError) { prompt(prompt_messages("assistant")).ask(chat) }
          assert_empty requests
        end
      end
    end
  end

  private
    def mcp_message(role, content)
      { "role" => role, "content" => content }
    end

    def text_block(text)
      { "type" => "text", "text" => text }
    end

    def media_block(type, mime, bytes)
      { "type" => type, "mimeType" => mime, "data" => Base64.strict_encode64(bytes) }
    end

    def prompt_messages(ending)
      return [] if ending == "system"

      [ mcp_message("user", text_block("question")),
        mcp_message("user", media_block("image", "image/png", IMAGE_BYTES)),
        mcp_message("user", media_block("audio", "audio/wav", AUDIO_BYTES)),
        (mcp_message("assistant", text_block("assistant prefill")) if ending == "assistant") ].compact
    end

    def prompt(messages)
      RubyLLM::MCP::Prompt.new(PromptAdapter.new(messages), "name" => "explicit generation")
    end

    def with_chat(kind)
      if kind == "plain"
        chat = RubyLLM::Chat.new(model: MODEL, provider: :openai)
        chat.add_message(role: :system, content: "system instructions")
        yield chat
      else
        user = User.create!(email: "mcp-generation@example.com", password: "testpassword123")
        account = Account.create!(name: "MCP generation", owner: user)
        ActsAsTenant.with_tenant(account) do
          chat = account.chats.create!(user: user, model: MODEL, provider: :openai)
          chat.add_message(role: :system, content: "system instructions")
          yield chat
        end
      end
    end

    def answer
      { "role" => "assistant", "content" => "generated response" }
    end

    def tool_request
      { "role" => "assistant", "content" => nil, "tool_calls" => [
        { "id" => "call-1", "type" => "function", "function" => { "name" => "mcp_generation_echo", "arguments" => { "query" => "question" }.to_json } }
      ] }
    end

    def assert_generated(response)
      assert_kind_of RubyLLM::Message, response
      assert_equal "generated response", response.content
      assert_equal MODEL, response.model
    end

    def assert_wire_media(request)
      parts = request.fetch("messages").flat_map { |item| item["content"].is_a?(Array) ? item["content"] : [] }
      assert_equal [ "data:image/png;base64,#{Base64.strict_encode64(IMAGE_BYTES)}" ], parts.filter_map { |part| part.dig("image_url", "url") }
      assert_equal [ Base64.strict_encode64(AUDIO_BYTES) ], parts.filter_map { |part| part.dig("input_audio", "data") }
    end

    # Only HTTP I/O is canned: the provider, protocol, loop, streaming parser,
    # attachment rendering, tool execution, approvals, and AR callbacks are real.
    def with_provider_replies(replies)
      requests = []
      queue = replies.dup
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/v1/chat/completions") do |env|
        request = JSON.parse(env.body)
        requests << request
        reply = queue.shift or raise "Unexpected extra provider generation"
        finish = reply["tool_calls"] ? "tool_calls" : "stop"
        if request["stream"]
          env.status = 200
          frames = [ { delta: { role: "assistant", content: "generated" } }, { delta: { content: " response" } }, { delta: {}, finish_reason: finish } ]
          frames.each do |choice|
            frame = { choices: [ choice.merge(index: 0) ], model: MODEL, usage: { prompt_tokens: 7, completion_tokens: 4 } }
            data = "data: #{frame.to_json}\n\n"
            env.request.on_data.call(data, data.bytesize, env)
          end
          env.request.on_data.call("data: [DONE]\n\n", 14, env)
          [ 200, { "content-type" => "text/event-stream" }, "" ]
        else
          body = { id: "reply-#{requests.size}", object: "chat.completion", model: MODEL,
            choices: [ { index: 0, message: reply, finish_reason: finish } ], usage: { prompt_tokens: 7, completion_tokens: 4 } }
          [ 200, { "content-type" => "application/json" }, body.to_json ]
        end
      end
      connection_class = RubyLLM::Transport::Connection
      original = connection_class.method(:new)
      connection_class.define_singleton_method(:new) do |*args, **kwargs|
        connection = original.call(*args, **kwargs)
        connection.connection.builder.adapter(:test, stubs)
        connection
      end
      yield requests
    ensure
      connection_class.define_singleton_method(:new, original) if original
    end
end
