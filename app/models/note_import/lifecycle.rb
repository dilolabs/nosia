# Schedules, leases and reconciles a private Notes import without keeping queue calls under locks.
module NoteImport::Lifecycle
  extend ActiveSupport::Concern

  CLAIM_DURATION = 15.minutes
  START_DEADLINE = 24.hours
  BATCH_SIZE = 100
  CLAIMABLE_STATUSES = %w[sealed queued].freeze

  class_methods do
    # Schedules fresh seals, retires expired work, and retries terminal staging cleanup.
    # @return [void]
    def reconcile_now
      without_import_sql_logging do
        now = Time.current
        cutoff = now - START_DEADLINE
        expired = where(status: :uploading, activity_at: ..cutoff)
          .or(where(status: CLAIMABLE_STATUSES, sealed_at: ..cutoff))
          .or(where(status: :running, claim_expires_at: ..now))
        sealed = where(status: :sealed, enqueued_at: nil, sealed_at: cutoff..)
        terminal_with_staging = where(status: NoteImport::TERMINAL_STATUSES, id: NoteImport::StagedFile.select(:note_import_id))

        # Each operation reloads under its lock; don't load manifests in the batch.
        expired.select(:id).find_each(batch_size: BATCH_SIZE, &:fail_expired)
        sealed.select(:id).find_each(batch_size: BATCH_SIZE, &:enqueue_publication)
        terminal_with_staging.select(:id, :account_id).find_each(batch_size: BATCH_SIZE, &:purge_terminal_staging)
      end
    end

    # @api private
    # @return [Object] The operation's result with private SQL bind logging suppressed.
    def without_import_sql_logging(&operation)
      logger = ActiveRecord::Base.logger
      logger ? logger.silence(Logger::INFO, &operation) : operation.call
    end
  end

  # Schedules publication after the seal commits; a refused enqueue leaves a recoverable seal.
  # @return [void]
  def enqueue_publication
    ActiveRecord.after_all_transactions_commit do
      if with_worker_lock { sealed? && !enqueued_at? && before_start_deadline?(Time.current) }
        if enqueue_publish_job
          with_worker_lock { update!(status: :queued, enqueued_at: Time.current) if sealed? }
        else
          Rails.logger.warn("Could not enqueue Notes import")
        end
      end
    rescue ActiveRecord::ActiveRecordError, NoteImport::Invalid
      Rails.logger.warn("Could not record Notes import enqueue")
    end
  end

  # @api private
  # Starts one attempt for a sealed or queued import.
  # @return [String, nil] The worker's token, or nil if another worker has already claimed it or it is no longer eligible.
  def claim
    with_worker_lock do
      now = Time.current
      if CLAIMABLE_STATUSES.include?(status) && before_start_deadline?(now)
        token = SecureRandom.uuid
        update!(status: :running, claim_token: token, claim_expires_at: now + CLAIM_DURATION)
        token
      end
    end
  end

  # @api private
  # @param token [String] The worker's claim.
  # @return [Boolean] Whether the unexpired claim was extended.
  def renew_claim(token)
    with_worker_lock do
      now = Time.current
      live_claim?(token, now:) && update!(claim_expires_at: now + CLAIM_DURATION)
    end
  end

  # @api private
  # Decrypts only the requested manifest entry, with the import row locked.
  # @param token [String] The worker's claim.
  # @param path [String] Canonical manifest path to open.
  # @return [String] Staged Markdown; conversion is done after releasing the row lock.
  # @raise [NoteImport::Invalid] If the claim is stale or staging is unavailable.
  def read_staged_payload(token, path)
    with_worker_lock do
      require_live_claim(token)
      file = staged_files.find_by(path:) if manifest.key?(path)
      raise NoteImport::Invalid.new(:staging_unavailable) unless file

      file.payload
    end
  end

  # @api private
  # Rechecks timeouts under the import lock before retiring an upload or revoking a claim.
  # @return [void]
  def fail_expired
    with_worker_lock do
      now = Time.current
      if uploading? && activity_at <= now - START_DEADLINE
        update!(status: :expired)
      elsif CLAIMABLE_STATUSES.include?(status) && !before_start_deadline?(now)
        record_failure(:processing_timeout)
      elsif running? && claim_expires_at && claim_expires_at <= now
        record_failure(:worker_claim_expired)
      end
    end
  rescue ActiveRecord::ActiveRecordError, NoteImport::Invalid
    Rails.logger.warn("Could not expire Notes import")
  end

  # @api private
  # Attempts terminal-only staging cleanup without altering the receipt on failure.
  # @return [void]
  def purge_terminal_staging
    purge_staging!
  rescue ActiveRecord::ActiveRecordError, NoteImport::Invalid
    Rails.logger.warn("Could not purge Notes import staging")
  end

  private
    def with_worker_lock(&operation)
      raise NoteImport::Invalid.new(:unavailable) unless persisted? && id == id_in_database

      self.class.uncached { with_lock(requires_new: true, &operation) }
    rescue ActiveRecord::RecordNotFound
      raise NoteImport::Invalid.new(:unavailable), cause: nil
    end

    def before_start_deadline?(now)
      sealed_at && sealed_at > now - START_DEADLINE
    end

    def enqueue_publish_job
      NoteImport::PublishJob.logger.silence(Logger::UNKNOWN) do
        NoteImport::PublishJob.perform_later(id)
      end
    rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
      false
    end

    def require_live_claim(token)
      raise NoteImport::Invalid.new(:stale_claim) unless live_claim?(token, now: Time.current)
    end

    def live_claim?(token, now:)
      running? && token.present? && claim_token == token && claim_expires_at.present? && claim_expires_at > now
    end

    def record_failure(code)
      update!(status: :failed, report: { error: code.to_s }, claim_token: nil, claim_expires_at: nil)
    end

    def fail_processing(token, code)
      with_worker_lock do
        if live_claim?(token, now: Time.current)
          record_failure(code)
          true
        end
      end
    end

    def schedule_staging_cleanup
      ActiveRecord.after_all_transactions_commit { purge_terminal_staging }
    end
end
