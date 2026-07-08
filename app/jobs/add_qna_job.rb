class AddQnaJob < ApplicationJob
  queue_as :background

  retry_on StandardError, wait: 30.seconds, attempts: 3 do |job, error|
    Qna.find_by(id: job.arguments.first)&.mark_indexing_failed!
  end

  discard_on ActiveRecord::RecordNotFound

  def perform(qna_id)
    qna = Qna.find(qna_id)
    qna.chunkify!
  end
end
