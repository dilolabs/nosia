# Processes a sealed Notes import without serializing any staged input.
class NoteImport::PublishJob < ApplicationJob
  queue_as :default

  # @param import_id [Integer] Private receipt identifier.
  # @return [NoteImport, nil] The current receipt, if it still exists.
  def perform(import_id)
    NoteImport.find_by(id: import_id)&.process_now
  end
end
