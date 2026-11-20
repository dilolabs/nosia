# A static client is a snapshot; confirm it still represents the saved
# connector before putting its headers on any socket, including retries.
class McpServer::Client::StaticHttpScope < McpServer::Client::RequestScope
  def initialize(server, chat_owner_id: nil)
    super(https_only: false)
    @server_id = server.id
    @account_id = server.account_id
    @configuration = server
    @revision = server.connection_revision
    @chat_owner_id = chat_owner_id
  end

  def endpoint
    @endpoint ||= @configuration.effective_endpoint&.dup&.freeze
  end

  def headers
    @headers ||= @configuration.static_headers
  end

  def admit!(_env)
    McpServer.uncached do
      saved = McpServer.unscoped.find_by(id: @server_id, account_id: @account_id, auth_mode: "static",
        transport_type: "streamable", connection_revision: @revision)
      unless saved && saved.effective_endpoint == endpoint && saved.static_headers == headers
        raise McpOutbound::Blocked
      end
      if @chat_owner_id && !(saved.enabled? && saved.ready_for_tools? && AccountUser.exists?(account_id: @account_id, user_id: @chat_owner_id))
        raise McpOutbound::Blocked
      end
    end
  end
end
