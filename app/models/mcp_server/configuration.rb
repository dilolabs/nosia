# Applies declared workspace configuration edits without exposing saved secrets.
module McpServer::Configuration
  extend ActiveSupport::Concern

  included { validate :validate_workspace_configuration }

  # @return [Array<Hash>] Declared fields; never inferred from encrypted keys
  def workspace_configuration_fields
    if local?
      Array(Engines::Registry[metadata["engine"]]&.required_config).map(&:deep_symbolize_keys)
    else
      [ { name: "token", label: I18n.t("nosia.mcp.bearer_token"), type: "secret" },
        { name: "api_key", label: I18n.t("nosia.mcp.api_key"), type: "secret" } ]
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

  # @param attributes [Hash] Whitelisted ordinary model attributes
  # @param values [Hash] Whitelisted declared configuration inputs
  # @param removals [Array<String>] Explicit saved-secret removals
  # @return [Boolean] Whether this complete edit was valid and saved
  def save_workspace(attributes, values:, removals: [])
    attrs = attributes.to_h.stringify_keys
    @workspace_configuration_errors = []
    if persisted? && local? && attrs.key?("transport_type") && attrs["transport_type"] != "local"
      @workspace_configuration_errors << [ :transport_type, I18n.t("nosia.mcp_workspace.local_transport_fixed") ]
      attrs.delete("transport_type")
    end
    if attrs["args"].is_a?(String)
      attrs["args"] = attrs["args"] == Array(args).join("\n") ? args : (attrs["args"].empty? ? [] : attrs["args"].lines(chomp: true))
    end
    assign_attributes(attrs)
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
        config.delete(key)
      elsif incoming.key?(key) && (!secret || incoming[key].present?)
        config[key] = incoming[key].to_s
      end
      @workspace_public_values[key] = config[key] unless secret
      @workspace_configuration_errors << [ :"configuration.#{key}", :blank ] if field[:required] && config[key].blank?
    end
    self.auth_config = config
    save
  ensure
    @workspace_configuration_errors = nil
  end

  private
    def validate_workspace_configuration
      Array(@workspace_configuration_errors).each { |attribute, message| errors.add(attribute, message) }
    end
end
