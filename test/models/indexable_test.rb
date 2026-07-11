require "test_helper"

class IndexableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "ix@example.com", password: "testpassword123")
    @account = Account.create!(name: "IX Account", owner: @user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "new source defaults to pending index_status" do
    website = @account.websites.new(url: "https://example.com/x")
    assert website.pending?
  end

  test "mark_indexed! sets indexed and indexed_at" do
    text = @account.texts.create!(data: "# Hi")
    text.mark_indexed!
    assert text.indexed?
    assert_not_nil text.indexed_at
  end

  test "mark_indexing_failed! sets failed" do
    text = @account.texts.create!(data: "# Hi")
    text.mark_indexing_failed!
    assert text.failed?
  end

  test "chunkify! marks the source indexed" do
    # Stub the embedding call: chunk creation triggers a before_save that hits
    # the embedding endpoint, which is out of scope for Indexable. The real
    # chunkify! flow (including mark_indexed!) still runs.
    Chunk.define_method(:generate_embedding) { }

    text = @account.texts.new(data: "# Title\n\nSome body text here.")
    text.save!
    text.chunkify!
    assert text.indexed?
  ensure
    Chunk.remove_method(:generate_embedding) if Chunk.instance_methods(false).include?(:generate_embedding)
  end

  test "chunkify! marks the source failed when it produces no chunks" do
    Chunk.define_method(:generate_embedding) { }

    text = @account.texts.new(data: "   ")  # whitespace-only -> splitter yields zero chunks
    text.save!
    text.chunkify!
    assert text.failed?
  ensure
    Chunk.remove_method(:generate_embedding) if Chunk.instance_methods(false).include?(:generate_embedding)
  end

  test "mark_pending! resets status to pending and clears indexed_at" do
    text = @account.texts.create!(data: "# Hi")
    text.mark_indexed!
    assert text.indexed?

    text.mark_pending!

    assert text.pending?
    assert_nil text.indexed_at
  end
end
