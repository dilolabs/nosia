# Application locking and owner checks around RubyLLM's encrypted Rails store.
class McpAuthorization::CredentialStore
  Unavailable = McpAuthorization::Unavailable
  NativeStore = RubyLLM::ActiveRecord::MCPCredential
  OWNED_KEY_PREFIX = "nosia-mcp-grant:".freeze

  # @param grants [Array<McpAuthorization>] Candidate grants for one account member
  # @return [Array<McpAuthorization>] Grants with a usable encrypted credential
  def self.chat_eligible(grants)
    return [] if grants.empty? || !NativeStore.table_exists?

    keys = grants.to_h { |grant| [ grant.id, "#{OWNED_KEY_PREFIX}#{grant.id}" ] }
    rows = NativeStore.where(key: keys.values, owner_type: McpAuthorization.polymorphic_name, owner_id: keys.keys).index_by(&:key)
    grants.select do |grant|
      new(grant).chat_credential_usable?(rows[keys.fetch(grant.id)])
    end
  end

  # @param grant [McpAuthorization] Exact native credential owner
  # @param retiring [Boolean] Allow only local credential removal
  # @param chat [Boolean] Enforce chat-specific admission for every operation
  def initialize(grant, retiring: false, chat: false)
    @grant = grant
    @retiring = retiring
    @chat = chat
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
    @grant.admit!(chat: @chat) unless @retiring
  end

  # @param require_credential [Boolean] An authorized workspace operation
  # @raise [Unavailable] This request no longer has an admissible grant or credential
  def admit_request!(require_credential:)
    raise Unavailable if @retiring

    admit_client!
    if @chat
      raise Unavailable unless chat_credential_usable?(owned_credential)
    elsif require_credential
      raise Unavailable if owned_data.to_h["access_token"].blank?
    end
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

      admit_client!
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

  # @param row [RubyLLM::ActiveRecord::MCPCredential, nil] Scoped encrypted row
  # @return [Boolean] Whether the token is usable now or can be refreshed by the SDK
  def chat_credential_usable?(row)
    return false unless row&.owner_id == @grant.id && row.encrypted_attribute?(:data)

    data = row.data
    return false unless data.is_a?(Hash) && data["access_token"].is_a?(String) && data["access_token"].present?

    expiry = data["expires_at"]
    refresh = data["refresh_token"]
    expiry.nil? || (expiry.is_a?(Numeric) && (expiry > Time.now.to_i || (refresh.is_a?(String) && refresh.present?)))
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  private
    # SDK keys carry the raw endpoint; the database key must not duplicate it.
    def owned_key = "#{OWNED_KEY_PREFIX}#{@grant.id}"

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
        admit_client!
        yield
      else
        @grant.class.transaction do
          raise Unavailable unless @grant.lock_identity

          admit_client!
          yield
        end
      end
    end
end
