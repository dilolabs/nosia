require_relative "native_mcp_wire"

class NativeMcpOAuthWire < NativeMcpWire
  ORIGIN = "https://#{HOST}"
  METADATA_PATH = "/protected-resource"
  DISCOVERY_PATH = "/.well-known/oauth-authorization-server"
  REDIRECT_URI = "https://nosia.example.test/mcp/oauth/callback"

  attr_reader :oauth_requests, :resource_metadata, :issuer_metadata
  attr_accessor :challenge, :expires_in, :refresh_token, :refresh_response, :mcp_rejection, :before_reply, :metadata_response

  def initialize
    super
    @oauth_requests = []
    @access_tokens = []
    @expires_in = 3600
    @refresh_token = true
    @challenge = %(Bearer resource_metadata="#{ORIGIN}#{METADATA_PATH}")
    @resource_metadata = { "resource" => URL, "authorization_servers" => [ ORIGIN ], "scopes_supported" => [ "read" ] }
    @issuer_metadata = {
      "issuer" => ORIGIN, "authorization_endpoint" => "#{ORIGIN}/authorize",
      "token_endpoint" => "#{ORIGIN}/token", "registration_endpoint" => "#{ORIGIN}/register",
      "code_challenge_methods_supported" => [ "S256" ], "authorization_response_iss_parameter_supported" => true
    }
  end

  def reply(env)
    raise Minitest::Assertion, "Unexpected OAuth fixture host" unless env.url.host == HOST
    raise Minitest::Assertion, "OAuth fixture requires HTTPS" unless env.url.scheme == "https"

    path = env.url.path
    if path == "/mcp"
      handle_mcp(env)
    else
      form = URI.decode_www_form(env.body).to_h if path == "/token"
      @oauth_requests << { path:, verb: env.method, form:, body: env.body, headers: env.request_headers.dup }
      before_reply&.call(path, form)
      case [ env.method, path ]
      when [ :get, METADATA_PATH ], [ :get, "/.well-known/oauth-protected-resource/mcp" ]
        metadata_response&.call(path, resource_metadata) || document(resource_metadata)
      when [ :get, DISCOVERY_PATH ]
        metadata_response&.call(path, issuer_metadata) || document(issuer_metadata)
      when [ :post, "/register" ]
        document({ "client_id" => "fixture-dynamic-client", "client_secret" => "fixture-client-signing-secret" }, 201)
      when [ :post, "/token" ] then exchange(form)
      else raise Minitest::Assertion, "Unexpected OAuth fixture request #{env.method} #{path}"
      end
    end
  end

  def start(grant)
    url = grant.client.authorization_url(redirect_uri: REDIRECT_URI)
    [ url, URI.decode_www_form(URI(url).query).to_h ]
  end

  def callback(query)
    { state: query.fetch("state"), code: "fixture-code", iss: ORIGIN }
  end

  def authorize(grant)
    _, query = start(grant)
    grant.client.authorize(callback(query))
  end

  def token_requests
    oauth_requests.select { |request| request[:path] == "/token" }.pluck(:form)
  end

  private
    def handle_mcp(env)
      presented = env.request_headers["Authorization"]&.split(" ", 2)&.last
      unless @access_tokens.include?(presented)
        @oauth_requests << { path: "/mcp", verb: env.method, headers: env.request_headers.dup }
        return [ 401, { "WWW-Authenticate" => challenge }, "" ]
      end

      rpc = env.body ? JSON.parse(env.body) : {}
      before_reply&.call(rpc["method"], nil)
      if (response = mcp_rejection&.call(rpc, presented))
        @oauth_requests << { path: "/mcp", verb: env.method, headers: env.request_headers.dup }
        response
      else
        super_reply(env)
      end
    end

    def super_reply(env)
      NativeMcpWire.instance_method(:reply).bind_call(self, env)
    end

    def exchange(form)
      if form["grant_type"] == "refresh_token" && refresh_response
        failure = refresh_response.call(form)
        return failure if failure
      end

      sequence = @access_tokens.size + 1
      access_token = "fixture-access-#{sequence}"
      @access_tokens << access_token
      payload = { "access_token" => access_token, "expires_in" => expires_in, "token_type" => challenge.start_with?("DPoP") ? "DPoP" : "Bearer" }
      payload["refresh_token"] = "fixture-refresh-#{sequence}" if refresh_token
      document(payload)
    end

    def document(body, status = 200)
      [ status, { "Content-Type" => "application/json" }, JSON.generate(body) ]
    end
end
