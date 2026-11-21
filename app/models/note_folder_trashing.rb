# A direct trash marker for one folder; its descendants need no markers.
class NoteFolderTrashing < ApplicationRecord
  belongs_to :note_folder, inverse_of: :trashing, touch: true
  belongs_to :account, default: -> { note_folder&.account }

  validate :account_matches_folder

  private
    def account_matches_folder
      if note_folder && account_id != note_folder.account_id
        errors.add(:account, :invalid)
      end
    end
end
