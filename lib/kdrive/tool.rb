module Kdrive
  class Tool
    INLINEABLE_TYPES = %w[text/plain text/markdown text/csv application/json].freeze
    INLINE_CAP_BYTES = 1.megabyte

    def self.search_files(query, auth:)
      build_client(auth).search(query)
    end

    def self.list_folder(folder_id, auth:)
      build_client(auth).list_folder(folder_id)
    end

    def self.get_file(file_id, auth:)
      client = build_client(auth)
      meta = client.file(file_id)
      { meta: meta, content: maybe_inline(client, meta) }
    end

    class << self
      private

      def build_client(auth)
        return Kdrive::ApiClient.new(auth) unless Kdrive.default_connection

        Kdrive::ApiClient.new(auth, connection: Kdrive.default_connection)
      end

      # `meta` is the unwrapped file hash from ApiClient#file (string-keyed).
      # kDrive reports content type as `content_type` (and sometimes `mime_type`).
      def maybe_inline(client, meta)
        type = meta["content_type"] || meta["mime_type"]
        size = meta["size"].to_i
        return nil unless type.to_s.start_with?("text/") || INLINEABLE_TYPES.include?(type.to_s)
        return nil if size > INLINE_CAP_BYTES

        download(client, meta["id"])
      rescue
        nil
      end

      def download(client, file_id)
        client.download(file_id)
      end
    end
  end
end
