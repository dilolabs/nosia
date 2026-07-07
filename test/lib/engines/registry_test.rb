# test/lib/engines/registry_test.rb
require "test_helper"

class Engines::RegistryTest < ActiveSupport::TestCase
  def setup
    # Preserve the boot-time registrations across tests. The boot initializer's
    # `to_prepare` runs once per process, so clearing here would leave the
    # registry empty for any later test that relies on it (e.g. EnginesBootTest).
    @engines = Engines::Registry.all
    Engines::Registry.clear
  end

  def teardown
    Engines::Registry.clear
    @engines.each { |registration| Engines::Registry.register(registration) }
  end

  def registration(id = "open_alex")
    Engines::Registration.new(
      id: id, name: "OpenAlex", icon: "📚", description: "x",
      required_config: [], tool_classes: [], health_check: ->(auth) { }
    )
  end

  test "register, all, find and [] work" do
    Engines::Registry.register(registration)
    assert_equal 1, Engines::Registry.all.size
    assert_equal "open_alex", Engines::Registry.find("open_alex").id
    assert_equal "open_alex", Engines::Registry["open_alex"].id
  end

  test "registering a duplicate id raises" do
    Engines::Registry.register(registration)
    assert_raises(Engines::Registry::DuplicateIdError) do
      Engines::Registry.register(registration)
    end
  end

  test "find returns nil for an unknown id" do
    assert_nil Engines::Registry.find("nope")
  end
end
