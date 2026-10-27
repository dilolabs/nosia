# Authorizes MCP account URLs without changing the user's default account.
module McpScoped
  extend ActiveSupport::Concern
  include AccountScoped
  include McpWorkspaceHelper

  included { around_action :with_mcp_account }

  private
    def with_mcp_account
      @mcp_scoped = request.path_parameters.key?(:account_id)
      @account = @mcp_scoped ? member_account(mcp_path_id(:account_id)) : Current.account

      if @account
        ActsAsTenant.with_tenant(@account) { yield }
      elsif request.get? && (controller_path == "mcp_catalog" || (controller_path == "mcp_servers" && %w[index new].include?(action_name)))
        render "mcp_workspace/setup", formats: [ :html ]
      else
        head :not_found
      end
    end

    def mcp_path_id(key)
      value = request.path_parameters[key]
      raise ActiveRecord::RecordNotFound unless value.is_a?(String) && value.match?(/\A[0-9]+\z/)

      value
    end

    def set_mcp_server
      key = request.path_parameters.key?(:mcp_server_id) ? :mcp_server_id : :id
      @mcp_server = @account.mcp_servers.find(mcp_path_id(key))
    end
end
