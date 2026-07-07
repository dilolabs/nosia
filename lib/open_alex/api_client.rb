module OpenAlex
  class ApiClient
    def initialize(auth = {}, connection: nil)
      @config = OpenAlex::Configuration.new
      @auth = auth || {}
      @connection = connection || build_default_connection
    end

    def get(path, params = {})
      params[:api_key] = api_key
      fetch_with_retry(path, params)
    end

    # Lightweight authenticated request used by McpServer#test_connection!.
    def ping
      get("/works", per_page: 1)
      true
    rescue
      false
    end

    private

    def api_key
      @auth[:api_key].presence || @auth["api_key"].presence || @config.api_key
    end

    def build_default_connection
      Faraday.new(url: @config.base_url) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end
    end

    def fetch_with_retry(path, params, attempt = 0)
      response = @connection.get(path, params)

      case response.status
      when 200
        JSON.parse(response.body)
      when 429, 500..599
        if attempt < @config.max_retries
          sleep(2 ** attempt)
          fetch_with_retry(path, params, attempt + 1)
        else
          raise "Max retries exceeded: #{response.status}"
        end
      else
        raise "HTTP Error #{response.status}: #{response.body}"
      end
    end
  end
end
