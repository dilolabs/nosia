# Lists and activates catalog entries in the authorized MCP account context.
class McpCatalogController < ApplicationController
  include McpScoped

  # @return [void] Renders catalog entries and the account's activated IDs
  def index
    @categories = McpCatalog.categories
    @servers = McpCatalog.all
    @servers_by_category = @servers.group_by { |s| s[:category] }

    # Get list of already activated server IDs
    @activated_ids = @account.mcp_servers
      .where("metadata->>'catalog_id' IS NOT NULL")
      .pluck(Arel.sql("metadata->>'catalog_id'"))
  end

  # @return [void] Renders a catalog template or redirects when it is missing
  def show
    @template = McpCatalog.find(params[:id])
    redirect_to mcp_catalog_list_path, alert: t("nosia.mcp.server_not_found") unless @template
  end

  # @return [void] Activates a template without changing the account context
  def create
    server_id = params[:id] || params[:server_id]
    template = McpCatalog.find(server_id)

    unless template
      redirect_to mcp_catalog_list_path, alert: t("nosia.mcp.server_not_found")
      return
    end

    # Get config values from params
    config_values = params[:config] || {}

    begin
      @mcp_server = McpCatalog.activate_for_account(@account, server_id, config_values)
      redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.activated_named", name: template[:name])
    rescue => e
      redirect_to mcp_catalog_list_path, alert: t("nosia.mcp.activation_error", error: e.message)
    end
  end
end
