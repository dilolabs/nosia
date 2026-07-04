require "test_helper"

class McpCatalogRegistryTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "cat@example.com", password: "testpassword123")
    @account = Account.create!(name: "Cat Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    # Preserve boot-time registrations; restore in teardown so later tests
    # (e.g. EnginesBootTest) still see the engines registered at boot.
    @engines = Engines::Registry.all
    Engines::Registry.clear
    Engines::Registry.register(Engines::Registration.new(
      id: "demo", name: "Demo", icon: "🧪", description: "demo engine",
      required_config: [ { name: "api_key", label: "Key", type: "secret", required: true } ],
      tool_classes: [], health_check: ->(auth) { }
    ))
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    Engines::Registry.clear
    @engines.each { |registration| Engines::Registry.register(registration) }
    # `McpCatalog.all`/`categories` memoize at the class level; clear so
    # registry changes between tests are picked up.
    McpCatalog.instance_variable_set(:@catalog, nil)
    McpCatalog.instance_variable_set(:@categories, nil)
  end

  test "all merges registry entries tagged source: :registry" do
    entry = McpCatalog.all.find { |s| s[:id] == "demo" }
    assert entry
    assert_equal :registry, entry[:source]
    assert_equal "engines", entry[:category]
  end

  test "find returns a registry entry" do
    assert_equal "demo", McpCatalog.find("demo")[:id]
  end

  test "activate_for_account creates a local McpServer with engine + auth" do
    server = McpCatalog.activate_for_account(@account, "demo", { "api_key" => "sekret" })
    assert server.persisted?
    assert_equal "local", server.transport_type
    assert_nil server.endpoint
    # metadata round-trips through Postgres JSONB as a string-keyed Hash,
    # so read back with string keys (not symbols).
    assert_equal "demo", server.metadata["engine"]
    assert_equal "demo", server.metadata["catalog_id"]
    assert_equal "sekret", server.auth_config["api_key"]
  end

  test "activation raises when a required config value is missing" do
    assert_raises(ActiveRecord::RecordInvalid) do
      McpCatalog.activate_for_account(@account, "demo", { "api_key" => "" })
    end
  end
end
