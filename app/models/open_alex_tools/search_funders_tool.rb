class OpenAlexTools::SearchFundersTool < MCP::Tool
  tool_name "openalex_search_funders"
  title "Search Funders"
  description "Search academic funding agencies"
  
  input_schema(
    properties: {
      name: { type: "string", description: "Funder name to search for" }
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
    results = OpenAlex::Tool.search_funders(name)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Found #{results.length} funders matching '#{name}'"
    }], structured_content: results)
  end
end