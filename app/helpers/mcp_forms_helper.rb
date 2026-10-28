# Connects MCP configuration metadata, field hints, and validation errors.
module McpFormsHelper
  # @param name [String, Symbol] Model attribute or configuration.name
  # @param catalog [Boolean] Whether the input belongs to catalog configuration
  # @return [String] Stable input ID
  def mcp_field_id(name, catalog: false)
    key = name.to_s
    if key.start_with?("configuration.")
      "#{catalog ? 'config' : 'mcp_server_configuration_values'}_#{key.delete_prefix('configuration.')}"
    else
      "mcp_server_#{key}"
    end
  end

  # @param field [Hash] Trusted field metadata
  # @param template [Hash, nil] Catalog entry for existing localization support
  # @return [String] Escaped by the caller, never HTML-safe
  def mcp_configuration_label(field, template: nil)
    template ? catalog_field_text(template, field, :label) : field[:label].presence || field[:name].to_s.humanize
  end

  # Formats declared configuration errors without reading virtual model attributes.
  # @param record [McpServer] Possibly invalid model
  # @param catalog [Boolean] Whether field IDs belong to catalog setup
  # @return [Array<Hash>] Messages and optional declared/editable field targets; no values
  def mcp_error_items(record, catalog: false)
    record.errors.flat_map do |error|
      if catalog && error.type == :missing_required_config
        error.options.fetch(:fields).split(", ").map do |key|
          field = Array(@template[:requires_config]).find { |item| item[:name].to_s == key }
          { message: "#{mcp_configuration_label(field, template: @template)} #{I18n.t('errors.messages.blank')}", target: mcp_field_id("configuration.#{key}", catalog: true) } if field
        end.compact
      elsif !catalog && error.attribute.to_s.start_with?("configuration.") &&
          (field = record.workspace_configuration_fields.find { |item| item[:name].to_s == error.attribute.to_s.delete_prefix("configuration.") })
        template = McpCatalog.find(record.metadata&.[]("engine")) if record.local?
        message = error.type == :blank ? I18n.t("errors.messages.blank") : error.message
        { message: "#{mcp_configuration_label(field, template: template)} #{message}", target: mcp_field_id(error.attribute) }
      else
        attribute = error.attribute.to_s
        editable = %w[name transport_type endpoint command args tags notes enabled].include?(attribute)
        { message: error.full_message, target: editable && !catalog ? mcp_field_id(attribute) : nil }
      end
    end
  end

  # @param record [McpServer] Possibly invalid model
  # @param name [String, Symbol] Model or configuration attribute
  # @param catalog [Boolean] Whether field IDs belong to catalog setup
  # @return [Hash] Connected hint/error attributes
  def mcp_field_options(record, name, catalog: false)
    id = mcp_field_id(name, catalog: catalog)
    invalid = mcp_error_items(record, catalog: catalog).any? { |item| item[:target] == id }
    { id: id, aria: { invalid: invalid ? "true" : nil, describedby: "#{id}_help#{invalid ? " #{id}_error" : ''}" } }
  end
end
