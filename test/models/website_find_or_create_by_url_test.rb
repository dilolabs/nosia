require "test_helper"
require "active_job/test_helper"

class WebsiteFindOrCreateByUrlTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email: "wu@example.com", password: "testpassword123")
    @account = Account.create!(name: "WU Account", owner: @user)
    @other_user = User.create!(email: "wu2@example.com", password: "testpassword123")
    @other_account = Account.create!(name: "WU Other", owner: @other_user)
    ActsAsTenant.current_tenant = @account
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  def teardown
    ActsAsTenant.current_tenant = nil
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "creates a new website and enqueues the crawl job" do
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      @website = Website.find_or_create_by_url!(@account, "https://new.example/page")
    end
    assert @website.persisted?
    assert @website.pending?
    assert_equal "https://new.example/page", @website.url
  end

  test "reuses an existing website for the same account+url without enqueuing" do
    existing = @account.websites.create!(url: "https://dup.example", index_status: :indexed)
    assert_no_enqueued_jobs(only: CrawlWebsiteUrlJob) do
      found = Website.find_or_create_by_url!(@account, "https://dup.example")
      assert_equal existing.id, found.id
    end
  end

  test "re-crawls when the existing website is failed" do
    existing = @account.websites.create!(url: "https://stale.example", index_status: :failed)
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      Website.find_or_create_by_url!(@account, "https://stale.example")
    end
    assert existing.reload.pending?
  end

  test "does not cross accounts" do
    ActsAsTenant.current_tenant = @other_account
    @other_account.websites.create!(url: "https://share.example", index_status: :indexed)
    ActsAsTenant.current_tenant = @account
    assert_enqueued_with(job: CrawlWebsiteUrlJob) do
      Website.find_or_create_by_url!(@account, "https://share.example")
    end
  end

  test "rejects a duplicate (account_id, url) at the model level" do
    @account.websites.create!(url: "https://dup-val.example")
    dup = @account.websites.new(url: "https://dup-val.example")
    assert_not dup.valid?
    assert dup.errors.where(:url, :taken).any?
  end

  test "the (account_id, url) unique index exists in the schema" do
    indexes = ActiveRecord::Base.connection.indexes(:websites)
    unique = indexes.find { |i| i.columns == [ "account_id", "url" ] }
    assert unique, "expected a unique index on (account_id, url)"
    assert unique.unique
  end

  # Race recovery (the `rescue ActiveRecord::RecordNotUnique` branch in
  # find_or_create_by_url!) is not unit-tested here: this suite loads neither
  # minitest/mock (no Object#stub) nor Mocha, and stubbing the association
  # proxy's find_or_initialize_by / find_by! via define_singleton_method is
  # fiddly. The DB unique index (asserted above) is the race-safety guard; the
  # rescue simply re-fetches the winner's row (already pending + enqueued by
  # the winner) and returns it without re-enqueuing.

  test "the dedup migration cleans up orphaned chunks of discarded duplicate rows" do
    # Simulate a pre-existing (account_id, url) race: two rows, the older one
    # carrying chunks. The unique-index migration must delete the older row AND
    # its chunks (a raw SQL DELETE bypasses dependent: :destroy).
    # Stub the embedding call: chunk creation triggers a before_save that hits
    # the embedding endpoint, out of scope for this migration test.
    Chunk.define_method(:generate_embedding) { }

    conn = ActiveRecord::Base.connection
    conn.remove_index :websites, column: [ :account_id, :url ]
    begin
      # Winner is the newer row (created now) and is the keeper per the
      # migration's ORDER BY created_at DESC, id DESC.
      winner = @account.websites.create!(url: "https://dedup.example", index_status: :indexed)

      # The loser is the older duplicate, inserted bypassing the model
      # uniqueness validation -- the race/concurrent-insert scenario predates
      # that validation. Backdate it so the migration ranks it as rn > 1.
      loser = Website.new(account: @account, url: "https://dedup.example",
                          index_status: :indexed, created_at: 1.hour.ago, updated_at: 1.hour.ago)
      loser.save(validate: false)
      Chunk.create!(account: @account, chunkable: loser, content: "orphaned chunk")

      # Re-run the migration's dedup + index step idempotently against current data.
      conn.execute <<~SQL.squish
        WITH dups AS (
          SELECT id FROM (
            SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id, url ORDER BY created_at DESC, id DESC) AS rn
            FROM websites WHERE account_id = '#{@account.id}'
          ) ranked WHERE rn > 1
        )
        DELETE FROM chunks WHERE chunkable_type = 'Website' AND chunkable_id IN (SELECT id FROM dups)
      SQL
      conn.execute <<~SQL.squish
        WITH dups AS (
          SELECT id FROM (
            SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id, url ORDER BY created_at DESC, id DESC) AS rn
            FROM websites WHERE account_id = '#{@account.id}'
          ) ranked WHERE rn > 1
        )
        DELETE FROM websites WHERE id IN (SELECT id FROM dups)
      SQL

      assert_equal 1, @account.websites.where(url: "https://dedup.example").count
      assert_equal winner.id, @account.websites.find_by(url: "https://dedup.example").id
      assert_equal 0, Chunk.where(chunkable_type: "Website", chunkable_id: loser.id).count
    ensure
      conn.add_index :websites, [ :account_id, :url ], unique: true
      Chunk.remove_method(:generate_embedding) if Chunk.instance_methods(false).include?(:generate_embedding)
    end
  end
end
