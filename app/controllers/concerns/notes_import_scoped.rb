# Restricts import receipts and responses to the initiator of an account upload.
module NotesImportScoped
  extend ActiveSupport::Concern
  include NotesAccountScoped

  AUTH_ERRORS = %i[ membership_required unavailable ].freeze
  CONFLICT_ERRORS = %i[ confirmation_conflict import_in_progress content_conflict not_uploading ].freeze
  INVALID_ERRORS = %i[
    invalid_batch invalid_confirmation_key invalid_root_name invalid_file_count invalid_path depth_limit_exceeded
    duplicate_path invalid_file_size total_size_exceeded path_collision folder_limit_exceeded invalid_ignored_counts
    unexpected_path size_mismatch invalid_payload incomplete_upload
  ].freeze

  included do
    wrap_parameters false
    prepend_before_action :no_store
    around_action :without_import_sql_logging
    rescue_from ActiveRecord::RecordNotFound, with: :render_import_not_found
    rescue_from NoteImport::Invalid, with: :render_import_error
  end

  private
    def import_receipt(param)
      @account.note_imports.where(initiator_id: Current.user.id)
        .find(notes_id(request.path_parameters.fetch(param)))
    end

    def import_progress(import)
      { status: import.status, uploaded_count: import.staged_files.count, total: import.manifest.size }
    end

    def render_import_error(error)
      if AUTH_ERRORS.include?(error.code)
        render_import_not_found
      elsif CONFLICT_ERRORS.include?(error.code)
        render_import_error_code(error.code, :conflict)
      else
        code = INVALID_ERRORS.include?(error.code) ? error.code : :invalid_request
        render_import_error_code(code, :unprocessable_content)
      end
    end

    def render_import_not_found
      if request.post? || request.format.json?
        render_import_error_code(:not_found, :not_found)
      else
        head :not_found
      end
    end

    def render_import_error_code(code, status)
      with_request_locale do
        render json: { error: code, message: t("nosia.notes.imports.errors.#{code}") }, status:
      end
    end

    def without_import_sql_logging(&action)
      # SQL bind logging would otherwise include validated names and path lookups.
      logger = ActiveRecord::Base.logger
      logger ? logger.silence(Logger::INFO, &action) : action.call
    end
end
