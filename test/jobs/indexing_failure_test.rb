require "test_helper"

class IndexingFailureTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "if@example.com", password: "testpassword123")
    @account = Account.create!(name: "IF Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "crawl_url! marks failed when robots disallows" do
    website = @account.websites.create!(url: "https://disallowed.example")
    website.define_singleton_method(:robots_allowed?) { false }

    website.crawl_url!

    assert website.failed?
  end

  test "the exhausted-retry contract sets failed (model-level)" do
    # The retry_on block's only job is to call mark_indexing_failed! — which is
    # independently verified here and in IndexableTest. The real exhausted-retry
    # path is exercised end-to-end in the Task 16 system test.
    website = @account.websites.create!(url: "https://example.com")
    website.mark_indexing_failed!

    assert website.reload.failed?
  end

  test "AddTextJob discards immediately when the record is gone (no 3x retry)" do
    # ActiveJob matches rescue handlers last-declared-first (LIFO), so
    # discard_on must be declared AFTER retry_on StandardError to win the
    # RecordNotFound match. Otherwise retry_on StandardError catches it first
    # and the job retries 3× on a deleted record before the exhaustion block's
    # find_by no-ops. Assert on the handler match order directly: deterministic
    # and side-effect-free.
    first_match = AddTextJob.rescue_handlers.reverse.find do |klass, _|
      klass = klass.safe_constantize if klass.is_a?(String)
      ActiveRecord::RecordNotFound <= klass
    end

    assert_equal "ActiveRecord::RecordNotFound", first_match&.first,
                 "expected RecordNotFound to be discarded (matched before StandardError retry)"
  end
end
