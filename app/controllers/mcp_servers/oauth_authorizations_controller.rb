# Starts native consent or forgets the acting member's local grant.
class McpServers::OauthAuthorizationsController < ApplicationController
  include McpScoped

  prepend_before_action :set_mcp_oauth_privacy_headers
  before_action :set_mcp_server
  before_action :require_oauth_configuration
  rescue_from ActionController::InvalidAuthenticityToken do
    head :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end

  # @return [void] Redirects to a validated provider consent page
  def create
    origin = oauth_app_origin
    return redirect_oauth(:invalid_origin) unless origin

    grant = @mcp_server.begin_oauth_grant_for!(Current.user)
    redirect_uri = "#{origin}#{mcp_oauth_callback_path}"
    grant.with_client do |client|
      if client.authorized?
        redirect_oauth(:already_authorized)
      else
        redirect_to_consent(client.authorization_url(redirect_uri:), grant)
      end
    end
  rescue McpAuthorization::Unavailable, McpAuthorization::InsufficientScope => error
    redirect_oauth(McpAuthorization.failure_reason(error))
  end

  # @return [void] Retires only the current member's authorization
  def destroy
    @mcp_server.disconnect!(user: Current.user)
    redirect_oauth(:disconnected, notice: true)
  rescue McpAuthorization::Unavailable => error
    redirect_oauth(McpAuthorization.failure_reason(error))
  end

  private
    def require_oauth_configuration
      redirect_oauth(:invalid_configuration) unless @mcp_server.oauth_configuration?
    end

    def redirect_to_consent(url, grant)
      uri, = McpOutbound.destination!(url, https_only: true)
      states = URI.decode_www_form(uri.query.to_s).filter_map { |key, value| value if key == "state" }
      raise McpOutbound::Blocked unless states.one? && states.first.present?

      remember_oauth_attempt(states.first, grant)
      request.set_header("action_dispatch.redirect_filter", [ url ])
      redirect_to url, allow_other_host: true, status: :see_other
    rescue McpOutbound::Blocked, ArgumentError
      redirect_oauth(:unsafe_consent)
    end
end
