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
  has_many :qnas, dependent: :destroy
  has_many :texts, dependent: :destroy
  has_many :websites, dependent: :destroy

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
end
