# frozen_string_literal: true

module Api
  module V1
    class ApplicationController < ApplicationController
      allow_unauthenticated_access
      skip_before_action :verify_authenticity_token
      before_action :verify_api_key

      private

      def verify_api_key
        authenticate_or_request_with_http_token do |token, _options|
          api_token = ApiToken.find_by(token:)
          @user = api_token&.user
          if params[:user].present?
            @account = @user.accounts.create_with(name: params[:user], owner: @user).find_or_create_by(uid: params[:user])
          else
            @account = api_token&.account
          end
        end
      end
    end
  end
end
