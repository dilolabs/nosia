module OpenAlex
  class EngineRegistration < Engines::Registration
    def initialize
      super(
        id: "open_alex",
        name: "OpenAlex",
        icon: "📚",
        description: "Search scholarly works, authors, institutions, sources, topics, publishers and funders.",
        required_config: [
          { name: "api_key", label: "OpenAlex API key (optional, for the polite pool)", type: "secret", required: false }
        ],
        tool_classes: OpenAlexTools.all,
        health_check: ->(auth) { OpenAlex::ApiClient.new(auth).ping || raise("OpenAlex unreachable") },
        capabilities: [ "tools" ]
      )
    end
  end
end
