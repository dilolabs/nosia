module DocumentFileStreaming
  extend ActiveSupport::Concern
  include ActiveStorage::Streaming

  private
    def stream_private_file(blob)
      response.headers["Cache-Control"] = "private, no-store"

      if (range = request.headers["Range"]).present?
        send_blob_byte_range_data(blob, range)
      else
        response.headers["Accept-Ranges"] = "bytes"
        response.headers["Content-Length"] = blob.byte_size.to_s
        send_blob_stream(blob)
      end
    end
end
