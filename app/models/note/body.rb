# Canonical HTML and its plain-text and hashtag projections.
class Note::Body
  ALLOWED_TAGS = %w[p br h1 h2 h3 h4 ul ol li blockquote strong b em i u s del code pre a table tbody thead tfoot tr td th hr span].freeze
  ALLOWED_ATTRIBUTES = %w[href colspan rowspan start].freeze
  ATTACHMENT_NODES = "attachment, action-text-attachment, figure.attachment".freeze
  ATTACHMENTS = /<(?:attachment\b|action-text-attachment\b|figure\b)/i
  DROP_SUBTREES = "script, style, iframe, template, noscript, textarea, title, img, picture, video, audio, source, track, object, embed, canvas, svg, math, #{ATTACHMENT_NODES}".freeze
  BLOCK_TAGS = %w[p br h1 h2 h3 h4 ul ol li blockquote table tbody thead tfoot tr td th hr].freeze
  HASHTAG = /(?<![\p{L}\p{M}\p{N}_#])#([\p{L}\p{N}][\p{L}\p{M}\p{N}_-]*)/u
  LITERAL_URL = %r{(?<![\p{L}\p{N}_])(?:[a-z][a-z0-9+.-]{0,31}://|www\.)[^\s<>]+}i
  EMPTY_EDITOR_HTML = [ "<p></p>", "<p><br></p>" ].freeze

  # @return [String] Stored, safe-list HTML.
  attr_reader :html

  # @return [String] Visible text with block boundaries.
  attr_reader :text

  # @return [Array<String>] Unique, normalized hashtag keys.
  attr_reader :tag_keys

  # @param html [String] Submitted Lexxy HTML.
  # @raise [ArgumentError] If the input exceeds the HTML parser's limits.
  def initialize(html)
    fragment = Loofah.html5_fragment(without_attachments(html))
    fragment.css(DROP_SUBTREES).remove
    move_table_captions(fragment)
    Rails::HTML5::SafeListSanitizer.new.scrub(fragment, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)

    # Unwrapping unsupported elements can change the HTML5 tree when reopened.
    fragment = Loofah.html5_fragment(serialize(fragment))
    @html = serialize(fragment)
    @html = "" if EMPTY_EDITOR_HTML.include?(@html)

    @text = project_text(fragment)
    @tag_keys = project_text(fragment, omit_code_blocks: true).gsub(LITERAL_URL, " ").scan(HASHTAG).map do |(tag)|
      tag.unicode_normalize(:nfc).downcase(:fold).unicode_normalize(:nfc)
    end.uniq
  end

  private
    def without_attachments(html)
      return html unless html.match?(ATTACHMENTS)

      # HTML5 recovery can move block descendants out of an inline attachment.
      # Prune first; only the subsequent HTML5 safe-list pass produces stored HTML.
      fragment = Nokogiri::HTML4.fragment(html)
      fragment.css(ATTACHMENT_NODES).remove
      fragment.to_html
    end

    def move_table_captions(fragment)
      fragment.css("table > caption").each do |caption|
        paragraph = fragment.document.create_element("p")
        paragraph.add_child(caption.children)
        caption.parent.add_previous_sibling(paragraph)
        caption.remove
      end
    end

    def serialize(fragment)
      # HTML5 eats one leading newline after <pre> on each parse.
      fragment.to_html(preserve_newline: true).strip
    end

    def project_text(fragment, omit_code_blocks: false)
      lines = []
      buffer = +""
      collect_text(fragment, lines, buffer, omit_code_blocks:)
      flush_text(lines, buffer)
      lines.join("\n")
    end

    def collect_text(node, lines, buffer, omit_code_blocks:)
      if node.text?
        buffer << node.content
      elsif node.name == "pre"
        flush_text(lines, buffer)
        lines << preformatted_text(node) unless omit_code_blocks
      else
        block = BLOCK_TAGS.include?(node.name)
        flush_text(lines, buffer) if block
        node.children.each { |child| collect_text(child, lines, buffer, omit_code_blocks:) }
        flush_text(lines, buffer) if block
      end
    end

    def flush_text(lines, buffer)
      lines << buffer.squish if buffer.present?
      buffer.clear
    end

    def preformatted_text(node)
      if node.text?
        node.content
      elsif node.name == "br"
        "\n"
      else
        node.children.map { |child| preformatted_text(child) }.join
      end
    end
end
