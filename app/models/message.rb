class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  acts_as_message
  broadcasts_to ->(message) { [ message.chat, "messages" ] }
  has_many_attached :attachments

  scope :for_user, -> { without_system_prompts.without_relevance_steps }
  scope :without_system_prompts, -> { where.not(role: :system) }
  scope :without_relevance_steps, -> { where.not(step: [ "context_relevance", "answer_relevance" ]) }

  enum :role, { system: 0, assistant: 10, user: 20 }

  belongs_to :chat

  before_create :set_default_role
  before_create :set_step_from_chat
  after_create_commit -> { broadcast_created }
  after_update_commit -> { broadcast_updated }

  # Helper to broadcast chunks during streaming
  def broadcast_append_chunk(chunk_content)
    return unless step == "default" # Ne broadcaster que les messages visibles par l'utilisateur
    broadcast_update_to [ chat, "messages" ],
      target: dom_id(self, "content"),
      html: Commonmarker.to_html(self.content, options: { parse: { smart: true }, extension: { table: true, autolink: true, strikethrough: true }, render: { unsafe: true } })
  end

  def broadcast_created
    return if system?
    return unless step == "default" # Ne broadcaster que les messages visibles par l'utilisateur

    # Ne pas broadcaster si un message utilisateur identique existe déjà (éviter les doublons)
    if user? && chat.messages.where(role: :user, content: content).where.not(id: id).exists?
      return
    end

    broadcast_append_to chat, :messages, target: dom_id(chat, :messages), locals: { message: self, scroll_to: true }
  end

  def broadcast_updated
    return unless step == "default" # Ne broadcaster que les messages visibles par l'utilisateur
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
    nil unless content.present?
    content_without_context
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

  def set_step_from_chat
    # Si le chat a défini un step pour les prochains messages, l'utiliser
    if chat.instance_variable_defined?(:@next_message_step) && chat.instance_variable_get(:@next_message_step)
      self.step = chat.instance_variable_get(:@next_message_step)
    end
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
end
