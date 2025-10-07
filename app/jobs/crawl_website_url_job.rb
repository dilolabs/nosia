class CrawlWebsiteUrlJob < ApplicationJob
  queue_as :background

  def perform(website_id)
    website = Website.find(website_id)
    website.crawl_url!
  end
end
