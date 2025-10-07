class AddDocumentJob < ApplicationJob
  queue_as :background

  def perform(document_id)
    document = Document.find(document_id)
    document.titlize!
    document.parse!
    document.chunkify! if document.content.present?
  end
end
