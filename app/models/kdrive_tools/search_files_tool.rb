class KdriveTools::SearchFilesTool < MCP::Tool
  tool_name "kdrive_search_files"
  title "Search kDrive files"
  description "Search files and folders in the user's Infomaniak kDrive by query"
  input_schema(properties: { query: { type: "string" } }, required: [ "query" ])
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def self.call(query:, server_context:)
    items = Array(Kdrive::Tool.search_files(query, auth: server_context))
    MCP::Tool::Response.new(
      [ { type: "text", text: "Found #{items.size} files matching '#{query}'" } ],
      structured_content: items
    )
  end
end
