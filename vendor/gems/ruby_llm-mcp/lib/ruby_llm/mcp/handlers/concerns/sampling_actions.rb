# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides action methods and utilities for sampling request handlers
        module SamplingActions
          attr_reader :sample

          protected

          # Accept the sampling request with a response
          # @param response [Object] the chat response to return
          # @return [Hash] structured acceptance response
          def accept(response)
            { accepted: true, response: response }
          end

          # Reject the sampling request
          # @param message [String] reason for rejection
          # @return [Hash] structured rejection response
          def reject(message)
            { accepted: false, message: message }
          end

          # Override guard_failed to return rejection (if GuardChecks is included)
          def guard_failed(message)
            reject(message)
          end

          # Request one explicit sampling generation, including assistant-prefilled histories.
          # @param model [String] the model to use
          # @return [RubyLLM::Message] generated sampling response
          def default_chat_completion(model)
            chat = RubyLLM::Chat.new(model: model)

            if sample.system_prompt
              chat.add_message(system_message)
            end

            sample.raw_messages.each do |message|
              chat.add_message(create_message(message))
            end

            chat.generate
          end

          private

          # Create a RubyLLM message from raw message data
          def create_message(message)
            role = message["role"]
            content = create_content_for_message(message["content"])
            content.to_message(role: role)
          end

          # Create content object for message
          def create_content_for_message(content)
            case content["type"]
            when "text"
              MCP::Content.new(text: content["text"])
            when "image", "audio"
              attachment = MCP::Attachment.new(content["data"], content["mimeType"])
              MCP::Content.new(text: nil, attachments: [attachment])
            else
              raise RubyLLM::MCP::Errors::InvalidFormatError.new(
                message: "Invalid content type: #{content['type']}"
              )
            end
          end

          # Create system message structure
          def system_message
            MCP::Content.new(text: sample.system_prompt).to_message(role: "system")
          end
        end
      end
    end
  end
end
