module AccountScoped
  extend ActiveSupport::Concern

  included do
    helper_method :account_owner?
  end

  private
    # @param id [String, Numeric]
    # @return [Account] An account the current user still belongs to
    # @raise [ActiveRecord::RecordNotFound] For malformed or unauthorized IDs
    def member_account(id)
      raise ActiveRecord::RecordNotFound unless id.is_a?(String) || id.is_a?(Numeric)

      Current.user.accounts.find(id)
    end

    def account_owner?(account = @account)
      account.present? && account.owner_id == Current.user.id
    end

    def require_account_owner
      head :forbidden unless account_owner?
    end
end
