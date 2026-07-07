class CrawlWebsiteUrlJob < ApplicationJob
  queue_as :background

  retry_on Faraday::TimeoutError,
           Faraday::ConnectionFailed,
           Faraday::ServerError,
           Website::Crawlable::ConversionError,
           wait: 30.seconds,
           attempts: 5

  discard_on ActiveRecord::RecordNotFound

  def perform(website_id)
    website = Website.find(website_id)
    website.crawl_url!
  end
end
