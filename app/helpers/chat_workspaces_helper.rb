# Presentation helpers for the focused new and saved conversation workspace.
module ChatWorkspacesHelper
  # @return [Boolean] Whether the current page owns the focused chat shell and history
  def chat_workspace_page?
    controller_path == "chats" && %w[new show].include?(action_name)
  end

  # @param chat [Chat] An already-authorized conversation
  # @param titles [Hash] Batched first-question markup keyed by chat ID
  # @return [String] A bounded plain-text preview or the existing localized fallback
  def chat_workspace_title(chat, titles:)
    truncate(account_conversation_title(chat, titles: titles), length: 120, omission: "…")
  end
end
