require "test_helper"

class Website::RobotsCheckableTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "rc@example.com", password: "testpassword123")
    @account = Account.create!(name: "RC Account", owner: @user)
    ActsAsTenant.current_tenant = @account
    @website = @account.websites.create!(url: "https://example.com/page")
  end

  def stub_robots(status: 200, body: "")
    response = Struct.new(:status, :body).new(status, body)
    response.define_singleton_method(:success?) { status.between?(200, 299) }
    connection = Object.new
    connection.define_singleton_method(:get) { |*_args| response }
    @website.define_singleton_method(:robots_connection) { connection }
    response
  end

  test "robots_allowed? allows everything when robots.txt is empty" do
    stub_robots(body: "")
    @website.update!(url: "https://example.com/anything")

    assert @website.robots_allowed?
  end

  test "robots_allowed? disallows paths under a Disallow rule" do
    stub_robots(body: "User-agent: *\nDisallow: /private/\n")
    @website.update!(url: "https://example.com/private/secret")

    refute @website.robots_allowed?
  end

  test "robots_allowed? lets Allow override Disallow by longest match" do
    stub_robots(body: "User-agent: *\nDisallow: /\nAllow: /public/\n")
    @website.update!(url: "https://example.com/public/doc")

    assert @website.robots_allowed?

    @website.update!(url: "https://example.com/other")

    refute @website.robots_allowed?
  end

  test "robots_allowed? honors * wildcards in patterns" do
    stub_robots(body: "User-agent: *\nDisallow: /private*\n")
    @website.update!(url: "https://example.com/privatex")

    refute @website.robots_allowed?

    @website.update!(url: "https://example.com/public")

    assert @website.robots_allowed?
  end

  test "robots_allowed? honors $ end-of-path anchor" do
    stub_robots(body: "User-agent: *\nDisallow: /search$\n")
    @website.update!(url: "https://example.com/search")

    refute @website.robots_allowed?

    @website.update!(url: "https://example.com/search/results")

    assert @website.robots_allowed?
  end

  test "robots_allowed? uses the Nosiabot group over * when present" do
    stub_robots(body: "User-agent: *\nAllow: /\nUser-agent: Nosiabot\nDisallow: /\n")
    @website.update!(url: "https://example.com/anything")

    refute @website.robots_allowed?
  end

  test "robots_allowed? allows all when robots.txt returns 404" do
    stub_robots(status: 404, body: "")
    @website.update!(url: "https://example.com/anything")

    assert @website.robots_allowed?
  end

  test "robots_allowed? raises on 5xx so the crawl job can retry" do
    stub_robots(status: 503, body: "")
    @website.update!(url: "https://example.com/anything")

    assert_raises(Faraday::ServerError) { @website.robots_allowed? }
  end

  test "robots_allowed? re-raises network timeouts" do
    connection = Object.new
    connection.define_singleton_method(:get) { |*_args| raise Faraday::TimeoutError }
    @website.define_singleton_method(:robots_connection) { connection }
    @website.update!(url: "https://example.com/anything")

    assert_raises(Faraday::TimeoutError) { @website.robots_allowed? }
  end

  test "robots_allowed? caches parsed rules per host so it isn't refetched" do
    stub_robots(body: "User-agent: *\nDisallow: /private/\n")
    original_cache = Rails.method(:cache)
    memory_cache = ActiveSupport::Cache::MemoryStore.new
    Rails.define_singleton_method(:cache) { memory_cache }

    begin
      calls = 0
      @website.define_singleton_method(:robots_connection) do
        Object.new.tap do |connection|
          response = Struct.new(:status, :body).new(200, "User-agent: *\nDisallow: /private/\n")
          response.define_singleton_method(:success?) { true }
          connection.define_singleton_method(:get) { |*_args| calls += 1; response }
        end
      end

      @website.update!(url: "https://example.com/private/x")
      @website.robots_allowed?
      @website.robots_allowed?

      assert_equal 1, calls
    ensure
      Rails.define_singleton_method(:cache, original_cache)
    end
  end

  test "crawl_url! returns nil when robots disallows and never fetches the page" do
    stub_robots(body: "User-agent: *\nDisallow: /\n")
    @website.update!(url: "https://example.com/secret")
    fetched = false
    sentinel = Object.new
    sentinel.define_singleton_method(:get) { |*_args| fetched = true; raise "should not fetch page" }
    @website.define_singleton_method(:faraday_connection) { sentinel }

    assert_nil @website.crawl_url!
    refute fetched
  end

  test "crawl_url! proceeds when robots allows" do
    stub_robots(body: "User-agent: *\nAllow: /\n")
    @website.update!(url: "https://example.com/page")
    response = Struct.new(:status, :body).new(200, "<h1>Hi</h1>")
    response.define_singleton_method(:success?) { true }
    connection = Object.new
    connection.define_singleton_method(:get) { |*_args| response }
    @website.define_singleton_method(:faraday_connection) { connection }
    @website.define_singleton_method(:chunkify!) { nil }

    @website.crawl_url!

    assert_equal true, @website.reload.data.present?
  end
end
