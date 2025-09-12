# frozen_string_literal: true

module Api
  module V1
    class TextsController < ApplicationController
      def create
        text = @account.texts.new(text_params)

        if text.save
          AddTextJob.perform_later(text.id)

          response = {
            id: text.id
          }

          render json: response
        else
          render json: {}
        end
      end

      private

      def text_params
        params.permit(:data, :user)
      end
    end
  end
end
