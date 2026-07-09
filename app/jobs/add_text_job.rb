class AddTextJob < ApplicationJob
  queue_as :background

  retry_on StandardError, wait: 30.seconds, attempts: 3 do |job, error|
    Text.find_by(id: job.arguments.first)&.mark_indexing_failed!
  end

  discard_on ActiveRecord::RecordNotFound

  def perform(text_id)
    text = Text.find(text_id)
    text.chunkify!
  end
end
