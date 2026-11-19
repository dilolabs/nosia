module Chat::ModelContextProtocol
  extend ActiveSupport::Concern

  included do
    has_many :chat_mcp_sessions, dependent: :destroy
    has_many :mcp_servers, through: :chat_mcp_sessions
  end

  # Registers linked tools and owns their remote sessions until the turn ends.
  def with_mcp_tools
    clients = []
    tools = mcp_tools_for_turn(clients)
    with_tools(nil)
    with_tools(*tools) if tools.any?
    yield
  ensure
    begin
      with_tools(nil)
    ensure
      clients.each(&:close)
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

  private
    def mcp_tools_for_turn(clients)
      ActsAsTenant.with_tenant(account) do
        chat_mcp_sessions.enabled.includes(:mcp_server).flat_map do |session|
          server = session.mcp_server
          if server&.account_id == account_id && server.enabled? && server.ready_for_tools?
            mcp_tools_for_server(server, clients)
          else
            []
          end
        end
      end
    end

    def mcp_tools_for_server(server, clients)
      return server.tools if server.local?

      connection = server.client
      return [] unless connection

      clients << connection
      connection.tools
    rescue McpServer::Client::Error
      []
    end
end
