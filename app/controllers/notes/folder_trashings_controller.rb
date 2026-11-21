# Hides or restores an entire folder branch through its root's trash marker.
class Notes::FolderTrashingsController < ApplicationController
  include NotesAccountScoped

  def create
    with_notes_write { folder_for_change(request.path_parameters.fetch(:note_folder_id)).trash }
    redirect_to_notes_trash
  end

  def destroy
    with_notes_write { trashed_folder.restore }
    redirect_to_notes_trash
  end
end
