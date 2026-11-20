require "test_helper"
require_relative "../support/mcp_oauth_fixtures"

class McpOauthAuthorizationsTest < ActionDispatch::IntegrationTest
  include McpOauthFixtures

  CALLBACK = "/mcp/oauth/callback"
  CODE = "fixture-private-callback-code"
  DETAIL = "fixture-private-provider-description"
  CONSENT_PATH = "/fixture-private-consent-location"

  setup do
    @server.update!(auth_mode: "oauth",
      token: "fixture-private-static-token", headers: { "X-Static" => "fixture-private-static-header" })
    @server.update_columns(status: "ready", last_error: "shared-private-diagnostic", latency_ms: 123_456,
      metadata: { tools_cache: [ { name: "shared-private-tool" } ] })
    @other = oauth_fixture("accounts", :oauth_other)
    @other.update!(created_at: 1.day.ago)
    @alice_browser = authenticated_browser(@alice)
    @saved_origin = ENV["NOSIA_URL"]
    ENV["NOSIA_URL"] = "https://nosia.example.test/"
    stub_url_resolver("93.184.216.34")
  end

  teardown do
    ENV["NOSIA_URL"] = @saved_origin
    unstub_url_resolver
  end

  test "consent returns to its original path account and no other member borrows access" do
    bob = authenticated_browser(@bob)
    same_user = authenticated_browser(@alice)
    shared = @server.reload.attributes
    @other.update!(created_at: @team.created_at + 1.day)

    @wire.install(self) do
      assert_equal @team, @alice.first_account
      state = start
      @other.update!(created_at: @team.created_at - 1.day)
      @alice_browser.get account_mcp_servers_path(@other)
      assert_equal @other, @alice.first_account
      [ bob, same_user ].each do |browser|
        callback(state, browser:)
        assert_equal root_path, location_path(browser)
        browser.get detail_path
        assert_equal "Authorization required", Nokogiri::HTML5(browser.response.body).at_css(".n-mcp-status").text.strip
        refute_includes browser.response.body, "Look up a fixture"
      end
      assert_empty @wire.token_requests
      callback(state)
      assert_equal detail_path, location_path
      assert_equal "Authorized", @alice_browser.flash[:notice]
      assert_equal 1, @wire.token_requests.size

      @alice_browser.follow_redirect!
      assert_includes @alice_browser.response.body, "Look up a fixture"
      refute_includes @alice_browser.response.body, "shared-private"
      assert_empty @wire.methods_requested & %w[tools/call prompts/get resources/read]
      count = @wire.requests.size
      bob.get detail_path
      assert_includes bob.response.body, "Authorization required"
      refute_includes bob.response.body, "Look up a fixture"
      [ test_connection_mcp_server_path(@server), account_mcp_server_connection_test_path(@team, @server) ].each do |path|
        bob.post path, as: :json
        assert_equal 422, bob.response.status
        assert_equal "Authorize this connector before using it.", bob.response.parsed_body.fetch("error")
      end
      [ execute_tool_mcp_server_path(@server), account_mcp_server_tool_execution_path(@team, @server) ].each do |path|
        bob.post path, as: :json, params: { tool_name: "lookup" }
        assert_equal({ "error" => "Authorize this connector before using it." }, bob.response.parsed_body)
      end
      assert_equal count, @wire.requests.size
      assert_equal shared, @server.reload.attributes
    end
  end

  test "wrong state is unrelated but matching malformed, denied, or wrong issuer attempts are consumed" do
    @wire.install(self) do
      state = start
      callback("unrelated")
      assert_equal root_path, location_path
      callback(state, code: [ CODE ])
      assert_equal detail_path, location_path
      assert_equal "This authorization attempt is invalid or no longer active. Start again.", @alice_browser.flash[:alert]
      callback(state)
      assert_equal root_path, location_path

      state = start
      callback(state, iss: "https://wrong-issuer.example.test")
      assert_equal detail_path, location_path
      assert_equal "Could not complete authorization. Start again.", @alice_browser.flash[:alert]
      callback(state)
      assert_equal root_path, location_path

      state = start
      callback(state, code: nil, error: "access_denied", error_description: DETAIL)
      assert_equal "Authorization was declined. You can try again.", @alice_browser.flash[:alert]
      assert_empty @wire.token_requests
    end
  end

  test "expiry, newer starts and replay cannot change a usable grant" do
    @wire.install(self) do
      old = start
      current = start
      callback(old)
      assert_empty @wire.token_requests
      callback(current)
      assert_equal "Authorized", @alice_browser.flash[:notice]
      callback(current)
      assert_equal root_path, location_path
      assert_equal 1, @wire.token_requests.size
      @alice_browser.post authorization_path
      assert_equal detail_path, location_path
      assert_equal "Disconnect your current authorization before starting again.", @alice_browser.flash[:alert]

      @alice_browser.delete authorization_path
      expired = start
      travel 11.minutes do
        callback(expired)
        assert_equal detail_path, location_path
        assert_equal "This authorization attempt expired. Start again.", @alice_browser.flash[:alert]
      end
      assert_equal 1, @wire.token_requests.size
    end
  end

  test "foreign and retired identities cannot complete consent" do
    @wire.install(self) do
      foreign = oauth_fixture("mcp_servers", :oauth_other)
      bob = authenticated_browser(@bob)
      bob.post account_mcp_server_oauth_authorization_path(@other, foreign)
      assert_equal 404, bob.response.status
      state = start
      @member.destroy!
      callback(state)
      assert_equal root_path, location_path
      assert_nil @server.oauth_grant_for(@alice)
      assert_empty @wire.token_requests
    end
  end

  test "disconnect retires only the acting member and pending callbacks cannot restore it" do
    bob = authenticated_browser(@bob)
    @wire.install(self) do
      callback(start(browser: bob), browser: bob)
      pending = start
      @alice_browser.delete authorization_path
      assert_private_redirect(@alice_browser)
      assert_equal detail_path, location_path
      assert_equal "Your authorization was disconnected.", @alice_browser.flash[:notice]
      callback(pending)
      refute @server.oauth_grant_for(@alice)&.authorized?
      assert @server.oauth_grant_for(@bob).authorized?
      assert_equal 1, @wire.token_requests.size

      pending = start
      @alice_browser.delete detail_path
      callback(pending)
      assert_equal root_path, location_path
      assert_equal 1, @wire.token_requests.size
    end
  end

  test "origin is verified independently of request headers before discovery" do
    @wire.install(self) do
      [ nil, "http://nosia.example.test", "https://@nosia.example.test", "https://nosia.example.test/?",
        "https://nosia.example.test/#", "https://nosia.example.test/subpath", "https://127.0.0.1" ].each do |origin|
        ENV["NOSIA_URL"] = origin
        @alice_browser.post authorization_path, headers: { "X-Forwarded-Host" => "public.example.test", "X-Forwarded-Proto" => "https" }
        assert_equal detail_path, location_path
        assert_equal "Set NOSIA_URL to a public HTTPS origin before using OAuth.", @alice_browser.flash[:alert]
      end
      assert_empty @wire.oauth_requests
      assert_nil @server.oauth_grant_for(@alice)
    end
  end

  test "callback and old OAuth actions return to the configured origin despite forwarded request headers" do
    hostile = { "Host" => "incoming.example.test", "X-Forwarded-Host" => "forwarded.example.test", "X-Forwarded-Proto" => "http" }
    @wire.install(self) do
      state = start
      @alice_browser.get CALLBACK, params: { code: CODE, state: state, iss: NativeMcpOAuthWire::ORIGIN, return_to: "https://ignored.example.test" }, headers: hostile
      assert_private_redirect(@alice_browser)
      assert_equal "https://nosia.example.test#{detail_path}", @alice_browser.response.location
      assert_equal "Authorized", @alice_browser.flash[:notice]
      assert_empty @alice_browser.response.body
      @alice_browser.post account_mcp_server_connection_test_path(@team, @server), headers: hostile
      assert_private_redirect(@alice_browser)
      assert_equal "https://nosia.example.test#{detail_path}", @alice_browser.response.location
      @alice_browser.delete account_mcp_server_connection_path(@team, @server), headers: hostile
      assert_private_redirect(@alice_browser)
      assert_equal "https://nosia.example.test#{detail_path}", @alice_browser.response.location
    end
  end

  test "setup and callback fallback use an internal relative Location when origin is unusable" do
    hostile = { "X-Forwarded-Host" => "forwarded.example.test", "X-Forwarded-Proto" => "https" }
    ENV["NOSIA_URL"] = "https://127.0.0.1"
    @alice_browser.post authorization_path, headers: hostile
    assert_private_redirect(@alice_browser)
    assert_equal detail_path, @alice_browser.response.location
    assert_equal "Set NOSIA_URL to a public HTTPS origin before using OAuth.", @alice_browser.flash[:alert]

    @alice_browser.get CALLBACK, params: { code: CODE, state: "unmatched", error_description: DETAIL }, headers: hostile
    assert_private_redirect(@alice_browser)
    assert_equal root_path, @alice_browser.response.location
    assert_empty @alice_browser.response.body
  end

  test "unsafe consent destination and providers that need pre-registration get local outcomes" do
    @wire.install(self) do
      @wire.issuer_metadata["authorization_endpoint"] = "https://127.0.0.1/authorize"
      with_singleton_replacement(UrlGuard, :resolve, ->(host) { [ IPAddr.new(host == "127.0.0.1" ? host : "93.184.216.34") ] }) do
        @alice_browser.post authorization_path
        assert_equal detail_path, location_path
        assert_equal "The provider’s consent page must use a public HTTPS address.", @alice_browser.flash[:alert]
      end
      @wire.issuer_metadata["authorization_endpoint"] = "#{NativeMcpOAuthWire::ORIGIN}/authorize"
      @wire.issuer_metadata.delete("registration_endpoint")
      @alice_browser.post authorization_path, headers: { "Accept-Language" => "fr" }
      assert_equal detail_path, location_path
      assert_equal I18n.t("nosia.mcp_workspace.oauth.registration_unsupported", locale: :fr), @alice_browser.flash[:alert]
      assert_empty @wire.token_requests
    end
  end

  test "oauth launch requires a CSRF token and rejects cross origin native forms" do
    old = ApplicationController.allow_forgery_protection
    ApplicationController.allow_forgery_protection = true
    @wire.install(self) do
      @alice_browser.get authorization_path
      assert_equal 404, @alice_browser.response.status
      @alice_browser.post authorization_path
      assert_equal 422, @alice_browser.response.status
      assert_equal "no-store", @alice_browser.response.headers["Cache-Control"]
      @alice_browser.get detail_path
      page = Nokogiri::HTML5(@alice_browser.response.body)
      form = page.at_css("form[action='#{authorization_path}'][data-turbo=false]")
      assert form
      token = form.at_css("input[name=authenticity_token]")["value"]
      @alice_browser.post authorization_path, params: { authenticity_token: token }, headers: { "Origin" => "https://foreign.example.test" }
      assert_equal 422, @alice_browser.response.status
      assert_equal "no-referrer", @alice_browser.response.headers["Referrer-Policy"]
      assert_empty @wire.oauth_requests
      @alice_browser.post authorization_path, params: { authenticity_token: token }
      assert_private_redirect(@alice_browser)
      assert_equal NativeMcpOAuthWire::HOST, URI(@alice_browser.response.location).host
    end
  ensure
    ApplicationController.allow_forgery_protection = old
  end

  test "anonymous callbacks never persist or reflect callback data" do
    browser = open_session
    callback("fixture-private-anonymous-state", browser:)
    assert_private_redirect(browser)
    assert_equal root_path, location_path(browser)
    assert_nil browser.request.session[:return_to_after_authenticating]
    refute_includes browser.response.body, CODE
  end

  test "callback cannot use pending browser state after changing authenticated sessions" do
    @wire.install(self) do
      state = start
      prior_id = @alice_browser.cookies[:session_id]
      @alice_browser.post login_path, params: { email: @alice.email, password: "fixture-password" }
      refute_equal prior_id, @alice_browser.cookies[:session_id]
      callback(state)
      assert_equal root_path, location_path
      assert_empty @wire.token_requests
    end
  end

  test "only five most recent pending attempts are available from a browser" do
    @wire.install(self) do
      first, *states = Array.new(6) { start }
      entries = @alice_browser.request.session[:mcp_oauth_attempts]
      assert_equal states.map { |state| Digest::SHA256.hexdigest(state) }, entries.keys
      assert entries.values.all? { |entry| entry.keys.sort == %w[account_id deadline grant_id server_id session_id] }
      callback(first)
      assert_equal root_path, location_path
      callback(states.last)
      assert_equal detail_path, location_path
      assert_equal "Authorized", @alice_browser.flash[:notice]
      assert_equal 1, @wire.token_requests.size
    end
  end

  test "consent redirect and malformed or denied callbacks redact Rails logs and keep markers out of feedback" do
    @wire.issuer_metadata["authorization_endpoint"] = "#{NativeMcpOAuthWire::ORIGIN}#{CONSENT_PATH}?vendor=fixture-private-query"
    captured = StringIO.new
    logger = ActiveSupport::Logger.new(captured)
    Rails.logger.broadcast_to(logger)
    @wire.install(self) do
      state = start
      assert_includes @alice_browser.response.location, CONSENT_PATH
      assert_empty @alice_browser.response.body
      markers = [ state, CODE, DETAIL, CONSENT_PATH, "fixture-private-query" ]
      @alice_browser.get "#{CALLBACK}?state=#{state}&c%6Fde%5B%5D=#{CODE}&error_description%5Bx%5D=#{DETAIL}"
      assert_private_redirect(@alice_browser)
      assert_empty @alice_browser.response.body
      markers.each { |marker| refute_includes @alice_browser.response.location, marker }
      @alice_browser.follow_redirect!
      markers.each { |marker| refute_includes @alice_browser.response.body, marker }
      state = start
      callback(state, code: nil, error: "access_denied", error_description: DETAIL)
      assert_includes @alice_browser.flash[:alert], "declined"
      assert_includes captured.string, "Redirected to [FILTERED]"
      (markers + [ state ]).each { |marker| refute_includes captured.string, marker }
    end
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  test "conflicting callback parameter shapes are rejected without logging raw query values" do
    captured = StringIO.new
    logger = ActiveSupport::Logger.new(captured)
    Rails.logger.broadcast_to(logger)
    @wire.install(self) do
      state = start
      @alice_browser.get "#{CALLBACK}?state=#{state}&code=#{CODE}&code%5B%5D=#{DETAIL}"
      assert_private_redirect(@alice_browser)
      assert_equal detail_path, location_path
      refute_includes @alice_browser.response.body, CODE
      refute_includes captured.string, CODE
      refute_includes captured.string, DETAIL
      assert_empty @wire.token_requests
      callback(state)
      assert_equal root_path, location_path
    end
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  test "save and lists are offline even when the current grant is ready and preserve existing static secrets" do
    @wire.install(self) do
      callback(start)
      count = @wire.requests.size
      oauth_count = @wire.oauth_requests.size
      failure = method(:flunk)
      with_singleton_replacement(McpServer::Client, :new, ->(*) { failure.call("Saving and listing must not construct a native client") }) do
        @alice_browser.patch detail_path, params: { mcp_server: { name: "Renamed", auth_mode: "oauth",
          token: "ignore-me", configuration_values: { api_key: "ignore-me" }, remove_credentials: [ "token" ] } }
        assert_equal 303, @alice_browser.response.status
        @alice_browser.follow_redirect!
        assert_equal "Authorized", Nokogiri::HTML5(@alice_browser.response.body).at_css(".n-mcp-status").text.strip
        assert_includes @alice_browser.response.body, "Connect to discover"
        @alice_browser.get account_mcp_servers_path(@team)
        row = Nokogiri::HTML5(@alice_browser.response.body).at_css("#mcp_server_#{@server.id} .n-mcp-status")
        assert_equal "Authorized", row.text.strip
        @alice_browser.get account_mcp_servers_path(@team, status: "ready")
        refute_includes @alice_browser.response.body, "Renamed"
      end
      @alice_browser.get edit_account_mcp_server_path(@team, @server)
      assert_includes @alice_browser.response.body, "mcp_server[auth_mode]"
      refute_includes @alice_browser.response.body, "fixture-private-static"
      @alice_browser.patch detail_path, params: { mcp_server: { auth_mode: "oauth", endpoint: "http://mcp.example.test/mcp" } }
      assert_equal 422, @alice_browser.response.status
      refute_includes @alice_browser.response.body, "fixture-private-static"
      @alice_browser.post account_mcp_servers_path(@team), params: { mcp_server: {
        name: "New OAuth", endpoint: NativeMcpOAuthWire::URL, auth_mode: "oauth", transport_type: "streamable" } }
      assert_equal 303, @alice_browser.response.status
      @alice_browser.follow_redirect!
      assert_includes @alice_browser.response.body, "Authorization required"
      assert_equal count, @wire.requests.size
      assert_equal oauth_count, @wire.oauth_requests.size
      assert_equal "fixture-private-static-token", @server.reload.token
      assert_equal "fixture-private-static-header", @server.headers.fetch("X-Static")
      assert_nil @server.api_key
    end
  end

  test "OAuth edits retain the override on unchanged and invalid submissions" do
    @server.update!(endpoint: "https://old.example.test/mcp", url: NativeMcpOAuthWire::URL)
    @wire.install(self) do
      callback(start)
      grant = @server.oauth_grant_for(@alice)
      count = @wire.oauth_requests.size
      @alice_browser.get edit_account_mcp_server_path(@team, @server)
      field = Nokogiri::HTML5(@alice_browser.response.body).at_css("#mcp_server_endpoint")
      assert_equal "https://old.example.test/mcp", field["value"]

      @alice_browser.patch detail_path, params: { mcp_server: { endpoint: field["value"], notes: "Unchanged URL" } }
      @alice_browser.follow_redirect!
      assert_equal "https://old.example.test/mcp", @server.reload.endpoint
      assert_equal NativeMcpOAuthWire::URL, @server.url
      assert_equal grant, @server.oauth_grant_for(@alice)

      @alice_browser.patch detail_path, params: { mcp_server: { endpoint: "http://mcp.example.test/insecure" } }
      assert_equal 422, @alice_browser.response.status
      field = Nokogiri::HTML5(@alice_browser.response.body).at_css("#mcp_server_endpoint")
      assert_equal "http://mcp.example.test/insecure", field["value"]
      assert_equal NativeMcpOAuthWire::URL, @server.reload.effective_endpoint
      assert_equal grant, @server.oauth_grant_for(@alice)
      assert_equal count, @wire.oauth_requests.size
      assert_empty @wire.requests
    end
  end

  test "saving a different OAuth URL clears the encrypted override and retires its grant without discovery" do
    @server.update!(endpoint: "https://old.example.test/mcp", url: NativeMcpOAuthWire::URL)
    @wire.install(self) do
      callback(start)
      grant = @server.oauth_grant_for(@alice)
      count = @wire.oauth_requests.size
      url = "https://new.example.test/mcp"
      fail_on_lookup = method(:flunk)
      with_singleton_replacement(UrlGuard, :resolve, ->(*) { fail_on_lookup.call("Save and its redirect must not resolve a host") }) do
        @alice_browser.patch detail_path, params: { mcp_server: { endpoint: url } }
        assert_private_redirect(@alice_browser)
        @alice_browser.follow_redirect!
      end
      assert_equal url, @server.reload.effective_endpoint
      assert_nil @server.url
      refute McpAuthorization.exists?(id: grant.id)
      assert_equal "fixture-private-static-header", @server.headers.fetch("X-Static")
      assert_equal count, @wire.oauth_requests.size
      assert_empty @wire.requests
    end
  end

  test "OAuth to static keeps the opted-in saved credentials when replacement fields are blank" do
    @alice_browser.patch detail_path, params: { mcp_server: { auth_mode: "static", configuration_values: { token: "", api_key: "" } } }
    assert_private_redirect(@alice_browser)
    assert_equal "static", @server.reload.auth_mode
    assert_equal "fixture-private-static-token", @server.token
  end

  test "an old static form cannot silently switch OAuth back to static on either workspace route" do
    bob = authenticated_browser(@bob)
    [ account_mcp_server_path(@team, @server), mcp_server_path(@server) ].each do |path|
      @server.update!(auth_mode: "static")
      edit_path = "#{path}/edit"
      bob.get edit_path
      assert_equal 200, bob.response.status
      original_mode = Nokogiri::HTML5(bob.response.body).at_css("input[name='mcp_server[editing_auth_mode]']")["value"]
      assert_equal "static", original_mode
      # The old form was opened in static mode before a different edit won.
      @server.update!(auth_mode: "oauth")
      before = @server.attributes

      bob.patch path, params: { mcp_server: { editing_auth_mode: original_mode, auth_mode: "static",
        token: "stale-secret" } }, headers: { "Accept-Language" => "fr" }
      assert_equal 422, bob.response.status
      page = Nokogiri::HTML5(bob.response.body)
      assert_includes page.at_css("[data-form-errors-target=summary]").text, "Rechargez"
      assert_equal original_mode, page.at_css("input[name='mcp_server[editing_auth_mode]']")["value"]
      refute_includes bob.response.body, "stale-secret"
      assert_equal before, @server.reload.attributes
    end
  end

  test "old OAuth forms cannot overwrite a new endpoint or retire grants on either workspace route" do
    bob = authenticated_browser(@bob)
    [ account_mcp_server_path(@team, @server), mcp_server_path(@server) ].each do |path|
      @server.update!(endpoint: "https://mcp.example.test/before")
      bob.get "#{path}/edit"
      assert_equal 200, bob.response.status
      form = Nokogiri::HTML5(bob.response.body)
      old_url = form.at_css("#mcp_server_endpoint")["value"]
      original_revision = form.at_css("input[name='mcp_server[editing_connection_revision]']")&.[]("value")
      @server.update!(endpoint: NativeMcpOAuthWire::URL)

      @wire.install(self) do
        fresh_grant = @server.begin_oauth_grant_for!(@bob)
        @wire.authorize(fresh_grant)
        before = @server.reload.attributes
        count = @wire.oauth_requests.size
        bob.patch path, params: { mcp_server: { editing_auth_mode: "oauth", editing_connection_revision: original_revision,
          endpoint: old_url, auth_mode: "oauth", transport_type: "streamable", notes: "Only notes were edited" } }
        assert_equal 422, bob.response.status
        assert original_revision.present?
        refute_includes original_revision, "fixture-private-static-token"
        summary = Nokogiri::HTML5(bob.response.body).at_css("[data-form-errors-target=summary]")
        assert_includes summary.text, "Reload the page"
        assert_equal before, @server.reload.attributes
        assert_equal fresh_grant, @server.oauth_grant_for(@bob)
        assert fresh_grant.authorized?
        assert_equal count, @wire.oauth_requests.size
      end
    end
  end

  test "a static form opened before a credential replacement cannot overwrite the newer credential" do
    @server.update!(auth_mode: "static")
    bob = authenticated_browser(@bob)
    bob.get "#{detail_path}/edit"
    old_revision = Nokogiri::HTML5(bob.response.body).at_css("input[name='mcp_server[editing_connection_revision]']")&.[]("value")
    @server.update!(token: "fixture-newest-token")
    bob.patch detail_path, params: { mcp_server: { editing_auth_mode: "static", editing_connection_revision: old_revision,
      configuration_values: { token: "fixture-stale-token" } } }
    assert_equal 422, bob.response.status
    refute_includes bob.response.body, "fixture-stale-token"
    refute_includes bob.response.body, "fixture-newest-token"
    assert_equal "fixture-newest-token", @server.reload.token
  end

  test "two old static forms cannot overwrite a raw endpoint edit that preserves the configured override" do
    @server.update!(auth_mode: "static", url: NativeMcpWire::URL, endpoint: "https://mcp.example.test/before")
    @server.update_columns(status: "ready", latency_ms: 23, last_connected_at: Time.current,
      metadata: { tools_cache: [ { name: "saved" } ] })
    static_connection = @server.reload.slice(:status, :latency_ms, :last_connected_at, :metadata, :connection_test_attempt)
    first = authenticated_browser(@bob)
    second = authenticated_browser(@bob)
    scoped = account_mcp_server_path(@team, @server)
    legacy = mcp_server_path(@server)

    @wire.install(self) do
      [ [ scoped, legacy ], [ legacy, scoped ] ].each_with_index do |(first_path, second_path), index|
        forms = [ [ first, first_path ], [ second, second_path ] ].map do |browser, path|
          browser.get "#{path}/edit"
          page = Nokogiri::HTML5(browser.response.body)
          page.at_css("input[name='mcp_server[editing_connection_revision]']")["value"]
        end
        assert_equal forms.first, forms.last
        raw = "https://mcp.example.test/raw-#{index}"
        first.patch first_path, params: { mcp_server: { editing_connection_revision: forms.first, endpoint: raw } }
        assert_equal 302, first.response.status
        first.follow_redirect!
        assert_equal raw, @server.reload.endpoint
        assert_equal NativeMcpWire::URL, @server.effective_endpoint
        assert_equal static_connection, @server.slice(*static_connection.keys)

        second.patch second_path, params: { mcp_server: { editing_connection_revision: forms.last, endpoint: "https://mcp.example.test/stale" } }
        assert_equal 422, second.response.status
        assert_includes second.response.body, "Reload the page"
        assert_equal raw, @server.reload.endpoint
        assert_equal static_connection, @server.slice(*static_connection.keys)
      end
      assert_empty @wire.requests
      assert_empty @wire.oauth_requests
    end
  end

  test "ready OAuth can atomically switch to static with explicit replacement and removal" do
    @server.update!(api_key: "fixture-obsolete-key", headers: { "Authorization" => "Bearer fixture-private-static-token", "X-API-Key" => "fixture-obsolete-key" })
    @wire.install(self) do
      callback(start)
      grant = @server.oauth_grant_for(@alice)
      count = @wire.oauth_requests.size
      @alice_browser.patch detail_path, params: { mcp_server: { auth_mode: "static", name: "", remove_credentials: [ "api_key" ],
        configuration_values: { token: "fixture-replacement-token" } } }
      assert_equal 422, @alice_browser.response.status
      %w[fixture-obsolete-key fixture-replacement-token fixture-private-static-token].each do |secret|
        refute_includes @alice_browser.response.body, secret
      end
      assert_equal "oauth", @server.reload.auth_mode
      assert_equal grant, @server.oauth_grant_for(@alice)

      @alice_browser.patch detail_path, params: { mcp_server: { auth_mode: "static", remove_credentials: [ "api_key", "unlisted" ],
        configuration_values: { token: "fixture-replacement-token", unlisted: "do-not-save" } } }
      assert_private_redirect(@alice_browser)
      @alice_browser.follow_redirect!
      assert_equal "static", @server.reload.auth_mode
      assert_equal "fixture-replacement-token", @server.token
      assert_nil @server.api_key
      assert_equal({ "Authorization" => "Bearer fixture-replacement-token" }, @server.static_headers)
      refute @server.auth_config.key?("unlisted")
      refute McpAuthorization.exists?(id: grant.id)
      assert_equal count, @wire.oauth_requests.size
      assert_empty @wire.requests
    end
  end

  test "wrong transports and static mode cannot start OAuth" do
    @wire.install(self) do
      %w[streamable local stdio sse].each do |transport|
        @server.update_columns(auth_mode: "static", transport_type: transport)
        @alice_browser.post authorization_path
        assert_equal detail_path, location_path
        assert_equal "OAuth is available only for public HTTPS Streamable HTTP connectors.", @alice_browser.flash[:alert]
        next if transport == "streamable"

        @alice_browser.patch detail_path, params: { mcp_server: { auth_mode: "oauth" } }
        assert_equal 422, @alice_browser.response.status
        assert_equal "static", @server.reload.auth_mode
      end
      assert_empty @wire.oauth_requests
    end
  end

  test "scoped and legacy operations report typed member results without changing shared diagnostics" do
    bob = authenticated_browser(@bob)
    @wire.install(self) do
      callback(start(browser: bob), browser: bob)
      shared = @server.reload.attributes
      bob.get mcp_server_path(@server)
      assert_includes bob.response.body, authorization_path
      refute_includes bob.response.body, "shared-private"
      bob.post connect_mcp_server_path(@server)
      assert_equal detail_path, location_path(bob)
      bob.post test_connection_mcp_server_path(@server), as: :json
      assert_equal({ "success" => true, "status" => "authorized", "latency" => nil,
        "message" => "Connection established" }, bob.response.parsed_body)
      bob.post account_mcp_server_tool_execution_path(@team, @server), as: :json,
        params: { tool_name: "lookup", arguments: { query: "fixture" } }
      assert_equal({ "success" => true, "result" => "found" }, bob.response.parsed_body)
      refute @wire.requests.any? { |entry| entry[:headers]["X-Static"] || entry[:headers]["Authorization"].to_s.include?("fixture-private-static") }

      @wire.mcp_rejection = ->(*) { [ 403, { "WWW-Authenticate" => 'Bearer error="insufficient_scope"' }, DETAIL ] }
      bob.post account_mcp_server_connection_test_path(@team, @server)
      assert_equal detail_path, location_path(bob)
      bob.follow_redirect!
      assert_includes bob.response.body, "The provider did not grant enough access for this operation."
      bob.post execute_tool_mcp_server_path(@server), params: { tool_name: "lookup" }, as: :json
      assert_equal "The provider did not grant enough access for this operation.", bob.response.parsed_body.fetch("error")
      assert @server.oauth_grant_for(@bob).authorized?
      assert_equal shared, @server.reload.attributes

      @wire.mcp_rejection = ->(*) { [ 401, { "WWW-Authenticate" => 'Bearer error="invalid_token"' }, DETAIL ] }
      @wire.refresh_response = ->(*) { [ 503, { "Content-Type" => "application/json" }, '{"error":"temporarily_unavailable"}' ] }
      bob.post account_mcp_server_tool_execution_path(@team, @server), params: { tool_name: "lookup" }, as: :json
      assert_equal "Could not authenticate to the MCP server. Try again, or disconnect and authorize again.", bob.response.parsed_body.fetch("error")
      assert @server.oauth_grant_for(@bob).authorized?
      assert_equal shared, @server.reload.attributes

      @wire.refresh_response = ->(*) { [ 400, { "Content-Type" => "application/json" }, '{"error":"invalid_grant"}' ] }
      bob.post test_connection_mcp_server_path(@server), as: :json
      assert_equal({ "success" => false, "status" => "reconnect_required", "error" => "Reconnect your authorization to use this connector.",
        "message" => "Connection failed" }, bob.response.parsed_body)
      bob.get mcp_server_path(@server)
      assert_includes bob.response.body, "Reconnect required"
      assert_includes bob.response.body, "Reconnect with OAuth"
      assert_includes bob.response.body, "Clear my authorization"
      bob.post account_mcp_server_tool_execution_path(@team, @server), params: { tool_name: "lookup" }, as: :json
      assert_equal "Reconnect your authorization to use this connector.", bob.response.parsed_body.fetch("error")
      assert_equal shared, @server.reload.attributes
      bob.post disconnect_mcp_server_path(@server)
      assert_equal detail_path, location_path(bob)
      assert_nil @server.oauth_grant_for(@bob)
    end
  end

  test "capability browsing shares one native connection and distinguishes unavailable from empty" do
    @wire.install(self) do
      callback(start)
      @wire.fail_method = "prompts/list"
      @wire.resources = []
      @alice_browser.get detail_path
      page = Nokogiri::HTML5(@alice_browser.response.body)
      assert_includes page.at_css("#tools").text, "Look up a fixture"
      assert_includes page.at_css("#prompts").text, "Could not authenticate"
      assert_includes page.at_css("#resources").text, "reported no items"
      assert_equal 1, @wire.methods_requested.count("server/discover")
      assert_empty @wire.methods_requested & %w[tools/call prompts/get resources/read]
    end
  end

  test "OAuth connection test feedback belongs to the connector that was tested" do
    other_server = oauth_fixture("mcp_servers", :oauth_team_duplicate)
    other_server.update!(auth_mode: "oauth")
    @alice_browser.post account_mcp_server_connection_test_path(@team, @server)
    assert_equal detail_path, location_path
    @alice_browser.get account_mcp_server_path(@team, other_server)
    refute Nokogiri::HTML5(@alice_browser.response.body).at_css("#connection-test-result")
  end

  test "OAuth connection test feedback is discarded after the tested grant is replaced" do
    bob = authenticated_browser(@bob)
    @wire.install(self) do
      callback(start(browser: bob), browser: bob)
      tested = @server.oauth_grant_for(@bob)
      bob.post account_mcp_server_connection_test_path(@team, @server)
      assert_equal detail_path, location_path(bob)

      tested.retire!
      replacement = @server.begin_oauth_grant_for!(@bob)
      @wire.authorize(replacement)
      bob.follow_redirect!
      assert_includes bob.response.body, "Authorized"
      refute Nokogiri::HTML5(bob.response.body).at_css("#connection-test-result")
    end
  end

  test "OAuth connection test without a grant does not describe a new grant on its redirect" do
    bob = authenticated_browser(@bob)
    @wire.install(self) do
      bob.post account_mcp_server_connection_test_path(@team, @server)
      assert_equal detail_path, location_path(bob)
      @wire.authorize(@server.begin_oauth_grant_for!(@bob))

      bob.follow_redirect!
      assert_includes bob.response.body, "Authorized"
      refute Nokogiri::HTML5(bob.response.body).at_css("#connection-test-result")
    end
  end

  { success: :stay_oauth, failure: :stay_oauth, restored: :back_to_static, credentials: :replace_credentials }.each do |outcome, change|
    test "an in-flight static test cannot commit #{outcome} after its configuration changes" do
      @server.update!(auth_mode: "static")
      static_wire = NativeMcpWire.new
      static_wire.unavailable_method = "tools/list" if outcome == :failure
      original_reply = static_wire.method(:reply)
      server_id = @server.id
      expected = nil
      with_singleton_replacement(static_wire, :reply, ->(env) {
        if JSON.parse(env.body)["method"] == "tools/list" && !expected
          saved = McpServer.find(server_id)
          if change == :replace_credentials
            saved.update_columns(auth_config: { token: "fixture-rotated-during-exchange" })
          else
            saved.update!(auth_mode: "oauth")
            saved.update!(auth_mode: "static") if change == :back_to_static
          end
          expected = saved.reload.attributes
        end
        original_reply.call(env)
      }) do
        static_wire.install(self) do
          @alice_browser.post account_mcp_server_connection_test_path(@team, @server), as: :json
          assert_includes static_wire.methods_requested, "tools/list"
          assert_equal expected, @server.reload.attributes
          assert_equal 422, @alice_browser.response.status
          assert_equal false, @alice_browser.response.parsed_body.fetch("success")
        end
      end
    end
  end

  private
    def authenticated_browser(user)
      open_session do |browser|
        browser.host! "nosia.example.test"
        browser.https!
        browser.post login_path, params: { email: user.email, password: "fixture-password" }
        assert_equal 302, browser.response.status
        assert browser.cookies[:session_id].present?
      end
    end

    def authorization_path = "#{detail_path}/oauth_authorization"
    def detail_path = account_mcp_server_path(@team, @server)
    def location_path(browser = @alice_browser) = browser.response.location && URI(browser.response.location).path

    def start(browser: @alice_browser)
      browser.post authorization_path
      assert_private_redirect(browser)
      uri = URI(browser.response.location)
      assert_equal NativeMcpOAuthWire::HOST, uri.host
      query = URI.decode_www_form(uri.query).to_h
      assert_equal NativeMcpOAuthWire::REDIRECT_URI, query.fetch("redirect_uri")
      query.fetch("state")
    end

    def callback(state, browser: @alice_browser, **params)
      browser.get CALLBACK, params: { code: CODE, iss: NativeMcpOAuthWire::ORIGIN, state: }.merge(params).compact
      assert_private_redirect(browser)
    end

    def assert_private_redirect(browser)
      assert_equal 303, browser.response.status
      assert_equal "no-store", browser.response.headers["Cache-Control"]
      assert_equal "no-referrer", browser.response.headers["Referrer-Policy"]
    end
end
