class McpCatalogController < ApplicationController
  def index
    @categories = McpCatalog.categories
    @servers = McpCatalog.all
    @servers_by_category = @servers.group_by { |s| s[:category] }

    # Get list of already activated server IDs
    @activated_ids = Current.account.mcp_servers
      .where("metadata->>'catalog_id' IS NOT NULL")
      .pluck(Arel.sql("metadata->>'catalog_id'"))
  end

  def show
    @template = McpCatalog.find(params[:id])
    redirect_to mcp_catalog_index_path, alert: "Server not found." unless @template
  end

  def create
    server_id = params[:id] || params[:server_id]
    template = McpCatalog.find(server_id)

    unless template
      redirect_to mcp_catalog_index_path, alert: "Server not found."
      return
    end

    # Get config values from params
    config_values = params[:config] || {}

    begin
      @mcp_server = McpCatalog.activate_for_account(Current.account, server_id, config_values)
      redirect_to @mcp_server, notice: "#{template[:name]} activated successfully."
    rescue => e
      redirect_to mcp_catalog_index_path, alert: "Activation error: #{e.message}."
    end
  end
end
