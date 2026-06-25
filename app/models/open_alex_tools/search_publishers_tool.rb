class OpenAlexTools::SearchPublishersTool < MCP::Tool
  tool_name "openalex_search_publishers"
  title "Search Publishers"
  description "Search academic publishers"
  
  input_schema(
    properties: {
      name: { type: "string", description: "Publisher name to search for" }
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
    results = OpenAlex::Tool.search_publishers(name)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Found #{results.length} publishers matching '#{name}'"
    }], structured_content: results)
  end
end