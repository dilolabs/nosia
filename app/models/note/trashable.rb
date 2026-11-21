# Manages a note's direct Trash marker without changing its folder or pin.
module Note::Trashable
  extend ActiveSupport::Concern

  included do
    has_one :trashing, class_name: "NoteTrashing", inverse_of: :note, dependent: :destroy
  end

  # Moves an active note to Trash. An existing direct marker makes this a no-op.
  # @return [Note] The trashed note.
  # @raise [Note::Unavailable] If the note is missing or only trashed by an ancestor.
  def trash
    with_locked_note do
      unless trashing
        ensure_active_note
        create_trashing!
      end
    end
  end

  # Restores a directly trashed note to its original folder, preserving its pin.
  # @return [Note] The restored note.
  # @raise [Note::Unavailable] If no direct marker exists or the original folder is inactive.
  def restore
    with_locked_note do
      marker = restorable_trashing
      marker.destroy!
      association(:trashing).reset
    end
  end

  # Permanently deletes a directly trashed note and its dependents, even under a trashed folder.
  # @param by [User] The acting account owner.
  # @return [Note] The destroyed note.
  # @raise [Note::PurgeForbidden] If the actor is not the account owner.
  # @raise [Note::Unavailable] If the note is missing or has no direct marker.
  def purge(by:)
    with_locked_note do |locked_account|
      unless by.is_a?(User) && by.persisted? && by.id_in_database == locked_account.owner_id
        raise Note::PurgeForbidden
      end

      raise Note::Unavailable unless trashing

      destroy!
    end
  end

  private
    def restorable_trashing
      marker = trashing
      unless marker && NoteFolder.active_in(account_id).exists?(id: note_folder_id)
        raise Note::Unavailable
      end

      marker
    end
end
