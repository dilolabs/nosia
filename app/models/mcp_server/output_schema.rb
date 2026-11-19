require "json_schemer"

# Validates only structured results, without resolving external schema documents.
module McpServer::OutputSchema
  OFFLINE_RESOLVER = ->(_uri) { raise JSONSchemer::UnknownRef }

  # @param schema [Hash, Boolean] The advertised JSON Schema
  # @param value [Object] The structured JSON value
  # @return [Boolean] Whether the value satisfies a supported schema
  def self.valid?(schema, value)
    return false unless schema.is_a?(Hash) || schema == true || schema == false

    schemer = JSONSchemer.schema(schema, ref_resolver: OFFLINE_RESOLVER, insert_property_defaults: false)
    schemer.valid_schema? && schemer.valid?(value)
  rescue StandardError, SystemStackError
    # The schema is peer-supplied; neither schema nor validator errors may
    # escape as diagnostics. Bound self-references can also overflow the stack.
    false
  end
end
