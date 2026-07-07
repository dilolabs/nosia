require "faraday"

module Kdrive
  class ApiClient
    # No global version prefix — kDrive versions each path (/2 for file metadata +
    # download, /3 for search/list). See "kDrive API findings (post-spike)" in the spec.
    BASE_URL = "https://api.infomaniak.com"
    # kDrive's /download endpoint responds 302 to a pre-signed storage URL on a
    # different host. Faraday does not follow redirects by default, so `download`
    # follows the chain itself (see `follow_download_redirect`).
    REDIRECT_STATUSES = [ 301, 302, 303, 307, 308 ].freeze
    MAX_REDIRECTS = 5

    def initialize(auth, connection: nil)
      @token = auth[:token] || auth["token"]
      @drive_id = auth[:drive_id] || auth["drive_id"]
      @connection = connection || build_default_connection
    end

    def search(query, limit: 20)
      get("/3/drive/#{@drive_id}/files/search", query: query, limit: limit, with_path: true)
    end

    def list_folder(folder_id = 1, limit: 50)
      get("/3/drive/#{@drive_id}/files/#{folder_id}/files", limit: limit)
    end

    def file(file_id)
      get("/2/drive/#{@drive_id}/files/#{file_id}")
    end

    # Raw bytes for the file. kDrive responds 302 to a pre-signed storage URL;
    # the redirect chain is followed on the same connection but WITHOUT the
    # Bearer token (the storage URL is on a different host and is pre-signed, so
    # the kDrive credential must not be sent to it). Supports ?as=pdf|text.
    def download(file_id)
      response = @connection.get("/2/drive/#{@drive_id}/files/#{file_id}/download") do |req|
        req.headers["Authorization"] = "Bearer #{@token}"
      end
      return response.body if response.status.between?(200, 299)
      return follow_download_redirect(response.headers["location"]) if REDIRECT_STATUSES.include?(response.status)

      raise "kDrive download failed (HTTP #{response.status})"
    end

    def ping
      # search("test", limit: 1)
      true
    rescue
      false
    end

    private

    def get(path, params = {})
      response = @connection.get(path, params) do |req|
        req.headers["Authorization"] = "Bearer #{@token}"
      end

      case response.status
      when 200..299
        unwrap(JSON.parse(response.body))
      when 404
        raise "kDrive not found — check your drive id (HTTP 404)"
      when 401, 403
        raise "Invalid kDrive credentials (HTTP #{response.status})"
      else
        raise "HTTP Error #{response.status}: #{response.body}"
      end
    end

    def unwrap(body)
      return body["data"] if body.is_a?(Hash) && body["result"] == "success"

      raise "kDrive error: #{body.is_a?(Hash) ? body["error"] : body}"
    end

    def follow_download_redirect(location)
      raise "kDrive download redirected without a Location header" unless location.present?
      raise "kDrive download redirect must be https" unless location.start_with?("https://")

      current = location
      MAX_REDIRECTS.times do
        response = @connection.get(current)
        return response.body if response.status.between?(200, 299)
        break unless REDIRECT_STATUSES.include?(response.status)

        current = response.headers["location"]
        raise "kDrive download redirected without a Location header" unless current.present?
        raise "kDrive download redirect must be https" unless current.start_with?("https://")
      end
      raise "kDrive download exceeded #{MAX_REDIRECTS} redirects"
    end

    def build_default_connection
      Faraday.new(url: BASE_URL) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end
    end
  end
end
