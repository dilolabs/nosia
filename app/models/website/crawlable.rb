module Website::Crawlable
  extend ActiveSupport::Concern

  class ConversionError < StandardError; end

  def crawl_url!
    return unless url.present?

    html = fetch_html
    return unless html

    self.data = convert_to_markdown(html)
    save!
    chunkify!
    self
  end

  private

  def fetch_html
    response = faraday_connection.get(self.url) do |request|
      request.headers["User-Agent"] = "Nosiabot/0.1"
    end

    if response.success?
      return response.body
    end

    if (500..599).cover?(response.status)
      raise Faraday::ServerError, "upstream #{response.status} for #{self.url}"
    end

    Rails.logger.warn("crawl_url! terminal status=#{response.status} url=#{self.url}")
    nil
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
    Rails.logger.warn("crawl_url! transient #{error.class} url=#{self.url}")
    raise
  end

  def faraday_connection
    Faraday.new do |builder|
      builder.options.timeout = 10
      builder.options.open_timeout = 5
    end
  end

  def convert_to_markdown(html)
    HtmlToMarkdown.convert(html).content
  rescue StandardError => error
    raise ConversionError, "html-to-markdown conversion failed: #{error.class}: #{error.message}"
  end
end
