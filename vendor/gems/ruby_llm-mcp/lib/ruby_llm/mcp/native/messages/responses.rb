# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      module Messages
        # Response message builders
        # Responses are sent in reply to requests from the server
        module Responses
          extend Helpers

          module_function

          def ping(id:)
            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: {}
            }
          end

          def roots_list(id:, roots_paths:)
            roots_response = roots_paths.map do |path|
              {
                uri: "file://#{path}",
                name: File.basename(path, ".*")
              }
            end

            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: {
                roots: roots_response
              }
            }
          end

          def result(id:, value:)
            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: value
            }
          end

          # @param protocol_version [String] negotiated MCP version
          # @param id [String, Integer] sampling request ID
          # @param message [RubyLLM::Message] completion with separate text and files
          # @param model [String] completion model ID
          # @return [Hash] MCP sampling response, with wire-encoded attachments
          # @raise [Errors::InvalidFormatError] if a legacy protocol cannot represent all blocks
          def sampling_create_message(id:, message:, model:, protocol_version: Native::Protocol.latest_version)
            stop_reason = case message.finish_reason
                          when nil, :stop then "endTurn"
                          when :tool_calls then "toolUse"
                          else snake_to_camel(message.finish_reason.to_s)
                          end

            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: {
                role: message.role,
                content: format_content(message, protocol_version: protocol_version),
                model: model,
                stopReason: stop_reason
              }
            }
          end

          def elicitation(id:, action:, content: nil)
            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              result: {
                action: action,
                content: content
              }.compact
            }
          end

          def error(id:, message:, code: JsonRpc::ErrorCodes::SERVER_ERROR, data: nil)
            error_object = {
              code: code,
              message: message
            }
            error_object[:data] = data if data

            {
              jsonrpc: JSONRPC_VERSION,
              id: id,
              error: error_object
            }
          end

          def format_content(message, protocol_version:)
            blocks = []
            blocks << { type: "text", text: message.content } unless message.content.to_s.empty?
            blocks.concat(message.attachments.map do |attachment|
              { type: attachment.type, data: attachment.encoded, mimeType: attachment.mime_type }
            end)
            return { type: "text", text: message.content } if blocks.empty?

            if blocks.length > 1 && (Native::Protocol.compare_date_versions(protocol_version, "2025-11-25") || -1) < 0
              raise Errors::InvalidFormatError.new(message: "Multiple sampling content blocks require MCP 2025-11-25 or newer")
            end

            blocks.length == 1 ? blocks.first : blocks
          end
          private_class_method :format_content

          def snake_to_camel(str)
            parts = str.split("_")
            parts.first + parts[1..].map(&:capitalize).join
          end
          private_class_method :snake_to_camel
        end
      end
    end
  end
end
