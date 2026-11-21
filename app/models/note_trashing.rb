# A direct trash marker, separate from inherited folder visibility.
class NoteTrashing < ApplicationRecord
  belongs_to :note, inverse_of: :trashing
  belongs_to :account, default: -> { note&.account }

  validate :account_matches_note, if: :new_record?
  validate :stable_identity, if: :persisted?
  before_create :lock_and_check_note
  before_update :check_stable_identity
  before_destroy :lock_original_account, if: :persisted?, prepend: true

  private
    def account_matches_note
      unless Note.uncached { Note.exists?(id: note_id, account_id:) }
        errors.add(:note, :invalid)
      end
    end

    def stable_identity
      errors.add(:note_id, :invalid) if will_save_change_to_note_id?
      errors.add(:account_id, :invalid) if will_save_change_to_account_id?
    end

    def lock_and_check_note
      if Account.lock.exists?(id: account_id)
        account_matches_note
      else
        errors.add(:account, :invalid)
      end
      raise ActiveRecord::RecordInvalid, self if errors.any?
    end

    def check_stable_identity
      stable_identity
      raise ActiveRecord::RecordInvalid, self if errors.any?
    end

    def lock_original_account
      # A rejected reassignment can leave a dirty target and account in memory.
      Account.lock.find(account_id_in_database)
    end
end
