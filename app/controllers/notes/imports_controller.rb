# Opens private uploads and shows their progress without exposing staging.
class Notes::ImportsController < ApplicationController
  include NotesImportScoped

  FAILURE_CODES = (NoteImport::Publication::FAILURE_CODES + %i[processing_timeout worker_claim_expired]).map(&:to_s).freeze

  # @return [void] Renders the import landing page.
  def new
    render formats: [ :html ]
  end

  # @return [void] Renders a new or replayed receipt and its upload URLs.
  def create
    body = request.request_parameters
    import = NoteImport.start!(account: @account, initiator: Current.user, confirmation_key: body[:confirmation_key],
      root_name: body[:root_name], files: manifest_files(body[:files]), ignored_counts: body[:ignored_counts])

    render json: import_progress(import).merge(
      status_url: account_note_import_path(@account, import),
      batch_url: account_note_import_batches_path(@account, import),
      seal_url: account_note_import_seal_path(@account, import)
    ), status: import.previously_new_record? ? :created : :ok
  end

  # @return [void] Renders the private receipt as HTML or JSON.
  def show
    import = import_receipt(:id)
    progress = import_progress(import).merge(message: status_message(import))
    if import.succeeded? && import.root_note_folder_id && active_folders.exists?(id: import.root_note_folder_id)
      progress[:result_url] = account_notes_workspace_path(@account, folder_id: import.root_note_folder_id, import_id: import.id)
    end

    respond_to do |format|
      format.html { render locals: { import:, progress: } }
      format.json { render json: progress }
    end
  end

  private
    def status_message(import)
      if import.failed?
        code = import.report["error"]
        t("nosia.notes.imports.failures.#{FAILURE_CODES.include?(code) ? code : 'generic'}")
      else
        t("nosia.notes.imports.statuses.#{import.status}")
      end
    end

    def manifest_files(files)
      return files unless files.is_a?(Array) && files.size <= NoteImport::Manifest::MAX_FILES

      files.map { |file| file.is_a?(Hash) ? { path: file[:path], size: file[:size] } : file }
    end
end
