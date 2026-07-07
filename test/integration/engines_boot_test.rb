require "test_helper"

class EnginesBootTest < ActiveSupport::TestCase
  test "open_alex and kdrive are registered at boot" do
    assert Engines::Registry["open_alex"], "open_alex engine not registered"
    assert Engines::Registry["kdrive"], "kdrive engine not registered"
  end

  test "every registered tool class is translatable by the adapter" do
    Engines::Registry.all.each do |reg|
      reg.tool_classes.each do |tool_class|
        assert Engines::ToolAdapter.supported?(tool_class),
               "#{reg.id}/#{tool_class.tool_name} has an unsupported schema"
      end
    end
  end
end
