# frozen_string_literal: true

require "base64"
require "stringio"

module RubyLLM
  module MCP
    # Decodes MCP wire data into an in-memory RubyLLM attachment.
    class Attachment < RubyLLM::Attachment
      # @param content [String] strict base64 from the MCP wire response
      # @param mime_type [String] the server-declared MIME type
      # @raise [ArgumentError] if content is not valid base64
      def initialize(content, mime_type)
        super(StringIO.new(Base64.strict_decode64(content)), filename: "mcp-attachment")
        @mime_type = mime_type
      end
    end
  end
end
