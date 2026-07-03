# test/lib/engines/registration_test.rb
require "test_helper"

class Engines::RegistrationTest < ActiveSupport::TestCase
  def build(overrides = {})
    defaults = {
      id: "open_alex", name: "OpenAlex", icon: "📚",
      description: "Scholarly search", required_config: [],
      tool_classes: [], health_check: ->(auth) { }
    }
    Engines::Registration.new(**defaults.merge(overrides))
  end

  test "to_catalog_entry emits the full catalog hash with source: :registry" do
    r = build(required_config: [ { name: :api_key, type: :secret, required: false } ],
              capabilities: [ "tools" ])
    entry = r.to_catalog_entry
    assert_equal "open_alex", entry[:id]
    assert_equal "OpenAlex", entry[:name]
    assert_equal "📚", entry[:icon]
    assert_equal "engines", entry[:category]
    assert_equal :registry, entry[:source]
    assert_equal [ "tools" ], entry[:capabilities]
    assert_equal [ { name: :api_key, type: :secret, required: false } ], entry[:requires_config]
  end

  test "capabilities defaults to an empty array" do
    assert_equal [], build.capabilities
  end
end
