class AccountUser < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :account, presence: true
  validates :user, uniqueness: { scope: :account_id }

  before_update :retire_mcp_authorizations, if: -> { will_save_change_to_account_id? || will_save_change_to_user_id? }
  before_destroy :retire_mcp_authorizations, prepend: true

  private
    def retire_mcp_authorizations
      previous_account = account_id_in_database
      Account.where(id: [ previous_account, account_id ]).order(:id).lock.load
      McpAuthorization.uncached do
        self.class.where(account_id: previous_account).find(id)
        McpAuthorization.where(account_id: previous_account, account_user_id: id).find_each(&:retire!)
      end
    end
end
