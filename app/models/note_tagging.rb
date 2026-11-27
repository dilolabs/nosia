# A link from a note to one inline hashtag in the same account.
class NoteTagging < ApplicationRecord
  belongs_to :note
  belongs_to :note_tag
  belongs_to :account, default: -> { note&.account }

  validate :same_account

  private
    def same_account
      unless Note.uncached { Note.exists?(id: note_id, account_id:) }
        errors.add(:note, :invalid)
      end
      unless NoteTag.uncached { NoteTag.exists?(id: note_tag_id, account_id:) }
        errors.add(:note_tag, :invalid)
      end
    end
end
