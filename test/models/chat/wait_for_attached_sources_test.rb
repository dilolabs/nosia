require "test_helper"

class ChatWaitForAttachedSourcesTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "wg@example.com", password: "testpassword123")
    @account = Account.create!(name: "WG Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @chat = @account.chats.create!(user: @user, model: "test-model", provider: :openai, assume_model_exists: true)
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  def message_with(websites: [], documents: [])
    @chat.messages.create!(role: "user", content: "hi",
      attached_website_ids: websites, attached_document_ids: documents)
  end

  test "no-op when there are no attached sources" do
    message = message_with
    result = @chat.wait_for_attached_sources!(message, timeout: 1.second, step: 0.05)
    assert_equal [], result[:ready]
    assert_equal [], result[:failed]
    assert_equal [], result[:timed_out]
  end

  test "waits for a pending source to become indexed, then returns it ready" do
    w = @account.websites.create!(url: "https://w.example", index_status: :pending)
    message = message_with(websites: [w.id])
    Thread.new { sleep 0.1; w.reload.update!(index_status: :indexed, indexed_at: Time.current) }
    result = @chat.wait_for_attached_sources!(message, timeout: 5.seconds, step: 0.05)
    assert_includes result[:ready].map(&:id), w.id
    assert_equal [], result[:timed_out]
  end

  test "a failed source is excluded and reported as failed without waiting" do
    w = @account.websites.create!(url: "https://f.example", index_status: :failed)
    message = message_with(websites: [w.id])
    result = @chat.wait_for_attached_sources!(message, timeout: 1.second, step: 0.05)
    assert_includes result[:failed].map(&:id), w.id
    assert_equal [], result[:ready]
  end

  test "a source still pending at the timeout is reported as timed_out" do
    w = @account.websites.create!(url: "https://t.example", index_status: :pending)
    message = message_with(websites: [w.id])
    result = @chat.wait_for_attached_sources!(message, timeout: 0.2.seconds, step: 0.05)
    assert_includes result[:timed_out].map(&:id), w.id
  end
end
