# Browser-side binding for a pending native OAuth attempt, not a credential store.
module McpOauthFlow
  extend ActiveSupport::Concern

  included do
    prepend_before_action :set_mcp_oauth_privacy_headers
  end

  private
    def set_mcp_oauth_privacy_headers
      no_store
      response.set_header("Referrer-Policy", "no-referrer")
    end

    def remember_oauth_attempt(state, grant)
      digest = Digest::SHA256.hexdigest(state)
      attempts = oauth_attempts.except(digest)
      attempts[digest] = {
        "account_id" => grant.account_id, "server_id" => grant.mcp_server_id, "grant_id" => grant.id,
        "session_id" => Current.session.id, "deadline" => 10.minutes.from_now.to_i
      }
      session[:mcp_oauth_attempts] = attempts.to_a.last(5).to_h
    end

    def take_oauth_attempt(state)
      if state.is_a?(String) && state.present?
        digest = Digest::SHA256.hexdigest(state)
        attempt = oauth_attempts[digest]
        if attempt && attempt["session_id"] == Current.session.id
          session[:mcp_oauth_attempts] = oauth_attempts.except(digest)
          attempt
        end
      end
    end

    def oauth_attempts = session[:mcp_oauth_attempts] || {}

    def redirect_oauth(reason, notice: false)
      path = @mcp_server ? account_mcp_server_path(@mcp_server.account_id, @mcp_server) : root_path
      redirect_to path, status: :see_other, flash: { (notice ? :notice : :alert) => mcp_oauth_text(reason) }, allow_other_host: false
    end
end
