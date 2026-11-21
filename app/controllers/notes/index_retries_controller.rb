# Retries indexing without writing to the note editor.
class Notes::IndexRetriesController < ApplicationController
  include NotesAccountScoped

  prepend_before_action :no_store
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }

  # @return [void] Redirects back to the frame or the note after attempting a retry.
  # @raise [ActiveRecord::RecordNotFound] If the note is inactive or inaccessible.
  def create
    note = with_notes_write do
      active_notes.find(notes_id(request.path_parameters.fetch(:note_id))).tap(&:retry_index)
    end

    destination = if turbo_frame_request_id == "note-index-status"
      account_note_index_status_path(@account, note)
    else
      account_note_path(@account, note)
    end
    redirect_to destination, status: :see_other
  end
end
