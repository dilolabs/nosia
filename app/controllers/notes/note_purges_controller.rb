# Permanently deletes a directly trashed note at the account owner's request.
class Notes::NotePurgesController < ApplicationController
  include NotesAccountScoped

  def destroy
    trashed_note.purge(by: Current.user)
    redirect_to_notes_trash
  end
end
