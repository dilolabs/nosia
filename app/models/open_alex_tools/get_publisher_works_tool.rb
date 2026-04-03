class OpenAlexTools::GetPublisherWorksTool < MCP::Tool
  tool_name "openalex_get_publisher_works"
  title "Get Publisher Works"
  description "Retrieve all works from a specific publisher"
  
  input_schema(
    properties: {
      publisher_id: { type: "string", description: "OpenAlex publisher ID" }
    },
    required: ["publisher_id"]
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

  def self.call(publisher_id:, server_context:)
    works = OpenAlex::Tool.get_publisher_works(publisher_id)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Retrieved #{works.length} works from publisher #{publisher_id}"
    }], structured_content: works)
  end
end