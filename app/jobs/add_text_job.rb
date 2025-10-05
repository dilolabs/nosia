class AddTextJob < ApplicationJob
  queue_as :background

  def perform(text_id)
    text = Text.find(text_id)
    text.chunkify!
  end
end
