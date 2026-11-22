# One member's private upload and retry-safe receipt for a Notes folder import.
class NoteImport < ApplicationRecord
  DESTROY_ONLY = "Note imports must be destroyed with their staged files".freeze

  # Bulk deletion skips the locked cleanup used by receipt and account destruction.
  module DestroyOnlyCollection
    def delete_all(*)
      raise ActiveRecord::ReadOnlyRecord, DESTROY_ONLY
    end
  end

  # Safe validation details for callers to translate. A path is included only after validation.
  class Invalid < StandardError
    attr_reader :code, :path

    # @param code [Symbol] Application-defined error code.
    # @param path [String, nil] Validated logical Markdown path, if available.
    def initialize(code, path: nil)
      @code = code
      @path = path
      super(code.to_s)
    end
  end

  LIVE_STATUSES = %w[uploading sealed queued running].freeze
  TERMINAL_STATUSES = %w[succeeded failed expired].freeze
  MAX_BATCH_FILES = 16
  CONFIRMATION_KEY = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  belongs_to :account
  belongs_to :initiator, class_name: "User"
  has_many :staged_files, ->(import) { where(account_id: import.account_id).extending(StagedFile::ProtectedCollection) },
    class_name: "NoteImport::StagedFile", inverse_of: :note_import, before_remove: :prevent_staging_removal

  around_destroy :destroy_with_staging

  attr_readonly :account_id, :initiator_id, :confirmation_key, :root_name, :manifest, :ignored_counts

  enum :status, (LIVE_STATUSES + TERMINAL_STATUSES).index_with(&:itself)

  # Starts a private upload, or returns the existing receipt for identical confirmation metadata.
  # @param account [Account] Target account.
  # @param initiator [User] Authenticated member starting the upload.
  # @param confirmation_key [String] UUID reused only for retries of the same confirmation.
  # @param root_name [String] Selected root folder name.
  # @param files [Array<Hash>] Relative file paths and byte sizes as { path:, size: }.
  # @param ignored_counts [Hash] Browser-reported counts for obsidian and other files.
  # @return [NoteImport] Current receipt without reviving a terminal upload.
  # @raise [Invalid] If the metadata is invalid or conflicts, membership is missing, or another upload is live.
  def self.start!(account:, initiator:, confirmation_key:, root_name:, files:, ignored_counts:)
    plan = Manifest.new(root_name:, files:, ignored_counts:)
    unless confirmation_key.is_a?(String) && confirmation_key.ascii_only? && CONFIRMATION_KEY.match?(confirmation_key)
      raise Invalid.new(:invalid_confirmation_key)
    end

    account.with_lock(requires_new: true) do
      uncached do
        unless initiator.persisted? && account.account_users.exists?(user_id: initiator.id)
          raise Invalid.new(:membership_required)
        end

        imports = account.note_imports.where(initiator:)
        if (existing = imports.find_by(confirmation_key:))
          unless existing.root_name == plan.root_name && existing.manifest == plan.files && existing.ignored_counts == plan.ignored_counts
            raise Invalid.new(:confirmation_conflict)
          end
          existing
        else
          raise Invalid.new(:import_in_progress) if imports.exists?(status: LIVE_STATUSES)

          imports.create!(confirmation_key:, root_name: plan.root_name, manifest: plan.files,
            ignored_counts: plan.ignored_counts, activity_at: Time.current)
        end
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise Invalid.new(:unavailable), cause: nil
  end

  # Stages one batch without replacing any previously accepted content.
  # Call on a receipt scoped to the authenticated initiator and target account.
  # @param entries [Array<Hash>] Relative file paths and uploaded strings as { path:, bytes: }.
  # @return [NoteImport] Updated receipt.
  # @raise [Invalid] If membership was lost, the upload is closed, or any entry is invalid or conflicts.
  def stage!(entries)
    with_locked_upload do
      raise Invalid.new(:not_uploading) unless uploading?

      files = batch_files(entries)
      existing = staged_files.where(path: files.keys).pluck(:path, :digest).to_h
      existing.each do |path, digest|
        raise Invalid.new(:content_conflict, path:) unless digest == files.fetch(path)[:digest]
      end
      files.except(*existing.keys).each do |path, attributes|
        staged_files.create!(path:, **attributes)
      end
      update!(activity_at: Time.current)
    end
  end

  # Seals a complete upload or returns the current receipt if already sealed.
  # Call on a receipt scoped to the authenticated initiator and target account.
  # @return [NoteImport] Current receipt; scheduling is separate.
  # @raise [Invalid] If membership was lost, the upload expired, or any manifest entry is missing.
  def seal!
    with_locked_upload do
      raise Invalid.new(:expired) if expired?

      if uploading?
        raise Invalid.new(:incomplete_upload) unless staged_files.pluck(:path).to_set == manifest.keys.to_set

        now = Time.current
        update!(status: :sealed, sealed_at: now, activity_at: now)
      end
    end
  end

  # @api private
  # Removes staged bytes after the import reaches a terminal state, preserving its receipt.
  # @return [NoteImport] The terminal receipt.
  # @raise [Invalid] If the import is live or unavailable.
  def purge_staging!
    with_locked_import do
      raise Invalid.new(:import_in_progress) unless TERMINAL_STATUSES.include?(status)

      delete_staging_rows
    end
  end

  # @raise [ActiveRecord::ReadOnlyRecord] If a saved receipt would bypass staged-file cleanup.
  def delete
    raise ActiveRecord::ReadOnlyRecord, DESTROY_ONLY if persisted?

    super
  end

  # @api private
  # Runs a staging operation while membership and import state are stable.
  # @return [NoteImport] The locked, refreshed import.
  # @raise [Invalid] If the import is unavailable or its initiator is no longer a member.
  def with_locked_upload
    with_locked_import do |locked_account|
      unless locked_account.account_users.exists?(user_id: initiator_id)
        raise Invalid.new(:membership_required)
      end

      yield
    end
  end

  private
    def with_locked_import
      raise Invalid.new(:unavailable) unless persisted? && id == id_in_database

      # Match Notes revocation and account destruction: acquire the account lock first.
      Account.transaction(requires_new: true) do
        locked_account = Account.lock.find(account_id_in_database)
        self.class.uncached do
          with_lock do
            raise Invalid.new(:unavailable) unless account_id == locked_account.id

            yield locked_account
          end
        end
      end
      self
    rescue ActiveRecord::RecordNotFound
      raise Invalid.new(:unavailable), cause: nil
    end

    def prevent_staging_removal(_file)
      raise ActiveRecord::ReadOnlyRecord, StagedFile::RETENTION_ONLY
    end

    def destroy_with_staging
      return yield unless persisted?

      with_locked_import do
        delete_staging_rows
        yield
      end
    end

    def delete_staging_rows
      StagedFile.where(account_id:, note_import_id: id).delete_all
    end

    def batch_files(entries)
      unless entries.is_a?(Array) && entries.size.between?(1, MAX_BATCH_FILES)
        raise Invalid.new(:invalid_batch)
      end

      entries.each_with_object({}) do |entry, files|
        raise Invalid.new(:invalid_batch) unless entry.is_a?(Hash)

        path, attributes = StagedFile.prepare_entry(manifest:, path: entry.fetch(:path, nil), bytes: entry.fetch(:bytes, nil))

        if files.key?(path) && files.fetch(path)[:digest] != attributes[:digest]
          raise Invalid.new(:content_conflict, path:)
        end
        files[path] ||= attributes
      end
    end
end
