module Website::Crawlable
  extend ActiveSupport::Concern

  class ConversionError < StandardError; end

  HEAD_FIELDS = %w[title meta-title meta-description meta-keywords].freeze

  def crawl_url!
    if url.blank?
      mark_indexing_failed!
      return
    end
    unless robots_allowed?
      mark_indexing_failed!
      return
    end

    html = fetch_html
    unless html
      mark_indexing_failed!
      return
    end

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
    filter_head_frontmatter(HtmlToMarkdown.convert(html, skip_images: true).content)
  rescue StandardError => error
    raise ConversionError, "html-to-markdown conversion failed: #{error.class}: #{error.message}"
  end

  def filter_head_frontmatter(content)
    return content unless content.start_with?("---\n")

    body_after_open = content[4..]
    close_index = body_after_open.index("\n---\n")
    return content unless close_index

    frontmatter = body_after_open[0...close_index]
    body = body_after_open[(close_index + 5)..]
    kept = frontmatter.each_line.select do |line|
      HEAD_FIELDS.any? { |field| line.start_with?("#{field}:") }
    end
    return body if kept.empty?

    "---\n#{kept.join.rstrip}\n---\n\n#{body}"
  end
end
