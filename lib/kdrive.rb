require_relative "kdrive/api_client"
require_relative "kdrive/tool"

module Kdrive
  class << self
    # Test seam: inject a Faraday connection (e.g. a :test adapter). nil in production.
    def default_connection; @default_connection; end
    def default_connection=(connection); @default_connection = connection; end
  end
end
