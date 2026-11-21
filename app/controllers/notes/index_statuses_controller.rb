# Shows the saved indexing state of an active account note.
class Notes::IndexStatusesController < ApplicationController
  include NotesAccountScoped

  prepend_before_action :no_store
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }

  # @return [void] Renders only the status frame, with no note content.
  # @raise [ActiveRecord::RecordNotFound] If the note is inactive or inaccessible.
  def show
    note = active_notes.select(:id, :embedding_status, :embedding_generation, :content_revision, :updated_at)
      .find(notes_id(request.path_parameters.fetch(:note_id)))
    retry_failed = turbo_frame_request_id == ActionView::RecordIdentifier.dom_id(note, :index_status) && note.embedding_failed? &&
      request.query_parameters["retry_failed"] == note.embedding_generation.to_s
    render partial: "notes/workspaces/index_status", formats: [ :html ], content_type: "text/html",
      locals: { account: @account, note: note, retry_failed: retry_failed }
  end
end
