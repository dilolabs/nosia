# Materializes chat tool choices within the explicitly selected account.
module ChatsHelper
  # @param account [Account]
  # @return [Array<McpServer>] Ready, enabled tools from this account only
  def ready_chat_mcp_servers(account)
    ActsAsTenant.with_tenant(account) { account.mcp_servers.enabled.ready.order(:name).to_a }
  end
end
