# A direct trash marker, separate from inherited folder visibility.
class NoteTrashing < ApplicationRecord
  belongs_to :note, inverse_of: :trashing
  belongs_to :account, default: -> { note&.account }

  validate :account_matches_note, if: :new_record?
  validate :stable_identity, if: :persisted?
  before_create :lock_and_check_note
  before_update :check_stable_identity
  before_destroy :lock_and_check_removal, if: :persisted?, prepend: true

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

    def lock_and_check_removal
      owner_id = account_id_in_database
      Account.lock.find(owner_id)

      self.class.uncached do
        marker = self.class.find_by(id: id_in_database, account_id: owner_id, note_id: note_id_in_database)
        unless marker && (dependent_cleanup? || parent_active?(marker))
          errors.add(:note, :invalid)
          raise ActiveRecord::RecordInvalid, self
        end
      end
    end

    def dependent_cleanup?
      # Rails also sets this reflection when replacing an association.
      destroyed_by_association == Note.reflect_on_association(:trashing) &&
        association(:note).target&.send(:destroying_trashing?, self)
    end

    def parent_active?(marker)
      Note.where(id: marker.note_id, account_id: marker.account_id,
        note_folder_id: NoteFolder.active_in(marker.account_id).select(:id)).exists?
    end
end
