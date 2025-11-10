class Account < ApplicationRecord
  belongs_to :owner, class_name: "User"

  has_many :account_users, dependent: :destroy do
    def grant_to(users)
      account = proxy_association.owner
      AccountUser.insert_all(Array(users).collect { |user| { account_id: account.id, user_id: user.id } })
    end
  end
  has_many :api_tokens, dependent: :destroy
  has_many :users, through: :account_users
  has_many :chats, dependent: :destroy
  has_many :chunks, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :mcp_servers, dependent: :destroy
  has_many :prompts, dependent: :destroy
  has_many :qnas, dependent: :destroy
  has_many :texts, dependent: :destroy
  has_many :websites, dependent: :destroy

  def self.create_with_system_prompt!(attributes)
    account = Account.create!(attributes)

    account.account_users.grant_to(account.owner)

    content = default_system_prompt
    account.prompts.create!(name: "system_prompt", content:)
    account.prompts.create!(user: account.owner, name: "system_prompt", content:)

    account
  end

  def augmented_context
    context = []
    context << texts.map(&:context)
    context << qnas.map(&:context)
    context << documents.map(&:context)
    context
  end

  def default_context
    context = []
    context << texts.map(&:context)
    context
  end

  def default_system_prompt
    YAML.load_file(Rails.root.join("config", "prompts.yml"))["system_prompt"]
  end

  def system_prompt(user: nil)
    prompt = prompts.find_by(name: "system_prompt", user_id: user&.id)
    prompt ||= prompts.find_by(name: "system_prompt", user_id: nil)
    prompt.present? ? prompt.content : default_system_prompt
  end
end
