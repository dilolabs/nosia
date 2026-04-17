class OpenAlexTools::SearchAuthorsTool < MCP::Tool
  tool_name "openalex_search_authors"
  title "Search Authors"
  description "Search for academic authors by name"
  
  input_schema(
    properties: {
      name: { type: "string", description: "Author name to search for" }
    },
    required: ["name"]
  )
  
  output_schema(
    type: "array",
    items: {
      properties: {
        id: { type: "string" },
        name: { type: "string" },
        works_count: { type: "integer" },
        cited_by_count: { type: "integer" }
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
    results = OpenAlex::Tool.search_authors(name)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Found #{results.length} authors matching '#{name}'"
    }], structured_content: results)
  end
end