# Manages a branch through its root's direct Trash marker.
module NoteFolder::Trashable
  extend ActiveSupport::Concern

  included do
    has_one :trashing, class_name: "NoteFolderTrashing", inverse_of: :note_folder, dependent: :destroy
  end

  # Hides an active branch without marking its descendants. Repeated trash is a no-op.
  # @return [NoteFolder] The trashed folder.
  # @raise [ActiveRecord::RecordInvalid] If the folder is General or only trashed by an ancestor.
  # @raise [ActiveRecord::RecordNotFound] If the saved folder or account no longer exists.
  def trash
    with_locked_folder do
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
    with_locked_folder do
      restorable_trashing.destroy!
      association(:trashing).reset
    end
  end

  # Permanently deletes a directly trashed branch and all of its contents.
  # @param by [User] The acting account owner.
  # @return [NoteFolder] The destroyed root of the branch.
  # @raise [Note::PurgeForbidden] If the actor is not the account owner.
  # @raise [ActiveRecord::RecordInvalid] If the folder has no direct marker, is General, or has an inactive parent.
  # @raise [ActiveRecord::RecordNotFound] If the saved folder or account no longer exists.
  def purge(by:)
    with_locked_folder do |locked_account|
      unless by.is_a?(User) && by.persisted? && by.id_in_database == locked_account.owner_id
        raise Note::PurgeForbidden
      end

      restorable_trashing
      destroy_branch
    end
  end

  private
    def with_locked_folder
      self.class.transaction(requires_new: true) do
        reject_trash_change unless persisted?
        locked_account = Account.lock.find(account_id_in_database)
        self.class.uncached do
          reload
          reject_trash_change if general?
          yield locked_account
        end
      end
      self
    end

    def reject_trash_change
      errors.add(:base, :invalid)
      raise ActiveRecord::RecordInvalid, self
    end

    def restorable_trashing
      marker = trashing
      unless marker && (parent_id.nil? || self.class.active_in(account_id).exists?(id: parent_id))
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
end
