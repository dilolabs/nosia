# Builds display and navigation context for scoped and legacy MCP pages.
module McpWorkspaceHelper
  # @return [Boolean] Whether the controller owns an MCP workspace shell
  def mcp_workspace_page?
    %w[mcp_servers mcp_catalog].include?(controller_path) || controller_path.start_with?("mcp_servers/")
  end

  # @return [Boolean] Whether context came from an authorized account URL
  def mcp_scoped? = @mcp_scoped == true

  # @return [String] Context-preserving server list
  def mcp_index_path = mcp_scoped? ? account_mcp_servers_path(@account) : mcp_servers_path

  # @return [String] Context-preserving creation form
  def mcp_new_path = mcp_scoped? ? new_account_mcp_server_path(@account) : new_mcp_server_path

  # @return [String] Context-preserving catalog list
  def mcp_catalog_list_path = mcp_scoped? ? account_mcp_catalog_index_path(@account) : mcp_catalog_index_path

  # @param id [String] Trusted catalog ID
  # @return [String] Context-preserving template URL
  def mcp_template_path(id) = mcp_scoped? ? account_mcp_catalog_path(@account, id) : mcp_catalog_path(id)

  # @param server [McpServer] Authorized record
  # @return [String] Context-preserving details URL
  def mcp_record_path(server) = mcp_scoped? ? account_mcp_server_path(@account, server) : mcp_server_path(server)

  # @param server [McpServer] Authorized record
  # @return [String] Context-preserving edit URL
  def mcp_edit_path(server) = mcp_scoped? ? edit_account_mcp_server_path(@account, server) : edit_mcp_server_path(server)

  # @param server [McpServer] New or authorized existing record
  # @return [McpServer, Array] Rails form model argument
  def mcp_form_model(server) = mcp_scoped? ? [ @account, server ] : server

  # @param server [McpServer] Authorized record
  # @return [String] Existing test operation URL
  def mcp_test_path(server) = mcp_scoped? ? account_mcp_server_connection_test_path(@account, server) : test_connection_mcp_server_path(server)

  # @param server [McpServer] Authorized record
  # @return [String] Existing connect operation URL
  def mcp_connect_path(server) = mcp_scoped? ? account_mcp_server_connection_path(@account, server) : connect_mcp_server_path(server)

  # @param server [McpServer] Authorized record
  # @return [String] Existing disconnect operation URL
  def mcp_disconnect_path(server) = mcp_scoped? ? account_mcp_server_connection_path(@account, server) : disconnect_mcp_server_path(server)

  # @return [Symbol] HTTP verb preserving the legacy disconnect URL
  def mcp_disconnect_method = mcp_scoped? ? :delete : :post

  # @return [String] Existing composer with explicit URL account when applicable
  def mcp_new_chat_path = mcp_scoped? ? new_chat_path(account_id: @account.id) : new_chat_path

  # @param current [String, nil] Detail/form current label
  # @param catalog [Boolean] Whether to include the catalog ancestor
  # @param server [McpServer, nil] Authorized edit ancestor
  # @return [Array<Hash>] Explicit complete breadcrumb
  def mcp_trail(current: nil, catalog: false, server: nil)
    trail = [ { label: t("nosia.nav.home"), path: user_root_path } ]
    if mcp_scoped?
      trail += [ { label: t("nosia.nav.accounts"), path: accounts_path }, { label: @account.name, path: account_path(@account) } ]
    else
      trail << { label: t("nosia.nav.settings"), path: settings_path }
    end
    trail << { label: t("nosia.mcp.title"), path: (current || catalog || server) ? mcp_index_path : nil }
    trail << { label: t("nosia.mcp.catalog"), path: current ? mcp_catalog_list_path : nil } if catalog
    trail << { label: server.name, path: mcp_record_path(server) } if server
    trail << { label: current, path: nil } if current
    trail
  end

  # @return [String, nil] Localized explicit scope; never changes the default
  def mcp_scope_label
    t(mcp_scoped? ? "nosia.workspace.account" : "nosia.workspace.default_account", name: @account.name) if @account
  end

  # @param server [McpServer] Authorized record
  # @return [String] Credential-free endpoint/command label
  def mcp_endpoint_label(server)
    if server.endpoint.present?
      uri = URI.parse(server.endpoint.match?(%r{\Ahttps?://}i) ? server.endpoint : "https://#{server.endpoint}")
      "#{uri.host}#{uri.path}"
    elsif server.command.present?
      File.basename(server.command.to_s.split.first.to_s)
    else
      t("nosia.mcp.transport.#{server.transport_type}_short")
    end
  rescue URI::InvalidURIError
    t("nosia.mcp.transport.#{server.transport_type}_short")
  end

  # @param server [McpServer] Authorized record
  # @return [String] Plain contextual confirmation
  def mcp_delete_confirmation(server)
    t("nosia.mcp_workspace.delete_confirm", name: server.name, account: @account.name)
  end

  # @param id [String] Trusted catalog ID/category
  # @return [String] Local-only icon path
  def mcp_icon(id)
    { "kchat" => "svg/chats.svg", "kdrive" => "svg/folders.svg", "open_alex" => "svg/file-search.svg",
      "communication" => "svg/chats.svg", "productivity" => "svg/folders.svg" }.fetch(id.to_s, "svg/server.svg")
  end
end
