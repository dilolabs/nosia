class OpenAlexTools::SearchInstitutionsTool < MCP::Tool
  tool_name "openalex_search_institutions"
  title "Search Institutions"
  description "Search academic institutions (universities, research organizations)"
  
  input_schema(
    properties: {
      name: { type: "string", description: "Institution name to search for" }
    },
    required: ["name"]
  )
  
  output_schema(
    type: "array",
    items: {
      properties: {
        id: { type: "string" },
        name: { type: "string" },
        ror: { type: "string" },
        country: { type: "string" },
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
    results = OpenAlex::Tool.search_institutions(name)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Found #{results.length} institutions matching '#{name}'"
    }], structured_content: results)
  end
end