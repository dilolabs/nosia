class KdriveTools::DownloadFileTool < MCP::Tool
  tool_name "kdrive_download_file"
  title "Download kDrive file"
  description "Download a file from Infomaniak kDrive and return its content as a base64-encoded string. Use kdrive_info first to check the file's size and MIME type. Files larger than the cap are refused."
  input_schema(properties: { file_id: { type: "number" } }, required: [ "file_id" ])
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def self.call(file_id:, server_context:)
    result = Kdrive::Tool.download_file(file_id, auth: server_context)
    text = if result[:error]
             "Error downloading file #{file_id}: #{result[:error]}"
    else
             result[:base64]
    end
    MCP::Tool::Response.new([ { type: "text", text: text } ])
  end
end
