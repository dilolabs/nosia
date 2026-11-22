# Discards one private, unfinished upload without removing its receipt.
class Notes::Imports::CancellationsController < ApplicationController
  include NotesImportScoped

  def create
    import = import_receipt(:note_import_id)
    render json: import_progress(import.discard_upload)
  end
end
