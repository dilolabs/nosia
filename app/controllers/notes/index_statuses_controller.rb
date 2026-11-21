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
    render partial: "notes/workspaces/index_status", formats: [ :html ], content_type: "text/html",
      locals: { account: @account, note: note }
  end
end
