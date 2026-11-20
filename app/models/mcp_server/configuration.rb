# Applies declared workspace configuration edits without exposing saved secrets.
module McpServer::Configuration
  extend ActiveSupport::Concern

  WORKSPACE_ATTRIBUTES = %w[name transport_type endpoint enabled notes tags command args auth_mode].freeze

  included { validate :validate_workspace_configuration }

  # @param auth_mode [String] Saved or proposed mode
  # @param transport_type [String] Saved or proposed transport
  # @return [Array<Hash>] Declared fields; never inferred from encrypted keys
  def workspace_configuration_fields(auth_mode: self.auth_mode, transport_type: self.transport_type)
    return [] unless auth_mode == "static"

    if transport_type == "local"
      Array(Engines::Registry[metadata&.[]("engine")]&.required_config).map(&:deep_symbolize_keys)
    elsif %w[streamable sse stdio].include?(transport_type)
      [ { name: "token", label: I18n.t("nosia.mcp.bearer_token"), type: "secret" },
        { name: "api_key", label: I18n.t("nosia.mcp.api_key"), type: "secret" } ]
    else
      []
    end
  end

  # @return [Hash] Only public values suitable for form repopulation
  def workspace_public_values
    source = @workspace_public_values || auth_config || {}
    source.slice(*workspace_configuration_fields.reject { |field| secret_configuration_field?(field) }.map { |field| field[:name].to_s })
  end

  # @param field [Hash] Trusted declaration
  # @return [Boolean] Whether the value must never be repopulated
  def secret_configuration_field?(field) = %w[secret password].include?(field[:type].to_s)

  # Saves declared edits and retires matching header copies when credentials change.
  # @param attributes [Hash] Whitelisted ordinary model attributes
  # @param values [Hash] Whitelisted declared configuration inputs
  # @param removals [Array<String>] Explicit saved-secret removals
  # @param editing_auth_mode [String, nil] Optional saved mode from the rendered editor
  # @param editing_connection_revision [String, nil] Optional configuration version from the rendered editor, not a credential fingerprint
  # @return [Boolean] Whether this complete edit was valid and saved
  def save_workspace(attributes, values:, removals: [], editing_auth_mode: nil, editing_connection_revision: nil)
    attrs = attributes.to_h.stringify_keys.slice(*WORKSPACE_ATTRIBUTES)
    @workspace_editing_auth_mode = editing_auth_mode
    @workspace_editing_connection_revision = editing_connection_revision
    @workspace_configuration_errors = []
    if persisted? && local? && attrs.key?("transport_type") && attrs["transport_type"] != "local"
      @workspace_configuration_errors << [ :transport_type, I18n.t("nosia.mcp_workspace.local_transport_fixed") ]
      attrs.delete("transport_type")
    end
    if attrs["args"].is_a?(String)
      attrs["args"] = attrs["args"] == Array(args).join("\n") ? args : (attrs["args"].empty? ? [] : attrs["args"].lines(chomp: true))
    end
    if (oauth? || attrs["auth_mode"] == "oauth") && attrs.key?("endpoint") && attrs["endpoint"] != endpoint && url
      self.url = nil
    end
    assign_attributes(attrs)
    return save if oauth?

    config = (auth_config || {}).deep_dup
    incoming = values.stringify_keys
    @workspace_public_values = {}
    workspace_configuration_fields.each do |field|
      key = field[:name].to_s
      secret = secret_configuration_field?(field)
      remove = secret && removals.map(&:to_s).include?(key)
      if remove && incoming[key].present?
        @workspace_configuration_errors << [ :"configuration.#{key}", I18n.t("nosia.mcp_workspace.credential_conflict") ]
      elsif remove
        remove_workspace_credential_header(key, config.delete(key))
      elsif incoming.key?(key) && (!secret || incoming[key].present?)
        remove_workspace_credential_header(key, config[key]) if secret && incoming[key].to_s != config[key]
        config[key] = incoming[key].to_s
      end
      @workspace_public_values[key] = config[key] unless secret
      @workspace_configuration_errors << [ :"configuration.#{key}", :blank ] if field[:required] && config[key].blank?
    end
    self.auth_config = config
    save
  ensure
    @workspace_configuration_errors = nil
    @workspace_editing_auth_mode = nil
    @workspace_editing_connection_revision = nil
  end

  private
    def remove_workspace_credential_header(key, value)
      return if value.blank? || local?

      header, expected = case key
      when "token" then [ "Authorization", "Bearer #{value}" ]
      when "api_key" then [ "X-API-Key", value ]
      end
      if header && headers
        self.headers = headers.reject { |key, value| key.to_s.casecmp?(header) && value == expected }
      end
    end

    def validate_workspace_configuration
      Array(@workspace_configuration_errors).each { |attribute, message| errors.add(attribute, message) }
    end
end
