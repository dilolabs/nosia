# frozen_string_literal: true

module Api
  module V1
    class WebsitesController < ApplicationController
      def create
        website = @account.websites.new(website_params)

        if website.save
          CrawlWebsiteUrlsJob.perform_later(website.id)

          response = {
            id: website.id
          }

          render json: response
        else
          render json: {}
        end
      end

      private

      def website_params
        params.permit(:url, :user)
      end
    end
  end
end
