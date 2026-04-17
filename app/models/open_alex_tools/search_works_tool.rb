class OpenAlexTools::SearchWorksTool < MCP::Tool
  tool_name "openalex_search_works"
  title "Search Works"
  description "Search scholarly works by query"
  
  input_schema(
    properties: {
      query: { type: "string", description: "Search query" },
      params: {
        type: "object",
        description: "Additional search parameters",
        properties: {
          per_page: { type: "integer", minimum: 1, maximum: 100 },
          page: { type: "integer", minimum: 1 }
        }
      }
    },
    required: ["query"]
  )
  
  output_schema(
    type: "array",
    items: {
      properties: {
        id: { type: "string" },
        doi: { type: "string" },
        title: { type: "string" },
        year: { type: "integer" },
        citations: { type: "integer" }
      }
    }
  )
  
  annotations(
    read_only_hint: true,
    destructive_hint: false,
    idempotent_hint: true,
    open_world_hint: false
  )

  def self.call(query:, params: {}, server_context:)
    results = OpenAlex::Tool.search_works(query, params)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Found #{results.length} works matching '#{query}'"
    }], structured_content: results)
  end
end