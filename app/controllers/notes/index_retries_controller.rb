# Retries indexing without writing to the note editor.
class Notes::IndexRetriesController < ApplicationController
  include NotesAccountScoped

  prepend_before_action :no_store
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }

  # @return [void] Redirects back to the frame or the note after attempting a retry.
  # @raise [ActiveRecord::RecordNotFound] If the note is inactive or inaccessible.
  def create
    note, generation = with_notes_write do
      note = active_notes.find(notes_id(request.path_parameters.fetch(:note_id)))
      generation = note.embedding_generation if note.embedding_failed?
      note.retry_index
      [ note, generation ]
    end

    destination = if turbo_frame_request_id == ActionView::RecordIdentifier.dom_id(note, :index_status)
      account_note_index_status_path(@account, note, retry_failed: failed_retry_generation(note.id, generation))
    else
      account_note_path(@account, note)
    end
    redirect_to destination, status: :see_other
  end

  private
    def failed_retry_generation(id, generation)
      # Enqueue runs after commit and can immediately mark this generation failed again.
      if generation && active_notes.embedding_failed.exists?(id: id, embedding_generation: generation)
        generation
      end
    end
end
