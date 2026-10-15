require "test_helper"

class CrawlWebsiteUrlJobTransactionTest < ActiveJob::TestCase
  # Exercise real commits, not savepoints inside transactional fixtures.
  self.use_transactional_tests = false
  self.fixture_paths = [ Rails.root.join("test/support/fixtures/chat_accounts") ]
  fixtures :users, :accounts

  setup do
    @account = accounts(:picker_second)
    @prior_tenant = ActsAsTenant.current_tenant
    @prior_adapter = ActiveJob::Base.queue_adapter
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  teardown do
    @account.websites.destroy_all
    ActsAsTenant.current_tenant = @prior_tenant
    ActiveJob::Base.queue_adapter = @prior_adapter
  end

  test "crawl publication waits until the website transaction commits" do
    website = nil
    assert_not Website.connection.transaction_open?

    assert_enqueued_with(job: CrawlWebsiteUrlJob, queue: "background") do
      Website.transaction do
        assert Website.connection.current_transaction.joinable?
        website = Website.find_or_create_by_url!(@account, "https://commit.example/page")

        assert_no_enqueued_jobs only: CrawlWebsiteUrlJob
      end
    end

    assert_not Website.connection.transaction_open?
    assert_enqueued_with(job: CrawlWebsiteUrlJob, args: [ website.id ], queue: "background")
    visible_to_worker = Thread.new do
      Website.connection_pool.with_connection { Website.exists?(website.id) }
    end.value
    assert visible_to_worker, "the committed website must be visible through another connection"
  end

  test "rolling back the website transaction cancels crawl publication" do
    website_id = nil
    assert_not Website.connection.transaction_open?

    assert_no_enqueued_jobs only: CrawlWebsiteUrlJob do
      Website.transaction do
        assert Website.connection.current_transaction.joinable?
        website_id = Website.find_or_create_by_url!(@account, "https://rollback.example/page").id
        raise ActiveRecord::Rollback
      end
    end

    assert_not Website.connection.transaction_open?
    assert_not Website.exists?(website_id)
  end

  test "crawl publication remains immediate outside a transaction" do
    assert_not Website.connection.transaction_open?

    website = Website.find_or_create_by_url!(@account, "https://immediate.example/page")

    assert_not Website.connection.transaction_open?
    assert_enqueued_with(job: CrawlWebsiteUrlJob, args: [ website.id ], queue: "background")
  end
end
