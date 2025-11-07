module Chat::ModelContextProtocol
  extend ActiveSupport::Concern

  included do
    has_many :chat_mcp_sessions, dependent: :destroy
    has_many :mcp_servers, through: :chat_mcp_sessions
  end

  # Get all enabled MCP tools for this chat
  def mcp_tools
    chat_mcp_sessions.enabled.includes(:mcp_server).flat_map do |session|
      next [] unless session.mcp_server.status_ready?
      session.mcp_server.tools
    end.compact
  end

  # Add an MCP server to this chat
  def add_mcp_server(mcp_server)
    chat_mcp_sessions.find_or_create_by(mcp_server: mcp_server)
  end

  # Remove an MCP server from this chat
  def remove_mcp_server(mcp_server)
    chat_mcp_sessions.find_by(mcp_server: mcp_server)&.destroy
  end
end
