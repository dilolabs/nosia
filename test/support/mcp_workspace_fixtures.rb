require_relative "chat_account_fixtures"

# Provides isolated account fixtures and a local MCP integration for workspace tests.
module McpWorkspaceFixtures
  extend ActiveSupport::Concern
  include ChatAccountFixtures

  # Echoes workspace test input without contacting external services.
  class EchoTool < MCP::Tool
    tool_name "workspace_echo"
    description "Echo a query without external services"
    input_schema(properties: { query: { type: "string" } }, required: [ "query" ])

    # @param query [String] Text to echo
    # @param server_context [Hash] Local integration credentials
    # @return [MCP::Tool::Response] Echoed text
    def self.call(query:, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: query } ])
    end
  end

  included do
    setup do
      @saved_engines = Engines::Registry.all
      @saved_catalog = McpCatalog.instance_variable_get(:@catalog)
      @saved_categories = McpCatalog.instance_variable_get(:@categories)
      @health_check = ->(auth) { raise "credential-echo-#{auth[:api_key]}" if auth[:api_key] == "bad" }
      Engines::Registry.register(Engines::Registration.new(id: "workspace-demo",
        name: "Workspace demo", icon: "test", description: "Local fixture integration",
        required_config: [ { name: "api_key", label: "Demo key", type: "secret", required: true },
          { name: "team", label: "Team", type: "string", required: true } ],
        tool_classes: [ EchoTool ], capabilities: [ "tools" ], health_check: ->(auth) { @health_check.call(auth) }))
      McpCatalog.instance_variable_set(:@catalog, nil)
      McpCatalog.instance_variable_set(:@categories, nil)
      @first_server = mcp_servers(:picker_first_tool)
      @second_server = mcp_servers(:picker_second_tool)
      [ [ @first, @first_server ], [ @second, @second_server ] ].each do |account, server|
        ActsAsTenant.with_tenant(account) do
          server.update!(status: "disconnected", metadata: { engine: "workspace-demo", catalog_id: "workspace-demo" },
            auth_config: { api_key: "saved-secret", team: "Research" })
        end
      end
      stub_url_resolver([ "93.184.216.34" ])
    end

    teardown do
      unstub_url_resolver
      Engines::Registry.clear
      @saved_engines.each { |entry| Engines::Registry.register(entry) }
      McpCatalog.instance_variable_set(:@catalog, @saved_catalog)
      McpCatalog.instance_variable_set(:@categories, @saved_categories)
    end
  end
end
