# Browser-side binding for a pending native OAuth attempt, not a credential store.
module McpOauthFlow
  extend ActiveSupport::Concern

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
      redirect_within_oauth_workspace(path, (notice ? :notice : :alert) => mcp_oauth_text(reason))
    end

    def redirect_within_oauth_workspace(path, feedback)
      redirect_to_internal_workspace_path(path, feedback, origin: oauth_app_origin)
    end

    def redirect_to_internal_workspace_path(path, feedback, origin: nil)
      raise ArgumentError, "Expected an internal workspace path" unless %r{\A/(?!/)[^\\?#[:cntrl:]]*\z}.match?(path)

      set_mcp_oauth_privacy_headers
      feedback.each { |key, value| flash[key] = value }
      # redirect_to would expand an internal path using incoming Host headers.
      response.location = "#{origin}#{path}"
      head :see_other
    end

    def oauth_app_origin
      return @oauth_app_origin if defined?(@oauth_app_origin)

      @oauth_app_origin = verified_oauth_app_origin
    end

    def verified_oauth_app_origin
      raw = ENV["NOSIA_URL"]
      return unless raw&.start_with?("https://")

      uri = McpOutbound.endpoint!(raw, https_only: true)
      return unless uri.query.nil? && [ "", "/" ].include?(uri.path)

      McpOutbound.check_literal!(uri)
      McpOutbound.destination!(raw, https_only: true)
      uri.origin
    rescue McpOutbound::Blocked
      nil
    end
end
