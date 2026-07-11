require "test_helper"
require "active_job/test_helper"

class Sources::RetryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email: "rt@example.com", password: "testpassword123")
    @account = Account.create!(name: "RT Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
    post login_url, params: { email: @user.email, password: "testpassword123" }
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  def teardown
    ActiveJob::Base.queue_adapter = @original_adapter
    ActsAsTenant.current_tenant = nil
  end

  test "retry resets a failed text to pending and re-enqueues indexing" do
    text = @account.texts.create!(data: "# Hi")
    text.mark_indexing_failed!

    assert_enqueued_with(job: AddTextJob) do
      post retry_sources_text_url(text)
    end

    assert text.reload.pending?
    assert_redirected_to sources_url(type: "text")
  end

  test "retry re-crawls a failed website" do
    web = @account.websites.create!(url: "https://example.com/x")
    web.mark_indexing_failed!

    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      post retry_sources_website_url(web)
    end
    assert web.reload.pending?
  end
end
