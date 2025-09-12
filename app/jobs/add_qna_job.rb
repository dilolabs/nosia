class AddQnaJob < ApplicationJob
  queue_as :default

  def perform(qna_id)
    qna = Qna.find(qna_id)
    qna.chunkify!
  end
end
