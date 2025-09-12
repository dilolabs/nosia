class AddTextJob < ApplicationJob
  queue_as :default

  def perform(text_id)
    text = Text.find(text_id)
    text.chunkify!
  end
end
