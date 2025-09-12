class Document < ApplicationRecord
  include Chunkable, Parsable, Vectorizable

  belongs_to :account, optional: true
  belongs_to :author, optional: true
  has_one_attached :file

  validates :file, presence: true

  def context
    content
  end

  def titlize!
    update(title: file.filename.to_s)
  end
end
