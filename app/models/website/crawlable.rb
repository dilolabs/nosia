module Website::Crawlable
  extend ActiveSupport::Concern

  class ConversionError < StandardError; end

  HEAD_FIELDS = %w[title meta-title meta-description meta-keywords].freeze
  MAX_PAGE_BYTES = 5.megabytes

  def crawl_url!
    if url.blank?
      mark_indexing_failed!
      return
    end

    McpOutbound.destination!(url, https_only: false)

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
  rescue McpOutbound::Blocked => error
    Rails.logger.warn("crawl_url! blocked website_id=#{id} reason=#{error.message}")
    mark_indexing_failed!
    nil
  end

  private

  def fetch_html
    response, body = fetch_website_resource(url, faraday_connection, max_bytes: MAX_PAGE_BYTES)

    if response.success?
      return body
    end

    if (500..599).cover?(response.status)
      raise Faraday::ServerError, "upstream status #{response.status}"
    end

    Rails.logger.warn("crawl_url! terminal status=#{response.status} website_id=#{id}")
    nil
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
    raise error.class, "website fetch failed", cause: nil
  end

  def faraday_connection
    Faraday.new do |builder|
      builder.options.timeout = 10
      builder.options.open_timeout = 5
      builder.adapter McpOutbound::Adapter
    end
  end

  def fetch_website_resource(url, connection, max_bytes:)
    body = +"".b
    response = McpOutbound.with(McpOutbound::Scope.new(https_only: false)) do
      connection.get(url) do |request|
        request.headers["User-Agent"] = Website::RobotsCheckable::USER_AGENT
        request.options.on_data = ->(chunk, received_bytes, _env) do
          raise McpOutbound::Blocked, "response too large" if received_bytes > max_bytes

          body << chunk
        end
      end
    end
    body = response.body.to_s if body.empty?
    raise McpOutbound::Blocked, "response too large" if body.bytesize > max_bytes

    [ response, body ]
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
