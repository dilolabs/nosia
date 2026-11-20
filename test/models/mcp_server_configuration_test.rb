require "test_helper"
require_relative "../support/mcp_workspace_fixtures"
require_relative "../support/native_mcp_wire"

class McpServerConfigurationTest < ActiveSupport::TestCase
  include McpWorkspaceFixtures

  [ {}, { auth_mode: "static" } ].each do |attributes|
    test "a stale static credential save cannot change an OAuth connector #{attributes.empty? ? 'without' : 'with'} a submitted mode" do
      @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL, token: "retained-token")
      stale = @second.mcp_servers.find(@second_server.id)
      @second_server.update!(auth_mode: "oauth")
      before = @second_server.attributes

      refute stale.save_workspace(attributes, values: { token: "stale-replacement" })
      assert stale.errors.added?(:base, :workspace_configuration_changed)
      assert_equal before, @second_server.reload.attributes
    end
  end

  test "a stale editor cannot replace a credential for a changed effective endpoint" do
    @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL, token: "retained-token")
    stale = @second.mcp_servers.find(@second_server.id)
    @second_server.update!(url: "https://mcp.example.test/replacement")
    before = @second_server.attributes

    refute stale.save_workspace({}, values: { token: "stale-replacement" })
    assert stale.errors.added?(:base, :workspace_configuration_changed)
    assert_equal before, @second_server.reload.attributes
  end

  test "a stale model credential update cannot bypass the saved mode check" do
    @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL, token: "retained-token")
    stale = @second.mcp_servers.find(@second_server.id)
    @second_server.update!(auth_mode: "oauth")

    refute stale.update(token: "stale-replacement")
    assert stale.errors.added?(:base, :workspace_configuration_changed)
    assert_equal "retained-token", @second_server.reload.token
  end

  test "workspace saves discard credential attributes and inputs when the destination is OAuth" do
    @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL, token: "retained-token")
    config = @second_server.auth_config

    assert @second_server.save_workspace({ auth_mode: "oauth", auth_config: { token: "unlisted" }, api_key: "unlisted" },
      values: { token: "forged" }, removals: [ "token" ])
    assert @second_server.reload.oauth?
    assert_equal config, @second_server.auth_config
  end

  { endpoint: { endpoint: "https://mcp.example.test/new" }, transport: { transport_type: "stdio", command: "fixture" },
    mode: { auth_mode: "static" }, credentials: {} }.each do |change, attributes|
    test "#{change} saves invalidate connection diagnostics but retain unrelated metadata and encrypted credentials" do
      stdio = ENV["MCP_STDIO_ENABLED"]
      ENV["MCP_STDIO_ENABLED"] = "true"
      @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL,
        auth_mode: change == :mode ? "oauth" : "static", token: "retained-token", api_key: "retained-key")
      @second_server.update_columns(status: "ready", last_connected_at: Time.current, latency_ms: 42, last_error: "old",
        metadata: { catalog_id: "preserved", tools_cache: [], prompts_cache: [], resources_cache: [],
          capabilities: {}, server_info: {}, last_test_at: Time.current.iso8601 })
      values = change == :credentials ? { token: "replacement" } : {}

      assert @second_server.save_workspace(attributes, values:)
      assert @second_server.reload.status_disconnected?
      refute @second_server.ready_for_tools?
      assert_nil @second_server.last_connected_at
      assert_nil @second_server.latency_ms
      assert_nil @second_server.last_error
      assert_equal({ "catalog_id" => "preserved" }, @second_server.metadata)
      assert_equal change == :credentials ? "replacement" : "retained-token", @second_server.token
      assert_equal "retained-key", @second_server.api_key
    ensure
      ENV["MCP_STDIO_ENABLED"] = stdio
    end
  end

  test "name and notes edits preserve the connection diagnostics and readiness" do
    @second_server.update_columns(status: "ready", last_connected_at: Time.current, latency_ms: 42, last_error: "old",
      metadata: @second_server.metadata.merge("last_test_at" => "fixture"))
    before = @second_server.reload.slice(:status, :last_connected_at, :latency_ms, :last_error, :metadata)

    assert @second_server.save_workspace({ name: "Renamed", notes: "Kept readiness" }, values: {})
    assert_equal before, @second_server.reload.slice(*before.keys)
  end

  test "a configuration save clears diagnostics measured after the editor loaded" do
    @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL)
    editor = @second.mcp_servers.find(@second_server.id)
    assert editor.status_disconnected?
    @second_server.update_columns(status: "ready", last_connected_at: Time.current, latency_ms: 42, metadata: { tools_cache: [ "latest" ] })

    assert editor.save_workspace({ endpoint: "https://other.example.test/mcp" }, values: {})
    assert @second_server.reload.status_disconnected?
    assert_nil @second_server.last_connected_at
    assert_nil @second_server.latency_ms
    assert_nil @second_server.tools_cache
  end

  test "blank keeps saved secrets and replacement preserves other configuration" do
    @second_server.update!(connection_config: { env: { "UNEDITED" => "keep" } })
    assert @second_server.save_workspace({ notes: "Updated" }, values: { "api_key" => "", "team" => "New team" })
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
    assert_equal "New team", @second_server.auth_config.fetch("team")
    assert @second_server.save_workspace({}, values: { "api_key" => "replacement" })
    assert_equal "replacement", @second_server.reload.auth_config.fetch("api_key")
    assert_equal({ "UNEDITED" => "keep" }, @second_server.connection_config.fetch("env"))
  end

  test "required removal and contradictory instructions fail without database writes" do
    before = @second_server.attributes
    refute @second_server.save_workspace({}, values: {}, removals: [ "api_key" ])
    assert @second_server.errors.include?(:"configuration.api_key")
    assert_equal before, @second_server.reload.attributes
    refute @second_server.save_workspace({}, values: { "api_key" => "new" }, removals: [ "api_key" ])
    assert @second_server.errors.include?(:"configuration.api_key")
    assert_equal before, @second_server.reload.attributes
  end

  test "optional removal is explicit and a failed edit retains only public values" do
    @second_server.update!(metadata: { engine: "open_alex" }, auth_config: { api_key: "optional-secret" })
    assert @second_server.save_workspace({}, values: {}, removals: [ "api_key" ])
    refute @second_server.reload.auth_config.key?("api_key")
    @second_server.update!(metadata: { engine: "workspace-demo" }, auth_config: { api_key: "saved-secret", team: "Research" })
    refute @second_server.save_workspace({ name: "" }, values: { "api_key" => "not-for-html", "team" => "Retained" })
    assert_equal({ "team" => "Retained" }, @second_server.workspace_public_values)
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
  end

  { "token" => [ "Authorization", "Bearer remote-secret" ], "api_key" => [ "X-API-Key", "remote-secret" ] }.each do |credential, (header, injected_value)|
    test "replacing #{credential} retires its saved header before removal without another connection test" do
      public_headers = { "X-Custom" => "keep" }
      @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL,
        auth_config: { credential => "remote-secret" }, connection_config: { headers: public_headers, env: { "UNEDITED" => "keep" } })
      wire = NativeMcpWire.new
      wire.install(self) do
        assert @second.mcp_servers.find(@second_server.id).test_connection!
        tested = @second.mcp_servers.find(@second_server.id)
        assert_equal injected_value, wire.requests.last.fetch(:headers)[header]
        assert_equal public_headers, tested.headers
        tested.update!(headers: public_headers.merge(header => injected_value)) # Historical persisted copy
        connection = tested.connection_config.deep_dup
        [ {}, { credential => "" }, { credential => "remote-secret" } ].each do |values|
          assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: values)
          unchanged = @second.mcp_servers.find(@second_server.id)
          assert_equal "remote-secret", unchanged.auth_config.fetch(credential)
          assert_equal connection, unchanged.connection_config
        end

        editable = @second.mcp_servers.find(@second_server.id)
        before = editable.attributes.deep_dup
        refute editable.save_workspace({ name: "" }, values: { credential => "replacement-secret" })
        assert_equal before, @second.mcp_servers.find(@second_server.id).attributes

        assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: { credential => "replacement-secret" })
        replaced = @second.mcp_servers.find(@second_server.id)
        assert_equal "replacement-secret", replaced.auth_config.fetch(credential)
        assert_equal public_headers, replaced.headers
        assert_equal({ "UNEDITED" => "keep" }, replaced.env)
        assert_equal %w[server/discover tools/list], wire.methods_requested

        assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: {}, removals: [ credential ])
        removed = @second.mcp_servers.find(@second_server.id)
        refute removed.auth_config.key?(credential)
        assert_equal public_headers, removed.headers
        assert_equal({ "UNEDITED" => "keep" }, removed.env)
        assert removed.test_connection!
        assert_equal %w[server/discover tools/list] * 2, wire.methods_requested
        assert_equal "keep", wire.requests.last.fetch(:headers)["X-Custom"]
        assert_nil wire.requests.last.fetch(:headers)[header]
        refute_includes wire.requests.last.fetch(:headers).to_json, "remote-secret"
        refute_includes wire.requests.last.fetch(:headers).to_json, "replacement-secret"
      end
    end

    test "removing #{credential} clears its persisted HTTP header copy without changing other configuration" do
      other_header = header == "Authorization" ? "X-API-Key" : "Authorization"
      public_headers = { "X-Custom" => "keep", other_header => "custom-auth" }
      @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL,
        auth_config: { credential => "remote-secret" }, connection_config: { headers: public_headers.merge(header.downcase => injected_value), env: { "UNEDITED" => "keep" } })
      wire = NativeMcpWire.new
      wire.install(self) do
        assert @second.mcp_servers.find(@second_server.id).test_connection!
        tested = @second.mcp_servers.find(@second_server.id)
        assert_equal injected_value, tested.headers.fetch(header.downcase)
        before = tested.attributes.deep_dup

        refute tested.save_workspace({ name: "" }, values: {}, removals: [ credential ])
        assert_equal before, @second.mcp_servers.find(@second_server.id).attributes
        conflicted = @second.mcp_servers.find(@second_server.id)
        refute conflicted.save_workspace({}, values: { credential => "replacement" }, removals: [ credential ])
        assert_equal before, @second.mcp_servers.find(@second_server.id).attributes

        editable = @second.mcp_servers.find(@second_server.id)
        assert editable.save_workspace({ endpoint: "https://#{NativeMcpWire::HOST}/new" }, values: {}, removals: [ credential ])
        saved = @second.mcp_servers.find(@second_server.id)
        refute saved.auth_config.key?(credential)
        assert_equal({ "UNEDITED" => "keep" }, saved.env)
        assert saved.test_connection!
        assert_equal "/new", wire.requests.last.fetch(:path)
        refute wire.requests.last.fetch(:headers).key?(header)
        assert_equal "custom-auth", wire.requests.last.fetch(:headers)[other_header]
        assert_equal "keep", wire.requests.last.fetch(:headers)["X-Custom"]
        assert_equal public_headers, @second.mcp_servers.find(@second_server.id).headers
      end
    end

    test "replacing and removing #{credential} preserves a header that does not match the saved credential" do
      custom_headers = { header => "custom-auth", "X-Custom" => "keep" }
      @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
        auth_config: { credential => "remote-secret" }, connection_config: { headers: custom_headers })

      assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: { credential => "replacement-secret" })
      assert_equal custom_headers, @second.mcp_servers.find(@second_server.id).headers
      assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: {}, removals: [ credential ])
      saved = @second.mcp_servers.find(@second_server.id)
      refute saved.auth_config.key?(credential)
      assert_equal custom_headers, saved.headers
    end

    test "changing #{credential} preserves a legacy header when the old credential is unknown" do
      unknown_headers = { header => injected_value, "X-Custom" => "keep" }
      @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
        auth_config: {}, connection_config: { headers: unknown_headers })

      assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: { credential => "replacement-secret" })
      assert_equal unknown_headers, @second.mcp_servers.find(@second_server.id).headers
      assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: {}, removals: [ credential ])
      assert_equal unknown_headers, @second.mcp_servers.find(@second_server.id).headers
    end

    { transition: false, persisted_stdio: true }.each do |stage, already_stdio|
      test "removing #{credential} at #{stage} clears its HTTP header copy before returning to HTTP" do
        previous = ENV["MCP_STDIO_ENABLED"]
        ENV["MCP_STDIO_ENABLED"] = "true"
        public_headers = { "X-Custom" => "keep" }
        @second_server.update!(transport_type: "streamable", endpoint: NativeMcpWire::URL,
          auth_config: { credential => "remote-secret" }, connection_config: { headers: public_headers.merge(header => injected_value), env: { "UNEDITED" => "keep" } })
        wire = NativeMcpWire.new
        wire.install(self) do
          assert @second.mcp_servers.find(@second_server.id).test_connection!
          tested = @second.mcp_servers.find(@second_server.id)
          assert_equal injected_value, tested.headers.fetch(header)
          stdio_attributes = { transport_type: "stdio", endpoint: nil, command: "must-not-run" }
          if already_stdio
            assert tested.save_workspace(stdio_attributes, values: {})
            tested = @second.mcp_servers.find(@second_server.id)
            assert_equal injected_value, tested.headers.fetch(header)
          end

          assert tested.save_workspace(stdio_attributes, values: {}, removals: [ credential ])
          saved = @second.mcp_servers.find(@second_server.id)
          assert_equal "stdio", saved.transport_type
          refute saved.auth_config.key?(credential)
          refute saved.headers.key?(header)
          assert_equal public_headers, saved.headers
          assert_equal({ "UNEDITED" => "keep" }, saved.env)

          assert saved.save_workspace({ transport_type: "streamable", endpoint: "https://#{NativeMcpWire::HOST}/new" }, values: {})
          assert saved.test_connection!
          assert_equal %w[server/discover tools/list] * 2, wire.methods_requested
          assert_equal "/new", wire.requests.last.fetch(:path)
          assert_nil wire.requests.last.fetch(:headers)[header]
          assert_equal "keep", wire.requests.last.fetch(:headers)["X-Custom"]
          assert_equal({ "UNEDITED" => "keep" }, @second.mcp_servers.find(@second_server.id).env)
        end
      ensure
        ENV["MCP_STDIO_ENABLED"] = previous
      end
    end
  end

  test "local credential changes preserve registered connection configuration" do
    connection = { "headers" => { "X-API-Key" => "optional-secret" }, "env" => { "LOCAL" => "keep" } }
    @second_server.update!(metadata: { engine: "open_alex" }, auth_config: { api_key: "optional-secret" }, connection_config: connection)

    assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: { "api_key" => "replacement-secret" })
    assert_equal connection, @second.mcp_servers.find(@second_server.id).connection_config
    assert @second.mcp_servers.find(@second_server.id).save_workspace({}, values: {}, removals: [ "api_key" ])
    assert_equal connection, @second.mcp_servers.find(@second_server.id).connection_config
  end

  test "local transport cannot be coerced and unknown registrations preserve data" do
    refute @second_server.save_workspace({ transport_type: "streamable" }, values: {})
    assert_equal "local", @second_server.reload.transport_type
    @second_server.update!(metadata: { engine: "missing" })
    assert @second_server.save_workspace({ notes: "Safe edit" }, values: { api_key: "ignored" })
    assert_equal "saved-secret", @second_server.reload.auth_config.fetch("api_key")
    assert_equal [], @second_server.workspace_configuration_fields
  end

  test "unchanged argument arrays round trip instead of becoming strings" do
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
      connection_config: { args: [ "one value", "", "last" ], headers: { "X-Custom" => "keep" } })
    assert @second_server.save_workspace({ args: "one value\n\nlast" }, values: {})
    assert_equal [ "one value", "", "last" ], @second_server.reload.args
    assert_equal({ "X-Custom" => "keep" }, @second_server.headers)
  end

  test "disabled stdio cannot construct a client or test a persisted command" do
    previous = ENV["MCP_STDIO_ENABLED"]
    ENV["MCP_STDIO_ENABLED"] = "true"
    @second_server.update!(transport_type: "stdio", endpoint: nil, command: "must-not-run", args: [])
    ENV["MCP_STDIO_ENABLED"] = "false"
    before = @second_server.attributes
    with_singleton_replacement(RubyLLM, :mcp, ->(**) { raise Minitest::Assertion, "stdio construction attempted" }) do
      assert_nil @second_server.client
      refute @second_server.test_connection!
    end
    assert_equal before, @second_server.reload.attributes
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous
  end
end
