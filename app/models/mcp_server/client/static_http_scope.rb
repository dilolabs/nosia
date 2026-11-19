# A static client is a snapshot; confirm it still represents the saved
# connector before putting its headers on any socket, including retries.
class McpServer::Client::StaticHttpScope < McpServer::Client::RequestScope
  def initialize(server)
    super(https_only: false)
    @server_id = server.id
    @account_id = server.account_id
    @configuration = server
  end

  def endpoint
    @endpoint ||= @configuration.effective_endpoint&.dup&.freeze
  end

  def headers
    @headers ||= @configuration.static_headers
  end

  def admit!(_env)
    saved = McpServer.uncached do
      McpServer.unscoped.find_by(id: @server_id, account_id: @account_id, auth_mode: "static", transport_type: "streamable")
    end
    unless saved && saved.effective_endpoint == endpoint && saved.static_headers == headers
      raise McpOutbound::Blocked
    end
  end
end
