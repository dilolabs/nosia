# frozen_string_literal: true

module Api
  module V1
    class QnasController < ApplicationController
      def create
        qna = @account.qnas.new(qna_params)

        if qna.save
          AddQnaJob.perform_later(qna.id)

          response = {
            id: qna.id
          }

          render json: response
        else
          render json: {}
        end
      end

      private

      def qna_params
        params.permit(:answer, :question, :user)
      end
    end
  end
end
