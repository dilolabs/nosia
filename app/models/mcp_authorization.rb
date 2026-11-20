# One member's native OAuth owner for one saved connector identity.
class McpAuthorization < ApplicationRecord
  # Workspace actions should localize by type, not by exception text.
  class Unavailable < McpServer::Client::Error
    def initialize(message = "MCP authorization is unavailable")
      super
    end
  end

  # Reconnect only when loss is confirmed for the current credential version.
  class ReconnectRequired < Unavailable
    def initialize
      super("MCP authorization requires reconnection")
    end
  end

  class InsufficientScope < McpServer::Client::Error
    def initialize
      super("MCP authorization has insufficient scope")
    end
  end

  # No current grant, or the current grant has not completed consent.
  class AuthorizationRequired < Unavailable; end
  # RubyLLM verified the callback and the provider reported access_denied.
  class ConsentRefused < Unavailable; end
  # The provider does not offer automatic client registration.
  class RegistrationUnsupported < Unavailable; end
  # The provider advertised a consent URL that fails the outbound policy.
  class UnsafeConsent < Unavailable; end

  belongs_to :account
  belongs_to :account_user
  belongs_to :mcp_server
  belongs_to :user, default: -> { account_user&.user }

  encrypts :endpoint, support_unencrypted_data: false
  attr_readonly :account_id, :account_user_id, :mcp_server_id, :user_id, :endpoint

  validate :matching_connector_and_membership, on: :create
  before_create :lock_and_validate_identity

  # @param error [McpServer::Client::Error] Sanitized application error
  # @param fallback [Symbol] App-defined reason for an unclassified failure
  # @return [Symbol] Translation key, never provider-supplied text
  def self.failure_reason(error, fallback: :unavailable)
    case error
    when ReconnectRequired then :reconnect_needed
    when InsufficientScope then :insufficient_scope
    when AuthorizationRequired then :authorization_needed
    when ConsentRefused then :declined
    when RegistrationUnsupported then :registration_unsupported
    when UnsafeConsent then :unsafe_consent
    else fallback
    end
  end

  def self.for_member(account_id:, mcp_server_id:, user_id:)
    joins(:account_user).where(account_id:, mcp_server_id:, user_id:, account_users: { account_id:, user_id: })
  end

  def self.find_with_saved_oauth_connector
    # Callers explicitly scope the account even when Current's active account
    # differs from the grant's (e.g. a callback or retained client).
    McpServer.unscoped do
      eager_load(:mcp_server).where(mcp_servers: { auth_mode: "oauth", transport_type: "streamable" })
        .where(arel_table[:account_id].eq(McpServer.arel_table[:account_id])).take
    end
  end

  def client
    McpServer::Client.new(grant: self)
  end

  def authorized?
    with_client(&:authorized?)
  rescue Unavailable
    false
  end

  # @return [String] Local grant state without constructing a native client or refreshing
  def workspace_state
    admit!
    store = CredentialStore.new(self)
    store.verify_schema!
    store.owned_data.to_h["access_token"].present? ? "authorized" : "authorization_required"
  rescue ReconnectRequired
    "reconnect_required"
  rescue Unavailable, ActiveRecord::Encryption::Errors::Base
    "authorization_required"
  end

  # @yieldparam connection [McpServer::Client] The native client for one operation
  # @return [Object] The result of the operation
  def with_client
    connection = client
    yield connection
  ensure
    connection&.close
  end

  # @yieldparam connection [McpServer::Client] The connection for this exact grant
  # @return [Object] The operation result
  # @raise [Unavailable] The grant is missing usable credentials or was retired
  def with_authorized_client
    raise ReconnectRequired if reconnect_required_at

    with_client do |connection|
      raise AuthorizationRequired unless connection.authorized?

      yield connection
    end
  end

  # Native OAuth takes its own per-key mutex before entering the store. Take the
  # grant lock there, not here, so retirement cannot deadlock with a refresh.
  def retire!
    self.class.transaction do
      Account.lock.find(account_id)
      store = CredentialStore.new(self, retiring: true)
      McpServer::Client.new(grant: self, credential_store: store).deauthorize
    end
  end

  # No association cache or database row lock on the ordinary socket path.
  def admit!
    self.class.uncached do
      raise Unavailable unless persisted? && !has_changes_to_save?

      current = self.class.for_member(account_id:, mcp_server_id:, user_id:)
        .where(id:, account_user_id:).find_with_saved_oauth_connector
      unless current&.matches_saved_connector? && current.endpoint == endpoint
        raise Unavailable
      end
      raise ReconnectRequired if current.reconnect_required_at
    end
  end

  def matches_saved_connector?
    mcp_server&.oauth_configuration? && mcp_server.effective_endpoint == endpoint
  end

  def lock_identity
    self.class.uncached { identity_scope.lock.find_by(id:) }
  end

  # Called only after the native exchange has unwound its transaction.
  def mark_reconnect_required(fingerprint, &fingerprint_for)
    self.class.transaction do
      if (current = lock_identity)
        stored = CredentialStore.new(current).owned_credential
        if stored && ActiveSupport::SecurityUtils.secure_compare(fingerprint, fingerprint_for.call(stored))
          current.update!(reconnect_required_at: Time.current) unless current.reconnect_required_at
          true
        end
      end
    end
  end

  private
    def identity_scope
      self.class.where(account_id:, account_user_id:, mcp_server_id:, user_id:)
    end

    def matching_connector_and_membership
      self.class.uncached do
        connector = McpServer.unscoped.find_by(id: mcp_server_id, account_id:)
        unless connector&.oauth_configuration? && connector.effective_endpoint == endpoint &&
            AccountUser.exists?(id: account_user_id, account_id:, user_id:)
          errors.add(:base, "MCP authorization requires matching connector and account membership")
        end
      end
    end

    def lock_and_validate_identity
      Account.lock.find(account_id)
      matching_connector_and_membership
      throw :abort if errors.any?
    end
end
