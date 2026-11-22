# frozen_string_literal: true

require "uri"

# Resolves logical Markdown destinations against one import manifest, never the filesystem.
class NoteImport::LinkTarget
  MARKDOWN_EXTENSION = /\.md\z/i
  INVALID_COMPONENT = /[\/\\\p{Cc}]/
  URI_SCHEME = /\A[a-z][a-z0-9+.-]*:/i
  MALFORMED_ESCAPE = /%(?![0-9a-f]{2})/i

  # @param paths [Enumerable<String>] Exact, manifest-normalized logical paths.
  def initialize(paths)
    @paths_by_stem = {}
    @paths_by_qualified_stem = {}

    paths.each do |path|
      stem = path.sub(MARKDOWN_EXTENSION, "")
      index(@paths_by_stem, stem.rpartition("/").last, path)
      index(@paths_by_qualified_stem, stem, path)
    end
  end

  # @param target [String] Literal wiki target (not a URL).
  # @return [String, nil] Exact manifest key, only if unambiguous.
  def resolve_wiki(target)
    return if target.match?(/[#^\p{Cc}]/)

    components = target.split("/", -1)
    return if components.empty? || components.any? { |part| !component?(part) || %w[. ..].include?(part) }
    return if components.last.sub(MARKDOWN_EXTENSION, "").empty?

    index = components.one? ? @paths_by_stem : @paths_by_qualified_stem
    index[target.unicode_normalize.sub(MARKDOWN_EXTENSION, "")]
  end

  # @param target [String] Parsed Markdown destination before renderer URL escaping.
  # @param from [String] Manifest path of the linking document.
  # @return [String, nil] Exact manifest key, only for unambiguous relative Markdown destinations.
  def resolve_markdown(target, from:)
    return if target.match?(URI_SCHEME) || target.match?(/[?#\\\p{Cc}]/) || target.match?(MALFORMED_ESCAPE)

    parts = target.split("/", -1).map { |part| URI::DEFAULT_PARSER.unescape(part) }
    return if parts.empty? || !parts.all? { |part| component?(part) } || !MARKDOWN_EXTENSION.match?(parts.last)

    path = from.split("/")[0...-1]
    parts.each do |part|
      case part
      when "."
        next
      when ".."
        return if path.empty?

        path.pop
      else
        path << part.unicode_normalize
      end
    end
    @paths_by_qualified_stem[path.join("/").sub(MARKDOWN_EXTENSION, "")]
  end

  private
    def index(map, stem, path)
      map[stem] = map.key?(stem) ? nil : path
    end

    def component?(part)
      !part.empty? && part.valid_encoding? && !part.match?(INVALID_COMPONENT)
    end
end
