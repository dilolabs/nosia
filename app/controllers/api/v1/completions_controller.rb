# frozen_string_literal: true

module Api
  module V1
    class CompletionsController < ApplicationController
      include ActionController::Live

      def create
        @chat = @user.chats.create(account: @account)

        max_tokens = completion_params[:max_tokens]&.to_i
        model = completion_params[:model]
        temperature = completion_params[:temperature]&.to_f
        top_k = completion_params[:top_k]&.to_f
        top_p = completion_params[:top_p]&.to_f

        if completion_params[:messages].present?
          last_message = completion_params[:messages].pop
          prompt = last_message[:content]

          completion_params[:messages].each do |message_params|
            @chat.messages.create(
              content: message_params[:content],
              response_number: @chat.messages.count,
              role: message_params[:role]
            )
          end
        elsif completion_params[:prompt].present?
          prompt = completion_params[:prompt]
        end

        stream_response = ActiveModel::Type::Boolean.new.cast(params[:stream]) || false

        if stream_response
          chat_response = @chat.complete_with_nosia(prompt, model:, temperature:, top_k:, top_p:, max_tokens:) do |stream|
            stream_content = stream.dig("delta", "content")
            next unless stream_content
            done = !!stream.dig("finish_reason")
            if done
              response.stream.write("data: [DONE]\n\n")
            else
              data = {
                choices: [
                  delta: {
                    content: stream_content,
                    role: "assistant"
                  },
                  finish_reason: done ? "stop" : nil,
                  index: 0
                ],
                created: Time.now.to_i,
                id: "chatcmpl-#{@chat.id}",
                model: "nosia:#{ENV["LLM_MODEL"]}",
                object: "chat.completion.chunk",
                system_fingerprint: "fp_nosia"
              }
              response.stream.write("data: #{data.to_json}\n\n")
            end
          end
        else
          chat_response = @chat.complete_with_nosia(prompt, model:, temperature:, top_k:, top_p:, max_tokens:)
          render json: {
            choices: [
              finish_reason: "stop",
              index: 0,
              message: {
                content: chat_response.content,
                role: "assistant"
              }
            ],
            created: Time.now.to_i,
            id: "chatcmpl-#{@uuid}",
            model: "nosia:#{ENV["LLM_MODEL"]}",
            object: "chat.completion",
            system_fingerprint: "fp_nosia"
          }
        end
      ensure
        response.stream.close if response.stream.respond_to?(:close)
      end

      private

      def completion_params
        params.permit(
          :max_tokens,
          :model,
          :prompt,
          :stream,
          :top_k,
          :top_p,
          :temperature,
          :user,
          messages: [
            :content,
            :role
          ],
          stop: [],
          chat: {},
          completion: {},
        )
      end
    end
  end
end
