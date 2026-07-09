class Website < ApplicationRecord
  include Chunkable
  include Crawlable
  include Indexable
  include RobotsCheckable
  include HtmlToMarkdownFormattable

  html_to_markdown_attribute :data

  belongs_to :account

  validates :url, presence: true, uniqueness: { scope: :account_id }

  def self.find_or_create_by_url!(account, url)
    website = account.websites.find_or_initialize_by(url: url)

    if website.new_record?
      begin
        website.save!
        CrawlWebsiteUrlJob.perform_later(website.id)
      rescue ActiveRecord::RecordNotUnique
        # A concurrent paste won the race; reuse its row (already enqueued).
        website = account.websites.find_by!(url: url)
      end
    elsif website.failed?
      # Re-crawl a known failure so the user gets another shot without pasting
      # a brand-new row. Once transitioned to pending, a concurrent paste sees
      # pending (not failed) and skips, so only one crawl is enqueued. update!
      # (not update_columns) is safe here: a failed row reached via this method
      # always has a non-blank url -- it was created through the now-validated
      # path, and users never paste a blank url -- so the presence validation
      # can't trip.
      website.update!(index_status: :pending, indexed_at: nil)
      CrawlWebsiteUrlJob.perform_later(website.id)
    end

    website
  end

  def context
    data
  end

  def title
    return unless data.present?

    document = Commonmarker.parse(data)

    document.walk do |node|
      if node.type == :heading && node.header_level == 1
        return node.first_child.string_content
      end
    end

    nil
  end

  def to_html
    Commonmarker.to_html(page_body)
  end

  private

  def page_body
    return "" if data.blank?
    return data unless data.start_with?("---\n")

    rest = data[4..]
    close_index = rest.index("\n---\n")
    close_index ? rest[(close_index + 5)..] : data
  end
end
