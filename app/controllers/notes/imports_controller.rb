# Opens private uploads and shows their progress without exposing staging.
class Notes::ImportsController < ApplicationController
  include NotesImportScoped

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
    progress = import_progress(import_receipt(:id))

    respond_to do |format|
      format.html { render locals: { progress: } }
      format.json { render json: progress }
    end
  end

  private
    def manifest_files(files)
      return files unless files.is_a?(Array) && files.size <= NoteImport::Manifest::MAX_FILES

      files.map { |file| file.is_a?(Hash) ? { path: file[:path], size: file[:size] } : file }
    end
end
