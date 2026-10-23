class User < ApplicationRecord
  has_secure_password

  # Supports validation error rendering without retaining the authorization password.
  # @return [nil] An unset attribute used only to render credential validation errors.
  attr_reader :current_password

  has_many :account_users, dependent: :destroy
  has_many :accounts, through: :account_users
  has_many :api_tokens, dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :credentials, dependent: :destroy
  has_many :prompts, dependent: :destroy
  has_many :sessions, dependent: :destroy

  validates :email,
    presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :password,
    presence: true,
    length: { minimum: 12 },
    on: [ :create, :password_change ]

  validates :password_confirmation, presence: true, on: :password_change

  encrypts :email, deterministic: true

  def self.create_with_account!(user_params)
    user = User.create!(user_params)
    user.create_default_system_prompt!

    account = Account.create!(name: FirstRun::ACCOUNT_NAME, owner: user)
    account.account_users.grant_to user
    account.create_default_system_prompt!
    account.create_default_system_prompt!(user:)

    user
  end

  def create_default_system_prompt!(account: nil)
    prompts.where(name: "system_prompt", account:).first_or_create!(
      content: YAML.load_file(Rails.root.join("config", "prompts.yml"))["system_prompt"]
    )
  end

  def first_account
    accounts.order(:created_at).first
  end

  def recent_chats(limit: 5)
    chats.order(:created_at).limit(limit)
  end

  # Changes the email after verifying the persisted password, preserving browser sessions.
  # @param email [String, nil] The replacement email address.
  # @param current_password [String, nil] The password authorizing the change.
  # @return [Boolean] Whether the email was saved, including an unchanged address.
  def change_email(email:, current_password:)
    with_lock(requires_new: true) do
      self.email = email
      if credential_password_valid?(current_password)
        save
      else
        false
      end
    end
  rescue ActiveRecord::RecordNotUnique
    errors.add(:email, :taken)
    false
  end

  # Changes the password and atomically revokes every other browser session for this user.
  # @param password [String, nil] The replacement password.
  # @param password_confirmation [String, nil] Confirmation of the replacement password.
  # @param current_password [String, nil] The password authorizing the change.
  # @param session [Session] The submitting browser session to retain.
  # @return [Boolean] Whether the password was saved and other sessions revoked.
  # @raise [ActiveRecord::RecordNotFound] If the retained session does not belong to this user.
  def change_password(password:, password_confirmation:, current_password:, session:)
    with_lock(requires_new: true) do
      retained_session = sessions.find(session.id)
      if credential_password_valid?(current_password)
        self.password = nil # Clear virtual state because has_secure_password ignores empty strings.
        assign_attributes(password: password, password_confirmation: password_confirmation)
        if save(context: :password_change)
          sessions.where.not(id: retained_session.id).delete_all
          true
        else
          false
        end
      else
        false
      end
    end
  end

  private
    def credential_password_valid?(current_password)
      errors.clear
      if authenticate(current_password.to_s)
        true
      else
        errors.add(:current_password, :invalid)
        false
      end
    end
end
