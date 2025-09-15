class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  enum :role, { system: 0, assistant: 10, user: 20 }

  belongs_to :chat

  before_create :set_default_role
  after_create_commit -> { broadcast_created }
  after_update_commit -> { broadcast_updated }

  def broadcast_created
    broadcast_append_to chat, :messages, target: dom_id(chat, :messages), locals: { message: self, scroll_to: true }
  end

  def broadcast_updated
    broadcast_update_to chat, :messages, target: dom_id(self, :messages), locals: { message: self, scroll_to: true }
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

  def to_html
    Commonmarker.to_html(content)
  end
end
