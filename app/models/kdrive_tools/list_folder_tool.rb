class KdriveTools::ListFolderTool < MCP::Tool
  tool_name "kdrive_list_folder"
  title "List kDrive folder"
  description "List the contents of a folder in the user's Infomaniak kDrive (defaults to drive root)"
  input_schema(
    properties: { folder_id: { type: "string", description: "Folder id; '1' for the drive root" } }
  )
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def self.call(folder_id: "1", server_context:)
    items = Array(Kdrive::Tool.list_folder(folder_id, auth: server_context))
    MCP::Tool::Response.new(
      [ { type: "text", text: "Folder has #{items.size} items" } ],
      structured_content: items
    )
  end
end
