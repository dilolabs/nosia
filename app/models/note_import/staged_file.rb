# An immutable, encrypted Markdown payload owned by one account's import.
class NoteImport::StagedFile < ApplicationRecord
  RETENTION_ONLY = "Staged files can only be removed by import cleanup".freeze

  # Protects both the collection proxy and chained relations from bulk removal.
  module RetentionProtected
    def delete_all(*)
      raise ActiveRecord::ReadOnlyRecord, RETENTION_ONLY
    end
  end

  belongs_to :note_import, inverse_of: :staged_files
  belongs_to :account, default: -> { note_import&.account }

  encrypts :payload, support_unencrypted_data: false
  self.filter_attributes += [ :payload ]
  attr_readonly :account_id, :note_import_id, :path, :payload, :digest

  validate :account_matches_import
  before_create :verify_staged_entry

  # @api private
  # @param manifest [Hash{String => Integer}] Canonical paths and expected byte sizes.
  # @param path [String] Logical file path.
  # @param bytes [String] Uploaded bytes, without transcoding.
  # @return [Array] The normalized path and validated payload/digest attributes.
  # @raise [NoteImport::Invalid] If the path is outside the manifest or the bytes are invalid.
  def self.prepare_entry(manifest:, path:, bytes:)
    path = NoteImport::Manifest.normalize_path(path)
    expected_size = manifest.fetch(path) { raise NoteImport::Invalid.new(:unexpected_path, path:) }
    raise NoteImport::Invalid.new(:invalid_payload, path:) unless bytes.is_a?(String)
    raise NoteImport::Invalid.new(:size_mismatch, path:) unless bytes.bytesize == expected_size

    payload = bytes.b.force_encoding(Encoding::UTF_8)
    unless payload.valid_encoding? && !payload.include?("\0")
      raise NoteImport::Invalid.new(:invalid_payload, path:)
    end
    [ path, { payload:, digest: Digest::SHA256.hexdigest(payload) } ]
  end

  # @return [Boolean] Persisted staging is immutable; retention cleanup uses bulk deletion.
  def readonly?
    persisted? || super
  end

  # @raise [ActiveRecord::ReadOnlyRecord] If a staged file is already persisted.
  def delete
    raise ActiveRecord::ReadOnlyRecord, RETENTION_ONLY if persisted?

    super
  end

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

    def verify_staged_entry
      # Don't trust an association target that may have been loaded before sealing.
      import = NoteImport.find_by(id: note_import_id, account_id:)
      raise NoteImport::Invalid.new(:unavailable) unless import

      # A normal save holds these locks through the insert, even if validation was skipped.
      import.with_locked_upload do
        raise NoteImport::Invalid.new(:not_uploading) unless import.uploading?

        canonical_path, attributes = self.class.prepare_entry(manifest: import.manifest,
          path: path_before_type_cast, bytes: payload_before_type_cast)
        raise NoteImport::Invalid.new(:invalid_path) unless canonical_path == path
        raise NoteImport::Invalid.new(:invalid_digest) unless attributes[:digest] == digest

        self.payload = attributes[:payload]
      end
    rescue NoteImport::Invalid => error
      errors.add(:base, error.code)
      throw :abort
    end
end
