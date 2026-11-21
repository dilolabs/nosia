# A direct trash marker for one folder; its descendants need no markers.
class NoteFolderTrashing < ApplicationRecord
  belongs_to :note_folder, inverse_of: :trashing
  belongs_to :account, default: -> { note_folder&.account }

  validate :folder_can_be_marked, if: :new_record?
  validate :stable_identity, if: :persisted?
  before_create :lock_and_check_folder
  before_update :check_stable_identity
  before_destroy :lock_and_check_removal, if: :persisted?, prepend: true

  private
    def folder_can_be_marked
      folder = NoteFolder.uncached { NoteFolder.find_by(id: note_folder_id) }
      if !folder || folder.general?
        errors.add(:note_folder, :invalid)
      elsif account_id != folder.account_id
        errors.add(:account, :invalid)
      end
    end

    def lock_and_check_folder
      Account.lock.find(account_id)
      # Do not trust either a loaded association or an earlier validation.
      folder_can_be_marked
      raise ActiveRecord::RecordInvalid, self if errors.any?
    end

    def stable_identity
      errors.add(:note_folder_id, :invalid) if will_save_change_to_note_folder_id?
      errors.add(:account_id, :invalid) if will_save_change_to_account_id?
    end

    def check_stable_identity
      stable_identity
      raise ActiveRecord::RecordInvalid, self if errors.any?
    end

    def lock_and_check_removal
      owner_id = account_id_in_database
      Account.lock.find(owner_id)

      self.class.uncached do
        marker = self.class.find_by(id: id_in_database, account_id: owner_id, note_folder_id: note_folder_id_in_database)
        unless marker && (dependent_cleanup? || parent_active?(marker))
          errors.add(:note_folder, :invalid)
          raise ActiveRecord::RecordInvalid, self
        end
      end
    end

    def dependent_cleanup?
      # Rails also sets this reflection when replacing an association.
      destroyed_by_association == NoteFolder.reflect_on_association(:trashing) &&
        association(:note_folder).target&.send(:destroying_trashing?, self)
    end

    def parent_active?(marker)
      folder = NoteFolder.find_by(id: marker.note_folder_id, account_id: marker.account_id)
      folder && (folder.parent_id.nil? || NoteFolder.active_in(marker.account_id).exists?(id: folder.parent_id))
    end
end
