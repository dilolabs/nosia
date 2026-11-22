# Seals complete uploads before scheduling background publication.
class Notes::Imports::SealsController < ApplicationController
  include NotesImportScoped

  # @return [void] Current durable state of a finalized receipt.
  def create
    import = import_receipt(:note_import_id)
    seal(import)
    import.enqueue_publication if import.sealed?
    status = NoteImport::TERMINAL_STATUSES.include?(import.status) ? :ok : :accepted
    render json: import_progress(import), status:
  end

  private
    def seal(import)
      import.seal!
    rescue NoteImport::Invalid => error
      # The model rejects an expired upload under lock; acknowledge its terminal receipt.
      raise unless error.code == :expired
    end
end
