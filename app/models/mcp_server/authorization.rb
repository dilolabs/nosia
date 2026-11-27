module McpServer::Authorization
  extend ActiveSupport::Concern

  CONNECTION_IDENTITY_FIELDS = %w[auth_mode transport_type endpoint connection_config account_id].freeze
  CONNECTION_CONFIGURATION_FIELDS = (CONNECTION_IDENTITY_FIELDS + %w[auth_config]).freeze
  CONNECTION_DIAGNOSTIC_METADATA = %w[last_test_at tools_cache prompts_cache resources_cache capabilities server_info].freeze

  included do
    validates :auth_mode, inclusion: { in: %w[static oauth] }
    validate :validate_oauth_transport
    before_update :guard_connection_configuration_update
    before_destroy :retire_oauth_authorizations, prepend: true
  end

  def oauth? = auth_mode == "oauth"

  # @return [Boolean] Whether the mode and endpoint meet OAuth's configuration rules
  def oauth_configuration?
    oauth? && valid_oauth_endpoint?(transport_type, effective_endpoint)
  end

  # @param user [User, nil] The acting member, not the ambient tenant
  # @return [McpAuthorization, nil] A grant for this member and connector; it may need reconnecting
  def oauth_grant_for(user)
    return unless persisted? && user&.id

    self.class.uncached do
      grant = McpAuthorization.for_member(account_id:, mcp_server_id: id, user_id: user.id).find_with_saved_oauth_connector
      grant if grant&.matches_saved_connector?
    end
  end

  # Finds or creates this member's consent identity without contacting the provider.
  # @param user [User] The member initiating consent
  # @return [McpAuthorization] The current or replacement grant
  # @raise [McpAuthorization::Unavailable] The connector or membership is no longer valid
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
  def with_authorized_oauth_client(user, &operation)
    grant = oauth_grant_for(user)
    raise McpAuthorization::AuthorizationRequired unless grant

    grant.with_authorized_client(&operation)
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
      return unless @workspace_editing_connection_revision || @workspace_editing_auth_mode ||
        CONNECTION_CONFIGURATION_FIELDS.any? { |name| will_save_change_to_attribute?(name) }

      previous_account = account_id_in_database
      Account.where(id: [ previous_account, account_id ]).order(:id).lock.load
      saved = self.class.uncached { self.class.unscoped.find_by!(id:, account_id: previous_account) }
      saved_identity = [ saved.auth_mode, saved.transport_type, saved.effective_endpoint, saved.account_id ]
      if stale_connection_configuration?(saved, saved_identity)
        errors.add(:base, :workspace_configuration_changed)
        throw :abort
      end

      resulting_identity = oauth_identity_after_update(saved)
      mode, transport, endpoint, resulting_account = resulting_identity
      if mode == "oauth" && !valid_oauth_endpoint?(transport, endpoint)
        errors.add(:auth_mode, :oauth_transport_required)
        throw :abort
      end
      if transport == "streamable" && (endpoint != saved.effective_endpoint || resulting_account != saved.account_id)
        remove_previous_destination_credentials(saved)
      end
      retire_oauth_authorizations if resulting_identity != saved_identity
      if resulting_identity != saved_identity || connection_credentials_changed?(saved)
        invalidate_connection_diagnostics(saved)
      end
    end

    def stale_connection_configuration?(saved, saved_identity)
      # Compare against what the editor loaded, not the submitted destination
      # mode: an unchanged value is omitted from Rails' partial UPDATE.
      loaded_endpoint = connection_config_in_database&.[]("url") || endpoint_in_database
      loaded_identity = [ auth_mode_in_database, transport_type_in_database, loaded_endpoint, account_id_in_database ]
      (@workspace_editing_connection_revision && !ActiveSupport::SecurityUtils.secure_compare(@workspace_editing_connection_revision, saved.workspace_connection_revision)) ||
        (@workspace_editing_auth_mode && @workspace_editing_auth_mode != saved.auth_mode) ||
        connection_revision_in_database != saved.connection_revision || loaded_identity != saved_identity ||
        (will_save_change_to_endpoint? && endpoint_in_database != saved.endpoint) ||
        (will_save_change_to_auth_config? && auth_config_in_database != saved.auth_config) ||
        (will_save_change_to_connection_config? && connection_config_in_database != saved.connection_config)
    end

    def connection_credentials_changed?(saved)
      (will_save_change_to_auth_config? && auth_config != saved.auth_config) ||
        (will_save_change_to_connection_config? && connection_config.to_h.except("url") != saved.connection_config.to_h.except("url"))
    end

    def remove_previous_destination_credentials(saved)
      previous_auth = saved.auth_config.to_h
      self.auth_config = auth_config.to_h.reject { |key, value| previous_auth[key] == value }

      self.headers = headers.to_h.reject do |key, value|
        saved.headers.to_h.any? { |old_key, old_value| old_key.to_s.casecmp?(key.to_s) && old_value == value }
      end
    end

    def invalidate_connection_diagnostics(saved)
      current_metadata = will_save_change_to_metadata? ? metadata : saved.metadata
      # This counter represents the live connection, not every form field.
      self.connection_revision = saved.connection_revision + 1
      { status: "disconnected", last_connected_at: nil, last_error: nil, latency_ms: nil,
        metadata: current_metadata&.except(*CONNECTION_DIAGNOSTIC_METADATA) }.each do |name, value|
        # Another request may have written diagnostics since this instance
        # was loaded. Do not let partial updates omit these reset values.
        attribute_will_change!(name.to_s)
        self[name] = value
      end
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
