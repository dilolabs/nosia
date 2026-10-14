# frozen_string_literal: true

module RubyLLM
  module MCP
    # Bridge-owned value, converted explicitly at RubyLLM's message/tool boundary.
    class Content
      attr_reader :text, :attachments

      # @param text [String, nil] message text
      # @param attachments [RubyLLM::Attachment, Array<RubyLLM::Attachment>, nil] decoded files
      # @raise [ArgumentError] if an attachment is not already a RubyLLM attachment
      def initialize(text: nil, attachments: nil)
        @text = text
        @attachments = (attachments.is_a?(Array) ? attachments : [attachments]).compact
        unless @attachments.all? { |attachment| attachment.is_a?(RubyLLM::Attachment) }
          raise ArgumentError, "MCP content requires RubyLLM::Attachment objects, not paths or URLs"
        end
      end

      # @return [String, Array<String, RubyLLM::Attachment>, nil] a RubyLLM 2 tool result
      def to_tool_result
        attachments.empty? ? text : [text, *attachments].compact
      end

      # @param role [String, Symbol] the message role
      # @return [RubyLLM::Message] text and files in their separate 2.0 fields
      def to_message(role:)
        RubyLLM::Message.new(role: role, content: text, attachments: attachments)
      end

      # @return [String] the bridge's text for display, not a tool-loop result
      def to_s
        text.to_s
      end
    end
  end
end
