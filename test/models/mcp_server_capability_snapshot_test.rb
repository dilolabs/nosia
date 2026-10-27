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

  test "disconnected servers with nil metadata report not loaded" do
    @second_server.update!(metadata: nil)
    assert_nil @second_server.reload.metadata

    assert_equal [ :not_loaded ], @second_server.capability_snapshot.values.map(&:state).uniq
    assert_nil @second_server.metadata
  end

  test "ready remote servers with nil metadata keep independent discovery outcomes" do
    @second_server.update!(transport_type: "streamable", endpoint: "https://mcp.example.org/mcp", status: "ready", metadata: nil)
    assert_nil @second_server.reload.metadata
    client = Struct.new(:tools, :resources).new([], [])
    client.define_singleton_method(:prompts) { raise "private diagnostic" }
    @second_server.define_singleton_method(:client) { client }

    snapshot = @second_server.capability_snapshot

    assert_equal({ tools: :loaded, prompts: :unavailable, resources: :loaded }, snapshot.transform_values(&:state))
    snapshot.each_value { |result| assert_empty result.items }
    assert_nil @second_server.metadata
  end

  test "ready local servers with nil metadata report unavailable" do
    @second_server.update!(status: "ready", metadata: nil)
    assert_nil @second_server.reload.metadata

    snapshot = @second_server.capability_snapshot

    assert_equal [ :unavailable ], snapshot.values.map(&:state).uniq
    snapshot.each_value { |result| assert_empty result.items }
    assert_nil @second_server.metadata
  end

  test "local capabilities load without invoking a tool or health check" do
    @health_check = ->(_) { flunk "browsing must not run a connection test" }
    @second_server.update!(status: "ready")
    execution_tripwire = ->(**_) { raise Minitest::Assertion, "browsing must not execute a tool" }
    with_singleton_replacement(McpWorkspaceFixtures::EchoTool, :call, execution_tripwire) do
      snapshot = @second_server.capability_snapshot
      assert_equal :loaded, snapshot.fetch(:tools).state
      assert_equal [ "workspace_echo" ], snapshot.fetch(:tools).items.map(&:name)
      assert_equal :loaded, snapshot.fetch(:prompts).state
      assert_empty snapshot.fetch(:prompts).items
      assert @second_server.tools.first.parameters_schema
    end
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

  test "status changes invalidate the snapshot independently" do
    snapshot = @second_server.capability_snapshot

    @second_server.update!(status: "ready")
    refreshed = @second_server.capability_snapshot

    refute_same snapshot, refreshed
    assert_equal [ :loaded ], refreshed.values.map(&:state).uniq
    assert_equal [ "workspace_echo" ], refreshed.fetch(:tools).items.map(&:name)
  end

  test "transport changes invalidate the snapshot independently" do
    @second_server.update!(status: "ready", endpoint: "https://mcp.example.org/mcp")
    snapshot = @second_server.capability_snapshot
    client = Struct.new(:tools, :prompts, :resources).new([], [], [])
    @second_server.define_singleton_method(:client) { client }

    @second_server.update!(transport_type: "streamable")
    refreshed = @second_server.capability_snapshot

    refute_same snapshot, refreshed
    assert_equal [ :loaded ], refreshed.values.map(&:state).uniq
    assert_empty refreshed.fetch(:tools).items
  end

  test "engine changes invalidate the snapshot independently" do
    @second_server.update!(status: "ready")
    snapshot = @second_server.capability_snapshot

    @second_server.update!(metadata: @second_server.metadata.merge("engine" => "missing"))
    refreshed = @second_server.capability_snapshot

    refute_same snapshot, refreshed
    assert_equal [ :unavailable ], refreshed.values.map(&:state).uniq
    assert_empty refreshed.fetch(:tools).items
  end
end
