require "test_helper"

class WebsiteTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "wt@example.com", password: "testpassword123")
    @account = Account.create!(name: "WT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @website = @account.websites.create!(url: "https://example.com/page")
  end

  def stub_connection(status:, body: "")
    response = Struct.new(:status, :body).new(status, body)
    response.define_singleton_method(:success?) { status.between?(200, 299) }
    connection = Object.new
    yield(connection) if block_given?
    connection.define_singleton_method(:get) { |*_args| response }
    @website.define_singleton_method(:faraday_connection) { connection }
    response
  end

  test "crawl_url! converts and persists a fetched page, then chunkifies" do
    stub_connection(status: 200, body: "<h1>Title</h1><p>Body text</p>")
    chunkified = []
    @website.define_singleton_method(:chunkify!) { chunkified << true; nil }

    @website.crawl_url!

    assert_equal true, @website.reload.data.present?
    assert_includes @website.data, "# Title"
    assert_includes @website.data, "Body text"
    assert_equal [ true ], chunkified
  end

  test "crawl_url! returns nil on terminal 4xx and creates no chunks" do
    stub_connection(status: 404, body: "")

    assert_nil @website.crawl_url!
    assert_nil @website.reload.data
    assert_equal 0, @website.chunks.count
  end

  test "crawl_url! raises on 5xx so the job can retry" do
    stub_connection(status: 503, body: "")

    assert_raises(Faraday::ServerError) { @website.crawl_url! }
    assert_nil @website.reload.data
  end

  test "crawl_url! re-raises network timeouts" do
    connection = Object.new
    connection.define_singleton_method(:get) { |*_args| raise Faraday::TimeoutError }
    @website.define_singleton_method(:faraday_connection) { connection }

    assert_raises(Faraday::TimeoutError) { @website.crawl_url! }
  end

  test "crawl_url! returns nil when url is blank and never fetches" do
    @website.update!(url: nil)
    sentinel = Object.new
    sentinel.define_singleton_method(:get) { |*_args| raise "should not be called" }
    @website.define_singleton_method(:faraday_connection) { sentinel }

    assert_nil @website.crawl_url!
  end

  test "crawl_url! wraps conversion failures in a retried ConversionError" do
    stub_connection(status: 200, body: "<html></html>")
    @website.define_singleton_method(:chunkify!) { nil }
    HtmlToMarkdown.define_singleton_method(:convert) { |*_args| raise "rust panic" }

    assert_raises(Website::Crawlable::ConversionError) { @website.crawl_url! }
  ensure
    HtmlToMarkdown.singleton_class.send(:remove_method, :convert)
  end
end
