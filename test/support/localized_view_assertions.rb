require "ripper"

module LocalizedViewAssertions
  TECHNICAL_TEXT = [ "Nosia", "NOSIA", "BETA", "AI", "PDF", "MCP", "LLM:", "Ruby:", "Ecologits", "compar:IA", "ISO 14044", "N/A", "kWh", "gCO2e", "gCO₂e", "kWh ·", "kWh · gCO₂e" ].freeze
  TECHNICAL_ATTRIBUTES = [ "https://your-mcp-server.com/mcp", "your-bearer-token", "your-api-key", "@modelcontextprotocol/server-filesystem\n/path/to/directory", "/path/to/directory" ].freeze
  HELPER_LABEL_ARGUMENTS = { "submit" => 0, "submit_tag" => 0, "button" => 0, "button_tag" => 0, "button_to" => 0, "link_to" => 0, "label" => 1, "label_tag" => 1 }.freeze
  HELPER_OPTION_NAMES = %w[title alt placeholder aria-label confirm data-confirm data-turbo-confirm].freeze
  OPTION_HELPERS = %w[image_tag image_button_tag inline_svg inline_svg_tag content_tag form_with form_for fields_for select collection_select grouped_collection_select time_zone_select date_select time_select datetime_select].freeze

  def assert_localized_view_sources(paths)
    failures = paths.flat_map do |path|
      source = File.read(path)
      fragment = Nokogiri::HTML.fragment(source.gsub(/<%.*?%>/m, ""))
      text = fragment.xpath(".//text()[not(ancestor::script) and not(ancestor::style)]").filter_map do |node|
        value = node.text.gsub(/\s+/, " ").strip
        "#{path}: #{value}" if value.match?(/[[:alpha:]]/) && !TECHNICAL_TEXT.include?(value)
      end
      attributes = fragment.css("*").flat_map do |node|
        names = %w[title alt placeholder aria-label]
        names += [ "value" ] if node.name == "input" && %w[submit button reset].include?(node["type"].to_s.downcase)
        names.filter_map do |name|
          value = node[name].to_s.strip
          "#{path}: #{name}=#{value}" if value.match?(/[[:alpha:]]/) && !TECHNICAL_TEXT.include?(value) && !TECHNICAL_ATTRIBUTES.include?(value)
        end
      end
      text + attributes + localized_helper_failures(source, path)
    end
    assert_empty failures, failures.join("\n")
  end

  private
    def localized_helper_failures(source, path)
      ruby = source.scan(/<%(.*?)%>/m).filter_map do |(tag)|
        tag = tag.delete_prefix("-")
        tag.sub(/\A==?/, "").delete_suffix("-") unless tag.start_with?("#")
      end.join("\n")
      # A view is a method body: wrapping permits layout yield without evaluating Ruby.
      tree = Ripper.sexp("def localized_view\n#{ruby}\nend")
      flunk "#{path}: cannot parse ERB Ruby for the copy audit" unless tree

      localized_helper_copy(tree).map { |copy| "#{path}: #{copy}" }
    end

    def localized_helper_copy(node, block: false)
      return [] unless node.is_a?(Array)

      if node[0] == :method_add_block
        localized_helper_copy(node[1], block: true) + localized_helper_copy(node[2])
      else
        name, arguments = case node[0]
        when :command then [ node[1][1], node[2] ]
        when :command_call then [ node[3][1], node[4] ]
        when :method_add_arg then [ node[1].last[1], node[2] ]
        end
        arguments = arguments[1] if arguments&.first == :arg_paren
        arguments = arguments&.first == :args_add_block ? arguments[1] : []
        label = arguments[HELPER_LABEL_ARGUMENTS[name]] if HELPER_LABEL_ARGUMENTS.key?(name) && !block
        label = arguments[1] if name == "content_for" && localized_option_key(arguments[0]) == "title"
        options = if %w[link_to button_to].include?(name)
          arguments.drop(block ? 1 : 2)
        elsif HELPER_LABEL_ARGUMENTS.key?(name) || OPTION_HELPERS.include?(name) || name.to_s.match?(/_(?:field|area)(?:_tag)?\z/)
          arguments
        else
          []
        end

        localized_literal_copy(label) + options.flat_map { |option| localized_option_copy(option) } +
          node.grep(Array).flat_map { |child| localized_helper_copy(child) }
      end
    end

    def localized_option_copy(node, prefix = nil)
      pairs = case node&.first
      when :bare_assoc_hash then node[1]
      when :hash then node.dig(1, 1)
      end
      Array(pairs).flat_map do |pair|
        next [] unless pair[0] == :assoc_new

        key = [ prefix, localized_option_key(pair[1]) ].compact.join("-").tr("_", "-")
        if HELPER_OPTION_NAMES.include?(key)
          localized_literal_copy(pair[2], attribute: true)
        elsif %w[aria data].include?(key)
          localized_option_copy(pair[2], key)
        else
          []
        end
      end
    end

    def localized_option_key(node)
      case node&.first
      when :@label then node[1].delete_suffix(":")
      when :symbol_literal then node.dig(1, 1, 1)
      when :string_literal, :dyna_symbol
        parts = node[1].drop(1)
        parts.map { |part| part[1] }.join if parts.all? { |part| part[0] == :@tstring_content }
      end
    end

    def localized_literal_copy(node, attribute: false)
      return [] unless node&.first == :string_literal

      node[1].drop(1).filter_map do |part|
        if part[0] == :@tstring_content
          value = part[1].strip
          value if value.match?(/[[:alpha:]]/) && !TECHNICAL_TEXT.include?(value) && !(attribute && TECHNICAL_ATTRIBUTES.include?(value))
        end
      end
    end
end
