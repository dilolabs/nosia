require "open_alex/version"
require "open_alex/configuration"
require "open_alex/engine"
require "open_alex/api_client"
require "open_alex/entities/work"
require "open_alex/entities/author"
require "open_alex/entities/source"
require "open_alex/entities/institution"
require "open_alex/entities/topic"
require "open_alex/entities/publisher"
require "open_alex/entities/funder"
require "open_alex/tool"
require "open_alex/engine_registration"

module OpenAlex
  VERSION = Version::STRING
end

module OpenAlex
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Used by tests to inject a Faraday :test-adapter connection.
    def default_connection
      @default_connection
    end

    def default_connection=(connection)
      @default_connection = connection
    end
  end
end
