require "test_helper"

class SourceRowTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "row@example.com", password: "testpassword123")
    @account = Account.create!(name: "ROW Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account

    @text = @account.texts.create!(data: "alpha content")
    @qna  = @account.qnas.create!(question: "beta question", answer: "answer")
    @web  = @account.websites.create!(url: "https://example.com")
    @web.mark_indexing_failed!
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "all view merges every type" do
    rows = SourceRow.for_account(@account, type: "all")
    assert_equal 3, rows.size
    assert_equal %w[qna text website].sort, rows.map(&:source_type_key).sort
  end

  test "type filter returns only that type" do
    rows = SourceRow.for_account(@account, type: "text")
    assert_equal [ @text.id ], rows.map(&:id)
  end

  test "status filter returns only matching status" do
    rows = SourceRow.for_account(@account, type: "all", status: "failed")
    assert_equal [ @web.id ], rows.map(&:id)
  end

  test "query filters by search" do
    rows = SourceRow.for_account(@account, type: "all", query: "beta")
    assert_equal [ @qna.id ], rows.map(&:id)
  end

  test "rows carry a chunk count without N+1" do
    Chunk.define_method(:generate_embedding) { }
    @account.chunks.create!(chunkable: @text, content: "c1")
    @account.chunks.create!(chunkable: @text, content: "c2")

    row = SourceRow.for_account(@account, type: "text").first
    assert_equal 2, row.chunks_count
  ensure
    Chunk.remove_method(:generate_embedding) if Chunk.instance_methods(false).include?(:generate_embedding)
  end

  test "limit and offset paginate" do
    5.times { |i| @account.texts.create!(data: "extra #{i}") }
    page1 = SourceRow.for_account(@account, type: "text", limit: 3, offset: 0)
    page2 = SourceRow.for_account(@account, type: "text", limit: 3, offset: 3)
    assert_equal 3, page1.size
    assert_equal 3, page2.size
    assert_empty (page1.map(&:id) & page2.map(&:id))
  end

  test "total_for counts all matches ignoring pagination" do
    5.times { |i| @account.texts.create!(data: "extra #{i}") }
    assert_equal 6, SourceRow.total_for(@account, type: "text")
  end

  test "counts_for returns totals by type and status" do
    counts = SourceRow.counts_for(@account)
    assert_equal 3, counts[:total]
    assert_equal 1, counts[:by_type]["text"]
    assert_equal 1, counts[:by_type]["qna"]
    assert_equal 1, counts[:by_type]["website"]
    assert_equal 0, counts[:by_type]["document"]
    assert_equal 1, counts[:by_status]["failed"]
  end
end
