module OpenAlex
  class Configuration
    attr_accessor :api_key, :base_url, :max_retries, :timeout

    def initialize
      @api_key = ENV['OPENALEX_API_KEY']
      @base_url = 'https://api.openalex.org'
      @max_retries = 5
      @timeout = 30
    end
  end
end