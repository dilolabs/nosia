require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../support/chat_workspace_fixtures"

class ChatMessageRenderingTest < ActionDispatch::IntegrationTest
  include ChatWorkspaceFixtures
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper

  test "message entry point keeps one role wrapper and streaming content target" do
    [ workspace(:messages, :workspace_question), workspace(:messages, :workspace_answer) ].each do |message|
      html = ApplicationController.render(partial: "messages/message", locals: { message: message })
      fragment = Nokogiri::HTML.fragment(html)
      assert_select fragment, "##{dom_id(message, :messages)}", count: 1
      if message.assistant?
        assert_select fragment, "##{dom_id(message, :content)}", count: 1
        assert_select fragment, "h2", text: "Three findings"
        assert_select fragment, "details", minimum: 1
      else
        assert_includes fragment.text, "What are the key findings"
      end
    end
  end

  test "saved request and streamed render use the same message identities" do
    sign_in_picker_user
    get chat_url(@chat)
    assert_response :success
    assert_select "##{dom_id(@chat, :messages)}", count: 1
    assert_select "##{dom_id(workspace(:messages, :workspace_answer), :content)}", count: 1
    assert_select "turbo-frame[id='#{dom_id(@chat)}_message_form']", count: 1
  end

  test "actual update payload does not nest a second message wrapper" do
    message = workspace(:messages, :workspace_answer)
    current = Nokogiri::HTML.fragment(ApplicationController.render(partial: "messages/message", locals: { message: message }))
    streams = capture_turbo_stream_broadcasts([ @chat, :messages, :en ]) { message.broadcast_updated }
    update = streams.find { |stream| stream["action"] == "update" && stream["target"] == dom_id(message, :messages) }
    assert update
    current.at_css("##{dom_id(message, :messages)}").inner_html = update.inner_html
    assert_select current, "##{dom_id(message, :messages)}", count: 1
    assert_select current, "##{dom_id(message, :content)}", count: 1
  end
end
