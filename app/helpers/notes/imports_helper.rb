module Notes::ImportsHelper
  DEFAULT_BATCH_BYTES = 3.megabytes
  MULTIPART_HEADROOM = 64.kilobytes

  def note_import_preview_limits
    manifest = NoteImport::Manifest
    {
      files: manifest::MAX_FILES, folders: manifest::MAX_FOLDERS,
      depth: manifest::MAX_DEPTH, componentBytes: manifest::MAX_COMPONENT_BYTES, pathBytes: manifest::MAX_PATH_BYTES,
      fileBytes: manifest::MAX_FILE_BYTES, totalBytes: manifest::MAX_TOTAL_BYTES,
      ignoredCount: manifest::MAX_IGNORED_COUNT, batchFiles: NoteImport::MAX_BATCH_FILES, batchBytes: note_import_batch_bytes
    }
  end

  def note_import_error_message(code)
    t("nosia.notes.imports.errors.#{code}", **note_import_limit_labels)
  end

  def note_import_limit_labels
    manifest = NoteImport::Manifest
    {
      max_files: manifest::MAX_FILES, max_folders: manifest::MAX_FOLDERS, max_depth: manifest::MAX_DEPTH,
      max_file_mib: manifest::MAX_FILE_BYTES / 1.megabyte, max_total_mib: manifest::MAX_TOTAL_BYTES / 1.megabyte,
      max_batch_files: NoteImport::MAX_BATCH_FILES
    }
  end

  private
    def note_import_batch_bytes
      wire_bytes = Integer(ENV.fetch("NOTES_IMPORT_BATCH_WIRE_BYTES", ""), exception: false)
      if wire_bytes&.positive?
        (wire_bytes - MULTIPART_HEADROOM).clamp(0, DEFAULT_BATCH_BYTES)
      else
        DEFAULT_BATCH_BYTES
      end
    end
end
