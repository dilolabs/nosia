class ApiToken < ApplicationRecord
  belongs_to :account
  belongs_to :user

  attr_accessor :plain_token

  validates :name, presence: true
  validates :token_digest, presence: true

  before_validation :assign_token_digest, on: :create

  # Looks a bearer token up by digest. Plaintext tokens are never stored, so a
  # leaked database cannot be replayed against the API.
  def self.authenticate_token(plain)
    find_by(token_digest: digest(plain.to_s))
  end

  def self.digest(plain)
    OpenSSL::Digest::SHA256.hexdigest(plain)
  end

  def current_membership?
    AccountUser.exists?(account_id: account_id, user_id: user_id)
  end

  private

  # The plaintext exists only in memory between creation and the response that
  # shows it once. Persisted rows keep nothing but the digest.
  def assign_token_digest
    self.plain_token = SecureRandom.base58(24)
    self.token_digest = self.class.digest(plain_token)
  end
end
