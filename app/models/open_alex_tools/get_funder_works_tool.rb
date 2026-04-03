class OpenAlexTools::GetFunderWorksTool < MCP::Tool
  tool_name "openalex_get_funder_works"
  title "Get Funder Works"
  description "Retrieve all works funded by a specific funding agency"
  
  input_schema(
    properties: {
      funder_id: { type: "string", description: "OpenAlex funder ID" }
    },
    required: ["funder_id"]
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

  def self.call(funder_id:, server_context:)
    works = OpenAlex::Tool.get_funder_works(funder_id)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Retrieved #{works.length} works funded by #{funder_id}"
    }], structured_content: works)
  end
end