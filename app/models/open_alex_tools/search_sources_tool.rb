class OpenAlexTools::SearchSourcesTool < MCP::Tool
  tool_name "openalex_search_sources"
  title "Search Sources"
  description "Search academic sources (journals, repositories, conferences)"
  
  input_schema(
    properties: {
      name: { type: "string", description: "Source name to search for" }
    },
    required: ["name"]
  )
  
  output_schema(
    type: "array",
    items: {
      properties: {
        id: { type: "string" },
        name: { type: "string" },
        issn: { type: "string" },
        publisher: { type: "string" },
        works_count: { type: "integer" }
      }
    }
  )
  
  annotations(
    read_only_hint: true,
    destructive_hint: false,
    idempotent_hint: true,
    open_world_hint: false
  )

  def self.call(name:, server_context:)
    results = OpenAlex::Tool.search_sources(name)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Found #{results.length} sources matching '#{name}'"
    }], structured_content: results)
  end
end