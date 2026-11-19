require "test_helper"
require_relative "../support/mcp_oauth_fixtures"

class McpAuthorizationTest < ActiveSupport::TestCase
  include McpOauthFixtures

  test "static is the default and OAuth only accepts raw HTTPS on streamable transport" do
    assert_respond_to @server, :auth_mode
    assert_equal "static", @server.auth_mode
    @server.auth_mode = "oauth"
    assert @server.valid?
    @server.assign_attributes(endpoint: nil, url: NativeMcpOAuthWire::URL)
    assert @server.valid?
    @server.url = "http://mcp.example.test/mcp"
    refute @server.valid?
    @server.url = "https://@mcp.example.test/mcp"
    refute @server.valid?
    @server.assign_attributes(transport_type: "local", url: nil)
    refute @server.valid?
  end

  test "membership, account and connector independently partition grant ownership" do
    assert_respond_to @server, :oauth_grant_for
    other = oauth_fixture("mcp_servers", :oauth_other)
    duplicate = oauth_fixture("mcp_servers", :oauth_team_duplicate)
    [ @server, other, duplicate ].each { |server| server.update!(auth_mode: "oauth") }

    assert_nil @server.oauth_grant_for(@alice)
    grants = [ @server.begin_oauth_grant_for!(@alice), @server.begin_oauth_grant_for!(@bob),
      other.begin_oauth_grant_for!(@alice), duplicate.begin_oauth_grant_for!(@alice) ]
    assert_equal 4, grants.map(&:id).uniq.size
    assert_nil other.oauth_grant_for(@bob)
    assert_raises(McpAuthorization::Unavailable) { other.begin_oauth_grant_for!(@bob) }
    assert_equal grants.first, @server.oauth_grant_for(@alice)
    wrong_membership = McpAuthorization.new(account: @team, mcp_server: @server,
      account_user: oauth_fixture("account_users", :oauth_other_alice), endpoint: @server.endpoint)
    refute wrong_membership.valid?

    @wire.install(self) { grants.each { |grant| @wire.authorize(grant) } }
    assert_equal 4, grants.map { |grant| credential(grant).id }.uniq.size
    assert_equal 4, grants.map { |grant| credential(grant).data.fetch("access_token") }.uniq.size
  end

  test "a member grant can be allocated and looked up uncached in another active account" do
    @server.update!(auth_mode: "oauth")
    other_account = oauth_fixture("accounts", :oauth_other)
    ActsAsTenant.with_tenant(other_account) do
      assert_nil @server.oauth_grant_for(@alice)
      grant = @server.begin_oauth_grant_for!(@alice)
      assert_predicate grant, :persisted?
      assert_equal [ @team.id, @member.id, @alice.id, @server.id ],
        [ grant.account_id, grant.account_user_id, grant.user_id, grant.mcp_server_id ]
      ApplicationRecord.cache do
        assert_equal grant, @server.oauth_grant_for(@alice)
        assert_queries_count(1) { assert_equal grant, @server.oauth_grant_for(@alice) }
      end
    end
  end

  test "native discovery, issuer checking, PKCE and DPoP persist only encrypted grant material" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @server.update!(token: "static-fallback", headers: { "X-Static" => "static-header" })
    @wire.challenge = @wire.challenge.sub("Bearer", "DPoP")

    @wire.install(self) do
      refute grant.authorized?
      assert_empty @wire.oauth_requests
      url, query = @wire.start(grant)
      assert_equal "/authorize", URI(url).path
      assert_equal "S256", query.fetch("code_challenge_method")
      assert_equal NativeMcpOAuthWire::REDIRECT_URI, query.fetch("redirect_uri")
      registration = @wire.oauth_requests.find { |request| request[:path] == "/register" }
      assert_equal [ NativeMcpOAuthWire::REDIRECT_URI ], JSON.parse(registration.fetch(:body)).fetch("redirect_uris")
      pending = credential(grant).data.fetch("pending")
      verifier = pending.fetch("verifier")
      assert_equal query.fetch("code_challenge"), Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      assert_ciphertext credential(grant), verifier, pending.fetch("dpop_key"), pending.fetch("client_secret"), query.fetch("state")
      refute_includes grant.read_attribute_before_type_cast("endpoint"), NativeMcpOAuthWire::URL

      client = grant.client
      [ { state: "different" }, { iss: "https://other.example.test" }, { iss: nil } ].each do |override|
        assert_raises(McpServer::Client::Error) { client.authorize(@wire.callback(query).merge(override)) }
      end
      assert_empty @wire.token_requests
      client.authorize(@wire.callback(query))
      assert_raises(McpServer::Client::Error) { client.authorize(@wire.callback(query)) }
      assert_equal 1, @wire.token_requests.size
      assert_equal verifier, @wire.token_requests.last.fetch("code_verifier")
      assert_equal NativeMcpOAuthWire::REDIRECT_URI, @wire.token_requests.last.fetch("redirect_uri")
      assert_ciphertext credential(grant), "fixture-access-1", "fixture-refresh-1", pending.fetch("dpop_key")
      assert grant.reload.authorized?
      assert_equal "found", grant.client.tools.first.call(query: "fixture")
      assert @wire.requests.all? { |request| request[:headers]["Authorization"] == "DPoP fixture-access-1" }
      refute (@wire.requests + @wire.oauth_requests).any? { |request| request[:headers]["X-Static"] }
      assert_nil @server.client
      assert_equal grant.id, @server.begin_oauth_grant_for!(@alice).id
      assert_raises(McpAuthorization::Unavailable) { @wire.start(grant) }
    end
  end

  test "name, notes and an unchanged effective override preserve the grant" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @wire.install(self) { @wire.start(grant) }
    @server.update!(name: "new label", notes: "new notes", url: @server.endpoint)
    @server.update!(endpoint: "https://mcp.example.test/ignored")
    assert_equal grant, @server.oauth_grant_for(@alice)
    assert credential(grant).data.key?("pending")
  end

  test "a stale static edit cannot save an HTTP endpoint on a connector switched to OAuth" do
    stale = McpServer.find(@server.id)
    grant = begin_grant
    refute stale.update(endpoint: "http://mcp.example.test/mcp")
    assert_equal grant, @server.oauth_grant_for(@alice)
    assert_equal NativeMcpOAuthWire::URL, @server.reload.effective_endpoint
  end

  test "removing a member via the account collection still retires its grant" do
    grant = begin_grant
    @wire.install(self) { @wire.authorize(grant) }
    @team.users.delete(@alice)
    refute @server.oauth_grant_for(@alice)
    refute native_credentials.exists?(owner: grant)
  end

  test "a retained grant independently verifies the member still represents its original user" do
    grant = begin_grant
    @wire.install(self) do
      @wire.authorize(grant)
      caller = grant.client
      @team.account_users.find_by!(user: @bob).destroy!
      # Simulate a data repair that bypasses the ordinary retirement callback.
      @member.update_columns(user_id: @bob.id)

      before = @wire.requests.dup
      assert_nil @server.oauth_grant_for(@bob)
      refute grant.reload.authorized?
      assert_raises(McpAuthorization::Unavailable) { caller.tools }
      assert_equal before, @wire.requests
    end
  end

  {
    endpoint: -> { @server.update!(url: "https://mcp.example.test/reconfigured") },
    mode: -> { @server.update!(auth_mode: "static") },
    connector: -> { @server.destroy! },
    membership: -> { @member.destroy! },
    account: -> { @team.destroy! },
    disconnect: -> { @server.disconnect!(user: @alice) },
    owner: -> { @grant.retire! }
  }.each do |kind, invalidate|
    test "#{kind} invalidation retires tokens and pending state but keeps shared registration" do
      assert_respond_to @server, :begin_oauth_grant_for!
      @grant = begin_grant
      pending = @server.begin_oauth_grant_for!(@bob)
      @wire.install(self) do
        @wire.authorize(@grant)
        _, query = @wire.start(pending)
        old = @grant.client
        old.tools
        before = @wire.requests.size
        instance_exec(&invalidate)
        assert_raises(McpAuthorization::Unavailable) { old.tools }
        refute @grant.authorized?
        refute native_credentials.exists?(owner: @grant)
        assert_equal before, @wire.requests.size
        assert native_credentials.where(owner: nil).exists?
        if %i[membership owner disconnect].include?(kind)
          assert credential(pending).data.key?("pending")
        else
          refute native_credentials.exists?(owner: pending)
          assert_raises(McpAuthorization::Unavailable) { pending.client.authorize(@wire.callback(query)) }
        end
        if kind == :owner
          refute_equal @grant.id, @server.begin_oauth_grant_for!(@alice).id
        end
      end
    end
  end

  test "missing native schema or encryption configuration fails closed before discovery" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @wire.install(self) do
      with_singleton_replacement(native_credentials, :table_exists?, -> { false }) do
        assert_raises(McpServer::Client::Error) { grant.client }
      end
      config = ActiveRecord::Encryption.config
      with_singleton_replacement(config, :primary_key, -> { raise ActiveRecord::Encryption::Errors::Configuration }) do
        assert_raises(McpServer::Client::Error) { grant.client }
      end
      assert_empty @wire.oauth_requests
      assert_empty @wire.requests
      assert_empty native_credentials.where(owner: grant)
    end
  end

  {
    challenge: [ "/mcp" ],
    resource: [ "/mcp", NativeMcpOAuthWire::METADATA_PATH ],
    authorization_servers: [ "/mcp", NativeMcpOAuthWire::METADATA_PATH ],
    issuer: [ "/mcp", NativeMcpOAuthWire::METADATA_PATH, NativeMcpOAuthWire::DISCOVERY_PATH ],
    authorization_endpoint: [ "/mcp", NativeMcpOAuthWire::METADATA_PATH, NativeMcpOAuthWire::DISCOVERY_PATH ],
    token_endpoint: [ "/mcp", NativeMcpOAuthWire::METADATA_PATH, NativeMcpOAuthWire::DISCOVERY_PATH ],
    registration_endpoint: [ "/mcp", NativeMcpOAuthWire::METADATA_PATH, NativeMcpOAuthWire::DISCOVERY_PATH ]
  }.each do |field, paths|
    test "rejects invalid raw URL syntax in OAuth #{field} before a downstream request" do
      assert_respond_to @server, :begin_oauth_grant_for!
      grant = begin_grant
      bad_url = "https://@#{NativeMcpWire::HOST}/fixture"
      case field
      when :challenge then @wire.challenge = %(Bearer resource_metadata="#{bad_url}")
      when :authorization_servers then @wire.resource_metadata[field.to_s] = [ bad_url ]
      when :resource then @wire.resource_metadata[field.to_s] = bad_url
      else @wire.issuer_metadata[field.to_s] = bad_url
      end
      @wire.install(self) { assert_raises(McpServer::Client::Error) { @wire.start(grant) } }
      assert_equal paths, @wire.oauth_requests.pluck(:path).uniq
      refute native_credentials.exists?(owner: grant)
    end
  end

  [ NativeMcpOAuthWire::METADATA_PATH, NativeMcpOAuthWire::DISCOVERY_PATH ].each do |redirect_path|
    test "rejects a discovery redirect from #{redirect_path} before native consumption" do
      grant = begin_grant
      @wire.metadata_response = ->(path, document) do
        if path == redirect_path
          [ 302, { "Content-Type" => "application/json", "Location" => "#{NativeMcpOAuthWire::ORIGIN}/fixture-redirect" },
            JSON.generate(document) ]
        end
      end
      @wire.install(self) do
        error = assert_raises(McpServer::Client::Error) { @wire.start(grant) }
        refute_includes error.message, "fixture-redirect"
        assert_nil error.cause
      end

      paths = [ "/mcp", NativeMcpOAuthWire::METADATA_PATH, NativeMcpOAuthWire::DISCOVERY_PATH ]
      assert_equal paths.take(paths.index(redirect_path) + 1), @wire.oauth_requests.pluck(:path).uniq
      refute native_credentials.exists?(owner: grant)
    end
  end

  test "refresh rotates credentials consumed by a fresh instance without losing tool error attribution" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @wire.expires_in = 120
    @wire.install(self) do
      @wire.authorize(grant)
      travel 121.seconds do
        @wire.expires_in = 3600
        client = grant.client
        @wire.fail_method = "tools/call"
        assert_equal({ error: "Tool execution error: The MCP server rejected the tool call" }, client.call("lookup", { "query" => "fixture" }))
        @wire.fail_method = nil
        assert_equal "found", grant.client.tools.first.call(query: "fresh")
        assert_equal "fixture-refresh-1", @wire.token_requests.last.fetch("refresh_token")
        assert_equal "fixture-refresh-2", credential(grant).data.fetch("refresh_token")
        assert_equal "Bearer fixture-access-2", @wire.requests.last[:headers]["Authorization"]
        assert_equal 2, @wire.token_requests.size
      end
    end
  end

  test "a refresh is attributed to the same token endpoint after Faraday encodes its query" do
    grant = begin_grant
    @wire.issuer_metadata["token_endpoint"] += "?z=old&a=two%20words"
    @wire.expires_in = 0
    @wire.install(self) do
      @wire.authorize(grant)
      @wire.expires_in = 3600
      assert_equal "found", grant.client.tools.first.call
    end
    assert_equal "fixture-refresh-2", credential(grant).data.fetch("refresh_token")
  end

  test "the OAuth connector does not negotiate tasks, apps or questions or poll unsolicited tasks" do
    grant = begin_grant
    @wire.legacy = true
    @wire.tool_result = { "resultType" => "task", "taskId" => "fixture-task", "status" => "working" }
    @wire.install(self) do
      @wire.authorize(grant)
      assert_raises(McpServer::Client::Error) { grant.client.call("lookup", {}) }
      initialize_request = @wire.requests.find { |request| request[:rpc]["method"] == "initialize" }
      assert_equal({}, initialize_request[:rpc].dig("params", "capabilities"))
      assert_empty @wire.methods_requested.grep(%r{\Atasks/})
    end
  end

  test "definitive refresh loss marks the matching grant and reconnect starts with no inherited refresh token" do
    assert_respond_to @server, :begin_oauth_grant_for!
    grant = begin_grant
    @wire.expires_in = 0
    @wire.refresh_response = ->(_) { [ 400, { "Content-Type" => "application/json" }, '{"error":"invalid_grant"}' ] }
    @wire.install(self) do
      @wire.authorize(grant)
      client = grant.client
      error = assert_raises(McpServer::Client::Error) { client.tools }
      assert_instance_of McpAuthorization::ReconnectRequired, error
      assert_nil error.cause
      assert grant.reload.reconnect_required_at
      refute grant.authorized?
      assert_equal 1, @wire.token_requests.count { |form| form["grant_type"] == "refresh_token" }
      assert_raises(McpAuthorization::Unavailable) { client.tools }
      fresh = @server.begin_oauth_grant_for!(@alice)
      refute_equal grant.id, fresh.id
      refute native_credentials.exists?(owner: grant)
      @wire.refresh_token = false
      @wire.expires_in = 3600
      @wire.authorize(fresh)
      assert fresh.authorized?
      refute credential(fresh).data.key?("refresh_token")
    end
  end

  [ "timeout", 429, 503, 401 ].each do |failure|
    test "transient #{failure} during refresh preserves the grant without a second exchange" do
      assert_respond_to @server, :begin_oauth_grant_for!
      grant = begin_grant
      @wire.expires_in = 0
      @wire.refresh_response = ->(_) do
        raise Faraday::TimeoutError, "fixture-timeout" if failure == "timeout"

        [ failure, { "Content-Type" => "application/json" }, '{"error":"temporarily_unavailable"}' ]
      end
      @wire.mcp_rejection = ->(*) { [ 401, { "WWW-Authenticate" => "Bearer" }, "" ] }
      @wire.install(self) do
        @wire.authorize(grant)
        error = assert_raises(McpServer::Client::Error) { grant.client.tools }
        assert_instance_of McpAuthorization::Unavailable, error
        assert_nil error.cause
      end
      assert_nil grant.reload.reconnect_required_at
      assert grant.authorized?
      assert_equal 1, @wire.token_requests.count { |form| form["grant_type"] == "refresh_token" }
    end
  end

  { expired: [ "invalid_token", 401, 0, true ], still_valid: [ "invalid_token", 401, 3600, false ],
    wrong_scheme: [ "invalid_token", 401, 0, false ],
    ambiguous: [ nil, 401, 0, false ], insufficient_scope: [ "insufficient_scope", 403, 0, false ] }.each do |kind, (code, status, expires, reconnect)|
    test "#{kind} MCP rejection only retires an exact expired access token if explicitly invalid" do
      assert_respond_to @server, :begin_oauth_grant_for!
      grant = begin_grant
      @wire.expires_in = expires
      @wire.refresh_token = false
      scheme = kind == :wrong_scheme ? "DPoP" : "Bearer"
      challenge = code ? %(#{scheme} error="#{code}", error_description="fixture-provider-detail", scope="fixture-private-scope") : scheme
      @wire.mcp_rejection = ->(*) { [ status, { "WWW-Authenticate" => challenge }, "" ] }
      @wire.install(self) do
        @wire.authorize(grant)
        error = assert_raises(McpServer::Client::Error) { grant.client.tools }
        expected = if reconnect
          McpAuthorization::ReconnectRequired
        elsif kind == :insufficient_scope
          McpAuthorization::InsufficientScope
        else
          McpAuthorization::Unavailable
        end
        assert_instance_of expected, error
        assert_nil error.cause
        refute_includes error.message, "fixture-provider-detail"
        refute_includes error.message, "fixture-private-scope"
      end
      assert_equal reconnect, grant.reload.reconnect_required_at.present?
      assert_equal 1, @wire.token_requests.size
    end
  end

  test "an ambiguous 401 with a stored refresh token does not initiate a refresh" do
    grant = begin_grant
    @wire.install(self) do
      @wire.authorize(grant)
      @wire.mcp_rejection = ->(*) { [ 401, { "WWW-Authenticate" => "Bearer" }, "" ] }
      assert_raises(McpServer::Client::Error) { grant.client.tools }
    end
    assert grant.authorized?
    assert_equal [ "authorization_code" ], @wire.token_requests.pluck("grant_type")
  end

  private
    def begin_grant
      @server.update!(auth_mode: "oauth")
      @server.begin_oauth_grant_for!(@alice)
    end

    def assert_ciphertext(record, *secrets)
      assert record.encrypted_attribute?(:data)
      raw = record.read_attribute_before_type_cast("data")
      secrets.each { |secret| refute_includes raw, secret }
    end
end
