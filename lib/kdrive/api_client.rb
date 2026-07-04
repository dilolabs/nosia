require "faraday"

module Kdrive
  class ApiClient
    # No global version prefix — kDrive versions each path (/2 for file metadata +
    # download, /3 for search/list). See "kDrive API findings (post-spike)" in the spec.
    BASE_URL = "https://api.infomaniak.com"

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

    # Raw bytes (may 302-redirect to storage; Faraday does not follow redirects
    # unless the follow_redirects middleware is added, so a redirect surfaces as a
    # non-2xx and the caller degrades to metadata-only). Supports ?as=pdf|text.
    def download(file_id)
      response = @connection.get("/2/drive/#{@drive_id}/files/#{file_id}/download") do |req|
        req.headers["Authorization"] = "Bearer #{@token}"
      end
      raise "kDrive download failed (HTTP #{response.status})" unless response.status.between?(200, 299)

      response.body
    end

    def ping
      list_folder(1, limit: 1)
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

    def build_default_connection
      Faraday.new(url: BASE_URL) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end
    end
  end
end
