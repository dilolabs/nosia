# Permanently deletes a directly trashed branch at the account owner's request.
class Notes::FolderPurgesController < ApplicationController
  include NotesAccountScoped

  def destroy
    trashed_folder.purge(by: Current.user)
    redirect_to_notes_trash
  end
end
