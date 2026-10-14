# frozen_string_literal: true

module RubyLLM
  module MCP
    class Attachment < RubyLLM::Attachment
      attr_reader :content, :mime_type

      def initialize(content, mime_type) # rubocop:disable Lint/MissingSuper
        @content = content
        @mime_type = mime_type
      end

      def encoded
        @content
      end
    end
  end
end
