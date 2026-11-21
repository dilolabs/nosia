# Moves a note to an active folder in the same account.
class Notes::MovementsController < ApplicationController
  include NotesWorkspaceRendering

  def create
    list_options
    note = note_for_change
    destination = folder_for_change(params[:note_folder_id])
    redirect_to_note(note.move_to(destination))
  end
end
