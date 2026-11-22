# An immutable, encrypted Markdown payload owned by one account's import.
class NoteImport::StagedFile < ApplicationRecord
  belongs_to :note_import, inverse_of: :staged_files
  belongs_to :account, default: -> { note_import&.account }

  encrypts :payload, support_unencrypted_data: false
  self.filter_attributes += [ :payload ]
  attr_readonly :account_id, :note_import_id, :path, :payload, :digest

  validate :account_matches_import

  # @param options [Hash, nil] Active Record attribute selection options.
  # @return [Hash] The staged file's metadata, never its payload.
  def serializable_hash(options = nil)
    # Generated methods such as payload_in_database can also return plaintext.
    super(options&.except(:methods, :include))
  end

  private
    def attribute_names_for_serialization
      super - [ "payload" ]
    end

    def account_matches_import
      if note_import && account_id != note_import.account_id
        errors.add(:account, :invalid)
      end
    end
end
