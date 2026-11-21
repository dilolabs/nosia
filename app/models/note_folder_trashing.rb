# A direct trash marker for one folder; its descendants need no markers.
class NoteFolderTrashing < ApplicationRecord
  belongs_to :note_folder, inverse_of: :trashing, touch: true
  belongs_to :account, default: -> { note_folder&.account }

  validate :account_matches_folder
  validate :stable_identity, if: :persisted?
  before_create :lock_folder_account
  before_destroy :lock_folder_account, if: :persisted?, prepend: true

  private
    def account_matches_folder
      if note_folder && account_id != note_folder.account_id
        errors.add(:account, :invalid)
      end
    end

    def stable_identity
      errors.add(:note_folder_id, :invalid) if will_save_change_to_note_folder_id?
      errors.add(:account_id, :invalid) if will_save_change_to_account_id?
    end

    def lock_folder_account
      # Lock the account before writing the marker or touching the folder.
      Account.lock.find(new_record? ? account_id : account_id_in_database)
    end
end
