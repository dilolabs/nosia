module LocalizedViewAssertions
  TECHNICAL_TEXT = [ "Nosia", "NOSIA", "BETA", "AI", "PDF", "MCP", "LLM:", "Ruby:", "Ecologits", "compar:IA", "ISO 14044", "N/A", "kWh", "gCO2e", "gCO₂e", "kWh ·", "kWh · gCO₂e" ].freeze
  TECHNICAL_ATTRIBUTES = [ "https://your-mcp-server.com/mcp", "your-bearer-token", "your-api-key", "@modelcontextprotocol/server-filesystem\n/path/to/directory", "/path/to/directory" ].freeze

  def assert_localized_view_sources(paths)
    failures = paths.flat_map do |path|
      source = File.read(path).gsub(/<%.*?%>/m, "")
      fragment = Nokogiri::HTML.fragment(source)
      text = fragment.xpath(".//text()[not(ancestor::script) and not(ancestor::style)]").filter_map do |node|
        value = node.text.gsub(/\s+/, " ").strip
        "#{path}: #{value}" if value.match?(/[[:alpha:]]/) && !TECHNICAL_TEXT.include?(value)
      end
      attributes = fragment.css("*").flat_map do |node|
        %w[title alt placeholder aria-label].filter_map do |name|
          value = node[name].to_s.strip
          "#{path}: #{name}=#{value}" if value.match?(/[[:alpha:]]/) && !TECHNICAL_TEXT.include?(value) && !TECHNICAL_ATTRIBUTES.include?(value)
        end
      end
      text + attributes
    end
    assert_empty failures, failures.join("\n")
  end
end
