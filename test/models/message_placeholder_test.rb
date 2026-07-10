require "test_helper"
require "turbo/broadcastable/test_helper"

class MessagePlaceholderTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper
  include ActionView::RecordIdentifier

  def setup
    @user = User.create!(email: "ph@example.com", password: "testpassword123")
    @account = Account.create!(name: "PH Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  # A blank assistant message (ruby_llm creates content: '' before the first delta)
  # must broadcast a bubble containing the generating placeholder, not an empty bubble.
  test "a blank assistant message broadcasts a bubble containing the generating placeholder" do
    streams = capture_turbo_stream_broadcasts([ @chat, "messages" ]) do
      @chat.messages.create!(role: :assistant, content: "")
    end

    append = streams.find { |s| s["action"] == "append" && s["target"] == dom_id(@chat, :messages) }
    assert append, "expected an append of the assistant bubble to the messages container"

    html = append.inner_html
    assert_includes html, "Generating", "blank bubble should show the Generating placeholder"
    assert_includes html, "animate-spin", "placeholder should include the spinner"
  end
end
