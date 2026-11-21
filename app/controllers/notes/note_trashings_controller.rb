# Hides an active note or restores a directly trashed note.
class Notes::NoteTrashingsController < ApplicationController
  include NotesAccountScoped

  def create
    note_for_change.trash
    redirect_to_notes_trash
  end

  def destroy
    trashed_note.restore
    redirect_to_notes_trash
  end
end
