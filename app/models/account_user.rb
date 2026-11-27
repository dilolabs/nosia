class AccountUser < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :account, presence: true
  validates :user, uniqueness: { scope: :account_id }

  before_update :revoke_membership_credentials, if: -> { will_save_change_to_account_id? || will_save_change_to_user_id? }
  before_destroy :revoke_membership_credentials, prepend: true

  private
    def revoke_membership_credentials
      previous_account = account_id_in_database
      Account.where(id: [ previous_account, account_id ]).order(:id).lock.load
      McpAuthorization.uncached do
        self.class.where(account_id: previous_account).find(id)
        McpAuthorization.where(account_id: previous_account, account_user_id: id).find_each(&:retire!)
      end
      ApiToken.where(account_id: previous_account, user_id: user_id_in_database).delete_all
    end
end
