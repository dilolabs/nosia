class OpenAlexTools::GetSourceWorksTool < MCP::Tool
  tool_name "openalex_get_source_works"
  title "Get Source Works"
  description "Retrieve all works from a specific source (journal, repository)"
  
  input_schema(
    properties: {
      source_id: { type: "string", description: "OpenAlex source ID" }
    },
    required: ["source_id"]
  )
  
  output_schema(
    type: "array",
    items: {
      properties: {
        id: { type: "string" },
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

  def self.call(source_id:, server_context:)
    works = OpenAlex::Tool.get_source_works(source_id)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Retrieved #{works.length} works from source #{source_id}"
    }], structured_content: works)
  end
end