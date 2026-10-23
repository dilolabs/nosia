# frozen_string_literal: true

module Api
  module V1
    class ApplicationController < ApplicationController
      RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

      allow_unauthenticated_access
      skip_before_action :verify_authenticity_token
      before_action :verify_api_key

      # A valid token can otherwise drive unbounded LLM spend and crawling.
      # Dedicated memory store: the default Rails.cache is NullStore in tests,
      # and a per-process ceiling is the conservative direction anyway.
      rate_limit to: 300, within: 1.minute, by: -> { request.remote_ip },
        store: RATE_LIMIT_STORE,
        with: -> { render json: { error: "Rate limit exceeded" }, status: :too_many_requests }

      private

      def request_locale
        :en
      end

      def locale_varies_by_request?
        false
      end

      # Bearer-token authentication. Fails closed: an unknown token gets a 401,
      # never a silent fallthrough into nil-user code paths.
      def verify_api_key
        authenticate_or_request_with_http_token do |given_token, _options|
          api_token = ApiToken.authenticate_token(given_token)
          unless api_token&.user
            render json: { error: "Unauthorized" }, status: :unauthorized
            return
          end

          @user = api_token.user
          @account = if params[:user].present?
            @user.accounts.create_with(name: params[:user], owner: @user)
              .find_or_create_by(uid: params[:user])
          else
            api_token.account
          end
          true
        end
      end
    end
  end
end
