class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  acts_as_message
  broadcasts_to ->(message) { [ message.chat, "messages" ] }
  has_many_attached :attachments

  scope :for_user, -> { without_system_prompts.with_content.without_tool_calls }
  scope :without_system_prompts, -> { where.not(role: [:system, :tool]) }
  scope :with_content, -> { where("role != 10 OR (role = 10 AND content IS NOT NULL AND content != '')") }
  scope :without_tool_calls, -> {
    left_joins(:tool_calls)
      .where("messages.role != 30 OR tool_calls.id IS NULL")
      .distinct
  }

  enum :role, { system: 0, assistant: 10, user: 20, tool: 30 }

  belongs_to :chat
  has_many :tool_calls, dependent: :destroy

  before_create :set_default_role
  after_create_commit -> { broadcast_created }
  after_update_commit -> { broadcast_updated }

  # Helper to broadcast chunks during streaming
  def broadcast_append_chunk(chunk_content)
    return unless assistant?

    broadcast_append_to [ chat, "messages" ], # Target the stream
      target: dom_id(self, "content"), # Target the content div inside the message frame
      html: chunk_content # Append the raw chunk
  end

  def broadcast_created
    # Do not broadcast system and tool messages (internal)
    return unless assistant?

    # EN: If it's an assistant message with tool_calls, DO NOT broadcast
    # They are intermediate messages not meant for the user
    if assistant? && tool_calls.exists?
      Rails.logger.info "🚫 Skipping broadcast for intermediate assistant message ##{id} with tool_calls"
      return
    end

    # Prevent broadcasting consecutive duplicate user messages
    # If the last message (excluding this one) is a user message with the same content
    # and there was no assistant message in between, do not broadcast
    if user?
      previous_message = chat.messages.where.not(id: id).order(created_at: :desc).first
      if previous_message&.user? && previous_message.question == question
        # It's a duplicate, do not broadcast
        return
      end
    end

    # If it's an assistant message, remove the thinking animation
    if assistant?
      broadcast_remove_to chat, :messages, target: "thinking_animation"

      previous_message = chat.messages.where.not(id: id).order(created_at: :desc).first
      if previous_message&.assistant? && previous_message.content.blank?
        # Remove the previous empty assistant message
        broadcast_remove_to chat, :messages, target: dom_id(previous_message, :messages)
      end

      if previous_message&.tool?
        # Remove the previous tool message
        broadcast_remove_to chat, :messages, target: dom_id(previous_message, :messages)
      end
    end

    broadcast_append_to chat, :messages, target: dom_id(chat, :messages), locals: { message: self, scroll_to: true }
  end

  def broadcast_updated
    return unless assistant?

    broadcast_update_to chat, :messages, target: dom_id(self, :messages), locals: { message: self, scroll_to: true }
  end

  def content_without_context
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.present?
    doc.at("context")&.remove
    Commonmarker.to_html(doc.to_html)
  end

  def context
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.at("content").present?
    Commonmarker.to_html(doc.at("context").to_html)
  end

  def question
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.present?
    doc.at("context")&.remove
    doc.to_html
  end

  def reasoning_content
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.at("think").present?
    Commonmarker.to_html(doc.at("think").to_html)
  end

  def response_content
    return unless content.present?
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    return unless doc.present?
    doc.at("think")&.remove
    Commonmarker.to_html(doc.to_html)
  end

  def set_default_role
    self.role ||= "user"
  end

  def similar_authors
    Author.where(id: similar_documents.pluck(:author_id))
  end

  def similar_chunks
    Chunk.where(id: similar_chunk_ids.uniq)
  end

  def similar_documents
    Document.where(id: similar_document_ids.uniq)
  end

  # Helper to check if it's an error message
  def error?
    false
  end

  # Helper to get the original message for retry
  def retryable?
    false
  end
end
