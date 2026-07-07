module Website::RobotsCheckable
  extend ActiveSupport::Concern

  USER_AGENT = "Nosiabot/0.1"
  ROBOTS_CACHE_TTL = 12.hours

  def robots_allowed?
    return true unless url.present?

    uri = URI.parse(url)
    return true if uri.host.blank?

    rules = robots_rules_for(uri)
    allowed = robots_path_allowed?(uri.request_uri, rules)

    unless allowed
      Rails.logger.warn("crawl_url! disallowed by robots.txt url=#{self.url}")
    end

    allowed
  rescue URI::InvalidURIError
    true
  end

  private

  def robots_rules_for(uri)
    Rails.cache.fetch(robots_cache_key(uri.host), expires_in: ROBOTS_CACHE_TTL) do
      fetch_robots_txt(uri)
    end
  end

  def fetch_robots_txt(uri)
    robots_uri = uri.dup
    robots_uri.path = "/robots.txt"
    robots_uri.query = nil

    response = robots_connection.get(robots_uri.to_s) do |request|
      request.headers["User-Agent"] = USER_AGENT
    end

    return parse_robots_txt(response.body) if response.success?

    return [] if (400..499).cover?(response.status)

    raise Faraday::ServerError, "upstream #{response.status} for #{robots_uri}"
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed
    raise
  end

  def robots_connection
    Faraday.new do |builder|
      builder.options.timeout = 10
      builder.options.open_timeout = 5
    end
  end

  def robots_cache_key(host)
    "website/robots_txt/#{host}"
  end

  def parse_robots_txt(body)
    groups = Hash.new { |hash, key| hash[key] = [] }
    current_agents = []
    in_rules = false

    body.to_s.each_line do |raw|
      line = raw.split("#", 2).first.to_s.strip
      next if line.empty?

      field, value = line.split(":", 2)
      next if field.nil?

      field = field.strip.downcase
      value = value.to_s.strip

      case field
      when "user-agent"
        if in_rules
          current_agents = []
          in_rules = false
        end
        current_agents << value.downcase
      when "allow", "disallow"
        in_rules = true
        allow = field == "allow"
        current_agents.each { |agent| groups[agent] << [ allow, value ] }
      end
    end

    select_group_rules(groups)
  end

  def select_group_rules(groups)
    product = USER_AGENT.split("/", 2).first.downcase
    matching = groups.keys.select { |agent| agent == "*" || product.start_with?(agent) }
    chosen = matching.max_by(&:length)
    groups[chosen] || []
  end

  def robots_path_allowed?(request_uri, rules)
    best = nil

    rules.each do |allow, pattern|
      next if pattern.empty?

      if robots_pattern_match?(pattern, request_uri)
        if best.nil? ||
           pattern.length > best[1].length ||
           (pattern.length == best[1].length && allow && !best[0])
          best = [ allow, pattern ]
        end
      end
    end

    best.nil? ? true : best[0]
  end

  def robots_pattern_match?(pattern, path)
    path.match?(robots_pattern_to_regex(pattern))
  end

  def robots_pattern_to_regex(pattern)
    parts = pattern.each_char.map do |char|
      next ".*" if char == "*"
      next "\\z" if char == "$"

      Regexp.escape(char)
    end

    Regexp.new("\\A" + parts.join)
  end
end
