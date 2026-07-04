class KdriveTools::GetFileTool < MCP::Tool
  tool_name "kdrive_get_file"
  title "Get kDrive file"
  description "Fetch a file's metadata from Infomaniak kDrive, inlining a bounded text excerpt for text-able types"
  input_schema(properties: { file_id: { type: "string" } }, required: [ "file_id" ])
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def self.call(file_id:, server_context:)
    result = Kdrive::Tool.get_file(file_id, auth: server_context)
    data = result[:meta] || {}
    content = result[:content]
    text = if content
             "File #{file_id} (#{data['name']}): #{content}"
    else
             "File #{file_id} (#{data['name']}, #{data['content_type']}, #{data['size']} bytes) — binary or too large to inline"
    end
    MCP::Tool::Response.new([ { type: "text", text: text } ], structured_content: data)
  end
end
