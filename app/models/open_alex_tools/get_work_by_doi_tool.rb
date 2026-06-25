class OpenAlexTools::GetWorkByDoiTool < MCP::Tool
  tool_name "openalex_get_work_by_doi"
  title "Get Work by DOI"
  description "Retrieve scholarly work details by DOI"
  
  input_schema(
    properties: {
      doi: { type: "string", description: "Digital Object Identifier" }
    },
    required: ["doi"]
  )
  
  output_schema(
    properties: {
      id: { type: "string" },
      doi: { type: "string" },
      title: { type: "string" },
      publication_year: { type: "integer" },
      cited_by_count: { type: "integer" },
      is_open_access: { type: "boolean" }
    }
  )
  
  annotations(
    read_only_hint: true,
    destructive_hint: false,
    idempotent_hint: true,
    open_world_hint: false
  )

  def self.call(doi:, server_context:)
    work = OpenAlex::Tool.get_work_by_doi(doi)
    
    if work
      MCP::Tool::Response.new([{
        type: "text",
        text: "Found work: #{work[:title]}"
      }], structured_content: work)
    else
      MCP::Tool::Response.new([{
        type: "text",
        text: "No work found for DOI: #{doi}"
      }], error: true)
    end
  end
end