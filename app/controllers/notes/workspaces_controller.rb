# Displays active lists or Trash for one authorized account.
class Notes::WorkspacesController < ApplicationController
  include NotesWorkspaceRendering

  def show
    render_workspace(import_id: params[:import_id])
  end
end
