require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

class McpWorkspaceDetailTest < ActionDispatch::IntegrationTest
  include McpWorkspaceFixtures

  setup { sign_in_picker_user }

  test "not-loaded counts are unknown and existing operations remain scoped" do
    get account_mcp_server_path(@second, @second_server)
    assert_response :success
    assert_select "[data-mcp-screen=detail] h1", text: @second_server.name
    assert_select "[data-tab-key=tools]", text: /—/
    assert_select "[data-mcp-capability=tools]", text: /#{Regexp.escape(I18n.t('nosia.mcp_workspace.not_loaded'))}/
    assert_select "form[action=?]", account_mcp_server_connection_path(@second, @second_server)
    assert_select "[data-mcp-danger] form[action=?]", account_mcp_server_path(@second, @second_server)
    assert_select "button", text: I18n.t("nosia.mcp.test"), count: 0
  end

  test "ready local schemas use the real SDK method and do not execute tools" do
    @second_server.update!(status: "ready")
    get account_mcp_server_path(@second, @second_server)
    assert_select "[data-tab-key=tools]", text: /1/
    assert_select "[data-mcp-capability=tools] details pre", text: /query/
    assert_select "[data-mcp-capability=prompts]", text: /#{Regexp.escape(I18n.t('nosia.mcp_workspace.no_items'))}/
    assert_select "form[action=?] input[name=_method][value=delete]", account_mcp_server_connection_path(@second, @second_server)
    assert_select "main script", count: 0
  end

  test "connection failure shows safe recovery while legacy JSON stays unchanged" do
    @second_server.update!(api_key: "bad")
    post account_mcp_server_connection_test_path(@second, @second_server)
    assert_response :see_other
    assert_redirected_to account_mcp_server_path(@second, @second_server)
    follow_redirect!
    assert_select "#connection-test-result[role=alert]"
    assert_select "a[href=?]", edit_account_mcp_server_path(@second, @second_server)
    refute_includes response.body, "credential-echo-bad"
    post test_connection_mcp_server_path(@first_server), as: :json
    assert_response :success
    assert_equal %w[latency message status success], response.parsed_body.keys.sort
  end

  test "real prompt argument objects render metadata without fetching messages" do
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp", status: "ready")
    prompt = RubyLLM::MCP::Prompt.new(Object.new, { "name" => "summary", "description" => "Read-only metadata",
      "arguments" => [ { "name" => "topic", "description" => "Research topic", "required" => true } ] })
    prompt.define_singleton_method(:fetch) { |*| flunk "prompt was executed" }
    resource = Struct.new(:uri, :description, :mime_type).new("mcp://example/record", "Resource metadata", "text/plain")
    client = Struct.new(:tools, :prompts, :resources).new([], [ prompt ], [ resource ])
    with_singleton_replacement(RubyLLM::MCP, :client, ->(**_) { client }) do
      get account_mcp_server_path(@second, @second_server)
      assert_response :success
      assert_select "[data-mcp-capability=prompts] dt", text: /topic.*Required/
      assert_select "[data-mcp-capability=resources] h3", text: "mcp://example/record"
    end
  end

  test "details never echo credential-bearing endpoint query or userinfo" do
    @first_server.update_columns(transport_type: "streamable", status: "disconnected",
      endpoint: "https://user:embedded-fixture@mcp.example.org/mcp?token=query-fixture")
    get mcp_server_path(@first_server)
    assert_response :success
    refute_includes response.body, "embedded-fixture"
    refute_includes response.body, "query-fixture"
    assert_includes response.body, "mcp.example.org/mcp"
  end
end
