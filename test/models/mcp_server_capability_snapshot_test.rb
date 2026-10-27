require "test_helper"
require_relative "../support/mcp_workspace_fixtures"

# Verifies capability discovery outcomes without executing server content.
class McpServerCapabilitySnapshotTest < ActiveSupport::TestCase
  include McpWorkspaceFixtures

  test "not-ready and unknown engines are not reported as empty successful lists" do
    assert_equal [ :not_loaded ], @second_server.capability_snapshot.values.map(&:state).uniq
    @second_server.update!(status: "ready", metadata: { engine: "missing" })
    assert_equal [ :unavailable ], @second_server.capability_snapshot.values.map(&:state).uniq
  end

  test "local capabilities load without invoking a tool or health check" do
    @health_check = ->(_) { flunk "browsing must not run a connection test" }
    @second_server.update!(status: "ready")
    snapshot = @second_server.capability_snapshot
    assert_equal :loaded, snapshot.fetch(:tools).state
    assert_equal [ "workspace_echo" ], snapshot.fetch(:tools).items.map(&:name)
    assert_equal :loaded, snapshot.fetch(:prompts).state
    assert_empty snapshot.fetch(:prompts).items
    assert @second_server.tools.first.parameters_schema
  end

  test "remote discovery runs once per kind and keeps independent failures distinct" do
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp", status: "ready")
    calls = Hash.new(0)
    client = Object.new
    client.define_singleton_method(:tools) { calls[:tools] += 1; [] }
    client.define_singleton_method(:prompts) { calls[:prompts] += 1; raise "private diagnostic" }
    client.define_singleton_method(:resources) { calls[:resources] += 1; [] }
    @second_server.define_singleton_method(:client) { client }
    snapshot = @second_server.capability_snapshot
    assert_same snapshot, @second_server.capability_snapshot
    assert_equal :loaded, snapshot.fetch(:tools).state
    assert_empty snapshot.fetch(:tools).items
    assert_equal :unavailable, snapshot.fetch(:prompts).state
    assert_equal :loaded, snapshot.fetch(:resources).state
    assert_equal({ tools: 1, prompts: 1, resources: 1 }, calls)
    refute snapshot.fetch(:prompts).to_h.values.join.include?("private diagnostic")
  end
end
