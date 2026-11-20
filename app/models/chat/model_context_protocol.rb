# Resolves selections and turn-scoped MCP clients for a chat's owner and account.
module Chat::ModelContextProtocol
  extend ActiveSupport::Concern

  included do
    has_many :chat_mcp_sessions, dependent: :destroy
    has_many :mcp_servers, through: :chat_mcp_sessions
  end

  # Presents eligible choices separately from preserved, unavailable links.
  # @return [Hash] Scoped servers and links, with a count of active selections
  def mcp_selection
    servers = chat_mcp_connections.keys
    sessions = persisted? ? mcp_sessions_by_server : {}
    available = sessions.slice(*servers.map(&:id)).select { |_id, session| session.enabled? }
    unavailable = sessions.except(*available.keys)
    { servers: servers.reject { |server| unavailable.key?(server.id) }, sessions: available, unavailable:, count: available.size }
  end

  # Registers linked tools and owns their remote sessions until the turn ends.
  # @return [Object] The completion result
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
    def mcp_account
      persisted? && account_id_changed? ? Account.find(account_id_in_database) : account
    end

    def mcp_owner_id
      persisted? ? user_id_in_database : user_id
    end

    def mcp_sessions_by_server
      chat_account = mcp_account
      ActsAsTenant.with_tenant(chat_account) do
        chat_mcp_sessions.joins(:mcp_server).where(mcp_servers: { account_id: chat_account.id })
          .includes(:mcp_server).order("mcp_servers.name").index_by(&:mcp_server_id)
      end
    end

    def chat_mcp_connections(ids: nil, include_unready_static: false)
      chat_account = mcp_account
      owner_id = mcp_owner_id
      return {} if ids == [] || chat_account.nil? || owner_id.nil?

      ActsAsTenant.with_tenant(chat_account) do
        return {} unless AccountUser.exists?(account_id: chat_account.id, user_id: owner_id)

        transports = McpServer.stdio_enabled? ? %w[streamable local stdio] : %w[streamable local]
        scope = chat_account.mcp_servers.enabled.where(transport_type: transports).order(:name)
        servers = (ids ? scope.where(id: ids) : scope).to_a
        grants = McpAuthorization.for_chat(account_id: chat_account.id, user_id: owner_id,
          server_ids: servers.select(&:oauth?).map(&:id))

        servers.each_with_object({}) do |server, result|
          if server.oauth?
            result[server] = grants[server.id] if grants.key?(server.id)
          elsif include_unready_static || server.ready_for_tools?
            result[server] = nil
          end
        end
      end
    end

    def mcp_tools_for_turn(clients)
      ActsAsTenant.with_tenant(mcp_account) do
        ids = chat_mcp_sessions.enabled.pluck(:mcp_server_id)
        chat_mcp_connections(ids: ids).flat_map do |server, grant|
          mcp_tools_for_server(server, grant, clients)
        end
      end
    end

    def mcp_tools_for_server(server, grant, clients)
      return server.tools if server.local?

      connection = McpServer::Client.new(server, grant: grant, chat_owner_id: mcp_owner_id)
      clients << connection
      connection.tools
    rescue McpServer::Client::Error => error
      Rails.logger.warn("MCP discovery unavailable chat_id=#{id} mcp_server_id=#{server.id} error=#{error.class.name}")
      []
    end
end
