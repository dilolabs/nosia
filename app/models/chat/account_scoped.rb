# Keeps a chat and its selected resources within its original account.
module Chat::AccountScoped
  extend ActiveSupport::Concern

  included do
    validate :account_is_fixed, on: :update
  end

  # @param website_ids [Array<String, Integer>, nil]
  # @param document_ids [Array<String, Integer>, nil]
  # @return [Hash] Normalized references owned by this chat's account
  # @raise [ActiveRecord::RecordNotFound] if any reference is unavailable
  def source_attributes(website_ids:, document_ids:)
    {
      attached_website_ids: source_ids(account.websites, website_ids),
      attached_document_ids: source_ids(account.documents, document_ids)
    }
  end

  # @param ids [Array<String, Integer>, nil]
  # @return [Array<McpServer>] Account-owned tools, materialized in its tenant context
  # @raise [ActiveRecord::RecordNotFound] if any tool is unavailable
  def selected_mcp_servers(ids)
    requested = normalized_source_ids(ids)

    ActsAsTenant.with_tenant(account) do
      servers = account.mcp_servers.where(id: requested).to_a
      if servers.map { |server| server.id.to_s }.sort != requested.sort
        raise ActiveRecord::RecordNotFound
      end
      servers
    end
  end

  private
    def account_is_fixed
      if will_save_change_to_account_id?
        errors.add(:account, :immutable_chat_account)
      end
    end

    def source_ids(relation, ids)
      requested = normalized_source_ids(ids)
      found = relation.where(id: requested).pluck(:id).map(&:to_s)
      if found.sort != requested.sort
        raise ActiveRecord::RecordNotFound
      end
      requested
    end

    def normalized_source_ids(ids)
      Array(ids).compact_blank.map(&:to_s).uniq
    end
end
