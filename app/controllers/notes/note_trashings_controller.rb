# Hides an active note or restores a directly trashed note.
class Notes::NoteTrashingsController < ApplicationController
  include NotesAccountScoped

  def create
    with_notes_write { note_for_change.trash }
    redirect_to_notes_trash
  end

  def destroy
    with_notes_write { trashed_note.restore }
    redirect_to_notes_trash
  end
end
