# Application locking and owner checks around RubyLLM's encrypted Rails store.
class McpAuthorization::CredentialStore
  Unavailable = McpAuthorization::Unavailable
  NativeStore = RubyLLM::ActiveRecord::MCPCredential

  def initialize(grant, retiring: false)
    @grant = grant
    @retiring = retiring
  end

  def verify_schema!
    raise Unavailable unless NativeStore.table_exists?

    unless @retiring
      ActiveRecord::Encryption.config.primary_key
      ActiveRecord::Encryption.config.key_derivation_salt
    end
  end

  def native_key(url)
    @native_key = "#{@grant.to_gid}@#{url}"
  end

  def admit_client!
    @grant.admit! unless @retiring
  end

  def admit_request!
    raise Unavailable if @retiring

    @grant.admit!
  end

  def read(key)
    raise Unavailable if @retiring

    if key == @native_key
      owned_data
    else
      read_row(registration_key(key), owner: nil)
    end
  end

  def write(key, data, owner:)
    raise Unavailable if @retiring

    if key == @native_key
      raise Unavailable unless @locked_grant && owner == @grant

      @grant.admit!
      require_unused_grant! if data.key?("pending")
      checked_row(owned_key, owner: @grant)
      NativeStore.write(owned_key, data, owner: @locked_grant)
    elsif owner.nil?
      with_current_grant do
        stored_key = registration_key(key)
        checked_row(stored_key, owner: nil)
        NativeStore.write(stored_key, data, owner: nil)
      end
    else
      raise Unavailable
    end
  end

  def delete(key)
    if @retiring && @locked_grant && key == @native_key
      checked_row(owned_key, owner: @grant)
      NativeStore.delete(owned_key)
    elsif !@retiring && key != @native_key
      with_current_grant do
        stored_key = registration_key(key)
        checked_row(stored_key, owner: nil)
        NativeStore.delete(stored_key)
      end
    else
      raise Unavailable
    end
  end

  def owned_data
    owned_credential&.data
  end

  def owned_credential
    raise Unavailable if @retiring

    encrypted_row(owned_key, owner: @grant)
  end

  def require_unused_grant!
    data = owned_data.to_h
    raise Unavailable if data["access_token"].present? || data["refresh_token"].present?
  end

  def synchronize(key)
    raise Unavailable unless key == @native_key

    @grant.class.transaction(requires_new: true) do
      @locked_grant = @grant.lock_identity
      next if @retiring && !@locked_grant
      raise Unavailable unless @locked_grant && @locked_grant.endpoint == @grant.endpoint

      admit_client!
      NativeStore.synchronize(owned_key) do
        result = Timeout.timeout(15, McpOutbound::Blocked) { yield }
        @locked_grant.delete if @retiring
        result
      end
    ensure
      @locked_grant = nil
    end
  end

  private
    # The SDK's key includes the raw server address. Do not duplicate it in
    # plaintext alongside the encrypted endpoint.
    def owned_key = "nosia-mcp-grant:#{@grant.id}"

    def registration_key(key)
      raise Unavailable unless key.start_with?("client:")

      "nosia-mcp-registration:#{Digest::SHA256.hexdigest(key)}"
    end

    def checked_row(key, owner:)
      row = NativeStore.uncached { NativeStore.find_by(key:) }
      if row && (row.owner_id != owner&.id || row.owner_type != owner&.class&.polymorphic_name)
        raise Unavailable
      end
      row
    end

    def read_row(key, owner:)
      encrypted_row(key, owner:)&.data
    end

    def encrypted_row(key, owner:)
      if (row = checked_row(key, owner:))
        raise Unavailable unless row.encrypted_attribute?(:data)

        row
      end
    end

    def with_current_grant
      if @locked_grant
        @grant.admit!
        yield
      else
        @grant.class.transaction do
          raise Unavailable unless @grant.lock_identity

          @grant.admit!
          yield
        end
      end
    end
end
