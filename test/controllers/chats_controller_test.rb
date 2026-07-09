require "test_helper"
require "active_job/test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email: "cc@example.com", password: "testpassword123")
    @account = Account.create!(name: "CC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    post login_url, params: { email: @user.email, password: "testpassword123" }
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "create stamps attached source ids on the user message" do
    w = @account.websites.create!(url: "https://c.example", index_status: :indexed)
    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { prompt: "<p>hello</p>", model: "test-model", attached_website_ids: [ w.id ] } }
    end
    message = Chat.last.messages.where(role: :user).last
    assert_equal [ w.id.to_s ], message.attached_website_ids
    assert_equal "hello", message.content.strip # HTML converted to markdown
  end

  # A TYPED url (Lexxy emits lexxy:insert-link only on paste) still becomes a
  # crawled Website source: the server extracts it from the message content.
  test "create turns a typed url in the prompt into a crawled Website source" do
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      assert_enqueued_with(job: ChatResponseJob) do
        post chats_url, params: { chat: { prompt: "<p>https://typed.example/page</p>", model: "test-model" } }
      end
    end

    website = @account.websites.find_by!(url: "https://typed.example/page")
    assert website.pending?
    message = Chat.last.messages.where(role: :user).last
    assert_includes message.attached_website_ids, website.id.to_s
  end
end
