# Toggles a note's pin in its current folder.
class Notes::PinsController < ApplicationController
  include NotesWorkspaceRendering

  def create
    list_options
    redirect_to_note(with_notes_write { note_for_change.pin_in_folder })
  end

  def destroy
    list_options
    redirect_to_note(with_notes_write { note_for_change.unpin })
  end
end
