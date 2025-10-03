class Chat < ApplicationRecord
  include Completionable

  acts_as_chat
  broadcasts_to ->(chat) { [ chat, "messages" ] }

  belongs_to :account
  belongs_to :user
  has_many :messages, dependent: :destroy

  def first_question
    messages.where(role: "user").order(:created_at).first&.question
  end

  def messages_hash
    messages.where(role: [ "user", "assistant" ]).order(:response_number).map do |message|
      {
        role: message.role,
        content: message.content
      }
    end
  end

  def response_number
    messages.count
  end

  def title
    first_question
  end
end
