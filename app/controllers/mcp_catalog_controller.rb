# Lists and activates catalog entries in the authorized MCP account context.
class McpCatalogController < ApplicationController
  include McpScoped

  before_action :validate_configuration, only: :create

  # @return [void] Renders catalog entries and the account's activated IDs
  def index
    @categories = McpCatalog.categories
    @servers_by_category = McpCatalog.all.group_by { |entry| entry[:category] }
    @added_servers = @account.mcp_servers.to_a.group_by { |server| server.metadata["catalog_id"] }
    @activated_ids = @added_servers.keys.compact
  end

  # @return [void] Renders a catalog template or redirects when it is missing
  def show
    @template = McpCatalog.find(request.path_parameters[:id])
    if @template
      @mcp_server = @account.mcp_servers.build
      @configuration_values = {}
      @added_servers = @account.mcp_servers.to_a.group_by { |server| server.metadata["catalog_id"] }
    else
      redirect_to mcp_catalog_list_path, alert: t("nosia.mcp.server_not_found")
    end
  end

  # @return [void] Activates an account template or returns input/validation errors
  def create
    @template = McpCatalog.find(params[:id] || params[:server_id])
    if @template
      values = params.fetch(:config, ActionController::Parameters.new).permit(*Array(@template[:requires_config]).map { |field| field[:name].to_s }).to_h
      begin
        @mcp_server = McpCatalog.activate_for_account(@account, @template[:id], values)
        redirect_to mcp_record_path(@mcp_server), notice: t("nosia.mcp.activated_named", name: @template[:name])
      rescue ActiveRecord::RecordInvalid => error
        @mcp_server = error.record
        render_configuration_error(values)
      rescue StandardError
        @mcp_server = @account.mcp_servers.build
        @mcp_server.errors.add(:base, I18n.t("nosia.mcp.connection_failed"))
        render_configuration_error(values)
      end
    else
      redirect_to mcp_catalog_list_path, alert: t("nosia.mcp.server_not_found")
    end
  end

  private
    def validate_configuration
      if params.key?(:config) && !params[:config].is_a?(ActionController::Parameters)
        head :bad_request
      end
    end

    def render_configuration_error(values)
      @configuration_values = McpCatalog.public_configuration_values(@template, values)
      @added_servers = @account.mcp_servers.to_a.group_by { |server| server.metadata["catalog_id"] }
      render :show, status: :unprocessable_entity
    end
end
