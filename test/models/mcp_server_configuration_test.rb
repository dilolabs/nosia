require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpServerConfigurationTest < ActiveSupport::TestCase
  include McpWorkspaceFixtures

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
    test "removing #{credential} clears its persisted HTTP header copy without changing other configuration" do
      other_header = header == "Authorization" ? "X-API-Key" : "Authorization"
      public_headers = { "X-Custom" => "keep", other_header => "custom-auth" }
      @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
        auth_config: { credential => "remote-secret" }, connection_config: { headers: public_headers, env: { "UNEDITED" => "keep" } })
      outgoing = []
      remote_client = Struct.new(:tools).new([])
      replacement = ->(config:, **_) { outgoing << config.deep_dup; remote_client }

      with_singleton_replacement(RubyLLM::MCP, :client, replacement) do
        assert @second.mcp_servers.find(@second_server.id).test_connection!
        tested = @second.mcp_servers.find(@second_server.id)
        assert_equal injected_value, tested.headers.fetch(header)
        before = tested.attributes.deep_dup

        refute tested.save_workspace({ name: "" }, values: {}, removals: [ credential ])
        assert_equal before, @second.mcp_servers.find(@second_server.id).attributes
        conflicted = @second.mcp_servers.find(@second_server.id)
        refute conflicted.save_workspace({}, values: { credential => "replacement" }, removals: [ credential ])
        assert_equal before, @second.mcp_servers.find(@second_server.id).attributes

        editable = @second.mcp_servers.find(@second_server.id)
        assert editable.save_workspace({ endpoint: "https://other.example.org/mcp" }, values: {}, removals: [ credential ])
        saved = @second.mcp_servers.find(@second_server.id)
        refute saved.auth_config.key?(credential)
        assert_equal({ "UNEDITED" => "keep" }, saved.env)
        assert_same remote_client, saved.client
        assert_equal "https://other.example.org/mcp", outgoing.last.fetch(:url)
        refute outgoing.last.fetch(:headers).key?(header)
        assert_equal public_headers, outgoing.last.fetch(:headers)
        assert_equal public_headers, @second.mcp_servers.find(@second_server.id).headers
      end
    end

    test "removing #{credential} preserves a header that does not match the saved credential" do
      custom_headers = { header => "custom-auth", "X-Custom" => "keep" }
      @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
        auth_config: { credential => "remote-secret" }, connection_config: { headers: custom_headers })

      assert @second_server.save_workspace({}, values: {}, removals: [ credential ])
      saved = @second.mcp_servers.find(@second_server.id)
      refute saved.auth_config.key?(credential)
      assert_equal custom_headers, saved.headers
    end

    { transition: false, persisted_stdio: true }.each do |stage, already_stdio|
      test "removing #{credential} at #{stage} clears its HTTP header copy before returning to HTTP" do
        previous = ENV["MCP_STDIO_ENABLED"]
        ENV["MCP_STDIO_ENABLED"] = "true"
        public_headers = { "X-Custom" => "keep" }
        @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp",
          auth_config: { credential => "remote-secret" }, connection_config: { headers: public_headers, env: { "UNEDITED" => "keep" } })
        outgoing = []
        remote_client = Struct.new(:tools).new([])
        replacement = ->(transport_type:, config:, **_) { outgoing << [ transport_type, config.deep_dup ]; remote_client }

        with_singleton_replacement(RubyLLM::MCP, :client, replacement) do
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

          assert saved.save_workspace({ transport_type: "streamable", endpoint: "https://other.example.org/mcp" }, values: {})
          assert_same remote_client, @second.mcp_servers.find(@second_server.id).client
          assert_equal [ :streamable, :streamable ], outgoing.map(&:first)
          assert_equal "https://other.example.org/mcp", outgoing.last.last.fetch(:url)
          assert_equal public_headers, outgoing.last.last.fetch(:headers)
          assert_equal({ "UNEDITED" => "keep" }, @second.mcp_servers.find(@second_server.id).env)
        end
      ensure
        ENV["MCP_STDIO_ENABLED"] = previous
      end
    end
  end

  test "local credential removal preserves registered connection configuration" do
    connection = { "headers" => { "X-API-Key" => "optional-secret" }, "env" => { "LOCAL" => "keep" } }
    @second_server.update!(metadata: { engine: "open_alex" }, auth_config: { api_key: "optional-secret" }, connection_config: connection)

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
    with_singleton_replacement(RubyLLM::MCP, :client, ->(**_) { flunk "stdio process construction attempted" }) do
      assert_nil @second_server.client
      refute @second_server.test_connection!
    end
    assert_equal before, @second_server.reload.attributes
  ensure
    ENV["MCP_STDIO_ENABLED"] = previous
  end
end
