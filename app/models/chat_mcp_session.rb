class ChatMcpSession < ApplicationRecord
  belongs_to :chat
  belongs_to :mcp_server

  validates :mcp_server_id, uniqueness: { scope: :chat_id }

  scope :enabled, -> { where(enabled: true) }

  # Store accessor for metadata
  store_accessor :metadata, :tool_call_count, :last_tool_call_at
end
