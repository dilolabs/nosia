require "test_helper"
require "base64"

class RubyLlmMcpCompatibilityTest < ActiveSupport::TestCase
  class CannedAdapter
    attr_accessor :result, :prompt_messages, :resource_contents
    attr_reader :calls, :registered_resources

    def initialize
      @calls = []
      @registered_resources = []
    end

    def client
      Struct.new(:name).new("canned")
    end

    def execute_tool(**arguments)
      @calls << arguments
      @result
    end

    def execute_prompt(**arguments)
      @calls << arguments
      RubyLLM::MCP::Result.new({ "result" => { "messages" => @prompt_messages } })
    end

    def resource_read(uri:)
      @calls << { uri: uri }
      RubyLLM::MCP::Result.new({ "result" => { "contents" => @resource_contents } })
    end

    def register_resource(resource)
      @registered_resources << resource
    end
  end

  class CannedCoordinator
    attr_accessor :sampling_callback
    attr_reader :responses, :errors

    def initialize
      @responses = []
      @errors = []
    end

    def sampling_callback_enabled?
      !sampling_callback.nil?
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
      accept(default_chat_completion("test-model"))
    end
  end

  setup do
    @adapter = CannedAdapter.new
  end

  test "loads the exact RubyLLM 2.0 release" do
    assert_equal Gem::Version.new("2.0.0"), Gem.loaded_specs.fetch("ruby_llm").version
  end

  test "keeps the configured endpoint on the Chat Completions protocol" do
    config = RubyLLM.config

    assert_respond_to config, :openai_protocol
    assert_equal :chat_completions, config.openai_protocol
    assert_equal ENV.fetch("LLM_MODEL"), config.default_model
    assert_equal ENV.fetch("EMBEDDING_MODEL"), config.default_embedding_model
    assert_equal ENV.fetch("AI_BASE_URL"), config.openai_api_base
    assert_equal ENV.fetch("AI_API_KEY"), config.openai_api_key
    assert_equal true, config.openai_use_system_role
  end

  test "MCP attachments expose decoded bytes and preserve the base64 wire payload" do
    payload = "binary payload".b
    encoded = Base64.strict_encode64(payload)
    attachment = RubyLLM::MCP::Attachment.new(encoded, "application/pdf")

    assert_equal payload, attachment.content
    assert_equal encoded, attachment.encoded
    assert_equal payload.bytesize, attachment.byte_size
    assert_equal "application/pdf", attachment.mime_type
    assert_kind_of StringIO, attachment.source
    assert_equal "mcp-attachment", attachment.filename
    assert_same RubyLLM.config, attachment.config
    assert_not attachment.path?
    assert_not attachment.url?
    assert attachment.pdf?
  end

  test "MCP rejects invalid base64 rather than reading a path or URL" do
    [ "/etc/passwd", "http://127.0.0.1/private", "not base64!" ].each do |data|
      assert_raises(ArgumentError) { RubyLLM::MCP::Attachment.new(data, "image/png") }
    end
  end

  test "image audio and file bytes survive provider serialization without double encoding" do
    bytes = "\x00\xff\x80binary\x00".b
    encoded = Base64.strict_encode64(bytes)
    attachments = %w[image/png audio/wav application/pdf].map { |mime| RubyLLM::MCP::Attachment.new(encoded, mime) }
    attachments.each do |attachment|
      assert_equal bytes, attachment.content
      assert_equal encoded, attachment.encoded
      assert_equal bytes.bytesize, attachment.byte_size
      assert_same RubyLLM.config, attachment.config
    end
    parts = RubyLLM::Protocols::ChatCompletions::Media.format_content("caption", attachments)
    assert_equal "data:image/png;base64,#{encoded}", parts[1].dig(:image_url, :url)
    assert_equal encoded, parts[2].dig(:input_audio, :data)
    assert_equal "data:application/pdf;base64,#{encoded}", parts[3].dig(:file, :file_data)
  end

  test "bridge content explicitly converts to supported tool results and messages" do
    assert_not RubyLLM.const_defined?(:Content, false)
    attachment = RubyLLM::MCP::Attachment.new(Base64.strict_encode64("bytes"), "image/png")
    content = RubyLLM::MCP::Content.new(text: "caption", attachments: [ nil, attachment ])

    assert_equal [ attachment ], content.attachments
    assert_equal [ "caption", attachment ], content.to_tool_result
    text, files = RubyLLM::Tool.split_result(content.to_tool_result)
    assert_equal "caption", text
    assert_equal [ attachment ], files
    message = content.to_message(role: :user)
    assert_equal :user, message.role
    assert_equal "caption", message.content
    assert_equal [ attachment ], message.attachments
    assert_equal "plain", RubyLLM::MCP::Content.new(text: "plain").to_tool_result
    assert_equal [ attachment ], RubyLLM::MCP::Content.new(attachments: attachment).to_tool_result
    assert_raises(ArgumentError) { RubyLLM::MCP::Content.new(attachments: [ "http://127.0.0.1/private" ]) }
  end

  test "remote tool preserves nested required schema and keyword arguments" do
    schema = { "type" => "object", "properties" => {
      "query" => { "type" => "string" }, "options" => { "type" => "object", "properties" => {
        "limit" => { "type" => "integer" }
      }, "required" => [ "limit" ] }
    }, "required" => [ "query", "options" ] }
    tool = remote_tool(input_schema: schema)
    canned_result([ text_block("first"), text_block("last") ])

    assert_equal schema, tool.parameters_schema
    assert_equal schema, tool.to_h.fetch(:parameters_schema)
    assert_equal "first\nlast", tool.call(**{ "query" => "search", "options" => { "limit" => 2 } })
    assert_equal [ { name: "lookup", parameters: { query: "search", options: { "limit" => 2 } } } ], @adapter.calls
  end

  test "remote tool retains every text image audio and file block" do
    canned_result([
      media_block("image", "image/png", "first image"), text_block("first text"),
      media_block("audio", "audio/wav", "audio bytes"),
      { "type" => "resource", "resource" => { "uri" => "file:///server/report", "mimeType" => "application/pdf", "blob" => Base64.strict_encode64("pdf bytes") } },
      text_block("last text"), media_block("image", "image/jpeg", "last image")
    ])

    result = remote_tool.call
    assert_kind_of Array, result
    text, files = RubyLLM::Tool.split_result(result)
    assert_includes text, "first text"
    assert_includes text, "last text"
    assert_equal [ "first image", "audio bytes", "pdf bytes", "last image" ], files.map(&:content)
    assert_equal [ "image/png", "audio/wav", "application/pdf", "image/jpeg" ], files.map(&:mime_type)
    files.each do |file|
      assert_equal Base64.strict_encode64(file.content), file.encoded
      assert_equal file.content.bytesize, file.byte_size
      assert_kind_of StringIO, file.source
    end
  end

  test "remote tool retains all attachments even without text" do
    canned_result([ media_block("image", "image/png", "first"), media_block("image", "image/png", "last") ])
    text, files = RubyLLM::Tool.split_result(remote_tool.call)
    assert_equal "", text
    assert_equal [ "first", "last" ], files.map(&:content)
  end

  test "structured output stays authoritative and retains attachments with and without a schema" do
    [ nil, { "type" => "object", "properties" => { "count" => { "type" => "integer" } }, "required" => [ "count" ] } ].each do |schema|
      canned_result([ text_block("untrusted summary"), media_block("image", "image/png", "image") ], "structuredContent" => { "count" => 3 })
      text, files = RubyLLM::Tool.split_result(remote_tool(output_schema: schema).call)
      assert_equal({ "count" => 3 }, JSON.parse(text))
      assert_equal [ "image" ], files.map(&:content)
    end
  end

  test "remote tool preserves error hashes and output schema validation" do
    tool = remote_tool(output_schema: { "type" => "object", "required" => [ "count" ], "properties" => { "count" => { "type" => "integer" } } })
    canned_result([ text_block("first"), text_block("last") ], "isError" => true)
    assert_equal({ error: "Tool execution error: first\nlast" }, tool.call)
    canned_result([], "structuredContent" => { "count" => "invalid" })
    assert_match(/Structured output is not valid/, tool.call.fetch(:error))
    @adapter.result = RubyLLM::MCP::Result.new({ "error" => { "code" => -32603, "message" => "server failed" } })
    assert_match(/server failed/, tool.call.fetch(:error))
    canned_result([])
    assert_equal "", tool.call
  end

  test "remote embedded resources and resource links retain text and URI dispatch" do
    @adapter.resource_contents = [ { "text" => "linked text" } ]
    canned_result([
      { "type" => "resource", "resource" => { "uri" => "file:///server/inline", "text" => "embedded text" } },
      { "type" => "resource_link", "name" => "linked", "uri" => "git://server/readme", "description" => "readme", "mimeType" => "text/plain" }
    ])
    result = remote_tool.call
    assert_kind_of String, result
    assert_includes result, "embedded text"
    assert_includes result, "linked text"
    assert_equal [ "git://server/readme" ], @adapter.registered_resources.map(&:uri)
    assert_equal({ uri: "git://server/readme" }, @adapter.calls.last)
  end

  test "prompt fetch and inclusion use real messages with separate attachments" do
    @adapter.prompt_messages = [
      { "role" => "user", "content" => text_block("prompt text") },
      { "role" => "user", "content" => media_block("image", "image/png", "prompt image") },
      { "role" => "assistant", "content" => media_block("audio", "audio/wav", "prompt audio") },
      { "role" => "user", "content" => { "type" => "resource", "resource" => { "uri" => "file:///inline", "text" => "inline text", "mimeType" => "text/plain" } } }
    ]
    prompt = RubyLLM::MCP::Prompt.new(@adapter, "name" => "demo")
    chat = plain_chat
    assert_same chat, prompt.include(chat)
    assert_equal 4, chat.messages.size
    assert_equal "prompt text", chat.messages.first.content
    assert_equal "prompt image", chat.messages[1].attachments.first.content
    assert_equal :assistant, chat.messages[2].role
    assert_equal "prompt audio", chat.messages[2].attachments.first.content
    assert_includes chat.messages.last.content, "inline text"
    assert chat.messages.all? { |message| message.content.nil? || message.content.is_a?(String) }
  end

  test "prompt and resource inclusion persist real chat text and bytes without provider calls" do
    user = User.create!(email: "bridge@example.com", password: "testpassword123")
    account = Account.create!(name: "Bridge", owner: user)
    ActsAsTenant.with_tenant(account) do
      chat = account.chats.create!(user: user, model: "test-model", provider: :openai, assume_model_exists: true)
      @adapter.prompt_messages = [ { "role" => "user", "content" => media_block("image", "image/png", "persisted image") } ]
      RubyLLM::MCP::Prompt.new(@adapter, "name" => "demo").include(chat)
      resource = RubyLLM::MCP::Resource.new(@adapter, "name" => "report", "uri" => "file:///report", "mimeType" => "application/pdf",
        "content_response" => { "blob" => Base64.strict_encode64("persisted pdf") })
      resource.include(chat)
      messages = chat.messages.reload.to_a
      assert_equal 2, messages.size
      assert_equal [ "persisted image", "persisted pdf" ], messages.map { |message| message.attachments.first.download }
      assert_equal [ "image/png", "application/pdf" ], messages.map { |message| message.attachments.first.content_type }
      assert_equal "report: ", messages.last.content
    end
  end

  test "resource inclusion on plain chats keeps text and blob data separate" do
    chat = plain_chat
    resource = RubyLLM::MCP::Resource.new(@adapter, "name" => "note", "description" => "notes", "uri" => "file:///note",
      "content_response" => { "text" => "resource text" })
    resource.include(chat)
    assert_equal "note: notes\n\nresource text", chat.messages.last.content
    assert_empty chat.messages.last.attachments
  end

  test "sample and sampling handler convert system text image and audio messages" do
    [ nil, SamplingHandler ].each do |handler|
      coordinator = CannedCoordinator.new
      coordinator.sampling_callback = handler
      sample = sampling_request(coordinator)
      chat = plain_chat
      response = RubyLLM::Message.new(role: :assistant, content: "canned reply")
      chat.define_singleton_method(:complete) { response }
      previous_model = RubyLLM::MCP.config.sampling.preferred_model
      RubyLLM::MCP.config.sampling.preferred_model = "test-model"
      original_new = RubyLLM::Chat.method(:new)
      RubyLLM::Chat.define_singleton_method(:new) { |**_| chat }
      begin
        sample.execute
        assert_empty coordinator.errors
        assert_equal response, coordinator.responses.first.fetch(:message)
        assert_equal [ :system, :user, :user, :assistant ], chat.messages.map(&:role)
        assert_equal [ "system instructions", "sample text", nil, nil ], chat.messages.map(&:content)
        assert_equal [ "sample image", "sample audio" ], chat.messages.flat_map(&:attachments).map(&:content)
      ensure
        RubyLLM::Chat.define_singleton_method(:new, original_new)
        RubyLLM::MCP.config.sampling.preferred_model = previous_model
      end
    end
  end

  test "sampling rejection still avoids completion and returns coordinator error" do
    coordinator = CannedCoordinator.new
    coordinator.sampling_callback = ->(_) { false }
    sampling_request(coordinator).execute
    assert_empty coordinator.responses
    assert_equal "Sampling request was rejected", coordinator.errors.first.fetch(:message)
  end

  test "sampling response formatter uses actual message fields and base64 wire data" do
    formatter = RubyLLM::MCP::Native::Messages::Responses
    response = formatter.sampling_create_message(id: "sample", model: "test-model",
      message: RubyLLM::Message.new(role: :assistant, content: "answer", finish_reason: :max_tokens))
    assert_equal({ type: "text", text: "answer" }, response.dig(:result, :content))
    assert_equal "maxTokens", response.dig(:result, :stopReason)

    attachment = RubyLLM::MCP::Attachment.new(Base64.strict_encode64("response audio"), "audio/wav")
    response = formatter.sampling_create_message(id: "audio", model: "test-model",
      message: RubyLLM::Message.new(role: :assistant, content: nil, attachments: [ attachment ]))
    assert_equal({ type: :audio, data: Base64.strict_encode64("response audio"), mimeType: "audio/wav" }, response.dig(:result, :content))
    assert_equal "endTurn", response.dig(:result, :stopReason)
  end

  test "sampling responses do not silently drop mixed text and multiple files" do
    attachments = [ "one", "two" ].map { |bytes| RubyLLM::MCP::Attachment.new(Base64.strict_encode64(bytes), "image/png") }
    response = RubyLLM::MCP::Native::Messages::Responses.sampling_create_message(id: "mixed", model: "test-model",
      message: RubyLLM::Message.new(role: :assistant, content: "caption", attachments: attachments))
    assert_equal [ { type: "text", text: "caption" },
      { type: :image, data: Base64.strict_encode64("one"), mimeType: "image/png" },
      { type: :image, data: Base64.strict_encode64("two"), mimeType: "image/png" } ], response.dig(:result, :content)
  end

  test "older sampling protocols retain single blocks but explicitly reject multiple blocks" do
    formatter = RubyLLM::MCP::Native::Messages::Responses
    single = RubyLLM::Message.new(role: :assistant, content: "answer")
    response = formatter.sampling_create_message(id: "legacy", model: "test-model", message: single, protocol_version: "2025-06-18")
    assert_equal({ type: "text", text: "answer" }, response.dig(:result, :content))
    attachment = RubyLLM::MCP::Attachment.new(Base64.strict_encode64("image"), "image/png")
    mixed = RubyLLM::Message.new(role: :assistant, content: "caption", attachments: [ attachment ])
    error = assert_raises(RubyLLM::MCP::Errors::InvalidFormatError) do
      formatter.sampling_create_message(id: "legacy", model: "test-model", message: mixed, protocol_version: "2025-06-18")
    end
    assert_match(/2025-11-25/, error.message)
  end

  private
    def sampling_request(coordinator)
      result = RubyLLM::MCP::Result.new({ "id" => "sample", "method" => "sampling/createMessage", "params" => {
        "systemPrompt" => "system instructions", "maxTokens" => 100,
        "modelPreferences" => { "hints" => [ { "name" => "test-model" } ] },
        "messages" => [
          { "role" => "user", "content" => text_block("sample text") },
          { "role" => "user", "content" => media_block("image", "image/png", "sample image") },
          { "role" => "assistant", "content" => media_block("audio", "audio/wav", "sample audio") }
        ]
      } })
      RubyLLM::MCP::Sample.new(result, coordinator)
    end

    def plain_chat
      RubyLLM::Chat.new(model: "test-model", provider: :openai, assume_model_exists: true)
    end

    def remote_tool(input_schema: { "type" => "object", "properties" => {} }, output_schema: nil)
      RubyLLM::MCP::Tool.new(@adapter, { "name" => "lookup", "description" => "Lookup", "inputSchema" => input_schema, "outputSchema" => output_schema })
    end

    def canned_result(blocks, extra = {})
      @adapter.result = RubyLLM::MCP::Result.new({ "result" => { "content" => blocks }.merge(extra) })
    end

    def text_block(text)
      { "type" => "text", "text" => text }
    end

    def media_block(type, mime_type, bytes)
      { "type" => type, "mimeType" => mime_type, "data" => Base64.strict_encode64(bytes) }
    end
end
