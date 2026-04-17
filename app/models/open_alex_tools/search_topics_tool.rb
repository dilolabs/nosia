class OpenAlexTools::SearchTopicsTool < MCP::Tool
  tool_name "openalex_search_topics"
  title "Search Topics"
  description "Search academic topics and subject classifications"
  
  input_schema(
    properties: {
      name: { type: "string", description: "Topic name to search for" }
    },
    required: ["name"]
  )
  
  output_schema(
    type: "array",
    items: {
      properties: {
        id: { type: "string" },
        name: { type: "string" },
        domain: { type: "string" },
        field: { type: "string" },
        subfield: { type: "string" },
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
    results = OpenAlex::Tool.search_topics(name)
    
    MCP::Tool::Response.new([{
      type: "text",
      text: "Found #{results.length} topics matching '#{name}'"
    }], structured_content: results)
  end
end