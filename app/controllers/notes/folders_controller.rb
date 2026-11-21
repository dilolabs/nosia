# Creates, renames, and moves authorized folders.
class Notes::FoldersController < ApplicationController
  include NotesWorkspaceRendering

  def new
    @folder = @account.note_folders.build(parent_id: real_folder_id)
    render_folder_form
  end

  def create
    @folder = @account.note_folders.build(name: folder_params[:name], parent: parent_from_form)
    save_folder
  end

  def edit
    @folder = active_folders.find(notes_id(request.path_parameters.fetch(:id)))
    list_options
    render_folder_form
  end

  def update
    @folder = folder_for_change(request.path_parameters.fetch(:id))
    raise Note::Unavailable if @folder.general?

    @folder.assign_attributes(name: folder_params[:name], parent: parent_from_form)
    save_folder
  end

  private
    def folder_params
      @folder_params ||= params.expect(note_folder: [ :name, :parent_id ])
    end

    def parent_from_form
      list_options
      raw = params[:note_folder]
      if raw.key?(:parent_id)
        folder_for_change(raw[:parent_id]) unless raw[:parent_id] == ""
      elsif @folder&.parent_id
        folder_for_change(@folder.parent_id.to_s)
      end
    end

    def save_folder
      if @folder.save
        redirect_to account_notes_workspace_path(@account, folder_id: @folder.id), status: :see_other
      elsif (@folder.persisted? && !active_folders.exists?(id: @folder.id)) ||
          (@folder.parent_id && !active_folders.exists?(id: @folder.parent_id))
        render_unavailable
      else
        render_folder_form(status: :unprocessable_entity)
      end
    end

    def render_folder_form(status: :ok)
      render_workspace(screen: "folder_form", status:)
    end
end
