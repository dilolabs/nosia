# Accepts a provider response only for a matching signed-in browser attempt.
class McpServers::OauthCallbacksController < ApplicationController
  include McpOauthFlow
  include McpWorkspaceHelper

  # @return [void] Redirects to the original authorized connector or a safe fallback
  def show
    return head :method_not_allowed unless request.get?

    arguments, scalar = request.get_header(McpOauthCallbackQuery::ENV_KEY) || [ {}, false ]
    attempt = take_oauth_attempt(arguments["state"])
    return redirect_oauth(:invalid_attempt) unless attempt

    account = Current.user.accounts.find_by(id: attempt.fetch("account_id"))
    return redirect_oauth(:invalid_attempt) unless account

    arguments = nil unless scalar && valid_callback?(arguments)
    ActsAsTenant.with_tenant(account) { complete_attempt(account, attempt, arguments) }
  rescue McpAuthorization::Unavailable, McpAuthorization::InsufficientScope => error
    redirect_oauth(McpAuthorization.failure_reason(error, fallback: :failed))
  end

  private
    def request_authentication
      # Never store the callback URL as the URL to resume after sign-in.
      redirect_oauth(:invalid_attempt)
    end

    def complete_attempt(account, attempt, arguments)
      @mcp_server = account.mcp_servers.find_by(id: attempt.fetch("server_id"))
      grant = @mcp_server&.oauth_grant_for(Current.user)
      return redirect_oauth(:invalid_attempt) unless grant&.id == attempt.fetch("grant_id")
      return redirect_oauth(:expired) if Time.current.to_i >= attempt.fetch("deadline")

      return redirect_oauth(:invalid_attempt) unless arguments

      grant.with_client { |client| client.authorize(arguments) }
      redirect_oauth(:authorized, notice: true)
    end

    def valid_callback?(arguments)
      (arguments.keys & %w[code error]).one? && (arguments["code"] || arguments["error"]).present?
    end
end
