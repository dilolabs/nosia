# Register built-in optional engines. Each engine is always bundled;
# an account activates it per-tenant via the MCP Catalog.
require_dependency "engines/registry" unless defined?(Engines::Registry)

Rails.application.config.to_prepare do
  # Register once; guard against re-loading in development.
  unless Engines::Registry.find("open_alex")
    require_dependency "open_alex/engine_registration"
    require_dependency "kdrive/engine_registration"
    Engines::Registry.register(OpenAlex::EngineRegistration.new)
    Engines::Registry.register(Kdrive::EngineRegistration.new)

    Engines::Registry.all.each do |registration|
      registration.tool_classes.each do |tool_class|
        next if Engines::ToolAdapter.supported?(tool_class)

        Rails.logger.warn "Engines: dropping unsupported tool #{registration.id}/#{tool_class.tool_name}"
      end
    end
  end
end
