require "base64"

module Kdrive
  class Tool
    INLINEABLE_TYPES = %w[text/plain text/markdown text/csv application/json].freeze
    INLINE_CAP_BYTES = 1.megabyte
    # Base64 in a prompt is ~4/3 the byte size, so cap downloads to keep the
    # response from blowing the model's context. Callers should use `info` to
    # check size before downloading large files.
    DOWNLOAD_CAP_BYTES = 5.megabytes

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

    # Fetches metadata first so an oversized file is refused before downloading
    # its body. Returns `{ meta:, base64: }` on success or `{ error: }` on
    # failure (size cap, HTTP error, or raise).
    def self.download_file(file_id, auth:)
      client = build_client(auth)
      meta = client.file(file_id)
      size = meta["size"].to_i
      if size > DOWNLOAD_CAP_BYTES
        return { error: "file too large (#{size} bytes; cap is #{DOWNLOAD_CAP_BYTES} bytes)" }
      end

      { meta: meta, base64: Base64.strict_encode64(client.download(file_id)) }
    rescue => e
      { error: e.message }
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
