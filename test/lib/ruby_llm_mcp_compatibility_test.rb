require "test_helper"
require "base64"

class RubyLlmMcpCompatibilityTest < ActiveSupport::TestCase
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
  end
end
