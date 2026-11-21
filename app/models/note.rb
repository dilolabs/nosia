# Saved, revisioned rich text that belongs to exactly one folder.
class Note < ApplicationRecord
  include Editable, Taggable

  # The submitted content or revision no longer matches the saved note.
  class EditConflict < StandardError; end

  # The note has been removed or is no longer active in its account.
  class Unavailable < StandardError; end

  belongs_to :account
  belongs_to :note_folder
  has_one :trashing, class_name: "NoteTrashing", inverse_of: :note, dependent: :destroy

  validate :folder_matches_account, if: -> { new_record? || will_save_change_to_note_folder_id? }
  validate :stable_identity, if: :persisted?

  # Matches a case-insensitive, literal substring of the saved title or plain text.
  # @param input [String] Search text.
  # @return [ActiveRecord::Relation<Note>] Matching notes within the calling scope.
  scope :search_literal, ->(input) do
    pattern = "%#{sanitize_sql_like(input.to_s.strip)}%"
    where("notes.title ILIKE :query OR notes.body_text ILIKE :query", query: pattern)
  end

  # @param account_id [Integer] Account whose active tree should be consulted.
  # @return [ActiveRecord::Relation<Note>] Notes visible in that account.
  def self.active_in(account_id)
    where(account_id:, note_folder_id: NoteFolder.active_in(account_id).select(:id)).where.missing(:trashing)
  end

  private
    def folder_matches_account
      unless NoteFolder.uncached { NoteFolder.exists?(id: note_folder_id, account_id:) }
        errors.add(:note_folder, :invalid)
      end
    end

    def stable_identity
      errors.add(:account_id, :invalid) if will_save_change_to_account_id?
      errors.add(:draft_key, :invalid) if will_save_change_to_draft_key?
    end
end
