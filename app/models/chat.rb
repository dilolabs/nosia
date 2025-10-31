class Chat < ApplicationRecord
  include AnswerRelevance
  include AugmentedPrompt
  include Completionable
  include ContextRelevance
  include SimilaritySearch

  acts_as_chat
  broadcasts_to ->(chat) { [ chat, "messages" ] }

  belongs_to :account
  belongs_to :chat, optional: true
  belongs_to :user
  has_many :chats, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :chat_mcp_sessions, dependent: :destroy
  has_many :mcp_servers, through: :chat_mcp_sessions

  scope :root, -> { where(chat_id: nil) }

  # Get all enabled MCP tools for this chat
  def mcp_tools
    chat_mcp_sessions.enabled.includes(:mcp_server).flat_map do |session|
      next [] unless session.mcp_server.status_ready?
      session.mcp_server.tools
    end.compact
  end

  # Add an MCP server to this chat
  def add_mcp_server(mcp_server)
    chat_mcp_sessions.find_or_create_by(mcp_server: mcp_server)
  end

  # Remove an MCP server from this chat
  def remove_mcp_server(mcp_server)
    chat_mcp_sessions.find_by(mcp_server: mcp_server)&.destroy
  end

  def first_question
    messages.where(role: "user").order(:created_at).first&.question
  end

  def response_number
    messages.count
  end

  def title
    first_question
  end
end
