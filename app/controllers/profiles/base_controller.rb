class Profiles::BaseController < ApplicationController
  CREDENTIAL_RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  before_action :prepare_profile
  before_action :limit_credential_changes, if: -> { action_name == "update" }

  rescue_from ActionController::ParameterMissing do
    response.headers["Cache-Control"] = "no-store"
    head :bad_request
  end

  rescue_from ActionController::InvalidAuthenticityToken do
    response.headers["Cache-Control"] = "no-store"
    head :unprocessable_entity
  end

  private
    def prepare_profile
      @user = Current.user
      response.headers["Cache-Control"] = "no-store"
    end

    def limit_credential_changes
      count = CREDENTIAL_RATE_LIMIT_STORE.increment("profile-credentials:#{@user.id}", 1, expires_in: 3.minutes)
      if count > 10
        @failed_section = controller_name.singularize.to_sym
        @user.errors.add(:base, :profile_rate_limited)
        render "profiles/show", status: :too_many_requests
      end
    end
end
