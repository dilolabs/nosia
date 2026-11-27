# frozen_string_literal: true

require "commonmarker"
require "digest"
require "set"
require "strscan"

# Prepares notes and resolves links without a database, filesystem, or network.
class NoteImport::Markdown
  MAX_RENDERED_BYTES = 4.megabytes
  MAX_TOTAL_RENDERED_BYTES = 64.megabytes
  MAX_WARNING_EXAMPLES = 100
  MAX_WARNING_TARGET_BYTES = 512

  OPTIONS = {
    extension: { wikilinks_title_after_pipe: true, table: true, strikethrough: true, header_ids: nil }.freeze,
    render: { unsafe: false, escape: true }.freeze
  }.freeze
  POSITIONED_OPTIONS = OPTIONS.merge(render: OPTIONS[:render].merge(sourcepos: true).freeze).freeze
  SOURCE_POSITION = / data-sourcepos="\d+:\d+-\d+:\d+"/
  PLUGINS = { syntax_highlighter: nil }.freeze
  FRONT_MATTER = /\A(?:\uFEFF)?---[ \t]*\n.*?^---[ \t]*(?:\n|\z)/m
  EXTERNAL_SCHEMES = %w[http https ftp mailto tel sms].freeze

  # A compact, reusable HTML template. Only empty hrefs are placeholders; other
  # unresolved anchors were removed, and Commonmarker never emits input HTML.
  class Prepared
    # @return [String] Exact manifest path of this note.
    attr_reader :path

    # @return [String] Logical parent directory, or "" for a root-level note.
    attr_reader :directory

    # @return [String] Filename stem with the original case.
    attr_reader :title

    # @return [Hash] The full unresolved :count and bounded :examples for this note.
    attr_reader :warnings

    # @api private
    # @param path [String] Exact manifest path.
    # @param html [String] Template HTML with empty hrefs where Notes URLs belong.
    # @param links [Array<String>] Target paths in placeholder order.
    # @param warnings [Hash] Prepared unresolved-link report.
    def initialize(path, html, links, warnings)
      @path = path
      @directory, _, filename = path.rpartition("/")
      @directory.freeze
      @title = filename.sub(NoteImport::LinkTarget::MARKDOWN_EXTENSION, "")
      @title.freeze
      @html = html.freeze
      @links = links.freeze
      @warnings = warnings.freeze
    end

    # @return [Integer] Template size for the worker's running pre-publication budget.
    def prepared_bytesize
      @html.bytesize
    end

    # @param urls_by_path [Hash{String => String}] Stable, server-generated Notes hrefs.
    # @return [String] Final unsaved HTML; sum its bytesize for the publication budget.
    # @raise [KeyError] If a resolved path was not assigned a URL.
    # @raise [NoteImport::Invalid] If the final document exceeds the per-note limit.
    def render(urls_by_path)
      return @html if @links.empty?

      fragment = Nokogiri::HTML5.fragment(@html)
      fragment.css('a[href=""]').each_with_index do |anchor, index|
        anchor["href"] = urls_by_path.fetch(@links.fetch(index))
      end
      html = fragment.to_html
      if html.bytesize > MAX_RENDERED_BYTES
        raise NoteImport::Invalid.new(:rendered_file_size_exceeded, path:)
      end
      html
    end
  end

  # @param paths [Enumerable<String>] Manifest paths, already normalized.
  def initialize(paths)
    @targets = NoteImport::LinkTarget.new(paths)
    @remaining_examples = MAX_WARNING_EXAMPLES
  end

  # @param path [String] Exact manifest path of this document.
  # @param source [String] Staged UTF-8 Markdown.
  # @return [Prepared] A template with warnings { count:, examples: [{ path:, target: }] }.
  #   Use one converter per attempt so the examples are capped across the import.
  # @raise [NoteImport::Invalid] If the rendered HTML exceeds the size or parser limits.
  def prepare(path, source)
    path = path.dup.freeze
    source = source.gsub(/\r\n?/, "\n")
    if (front_matter = source[FRONT_MATTER])
      source = source.delete_prefix(front_matter)
    end
    embeds = Embeds.new(source)
    source = embeds.mask
    document = Commonmarker.parse(source, options: OPTIONS)
    positioned = source.include?("[[")
    rendered_markdown = document.to_html(options: positioned ? POSITIONED_OPTIONS : OPTIONS, plugins: PLUGINS)
    html = rendered_markdown
    if front_matter
      html = "<pre><code>#{ERB::Util.html_escape(front_matter)}</code></pre>\n#{html}"
    end
    check_size(html, path, positioned:)

    fragment = parse_fragment(html, path)
    wiki = positioned ? WikiSource.new(source, rendered_markdown).destinations(fragment) : {}
    remove_media(fragment)
    links, warnings = prepare_links(fragment, document, wiki, embeds.masked_anchors(fragment), path)
    embeds.restore(fragment)
    html = fragment.to_html
    check_size(html, path)
    @remaining_examples -= warnings.fetch(:examples).size
    Prepared.new(path, html, links, warnings)
  end

  private
    def check_size(html, path, positioned: false)
      bytesize = html.bytesize
      html.scan(SOURCE_POSITION) { |attribute| bytesize -= attribute.bytesize } if positioned
      if bytesize > MAX_RENDERED_BYTES
        raise NoteImport::Invalid.new(:rendered_file_size_exceeded, path:)
      end
    end

    def parse_fragment(html, path)
      Nokogiri::HTML5.fragment(html)
    rescue ArgumentError
      raise NoteImport::Invalid.new(:invalid_rendered_content, path:), cause: nil
    end

    def remove_media(fragment)
      fragment.css("img").each { |image| image.replace(fragment.document.create_text_node(image["alt"])) }
      fragment.css("input").each do |checkbox|
        checkbox.replace(fragment.document.create_text_node(checkbox.key?("checked") ? "[x] " : "[ ] "))
      end
    end

    def prepare_links(fragment, document, wiki, embedded_anchors, path)
      anchors = fragment.css("a")
      markdown_anchors = anchors.reject { |anchor| anchor.key?("data-wikilink") }
      markdown = markdown_destinations(document, markdown_anchors)
      examples = []
      count = 0
      links = anchors.filter_map do |anchor|
        if embedded_anchors.include?(anchor)
          unlink(anchor, markdown[anchor] || anchor.text)
          next
        end

        if anchor.key?("data-wikilink")
          raw = wiki[anchor]
          target = raw && @targets.resolve_wiki(raw)
          anchor.remove_attribute("data-wikilink")
        else
          next if external?(anchor["href"])

          raw = markdown[anchor]
          target = raw && @targets.resolve_markdown(raw, from: path)
        end

        if target
          anchor["href"] = ""
          target
        else
          raw ||= anchor["href"].to_s
          count += 1
          if examples.size < @remaining_examples
            examples << { path: path, target: raw.byteslice(0, MAX_WARNING_TARGET_BYTES).scrub("").freeze }.freeze
          end
          unlink(anchor, raw)
          nil
        end
      end
      [ links, { count: count, examples: examples.freeze } ]
    end

    def markdown_destinations(document, anchors)
      destinations = []
      stack = [ document ]
      until stack.empty?
        node = stack.pop
        destinations << node.url if node.type == :link
        unless node.type == :image
          child = node.last_child
          while child
            stack << child
            child = child.previous_sibling
          end
        end
      end
      anchors.size == destinations.size ? anchors.zip(destinations).to_h : {}
    end

    def external?(href)
      scheme = href&.slice(NoteImport::LinkTarget::URI_SCHEME)&.chop&.downcase
      return false unless EXTERNAL_SCHEMES.include?(scheme)

      uri = URI.parse(href)
      case scheme
      when "http", "https", "ftp" then uri.host.present?
      else uri.opaque.present?
      end
    rescue URI::Error
      false
    end

    def unlink(anchor, target)
      label = anchor.text
      anchor.children.each { |child| anchor.add_previous_sibling(child) }
      if label != target
        anchor.add_previous_sibling(anchor.document.create_text_node(" (#{target})"))
      end
      anchor.remove
    end

    # Comrak escapes WikiLink URLs and can lose physical source columns in
    # multiline inlines and tables. A second, detached parse tags lexical wiki
    # openings. Match stable block starts, then verify the generated anchors
    # within each block without trusting inline source columns.
    class WikiSource
      OPENING = /\[\[[ \t\n]*+(?=(?:[^\[\]\\]|\\.){0,2002}\]\])/m
      TARGET = /(?:[^\[\]|\\]|\\[[:punct:]]|\\(?![[:punct:]]))*/
      TABLE_TARGET = /(?:[^\[\]|\\]|\\(?!\|)[[:punct:]]|\\(?![[:punct:]]))*/
      MARKER_PREFIX = "nosiawikiref"
      MAX_COMPONENT_BYTES = 1_000 # Comrak's wiki target/label limit.
      VERBATIM_RUN = /[a-zA-Z0-9_.~\/\-\u0080-\u{10ffff}]+/
      # Only Commonmarker's generated wiki anchors have this markup. Raw HTML is escaped.
      ANCHOR = %r{<a href="([^"]*)" data-wikilink="true">.*?</a>}m
      WIKI_ANCHORS = 'a[data-wikilink="true"]'
      CONTAINERS = Set.new(%w[p li tr h1 h2 h3 h4 h5 h6]).freeze
      LIST_ITEM_BLOCKS = %w[blockquote div h1 h2 h3 h4 h5 h6 hr ol p pre table ul].freeze

      def initialize(source, html)
        @source = source
        @html = html
      end

      def destinations(fragment)
        original_blocks = take_blocks(fragment)
        return {} if original_blocks.empty?

        prefix = "#{MARKER_PREFIX}#{Digest::SHA256.hexdigest(@source)[0, 12]}z"
        return {} if @source.include?(prefix) || @html.include?(prefix)

        marker = /#{prefix}(\d+)z/
        shadow, replacements = mark_source(prefix)
        witnessed = Commonmarker.to_html(shadow, options: POSITIONED_OPTIONS, plugins: PLUGINS)
        shadow_blocks = take_blocks(Nokogiri::HTML5.fragment(witnessed))

        scanner = StringScanner.new(@source)
        original_blocks.each_with_object({}) do |(position, original_block), destinations|
          next unless original_block && (shadow_block = shadow_blocks[position])

          container, nodes = original_block
          original_html = inline_html(container)
          originals = wiki_spans(original_html)
          next unless originals.size == nodes.size

          shadow_html = inline_html(shadow_block.first)
          witnesses = wiki_spans(shadow_html)
          verified_pairs(original_html, originals, shadow_html, witnesses, marker, replacements).each do |index, witness|
            if (match = witness[1].match(marker))
              anchor = nodes.fetch(index)
              scanner.pos = match[1].to_i
              destinations[anchor] = scanner.scan(container.name == "tr" ? TABLE_TARGET : TARGET)
            end
          end
        end
      rescue ArgumentError
        # A shadow parse hitting the HTML parser's bounds proves no bindings.
        {}
      end

      private
        def take_blocks(fragment)
          groups = fragment.css(WIKI_ANCHORS).group_by { |anchor| nearest_container(anchor) }
          groups.each_with_object({}) do |(node, matches), found|
            next unless node && (position = node["data-sourcepos"])

            key = [ node.name, position.partition("-").first ]
            found[key] = found.key?(key) ? nil : [ node, matches ]
          end.tap do
            fragment.css("[data-sourcepos]").each { |node| node.remove_attribute("data-sourcepos") }
          end
        end

        def nearest_container(anchor)
          node = anchor.parent
          node = node.parent while node && !CONTAINERS.include?(node.name)
          node
        end

        def inline_html(container)
          if container.name == "li"
            # Tight items have no paragraph wrapper. Nested blocks have their
            # own positions; don't include them in the item or verify twice.
            container.children.reject { |child| LIST_ITEM_BLOCKS.include?(child.name) }.map(&:to_html).join
          else
            container.inner_html
          end
        end

        def wiki_spans(html)
          spans = []
          html.scan(ANCHOR) { spans << Regexp.last_match }
          spans
        end

        def verified_pairs(original_html, originals, html, witnesses, marker, replacements)
          # Match each anchor with its exact surrounding renderer output. If
          # marking changes a parse, keep the proven prefix and suffix without
          # pairing anything across the changed region.
          pairs = {}
          left = right = 0
          size = [ originals.size, witnesses.size ].min
          size.times do |index|
            original, witness = originals[index], witnesses[index]
            break unless same_rendering?(original_html.byteslice(left...original.byteend(0)),
              html.byteslice(right...witness.byteend(0)), marker, replacements)

            pairs[index] = witness
            left, right = original.byteend(0), witness.byteend(0)
          end

          left, right = original_html.bytesize, html.bytesize
          (size - pairs.size).times do |distance|
            index = originals.size - distance - 1
            original, witness = originals[index], witnesses[-distance - 1]
            break unless same_rendering?(original_html.byteslice(original.bytebegin(0)...left),
              html.byteslice(witness.bytebegin(0)...right), marker, replacements)

            pairs[index] = witness
            left, right = original.bytebegin(0), witness.bytebegin(0)
          end
          pairs
        end

        def mark_source(prefix)
          scanner = StringScanner.new(@source)
          output = +""
          replacements = {}
          while (through_opening = scanner.scan_until(OPENING))
            output << through_opening
            opening = scanner.matched
            # A token on a continuation line must not hide a block marker
            # such as `>`. Plain letter-led text can still witness the raw
            # target (including its newline), which remains unresolvable.
            next if opening.include?("\n") && !scanner.match?(/\p{L}/)

            offset = scanner.pos - opening.bytesize + 2
            token = "#{prefix}#{offset}z"
            target = scanner.check(TARGET)
            if scanner.pos - offset + target.bytesize + token.bytesize <= MAX_COMPONENT_BYTES
              output << token
            elsif target.bytesize <= MAX_COMPONENT_BYTES &&
                (run = target.enum_for(:scan, VERBATIM_RUN).find { |part| part.bytesize >= token.bytesize })
              # Substitute a run instead of lengthening a target near Comrak's limit.
              skip = target.byteindex(run)
              output << scanner.peek(skip) << token
              scanner.pos += skip + run.bytesize
              replacements[offset] = run
            end
          end
          [ output << scanner.rest, replacements ]
        end

        def same_rendering?(original, witnessed, marker, replacements)
          original_offset = shadow_offset = 0
          witnessed.scan(marker) do |(id)|
            match = Regexp.last_match
            unchanged = witnessed.byteslice(shadow_offset...match.bytebegin(0))
            return false unless unchanged == original.byteslice(original_offset, unchanged.bytesize)

            original_offset += unchanged.bytesize
            shadow_offset = match.byteend(0)
            if (raw = replacements[id.to_i])
              restored = if raw == original.byteslice(original_offset, raw.bytesize)
                raw
              else
                URI::DEFAULT_PARSER.escape(raw.b, /[^\x00-\x7f]/n)
              end
              return false unless restored == original.byteslice(original_offset, restored.bytesize)

              original_offset += restored.bytesize
            end
          end
          witnessed.byteslice(shadow_offset..) == original.byteslice(original_offset..)
        end
    end
    private_constant :WikiSource

    # Commonmarker has no embed node. Probe the candidate openings in one AST
    # to distinguish inline text from code, HTML, and link destinations. Only
    # mask those inline spans; restore them as literal DOM text after linking.
    class Embeds
      TOKENS = /\\[[:punct:]]|!\[\[|[\[\]\n]/

      def initialize(source)
        @source = source
        @prefix = "nosiaembed#{Digest::SHA256.hexdigest(source)[0, 12]}z"
        @marker = /#{@prefix}(\d+)z/
        @literal_marker = /!#{@marker};/
        @masked = {}
      end

      def mask
        return @source unless @source.include?("![[")

        spans = candidate_spans
        return @source if spans.empty?

        actual = inline_openings(replace_spans(spans, probe: true))
        replace_spans(spans.select { |start, _| actual.include?(start) }, probe: false)
      end

      def masked_anchors(fragment)
        return Set.new if @masked.empty?

        fragment.css("a").select do |anchor|
          anchor.text.to_enum(:scan, @literal_marker).any? { @masked.key?(Regexp.last_match[0]) }
        end.to_set
      end

      def restore(fragment)
        unless @masked.empty?
          fragment.xpath(".//text()").each do |node|
            if node.content.match?(@literal_marker)
              node.content = node.content.gsub(@literal_marker) { |token| @masked.fetch(token, token) }
            end
          end
        end
      end

      private
        def candidate_spans
          scanner = StringScanner.new(@source)
          brackets = []
          spans = []
          while scanner.scan_until(TOKENS)
            case scanner.matched
            # Obsidian embeds are inline: don't use a bracket on another
            # line to claim unrelated Markdown belongs to the caption.
            when "\n"
              brackets.clear
            when "![[" then brackets.push(scanner.pos - 3, nil)
            when "[" then brackets.push(nil)
            when "]"
              if (start = brackets.pop) && @source.getbyte(scanner.pos - 2) == "]".ord
                spans << [ start, scanner.pos ]
              end
            end
          end
          spans.sort_by(&:first)
        end

        def replace_spans(spans, probe:)
          source = +""
          offset = 0
          spans.each do |start, finish|
            next if start < offset

            token = "#{@prefix}#{start}z"
            if probe
              source << @source.byteslice(offset..start) << token
              offset = start + 1
            else
              # Keep punctuation on both sides. Literal square brackets here
              # could turn the placeholder back into Markdown link syntax.
              token = "!#{token};"
              source << @source.byteslice(offset...start) << token
              @masked[token] = @source.byteslice(start...finish)
              offset = finish
            end
          end
          source << @source.byteslice(offset..)
        end

        def inline_openings(probe)
          document = Commonmarker.parse(probe, options: OPTIONS)
          openings = Set.new
          stack = [ document ]
          until stack.empty?
            node = stack.pop
            if node.type == :text
              node.string_content.scan(/!#{@marker}/) { |(offset)| openings.add(offset.to_i) }
            end
            # A token in a URL is not an embed, even if the URL is also the
            # displayed label (as in an automatic link).
            unless node.type == :link && node.url.match?(@marker)
              node.each { |child| stack << child }
            end
          end
          openings
        end
    end
    private_constant :Embeds
end
