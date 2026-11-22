# frozen_string_literal: true

require "commonmarker"
require "digest"
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
    document = Commonmarker.parse(source, options: OPTIONS)
    rendered_markdown = document.to_html(options: OPTIONS, plugins: PLUGINS)
    html = rendered_markdown
    if front_matter
      html = "<pre><code>#{ERB::Util.html_escape(front_matter)}</code></pre>\n#{html}"
    end
    check_size(html, path)

    fragment = parse_fragment(html, path)
    remove_media(fragment)
    wiki = WikiSource.new(source, rendered_markdown)
    links, warnings = prepare_links(fragment, document, wiki, path)
    html = fragment.to_html
    check_size(html, path)
    @remaining_examples -= warnings.fetch(:examples).size
    Prepared.new(path, html, links, warnings)
  end

  private
    def check_size(html, path)
      if html.bytesize > MAX_RENDERED_BYTES
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

    def prepare_links(fragment, document, wiki_source, path)
      anchors = fragment.css("a")
      markdown_anchors = anchors.reject { |anchor| anchor.key?("data-wikilink") }
      wiki_anchors = anchors.select { |anchor| anchor["data-wikilink"] == "true" }
      markdown = markdown_destinations(document, markdown_anchors)
      wiki = wiki_source.destinations(wiki_anchors)
      examples = []
      count = 0
      links = anchors.filter_map do |anchor|
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
    # openings; only tags on parser-generated wiki anchors can identify a target.
    class WikiSource
      OPENING = /\[\[[ \t]*+(?=(?:[^\[\]\\]|\\.){0,2002}\]\])/m
      TARGET = /(?:[^\[\]|\\]|\\[[:punct:]]|\\(?![[:punct:]]))*/
      TABLE_TARGET = /(?:[^\[\]|\\]|\\(?!\|)[[:punct:]]|\\(?![[:punct:]]))*/
      MARKER_PREFIX = "nosiawikiref"
      MAX_COMPONENT_BYTES = 1_000 # Comrak's wiki target/label limit.
      VERBATIM_RUN = /[a-zA-Z0-9_.~\/\-\u0080-\u{10ffff}]+/

      def initialize(source, html)
        @source = source
        @html = html
      end

      def destinations(anchors)
        return {} if anchors.empty?

        prefix = "#{MARKER_PREFIX}#{Digest::SHA256.hexdigest(@source)[0, 12]}z"
        return {} if @source.include?(prefix) || @html.include?(prefix)

        marker = /#{prefix}(\d+)z/
        shadow, replacements = mark_source(prefix)
        witnessed = Commonmarker.to_html(shadow, options: OPTIONS, plugins: PLUGINS)
        # Check the entire renderer output, not only link count/href. False
        # lexical matches in code or escaped text must not alter the parse.
        return {} unless same_rendering?(witnessed, marker, replacements)

        witnesses = Nokogiri::HTML5.fragment(witnessed).css('a[data-wikilink="true"]')
        return {} unless witnesses.size == anchors.size

        scanner = StringScanner.new(@source)
        anchors.zip(witnesses).to_h do |anchor, witness|
          if (match = witness["href"].match(marker))
            scanner.pos = match[1].to_i
            target = scanner.scan(witness.ancestors("td, th").empty? ? TARGET : TABLE_TARGET)
          end
          [ anchor, match && target ]
        end
      end

      private
        def mark_source(prefix)
          scanner = StringScanner.new(@source)
          output = +""
          replacements = {}
          while (through_opening = scanner.scan_until(OPENING))
            output << through_opening
            offset = scanner.pos - scanner.matched_size + 2
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

        def same_rendering?(witnessed, marker, replacements)
          original_offset = shadow_offset = 0
          witnessed.scan(marker) do |(id)|
            match = Regexp.last_match
            unchanged = witnessed.byteslice(shadow_offset...match.bytebegin(0))
            return false unless unchanged == @html.byteslice(original_offset, unchanged.bytesize)

            original_offset += unchanged.bytesize
            shadow_offset = match.byteend(0)
            if (raw = replacements[id.to_i])
              restored = if raw == @html.byteslice(original_offset, raw.bytesize)
                raw
              else
                URI::DEFAULT_PARSER.escape(raw.b, /[^\x00-\x7f]/n)
              end
              return false unless restored == @html.byteslice(original_offset, restored.bytesize)

              original_offset += restored.bytesize
            end
          end
          witnessed.byteslice(shadow_offset..) == @html.byteslice(original_offset..)
        end
    end
    private_constant :WikiSource
end
