# Makes provider-facing object schemas explicit without changing what they allow.
module McpServer::InputSchema
  MAPS = %w[properties patternProperties $defs definitions dependentSchemas].freeze
  SUBSCHEMAS = %w[additionalProperties unevaluatedProperties propertyNames items additionalItems
    unevaluatedItems contains not if then else contentSchema].freeze
  LISTS = %w[allOf anyOf oneOf prefixItems].freeze

  # @param schema [Hash, Boolean, nil] A native tool's schema or subschema
  # @return [Hash, Boolean, nil] A provider-ready schema, with annotations untouched
  def self.for_provider(schema)
    return schema unless schema.is_a?(Hash)

    normalized = schema.to_h do |keyword, value|
      [ keyword, normalize_keyword(keyword, value) ]
    end
    if Array(normalized["type"]).include?("object") && !normalized.key?("properties")
      normalized["properties"] = {}
    end
    normalized
  end

  def self.normalize_keyword(keyword, value)
    if (MAPS.include?(keyword) || keyword == "dependencies") && value.is_a?(Hash)
      value.transform_values { |child| for_provider(child) }
    elsif (LISTS.include?(keyword) || keyword == "items") && value.is_a?(Array)
      value.map { |child| for_provider(child) }
    elsif SUBSCHEMAS.include?(keyword)
      for_provider(value)
    else
      value
    end
  end
  private_class_method :normalize_keyword
end
