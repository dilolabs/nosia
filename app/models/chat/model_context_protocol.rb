module Chat::ModelContextProtocol
  extend ActiveSupport::Concern

  included do
    has_many :chat_mcp_sessions, dependent: :destroy
    has_many :mcp_servers, through: :chat_mcp_sessions
  end

  # Get all enabled MCP tools within this chat's account tenant.
  # @return [Array<RubyLLM::Tool>] Tools from ready, linked servers
  def mcp_tools
    ActsAsTenant.with_tenant(account) do
      chat_mcp_sessions.enabled.includes(:mcp_server).flat_map do |session|
        if session.mcp_server&.status_ready?
          session.mcp_server.tools
        else
          []
        end
      end.compact
    end
  end

  # Add an MCP server owned by this chat's account.
  # @param mcp_server [McpServer]
  # @return [ChatMcpSession] Existing or newly created link
  # @raise [ActiveRecord::RecordNotFound] if the server belongs to another account
  def add_mcp_server(mcp_server)
    raise ActiveRecord::RecordNotFound unless mcp_server.account_id == account_id

    ActsAsTenant.with_tenant(account) do
      chat_mcp_sessions.find_or_create_by(mcp_server: mcp_server)
    end
  end

  # Remove an MCP server from this chat
  def remove_mcp_server(mcp_server)
    chat_mcp_sessions.find_by(mcp_server: mcp_server)&.destroy
  end
end
