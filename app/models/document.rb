class Document < ApplicationRecord
  include Chunkable
  include Indexable
  include Parsable

  belongs_to :account, optional: true
  belongs_to :author, optional: true
  has_one_attached :file

  validates :file, presence: true

  def self.create_from_blob!(account, signed_id)
    document = account.documents.new
    document.file.attach(signed_id)
    document.save!
    AddDocumentJob.perform_later(document.id)
    document
  end

  def context
    content
  end

  def titlize!
    update(title: file.filename.to_s)
  end
end
