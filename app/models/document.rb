class Document < ApplicationRecord
  include Chunkable
  include Indexable
  include Sourceable
  include Parsable

  belongs_to :account, optional: true
  belongs_to :author, optional: true
  has_one_attached :file

  validates :file, presence: true

  scope :search, ->(query) {
    query.present? ? where("title ILIKE ?", "%#{query}%") : all
  }

  def self.create_from_blob!(account, signed_id)
    document = account.documents.new
    document.file.attach(signed_id)
    document.save!
    AddDocumentJob.perform_later(document.id)
    document
  end

  # Lexxy uploads a PDF via Active Storage direct upload, then embeds an
  # <action-text-attachment sgid="..."> node carrying the blob's attachable
  # sgid — which is NOT the blob's signed_id (attach(sgid) raises
  # InvalidSignature). Resolve the blob the way Action Text does, then delegate
  # to create_from_blob! with the real signed_id.
  def self.create_from_attachable_sgid!(account, sgid)
    blob = ActionText::Attachable.from_attachable_sgid(sgid)
    raise ActiveRecord::RecordNotFound, "invalid attachable sgid" if blob.nil?

    create_from_blob!(account, blob.signed_id)
  end

  def context
    content
  end

  def titlize!
    update(title: file.filename.to_s)
  end

  def display_title
    title.presence || file.filename.to_s.presence || "Untitled document"
  end

  def source_subtitle
    return "" unless file.attached?
    "#{ActiveSupport::NumberHelper.number_to_human_size(file.byte_size)} · #{file.filename.extension.to_s.upcase.presence || 'FILE'}"
  end
end
