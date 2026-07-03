require "test_helper"

class Engines::ToolAdapterTest < ActiveSupport::TestCase
  # A minimal MCP::Tool with a flat scalar param.
  class FlatTool < MCP::Tool
    tool_name "flat_demo"
    description "flat scalar tool"
    input_schema(properties: { query: { type: "string" } }, required: [ "query" ])
    def self.call(query:, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: "got #{query} key=#{server_context[:api_key]}" } ])
    end
  end

  # An MCP::Tool with a nested-object param (like OpenAlex's params: { per_page, page }).
  class NestedTool < MCP::Tool
    tool_name "nested_demo"
    description "nested object tool"
    input_schema(
      properties: {
        query: { type: "string" },
        params: {
          type: "object",
          properties: { per_page: { type: "integer" }, page: { type: "integer" } }
        }
      },
      required: [ "query" ]
    )
    def self.call(query:, params: {}, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: "ok" } ], structured_content: { query: query })
    end
  end

  # An MCP::Tool using an unsupported schema feature (oneOf) -> must be dropped.
  class UnsupportedTool < MCP::Tool
    tool_name "unsupported_demo"
    description "unsupported"
    input_schema(properties: { q: { oneOf: [ { type: "string" }, { type: "integer" } ] } })
    def self.call(q:, server_context:)
      MCP::Tool::Response.new([ { type: "text", text: "nope" } ])
    end
  end

  test "returns a RubyLLM::Tool instance named from the tool_name" do
    adapted = Engines::ToolAdapter.for(FlatTool, server_context: { api_key: "sekret" })
    assert_kind_of RubyLLM::Tool, adapted
    assert_equal "flat_demo", adapted.name
  end

  test "execute delegates to the MCP tool with server_context and returns a string" do
    adapted = Engines::ToolAdapter.for(FlatTool, server_context: { api_key: "sekret" })
    result = adapted.call({ "query" => "einstein" })
    assert_equal "got einstein key=sekret", result
  end

  test "nested-object schema is accepted (not dropped)" do
    adapted = Engines::ToolAdapter.for(NestedTool, server_context: { api_key: "k" })
    assert_kind_of RubyLLM::Tool, adapted
    assert_equal "nested_demo", adapted.name
  end

  test "unsupported schema returns nil (tool dropped)" do
    assert_nil Engines::ToolAdapter.for(UnsupportedTool, server_context: {})
  end

  test "supported? distinguishes translatable schemas" do
    assert Engines::ToolAdapter.supported?(FlatTool)
    assert Engines::ToolAdapter.supported?(NestedTool)
    assert_not Engines::ToolAdapter.supported?(UnsupportedTool)
  end
end
