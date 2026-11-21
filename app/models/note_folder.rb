# An account-owned folder in the Notes workspace.
class NoteFolder < ApplicationRecord
  include Tree, Trashable

  GENERAL_SYSTEM_KEY = "general".freeze

  belongs_to :account
  belongs_to :parent, class_name: "NoteFolder", optional: true, inverse_of: :children
  has_many :children, class_name: "NoteFolder", foreign_key: :parent_id, inverse_of: :parent

  validates :name, presence: true
  validate :stable_identity, on: :update
  validate :location_in_active_tree

  # Moves an active folder within its account, or back to the root.
  # @param parent [NoteFolder, nil] Destination folder, or nil for the root.
  # @return [NoteFolder] The updated folder.
  # @raise [ActiveRecord::RecordInvalid] If the move is not allowed.
  def change_location!(parent:)
    with_locked_folder do
      if general?
        errors.add(:parent, :invalid)
        raise ActiveRecord::RecordInvalid, self
      end

      update!(parent:)
    end
  end

  # @return [Boolean] Whether this is the account's permanent General folder.
  def general?
    system_key == GENERAL_SYSTEM_KEY
  end

  private
    def with_locked_folder
      self.class.transaction(requires_new: true) do
        reject_trash_change unless persisted? && id == id_in_database

        locked_account = Account.lock.find(account_id_in_database)
        self.class.uncached do
          reload
          reject_trash_change unless account_id == locked_account.id

          yield locked_account
        end
      end
      self
    end

    def stable_identity
      errors.add(:id, :invalid) if will_save_change_to_id?
      errors.add(:account_id, :invalid) if will_save_change_to_account_id?
      errors.add(:system_key, :invalid) if will_save_change_to_system_key?
      errors.add(:name, :invalid) if general? && will_save_change_to_name?
    end

    def location_in_active_tree
      return if errors.any?

      # A normal save runs validation inside its transaction, so this lock lasts through the write.
      if Account.lock.exists?(id: account_id)
        # Earlier validations or reads may have cached the tree before the lock.
        self.class.uncached do
          active_folders = self.class.active_in(account_id)
          errors.add(:base, :invalid) if persisted? && !active_folders.exists?(id:)
          errors.add(:parent, :invalid) if invalid_parent?(active_folders)
        end
      else
        errors.add(:account, :invalid)
      end
    end

    def invalid_parent?(active_folders)
      return true if association(:parent).target&.new_record?
      return false if parent_id.nil?

      general? || !active_folders.exists?(id: parent_id) ||
        (persisted? && will_save_change_to_parent_id? && self.class.branch_in(account_id, root_id: id).exists?(id: parent_id))
    end
end
