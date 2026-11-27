class Document::Upload
  MAX_BYTES = 25.megabytes
  EXPIRES_IN = 1.hour

  def self.create(account:, user:, attributes:)
    ActiveStorage::Blob.create_before_direct_upload!(**attributes,
      metadata: { "nosia_upload_account_id" => account.id, "nosia_upload_user_id" => user.id })
  end

  def self.account_for(blob, user:)
    if blob.created_at >= EXPIRES_IN.ago && blob.metadata["nosia_upload_user_id"] == user.id
      user.accounts.find_by(id: blob.metadata["nosia_upload_account_id"])
    end
  end

  def self.authorize(blob, account:, user:)
    unless blob.is_a?(ActiveStorage::Blob) && account_for(blob, user:) == account
      raise ActiveRecord::RecordNotFound, "invalid attachable sgid"
    end

    blob
  end

  def self.resolve(file, account:, user:)
    if file.is_a?(String) && file.present?
      authorize(ActiveStorage::Blob.find_signed(file), account:, user:)
    else
      file
    end
  end
end
