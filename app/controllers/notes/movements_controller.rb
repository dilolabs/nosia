# Moves a note to an active folder in the same account.
class Notes::MovementsController < ApplicationController
  include NotesWorkspaceRendering

  def create
    list_options
    note = with_notes_write do
      note_for_change.move_to(folder_for_change(params[:note_folder_id]))
    end
    redirect_to account_note_path(@account, note, folder_id: note.note_folder_id), status: :see_other
  end
end
