# Retries indexing without writing to the note editor.
class Notes::IndexRetriesController < ApplicationController
  include NotesAccountScoped

  prepend_before_action :no_store
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }

  # @return [void] Renders the retry result in place or redirects a plain form back to its note.
  # @raise [ActiveRecord::RecordNotFound] If the note is inactive or inaccessible.
  def create
    note, attempted = with_notes_write do
      note = active_notes.lock("FOR UPDATE OF notes").find(notes_id(request.path_parameters.fetch(:note_id)))
      attempted = note.embedding_failed? && request.request_parameters["expected_generation"] == note.embedding_generation.to_s
      note.retry_index if attempted
      [ note, attempted ]
    end

    current = with_notes_write { active_notes.find(note.id) }
    outcome = retry_outcome(note, current, attempted)
    if turbo_frame_request_id == ActionView::RecordIdentifier.dom_id(current, :index_status)
      render partial: "notes/workspaces/index_status", formats: [ :html ], content_type: "text/html",
        status: outcome == :index_retry_changed ? :conflict : :ok, locals: { account: @account, note: current, outcome: outcome }
    else
      redirect_to account_note_path(@account, current), status: :see_other, alert: outcome && I18n.t("nosia.notes.#{outcome}")
    end
  end

  private
    def retry_outcome(note, current, attempted)
      # Enqueue runs after commit and may immediately mark this generation failed again.
      if !attempted || current.embedding_generation != note.embedding_generation
        :index_retry_changed
      elsif current.embedding_failed?
        :index_retry_not_started
      end
    end
end
