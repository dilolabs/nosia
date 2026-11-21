# Manages a branch through its root's direct Trash marker.
module NoteFolder::Trashable
  extend ActiveSupport::Concern

  included do
    has_one :trashing, class_name: "NoteFolderTrashing", inverse_of: :note_folder, dependent: :destroy, autosave: false
    private :build_trashing, :create_trashing, :create_trashing!, :trashing=

    around_destroy :destroy_with_fresh_trashing, prepend: true
  end

  # Hides an active branch without marking its descendants. Repeated trash is a no-op.
  # @return [NoteFolder] The trashed folder.
  # @raise [ActiveRecord::RecordInvalid] If the folder is General or only trashed by an ancestor.
  # @raise [ActiveRecord::RecordNotFound] If the saved folder or account no longer exists.
  def trash
    with_locked_trashable_folder do
      unless trashing
        reject_trash_change unless self.class.active_in(account_id).exists?(id:)
        create_trashing!
      end
    end
  end

  # Restores this folder at its original location, leaving separately trashed items hidden.
  # @return [NoteFolder] The restored folder.
  # @raise [ActiveRecord::RecordInvalid] If the folder has no direct marker, is General, or has an inactive parent.
  # @raise [ActiveRecord::RecordNotFound] If the saved folder or account no longer exists.
  def restore
    with_locked_trashable_folder do
      restorable_trashing.destroy!
      association(:trashing).reset
      resume_indexing_later
    end
  end

  # Visits active pending or failed notes in this branch without embedding inline.
  # @return [void]
  def resume_indexing_now
    branch = self.class.branch_in(account_id, root_id: id).select(:id)
    Note.active_in(account_id).where(note_folder_id: branch, embedding_status: %w[pending failed]).find_each(&:resume_indexing)
  end

  # Permanently deletes a directly trashed branch and its contents, even under a trashed ancestor.
  # @param by [User] The acting account owner.
  # @return [NoteFolder] The destroyed root of the branch.
  # @raise [Note::PurgeForbidden] If the actor is not the account owner.
  # @raise [ActiveRecord::RecordInvalid] If the folder has no direct marker or is General.
  # @raise [ActiveRecord::RecordNotFound] If the saved folder or account no longer exists.
  def purge(by:)
    with_locked_trashable_folder do |locked_account|
      unless by.is_a?(User) && by.persisted? && by.id_in_database == locked_account.owner_id
        raise Note::PurgeForbidden
      end

      reject_trash_change unless trashing
      destroy_branch
    end
  end

  private
    def resume_indexing_later
      folder_id = id
      ActiveRecord.after_all_transactions_commit do
        NoteFolder::ResumeIndexingJob.perform_later(folder_id)
      end
    end

    def with_locked_trashable_folder
      with_locked_folder do |locked_account|
        reject_trash_change if general?
        yield locked_account
      end
    end

    def reject_trash_change
      errors.add(:base, :invalid)
      raise ActiveRecord::RecordInvalid, self
    end

    def restorable_trashing
      marker = trashing
      unless marker&.account_id == account_id && (parent_id.nil? || self.class.active_in(account_id).exists?(id: parent_id))
        reject_trash_change
      end

      marker
    end

    def destroy_branch
      branch = self.class.branch_in(account_id, root_id: id).to_a
      children_by_parent = branch.group_by(&:parent_id)
      # Build breadth-first in memory so reversing it destroys the deepest folders first.
      breadth_first = [ self ]
      breadth_first.each { |folder| breadth_first.concat(children_by_parent.fetch(folder.id, [])) }

      Note.where(account_id:, note_folder_id: branch.map(&:id)).find_each(&:destroy!)
      breadth_first.reverse_each(&:destroy!)
    end

    def destroy_with_fresh_trashing
      return yield unless persisted?

      reject_trash_change unless id == id_in_database
      owner_id = account_id_in_database
      Account.lock.find(owner_id)
      self.class.uncached do
        reject_trash_change unless self.class.exists?(id:, account_id: owner_id)

        association(:trashing).reset
        marker = trashing
        reject_trash_change if marker && marker.account_id != owner_id

        @trashing_for_cleanup = marker
        yield
      end
    ensure
      @trashing_for_cleanup = nil
    end

    def destroying_trashing?(marker)
      @trashing_for_cleanup.equal?(marker)
    end
end
