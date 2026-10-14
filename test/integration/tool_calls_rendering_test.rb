require "test_helper"

class ToolCallsRenderingTest < ActiveSupport::TestCase
  test "persisted tool call hashes render each name and arguments without treating entries as AR records" do
    user = User.create!(email: "tool-render@example.com", password: "testpassword123")
    account = Account.create!(name: "Tool Rendering", owner: user)
    ActsAsTenant.current_tenant = account
    chat = account.chats.create!(user: user, model: "test-model", provider: :openai, assume_model_exists: true)
    caller = chat.messages.create!(role: :assistant, content: "")
    result = chat.messages.create!(role: :tool, content: "Found the answer")
    caller.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "search", arguments: { query: "<query>", limit: 2 }, result: result)
    caller.ruby_llm_tool_calls.create!(tool_call_id: "call_2", name: "lookup", arguments: { id: "abc" })
    caller.reload

    assert_kind_of RubyLLM::ToolCall, caller.tool_calls.fetch("call_1")
    html = ApplicationController.render(partial: "messages/tool_calls", locals: { message: caller })
    text = Nokogiri::HTML.fragment(html).text
    assert_includes text, "search("
    assert_includes text, 'query: "<query>"'
    assert_includes text, "limit: 2"
    assert_includes text, 'lookup(id: "abc")'
    assert_not_includes html, "<query>"
    assert_equal "Found the answer", caller.ruby_llm_tool_calls.find_by!(tool_call_id: "call_1").result.content
  ensure
    ActsAsTenant.current_tenant = nil
  end
end
