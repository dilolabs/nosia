class Chat < ApplicationRecord
  include Completionable
  include Infomaniak
  include Ollama

  belongs_to :account
  belongs_to :user
  has_many :messages, -> { order(:response_number) }, dependent: :destroy

  def first_question
    messages.where(role: "user").order(:created_at).first&.content
  end

  def last_question
    messages.where(role: "user").order(:created_at).last&.content
  end

  def messages_hash
    messages.order(:response_number).map do |message|
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
