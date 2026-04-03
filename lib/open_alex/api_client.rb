module OpenAlex
  class ApiClient
    def initialize(config = OpenAlex::Configuration.new)
      @config = config
      @connection = Faraday.new(url: @config.base_url) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end
    end

    def get(path, params = {})
      params[:api_key] = @config.api_key
      fetch_with_retry(path, params)
    end

    private

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