# Gives a note priority within its current folder, without changing content recency.
class NotePin < ApplicationRecord
  belongs_to :note, inverse_of: :pin, autosave: false
  belongs_to :account, default: -> { note&.account }, autosave: false

  validate :active_note, if: :new_record?
  validate :stable_identity, if: :persisted?
  before_create :lock_and_check_note
  before_update :check_stable_identity
  before_destroy :lock_and_check_removal, if: :persisted?, prepend: true

  private
    def active_note
      unless Note.uncached { Note.active_in(account_id).exists?(id: note_id) }
        errors.add(:note, :invalid)
      end
    end

    def stable_identity
      errors.add(:note_id, :invalid) if will_save_change_to_note_id?
      errors.add(:account_id, :invalid) if will_save_change_to_account_id?
    end

    def lock_and_check_note
      if Account.lock.exists?(id: account_id)
        active_note
      else
        errors.add(:account, :invalid)
      end
      raise ActiveRecord::RecordInvalid, self if errors.any?
    end

    def check_stable_identity
      stable_identity
      raise ActiveRecord::RecordInvalid, self if errors.any?
    end

    def lock_and_check_removal
      owner_id = account_id_in_database
      Account.lock.find(owner_id)
      # Destroying the note must clean up even a pin preserved in Trash.
      unless destroyed_by_association == Note.reflect_on_association(:pin) ||
          Note.uncached { Note.active_in(owner_id).exists?(id: note_id_in_database) }
        errors.add(:note, :invalid)
        raise ActiveRecord::RecordInvalid, self
      end
    end
end
