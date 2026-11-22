# Validates the upload envelope before passing file bytes to staging.
class Notes::Imports::BatchesController < ApplicationController
  include NotesImportScoped

  # @return [void] Acknowledges validated paths, including identical retries.
  def create
    import = import_receipt(:note_import_id)
    entries = batch_entries(import)
    import.stage!(entries)
    render json: import_progress(import).merge(accepted_count: entries.pluck(:path).uniq.size)
  end

  private
    def batch_entries(import)
      entries = request.request_parameters[:entries]
      unless entries.is_a?(Array) && entries.size.between?(1, NoteImport::MAX_BATCH_FILES) && entries.all? { |entry| uploaded_entry?(entry) }
        raise NoteImport::Invalid.new(:invalid_batch)
      end

      files = entries.map { |entry| validate_upload(import, entry) }
      files.map do |path, file, size|
        bytes = file.read(size + 1) || "".b
        raise NoteImport::Invalid.new(:size_mismatch) unless bytes.bytesize == size

        { path:, bytes: }
      end
    end

    def uploaded_entry?(entry)
      entry.is_a?(Hash) && entry[:path].is_a?(String) && entry[:file].is_a?(ActionDispatch::Http::UploadedFile)
    end

    def validate_upload(import, entry)
      path = NoteImport::Manifest.normalize_path(entry[:path])
      size = import.manifest.fetch(path) { raise NoteImport::Invalid.new(:unexpected_path) }
      file = entry[:file]
      raise NoteImport::Invalid.new(:invalid_file_size) if file.size > NoteImport::Manifest::MAX_FILE_BYTES
      raise NoteImport::Invalid.new(:size_mismatch) unless file.size == size

      [ path, file, size ]
    end
end
