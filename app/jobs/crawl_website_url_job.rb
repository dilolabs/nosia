class CrawlWebsiteUrlJob < ApplicationJob
  queue_as :background

  retry_on Faraday::TimeoutError,
           Faraday::ConnectionFailed,
           Faraday::ServerError,
           wait: 30.seconds,
           attempts: 5

  def perform(website_id)
    website = Website.find(website_id)
    website.crawl_url!
  end
end