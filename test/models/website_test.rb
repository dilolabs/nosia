require "test_helper"

class WebsiteTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "wt@example.com", password: "testpassword123")
    @account = Account.create!(name: "WT Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @website = @account.websites.create!(url: "https://example.com/page")
    # Robots checking is covered in RobotsCheckableTest; keep these tests
    # focused on fetch/convert by allowing every URL.
    @website.define_singleton_method(:robots_allowed?) { true }
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

  test "crawl_url! keeps only title and key meta tags from the head" do
    html = <<~HTML
      <html><head>
        <title>Real Title</title>
        <meta name="title" content="Meta Title Name">
        <meta name="description" content="desc here">
        <meta name="keywords" content="kw1, kw2">
        <meta name="robots" content="noindex">
        <base href="https://example.com/">
      </head><body><h1>Body</h1><p>text</p></body></html>
    HTML
    stub_connection(status: 200, body: html)
    @website.define_singleton_method(:chunkify!) { nil }

    @website.crawl_url!

    data = @website.reload.data
    assert_includes data, "title: Real Title"
    assert_includes data, "meta-title: Meta Title Name"
    assert_includes data, "meta-description: desc here"
    assert_includes data, "meta-keywords: kw1, kw2"
    refute_includes data, "meta-robots"
    refute_includes data, "base:"
    assert_includes data, "# Body"
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
    original = HtmlToMarkdown.method(:convert)
    HtmlToMarkdown.define_singleton_method(:convert) { |*_args| raise "rust panic" }

    assert_raises(Website::Crawlable::ConversionError) { @website.crawl_url! }
  ensure
    HtmlToMarkdown.define_singleton_method(:convert, original) if original
  end

  test "crawl_url! skips images including inline SVGs in the converted markdown" do
    stub_connection(
      status: 200,
      body: "<h1>Title</h1><svg><circle/></svg><img src=\"https://x/y.svg\" alt=\"y\"/><p>Body</p>"
    )
    @website.define_singleton_method(:chunkify!) { nil }

    @website.crawl_url!

    assert_includes @website.data, "# Title"
    assert_includes @website.data, "Body"
    refute_includes @website.data, "data:image/svg+xml"
    refute_includes @website.data, "y.svg"
  end

  test "to_html renders the body and strips the head frontmatter" do
    @website.update!(data: "---\ntitle: Real Title\nmeta-description: desc\n---\n\n# Heading\n\nParagraph.")

    html = @website.to_html

    assert_includes html, "<h1"
    assert_includes html, "Heading"
    assert_includes html, "Paragraph"
    refute_includes html, "meta-description"
    refute_includes html, "Real Title"
  end

  test "to_html renders body markdown when there is no frontmatter" do
    @website.update!(data: "# Heading\n\nParagraph.")

    html = @website.to_html

    assert_includes html, "<h1"
    assert_includes html, "Paragraph"
  end

  test "to_html returns an empty string when data is blank" do
    @website.update!(data: nil)

    assert_equal "", @website.to_html
  end
end
