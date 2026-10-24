# Selects the account-local website and its crawl job for a retry.
class Sources::Websites::RetriesController < Sources::RetriesController
  private
    def retry_source
      source_account.websites.find(params[:website_id])
    end

    def retry_job
      CrawlWebsiteUrlJob
    end
end
