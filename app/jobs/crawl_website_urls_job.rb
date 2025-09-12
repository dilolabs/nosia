class CrawlWebsiteUrlsJob < ApplicationJob
  queue_as :default

  def perform(website_id)
    website = Website.find(website_id)
    website.crawl_urls!
  end
end
