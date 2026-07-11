require "test_helper"

class SourceableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "src@example.com", password: "testpassword123")
    @account = Account.create!(name: "SRC Account", owner: @user)
    @account.account_users.grant_to(@user)
    ActsAsTenant.current_tenant = @account
  end

  def teardown
    ActsAsTenant.current_tenant = nil
  end

  test "each type reports its label and key" do
    doc  = @account.documents.new
    text = @account.texts.new(data: "hello")
    qna  = @account.qnas.new(question: "Q?", answer: "A")
    web  = @account.websites.new(url: "https://example.com")

    assert_equal "Document", doc.source_type_label
    assert_equal "document", doc.source_type_key
    assert_equal "Text",     text.source_type_label
    assert_equal "Q&A",      qna.source_type_label
    assert_equal "Website",  web.source_type_label
  end

  test "display_title falls back sensibly when title is blank" do
    text = @account.texts.new(data: "The quick brown fox jumps over the lazy dog and keeps going well past forty two characters")
    qna  = @account.qnas.new(question: "What is the refund policy?", answer: "30 days")
    web  = @account.websites.new(url: "https://example.com/blog")

    assert_equal "The quick brown fox jumps over the lazy do", text.display_title # first 42 chars
    assert_equal "What is the refund policy?", qna.display_title
    assert_equal "https://example.com/blog", web.display_title # no markdown H1 -> url
  end

  test "search scope matches on the type's natural columns" do
    matching = @account.qnas.create!(question: "How do refunds work?", answer: "Within 30 days")
    other    = @account.qnas.create!(question: "What are your hours?",  answer: "9 to 5")

    results = @account.qnas.search("refund")

    assert_includes results, matching
    assert_not_includes results, other
  end

  test "search with blank query returns all" do
    @account.texts.create!(data: "alpha")
    @account.texts.create!(data: "beta")
    assert_equal 2, @account.texts.search(nil).count
    assert_equal 2, @account.texts.search("").count
  end
end
