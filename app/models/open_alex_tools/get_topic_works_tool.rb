class OpenAlexTools::GetTopicWorksTool < MCP::Tool
  tool_name "openalex_get_topic_works"
  title "Get Topic Works"
  description "Retrieve all works related to a specific topic"
  
  input_schema(
    properties: {
      topic_id: { type: "string", description: "OpenAlex topic ID" }
    },
    required: ["topic_id"]
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

  def self.call(topic_id:, server_context:)
    works = OpenAlex::Tool.get_topic_works(topic_id)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Retrieved #{works.length} works for topic #{topic_id}"
    }], structured_content: works)
  end
end