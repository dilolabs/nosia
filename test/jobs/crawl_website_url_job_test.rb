require "test_helper"

class CrawlWebsiteUrlJobTest < ActiveJob::TestCase
  test "perform finds the website and calls crawl_url!" do
    called = false
    fake = Object.new
    fake.define_singleton_method(:crawl_url!) { called = true; nil }

    original_find = Website.method(:find)
    Website.define_singleton_method(:find) { |*_args| fake }

    begin
      CrawlWebsiteUrlJob.perform_now(123)
    ensure
      Website.define_singleton_method(:find, original_find)
    end

    assert called, "crawl_url! was not called on the found website"
  end
end
