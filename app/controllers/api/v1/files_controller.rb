# frozen_string_literal: true

module Api
  module V1
    class FilesController < ApplicationController
      def create
        document = @account.documents.new(document_params)

        if document.save
          AddDocumentJob.perform_later(document.id)

          response = {
            id: document.id,
            object: "file",
            bytes: 0, # FIXME
            created_at: Time.zone.now.to_i,
            filename: document.title,
            purpose: document.purpose
          }

          render json: response
        else
          render json: {}
        end
      end

      private

      def document_params
        params.permit(:file, :purpose, :user)
      end
    end
  end
end
