# Maintains an account's note-to-hashtag links.
module Note::Taggable
  extend ActiveSupport::Concern

  included do
    has_many :note_taggings, dependent: :delete_all
    has_many :note_tags, through: :note_taggings
  end

  # Called by the revisioned content write while the account lock is held.
  # @api private
  def self.sync(note, keys)
    tags = NoteTag.where(account_id: note.account_id)
    note.note_tag_ids = keys.map { |key| tags.find_or_create_by!(key:).id }
  end
end
