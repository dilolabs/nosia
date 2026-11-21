# An account's normalized inline hashtag; it may outlive its note links.
class NoteTag < ApplicationRecord
  # Keep even uncompressible UTF-8 keys within PostgreSQL's btree entry limit.
  MAX_KEY_BYTES = 2_048

  belongs_to :account
  has_many :note_taggings, dependent: :delete_all
  has_many :notes, through: :note_taggings

  validates :key, presence: true
  validate :indexable_key
  validate :stable_account, if: :persisted?

  private
    def indexable_key
      if key && key.bytesize > MAX_KEY_BYTES
        errors.add(:key, :too_long, count: MAX_KEY_BYTES)
      end
    end

    def stable_account
      errors.add(:account_id, :invalid) if will_save_change_to_account_id?
    end
end
