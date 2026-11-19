# The SDK owns the protocol. This scope inspects only OAuth destinations and
# the outcome of HTTP attempts attributable to this exact stored credential.
class McpServer::Client::OauthScope < McpServer::Client::RequestScope
  URL_FIELDS = %w[resource issuer authorization_endpoint token_endpoint registration_endpoint].freeze
  Attempt = Data.define(:kind, :fingerprint, :scheme) do
    def initialize(kind:, fingerprint: nil, scheme: nil)
      super(kind:, fingerprint:, scheme:)
    end
  end

  def initialize(grant, store)
    super(https_only: true)
    @grant = grant
    @store = store
    @fingerprint_key = SecureRandom.random_bytes(32)
  end

  def during_operation(operation)
    @operation = operation
    yield
  ensure
    rejected = @rejected_credential
    @operation = @rejected_credential = @refresh_started = @nonce_retry = @deny_refresh = nil
    if rejected && !$!.is_a?(RubyLLM::CancelledError)
      if @grant.mark_reconnect_required(rejected, &method(:fingerprint))
        raise McpAuthorization::ReconnectRequired, cause: nil
      else
        raise McpAuthorization::Unavailable, cause: nil
      end
    end
  end

  def admit!(_env)
    raise McpOutbound::Blocked if @rejected_credential
    if @operation == :use && @store.owned_data.to_h["access_token"].blank?
      raise McpAuthorization::Unavailable
    end
    @store.admit_request!
  end

  def capture(env)
    if env.request_headers["Content-Type"] == "application/x-www-form-urlencoded" && env.method == :post
      capture_grant_exchange(env)
    elsif env.request_headers["Accept"] == "application/json" && env.method == :get && @operation == :consent
      Attempt.new(kind: :metadata)
    elsif same_destination?(env, @grant.endpoint)
      # RubyLLM's direct-call API can otherwise poll an unsolicited task
      # even though this client didn't negotiate the extension.
      raise McpOutbound::Blocked if env.request_headers["Mcp-Method"].to_s.start_with?("tasks/")

      super
      capture_mcp(env)
    end
  end

  def observe(attempt, response)
    if attempt
      case attempt.kind
      when :metadata
        # Faraday's raise_error still hands 3xx bodies to the SDK.
        raise McpOutbound::Blocked unless (200...300).cover?(response.status) || (400...600).cover?(response.status)

        validate_metadata(response.body) if (200...300).cover?(response.status)
      when :mcp, :expired_access
        observe_mcp(attempt, response)
      when :refresh
        observe_refresh(attempt, response)
      end
    end
  end

  private
    def capture_grant_exchange(env)
      form = URI.decode_www_form(env.body).to_h
      return unless form["grant_type"] == "refresh_token"

      # Native may attempt a recovery after a failed proactive refresh, or
      # fall back to the older handshake. Don't repeat a failed exchange.
      raise McpOutbound::Blocked if @refresh_started || @deny_refresh

      record = @store.owned_credential
      data = record&.data.to_h
      endpoint = data.dig("server", "token_endpoint")
      unless endpoint && same_destination?(env, endpoint) && exact_token?(form["refresh_token"], data["refresh_token"])
        raise McpOutbound::Blocked
      end

      @refresh_started = true
      Attempt.new(kind: :refresh, fingerprint: fingerprint(record))
    end

    def capture_mcp(env)
      scheme, token = env.request_headers["Authorization"].to_s.split(" ", 2)
      if token
        record = @store.owned_credential
        data = record&.data.to_h
        if data["refresh_token"].blank? && data["expires_at"].is_a?(Numeric) &&
            data["expires_at"] <= Time.now.to_i && exact_token?(token, data["access_token"])
          return Attempt.new(kind: :expired_access, fingerprint: fingerprint(record), scheme: scheme&.downcase)
        end
      end
      Attempt.new(kind: :mcp, scheme: scheme&.downcase)
    end

    def observe_mcp(attempt, response)
      return unless [ 401, 403 ].include?(response.status)

      challenge = RubyLLM::MCP::OAuth.challenge(response.headers["WWW-Authenticate"])
      challenge.each_value do |parameters|
        validate_raw_url!(parameters[:resource_metadata]) if parameters.key?(:resource_metadata)
      end
      if @operation == :use && response.status == 403 && challenge.slice("bearer", "dpop").values.any? { |params| params[:error] == "insufficient_scope" }
        raise McpAuthorization::InsufficientScope
      end

      invalid_token = response.status == 401 && challenge.dig(attempt.scheme, :error) == "invalid_token"
      @deny_refresh = true unless invalid_token
      if invalid_token && attempt.kind == :expired_access
        @rejected_credential = attempt.fingerprint
      end
    end

    def observe_refresh(attempt, response)
      data = json_object(response.body).to_h
      case data["error"]
      when "invalid_grant"
        @rejected_credential = attempt.fingerprint if [ 400, 401 ].include?(response.status)
      when "use_dpop_nonce"
        if !@nonce_retry && response.headers["DPoP-Nonce"].present?
          @nonce_retry = true
          @refresh_started = false
        end
      when nil
        @refresh_started = false if response.success? && data["access_token"].present?
      end
    end

    def validate_metadata(body)
      if (document = json_object(body))
        document.slice(*URL_FIELDS).each_value { |value| validate_raw_url!(value) }
        Array(document["authorization_servers"]).each { |url| validate_raw_url!(url) }
      end
    end

    def validate_raw_url!(url)
      McpOutbound.endpoint!(url, https_only: true)
    end

    # Faraday decomposes and re-encodes the query before the adapter sees it.
    def same_destination?(env, raw_url)
      expected = McpOutbound.endpoint!(raw_url, https_only: true)
      actual = env.url
      encoder = env.request.params_encoder || Faraday::Utils.default_params_encoder
      expected.origin == actual.origin && (expected.path.presence || "/") == (actual.path.presence || "/") &&
        encoder.decode(expected.query) == encoder.decode(actual.query)
    end

    def json_object(body)
      parsed = JSON.parse(body.to_s)
      parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def exact_token?(presented, stored)
      presented.present? && stored.is_a?(String) &&
        ActiveSupport::SecurityUtils.secure_compare(digest(presented), digest(stored))
    end

    def fingerprint(record)
      digest(record.read_attribute_before_type_cast("data"))
    end

    def digest(value)
      OpenSSL::HMAC.digest("SHA256", @fingerprint_key, value)
    end
end
