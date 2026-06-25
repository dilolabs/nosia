class OpenAlexTools::GetInstitutionWorksTool < MCP::Tool
  tool_name "openalex_get_institution_works"
  title "Get Institution Works"
  description "Retrieve all works from a specific institution"
  
  input_schema(
    properties: {
      institution_id: { type: "string", description: "OpenAlex institution ID" }
    },
    required: ["institution_id"]
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

  def self.call(institution_id:, server_context:)
    works = OpenAlex::Tool.get_institution_works(institution_id)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Retrieved #{works.length} works from institution #{institution_id}"
    }], structured_content: works)
  end
end