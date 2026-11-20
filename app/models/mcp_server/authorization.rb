module McpServer::Authorization
  extend ActiveSupport::Concern

  CONNECTION_IDENTITY_FIELDS = %w[auth_mode transport_type endpoint connection_config account_id].freeze
  CONNECTION_CONFIGURATION_FIELDS = (CONNECTION_IDENTITY_FIELDS + %w[auth_config]).freeze

  included do
    validates :auth_mode, inclusion: { in: %w[static oauth] }
    validate :validate_oauth_transport
    before_update :guard_connection_configuration_update
    before_destroy :retire_oauth_authorizations, prepend: true
  end

  def oauth? = auth_mode == "oauth"

  def oauth_configuration?
    oauth? && valid_oauth_endpoint?(transport_type, effective_endpoint)
  end

  def oauth_grant_for(user)
    return unless persisted? && user&.id

    self.class.uncached do
      grant = McpAuthorization.for_member(account_id:, mcp_server_id: id, user_id: user.id).find_with_saved_oauth_connector
      grant if grant&.matches_saved_connector?
    end
  end

  def begin_oauth_grant_for!(user)
    self.class.transaction do
      Account.lock.find(account_id)
      self.class.uncached do
        saved, member = oauth_identity_for(user)
        raise McpAuthorization::Unavailable unless saved && member

        grants = McpAuthorization.for_member(account_id:, mcp_server_id: id, user_id: user.id)
          .where(account_user_id: member.id)
        grant = grants.first
        if grant && (grant.reconnect_required_at || grant.endpoint != saved.effective_endpoint)
          grant.retire!
          grant = nil
        end
        grant || McpAuthorization.create!(account_id:, mcp_server: saved, account_user: member,
          user_id: user.id, endpoint: saved.effective_endpoint)
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise McpAuthorization::Unavailable, cause: nil
  end

  # @param user [User] Current member explicitly selected by the caller
  # @yieldparam connection [McpServer::Client] The acting member's usable client
  # @return [Object] The result of the operation
  # @raise [McpAuthorization::Unavailable] No matching usable authorization
  def with_authorized_oauth_client(user)
    grant = oauth_grant_for(user)
    raise McpAuthorization::AuthorizationRequired unless grant
    raise McpAuthorization::ReconnectRequired if grant.reconnect_required_at

    grant.with_client do |connection|
      raise McpAuthorization::AuthorizationRequired unless connection.authorized?

      yield connection
    end
  end

  private
    def validate_oauth_transport
      errors.add(:auth_mode, :oauth_transport_required) if oauth? && !oauth_configuration?
    end

    def valid_oauth_endpoint?(transport, endpoint)
      return false unless transport == "streamable"

      McpOutbound.check_literal!(McpOutbound.endpoint!(endpoint, https_only: true))
      true
    rescue McpOutbound::Blocked
      false
    end

    def oauth_identity_for(user)
      return unless persisted? && user&.id

      saved = self.class.unscoped.find_by(id:, account_id:)
      if saved&.oauth_configuration?
        [ saved, AccountUser.find_by(account_id:, user_id: user.id) ]
      end
    end

    def guard_connection_configuration_update
      return unless @workspace_editing_auth_mode || CONNECTION_CONFIGURATION_FIELDS.any? { |name| will_save_change_to_attribute?(name) }

      previous_account = account_id_in_database
      Account.where(id: [ previous_account, account_id ]).order(:id).lock.load
      saved = self.class.uncached { self.class.unscoped.find_by!(id:, account_id: previous_account) }
      saved_identity = [ saved.auth_mode, saved.transport_type, saved.effective_endpoint, saved.account_id ]
      if stale_connection_configuration?(saved, saved_identity)
        errors.add(:base, :workspace_configuration_changed)
        throw :abort
      end

      resulting_identity = oauth_identity_after_update(saved)
      mode, transport, endpoint = resulting_identity
      if mode == "oauth" && !valid_oauth_endpoint?(transport, endpoint)
        errors.add(:auth_mode, :oauth_transport_required)
        throw :abort
      end
      retire_oauth_authorizations if resulting_identity != saved_identity
    end

    def stale_connection_configuration?(saved, saved_identity)
      # Compare against what the editor loaded, not the submitted destination
      # mode: an unchanged value is omitted from Rails' partial UPDATE.
      loaded_endpoint = connection_config_in_database&.[]("url") || endpoint_in_database
      loaded_identity = [ auth_mode_in_database, transport_type_in_database, loaded_endpoint, account_id_in_database ]
      (@workspace_editing_auth_mode && @workspace_editing_auth_mode != saved.auth_mode) || loaded_identity != saved_identity ||
        (will_save_change_to_auth_config? && auth_config_in_database != saved.auth_config) ||
        (will_save_change_to_connection_config? && connection_config_in_database != saved.connection_config)
    end

    def oauth_identity_after_update(saved)
      mode, transport, endpoint, config, account = CONNECTION_IDENTITY_FIELDS.map do |name|
        will_save_change_to_attribute?(name) ? self[name] : saved[name]
      end
      [ mode, transport, config&.[]("url") || endpoint, account ]
    end

    def retire_oauth_authorizations
      previous_account = account_id_in_database
      Account.lock.find(previous_account)
      McpAuthorization.uncached do
        McpAuthorization.where(account_id: previous_account, mcp_server_id: id).find_each(&:retire!)
      end
    end
end
