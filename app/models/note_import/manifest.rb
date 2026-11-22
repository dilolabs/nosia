# A bounded, normalized plan of logical paths and their expected byte sizes.
class NoteImport::Manifest
  MAX_FILES = 500
  MAX_FOLDERS = 250
  MAX_DEPTH = 32
  MAX_FILE_BYTES = 2.megabytes
  MAX_TOTAL_BYTES = 32.megabytes
  MAX_COMPONENT_BYTES = 255
  MAX_PATH_BYTES = 1_024
  MAX_IGNORED_COUNT = 2_147_483_647

  attr_reader :root_name, :files, :ignored_counts

  # Normalizes one Markdown-relative path without consulting the filesystem.
  # @param path [String] Untrusted logical name.
  # @return [String] A relative NFC path, retaining the case of every component.
  # @raise [NoteImport::Invalid] If the path is invalid or too deep.
  def self.normalize_path(path)
    normalized = normalize_name(path)
    components = normalized&.split("/", -1)
    unless normalized && normalized.bytesize <= MAX_PATH_BYTES && components.present? &&
        components.all? { |component| valid_component?(component) } && /\.md\z/i.match?(components.last)
      raise NoteImport::Invalid.new(:invalid_path)
    end
    if components.size - 1 > MAX_DEPTH
      raise NoteImport::Invalid.new(:depth_limit_exceeded, path: normalized)
    end

    normalized
  end

  # @param name [String] Untrusted root folder name.
  # @return [String] A single NFC folder component.
  # @raise [NoteImport::Invalid] If the name cannot be used as a root.
  def self.normalize_root_name(name)
    normalized = normalize_name(name)
    unless normalized && !normalized.include?("/") && valid_component?(normalized)
      raise NoteImport::Invalid.new(:invalid_root_name)
    end
    normalized
  end

  # @param root_name [String] Single logical folder component.
  # @param files [Array<Hash>] Entries shaped as { path:, size: }, with integer byte sizes.
  # @param ignored_counts [Hash] Counts keyed by obsidian and other.
  # @raise [NoteImport::Invalid] If metadata is malformed or exceeds an import limit.
  def initialize(root_name:, files:, ignored_counts:)
    @root_name = self.class.normalize_root_name(root_name).freeze
    @files = normalize_files(files).freeze
    validate_tree
    @ignored_counts = normalize_counts(ignored_counts).freeze
  end

  class << self
    private
      def normalize_name(value)
        return unless value.is_a?(String)

        utf8 = value.b.force_encoding(Encoding::UTF_8)
        if utf8.valid_encoding? && !/[\\\p{Cc}]/.match?(utf8)
          utf8.unicode_normalize
        end
      end

      def valid_component?(component)
        component.present? && component.bytesize <= MAX_COMPONENT_BYTES &&
          !%w[. .. .obsidian].include?(component) && !/\A[A-Za-z]:/.match?(component)
      end
  end

  private
    def normalize_files(entries)
      unless entries.is_a?(Array) && entries.size.between?(1, MAX_FILES)
        raise NoteImport::Invalid.new(:invalid_file_count)
      end

      entries.each_with_object({}) do |entry, normalized|
        raise NoteImport::Invalid.new(:invalid_path) unless entry.is_a?(Hash)

        path = self.class.normalize_path(entry.fetch(:path, nil))
        raise NoteImport::Invalid.new(:duplicate_path, path:) if normalized.key?(path)

        size = entry.fetch(:size, nil)
        unless size.is_a?(Integer) && size.between?(0, MAX_FILE_BYTES)
          raise NoteImport::Invalid.new(:invalid_file_size, path:)
        end
        normalized[path] = size
      end
    end

    def validate_tree
      raise NoteImport::Invalid.new(:total_size_exceeded) if files.values.sum > MAX_TOTAL_BYTES

      folders = Set.new
      files.each_key do |path|
        components = path.split("/")
        components.pop
        until components.empty?
          folder = components.join("/")
          break unless folders.add?(folder)

          raise NoteImport::Invalid.new(:path_collision, path: folder) if files.key?(folder)
          raise NoteImport::Invalid.new(:folder_limit_exceeded) if folders.size >= MAX_FOLDERS

          components.pop
        end
      end
    end

    def normalize_counts(counts)
      unless counts.is_a?(Hash) && counts.size == 2
        raise NoteImport::Invalid.new(:invalid_ignored_counts)
      end

      %w[obsidian other].to_h do |key|
        value = counts.fetch(key) { counts.fetch(key.to_sym, nil) }
        unless value.is_a?(Integer) && value.between?(0, MAX_IGNORED_COUNT)
          raise NoteImport::Invalid.new(:invalid_ignored_counts)
        end
        [ key, value ]
      end
    end
end
