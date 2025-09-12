module Website::Crawlable
  extend ActiveSupport::Concern

  def crawl_urls!
    robots_txt = fetch_robots_txt
    return unless robots_txt.present?

    rules = parse_robots_txt(robots_txt, "Nosiabot/0.1")
    urls.each do |website_url|
      next unless allowed?(website_url, rules)
      website = Website.where(account: self.account, url: website_url).first_or_create
      CrawlWebsiteUrlJob.perform_later(website.id)
    end if urls.present? && urls.any?
  end

  def crawl_url!
    return unless ENV["DOCLING_SERVE_BASE_URL"].present?

    connection = Faraday.new(url: ENV["DOCLING_SERVE_BASE_URL"])

    request_body = {
      http_sources: [
        {
          url: self.url
        }
      ]
    }

    response = connection.post do |request|
      request.url "/v1alpha/convert/source"
      request.headers["Content-Type"] = "application/json"
      request.headers["Accept"] = "application/json"
      request.headers["User-Agent"] = "Nosiabot/0.1"
      request.body = request_body.to_json
    end

    return unless response.success?
    parsed_response = JSON.parse(response.body)
    self.data = parsed_response.dig("document", "md_content")
    self.save!
  end

  private

  def parse_robots_txt(robots_txt, user_agent)
    rules = { disallow: [], allow: [] }
    in_group = false
    current_agent_rules = []

    robots_txt.split("\n").each do |line|
      line.strip!
      next if line.empty? || line.start_with?("#")

      directive, value = line.split(/\s+/, 2)
      case directive.downcase
      when "user-agent"
        in_group = user_agent.match?(/\A#{Regexp.escape(value)}\z/i) || value == "*"
        current_agent_rules.clear if !in_group
      when "disallow"
        rules[:disallow] << Regexp.new("^" + Regexp.escape(value).gsub('\\*', ".*?")) if in_group
      when "allow"
        rules[:allow] << Regexp.new("^" + Regexp.escape(value).gsub('\\*', ".*?")) if in_group
      end
    end

    rules
  end

  def allowed?(url, rules)
    return true if rules[:disallow].empty?

    disallowed = rules[:disallow].any? { |rule| url.match(rule) }
    allowed = rules[:allow].any? { |rule| url.match(rule) }

    # If no allow rules are present, default to disallow if matched
    return false if disallowed && rules[:allow].empty?
    return true if allowed

    !disallowed
  end

  def extract_sitemap_urls_from_robots_txt(robots_txt)
    robots_txt.split("\n").map do |line|
      line.strip.match(/\ASitemap:\s*(.+)$/i)&.captures&.first
    end.compact
  end

  def extract_urls_from_sitemap(xml)
    doc = Nokogiri::XML(xml)
    namespace = { sitemap: "http://www.sitemaps.org/schemas/sitemap/0.9" }
    doc.xpath("//sitemap:urlset/sitemap:url/sitemap:loc", namespace).map(&:text).map(&:strip)
  end

  def fetch_robots_txt
    fetch_uri("/robots.txt")
  end

  def fetch_sitemap(uri)
    fetch_uri(uri)
  end

  def fetch_uri(uri)
    connection = Faraday.new(url:)
    response = connection.get(uri) do |request|
      request.headers["User-Agent"] = "Nosiabot/0.1"
    end
    if response.success?
      response.body
    else
      nil
    end
  end

  def urls
    robots_txt = fetch_robots_txt
    return unless robots_txt.present?

    sitemap_urls = extract_sitemap_urls_from_robots_txt(robots_txt)
    return unless sitemap_urls.any?

    urls = []

    sitemap_urls.each do |sitemap_url|
      sitemap = fetch_sitemap(sitemap_url)
      next unless sitemap
      urls << extract_urls_from_sitemap(sitemap)
    end

    urls.flatten.uniq
  end
end
