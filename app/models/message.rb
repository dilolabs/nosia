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
    # Ne pas broadcaster les messages system et tool (internes)
    return unless assistant?

    # Si c'est un message assistant avec des tool_calls, NE PAS broadcaster
    # Ces messages sont créés par RubyLLM juste avant d'exécuter un tool
    if assistant? && tool_calls.exists?
      Rails.logger.info "🚫 Skipping broadcast for intermediate assistant message ##{id} with tool_calls"
      return
    end

    # Empêcher le broadcast des doublons consécutifs
    # Si le dernier message (hors celui-ci) est un message user avec le même contenu
    # et qu'il n'y a pas eu de message assistant entre, ne pas broadcaster
    if user?
      previous_message = chat.messages.where.not(id: id).order(created_at: :desc).first
      if previous_message&.user? && previous_message.question == question
        # C'est un doublon, ne pas broadcaster
        return
      end
    end

    # Si c'est un message assistant, retirer l'animation de réflexion
    if assistant?
      broadcast_remove_to chat, :messages, target: "thinking_animation"

      previous_message = chat.messages.where.not(id: id).order(created_at: :desc).first
      if previous_message&.assistant? && previous_message.content.blank?
        # Retirer le message vide précédent
        broadcast_remove_to chat, :messages, target: dom_id(previous_message, :messages)
      end

      if previous_message&.tool?
        # Retirer le message tool précédent
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

  # Helper pour vérifier si c'est un message d'erreur
  def error?
    false
  end

  # Helper pour obtenir le message original pour retry
  def retryable?
    false
  end
end
