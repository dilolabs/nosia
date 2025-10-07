class User < ApplicationRecord
  has_secure_password

  has_many :account_users, dependent: :destroy
  has_many :accounts, through: :account_users
  has_many :api_tokens, dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :credentials, dependent: :destroy
  has_many :sessions, dependent: :destroy

  validates :email,
    presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :password,
    presence: true,
    length: { minimum: 12 },
    on: :create

  def self.create_with_account!(user_params)
    user = User.create!(user_params)

    account = Account.create!(name: FirstRun::ACCOUNT_NAME, owner: user)
    account.account_users.grant_to user

    user
  end

  def first_account
    accounts.order(:created_at).first
  end

  def recent_chats(limit: 5)
    chats.order(:created_at).limit(limit)
  end
end
