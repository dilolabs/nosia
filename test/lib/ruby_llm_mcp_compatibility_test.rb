require "test_helper"
require "base64"

class RubyLlmMcpCompatibilityTest < ActiveSupport::TestCase
  test "loads the exact RubyLLM 2.0 release" do
    assert_equal Gem::Version.new("2.0.0"), Gem.loaded_specs.fetch("ruby_llm").version
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
