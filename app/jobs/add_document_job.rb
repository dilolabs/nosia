class AddDocumentJob < ApplicationJob
  queue_as :background

  retry_on StandardError, wait: 30.seconds, attempts: 3 do |job, error|
    Document.find_by(id: job.arguments.first)&.mark_indexing_failed!
  end

  discard_on ActiveRecord::RecordNotFound

  def perform(document_id)
    document = Document.find(document_id)
    document.titlize!
    document.parse!
    document.chunkify! if document.content.present?
  end
end
