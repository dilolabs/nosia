# lib/engines/tool_adapter.rb
module Engines
  class ToolAdapter
    SUPPORTED_TYPES = %w[string integer number boolean].freeze

    class << self
      def for(mcp_tool_class, server_context:)
        return nil unless supported?(mcp_tool_class)

        klass = adapted_class(mcp_tool_class)
        klass.new(mcp_tool_class, server_context)
      end

      def supported?(mcp_tool_class)
        schema_translatable?(mcp_tool_class.input_schema_value&.to_h)
      end

      def unwrap(response)
        return "Error: #{response.content.inspect}" if response.error?

        text = Array(response.content).map { |c| c[:text] || c["text"] }.compact.join("\n")
        return text unless response.structured_content

        structured = response.structured_content.is_a?(String) ? response.structured_content : response.structured_content.to_json
        structured = structured.present? ? "\n\n#{structured}" : ""
        "#{text}#{structured}"
      end

      private

      def adapted_class(mcp_tool_class)
        @adapted_classes ||= {}
        @adapted_classes[mcp_tool_class] ||= build_class(mcp_tool_class)
      end

      def build_class(mcp_tool_class)
        tool_name = mcp_tool_class.tool_name
        klass = Class.new(RubyLLM::Tool) do
          # The LLM-facing tool name is the MCP tool's tool_name, NOT the Ruby
          # class-name derivation (which would prefix the namespace). Override
          # the instance accessor RubyLLM keys tools by.
          define_method(:name) { tool_name }

          def initialize(mcp_tool_class, server_context)
            @mcp_tool_class = mcp_tool_class
            @server_context = server_context
          end

          def execute(**args)
            response = @mcp_tool_class.call(**args, server_context: @server_context)
            Engines::ToolAdapter.unwrap(response)
          rescue => e
            Rails.logger.error("[ToolAdapter] #{@mcp_tool_class.tool_name}: #{e.class}: #{e.message}")
            "Error calling #{@mcp_tool_class.tool_name}: #{e.message}"
          end
        end
        # Name the constant purely for organization/debuggability; it has no
        # effect on the LLM-facing name (overridden above). Assumes distinct
        # tool_names across engines (OpenAlex/kDrive names are distinct), so
        # two tools never camelize to the same constant.
        Engines::ToolAdapter.const_set(const_name_for(tool_name), klass)
        klass.description(mcp_tool_class.description_value)
        schema = mcp_tool_class.input_schema_value&.to_h
        klass.params(schema.deep_transform_keys(&:to_s)) if schema
        klass
      end

      def const_name_for(tool_name)
        tool_name.camelize.upcase_first
      end

      def schema_translatable?(schema)
        return true if schema.blank?

        props = schema[:properties] || schema["properties"]
        required = schema[:required] || schema["required"] || []
        return false unless props.is_a?(Hash)

        props.values.all? { |spec| type_translatable?(spec) } &&
          required.is_a?(Array)
      end

      def type_translatable?(spec)
        type = spec[:type] || spec["type"]
        case type.to_s
        when *SUPPORTED_TYPES then true
        when "object"
          schema_translatable?(spec)
        when "array"
          items = spec[:items] || spec["items"]
          items ? type_translatable?(items) : true
        else
          false # oneOf/anyOf/$ref and anything unexpected
        end
      end
    end
  end
end
