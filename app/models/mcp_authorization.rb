# One member's native OAuth owner for one saved connector identity.
class McpAuthorization < ApplicationRecord
  class Unavailable < McpServer::Client::Error
    def initialize
      super("MCP authorization is unavailable")
    end
  end

  belongs_to :account
  belongs_to :account_user
  belongs_to :mcp_server

  encrypts :endpoint, support_unencrypted_data: false
  attr_readonly :account_id, :account_user_id, :mcp_server_id, :endpoint

  validate :matching_connector_and_membership, on: :create
  before_create :lock_and_validate_identity

  def client
    McpServer::Client.new(grant: self)
  end

  def authorized?
    client.authorized?
  rescue Unavailable
    false
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

      # A single database snapshot checks the grant, membership and saved
      # connector together, including retirement that commits before admission.
      member = AccountUser.where(id: account_user_id, account_id:)
      current = identity_scope.where(id:, reconnect_required_at: nil).where(member.arel.exists)
      connector = McpServer.unscoped.where(id: mcp_server_id, account_id:).where(current.arel.exists).take
      raise Unavailable unless connector&.oauth_configuration? && connector.effective_endpoint == endpoint
    end
  end

  def lock_identity
    self.class.uncached { identity_scope.lock.find_by(id:) }
  end

  # Called only after the native exchange has unwound its transaction.
  def mark_reconnect_required(fingerprint, &fingerprint_for)
    self.class.transaction do
      if (current = lock_identity) && current.reconnect_required_at.nil?
        stored = CredentialStore.new(current).owned_credential
        if stored && ActiveSupport::SecurityUtils.secure_compare(fingerprint, fingerprint_for.call(stored))
          current.update!(reconnect_required_at: Time.current)
        end
      end
    end
  end

  private
    def identity_scope
      self.class.where(account_id:, account_user_id:, mcp_server_id:)
    end

    def matching_connector_and_membership
      self.class.uncached do
        connector = McpServer.unscoped.find_by(id: mcp_server_id, account_id:)
        unless connector&.oauth_configuration? && connector.effective_endpoint == endpoint &&
            AccountUser.exists?(id: account_user_id, account_id:)
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
