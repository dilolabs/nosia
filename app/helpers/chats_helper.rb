module ChatsHelper
  # @param server [McpServer] Tool this option represents
  # @return [String] Accessible label for removing a saved, unavailable tool
  def remove_unavailable_mcp_label(server)
    t("nosia.chat.remove_unavailable_tool", name: server.name)
  end
end
