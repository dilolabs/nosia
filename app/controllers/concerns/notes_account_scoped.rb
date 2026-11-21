# Resolves Notes resources through the requested membership and maps lifecycle errors.
module NotesAccountScoped
  extend ActiveSupport::Concern
  include AccountScoped

  included do
    before_action :set_notes_account
    rescue_from Note::EditConflict, with: :render_edit_conflict
    rescue_from Note::Unavailable, ActiveRecord::RecordInvalid, with: :render_unavailable
    rescue_from Note::PurgeForbidden, with: -> { head :forbidden }
  end

  private
    def set_notes_account
      @account = member_account(notes_id(request.path_parameters.fetch(:account_id)))
    end

    def notes_id(id)
      return id if id.is_a?(String) && /\A[1-9][0-9]{0,18}\z/.match?(id)

      raise ActiveRecord::RecordNotFound
    end

    def active_notes
      Note.active_in(@account.id)
    end

    def active_folders
      NoteFolder.active_in(@account.id)
    end

    def note_for_change
      id = notes_id(request.path_parameters.fetch(:note_id))
      active_for_change(active_notes, @account.notes, id)
    end

    def folder_for_change(id)
      active_for_change(active_folders, @account.note_folders, notes_id(id))
    end

    def active_for_change(active, all, id)
      active.find_by(id:) || unavailable_item(all, id)
    end

    def trashed_note
      id = notes_id(request.path_parameters.fetch(:note_id))
      @account.notes.joins(:trashing).find_by(id:, note_trashings: { account_id: @account.id }) ||
        unavailable_item(@account.notes, id)
    end

    def trashed_folder
      id = notes_id(request.path_parameters.fetch(:note_folder_id))
      @account.note_folders.joins(:trashing).find_by(id:, note_folder_trashings: { account_id: @account.id }) ||
        unavailable_item(@account.note_folders, id)
    end

    def unavailable_item(scope, id)
      scope.find(id)
      raise Note::Unavailable
    end

    def render_edit_conflict
      render_notes_conflict("edit_conflict")
    end

    def render_unavailable
      render_notes_conflict("unavailable")
    end

    def render_notes_conflict(message)
      @notes_conflict_message = message
      # rescue_from runs after the regular locale around-action unwinds.
      with_request_locale do
        render "notes/workspaces/conflict", formats: [ :html ], status: :conflict
      end
    end

    def redirect_to_notes_trash
      redirect_to account_notes_workspace_path(@account, view: "trash"), status: :see_other
    end
end
