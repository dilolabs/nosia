# Saved, revisioned rich text that belongs to exactly one folder.
class Note < ApplicationRecord
  include Editable, Taggable, Trashable, Indexable

  # The submitted content or revision no longer matches the saved note.
  class EditConflict < StandardError; end

  # The note has been removed or is no longer active in its account.
  class Unavailable < StandardError; end

  # Only the account owner may permanently delete Notes content.
  class PurgeForbidden < StandardError; end

  belongs_to :account
  belongs_to :note_folder
  has_many :chunks, as: :chunkable, dependent: :destroy
  has_one :pin, class_name: "NotePin", inverse_of: :note, dependent: :destroy, autosave: false
  private :pin=, :build_pin, :create_pin, :create_pin!

  validate :stable_identity, if: :persisted?
  validate :folder_in_active_tree, if: -> { new_record? || will_save_change_to_note_folder_id? }

  before_update :clear_pin_on_folder_change, if: :will_save_change_to_note_folder_id?
  around_destroy :destroy_with_fresh_dependents, prepend: true

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

  # @param account_id [Integer] Account whose active published notes should be searched.
  # @return [ActiveRecord::Relation<Note>] Active notes with up-to-date embeddings.
  def self.indexed_in(account_id)
    active_in(account_id).embedding_ready.where("notes.indexed_generation = notes.embedding_generation")
  end

  # @return [String] The saved title, or the localized label for an untitled Note.
  def display_title
    title.presence || I18n.t("nosia.notes.untitled")
  end

  # Pins an active note in its current folder. Repeated pinning is a no-op.
  # @return [Note] The pinned note.
  # @raise [Note::Unavailable] If the note is missing or inactive.
  def pin_in_folder
    with_locked_note do
      ensure_active_note
      create_pin! unless pin
    end
  end

  # Unpins an active note. A note without a pin is unchanged.
  # @return [Note] The unpinned note.
  # @raise [Note::Unavailable] If the note is missing or inactive.
  def unpin
    with_locked_note do
      ensure_active_note
      pin&.destroy!
      association(:pin).reset
    end
  end

  # Moves an active note and clears its pin only if the folder changes.
  # @param folder [NoteFolder] A persisted, active folder in the same account.
  # @return [Note] The note, with its content revision and edit time unchanged.
  # @raise [Note::Unavailable] If the note is missing or inactive.
  # @raise [ActiveRecord::RecordNotFound] If the destination is missing, inactive, or foreign.
  def move_to(folder)
    with_locked_note do
      ensure_active_note
      destination_id = folder.id if folder.is_a?(NoteFolder) && folder.persisted?
      destination = NoteFolder.active_in(account_id).find(destination_id)
      update!(note_folder: destination) unless destination.id == note_folder_id
    end
  end

  private
    def with_locked_note(lock_record: false)
      self.class.transaction(requires_new: true) do
        raise Note::Unavailable unless persisted? && id == id_in_database

        locked_account = Account.lock.find_by(id: account_id_in_database)
        raise Note::Unavailable unless locked_account

        self.class.uncached do
          reload_for_lifecycle(locked_account.id, lock_record:)
          yield locked_account
        end
      end
      self
    end

    def reload_for_lifecycle(locked_account_id, lock_record:)
      reload(lock: lock_record)
      raise Note::Unavailable unless account_id == locked_account_id
    rescue ActiveRecord::RecordNotFound
      raise Note::Unavailable
    end

    def ensure_active_note
      raise Note::Unavailable unless self.class.active_in(account_id).exists?(id:)
    end

    def stable_identity
      errors.add(:id, :invalid) if will_save_change_to_id?
      errors.add(:account_id, :invalid) if will_save_change_to_account_id?
      errors.add(:draft_key, :invalid) if will_save_change_to_draft_key?
    end

    def folder_in_active_tree
      return if errors.any?

      owner_id = new_record? ? account_id : account_id_in_database
      # A normal save runs validation inside its transaction and holds this lock through the write.
      if Account.lock.exists?(id: owner_id)
        self.class.uncached do
          if persisted? && !self.class.active_in(owner_id).exists?(id:)
            errors.add(:base, :invalid)
          end
          if association(:note_folder).target&.new_record? || !NoteFolder.active_in(owner_id).exists?(id: note_folder_id)
            errors.add(:note_folder, :invalid)
          end
        end
      else
        errors.add(:account, :invalid)
      end
    end

    def clear_pin_on_folder_change
      # Validation normally holds the lock; also check writes that skip validation.
      stable_identity
      folder_in_active_tree
      raise ActiveRecord::RecordInvalid, self if errors.any?

      self.class.uncached do
        stored_folder_id = self.class.where(account_id: account_id_in_database, id:).pick(:note_folder_id)
        if stored_folder_id != note_folder_id
          NotePin.find_by(account_id: account_id_in_database, note_id: id)&.destroy!
          association(:pin).reset
        end
      end
    end

    def destroy_with_fresh_dependents
      return yield unless persisted?

      if id != id_in_database
        errors.add(:id, :invalid)
        raise ActiveRecord::RecordInvalid, self
      end

      owner_id = account_id_in_database
      Account.lock.find(owner_id)
      self.class.uncached do
        unless self.class.exists?(id:, account_id: owner_id)
          errors.add(:account, :invalid)
          raise ActiveRecord::RecordInvalid, self
        end

        association(:pin).reset
        association(:trashing).reset
        association(:chunks).reset
        if [ pin, trashing ].compact.any? { |state| state.account_id != owner_id }
          errors.add(:base, :invalid)
          raise ActiveRecord::RecordInvalid, self
        end

        @trashing_for_cleanup = trashing
        yield
      end
    ensure
      @trashing_for_cleanup = nil
    end

    def destroying_trashing?(marker)
      @trashing_for_cleanup.equal?(marker)
    end
end
