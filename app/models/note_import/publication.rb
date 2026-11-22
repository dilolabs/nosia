# Prepares one leased import, then atomically publishes its entire Notes tree and receipt.
module NoteImport::Publication
  extend ActiveSupport::Concern

  FAILURE_CODES = %i[
    staging_unavailable membership_revoked empty_import rendered_file_size_exceeded
    rendered_total_size_exceeded invalid_rendered_content publication_failed
  ].freeze

  # An unexpected worker error, safe for the job backend to log.
  class ProcessingError < StandardError; end

  # Claims and publishes an import; duplicate deliveries return its current receipt.
  # @return [NoteImport, nil] Current receipt, or nil if removed.
  # @raise [ProcessingError] If an unexpected error interrupted the attempt.
  def process_now
    self.class.without_import_sql_logging do
      process_claim
    end
  rescue StandardError
    # Unexpected errors leave recovery to the lease sweeper. Do not expose an
    # exception chain from a parser, database driver or after-commit callback.
    raise ProcessingError, "Notes import worker interrupted", cause: nil
  end

  # @api private
  # Saves final Notes and the successful receipt in one account-locked transaction.
  # @param token [String] The worker's claim.
  # @param documents [Array<NoteImport::Markdown::Prepared>] Fully prepared logical documents.
  # @return [NoteImport] The published receipt (including on replay).
  # @raise [NoteImport::Invalid, ActiveRecord::RecordInvalid] If publication is no longer permitted or a write is rejected.
  def publish_prepared(token, documents)
    with_locked_import do |locked_account|
      unless succeeded?
        require_live_claim(token)
        unless locked_account.account_users.exists?(user_id: initiator_id)
          raise NoteImport::Invalid.new(:membership_revoked)
        end

        folders = create_import_folders(locked_account, documents)
        save_import_notes(locked_account, folders, documents)
        root = folders.fetch("")
        update!(status: :succeeded, root_note_folder_id: root.id, report: success_report(root, folders, documents),
          claim_token: nil, claim_expires_at: nil)
      end
    end
  end

  private
    def process_claim
      if (token = claim)
        publish_prepared(token, prepare_documents(token))
        schedule_staging_cleanup
      end
      self
    rescue NoteImport::Invalid => error
      return if error.code == :unavailable
      return self if error.code == :stale_claim

      finish_failed_attempt(token, FAILURE_CODES.include?(error.code) ? error.code : :publication_failed)
    rescue ActiveRecord::Encryption::Errors::Base
      finish_failed_attempt(token, :staging_unavailable)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid
      finish_failed_attempt(token, :publication_failed)
    end

    def finish_failed_attempt(token, code)
      # Publication has rolled back (or an after-commit operation failed).
      # Only the still-current attempt can record a failure.
      reload
      if token && fail_processing(token, code)
        schedule_staging_cleanup
      end
      self
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def prepare_documents(token)
      converter = NoteImport::Markdown.new(manifest.keys)
      total_bytes = 0
      manifest.each_key.map do |path|
        raise NoteImport::Invalid.new(:stale_claim) unless renew_claim(token)

        converter.prepare(path, read_staged_payload(token, path)).tap do |document|
          total_bytes += document.prepared_bytesize
          enforce_render_budget(total_bytes)
        end
      end
    end

    def enforce_render_budget(total_bytes)
      if total_bytes > NoteImport::Markdown::MAX_TOTAL_RENDERED_BYTES
        raise NoteImport::Invalid.new(:rendered_total_size_exceeded)
      end
    end

    def create_import_folders(locked_account, documents)
      root = locked_account.note_folders.create!(name: unused_root_name(locked_account))
      directories = documents.flat_map { |document| directory_prefixes(document.directory) }
      directories.uniq.sort_by { |path| path.count("/") }.each_with_object({ "" => root }) do |path, folders|
        parent, _, name = path.rpartition("/")
        folders[path] = locked_account.note_folders.create!(name:, parent: folders.fetch(parent))
      end
    end

    def unused_root_name(locked_account)
      taken = locked_account.note_folders.where(parent_id: nil).pluck(:name).map(&:unicode_normalize).to_set
      taken.add("General") # The canonical system folder may not have been created yet.
      return root_name unless taken.include?(root_name)

      (2..).each do |number|
        suffix = " (#{number})"
        stem = root_name.byteslice(0, NoteImport::Manifest::MAX_COMPONENT_BYTES - suffix.bytesize).scrub("")
        name = stem + suffix
        return name unless taken.include?(name)
      end
    end

    def directory_prefixes(directory)
      prefix = ""
      directory.split("/").map do |name|
        prefix = prefix.empty? ? name : "#{prefix}/#{name}"
      end
    end

    def save_import_notes(locked_account, folders, documents)
      ids = reserve_note_ids(documents.size)
      routes = Rails.application.routes.url_helpers
      urls = documents.map(&:path).zip(ids).to_h.transform_values { |id| routes.account_note_path(locked_account, id) }
      total_bytes = 0
      documents.zip(ids).each do |document, id|
        html = document.render(urls)
        total_bytes += html.bytesize
        enforce_render_budget(total_bytes)
        Note.save_imported_note!(account: locked_account, folder: folders.fetch(document.directory),
          reserved_id: id, title: document.title, body_html: html)
      end
    end

    def reserve_note_ids(count)
      raise NoteImport::Invalid.new(:empty_import) if count.zero?
      raise NoteImport::Invalid.new(:publication_failed) unless count.between?(1, NoteImport::Manifest::MAX_FILES)

      Note.with_connection do |connection|
        connection.select_values(<<~SQL).map(&:to_i)
          SELECT nextval(pg_get_serial_sequence('notes', 'id')) FROM generate_series(1, #{Integer(count)})
        SQL
      end
    end

    def success_report(root, folders, documents)
      { root_name: root.name, note_count: documents.size, folder_count: folders.size, ignored_counts:,
        unresolved_count: documents.sum { |document| document.warnings.fetch(:count) },
        unresolved_examples: documents.flat_map { |document| document.warnings.fetch(:examples) } }
    end
end
