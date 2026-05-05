class OpenAlexTools::GetAuthorWorksTool < MCP::Tool
  tool_name "openalex_get_author_works"
  title "Get Author Works"
  description "Retrieve all works by a specific author ID"
  
  input_schema(
    properties: {
      author_id: { type: "string", description: "OpenAlex author ID" }
    },
    required: ["author_id"]
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

  def self.call(author_id:, server_context:)
    works = OpenAlex::Tool.get_author_works(author_id)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Retrieved #{works.length} works for author #{author_id}"
    }], structured_content: works)
  end
end