# lib/nosia/engines/registration.rb
module Engines
  class Registration
    attr_reader :id, :name, :icon, :description, :category,
                :required_config, :tool_classes, :health_check, :capabilities

    def initialize(id:, name:, icon:, description:, required_config:, tool_classes:,
                   health_check:, capabilities: [])
      @id = id
      @name = name
      @icon = icon
      @description = description
      @category = "engines"
      @required_config = required_config
      @tool_classes = tool_classes
      @health_check = health_check
      @capabilities = capabilities
    end

    def to_catalog_entry
      {
        id: id,
        name: name,
        icon: icon,
        description: description,
        category: category,
        source: :registry,
        capabilities: capabilities,
        required_config: required_config
      }
    end
  end
end
